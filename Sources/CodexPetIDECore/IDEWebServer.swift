import Foundation
import Network

public struct IDEWebClientState: Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case connected
        case disconnected
    }

    public let clientId: String
    public let kind: Kind

    public init(clientId: String, kind: Kind) {
        self.clientId = clientId
        self.kind = kind
    }
}

public final class IDEWebServer: @unchecked Sendable {
    public typealias Handler = @Sendable (BridgeRequest) async -> BridgeResponse
    public typealias ClientStateHandler = @Sendable (IDEWebClientState) -> Void

    public static let maximumRequestBytes = 16 * 1_024 * 1_024
    static let maximumHeaderBytes = 64 * 1_024

    private struct EventStream {
        let id: UUID
        let clientId: String
        let connection: NWConnection
    }

    private struct ReadyWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let sessionToken: String
    private let document: Data
    private let handler: Handler
    private let clientStateHandler: ClientStateHandler?
    private let queue = DispatchQueue(label: "com.local.codex-inner-ide.browser", qos: .userInitiated)
    private let lock = NSLock()
    private var listener: NWListener?
    private var origin: String?
    private var startContinuation: CheckedContinuation<URL, Error>?
    private var streams: [UUID: EventStream] = [:]
    private var readyClients = Set<String>()
    private var readyWaiters: [String: [ReadyWaiter]] = [:]

    public init(
        rendererAssets: RendererAssets,
        sessionToken: String,
        handler: @escaping Handler,
        clientStateHandler: ClientStateHandler? = nil
    ) {
        self.sessionToken = sessionToken
        document = Data(rendererAssets.document(
            bridgeScript: InjectionScripts.browserBridgeBootstrap(),
            browserMode: true
        ).utf8)
        self.handler = handler
        self.clientStateHandler = clientStateHandler
    }

    public var pageURL: URL? {
        lock.withLock {
            guard let origin else { return nil }
            return URL(string: "\(origin)/#\(sessionToken)")
        }
    }

    public func start() async throws -> URL {
        if let pageURL { return pageURL }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        lock.withLock { self.listener = listener }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            lock.withLock { startContinuation = continuation }
            listener.stateUpdateHandler = { [weak self] state in
                self?.resolveStart(state)
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        let values: ([EventStream], [CheckedContinuation<Bool, Never>]) = lock.withLock {
            listener?.cancel()
            listener = nil
            origin = nil
            let currentStreams = Array(streams.values)
            streams.removeAll()
            readyClients.removeAll()
            let waiters = readyWaiters.values.flatMap { $0 }.map(\.continuation)
            readyWaiters.removeAll()
            return (currentStreams, waiters)
        }
        for stream in values.0 {
            stream.connection.send(
                content: Data("0\r\n\r\n".utf8),
                completion: .contentProcessed { _ in stream.connection.cancel() }
            )
            clientStateHandler?(IDEWebClientState(clientId: stream.clientId, kind: .disconnected))
        }
        values.1.forEach { $0.resume(returning: false) }
    }

    public func waitUntilReady(clientId: String, timeout: Duration = .seconds(12)) async -> Bool {
        if lock.withLock({ readyClients.contains(clientId) }) { return true }
        let waiterID = UUID()
        return await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                if readyClients.contains(clientId) { return true }
                readyWaiters[clientId, default: []].append(ReadyWaiter(
                    id: waiterID,
                    continuation: continuation
                ))
                return false
            }
            if resumeImmediately {
                continuation.resume(returning: true)
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.timeoutReadyWaiter(clientId: clientId, waiterID: waiterID)
            }
        }
    }

    public func markReady(clientId: String) {
        let waiters = lock.withLock {
            readyClients.insert(clientId)
            return (readyWaiters.removeValue(forKey: clientId) ?? []).map(\.continuation)
        }
        waiters.forEach { $0.resume(returning: true) }
    }

    private func timeoutReadyWaiter(clientId: String, waiterID: UUID) {
        let waiter = lock.withLock { () -> ReadyWaiter? in
            guard var values = readyWaiters[clientId],
                  let index = values.firstIndex(where: { $0.id == waiterID })
            else { return nil }
            let removed = values.remove(at: index)
            if values.isEmpty {
                readyWaiters.removeValue(forKey: clientId)
            } else {
                readyWaiters[clientId] = values
            }
            return removed
        }
        waiter?.continuation.resume(returning: false)
    }

    public func markDisconnected(clientId: String) {
        let removed = lock.withLock {
            readyClients.remove(clientId)
            let values = streams.values.filter { $0.clientId == clientId }
            for value in values { streams.removeValue(forKey: value.id) }
            return values
        }
        removed.forEach { $0.connection.cancel() }
        clientStateHandler?(IDEWebClientState(clientId: clientId, kind: .disconnected))
    }

    public func emit(type: String, payload: JSONValue) {
        let event = JSONValue.object(["type": .string(type), "payload": payload])
        guard let encoded = try? JSONEncoder().encode(event) else { return }
        var line = encoded
        line.append(0x0a)
        let chunk = Self.chunk(line)
        let current = lock.withLock { Array(streams.values) }
        for stream in current {
            stream.connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                if error != nil { self?.removeStream(stream.id) }
            })
        }
    }

    private func resolveStart(_ state: NWListener.State) {
        let continuation = lock.withLock { () -> CheckedContinuation<URL, Error>? in
            guard let startContinuation else { return nil }
            switch state {
            case .ready:
                guard let port = listener?.port else { return nil }
                origin = "http://127.0.0.1:\(port.rawValue)"
                self.startContinuation = nil
                return startContinuation
            case .failed, .cancelled:
                self.startContinuation = nil
                return startContinuation
            default:
                return nil
            }
        }
        guard let continuation else { return }
        switch state {
        case .ready:
            guard let pageURL else {
                continuation.resume(throwing: InnerIDEError.localBridgeUnavailable("Browser server did not expose a port"))
                return
            }
            continuation.resume(returning: pageURL)
        case .failed(let error):
            continuation.resume(throwing: InnerIDEError.localBridgeUnavailable(
                "Browser server failed: \(error.localizedDescription)"
            ))
        default:
            continuation.resume(throwing: InnerIDEError.localBridgeUnavailable("Browser server stopped"))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(connection, buffer: Data())
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            var next = buffer
            if let data { next.append(data) }
            if next.count > Self.maximumRequestBytes + Self.maximumHeaderBytes {
                self.sendAndClose(connection, Self.response(status: 413, body: "Request too large"))
                return
            }
            do {
                if let request = try IDEHTTPRequest.parseIfComplete(
                    next,
                    maximumHeaderBytes: Self.maximumHeaderBytes,
                    maximumBodyBytes: Self.maximumRequestBytes
                ) {
                    self.process(request, connection: connection)
                    return
                }
            } catch let error as IDEHTTPError {
                self.sendAndClose(connection, Self.response(status: error.status, body: error.message))
                return
            } catch {
                self.sendAndClose(connection, Self.response(status: 400, body: "Bad request"))
                return
            }
            if isComplete || error != nil {
                self.sendAndClose(connection, Self.response(status: 400, body: "Incomplete request"))
                return
            }
            self.receive(connection, buffer: next)
        }
    }

    private func process(_ request: IDEHTTPRequest, connection: NWConnection) {
        let currentOrigin = lock.withLock { origin }
        guard request.isLoopbackPeer(connection.currentPath?.remoteEndpoint) else {
            sendAndClose(connection, Self.response(status: 403, body: "Forbidden"))
            return
        }
        if request.method == "GET", request.path == "/" {
            guard request.body.isEmpty else {
                sendAndClose(connection, Self.response(status: 400, body: "Bad request"))
                return
            }
            sendAndClose(connection, Self.response(
                status: 200,
                body: document,
                contentType: "text/html; charset=utf-8"
            ))
            return
        }
        guard request.path == "/api/v1/rpc" || request.path == "/api/v1/events",
              let currentOrigin,
              request.validOrigin(currentOrigin),
              request.headers["x-codex-ide-token"] == sessionToken,
              let clientId = request.headers["x-codex-ide-client"],
              Self.isValidClientID(clientId)
        else {
            sendAndClose(connection, Self.response(status: 403, body: "Forbidden"))
            return
        }

        if request.method == "GET", request.path == "/api/v1/events" {
            startEventStream(connection, clientId: clientId)
            return
        }
        guard request.method == "POST",
              request.path == "/api/v1/rpc",
              request.headers["content-type"]?.lowercased().hasPrefix("application/json") == true
        else {
            sendAndClose(connection, Self.response(status: 405, body: "Method not allowed"))
            return
        }
        Task { [handler, sessionToken] in
            let response: BridgeResponse
            do {
                let decoded = try JSONDecoder().decode(BridgeRequest.self, from: request.body)
                guard decoded.version == 1,
                      decoded.sessionToken == sessionToken,
                      decoded.clientId == clientId
                else { throw InnerIDEError.bridgeRejected("invalid Browser bridge session") }
                response = await handler(decoded)
            } catch {
                response = .failure("invalid-request", error: error)
            }
            guard let body = try? JSONEncoder().encode(response) else {
                self.sendAndClose(connection, Self.response(status: 500, body: "Encoding failed"))
                return
            }
            self.sendAndClose(connection, Self.response(
                status: 200,
                body: body,
                contentType: "application/json; charset=utf-8"
            ))
        }
    }

    private func startEventStream(_ connection: NWConnection, clientId: String) {
        let id = UUID()
        let stream = EventStream(id: id, clientId: clientId, connection: connection)
        lock.withLock { streams[id] = stream }
        let headers = [
            "HTTP/1.1 200 OK",
            "Content-Type: application/x-ndjson; charset=utf-8",
            "Transfer-Encoding: chunked",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Connection: keep-alive",
            "",
            ""
        ].joined(separator: "\r\n")
        connection.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.removeStream(id) }
            if case .cancelled = state { self?.removeStream(id) }
        }
        connection.send(
            content: Data(headers.utf8) + Self.chunk(Data("{\"type\":\"window.connected\",\"payload\":{}}\n".utf8)),
            completion: .contentProcessed { [weak self] error in
                if error != nil { self?.removeStream(id) }
            }
        )
        clientStateHandler?(IDEWebClientState(clientId: clientId, kind: .connected))
    }

    private func removeStream(_ id: UUID) {
        let removed = lock.withLock { streams.removeValue(forKey: id) }
        if let removed {
            clientStateHandler?(IDEWebClientState(clientId: removed.clientId, kind: .disconnected))
        }
    }

    private func sendAndClose(_ connection: NWConnection, _ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func isValidClientID(_ value: String) -> Bool {
        value.count >= 8 && value.count <= 128
            && value.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_")).contains($0)
            }
    }

    private static func chunk(_ data: Data) -> Data {
        var value = Data(String(data.count, radix: 16).utf8)
        value.append(Data("\r\n".utf8))
        value.append(data)
        value.append(Data("\r\n".utf8))
        return value
    }

    private static func response(
        status: Int,
        body: String,
        contentType: String = "text/plain; charset=utf-8"
    ) -> Data {
        response(status: status, body: Data(body.utf8), contentType: contentType)
    }

    private static func response(status: Int, body: Data, contentType: String) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 413: reason = "Payload Too Large"
        default: reason = "Internal Server Error"
        }
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Referrer-Policy: no-referrer",
            "Cross-Origin-Resource-Policy: same-origin",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var value = Data(headers.utf8)
        value.append(body)
        return value
    }
}

enum IDEHTTPError: Error {
    case badRequest(String)
    case tooLarge

    var status: Int {
        switch self {
        case .badRequest: 400
        case .tooLarge: 413
        }
    }

    var message: String {
        switch self {
        case .badRequest(let message): message
        case .tooLarge: "Request too large"
        }
    }
}

struct IDEHTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]
    let body: Data

    static func parseIfComplete(
        _ data: Data,
        maximumHeaderBytes: Int,
        maximumBodyBytes: Int
    ) throws -> IDEHTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else {
            if data.count > maximumHeaderBytes { throw IDEHTTPError.tooLarge }
            return nil
        }
        guard range.lowerBound <= maximumHeaderBytes,
              let head = String(data: data[..<range.lowerBound], encoding: .utf8)
        else { throw IDEHTTPError.badRequest("Invalid headers") }
        let lines = head.components(separatedBy: "\r\n")
        guard let first = lines.first else { throw IDEHTTPError.badRequest("Missing request line") }
        let requestLine = first.split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3,
              requestLine[2] == "HTTP/1.1",
              ["GET", "POST"].contains(String(requestLine[0]))
        else { throw IDEHTTPError.badRequest("Invalid request line") }
        let rawTarget = String(requestLine[1])
        guard rawTarget.first == "/",
              let components = URLComponents(string: "http://127.0.0.1\(rawTarget)"),
              let path = components.percentEncodedPath.removingPercentEncoding,
              !path.contains("\0"),
              !path.split(separator: "/").contains("..")
        else { throw IDEHTTPError.badRequest("Invalid request path") }
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else {
                throw IDEHTTPError.badRequest("Invalid header")
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, headers[name] == nil else {
                throw IDEHTTPError.badRequest("Duplicate or empty header")
            }
            headers[name] = value
        }
        let contentLength: Int
        if let value = headers["content-length"] {
            guard let parsed = Int(value), parsed >= 0 else {
                throw IDEHTTPError.badRequest("Invalid content length")
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= maximumBodyBytes else { throw IDEHTTPError.tooLarge }
        let bodyStart = range.upperBound
        let total = bodyStart + contentLength
        guard data.count >= total else { return nil }
        guard data.count == total else { throw IDEHTTPError.badRequest("Unexpected trailing bytes") }
        return IDEHTTPRequest(
            method: String(requestLine[0]),
            path: path,
            headers: headers,
            body: Data(data[bodyStart..<total])
        )
    }

    func validOrigin(_ expectedOrigin: String) -> Bool {
        if let origin = headers["origin"] { return origin == expectedOrigin }
        if let referer = headers["referer"] { return referer == "\(expectedOrigin)/" }
        guard headers["sec-fetch-site"] == "same-origin",
              let expectedHost = URL(string: expectedOrigin)?.host,
              let expectedPort = URL(string: expectedOrigin)?.port
        else { return false }
        return headers["host"] == "\(expectedHost):\(expectedPort)"
    }

    func isLoopbackPeer(_ endpoint: NWEndpoint?) -> Bool {
        guard let endpoint else { return false }
        let value = String(describing: endpoint)
        return value.contains("127.0.0.1") || value.contains("[::1]") || value.contains("::1")
    }
}

private extension NSLock {
    func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try operation()
    }
}

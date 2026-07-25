@preconcurrency import Foundation
import Darwin

public enum CDPValidation {
    public static let loopbackHosts: Set<String> = ["127.0.0.1", "localhost", "::1", "[::1]"]

    public static func validatedWebSocketURL(for target: CDPTarget, port: Int) throws -> URL {
        guard target.type == "page" else {
            throw InnerIDEError.invalidTarget("target type is \(target.type)")
        }
        guard let appURL = URL(string: target.url), appURL.scheme == "app" else {
            throw InnerIDEError.invalidTarget("renderer URL is not app://")
        }
        guard let url = URL(string: target.webSocketDebuggerUrl), url.scheme == "ws" else {
            throw InnerIDEError.invalidTarget("debugger URL is not ws://")
        }
        guard let host = url.host, loopbackHosts.contains(host) else {
            throw InnerIDEError.invalidTarget("debugger host is not loopback")
        }
        guard url.port == port else {
            throw InnerIDEError.invalidTarget("debugger port does not match the launched Codex instance")
        }
        return url
    }

    public static func isMainTarget(_ target: CDPTarget) -> Bool {
        guard target.type == "page",
              target.title.localizedCaseInsensitiveContains("Codex"),
              let url = URL(string: target.url),
              url.scheme == "app",
              url.lastPathComponent == "index.html"
        else { return false }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return true }
        return components.queryItems?
            .first(where: { $0.name == "initialRoute" })?
            .value?
            .hasPrefix("/avatar-overlay") != true
    }
}

public enum LoopbackPort {
    public static func reserve() throws -> Int {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw InnerIDEError.cdpUnavailable("unable to allocate a loopback socket")
        }
        defer { close(descriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw InnerIDEError.cdpUnavailable("unable to bind a loopback socket")
        }

        var resolved = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &resolved) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                getsockname(descriptor, socketAddress, &length)
            }
        }
        guard nameResult == 0 else {
            throw InnerIDEError.cdpUnavailable("unable to read the reserved loopback port")
        }
        return Int(in_port_t(bigEndian: resolved.sin_port))
    }
}

public enum CDPTargetDiscovery {
    public static func listTargets(port: Int) async throws -> [CDPTarget] {
        guard let url = URL(string: "http://127.0.0.1:\(port)/json/list") else {
            throw InnerIDEError.cdpUnavailable("invalid target discovery URL")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 3
        configuration.connectionProxyDictionary = [:]
        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InnerIDEError.cdpUnavailable("target discovery did not return HTTP 200")
        }
        let targets = try JSONDecoder().decode([CDPTarget].self, from: data)
        return targets.filter { target in
            (try? CDPValidation.validatedWebSocketURL(for: target, port: port)) != nil
        }
    }

    public static func waitForTargets(
        port: Int,
        timeout: TimeInterval = 15
    ) async throws -> [CDPTarget] {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                let targets = try await listTargets(port: port)
                if !targets.isEmpty { return targets }
            } catch {
                lastError = error
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw InnerIDEError.cdpUnavailable(lastError?.localizedDescription ?? "timed out")
    }

    public static func waitForTarget(
        port: Int,
        timeout: TimeInterval = 30,
        matching predicate: @escaping (CDPTarget) -> Bool
    ) async throws -> CDPTarget {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                if let target = try await listTargets(port: port).first(where: predicate) {
                    return target
                }
            } catch {
                lastError = error
            }
            try await Task.sleep(for: .milliseconds(300))
        }
        throw InnerIDEError.cdpUnavailable(
            lastError?.localizedDescription ?? "matching renderer target did not become ready"
        )
    }
}

public actor CDPSession {
    public let target: CDPTarget
    public let port: Int

    private let webSocket: URLSessionWebSocketTask
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var eventContinuations: [UUID: AsyncStream<CDPEvent>.Continuation] = [:]
    private var receiveTask: Task<Void, Never>?
    private var closed = false

    public init(target: CDPTarget, port: Int) throws {
        self.target = target
        self.port = port
        let url = try CDPValidation.validatedWebSocketURL(for: target, port: port)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        configuration.connectionProxyDictionary = [:]
        self.webSocket = URLSession(configuration: configuration).webSocketTask(with: url)
    }

    public func connect() async throws {
        guard receiveTask == nil else { return }
        webSocket.resume()
        receiveTask = Task { await receiveLoop() }
        _ = try await send(method: "Runtime.enable")
        _ = try await send(method: "Page.enable")
    }

    public func events() -> AsyncStream<CDPEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventContinuation(id) }
            }
        }
    }

    public func send(
        method: String,
        params: [String: JSONValue] = [:],
        timeout: TimeInterval = 15
    ) async throws -> JSONValue {
        guard !closed else { throw InnerIDEError.cdpUnavailable("session is closed") }
        let id = nextID
        nextID += 1
        let message = JSONValue.object([
            "id": .number(Double(id)),
            "method": .string(method),
            "params": .object(params)
        ])
        let data = try JSONEncoder().encode(message)
        guard let text = String(data: data, encoding: .utf8) else {
            throw InnerIDEError.cdpUnavailable("could not encode a CDP request")
        }

        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeoutTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await self?.expire(id: id, method: method)
            }
            Task { [weak self] in
                do {
                    try await self?.webSocket.send(.string(text))
                } catch {
                    await self?.fail(id: id, error: error)
                }
            }
        }
    }

    public func evaluate(
        _ expression: String,
        awaitPromise: Bool = true,
        userGesture: Bool = false
    ) async throws -> JSONValue {
        let response = try await send(method: "Runtime.evaluate", params: [
            "expression": .string(expression),
            "awaitPromise": .bool(awaitPromise),
            "returnByValue": .bool(true),
            "userGesture": .bool(userGesture),
            "allowUnsafeEvalBlockedByCSP": .bool(true)
        ])
        if let details = response["exceptionDetails"]?.objectValue {
            let description = details["text"]?.stringValue
                ?? details["exception"]?["description"]?.stringValue
                ?? "renderer evaluation failed"
            throw InnerIDEError.cdpUnavailable(description)
        }
        return response["result"]?["value"] ?? .null
    }

    public func close() {
        guard !closed else { return }
        closed = true
        receiveTask?.cancel()
        webSocket.cancel(with: .goingAway, reason: nil)
        let error = InnerIDEError.cdpUnavailable("session closed")
        pending.values.forEach { $0.resume(throwing: error) }
        pending.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
        eventContinuations.values.forEach { $0.finish() }
        eventContinuations.removeAll()
    }

    private func receiveLoop() async {
        while !Task.isCancelled && !closed {
            do {
                let message = try await webSocket.receive()
                let data: Data
                switch message {
                case .string(let text): data = Data(text.utf8)
                case .data(let bytes): data = bytes
                @unknown default: continue
                }
                try handle(data: data)
            } catch {
                if !closed { close() }
                return
            }
        }
    }

    private func handle(data: Data) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        guard let object = value.objectValue else { return }
        if let id = object["id"]?.intValue {
            timeoutTasks.removeValue(forKey: id)?.cancel()
            guard let continuation = pending.removeValue(forKey: id) else { return }
            if let error = object["error"]?.objectValue {
                continuation.resume(throwing: InnerIDEError.cdpUnavailable(
                    error["message"]?.stringValue ?? "CDP command failed"
                ))
            } else {
                continuation.resume(returning: object["result"] ?? .object([:]))
            }
            return
        }
        if let method = object["method"]?.stringValue {
            let event = CDPEvent(method: method, params: object["params"] ?? .object([:]))
            eventContinuations.values.forEach { $0.yield(event) }
        }
    }

    private func expire(id: Int, method: String) {
        timeoutTasks.removeValue(forKey: id)
        pending.removeValue(forKey: id)?.resume(
            throwing: InnerIDEError.cdpUnavailable("CDP command timed out: \(method)")
        )
    }

    private func fail(id: Int, error: Error) {
        timeoutTasks.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }
}

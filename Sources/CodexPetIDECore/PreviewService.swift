import Foundation
import Network

public final class PreviewService: @unchecked Sendable {
    private let workspace: WorkspaceService
    private let queue = DispatchQueue(label: "com.local.codex-inner-ide.preview", qos: .userInitiated)
    private let token = UUID().uuidString.lowercased()
    private var listener: NWListener?
    private var baseURL: URL?
    private var lastHTMLEntry: String?
    private var startContinuation: CheckedContinuation<URL, Error>?

    public init(workspace: WorkspaceService) {
        self.workspace = workspace
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        baseURL = nil
    }

    public func descriptor(
        relativePath: String,
        languageID: String,
        preferredHTMLEntry: String? = nil
    ) async throws -> PreviewDescriptor {
        switch languageID {
        case "html":
            _ = try workspace.read(relativePath: relativePath)
            lastHTMLEntry = relativePath
            return PreviewDescriptor(
                relativePath: relativePath,
                languageId: languageID,
                url: try await previewURL(relativePath: relativePath).absoluteString,
                entryRelativePath: relativePath
            )
        case "css":
            let entry = try resolveHTMLEntry(
                forCSS: relativePath,
                preferred: preferredHTMLEntry ?? lastHTMLEntry
            )
            lastHTMLEntry = entry
            return PreviewDescriptor(
                relativePath: relativePath,
                languageId: languageID,
                url: try await previewURL(relativePath: entry).absoluteString,
                entryRelativePath: entry
            )
        case "markdown":
            let file = try workspace.read(relativePath: relativePath)
            return PreviewDescriptor(
                relativePath: relativePath,
                languageId: languageID,
                content: file.content,
                entryRelativePath: relativePath
            )
        default:
            throw InnerIDEError.commandFailed("\(languageID) does not provide a preview")
        }
    }

    public func openExternal(relativePath: String, languageID: String) async throws -> PreviewDescriptor {
        let value = try await descriptor(relativePath: relativePath, languageID: languageID)
        return value
    }

    private func previewURL(relativePath: String) async throws -> URL {
        var url = try await start()
        for component in relativePath.split(separator: "/") {
            url.appendPathComponent(String(component))
        }
        return url
    }

    private func start() async throws -> URL {
        if let baseURL { return baseURL }
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        return try await withCheckedThrowingContinuation { continuation in
            startContinuation = continuation
            listener.stateUpdateHandler = { [weak self] state in
                self?.resolveStart(state: state)
            }
            listener.start(queue: queue)
        }
    }

    private func resolveStart(state: NWListener.State) {
        guard let continuation = startContinuation else { return }
        switch state {
        case .ready:
            guard let port = listener?.port,
                  let url = URL(string: "http://127.0.0.1:\(port.rawValue)/\(token)/")
            else {
                startContinuation = nil
                continuation.resume(throwing: InnerIDEError.commandFailed("Preview server did not expose a port"))
                return
            }
            startContinuation = nil
            baseURL = url
            continuation.resume(returning: url)
        case .failed(let error):
            startContinuation = nil
            continuation.resume(throwing: InnerIDEError.commandFailed("Preview server failed: \(error.localizedDescription)"))
        case .cancelled:
            startContinuation = nil
            continuation.resume(throwing: InnerIDEError.commandFailed("Preview server stopped"))
        default:
            break
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else {
                connection.cancel()
                return
            }
            let response = self.response(for: data)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: Data) -> Data {
        guard let text = String(data: request, encoding: .utf8),
              let requestLine = text.split(separator: "\n", omittingEmptySubsequences: true).first,
              requestLine.hasPrefix("GET "),
              let target = requestLine.split(separator: " ").dropFirst().first
        else { return response(status: 400, body: Data("Bad request".utf8), mimeType: "text/plain; charset=utf-8") }

        let pathOnly = String(target).split(separator: "?", maxSplits: 1).first.map(String.init) ?? ""
        let prefix = "/\(token)/"
        guard pathOnly.hasPrefix(prefix),
              let decoded = String(pathOnly.dropFirst(prefix.count)).removingPercentEncoding,
              !decoded.isEmpty,
              !decoded.contains("\0"),
              !decoded.split(separator: "/").contains("..")
        else { return response(status: 403, body: Data("Forbidden".utf8), mimeType: "text/plain; charset=utf-8") }

        var url = workspace.rootURL.appendingPathComponent(decoded).standardizedFileURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            url.appendPathComponent("index.html")
        }
        guard workspace.isContained(url),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url, options: [.mappedIfSafe])
        else { return response(status: 404, body: Data("Not found".utf8), mimeType: "text/plain; charset=utf-8") }
        return response(status: 200, body: data, mimeType: Self.mimeType(for: url.pathExtension))
    }

    private func response(status: Int, body: Data, mimeType: String) -> Data {
        let reason = status == 200 ? "OK" : status == 400 ? "Bad Request" : status == 403 ? "Forbidden" : "Not Found"
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(mimeType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "X-Content-Type-Options: nosniff",
            "Content-Security-Policy: default-src 'self' data: blob:; connect-src 'none'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; object-src 'none'; base-uri 'self'; form-action 'none'",
            "Connection: close",
            "",
            ""
        ].joined(separator: "\r\n")
        var value = Data(headers.utf8)
        value.append(body)
        return value
    }

    private func resolveHTMLEntry(forCSS relativePath: String, preferred: String?) throws -> String {
        let directory = (relativePath as NSString).deletingLastPathComponent
        let candidates = [
            preferred,
            directory.isEmpty ? "index.html" : "\(directory)/index.html",
            "index.html"
        ].compactMap { $0 }
        for candidate in candidates where candidate.lowercased().hasSuffix(".html") || candidate.lowercased().hasSuffix(".htm") {
            if (try? workspace.read(relativePath: candidate)) != nil { return candidate }
        }
        throw InnerIDEError.commandFailed("Choose or create an HTML entry file before previewing CSS")
    }

    private static func mimeType(for pathExtension: String) -> String {
        switch pathExtension.lowercased() {
        case "html", "htm": "text/html; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "js", "mjs", "cjs": "text/javascript; charset=utf-8"
        case "json": "application/json; charset=utf-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "jpg", "jpeg": "image/jpeg"
        case "gif": "image/gif"
        case "webp": "image/webp"
        case "woff": "font/woff"
        case "woff2": "font/woff2"
        default: "application/octet-stream"
        }
    }
}

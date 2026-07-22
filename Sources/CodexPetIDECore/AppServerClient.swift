@preconcurrency import Foundation

public actor AppServerClient {
    public typealias NotificationHandler = @Sendable (String, JSONValue) -> Void

    private let executableURL: URL
    private let workingDirectoryURL: URL
    private var process: Process?
    private var inputHandle: FileHandle?
    private var outputBuffer = Data()
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<JSONValue, Error>] = [:]
    private var timeoutTasks: [Int: Task<Void, Never>] = [:]
    private var notificationHandler: NotificationHandler?
    private var stopped = false

    public init(executableURL: URL, workingDirectoryURL: URL) {
        self.executableURL = executableURL
        self.workingDirectoryURL = workingDirectoryURL
    }

    public func setNotificationHandler(_ handler: NotificationHandler?) {
        notificationHandler = handler
    }

    public func start() async throws {
        guard process == nil else { return }
        stopped = false
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--stdio"]
        process.currentDirectoryURL = workingDirectoryURL
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { await self?.ingest(data) }
        }
        errors.fileHandleForReading.readabilityHandler = { handle in
            // App Server diagnostics are intentionally not forwarded to the IDE output.
            _ = handle.availableData
        }
        process.terminationHandler = { [weak self] process in
            Task { await self?.processDidExit(status: process.terminationStatus) }
        }
        try process.run()
        self.process = process
        inputHandle = input.fileHandleForWriting

        _ = try await request(method: "initialize", params: .object([
            "clientInfo": .object([
                "name": .string("codex_inner_ide"),
                "title": .string("Codex Inner IDE"),
                "version": .string("0.1.0")
            ]),
            "capabilities": .object([
                "experimentalApi": .bool(true)
            ])
        ]))
        try notify(method: "initialized", params: .object([:]))
    }

    public func request(
        method: String,
        params: JSONValue,
        timeout: TimeInterval = 300
    ) async throws -> JSONValue {
        guard process?.isRunning == true, let inputHandle, !stopped else {
            throw InnerIDEError.appServerUnavailable("process is not running")
        }
        let id = nextID
        nextID += 1
        let request = JSONValue.object([
            "id": .number(Double(id)),
            "method": .string(method),
            "params": params
        ])
        let data = try lineData(for: request)
        return try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            timeoutTasks[id] = Task { [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                await self?.expire(id: id, method: method)
            }
            do {
                try inputHandle.write(contentsOf: data)
            } catch {
                timeoutTasks.removeValue(forKey: id)?.cancel()
                pending.removeValue(forKey: id)
                continuation.resume(throwing: error)
            }
        }
    }

    public func stop() {
        guard !stopped else { return }
        stopped = true
        inputHandle?.closeFile()
        if process?.isRunning == true { process?.terminate() }
        failPending(with: InnerIDEError.appServerUnavailable("connection closed"))
        process = nil
        inputHandle = nil
    }

    private func notify(method: String, params: JSONValue) throws {
        guard let inputHandle else { throw InnerIDEError.appServerUnavailable("stdin is closed") }
        try inputHandle.write(contentsOf: lineData(for: .object([
            "method": .string(method),
            "params": params
        ])))
    }

    private func lineData(for value: JSONValue) throws -> Data {
        var data = try JSONEncoder().encode(value)
        data.append(0x0A)
        return data
    }

    private func ingest(_ data: Data) {
        outputBuffer.append(data)
        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = outputBuffer[..<newline]
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty,
                  let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line)),
                  let object = message.objectValue
            else { continue }
            if let id = object["id"]?.intValue {
                timeoutTasks.removeValue(forKey: id)?.cancel()
                guard let continuation = pending.removeValue(forKey: id) else { continue }
                if let error = object["error"]?.objectValue {
                    continuation.resume(throwing: InnerIDEError.appServerUnavailable(
                        error["message"]?.stringValue ?? "request failed"
                    ))
                } else {
                    continuation.resume(returning: object["result"] ?? .object([:]))
                }
            } else if let method = object["method"]?.stringValue {
                notificationHandler?(method, object["params"] ?? .object([:]))
            }
        }
    }

    private func expire(id: Int, method: String) {
        timeoutTasks.removeValue(forKey: id)
        pending.removeValue(forKey: id)?.resume(
            throwing: InnerIDEError.appServerUnavailable("request timed out: \(method)")
        )
    }

    private func processDidExit(status: Int32) {
        guard !stopped else { return }
        stopped = true
        failPending(with: InnerIDEError.appServerUnavailable("process exited with status \(status)"))
        process = nil
        inputHandle = nil
    }

    private func failPending(with error: Error) {
        pending.values.forEach { $0.resume(throwing: error) }
        pending.removeAll()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
    }
}

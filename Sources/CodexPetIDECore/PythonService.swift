import Foundation

public actor PythonService {
    public typealias EventHandler = @Sendable (PythonExecutionEvent) -> Void

    private let client: AppServerClient
    private let workspace: WorkspaceService
    private var interpreters: [PythonInterpreter] = []
    private var eventHandler: EventHandler?
    private var outputByRun: [String: String] = [:]
    private var streamedOutputByRun: [String: [String: String]] = [:]
    private var activeRunIDs: Set<String> = []
    private var notificationHandlerID: UUID?

    public init(client: AppServerClient, workspace: WorkspaceService) {
        self.client = client
        self.workspace = workspace
    }

    public func start() async throws {
        notificationHandlerID = await client.addNotificationHandler { [weak self] method, params in
            Task { await self?.handleNotification(method: method, params: params) }
        }
        try await client.start()
    }

    public func setEventHandler(_ handler: EventHandler?) {
        eventHandler = handler
    }

    public func discover(cachedExecutable: String? = nil) async -> [PythonInterpreter] {
        var candidates: [(URL, String)] = []
        if let cachedExecutable {
            candidates.append((URL(fileURLWithPath: cachedExecutable), "task"))
        }
        candidates.append((workspace.rootURL.appendingPathComponent(".venv/bin/python"), ".venv"))
        candidates.append((workspace.rootURL.appendingPathComponent("venv/bin/python"), "venv"))
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for name in ["python3", "python"] {
            if let path = pathDirectories
                .map({ URL(fileURLWithPath: $0).appendingPathComponent(name) })
                .first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
                candidates.append((path, "path"))
            }
        }

        var seen = Set<String>()
        var found: [PythonInterpreter] = []
        for (candidate, source) in candidates {
            let resolved = candidate.resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: resolved.path), seen.insert(resolved.path).inserted else {
                continue
            }
            let version = (try? await bufferedCommand(
                [resolved.path, "--version"],
                sandboxPolicy: readOnlyPolicy,
                timeout: 10
            ))?.combined.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Python"
            found.append(PythonInterpreter(
                id: WorkspaceService.sha256(Data(resolved.path.utf8)),
                executable: resolved.path,
                version: version,
                source: source
            ))
        }
        interpreters = found
        return found
    }

    public func createVenv() async throws -> PythonInterpreter {
        let base = interpreters.first(where: { $0.source == "path" }) ?? interpreters.first
        guard let base else { throw InnerIDEError.commandFailed("No Python interpreter is available") }
        let result = try await bufferedCommand(
            [base.executable, "-m", "venv", ".venv"],
            sandboxPolicy: workspaceWritePolicy,
            timeout: 180
        )
        guard result.exitCode == 0 else {
            throw InnerIDEError.commandFailed(result.combined)
        }
        let refreshed = await discover()
        guard let created = refreshed.first(where: { $0.source == ".venv" }) else {
            throw InnerIDEError.commandFailed(".venv was created but its interpreter was not found")
        }
        return created
    }

    public func run(relativePath: String, interpreterID: String) async throws -> String {
        let file = try workspace.read(relativePath: relativePath)
        guard !file.readonly, relativePath.hasSuffix(".py") else {
            throw InnerIDEError.commandFailed("Only editable Python files can run")
        }
        guard let interpreter = interpreters.first(where: { $0.id == interpreterID }) else {
            throw InnerIDEError.commandFailed("Selected Python interpreter is unavailable")
        }
        let runID = UUID().uuidString.lowercased()
        activeRunIDs.insert(runID)
        outputByRun[runID] = ""
        streamedOutputByRun[runID] = ["stdout": "", "stderr": ""]
        eventHandler?(PythonExecutionEvent(runId: runID, kind: "started"))
        Task { [weak self] in
            await self?.executeRun(
                runID: runID,
                command: [interpreter.executable, self?.workspace.rootURL.appendingPathComponent(relativePath).path ?? relativePath]
            )
        }
        return runID
    }

    public func checkSyntax(relativePath: String, interpreterID: String) async throws -> [Diagnostic] {
        guard let interpreter = interpreters.first(where: { $0.id == interpreterID }) else { return [] }
        let script = "import ast,pathlib,sys; p=pathlib.Path(sys.argv[1]); ast.parse(p.read_text(encoding='utf-8'), filename=sys.argv[1])"
        let result = try await bufferedCommand(
            [interpreter.executable, "-c", script, relativePath],
            sandboxPolicy: readOnlyPolicy,
            timeout: 30
        )
        return result.exitCode == 0 ? [] : parseDiagnostics(result.combined)
    }

    public func terminate(runID: String) async throws {
        guard activeRunIDs.contains(runID) else { return }
        _ = try await client.request(
            method: "command/exec/terminate",
            params: .object(["processId": .string(runID)]),
            timeout: 15
        )
    }

    public func stop() async {
        for runID in activeRunIDs {
            try? await terminate(runID: runID)
        }
        if let notificationHandlerID {
            await client.removeNotificationHandler(notificationHandlerID)
            self.notificationHandlerID = nil
        }
        await client.stop()
    }

    private func executeRun(runID: String, command: [String]) async {
        do {
            let result = try await client.request(
                method: "command/exec",
                params: .object([
                    "command": .array(command.map(JSONValue.string)),
                    "cwd": .string(workspace.rootURL.path),
                    "processId": .string(runID),
                    "streamStdoutStderr": .bool(true),
                    "streamStdin": .bool(false),
                    "tty": .bool(false),
                    "disableTimeout": .bool(true),
                    "sandboxPolicy": workspaceWritePolicy
                ]),
                timeout: 86_400
            )
            let exitCode = result["exitCode"]?.intValue ?? -1
            reconcileReturnedOutput(runID: runID, result: result)
            let diagnostics = parseDiagnostics(outputByRun[runID] ?? "")
            activeRunIDs.remove(runID)
            outputByRun.removeValue(forKey: runID)
            streamedOutputByRun.removeValue(forKey: runID)
            eventHandler?(PythonExecutionEvent(
                runId: runID,
                kind: "exited",
                exitCode: exitCode,
                diagnostics: diagnostics
            ))
        } catch {
            activeRunIDs.remove(runID)
            let text = error.localizedDescription
            outputByRun.removeValue(forKey: runID)
            streamedOutputByRun.removeValue(forKey: runID)
            eventHandler?(PythonExecutionEvent(runId: runID, kind: "failed", text: text, exitCode: -1))
        }
    }

    private func handleNotification(method: String, params: JSONValue) {
        guard method == "command/exec/outputDelta",
              let runID = params["processId"]?.stringValue,
              activeRunIDs.contains(runID),
              let encoded = params["deltaBase64"]?.stringValue,
              let data = Data(base64Encoded: encoded),
              let text = String(data: data, encoding: .utf8)
        else { return }
        let stream = params["stream"]?.stringValue ?? "stdout"
        emitOutput(runID: runID, stream: stream, text: text)
    }

    private func reconcileReturnedOutput(runID: String, result: JSONValue) {
        for stream in ["stdout", "stderr"] {
            let returned = result[stream]?.stringValue ?? ""
            let streamed = streamedOutputByRun[runID]?[stream] ?? ""
            let suffix = RuntimeOutputReconciler.unstreamedSuffix(
                returned: returned,
                streamed: streamed
            )
            emitOutput(runID: runID, stream: stream, text: suffix)
        }
    }

    private func emitOutput(runID: String, stream: String, text: String) {
        guard !text.isEmpty, activeRunIDs.contains(runID) else { return }
        outputByRun[runID, default: ""] += text
        streamedOutputByRun[runID, default: [:]][stream, default: ""] += text
        eventHandler?(PythonExecutionEvent(runId: runID, kind: "output", stream: stream, text: text))
    }

    private func bufferedCommand(
        _ command: [String],
        sandboxPolicy: JSONValue,
        timeout: TimeInterval
    ) async throws -> (exitCode: Int, combined: String) {
        let result = try await client.request(
            method: "command/exec",
            params: .object([
                "command": .array(command.map(JSONValue.string)),
                "cwd": .string(workspace.rootURL.path),
                "timeoutMs": .number(timeout * 1_000),
                "sandboxPolicy": sandboxPolicy
            ]),
            timeout: timeout + 10
        )
        return (
            result["exitCode"]?.intValue ?? -1,
            (result["stdout"]?.stringValue ?? "") + (result["stderr"]?.stringValue ?? "")
        )
    }

    private var readOnlyPolicy: JSONValue {
        .object(["type": .string("readOnly"), "networkAccess": .bool(false)])
    }

    private var workspaceWritePolicy: JSONValue {
        .object([
            "type": .string("workspaceWrite"),
            "writableRoots": .array([.string(workspace.rootURL.path)]),
            "networkAccess": .bool(false),
            "excludeSlashTmp": .bool(true),
            "excludeTmpdirEnvVar": .bool(true)
        ])
    }

    private func parseDiagnostics(_ output: String) -> [Diagnostic] {
        let pattern = #"File \"([^\"]+)\", line ([0-9]+)"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        let message = output.split(separator: "\n").last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }).map(String.init)
            ?? "Python error"
        return expression.matches(in: output, range: range).compactMap { match in
            guard let pathRange = Range(match.range(at: 1), in: output),
                  let lineRange = Range(match.range(at: 2), in: output),
                  let line = Int(output[lineRange])
            else { return nil }
            let path = String(output[pathRange])
            let fileURL = URL(fileURLWithPath: path, relativeTo: workspace.rootURL).standardizedFileURL
            guard workspace.isContained(fileURL) else { return nil }
            let relative = fileURL.path == workspace.rootURL.path
                ? ""
                : String(fileURL.path.dropFirst(workspace.rootURL.path.count + 1))
            return Diagnostic(relativePath: relative, line: line, column: 1, severity: "error", message: message)
        }
    }
}

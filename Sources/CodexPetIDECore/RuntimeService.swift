import Foundation

public actor RuntimeService {
    public typealias EventHandler = @Sendable (RuntimeExecutionEvent) -> Void

    private let client: AppServerClient
    private let workspace: WorkspaceService
    private let fileManager: FileManager
    private let cacheRoot: URL
    private var descriptors: [RuntimeDescriptor] = []
    private var eventHandler: EventHandler?
    private var notificationHandlerID: UUID?
    private var activeRunID: String?
    private var activeLanguageID: String?
    private var output = ""

    public init(
        client: AppServerClient,
        workspace: WorkspaceService,
        fileManager: FileManager = .default
    ) {
        self.client = client
        self.workspace = workspace
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        cacheRoot = support
            .appendingPathComponent("CodexInnerIDE", isDirectory: true)
            .appendingPathComponent("runtime-cache", isDirectory: true)
            .appendingPathComponent(workspace.binding.id, isDirectory: true)
    }

    public func start() async {
        notificationHandlerID = await client.addNotificationHandler { [weak self] method, params in
            Task { await self?.handleNotification(method: method, params: params) }
        }
    }

    public func stop() async {
        if let activeRunID {
            try? await terminate(runID: activeRunID)
        }
        if let notificationHandlerID {
            await client.removeNotificationHandler(notificationHandlerID)
            self.notificationHandlerID = nil
        }
    }

    public func setEventHandler(_ handler: EventHandler?) {
        eventHandler = handler
    }

    public func discover(languageID: String? = nil) async -> [RuntimeDescriptor] {
        let requested = languageID.map { Set([$0]) }
        var found: [RuntimeDescriptor] = []

        if requested == nil || requested!.contains("java") {
            found.append(contentsOf: await discoverJava())
        }
        if requested == nil || requested!.contains("javascript") {
            found.append(contentsOf: await discoverNode(languageID: "javascript"))
        }
        if requested == nil || requested!.contains("typescript") {
            found.append(contentsOf: await discoverTypeScript())
        }
        for (id, label, action) in [
            ("html", "HTML Preview", RuntimeAction.preview),
            ("css", "CSS Preview", RuntimeAction.preview),
            ("json", "JSON Validator", RuntimeAction.validate),
            ("markdown", "Markdown Preview", RuntimeAction.preview)
        ] where requested == nil || requested!.contains(id) {
            found.append(RuntimeDescriptor(
                id: "builtin-\(id)",
                languageId: id,
                label: label,
                version: "Built in",
                source: "builtin",
                action: action
            ))
        }

        descriptors.removeAll { descriptor in
            requested == nil || requested!.contains(descriptor.languageId)
        }
        descriptors.append(contentsOf: found)
        return found
    }

    public func execute(_ request: RuntimeExecuteRequest) async throws -> String {
        guard activeRunID == nil else {
            throw InnerIDEError.commandFailed("Another workspace task is already running")
        }
        let file = try workspace.read(relativePath: request.relativePath)
        guard !file.readonly else {
            throw InnerIDEError.commandFailed("Read-only files cannot run")
        }

        let runID = UUID().uuidString.lowercased()
        activeRunID = runID
        activeLanguageID = request.languageId
        output = ""
        eventHandler?(RuntimeExecutionEvent(runId: runID, languageId: request.languageId, kind: "started"))

        if request.languageId == "json" {
            do {
                _ = try JSONSerialization.jsonObject(with: Data(file.content.utf8), options: [.fragmentsAllowed])
                finish(runID: runID, languageID: request.languageId, exitCode: 0, text: "Valid JSON\n")
            } catch {
                let diagnostic = Diagnostic(
                    relativePath: request.relativePath,
                    line: 1,
                    column: 1,
                    severity: "error",
                    message: error.localizedDescription
                )
                finish(
                    runID: runID,
                    languageID: request.languageId,
                    exitCode: 1,
                    text: "\(error.localizedDescription)\n",
                    diagnostics: [diagnostic]
                )
            }
            return runID
        }

        let descriptor = try await selectedDescriptor(
            languageID: request.languageId,
            runtimeID: request.runtimeId
        )
        Task { [weak self] in
            await self?.execute(
                runID: runID,
                request: request,
                descriptor: descriptor
            )
        }
        return runID
    }

    public func check(_ request: RuntimeCheckRequest) async throws -> [Diagnostic] {
        let file = try workspace.read(relativePath: request.relativePath)
        if request.languageId == "json" {
            do {
                _ = try JSONSerialization.jsonObject(with: Data(file.content.utf8), options: [.fragmentsAllowed])
                return []
            } catch {
                return [Diagnostic(
                    relativePath: request.relativePath,
                    line: 1,
                    column: 1,
                    severity: "error",
                    message: error.localizedDescription
                )]
            }
        }
        guard ["java", "javascript", "typescript"].contains(request.languageId) else { return [] }
        let descriptor = try await selectedDescriptor(
            languageID: request.languageId,
            runtimeID: request.runtimeId
        )
        let command = try await validationCommand(
            relativePath: request.relativePath,
            languageID: request.languageId,
            descriptor: descriptor
        )
        let result = try await bufferedCommand(command, policy: workspaceWritePolicy, timeout: 90)
        return result.exitCode == 0
            ? []
            : parseDiagnostics(result.combined, languageID: request.languageId, fallbackPath: request.relativePath)
    }

    public func terminate(runID: String) async throws {
        guard activeRunID == runID else { return }
        _ = try await client.request(
            method: "command/exec/terminate",
            params: .object(["processId": .string(runID)]),
            timeout: 15
        )
    }

    private func execute(
        runID: String,
        request: RuntimeExecuteRequest,
        descriptor: RuntimeDescriptor
    ) async {
        do {
            let command: [String]
            switch request.languageId {
            case "java":
                command = try await prepareJava(
                    runID: runID,
                    relativePath: request.relativePath,
                    descriptor: descriptor
                )
            case "javascript":
                guard let executable = descriptor.executable else {
                    throw InnerIDEError.commandFailed("Selected Node.js runtime is unavailable")
                }
                command = [executable, absolutePath(request.relativePath)]
            case "typescript":
                command = try await prepareTypeScript(
                    runID: runID,
                    relativePath: request.relativePath,
                    descriptor: descriptor
                )
            default:
                throw InnerIDEError.commandFailed("\(request.languageId) does not provide a command-line runner")
            }
            let result = try await streamedCommand(runID: runID, command: command)
            let diagnostics = parseDiagnostics(
                output,
                languageID: request.languageId,
                fallbackPath: request.relativePath
            )
            finish(
                runID: runID,
                languageID: request.languageId,
                exitCode: result,
                diagnostics: diagnostics
            )
        } catch {
            finish(
                runID: runID,
                languageID: request.languageId,
                exitCode: 1,
                text: "\(error.localizedDescription)\n",
                diagnostics: parseDiagnostics(
                    error.localizedDescription,
                    languageID: request.languageId,
                    fallbackPath: request.relativePath
                )
            )
        }
    }

    private func prepareJava(
        runID: String,
        relativePath: String,
        descriptor: RuntimeDescriptor
    ) async throws -> [String] {
        guard let javac = descriptor.executable else {
            throw InnerIDEError.commandFailed("Install a JDK that includes javac to run Java files")
        }
        let runCache = try freshRunCache(runID: runID)
        let compile = try await bufferedCommand([
            javac,
            "-encoding", "UTF-8",
            "-sourcepath", workspace.rootURL.path,
            "-d", runCache.path,
            absolutePath(relativePath)
        ], policy: workspaceWritePolicy, timeout: 120)
        if !compile.combined.isEmpty { emitOutput(runID: runID, stream: "stderr", text: compile.combined) }
        guard compile.exitCode == 0 else {
            throw InnerIDEError.commandFailed(compile.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let siblingJava = URL(fileURLWithPath: javac).deletingLastPathComponent().appendingPathComponent("java").path
        let java = fileManager.isExecutableFile(atPath: siblingJava)
            ? siblingJava
            : try await executable(named: "java")
        let content = try workspace.read(relativePath: relativePath).content
        let packageName = Self.javaPackageName(content)
        let className = URL(fileURLWithPath: relativePath).deletingPathExtension().lastPathComponent
        let qualifiedName = packageName.map { "\($0).\(className)" } ?? className
        return [java, "-cp", runCache.path, qualifiedName]
    }

    private func prepareTypeScript(
        runID: String,
        relativePath: String,
        descriptor: RuntimeDescriptor
    ) async throws -> [String] {
        guard let executable = descriptor.executable else {
            throw InnerIDEError.commandFailed("Install a project-local TypeScript runner or compiler")
        }
        if descriptor.id.contains("tsx") || descriptor.id.contains("ts-node") {
            return [executable, absolutePath(relativePath)]
        }
        let runCache = try freshRunCache(runID: runID)
        var command = [
            executable,
            "--pretty", "false",
            "--target", "ES2022",
            "--module", "commonjs",
            "--moduleResolution", "node",
            "--rootDir", workspace.rootURL.path,
            "--outDir", runCache.path
        ]
        if relativePath.lowercased().hasSuffix(".tsx") {
            command.append(contentsOf: ["--jsx", "react-jsx"])
        }
        command.append(absolutePath(relativePath))
        let compile = try await bufferedCommand(command, policy: workspaceWritePolicy, timeout: 120)
        if !compile.combined.isEmpty { emitOutput(runID: runID, stream: "stderr", text: compile.combined) }
        guard compile.exitCode == 0 else {
            throw InnerIDEError.commandFailed(compile.combined.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let outputPath = runCache
            .appendingPathComponent(relativePath)
            .deletingPathExtension()
            .appendingPathExtension("js")
        let node = try await self.executable(named: "node")
        return [node, outputPath.path]
    }

    private func validationCommand(
        relativePath: String,
        languageID: String,
        descriptor: RuntimeDescriptor
    ) async throws -> [String] {
        guard let executable = descriptor.executable else {
            throw InnerIDEError.commandFailed("Selected runtime is unavailable")
        }
        switch languageID {
        case "java":
            let cache = try freshRunCache(runID: "check")
            return [
                executable,
                "-encoding", "UTF-8",
                "-sourcepath", workspace.rootURL.path,
                "-d", cache.path,
                absolutePath(relativePath)
            ]
        case "javascript":
            return [executable, "--check", absolutePath(relativePath)]
        case "typescript":
            let compiler = descriptor.id.contains("tsc")
                ? executable
                : uniqueExecutableURLs(executableCandidates(named: "tsc")).first?.path
            guard let compiler else { return [] }
            return [compiler, "--pretty", "false", "--noEmit", absolutePath(relativePath)]
        default:
            return []
        }
    }

    private func discoverJava() async -> [RuntimeDescriptor] {
        var candidates: [URL] = []
        if let javaHome = ProcessInfo.processInfo.environment["JAVA_HOME"] {
            candidates.append(URL(fileURLWithPath: javaHome).appendingPathComponent("bin/javac"))
        }
        candidates.append(workspace.rootURL.appendingPathComponent(".jdk/bin/javac"))
        candidates.append(contentsOf: executableCandidates(named: "javac"))
        for candidate in uniqueExecutableURLs(candidates) {
            guard let result = try? await bufferedCommand(
                [candidate.path, "-version"],
                policy: readOnlyPolicy,
                timeout: 10
            ), result.exitCode == 0 else { continue }
            let version = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
            return [RuntimeDescriptor(
                id: "java-\(WorkspaceService.sha256(Data(candidate.path.utf8)))",
                languageId: "java",
                label: version.isEmpty ? "Java JDK" : version,
                version: version.isEmpty ? "Java JDK" : version,
                executable: candidate.path,
                source: source(for: candidate),
                action: .run
            )]
        }
        return [RuntimeDescriptor(
            id: "java-unavailable",
            languageId: "java",
            label: "Java JDK required",
            version: "javac not found",
            source: "missing",
            action: .run,
            available: false,
            unavailableReason: "Install a JDK that includes javac"
        )]
    }

    private func discoverNode(languageID: String) async -> [RuntimeDescriptor] {
        for candidate in uniqueExecutableURLs(executableCandidates(named: "node")) {
            guard let result = try? await bufferedCommand(
                [candidate.path, "--version"],
                policy: readOnlyPolicy,
                timeout: 10
            ), result.exitCode == 0 else { continue }
            let version = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
            return [RuntimeDescriptor(
                id: "node-\(WorkspaceService.sha256(Data(candidate.path.utf8)))",
                languageId: languageID,
                label: "Node.js \(version)",
                version: version,
                executable: candidate.path,
                source: source(for: candidate),
                action: .run
            )]
        }
        return [RuntimeDescriptor(
            id: "node-unavailable",
            languageId: languageID,
            label: "Node.js required",
            version: "node not found",
            source: "missing",
            action: .run,
            available: false,
            unavailableReason: "Install Node.js or add it to PATH"
        )]
    }

    private func discoverTypeScript() async -> [RuntimeDescriptor] {
        for name in ["tsx", "ts-node", "tsc"] {
            for candidate in uniqueExecutableURLs(executableCandidates(named: name)) {
                let versionArguments = name == "tsc" ? ["--version"] : ["--version"]
                guard let result = try? await bufferedCommand(
                    [candidate.path] + versionArguments,
                    policy: readOnlyPolicy,
                    timeout: 10
                ), result.exitCode == 0 else { continue }
                let version = result.combined.trimmingCharacters(in: .whitespacesAndNewlines)
                return [RuntimeDescriptor(
                    id: "typescript-\(name)-\(WorkspaceService.sha256(Data(candidate.path.utf8)))",
                    languageId: "typescript",
                    label: "\(name) \(version)",
                    version: version,
                    executable: candidate.path,
                    source: source(for: candidate),
                    action: .run
                )]
            }
        }
        return [RuntimeDescriptor(
            id: "typescript-unavailable",
            languageId: "typescript",
            label: "TypeScript toolchain required",
            version: "tsx, ts-node, or tsc not found",
            source: "missing",
            action: .run,
            available: false,
            unavailableReason: "Install a project-local tsx, ts-node, or TypeScript compiler"
        )]
    }

    private func selectedDescriptor(languageID: String, runtimeID: String?) async throws -> RuntimeDescriptor {
        var candidates = descriptors.filter { $0.languageId == languageID }
        if candidates.isEmpty { candidates = await discover(languageID: languageID) }
        let selected = runtimeID.flatMap { id in candidates.first(where: { $0.id == id }) }
            ?? candidates.first(where: \.available)
        guard let selected, selected.available else {
            let reason = candidates.first?.unavailableReason ?? "No runtime is available for \(languageID)"
            throw InnerIDEError.commandFailed(reason)
        }
        return selected
    }

    private func streamedCommand(runID: String, command: [String]) async throws -> Int {
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
        return result["exitCode"]?.intValue ?? -1
    }

    private func bufferedCommand(
        _ command: [String],
        policy: JSONValue,
        timeout: TimeInterval
    ) async throws -> (exitCode: Int, combined: String) {
        if command.isEmpty { return (0, "") }
        let result = try await client.request(
            method: "command/exec",
            params: .object([
                "command": .array(command.map(JSONValue.string)),
                "cwd": .string(workspace.rootURL.path),
                "timeoutMs": .number(timeout * 1_000),
                "sandboxPolicy": policy
            ]),
            timeout: timeout + 10
        )
        return (
            result["exitCode"]?.intValue ?? -1,
            (result["stdout"]?.stringValue ?? "") + (result["stderr"]?.stringValue ?? "")
        )
    }

    private func handleNotification(method: String, params: JSONValue) {
        guard method == "command/exec/outputDelta",
              let runID = params["processId"]?.stringValue,
              runID == activeRunID,
              let languageID = activeLanguageID,
              let encoded = params["deltaBase64"]?.stringValue,
              let data = Data(base64Encoded: encoded),
              let text = String(data: data, encoding: .utf8)
        else { return }
        let stream = params["stream"]?.stringValue ?? "stdout"
        output += text
        eventHandler?(RuntimeExecutionEvent(
            runId: runID,
            languageId: languageID,
            kind: "output",
            stream: stream,
            text: text
        ))
    }

    private func emitOutput(runID: String, stream: String, text: String) {
        guard !text.isEmpty, let languageID = activeLanguageID else { return }
        output += text
        eventHandler?(RuntimeExecutionEvent(
            runId: runID,
            languageId: languageID,
            kind: "output",
            stream: stream,
            text: text
        ))
    }

    private func finish(
        runID: String,
        languageID: String,
        exitCode: Int,
        text: String? = nil,
        diagnostics: [Diagnostic] = []
    ) {
        if let text { emitOutput(runID: runID, stream: exitCode == 0 ? "stdout" : "stderr", text: text) }
        guard activeRunID == runID else { return }
        eventHandler?(RuntimeExecutionEvent(
            runId: runID,
            languageId: languageID,
            kind: exitCode == 0 ? "exited" : "failed",
            exitCode: exitCode,
            diagnostics: diagnostics
        ))
        activeRunID = nil
        activeLanguageID = nil
        output = ""
    }

    private func freshRunCache(runID: String) throws -> URL {
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        let target = cacheRoot.appendingPathComponent(runID, isDirectory: true)
        if fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    private func absolutePath(_ relativePath: String) -> String {
        workspace.rootURL.appendingPathComponent(relativePath).standardizedFileURL.path
    }

    private func executable(named name: String) async throws -> String {
        guard let url = uniqueExecutableURLs(executableCandidates(named: name)).first else {
            throw InnerIDEError.commandFailed("\(name) is not available")
        }
        return url.path
    }

    private func executableCandidates(named name: String) -> [URL] {
        var directories = [
            workspace.rootURL.appendingPathComponent("node_modules/.bin", isDirectory: true),
            fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin", isDirectory: true),
            URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
            URL(fileURLWithPath: "/usr/bin", isDirectory: true)
        ]
        directories.append(contentsOf: (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true) })
        return directories.map { $0.appendingPathComponent(name) }
    }

    private func uniqueExecutableURLs(_ values: [URL]) -> [URL] {
        var seen = Set<String>()
        return values.compactMap { value in
            let resolved = value.resolvingSymlinksInPath()
            guard fileManager.isExecutableFile(atPath: resolved.path), seen.insert(resolved.path).inserted else {
                return nil
            }
            return resolved
        }
    }

    private func source(for executable: URL) -> String {
        executable.path.hasPrefix(workspace.rootURL.path + "/") ? "project" : "path"
    }

    private var readOnlyPolicy: JSONValue {
        .object(["type": .string("readOnly"), "networkAccess": .bool(false)])
    }

    private var workspaceWritePolicy: JSONValue {
        .object([
            "type": .string("workspaceWrite"),
            "writableRoots": .array([
                .string(workspace.rootURL.path),
                .string(cacheRoot.path)
            ]),
            "networkAccess": .bool(false),
            "excludeSlashTmp": .bool(true),
            "excludeTmpdirEnvVar": .bool(true)
        ])
    }

    public static func javaPackageName(_ source: String) -> String? {
        let pattern = #"(?m)^\s*package\s+([A-Za-z_][A-Za-z0-9_.]*)\s*;"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
              ),
              let range = Range(match.range(at: 1), in: source)
        else { return nil }
        return String(source[range])
    }

    public func parseDiagnostics(
        _ text: String,
        languageID: String,
        fallbackPath: String
    ) -> [Diagnostic] {
        let patterns: [(String, Int, Int, Int?, Int, Int?)]
        switch languageID {
        case "java":
            patterns = [(#"(?m)^(.+\.java):(\d+):\s+(error|warning):\s+(.+)$"#, 1, 2, nil, 4, 3)]
        case "typescript":
            patterns = [(#"(?m)^(.+)\((\d+),(\d+)\):\s+(error|warning)\s+TS\d+:\s+(.+)$"#, 1, 2, 3, 5, 4)]
        case "javascript":
            patterns = [(#"(?m)^(.+\.(?:js|jsx|mjs|cjs)):(\d+)\s*$"#, 1, 2, nil, 0, nil)]
        default:
            patterns = []
        }
        var values: [Diagnostic] = []
        for (pattern, pathIndex, lineIndex, columnIndex, messageIndex, severityIndex) in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = expression.matches(
                in: text,
                range: NSRange(text.startIndex..<text.endIndex, in: text)
            )
            for match in matches {
                guard let pathRange = Range(match.range(at: pathIndex), in: text),
                      let lineRange = Range(match.range(at: lineIndex), in: text),
                      let line = Int(text[lineRange])
                else { continue }
                let rawPath = String(text[pathRange])
                let fileURL = URL(fileURLWithPath: rawPath, relativeTo: workspace.rootURL).standardizedFileURL
                let relativePath = workspace.isContained(fileURL)
                    ? String(fileURL.path.dropFirst(min(fileURL.path.count, workspace.rootURL.path.count + 1)))
                    : fallbackPath
                let column: Int
                if let columnIndex,
                   let range = Range(match.range(at: columnIndex), in: text),
                   let parsed = Int(text[range]) {
                    column = parsed
                } else {
                    column = 1
                }
                let message: String
                if messageIndex > 0, let range = Range(match.range(at: messageIndex), in: text) {
                    message = String(text[range])
                } else {
                    message = "\(languageID.capitalized) error"
                }
                values.append(Diagnostic(
                    relativePath: relativePath,
                    line: line,
                    column: column,
                    severity: severityIndex.flatMap { index in
                        Range(match.range(at: index), in: text).map { String(text[$0]) }
                    } ?? "error",
                    message: message
                ))
            }
        }
        if values.isEmpty, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [Diagnostic(
                relativePath: fallbackPath,
                line: 1,
                column: 1,
                severity: "error",
                message: text.split(separator: "\n").last.map(String.init) ?? "Runtime error"
            )]
        }
        return values
    }
}

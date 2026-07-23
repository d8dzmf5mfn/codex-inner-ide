import AppKit
import CodexPetIDECore
import Foundation

@MainActor
final class ControllerCoordinator: IDEWindowControllerDelegate {
    private let launcher = CodexLauncher()
    private let workspaceStateStore = WorkspaceStateStore()
    private let sessionToken = UUID().uuidString.lowercased()
    private lazy var quickChatHandoffController = QuickChatHandoffController(launcher: launcher)
    private var installation: CodexInstallation?
    private var compatibilityProfile: CompatibilityProfile?
    private var port: Int?
    private var mainTargetID: String?
    private var mainSession: CDPSession?
    private var mainEventsTask: Task<Void, Never>?

    private var ideWindowController: IDEWindowController?
    private var rendererAssets: RendererAssets?
    private var workspace: WorkspaceService?
    private var watcher: WorkspaceWatcher?
    private var appServerClient: AppServerClient?
    private var pythonService: PythonService?
    private var runtimeService: RuntimeService?
    private var previewService: PreviewService?
    private var pythonEditService: PythonEditService?
    private var pythonUnavailableReason: String?
    private var localBridgeServer: LocalBridgeServer?

    private var dirty = false
    private var activeRuntimeRunID: String?
    private var activeTaskKey = ""
    private var boundTaskKey = ""
    private var recentIDEChanges: [String: Date] = [:]

    func startLocalBridge() {
        guard localBridgeServer == nil else { return }
        let server = LocalBridgeServer(sessionToken: sessionToken) { [weak self] request in
            guard let self else {
                return BridgeResponse.failure(
                    request.requestId,
                    error: InnerIDEError.localBridgeUnavailable("controller stopped")
                )
            }
            return await self.handleLocalBridge(request)
        }
        do {
            try server.start()
            localBridgeServer = server
        } catch {
            presentMessage("Codex Inner Edit unavailable", detail: error.localizedDescription)
        }
    }

    func openIDE() async {
        var integrationError: Error?
        do {
            try await ensureConnected()
        } catch {
            integrationError = error
            if installation == nil { installation = try? CodexInstallation.detect() }
        }

        do {
            try await openIDEWindow(taskKey: activeTaskKey)
            if let integrationError {
                presentMessage(
                    "Codex integration unavailable",
                    detail: "The IDE is open, but the Sidepanel and chat handoff are disabled.\n\n\(integrationError.localizedDescription)"
                )
            }
        } catch {
            present(error)
        }
    }

    func chooseWorkspace() async {
        let panel = NSOpenPanel()
        panel.title = "Choose the Codex Inner IDE workspace"
        panel.prompt = "Use Workspace"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            if ideWindowController != nil {
                guard await closeIDE(requireDirtyConfirmation: true) else { return }
            }
            try bindWorkspace(url, taskKey: activeTaskKey)
            try await openIDEWindow(taskKey: activeTaskKey)
        } catch {
            present(error)
        }
    }

    func prepareForTermination() async -> Bool {
        guard await closeIDE(requireDirtyConfirmation: true) else { return false }
        localBridgeServer?.stop()
        localBridgeServer = nil
        mainEventsTask?.cancel()
        mainEventsTask = nil
        if let mainSession { await mainSession.close() }
        mainSession = nil
        mainTargetID = nil
        return true
    }

    private func handleLocalBridge(_ request: BridgeRequest) async -> BridgeResponse {
        do {
            guard request.version == 1, request.sessionToken == sessionToken else {
                throw InnerIDEError.bridgeRejected("invalid local bridge session")
            }
            return .success(request.requestId, data: try await routeLocalBridge(request))
        } catch {
            return .failure(request.requestId, error: error)
        }
    }

    private func routeLocalBridge(_ request: BridgeRequest) async throws -> JSONValue {
        switch request.method {
        case "mcp.status":
            guard let controller = ideWindowController,
                  let context = await controller.requestActiveEditContext(
                    instruction: "status",
                    scope: .auto
                  )
            else {
                return .object([
                    "connected": .bool(true),
                    "ideOpen": .bool(ideWindowController != nil)
                ])
            }
            var result: [String: JSONValue] = [
                "connected": .bool(true),
                "ideOpen": .bool(true),
                "workspaceId": .string(context.workspaceId),
                "relativePath": .string(context.relativePath),
                "language": .string("python"),
                "selectionAvailable": .bool(context.range != nil)
            ]
            if let proposal = await pythonEditService?.currentProposal() {
                result["proposalId"] = .string(proposal.proposalId)
                result["proposalState"] = .string(proposal.state.rawValue)
            }
            return .object(result)
        case "mcp.propose":
            guard let instruction = request.params["instruction"]?.stringValue,
                  let scope = PythonEditScope(rawValue: request.params["scope"]?.stringValue ?? "auto")
            else { throw InnerIDEError.proposalInvalid("instruction or scope is missing") }
            if installation == nil { installation = try? CodexInstallation.detect() }
            if ideWindowController == nil {
                try await openIDEWindow(taskKey: activeTaskKey)
            }
            guard let controller = ideWindowController,
                  let context = await waitForActiveEditContext(
                    controller: controller,
                    instruction: instruction,
                    scope: scope
                  ),
                  let pythonEditService
            else {
                throw InnerIDEError.proposalInvalid("open an editable Python file in Codex Inner IDE")
            }
            return try .fromEncodable(try await pythonEditService.request(context))
        case "mcp.cancel":
            guard let proposalID = request.params["proposalId"]?.stringValue,
                  let pythonEditService
            else { throw InnerIDEError.proposalInvalid("proposal id is missing") }
            return .object([
                "cancelled": .bool(await pythonEditService.cancel(proposalID: proposalID))
            ])
        default:
            throw InnerIDEError.bridgeRejected("unknown local method: \(request.method)")
        }
    }

    private func waitForActiveEditContext(
        controller: IDEWindowController,
        instruction: String,
        scope: PythonEditScope,
        timeout: Duration = .seconds(15)
    ) async -> ActivePythonEditContext? {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            if let context = await controller.requestActiveEditContext(
                instruction: instruction,
                scope: scope
            ) {
                return context
            }
            try? await Task.sleep(for: .milliseconds(150))
        } while clock.now < deadline && !Task.isCancelled
        return nil
    }

    func ideWindowController(
        _ controller: IDEWindowController,
        handle request: BridgeRequest
    ) async -> BridgeResponse {
        do {
            guard controller === ideWindowController,
                  request.version == 1,
                  request.sessionToken == sessionToken
            else {
                throw InnerIDEError.bridgeRejected("invalid session")
            }
            return .success(request.requestId, data: try await route(request))
        } catch {
            return .failure(request.requestId, error: error)
        }
    }

    func ideWindowControllerShouldClose(_ controller: IDEWindowController) async -> Bool {
        guard controller === ideWindowController else { return true }
        guard await confirmIDEClosure(controller) else { return false }
        await stopIDERuntime()
        ideWindowController = nil
        dirty = false
        return true
    }

    @discardableResult
    private func closeIDE(requireDirtyConfirmation: Bool) async -> Bool {
        guard let controller = ideWindowController else {
            await stopIDERuntime()
            return true
        }
        if requireDirtyConfirmation {
            guard await confirmIDEClosure(controller) else { return false }
        }
        await stopIDERuntime()
        ideWindowController = nil
        dirty = false
        controller.closeImmediately()
        return true
    }

    private func confirmIDEClosure(_ controller: IDEWindowController) async -> Bool {
        guard dirty else { return true }
        let alert = NSAlert()
        alert.messageText = "The IDE has unsaved files."
        alert.informativeText = "Save all files, discard the editor changes, or cancel."
        alert.addButton(withTitle: "Save All")
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            let saved = await controller.requestSaveAll()
            if saved { dirty = false }
            return saved
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    private func openIDEWindow(taskKey: String) async throws {
        if let controller = ideWindowController {
            if !taskKey.isEmpty, taskKey != boundTaskKey {
                guard await closeIDE(requireDirtyConfirmation: true) else { return }
                workspace = nil
            } else {
                controller.present()
                return
            }
        }

        if workspace == nil { try await resolveWorkspace(taskKey: taskKey) }
        guard let workspace else { throw InnerIDEError.workspaceUnavailable }

        if rendererAssets == nil {
            guard let resources = Bundle.main.resourceURL else {
                throw InnerIDEError.rendererAssetsMissing
            }
            rendererAssets = try RendererAssets.load(from: resources)
        }
        guard let rendererAssets else { throw InnerIDEError.rendererAssetsMissing }

        await startPythonRuntime(workspace)
        let controller = IDEWindowController(
            rendererAssets: rendererAssets,
            sessionToken: sessionToken,
            workspaceID: workspace.binding.id
        )
        controller.delegate = self
        ideWindowController = controller
        boundTaskKey = taskKey
        try startWatcher(workspace)
        controller.present()
    }

    private func startPythonRuntime(_ workspace: WorkspaceService) async {
        pythonUnavailableReason = nil
        previewService = PreviewService(workspace: workspace)
        guard let installation else {
            pythonUnavailableReason = "Codex Desktop is unavailable, so Python execution is disabled."
            return
        }
        let client = AppServerClient(
            executableURL: installation.codexURL,
            workingDirectoryURL: workspace.rootURL
        )
        let python = PythonService(client: client, workspace: workspace)
        let runtime = RuntimeService(client: client, workspace: workspace)
        let edits = PythonEditService(client: client, workspace: workspace)
        await python.setEventHandler { [weak self] event in
            Task { await self?.handlePythonRuntimeEvent(event) }
        }
        await runtime.setEventHandler { [weak self] event in
            Task { await self?.handleRuntimeEvent(event) }
        }
        await edits.setEventHandler { [weak self] event in
            Task { await self?.emit(type: "edits.event", payload: try? .fromEncodable(event)) }
        }
        do {
            try await python.start()
            await runtime.start()
            await edits.start()
            appServerClient = client
            pythonService = python
            runtimeService = runtime
            pythonEditService = edits
        } catch {
            pythonUnavailableReason = error.localizedDescription
            await python.stop()
        }
    }

    private func stopIDERuntime() async {
        watcher?.stop()
        watcher = nil
        if let pythonEditService { await pythonEditService.stop() }
        pythonEditService = nil
        if let runtimeService { await runtimeService.stop() }
        runtimeService = nil
        if let pythonService { await pythonService.stop() }
        pythonService = nil
        previewService?.stop()
        previewService = nil
        activeRuntimeRunID = nil
        appServerClient = nil
        pythonUnavailableReason = nil
        recentIDEChanges.removeAll()
    }

    private func ensureConnected(forChatHandoff: Bool = false) async throws {
        if mainSession != nil { return }
        let installation = try CodexInstallation.detect()
        self.installation = installation
        let compatibilityProfile = try installation.validateCompatibility()
        self.compatibilityProfile = compatibilityProfile

        if !launcher.runningApplications.isEmpty {
            let alert = NSAlert()
            if forChatHandoff {
                alert.messageText = "Quick Chat needs Codex local integration."
                alert.informativeText = "Codex is currently running without the local connection required to open and fill Quick Chat. Save active work, then relaunch Codex. Nothing will be sent automatically."
                alert.addButton(withTitle: "Quit and Relaunch Codex")
                alert.addButton(withTitle: "Copy Context Instead")
            } else {
                alert.messageText = "Codex must relaunch with local debugging enabled."
                alert.informativeText = "Save active work, then choose Quit and Relaunch. The IDE never terminates Codex without confirmation."
                alert.addButton(withTitle: "Quit and Relaunch")
                alert.addButton(withTitle: "Open IDE Only")
            }
            guard alert.runModal() == .alertFirstButtonReturn else {
                throw InnerIDEError.cdpUnavailable("Codex relaunch was skipped")
            }
            guard await launcher.terminateRunningApplications() else {
                throw InnerIDEError.cdpUnavailable("Codex did not quit cleanly")
            }
        }

        let port = try LoopbackPort.reserve()
        try await launcher.launch(installation, port: port)
        self.port = port
        let mainTarget = try await CDPTargetDiscovery.waitForTarget(
            port: port,
            timeout: 30,
            matching: CDPValidation.isMainTarget
        )
        let session = try CDPSession(target: mainTarget, port: port)
        try await session.connect()
        do {
            try await waitForMainRendererShell(session)
            _ = try await session.send(method: "Runtime.addBinding", params: [
                "name": .string(InjectionScripts.mainBindingName)
            ])
        } catch {
            await session.close()
            throw error
        }

        mainSession = session
        mainTargetID = mainTarget.id
        observeMainEvents(session)
        _ = try await injectMainEntry()
    }

    private func injectMainEntry() async throws -> Bool {
        guard compatibilityProfile != nil,
              let mainSession
        else { throw InnerIDEError.cdpUnavailable("main renderer integration is disabled") }
        return try await mainSession.evaluate(
            InjectionScripts.sidePanelEntry(sessionToken: sessionToken)
        ).boolValue == true
    }

    private func observeMainEvents(_ session: CDPSession) {
        mainEventsTask?.cancel()
        mainEventsTask = Task { [weak self] in
            let events = await session.events()
            for await event in events {
                guard !Task.isCancelled else { break }
                if event.method == "Runtime.bindingCalled",
                   event.params["name"]?.stringValue == InjectionScripts.mainBindingName,
                   let payload = event.params["payload"]?.stringValue {
                    await self?.handleMainBinding(payload)
                } else if event.method == "Page.loadEventFired" {
                    _ = try? await self?.injectMainEntry()
                }
            }
        }
    }

    private func handleMainBinding(_ payload: String) async {
        guard let data = payload.data(using: .utf8),
              let request = try? JSONDecoder().decode(BridgeRequest.self, from: data),
              request.version == 1,
              request.sessionToken == sessionToken,
              request.method == "window.openIde"
        else { return }
        activeTaskKey = request.params["taskKey"]?.stringValue ?? ""
        do {
            try await openIDEWindow(taskKey: activeTaskKey)
        } catch {
            present(error)
        }
    }

    private func route(_ request: BridgeRequest) async throws -> JSONValue {
        guard let workspace else { throw InnerIDEError.workspaceUnavailable }
        switch request.method {
        case "workspace.current":
            return try .fromEncodable(workspace.binding)
        case "workspace.choose":
            await chooseWorkspace()
            guard let current = self.workspace else { throw InnerIDEError.workspaceUnavailable }
            return try .fromEncodable(current.binding)
        case "files.list":
            return try .fromEncodable(workspace.list(
                relativePath: request.params["relativePath"]?.stringValue ?? ""
            ))
        case "files.read":
            return try .fromEncodable(workspace.read(relativePath: try relativePath(request.params)))
        case "files.write":
            let write = try request.params.decode(WriteFileRequest.self)
            recentIDEChanges[write.relativePath] = Date()
            return try .fromEncodable(workspace.write(write))
        case "files.create":
            let path = try relativePath(request.params)
            guard let kind = FileKind(rawValue: request.params["kind"]?.stringValue ?? "") else {
                throw InnerIDEError.bridgeRejected("invalid file kind")
            }
            recentIDEChanges[path] = Date()
            return try .fromEncodable(workspace.create(relativePath: path, kind: kind))
        case "files.rename":
            guard let from = request.params["from"]?.stringValue,
                  let to = request.params["to"]?.stringValue
            else { throw InnerIDEError.bridgeRejected("rename paths are required") }
            recentIDEChanges[from] = Date()
            recentIDEChanges[to] = Date()
            return try .fromEncodable(workspace.rename(from: from, to: to))
        case "files.trash":
            let path = try relativePath(request.params)
            recentIDEChanges[path] = Date()
            try workspace.moveToTrash(relativePath: path)
            return .object([:])
        case "python.discover":
            guard let pythonService else {
                throw InnerIDEError.appServerUnavailable(
                    pythonUnavailableReason ?? "Python service is not ready"
                )
            }
            return try .fromEncodable(await pythonService.discover())
        case "python.createVenv":
            guard confirmVenvCreation(), let pythonService else {
                throw InnerIDEError.commandFailed(
                    pythonUnavailableReason ?? ".venv creation cancelled"
                )
            }
            return try .fromEncodable(try await pythonService.createVenv())
        case "python.run":
            guard let pythonService,
                  let path = request.params["relativePath"]?.stringValue,
                  let interpreter = request.params["interpreterId"]?.stringValue
            else { throw InnerIDEError.bridgeRejected("run parameters are missing") }
            try reserveRuntimeTask()
            do {
                let runID = try await pythonService.run(
                    relativePath: path,
                    interpreterID: interpreter
                )
                adoptRuntimeRunID(runID)
                return .object(["runId": .string(runID)])
            } catch {
                clearRuntimeReservation()
                throw error
            }
        case "python.checkSyntax":
            guard let pythonService,
                  let path = request.params["relativePath"]?.stringValue,
                  let interpreter = request.params["interpreterId"]?.stringValue
            else { throw InnerIDEError.bridgeRejected("syntax parameters are missing") }
            return try .fromEncodable(try await pythonService.checkSyntax(
                relativePath: path,
                interpreterID: interpreter
            ))
        case "python.terminate":
            guard let pythonService,
                  let runID = request.params["runId"]?.stringValue
            else { throw InnerIDEError.bridgeRejected("run id is missing") }
            try await pythonService.terminate(runID: runID)
            return .object([:])
        case "runtime.discover":
            guard let languageID = request.params["languageId"]?.stringValue else {
                throw InnerIDEError.bridgeRejected("runtime language is missing")
            }
            if languageID == "python" {
                guard let pythonService else {
                    return try .fromEncodable([RuntimeDescriptor(
                        id: "python-unavailable",
                        languageId: "python",
                        label: "Python unavailable",
                        version: "Interpreter discovery is unavailable",
                        source: "missing",
                        action: .run,
                        available: false,
                        unavailableReason: pythonUnavailableReason ?? "Python service is not ready"
                    )])
                }
                let interpreters = await pythonService.discover()
                return try .fromEncodable(interpreters.map { interpreter in
                    RuntimeDescriptor(
                        id: interpreter.id,
                        languageId: "python",
                        label: interpreter.version,
                        version: interpreter.version,
                        executable: interpreter.executable,
                        source: interpreter.source,
                        action: .run
                    )
                })
            }
            if let runtimeService {
                return try .fromEncodable(await runtimeService.discover(languageID: languageID))
            }
            return try .fromEncodable(Self.builtinRuntimeDescriptors(languageID: languageID))
        case "runtime.execute":
            let value = try request.params.decode(RuntimeExecuteRequest.self)
            try reserveRuntimeTask()
            if value.languageId == "python" {
                guard let pythonService, let runtimeID = value.runtimeId else {
                    clearRuntimeReservation()
                    throw InnerIDEError.commandFailed(
                        pythonUnavailableReason ?? "Select an available Python interpreter"
                    )
                }
                do {
                    let runID = try await pythonService.run(
                        relativePath: value.relativePath,
                        interpreterID: runtimeID
                    )
                    adoptRuntimeRunID(runID)
                    return .object(["runId": .string(runID)])
                } catch {
                    clearRuntimeReservation()
                    throw error
                }
            }
            guard let runtimeService else {
                clearRuntimeReservation()
                throw InnerIDEError.appServerUnavailable("Language runtime service is not ready")
            }
            do {
                let runID = try await runtimeService.execute(value)
                adoptRuntimeRunID(runID)
                return .object(["runId": .string(runID)])
            } catch {
                clearRuntimeReservation()
                throw error
            }
        case "runtime.check":
            let value = try request.params.decode(RuntimeCheckRequest.self)
            if value.languageId == "python" {
                guard let pythonService, let runtimeID = value.runtimeId else { return .array([]) }
                return try .fromEncodable(try await pythonService.checkSyntax(
                    relativePath: value.relativePath,
                    interpreterID: runtimeID
                ))
            }
            guard let runtimeService else { return .array([]) }
            return try .fromEncodable(try await runtimeService.check(value))
        case "runtime.terminate":
            guard let runID = request.params["runId"]?.stringValue else {
                throw InnerIDEError.bridgeRejected("run id is missing")
            }
            try? await pythonService?.terminate(runID: runID)
            try? await runtimeService?.terminate(runID: runID)
            return .object([:])
        case "preview.open":
            guard let previewService,
                  let relativePath = request.params["relativePath"]?.stringValue,
                  let languageID = request.params["languageId"]?.stringValue
            else { throw InnerIDEError.bridgeRejected("preview parameters are missing") }
            return try .fromEncodable(try await previewService.descriptor(
                relativePath: relativePath,
                languageID: languageID,
                preferredHTMLEntry: request.params["htmlEntryRelativePath"]?.stringValue
            ))
        case "preview.openExternal":
            guard let previewService,
                  let relativePath = request.params["relativePath"]?.stringValue,
                  let languageID = request.params["languageId"]?.stringValue
            else { throw InnerIDEError.bridgeRejected("preview parameters are missing") }
            let value = try await previewService.descriptor(
                relativePath: relativePath,
                languageID: languageID,
                preferredHTMLEntry: request.params["htmlEntryRelativePath"]?.stringValue
            )
            guard let urlText = value.url, let url = URL(string: urlText) else {
                throw InnerIDEError.commandFailed("This preview cannot open in a browser")
            }
            NSWorkspace.shared.open(url)
            return try .fromEncodable(value)
        case "chatgpt.moreDetails":
            let context = try request.params.decode(IdeSelectionContext.self)
            let prompt = try SelectionPrompt.renderForChatGPT(context)
            return try .fromEncodable(await openMoreDetails(prompt))
        case "edits.request":
            guard let pythonEditService else {
                throw InnerIDEError.appServerUnavailable(
                    pythonUnavailableReason ?? "Codex edit service is not ready"
                )
            }
            let edit = try request.params.decode(PythonEditRequest.self)
            guard edit.instruction == edit.context.instruction,
                  edit.scope == edit.context.scope
            else { throw InnerIDEError.bridgeRejected("edit request context does not match") }
            return try .fromEncodable(try await pythonEditService.request(edit.context))
        case "edits.cancel":
            guard let pythonEditService,
                  let proposalID = request.params["proposalId"]?.stringValue
            else { throw InnerIDEError.bridgeRejected("proposal id is missing") }
            return .object([
                "cancelled": .bool(await pythonEditService.cancel(proposalID: proposalID))
            ])
        case "edits.decide":
            guard let pythonEditService else {
                throw InnerIDEError.appServerUnavailable("Codex edit service is not ready")
            }
            try await pythonEditService.decide(request.params.decode(PythonEditDecision.self))
            return .object([:])
        case "window.setDirty":
            dirty = request.params["dirty"]?.boolValue == true
            return .object([:])
        case "window.setPinned":
            ideWindowController?.setPinned(request.params["pinned"]?.boolValue == true)
            return .object([:])
        case "window.loadState":
            return try workspaceStateStore.loadWindowState(workspaceID: workspace.binding.id)
        case "window.saveState":
            try workspaceStateStore.saveWindowState(request.params, workspaceID: workspace.binding.id)
            return .object([:])
        case "window.closeIde":
            Task { [weak self] in
                _ = await self?.closeIDE(requireDirtyConfirmation: true)
            }
            return .object([:])
        default:
            throw InnerIDEError.bridgeRejected("unknown method: \(request.method)")
        }
    }

    private func openMoreDetails(_ prompt: String) async -> HandoffResult {
        guard await ensureChatHandoffConnection(),
              compatibilityProfile != nil,
              let mainSession
        else {
            return quickChatHandoffController.copyToClipboard(prompt, destination: .chatgpt)
        }
        return await quickChatHandoffController.handoff(
            prompt: prompt,
            mainSession: mainSession,
            port: port,
            mainTargetID: mainTargetID
        )
    }

    private func ensureChatHandoffConnection() async -> Bool {
        if let mainSession,
           compatibilityProfile != nil,
           let healthy = try? await mainSession.evaluate(
               "Boolean(document && document.documentElement)"
           ),
           healthy.boolValue == true {
            return true
        }

        await resetMainConnection()
        do {
            try await ensureConnected(forChatHandoff: true)
            return mainSession != nil && compatibilityProfile != nil
        } catch {
            return false
        }
    }

    private func resetMainConnection() async {
        mainEventsTask?.cancel()
        mainEventsTask = nil
        if let mainSession { await mainSession.close() }
        mainSession = nil
        mainTargetID = nil
        port = nil
        compatibilityProfile = nil
    }

    private func relativePath(_ params: JSONValue) throws -> String {
        guard let path = params["relativePath"]?.stringValue else {
            throw InnerIDEError.invalidRelativePath("")
        }
        return path
    }

    private func resolveWorkspace(taskKey: String) async throws {
        if let cached = workspaceStateStore.cachedWorkspace(for: taskKey),
           workspaceStateStore.isDirectory(cached) {
            try bindWorkspace(cached, taskKey: taskKey)
            return
        }
        if taskKey.isEmpty,
           let last = workspaceStateStore.lastWorkspace(),
           workspaceStateStore.isDirectory(last) {
            try bindWorkspace(last, taskKey: taskKey)
            return
        }

        if let mainSession,
           let result = try? await mainSession.evaluate(InjectionScripts.probeWorkspace()),
           let candidates = result["candidates"]?.arrayValue?.compactMap(\.stringValue) {
            for path in candidates {
                let url = URL(fileURLWithPath: path)
                guard workspaceStateStore.isDirectory(url) else { continue }
                let alert = NSAlert()
                alert.messageText = "Use this workspace?"
                alert.informativeText = path
                alert.addButton(withTitle: "Use Workspace")
                alert.addButton(withTitle: "Choose Another…")
                if alert.runModal() == .alertFirstButtonReturn {
                    try bindWorkspace(url, taskKey: taskKey)
                    return
                }
                break
            }
        }

        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Workspace"
        guard panel.runModal() == .OK, let url = panel.url else {
            throw InnerIDEError.workspaceUnavailable
        }
        try bindWorkspace(url, taskKey: taskKey)
    }

    private func bindWorkspace(_ url: URL, taskKey: String) throws {
        workspace = try WorkspaceService(rootURL: url)
        workspaceStateStore.recordWorkspace(url, taskKey: taskKey)
    }

    private func waitForMainRendererShell(
        _ session: CDPSession,
        timeout: TimeInterval = 20
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let ready = try? await session.evaluate(
                "location.protocol === 'app:' && !!document.body && !!document.querySelector('#root')"
            ).boolValue
            if ready == true { return }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw InnerIDEError.invalidTarget("Codex main renderer did not become ready")
    }

    private func startWatcher(_ workspace: WorkspaceService) throws {
        watcher?.stop()
        let watcher = WorkspaceWatcher(rootURL: workspace.rootURL) { [weak self] changes in
            for change in changes {
                Task { await self?.emitFileChange(change) }
            }
        }
        try watcher.start()
        self.watcher = watcher
    }

    private func emitFileChange(_ change: FileChange) async {
        let recent = recentIDEChanges.first { path, date in
            Date().timeIntervalSince(date) < 1.5
                && (change.relativePath == path || change.relativePath.hasPrefix(path + "/"))
        }
        recentIDEChanges = recentIDEChanges.filter { Date().timeIntervalSince($0.value) < 1.5 }
        let classified = FileChange(
            relativePath: change.relativePath,
            kind: change.kind,
            source: recent == nil ? "external" : "ide"
        )
        await emit(type: "files.changed", payload: try? .fromEncodable(classified))
    }

    private func reserveRuntimeTask() throws {
        guard activeRuntimeRunID == nil else {
            throw InnerIDEError.commandFailed("Another workspace task is already running")
        }
        activeRuntimeRunID = "starting"
    }

    private func adoptRuntimeRunID(_ runID: String) {
        if activeRuntimeRunID == "starting" { activeRuntimeRunID = runID }
    }

    private func clearRuntimeReservation() {
        if activeRuntimeRunID == "starting" { activeRuntimeRunID = nil }
    }

    private func handlePythonRuntimeEvent(_ event: PythonExecutionEvent) async {
        await emit(type: "python.event", payload: try? .fromEncodable(event))
        await handleRuntimeEvent(RuntimeExecutionEvent(python: event))
    }

    private func handleRuntimeEvent(_ event: RuntimeExecutionEvent) async {
        if event.kind == "started", activeRuntimeRunID == nil || activeRuntimeRunID == "starting" {
            activeRuntimeRunID = event.runId
        } else if ["exited", "failed"].contains(event.kind),
                  activeRuntimeRunID == event.runId || activeRuntimeRunID == "starting" {
            activeRuntimeRunID = nil
        }
        await emit(type: "runtime.event", payload: try? .fromEncodable(event))
    }

    private func emit(type: String, payload: JSONValue?) async {
        guard let payload else { return }
        ideWindowController?.emit(type: type, payload: payload)
    }

    private func confirmVenvCreation() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Create .venv in the current workspace?"
        alert.informativeText = "No dependencies will be installed."
        alert.addButton(withTitle: "Create .venv")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func builtinRuntimeDescriptors(languageID: String) -> [RuntimeDescriptor] {
        switch languageID {
        case "html", "css":
            return [RuntimeDescriptor(
                id: "builtin-\(languageID)",
                languageId: languageID,
                label: languageID == "html" ? "HTML Preview" : "CSS Preview",
                version: "Built in",
                source: "builtin",
                action: .preview
            )]
        case "json":
            return [RuntimeDescriptor(
                id: "builtin-json",
                languageId: languageID,
                label: "JSON Validator",
                version: "Built in",
                source: "builtin",
                action: .validate
            )]
        case "markdown":
            return [RuntimeDescriptor(
                id: "builtin-markdown",
                languageId: languageID,
                label: "Markdown Preview",
                version: "Built in",
                source: "builtin",
                action: .preview
            )]
        default:
            return [RuntimeDescriptor(
                id: "\(languageID)-unavailable",
                languageId: languageID,
                label: "Runtime unavailable",
                version: "Codex runtime service is not ready",
                source: "missing",
                action: .run,
                available: false,
                unavailableReason: "Codex Desktop integration is required for command execution"
            )]
        }
    }

    private func present(_ error: Error) {
        presentMessage("Codex Inner IDE", detail: error.localizedDescription)
    }

    private func presentMessage(_ title: String, detail: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = detail
        alert.runModal()
    }

}

import XCTest
@testable import CodexPetIDECore

final class CompatibilityProfileTests: XCTestCase {
    func testMatchesValidatedDesktopAndCLIProfile() {
        let profile = CompatibilityProfile.match(
            appVersion: "26.715.70719",
            codexCLIVersion: "codex-cli 0.145.0-alpha.27"
        )

        XCTAssertEqual(profile?.appVersion, "26.715.70719")
        XCTAssertEqual(profile?.codexCLIVersionPrefix, "codex-cli 0.145.0-alpha.27")
    }

    func testCurrentProfileUsesDesktopRendererProfile() {
        let profile = CompatibilityProfile.match(
            appVersion: "26.721.30844",
            codexCLIVersion: "codex-cli 0.146.0-alpha.3"
        )

        XCTAssertEqual(profile?.rendererProfile, "desktop-v1")
    }

    func testPreviousProfileRemainsSupported() {
        let profile = CompatibilityProfile.match(
            appVersion: "26.715.72359",
            codexCLIVersion: "codex-cli 0.145.0-alpha.30"
        )

        XCTAssertEqual(profile?.appVersion, "26.715.72359")
    }

    func testEarlierProfileRemainsSupported() {
        let profile = CompatibilityProfile.match(
            appVersion: "26.715.72028",
            codexCLIVersion: "codex-cli 0.145.0-alpha.30"
        )

        XCTAssertEqual(profile?.appVersion, "26.715.72028")
    }

    func testLegacyProfileRemainsSupported() {
        let profile = CompatibilityProfile.match(
            appVersion: "26.715.71837",
            codexCLIVersion: "codex-cli 0.145.0-alpha.30"
        )

        XCTAssertEqual(profile?.appVersion, "26.715.71837")
    }
}

final class CodexLaunchArgumentsTests: XCTestCase {
    func testFindsLoopbackRemoteDebuggingPort() {
        XCTAssertEqual(
            CodexLaunchArguments.remoteDebuggingPort(in: [
                "/Applications/ChatGPT.app/Contents/MacOS/ChatGPT",
                "--remote-debugging-address=127.0.0.1",
                "--remote-debugging-port=49686"
            ]),
            49_686
        )
    }

    func testRejectsMissingLoopbackAddressAndInvalidPorts() {
        XCTAssertNil(CodexLaunchArguments.remoteDebuggingPort(in: [
            "--remote-debugging-port=49686"
        ]))
        XCTAssertNil(CodexLaunchArguments.remoteDebuggingPort(in: [
            "--remote-debugging-address=0.0.0.0",
            "--remote-debugging-port=49686"
        ]))
        XCTAssertNil(CodexLaunchArguments.remoteDebuggingPort(in: [
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=70000"
        ]))
    }
}

final class WorkspaceServiceTests: XCTestCase {
    private var temporaryURL: URL!

    override func setUpWithError() throws {
        temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPetIDE-Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
    }

    func testVersionedAtomicWriteRejectsStaleDigest() throws {
        let file = temporaryURL.appendingPathComponent("main.py")
        try Data("print('one')\n".utf8).write(to: file)
        let service = try WorkspaceService(rootURL: temporaryURL)
        let initial = try service.read(relativePath: "main.py")
        let saved = try service.write(WriteFileRequest(
            relativePath: "main.py",
            content: "print('two')\n",
            expectedDigest: initial.digest
        ))
        XCTAssertNotEqual(saved.digest, initial.digest)
        XCTAssertThrowsError(try service.write(WriteFileRequest(
            relativePath: "main.py",
            content: "print('three')\n",
            expectedDigest: initial.digest
        ))) { error in
            XCTAssertEqual(error as? InnerIDEError, .fileChanged("main.py"))
        }
    }

    func testRejectsTraversalAndSymlinkEscape() throws {
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPetIDE-Outside-\(UUID().uuidString)")
        try Data("secret".utf8).write(to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(
            at: temporaryURL.appendingPathComponent("outside"),
            withDestinationURL: outside
        )
        let service = try WorkspaceService(rootURL: temporaryURL)
        XCTAssertThrowsError(try service.read(relativePath: "../outside"))
        XCTAssertThrowsError(try service.read(relativePath: "outside")) { error in
            guard case .pathEscapesWorkspace = error as? InnerIDEError else {
                return XCTFail("Expected pathEscapesWorkspace, got \(error)")
            }
        }
    }

    func testLargeAndBinaryFilesAreReadOnly() throws {
        try Data(repeating: 65, count: WorkspaceService.maximumEditableBytes + 1)
            .write(to: temporaryURL.appendingPathComponent("large.txt"))
        try Data([0, 1, 2, 3]).write(to: temporaryURL.appendingPathComponent("binary.bin"))
        let service = try WorkspaceService(rootURL: temporaryURL)
        XCTAssertTrue(try service.read(relativePath: "large.txt").readonly)
        XCTAssertTrue(try service.read(relativePath: "binary.bin").readonly)
    }

    func testRenamingContainedSymlinkDoesNotMoveItsTarget() throws {
        let target = temporaryURL.appendingPathComponent("target.txt")
        let link = temporaryURL.appendingPathComponent("link.txt")
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let service = try WorkspaceService(rootURL: temporaryURL)

        _ = try service.rename(from: "link.txt", to: "renamed-link.txt")

        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: temporaryURL.appendingPathComponent("renamed-link.txt").path
            ),
            target.path
        )
    }
}

final class PythonEditValidatorTests: XCTestCase {
    private var temporaryURL: URL!
    private var workspace: WorkspaceService!

    override func setUpWithError() throws {
        temporaryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInnerEdit-Tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryURL, withIntermediateDirectories: true)
        try Data("value = 1\nprint(value)\n".utf8)
            .write(to: temporaryURL.appendingPathComponent("main.py"))
        workspace = try WorkspaceService(rootURL: temporaryURL)
    }

    override func tearDownWithError() throws {
        if let temporaryURL { try? FileManager.default.removeItem(at: temporaryURL) }
    }

    func testAutoScopeUsesSelectionAndValidatesUTF16Range() throws {
        let content = "value = \"😀\"\nprint(value)\n"
        let context = ActivePythonEditContext(
            workspaceId: workspace.binding.id,
            relativePath: "main.py",
            scope: .auto,
            range: SelectionRange(startLine: 1, startColumn: 10, endLine: 1, endColumn: 12),
            bufferContent: content,
            bufferDigest: WorkspaceService.sha256(Data(content.utf8)),
            instruction: "Use a named constant",
            readonly: false
        )

        let validated = try PythonEditValidator.validate(context, workspace: workspace)

        XCTAssertEqual(validated.scope, .selection)
        XCTAssertEqual(PythonEditValidator.selectedText(in: content, range: validated.range!), "😀")
    }

    func testRejectsForgedDigestAndOversizedWholeFile() throws {
        let forged = ActivePythonEditContext(
            workspaceId: workspace.binding.id,
            relativePath: "main.py",
            scope: .file,
            range: nil,
            bufferContent: "print('changed')\n",
            bufferDigest: "not-the-buffer-digest",
            instruction: "Change it",
            readonly: false
        )
        XCTAssertThrowsError(try PythonEditValidator.validate(forged, workspace: workspace))

        let large = String(repeating: "x", count: PythonEditValidator.maximumFileCharacters + 1)
        let oversized = ActivePythonEditContext(
            workspaceId: workspace.binding.id,
            relativePath: "main.py",
            scope: .file,
            range: nil,
            bufferContent: large,
            bufferDigest: WorkspaceService.sha256(Data(large.utf8)),
            instruction: "Change it",
            readonly: false
        )
        XCTAssertThrowsError(try PythonEditValidator.validate(oversized, workspace: workspace))
    }

    func testRejectsNoOpReplacement() throws {
        let content = "value = 1\nprint(value)\n"
        let context = ActivePythonEditContext(
            workspaceId: workspace.binding.id,
            relativePath: "main.py",
            scope: .file,
            range: nil,
            bufferContent: content,
            bufferDigest: WorkspaceService.sha256(Data(content.utf8)),
            instruction: "Change it",
            readonly: false
        )
        XCTAssertThrowsError(try PythonEditValidator.validateReplacement(content, for: context))
    }
}

final class ProtocolSafetyTests: XCTestCase {
    func testCDPValidationRejectsNonLoopbackAndNonAppTargets() throws {
        let valid = CDPTarget(
            id: "1",
            type: "page",
            title: "Codex",
            url: "app://codex/index.html",
            webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/page/1"
        )
        XCTAssertNoThrow(try CDPValidation.validatedWebSocketURL(for: valid, port: 9222))
        let remote = CDPTarget(
            id: "1",
            type: "page",
            title: "Codex",
            url: "app://codex/index.html",
            webSocketDebuggerUrl: "ws://192.0.2.10:9222/devtools/page/1"
        )
        XCTAssertThrowsError(try CDPValidation.validatedWebSocketURL(for: remote, port: 9222))
        let web = CDPTarget(
            id: "1",
            type: "page",
            title: "Codex",
            url: "https://example.com",
            webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/page/1"
        )
        XCTAssertThrowsError(try CDPValidation.validatedWebSocketURL(for: web, port: 9222))
    }

    func testMainTargetRejectsAvatarOverlayRoutes() {
        let target = CDPTarget(
            id: "pet",
            type: "page",
            title: "Codex Pet",
            url: "app://codex/index.html?initialRoute=/avatar-overlay",
            webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/page/pet"
        )
        XCTAssertFalse(CDPValidation.isMainTarget(target))

        let compositionSurface = CDPTarget(
            id: "composition",
            type: "page",
            title: "Codex Pet Composition Surface",
            url: "app://-/avatar-overlay-composition-surface.html?surfaceId=mascot-badge",
            webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/page/composition"
        )
        XCTAssertFalse(CDPValidation.isMainTarget(compositionSurface))
    }

    func testMainTargetRecognition() {
        let target = CDPTarget(
            id: "main",
            type: "page",
            title: "Codex",
            url: "app://-/index.html",
            webSocketDebuggerUrl: "ws://127.0.0.1:9222/devtools/page/main"
        )
        XCTAssertTrue(CDPValidation.isMainTarget(target))
    }

    func testSelectionPromptIncludesContextAndEnforcesLimit() throws {
        let context = IdeSelectionContext(
            workspaceId: "workspace",
            relativePath: "main.py",
            language: "python",
            range: SelectionRange(startLine: 1, startColumn: 1, endLine: 1, endColumn: 8),
            selectedText: "print(1)",
            surroundingText: "print(1)",
            dirty: true
        )
        let chatGPTPrompt = try SelectionPrompt.renderForChatGPT(context)
        XCTAssertTrue(chatGPTPrompt.contains("main.py"))
        XCTAssertTrue(chatGPTPrompt.contains("Tell me more"))

        let oversized = IdeSelectionContext(
            workspaceId: context.workspaceId,
            relativePath: context.relativePath,
            language: context.language,
            range: context.range,
            selectedText: String(repeating: "x", count: SelectionPrompt.maximumSelectionCharacters + 1),
            surroundingText: "",
            dirty: false
        )
        XCTAssertThrowsError(try SelectionPrompt.renderForChatGPT(oversized))
    }

    func testBridgeBootstrapExposesSeparateCodexAndChatGPTRoutes() {
        let script = InjectionScripts.webViewBridgeBootstrap(sessionToken: "token")
        XCTAssertTrue(script.contains("window.codexInnerIdeHost"))
        XCTAssertFalse(script.contains("codex.addToChat"))
        XCTAssertTrue(script.contains("chatgpt.moreDetails"))
        XCTAssertTrue(script.contains("window.setPinned"))
        XCTAssertTrue(script.contains("crypto?.randomUUID"))
        XCTAssertTrue(script.contains("crypto?.getRandomValues"))
        XCTAssertFalse(script.contains("const requestId = crypto.randomUUID()"))
        XCTAssertFalse(script.contains("codexPetIdeHost"))
        XCTAssertTrue(script.contains("edits.request"))
        XCTAssertTrue(script.contains("edits.event"))
        XCTAssertTrue(script.contains("preferences.load"))
        XCTAssertTrue(script.contains("preferences.save"))
        XCTAssertTrue(script.contains("workspace.recent"))
        XCTAssertTrue(script.contains("workspace.openRecent"))
        XCTAssertTrue(script.contains("__codexInnerIdeGetActiveEditContext"))
    }

    func testLegacyWindowStateDefaultsSidebarToVisible() throws {
        let state = try JSONDecoder().decode(
            IdeWindowState.self,
            from: Data(#"{"openPaths":["main.py"],"activePath":"main.py","bottomPanelOpen":true,"expandedDirectories":[]}"#.utf8)
        )
        XCTAssertFalse(state.sidebarCollapsed)
        let collapsed = IdeWindowState(
            openPaths: ["main.py"],
            activePath: "main.py",
            bottomPanelOpen: true,
            sidebarCollapsed: true
        )
        XCTAssertTrue(try JSONDecoder().decode(
            IdeWindowState.self,
            from: JSONEncoder().encode(collapsed)
        ).sidebarCollapsed)
    }

    func testQuickChatHandoffUsesTheDedicatedQuickChatComposerInsteadOfCodexComposer() {
        let script = InjectionScripts.quickChatComposerHandoff(prompt: "test selection")

        XCTAssertTrue(script.contains("data-thread-find-composer"))
        XCTAssertTrue(script.contains("[contenteditable=\"true\"]"))
        XCTAssertTrue(script.contains("!element.hasAttribute('data-codex-composer')"))
        XCTAssertTrue(script.contains("quickChatCandidates.includes(focused)"))
        XCTAssertTrue(script.contains("routeMatch && scoped.length === 1"))
        XCTAssertTrue(script.contains("quick_chat_composer_ambiguous"))
    }
}

final class AppServerIntegrationTests: XCTestCase {
    func testCommandExecEnforcesWorkspaceAndNetworkSandbox() async throws {
        let codexURL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            throw XCTSkip("Bundled Codex App Server is unavailable")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPetIDE-AppServer-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexPetIDE-Outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }

        let client = AppServerClient(executableURL: codexURL, workingDirectoryURL: root)
        try await client.start()
        defer { Task { await client.stop() } }
        let sandbox = JSONValue.object([
            "type": .string("workspaceWrite"),
            "writableRoots": .array([.string(root.path)]),
            "networkAccess": .bool(false),
            "excludeSlashTmp": .bool(true),
            "excludeTmpdirEnvVar": .bool(true)
        ])

        let inside = try await command(
            client,
            argv: ["/usr/bin/python3", "-c", "open('inside.txt','w').write('ok')"],
            cwd: root,
            sandbox: sandbox
        )
        XCTAssertEqual(inside["exitCode"]?.intValue, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("inside.txt").path))

        let readOnlyTarget = root.appendingPathComponent("read-only-write.txt")
        let readOnly = try await command(
            client,
            argv: ["/usr/bin/python3", "-c", "open('read-only-write.txt','w').write('blocked')"],
            cwd: root,
            sandbox: .object(["type": .string("readOnly"), "networkAccess": .bool(false)])
        )
        XCTAssertNotEqual(readOnly["exitCode"]?.intValue, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: readOnlyTarget.path))

        let outsideResult = try await command(
            client,
            argv: ["/usr/bin/python3", "-c", "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text('escape')", outside.path],
            cwd: root,
            sandbox: sandbox
        )
        XCTAssertNotEqual(outsideResult["exitCode"]?.intValue, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))

        let network = try await command(
            client,
            argv: ["/usr/bin/python3", "-c", "import socket; socket.create_connection(('1.1.1.1', 80), timeout=2)"],
            cwd: root,
            sandbox: sandbox
        )
        XCTAssertNotEqual(network["exitCode"]?.intValue, 0)
    }

    func testReadOnlyProposalDoesNotChangeFile() async throws {
        guard ProcessInfo.processInfo.environment["CODEX_INNER_EDIT_LIVE_TEST"] == "1" else {
            throw XCTSkip("Set CODEX_INNER_EDIT_LIVE_TEST=1 to call the configured Codex model")
        }
        let codexURL = URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            throw XCTSkip("Bundled Codex App Server is unavailable")
        }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInnerEdit-Live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("main.py")
        let content = "def answer():\n    return 42\n"
        try Data(content.utf8).write(to: file)
        let before = WorkspaceService.sha256(try Data(contentsOf: file))

        let workspace = try WorkspaceService(rootURL: root)
        let client = AppServerClient(executableURL: codexURL, workingDirectoryURL: root)
        try await client.start()
        let service = PythonEditService(client: client, workspace: workspace)
        let events = AsyncStream.makeStream(of: PythonEditProposalEvent.self)
        await service.setEventHandler { events.continuation.yield($0) }
        await service.start()
        defer {
            events.continuation.finish()
            Task {
                await service.stop()
                await client.stop()
            }
        }

        let context = ActivePythonEditContext(
            workspaceId: workspace.binding.id,
            relativePath: "main.py",
            scope: .file,
            range: nil,
            bufferContent: content,
            bufferDigest: WorkspaceService.sha256(Data(content.utf8)),
            instruction: "Add a concise return type annotation without changing behavior.",
            readonly: false
        )
        _ = try await service.request(context)
        let terminal = try await withThrowingTaskGroup(of: PythonEditProposalEvent.self) { group in
            group.addTask {
                for await event in events.stream where event.proposal.state != .generating {
                    return event
                }
                throw InnerIDEError.proposalInvalid("proposal event stream ended")
            }
            group.addTask {
                try await Task.sleep(for: .seconds(120))
                throw InnerIDEError.appServerUnavailable("live proposal timed out")
            }
            let value = try await group.next()!
            group.cancelAll()
            return value
        }

        XCTAssertEqual(terminal.proposal.state, .ready, terminal.message ?? "proposal failed")
        XCTAssertNotEqual(terminal.proposal.replacementText, content)
        XCTAssertEqual(WorkspaceService.sha256(try Data(contentsOf: file)), before)
        try await service.decide(PythonEditDecision(
            proposalId: terminal.proposal.proposalId,
            decision: .rejected
        ))
    }

    private func command(
        _ client: AppServerClient,
        argv: [String],
        cwd: URL,
        sandbox: JSONValue
    ) async throws -> JSONValue {
        try await client.request(
            method: "command/exec",
            params: .object([
                "command": .array(argv.map(JSONValue.string)),
                "cwd": .string(cwd.path),
                "timeoutMs": .number(10_000),
                "sandboxPolicy": sandbox
            ]),
            timeout: 20
        )
    }
}

final class LiveCDPIntegrationTests: XCTestCase {
    func testRecoversDebugPortFromRunningCodexWhenRequested() async throws {
        guard let portText = ProcessInfo.processInfo.environment["CODEX_INNER_IDE_CDP_PORT"],
              let expectedPort = Int(portText)
        else {
            throw XCTSkip("Set CODEX_INNER_IDE_CDP_PORT to test a running Codex CDP endpoint")
        }

        let launcher = await MainActor.run { CodexLauncher() }
        let recoveredPort = await launcher.runningDebugPort()
        XCTAssertEqual(recoveredPort, expectedPort)
    }

    func testConnectsToRunningCodexWhenRequested() async throws {
        guard let portText = ProcessInfo.processInfo.environment["CODEX_INNER_IDE_CDP_PORT"],
              let port = Int(portText)
        else {
            throw XCTSkip("Set CODEX_INNER_IDE_CDP_PORT to test a running Codex CDP endpoint")
        }

        let target = try await CDPTargetDiscovery.waitForTarget(
            port: port,
            timeout: 5,
            matching: CDPValidation.isMainTarget
        )
        let session = try CDPSession(target: target, port: port)
        do {
            try await session.connect()
            let href = try await session.evaluate("location.href")
            XCTAssertTrue(href.stringValue?.hasPrefix("app://") == true)
        } catch {
            await session.close()
            throw error
        }
        await session.close()
    }
}

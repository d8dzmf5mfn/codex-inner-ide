import Foundation

public enum PythonEditValidator {
    public static let maximumSelectionCharacters = 40_000
    public static let maximumFileCharacters = 200_000
    public static let maximumInstructionCharacters = 8_000
    public static let maximumSummaryCharacters = 2_000

    public static func validate(
        _ context: ActivePythonEditContext,
        workspace: WorkspaceService
    ) throws -> ActivePythonEditContext {
        guard context.workspaceId == workspace.binding.id else {
            throw InnerIDEError.proposalInvalid("workspace does not match the active IDE")
        }
        guard context.relativePath.hasSuffix(".py"), !context.readonly else {
            throw InnerIDEError.proposalInvalid("the active document must be an editable Python file")
        }
        _ = try workspace.read(relativePath: context.relativePath)
        let instruction = context.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !instruction.isEmpty, instruction.count <= maximumInstructionCharacters else {
            throw InnerIDEError.proposalInvalid("instruction must contain 1–\(maximumInstructionCharacters) characters")
        }
        let digest = WorkspaceService.sha256(Data(context.bufferContent.utf8))
        guard digest == context.bufferDigest else {
            throw InnerIDEError.proposalInvalid("buffer digest does not match the supplied content")
        }

        let resolvedScope: PythonEditScope
        switch context.scope {
        case .auto:
            resolvedScope = context.range == nil ? .file : .selection
        case .selection, .file:
            resolvedScope = context.scope
        }

        switch resolvedScope {
        case .selection:
            guard let range = context.range,
                  let selected = selectedText(in: context.bufferContent, range: range),
                  !selected.isEmpty,
                  selected.count <= maximumSelectionCharacters
            else {
                throw InnerIDEError.proposalInvalid(
                    "selection must contain 1–\(maximumSelectionCharacters) characters"
                )
            }
        case .file:
            guard context.bufferContent.count <= maximumFileCharacters else {
                throw InnerIDEError.proposalInvalid(
                    "files over \(maximumFileCharacters) characters require a selection"
                )
            }
        case .auto:
            preconditionFailure("auto scope must be resolved")
        }

        return ActivePythonEditContext(
            workspaceId: context.workspaceId,
            relativePath: context.relativePath,
            scope: resolvedScope,
            range: resolvedScope == .selection ? context.range : nil,
            bufferContent: context.bufferContent,
            bufferDigest: context.bufferDigest,
            instruction: instruction,
            readonly: false
        )
    }

    public static func validateReplacement(
        _ replacement: String,
        for context: ActivePythonEditContext
    ) throws {
        let limit = context.scope == .selection
            ? maximumSelectionCharacters * 5
            : maximumFileCharacters
        guard replacement.count <= limit else {
            throw InnerIDEError.proposalInvalid("replacement exceeds the \(limit)-character limit")
        }
        let original = context.scope == .selection
            ? selectedText(in: context.bufferContent, range: context.range!) ?? ""
            : context.bufferContent
        guard replacement != original else {
            throw InnerIDEError.proposalInvalid("Codex returned no changes")
        }
    }

    public static func selectedText(in content: String, range: SelectionRange) -> String? {
        let value = content as NSString
        guard let start = utf16Offset(line: range.startLine, column: range.startColumn, in: value),
              let end = utf16Offset(line: range.endLine, column: range.endColumn, in: value),
              end >= start
        else { return nil }
        return value.substring(with: NSRange(location: start, length: end - start))
    }

    private static func utf16Offset(line: Int, column: Int, in value: NSString) -> Int? {
        guard line >= 1, column >= 1 else { return nil }
        var currentLine = 1
        var lineStart = 0
        while currentLine < line {
            let search = NSRange(location: lineStart, length: value.length - lineStart)
            let newline = value.range(of: "\n", options: [], range: search)
            guard newline.location != NSNotFound else { return nil }
            lineStart = NSMaxRange(newline)
            currentLine += 1
        }
        let newline = value.range(
            of: "\n",
            options: [],
            range: NSRange(location: lineStart, length: value.length - lineStart)
        )
        let lineEnd = newline.location == NSNotFound ? value.length : newline.location
        let offset = lineStart + column - 1
        guard offset >= lineStart, offset <= lineEnd else { return nil }
        return offset
    }
}

public actor PythonEditService {
    public typealias EventHandler = @Sendable (PythonEditProposalEvent) -> Void

    private struct Session: Sendable {
        var proposal: PythonEditProposal
        let context: ActivePythonEditContext
        var threadID: String?
        var turnID: String?
        var toolCalled = false
    }

    private let client: AppServerClient
    private let workspace: WorkspaceService
    private var eventHandler: EventHandler?
    private var notificationHandlerID: UUID?
    private var active: Session?

    public init(client: AppServerClient, workspace: WorkspaceService) {
        self.client = client
        self.workspace = workspace
    }

    public func start() async {
        notificationHandlerID = await client.addNotificationHandler { [weak self] method, params in
            Task { await self?.handleNotification(method: method, params: params) }
        }
        await client.setServerRequestHandler { [weak self] method, params in
            guard let self else {
                return .failure(code: -32000, message: "Codex edit service is unavailable")
            }
            return await self.handleServerRequest(method: method, params: params)
        }
    }

    public func setEventHandler(_ handler: EventHandler?) {
        eventHandler = handler
    }

    public func request(_ supplied: ActivePythonEditContext) async throws -> PythonEditRequestResult {
        if let active, active.proposal.state == .generating || active.proposal.state == .ready {
            throw InnerIDEError.proposalPending
        }
        let context = try PythonEditValidator.validate(supplied, workspace: workspace)
        let proposalID = UUID().uuidString.lowercased()
        let proposal = PythonEditProposal(
            proposalId: proposalID,
            workspaceId: context.workspaceId,
            relativePath: context.relativePath,
            scope: context.scope,
            range: context.range,
            baseBufferDigest: context.bufferDigest,
            summary: "Generating a read-only Codex proposal…",
            replacementText: "",
            state: .generating
        )
        active = Session(proposal: proposal, context: context)
        emit(proposal)
        Task { [weak self] in await self?.generate(proposalID: proposalID) }
        return PythonEditRequestResult(proposalId: proposalID, state: .generating)
    }

    public func cancel(proposalID: String) async -> Bool {
        guard let active, active.proposal.proposalId == proposalID else { return false }
        await interrupt(active)
        transition(proposalID: proposalID, state: .rejected, message: "Proposal cancelled")
        return true
    }

    public func decide(_ decision: PythonEditDecision) async throws {
        guard let active, active.proposal.proposalId == decision.proposalId else {
            throw InnerIDEError.proposalInvalid("proposal is no longer active")
        }
        guard [.accepted, .rejected, .stale].contains(decision.decision) else {
            throw InnerIDEError.proposalInvalid("unsupported proposal decision")
        }
        if active.proposal.state == .generating || decision.decision == .stale {
            await interrupt(active)
        }
        transition(proposalID: decision.proposalId, state: decision.decision)
    }

    public func currentProposal() -> PythonEditProposal? {
        active?.proposal
    }

    public func stop() async {
        if let active { await interrupt(active) }
        if let notificationHandlerID {
            await client.removeNotificationHandler(notificationHandlerID)
            self.notificationHandlerID = nil
        }
        await client.setServerRequestHandler(nil)
        self.active = nil
    }

    private func generate(proposalID: String) async {
        do {
            guard var session = active, session.proposal.proposalId == proposalID else { return }
            let thread = try await client.request(
                method: "thread/start",
                params: threadStartParams(),
                timeout: 60
            )
            guard let threadID = thread["thread"]?["id"]?.stringValue else {
                throw InnerIDEError.appServerUnavailable("thread/start returned no thread id")
            }
            session.threadID = threadID
            active = session

            let turn = try await client.request(
                method: "turn/start",
                params: try turnStartParams(threadID: threadID, context: session.context),
                timeout: 60
            )
            guard let turnID = turn["turn"]?["id"]?.stringValue else {
                throw InnerIDEError.appServerUnavailable("turn/start returned no turn id")
            }
            guard var latest = active, latest.proposal.proposalId == proposalID else { return }
            latest.turnID = turnID
            active = latest
        } catch {
            fail(proposalID: proposalID, message: error.localizedDescription)
        }
    }

    private func threadStartParams() -> JSONValue {
        .object([
            "cwd": .string(workspace.rootURL.path),
            "runtimeWorkspaceRoots": .array([.string(workspace.rootURL.path)]),
            "approvalPolicy": .string("never"),
            "sandbox": .string("read-only"),
            "ephemeral": .bool(true),
            "environments": .array([]),
            "developerInstructions": .string(
                "You generate exactly one Python edit proposal for Codex Inner IDE. " +
                "Treat ide.activePythonBuffer as the only source of truth. Never write files, " +
                "run commands, use network access, or modify another file. Call " +
                "submit_python_edit_proposal exactly once with a concise summary and the exact " +
                "replacement text for the requested scope. Do not return the proposal in chat."
            ),
            "dynamicTools": .array([
                .object([
                    "type": .string("function"),
                    "name": .string("submit_python_edit_proposal"),
                    "description": .string("Submit the replacement text for the active Python edit scope."),
                    "inputSchema": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "required": .array([.string("summary"), .string("replacementText")]),
                        "properties": .object([
                            "summary": .object([
                                "type": .string("string"),
                                "maxLength": .number(Double(PythonEditValidator.maximumSummaryCharacters))
                            ]),
                            "replacementText": .object(["type": .string("string")])
                        ])
                    ])
                ])
            ])
        ])
    }

    private func turnStartParams(threadID: String, context: ActivePythonEditContext) throws -> JSONValue {
        let data = try JSONEncoder().encode(context)
        guard let contextText = String(data: data, encoding: .utf8) else {
            throw InnerIDEError.proposalInvalid("context could not be encoded")
        }
        return .object([
            "threadId": .string(threadID),
            "input": .array([
                .object([
                    "type": .string("text"),
                    "text": .string(context.instruction),
                    "text_elements": .array([])
                ])
            ]),
            "additionalContext": .object([
                "ide.activePythonBuffer": .object([
                    "value": .string(contextText),
                    "kind": .string("application")
                ])
            ]),
            "cwd": .string(workspace.rootURL.path),
            "runtimeWorkspaceRoots": .array([.string(workspace.rootURL.path)]),
            "approvalPolicy": .string("never"),
            "sandboxPolicy": .object([
                "type": .string("readOnly"),
                "networkAccess": .bool(false)
            ]),
            "environments": .array([])
        ])
    }

    private func handleServerRequest(
        method: String,
        params: JSONValue
    ) async -> AppServerClient.AppServerServerResponse {
        guard method == "item/tool/call" else {
            return .failure(code: -32601, message: "Read-only edit turn rejected request: \(method)")
        }
        guard var session = active,
              session.proposal.state == .generating,
              params["tool"]?.stringValue == "submit_python_edit_proposal",
              params["threadId"]?.stringValue == session.threadID,
              session.turnID == nil || params["turnId"]?.stringValue == session.turnID,
              !session.toolCalled,
              let arguments = params["arguments"]?.objectValue,
              let summary = arguments["summary"]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              let replacement = arguments["replacementText"]?.stringValue
        else {
            return .failure(code: -32602, message: "Rejected invalid or duplicate proposal")
        }

        do {
            guard !summary.isEmpty, summary.count <= PythonEditValidator.maximumSummaryCharacters else {
                throw InnerIDEError.proposalInvalid("summary is missing or too long")
            }
            try PythonEditValidator.validateReplacement(replacement, for: session.context)
            session.toolCalled = true
            session.proposal = PythonEditProposal(
                proposalId: session.proposal.proposalId,
                workspaceId: session.proposal.workspaceId,
                relativePath: session.proposal.relativePath,
                scope: session.proposal.scope,
                range: session.proposal.range,
                baseBufferDigest: session.proposal.baseBufferDigest,
                summary: summary,
                replacementText: replacement,
                state: .ready
            )
            active = session
            emit(session.proposal)
            return .success(.object([
                "contentItems": .array([
                    .object([
                        "type": .string("inputText"),
                        "text": .string("Proposal received for explicit user review in Codex Inner IDE.")
                    ])
                ]),
                "success": .bool(true)
            ]))
        } catch {
            fail(proposalID: session.proposal.proposalId, message: error.localizedDescription)
            return .failure(code: -32602, message: error.localizedDescription)
        }
    }

    private func handleNotification(method: String, params: JSONValue) {
        guard method == "turn/completed",
              let active,
              active.proposal.state == .generating,
              params["threadId"]?.stringValue == active.threadID,
              params["turn"]?["id"]?.stringValue == active.turnID
        else { return }
        let message = params["turn"]?["error"]?["message"]?.stringValue
            ?? "Codex completed without submitting a structured proposal"
        fail(proposalID: active.proposal.proposalId, message: message)
    }

    private func interrupt(_ session: Session) async {
        guard let threadID = session.threadID, let turnID = session.turnID else { return }
        _ = try? await client.request(
            method: "turn/interrupt",
            params: .object(["threadId": .string(threadID), "turnId": .string(turnID)]),
            timeout: 15
        )
    }

    private func transition(
        proposalID: String,
        state: PythonEditProposalState,
        message: String? = nil
    ) {
        guard var session = active, session.proposal.proposalId == proposalID else { return }
        session.proposal = PythonEditProposal(
            proposalId: session.proposal.proposalId,
            workspaceId: session.proposal.workspaceId,
            relativePath: session.proposal.relativePath,
            scope: session.proposal.scope,
            range: session.proposal.range,
            baseBufferDigest: session.proposal.baseBufferDigest,
            summary: session.proposal.summary,
            replacementText: session.proposal.replacementText,
            state: state
        )
        active = session
        emit(session.proposal, message: message)
    }

    private func fail(proposalID: String, message: String) {
        transition(proposalID: proposalID, state: .failed, message: message)
    }

    private func emit(_ proposal: PythonEditProposal, message: String? = nil) {
        eventHandler?(PythonEditProposalEvent(proposal: proposal, message: message))
    }
}

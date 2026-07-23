import Foundation

public enum InnerIDEError: Error, LocalizedError, Equatable, Sendable {
    case unsupportedCodexVersion(String)
    case unsupportedCodexCLIVersion(actual: String, expected: String)
    case invalidTarget(String)
    case cdpUnavailable(String)
    case bridgeRejected(String)
    case workspaceUnavailable
    case invalidRelativePath(String)
    case pathEscapesWorkspace(String)
    case fileChanged(String)
    case fileTooLarge(String)
    case binaryFile(String)
    case appServerUnavailable(String)
    case commandFailed(String)
    case proposalPending
    case proposalStale
    case proposalInvalid(String)
    case localBridgeUnavailable(String)
    case rendererAssetsMissing

    public var errorDescription: String? {
        switch self {
        case .unsupportedCodexVersion(let version):
            return "Codex version \(version) has not been validated."
        case .unsupportedCodexCLIVersion(let actual, let expected):
            return "Bundled Codex CLI \(actual) does not match validated profile \(expected)."
        case .invalidTarget(let reason): return "Rejected Codex target: \(reason)"
        case .cdpUnavailable(let reason): return "Codex CDP is unavailable: \(reason)"
        case .bridgeRejected(let reason): return "IDE bridge rejected the request: \(reason)"
        case .workspaceUnavailable: return "No workspace is bound to the IDE."
        case .invalidRelativePath(let path): return "Invalid workspace-relative path: \(path)"
        case .pathEscapesWorkspace(let path): return "Path escapes the workspace: \(path)"
        case .fileChanged(let path): return "File changed on disk: \(path)"
        case .fileTooLarge(let path): return "File is larger than the 5 MB editor limit: \(path)"
        case .binaryFile(let path): return "Binary files are read-only: \(path)"
        case .appServerUnavailable(let reason): return "Codex App Server is unavailable: \(reason)"
        case .commandFailed(let reason): return "Command failed: \(reason)"
        case .proposalPending: return "A Codex edit proposal is already active."
        case .proposalStale: return "The Codex edit proposal is stale."
        case .proposalInvalid(let reason): return "Invalid Codex edit proposal: \(reason)"
        case .localBridgeUnavailable(let reason): return "Codex Inner IDE bridge unavailable: \(reason)"
        case .rendererAssetsMissing: return "The embedded IDE renderer is missing or invalid."
        }
    }

    public var code: String {
        switch self {
        case .unsupportedCodexVersion: "unsupported_codex_version"
        case .unsupportedCodexCLIVersion: "unsupported_codex_cli_version"
        case .invalidTarget: "invalid_target"
        case .cdpUnavailable: "cdp_unavailable"
        case .bridgeRejected: "bridge_rejected"
        case .workspaceUnavailable: "workspace_unavailable"
        case .invalidRelativePath: "invalid_relative_path"
        case .pathEscapesWorkspace: "path_escapes_workspace"
        case .fileChanged: "file_changed"
        case .fileTooLarge: "file_too_large"
        case .binaryFile: "binary_file"
        case .appServerUnavailable: "app_server_unavailable"
        case .commandFailed: "command_failed"
        case .proposalPending: "proposal_pending"
        case .proposalStale: "proposal_stale"
        case .proposalInvalid: "proposal_invalid"
        case .localBridgeUnavailable: "local_bridge_unavailable"
        case .rendererAssetsMissing: "renderer_assets_missing"
        }
    }
}

public enum PythonEditScope: String, Codable, Equatable, Sendable {
    case auto
    case selection
    case file
}

public enum PythonEditProposalState: String, Codable, Equatable, Sendable {
    case generating
    case ready
    case stale
    case accepted
    case rejected
    case failed
}

public struct ActivePythonEditContext: Codable, Equatable, Sendable {
    public let workspaceId: String
    public let relativePath: String
    public let scope: PythonEditScope
    public let range: SelectionRange?
    public let bufferContent: String
    public let bufferDigest: String
    public let instruction: String
    public let readonly: Bool

    public init(
        workspaceId: String,
        relativePath: String,
        scope: PythonEditScope,
        range: SelectionRange?,
        bufferContent: String,
        bufferDigest: String,
        instruction: String,
        readonly: Bool
    ) {
        self.workspaceId = workspaceId
        self.relativePath = relativePath
        self.scope = scope
        self.range = range
        self.bufferContent = bufferContent
        self.bufferDigest = bufferDigest
        self.instruction = instruction
        self.readonly = readonly
    }
}

public struct PythonEditProposal: Codable, Equatable, Sendable {
    public let proposalId: String
    public let workspaceId: String
    public let relativePath: String
    public let scope: PythonEditScope
    public let range: SelectionRange?
    public let baseBufferDigest: String
    public let summary: String
    public let replacementText: String
    public let state: PythonEditProposalState

    public init(
        proposalId: String,
        workspaceId: String,
        relativePath: String,
        scope: PythonEditScope,
        range: SelectionRange?,
        baseBufferDigest: String,
        summary: String,
        replacementText: String,
        state: PythonEditProposalState
    ) {
        self.proposalId = proposalId
        self.workspaceId = workspaceId
        self.relativePath = relativePath
        self.scope = scope
        self.range = range
        self.baseBufferDigest = baseBufferDigest
        self.summary = summary
        self.replacementText = replacementText
        self.state = state
    }
}

public struct PythonEditProposalEvent: Codable, Equatable, Sendable {
    public let proposal: PythonEditProposal
    public let message: String?

    public init(proposal: PythonEditProposal, message: String? = nil) {
        self.proposal = proposal
        self.message = message
    }
}

public struct PythonEditRequest: Codable, Equatable, Sendable {
    public let instruction: String
    public let scope: PythonEditScope
    public let context: ActivePythonEditContext

    public init(instruction: String, scope: PythonEditScope, context: ActivePythonEditContext) {
        self.instruction = instruction
        self.scope = scope
        self.context = context
    }
}

public struct PythonEditRequestResult: Codable, Equatable, Sendable {
    public let proposalId: String
    public let state: PythonEditProposalState

    public init(proposalId: String, state: PythonEditProposalState) {
        self.proposalId = proposalId
        self.state = state
    }
}

public struct PythonEditDecision: Codable, Equatable, Sendable {
    public let proposalId: String
    public let decision: PythonEditProposalState

    public init(proposalId: String, decision: PythonEditProposalState) {
        self.proposalId = proposalId
        self.decision = decision
    }
}

public struct CDPTarget: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let title: String
    public let url: String
    public let webSocketDebuggerUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case title
        case url
        case webSocketDebuggerUrl
    }

    public init(
        id: String,
        type: String,
        title: String,
        url: String,
        webSocketDebuggerUrl: String
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.url = url
        self.webSocketDebuggerUrl = webSocketDebuggerUrl
    }
}

public struct CDPEvent: Sendable {
    public let method: String
    public let params: JSONValue

    public init(method: String, params: JSONValue) {
        self.method = method
        self.params = params
    }
}

public struct WorkspaceBinding: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let rootLabel: String

    public init(id: String, name: String, rootLabel: String) {
        self.id = id
        self.name = name
        self.rootLabel = rootLabel
    }
}

public struct RecentWorkspace: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let rootLabel: String
    public let available: Bool

    public init(id: String, name: String, rootLabel: String, available: Bool) {
        self.id = id
        self.name = name
        self.rootLabel = rootLabel
        self.available = available
    }
}

public enum FileKind: String, Codable, Sendable {
    case file
    case directory
}

public struct FileEntry: Codable, Equatable, Sendable {
    public let name: String
    public let relativePath: String
    public let kind: FileKind

    public init(name: String, relativePath: String, kind: FileKind) {
        self.name = name
        self.relativePath = relativePath
        self.kind = kind
    }
}

public struct FileSnapshot: Codable, Equatable, Sendable {
    public let relativePath: String
    public let content: String
    public let digest: String
    public let readonly: Bool
    public let readonlyReason: String?

    public init(
        relativePath: String,
        content: String,
        digest: String,
        readonly: Bool,
        readonlyReason: String? = nil
    ) {
        self.relativePath = relativePath
        self.content = content
        self.digest = digest
        self.readonly = readonly
        self.readonlyReason = readonlyReason
    }
}

public struct WriteFileRequest: Codable, Equatable, Sendable {
    public let relativePath: String
    public let content: String
    public let expectedDigest: String
}

public struct FileChange: Codable, Equatable, Sendable {
    public let relativePath: String
    public let kind: String
    public let source: String

    public init(relativePath: String, kind: String, source: String) {
        self.relativePath = relativePath
        self.kind = kind
        self.source = source
    }
}

public struct PythonInterpreter: Codable, Equatable, Sendable {
    public let id: String
    public let executable: String
    public let version: String
    public let source: String
}

public enum RuntimeAction: String, Codable, Equatable, Sendable {
    case run
    case preview
    case validate
    case none
}

public struct RuntimeDescriptor: Codable, Equatable, Sendable {
    public let id: String
    public let languageId: String
    public let label: String
    public let version: String
    public let executable: String?
    public let source: String
    public let action: RuntimeAction
    public let available: Bool
    public let unavailableReason: String?

    public init(
        id: String,
        languageId: String,
        label: String,
        version: String,
        executable: String? = nil,
        source: String,
        action: RuntimeAction,
        available: Bool = true,
        unavailableReason: String? = nil
    ) {
        self.id = id
        self.languageId = languageId
        self.label = label
        self.version = version
        self.executable = executable
        self.source = source
        self.action = action
        self.available = available
        self.unavailableReason = unavailableReason
    }
}

public struct RuntimeExecuteRequest: Codable, Equatable, Sendable {
    public let relativePath: String
    public let languageId: String
    public let runtimeId: String?

    public init(relativePath: String, languageId: String, runtimeId: String? = nil) {
        self.relativePath = relativePath
        self.languageId = languageId
        self.runtimeId = runtimeId
    }
}

public struct RuntimeCheckRequest: Codable, Equatable, Sendable {
    public let relativePath: String
    public let languageId: String
    public let runtimeId: String?

    public init(relativePath: String, languageId: String, runtimeId: String? = nil) {
        self.relativePath = relativePath
        self.languageId = languageId
        self.runtimeId = runtimeId
    }
}

public struct Diagnostic: Codable, Equatable, Sendable {
    public let relativePath: String
    public let line: Int
    public let column: Int
    public let severity: String
    public let message: String
}

public struct PythonExecutionEvent: Codable, Equatable, Sendable {
    public let runId: String
    public let kind: String
    public let stream: String?
    public let text: String?
    public let exitCode: Int?
    public let diagnostics: [Diagnostic]?

    public init(
        runId: String,
        kind: String,
        stream: String? = nil,
        text: String? = nil,
        exitCode: Int? = nil,
        diagnostics: [Diagnostic]? = nil
    ) {
        self.runId = runId
        self.kind = kind
        self.stream = stream
        self.text = text
        self.exitCode = exitCode
        self.diagnostics = diagnostics
    }
}

public struct RuntimeExecutionEvent: Codable, Equatable, Sendable {
    public let runId: String
    public let languageId: String
    public let kind: String
    public let stream: String?
    public let text: String?
    public let exitCode: Int?
    public let diagnostics: [Diagnostic]?

    public init(
        runId: String,
        languageId: String,
        kind: String,
        stream: String? = nil,
        text: String? = nil,
        exitCode: Int? = nil,
        diagnostics: [Diagnostic]? = nil
    ) {
        self.runId = runId
        self.languageId = languageId
        self.kind = kind
        self.stream = stream
        self.text = text
        self.exitCode = exitCode
        self.diagnostics = diagnostics
    }

    public init(python event: PythonExecutionEvent) {
        self.init(
            runId: event.runId,
            languageId: "python",
            kind: event.kind,
            stream: event.stream,
            text: event.text,
            exitCode: event.exitCode,
            diagnostics: event.diagnostics
        )
    }
}

public struct PreviewDescriptor: Codable, Equatable, Sendable {
    public let relativePath: String
    public let languageId: String
    public let url: String?
    public let content: String?
    public let entryRelativePath: String?

    public init(
        relativePath: String,
        languageId: String,
        url: String? = nil,
        content: String? = nil,
        entryRelativePath: String? = nil
    ) {
        self.relativePath = relativePath
        self.languageId = languageId
        self.url = url
        self.content = content
        self.entryRelativePath = entryRelativePath
    }
}

public enum ThemeMode: String, Codable, Equatable, Sendable {
    case auto
    case light
    case dark
}

public struct UserCompletionSnippet: Codable, Equatable, Sendable {
    public let id: String
    public let languageId: String
    public let triggerPrefix: String
    public let displayName: String
    public let description: String
    public let body: String

    public init(
        id: String,
        languageId: String,
        triggerPrefix: String,
        displayName: String,
        description: String,
        body: String
    ) {
        self.id = id
        self.languageId = languageId
        self.triggerPrefix = triggerPrefix
        self.displayName = displayName
        self.description = description
        self.body = body
    }
}

public struct GlobalPreferences: Codable, Equatable, Sendable {
    public let themeMode: ThemeMode
    public let completionSnippets: [UserCompletionSnippet]

    public init(themeMode: ThemeMode = .auto, completionSnippets: [UserCompletionSnippet] = []) {
        self.themeMode = themeMode
        self.completionSnippets = completionSnippets
    }
}

public struct IdeWindowState: Codable, Equatable, Sendable {
    public let openPaths: [String]
    public let activePath: String?
    public let bottomPanelOpen: Bool
    public let expandedDirectories: [String]
    public let sidebarCollapsed: Bool

    public init(
        openPaths: [String],
        activePath: String?,
        bottomPanelOpen: Bool,
        expandedDirectories: [String] = [],
        sidebarCollapsed: Bool = false
    ) {
        self.openPaths = openPaths
        self.activePath = activePath
        self.bottomPanelOpen = bottomPanelOpen
        self.expandedDirectories = expandedDirectories
        self.sidebarCollapsed = sidebarCollapsed
    }

    private enum CodingKeys: String, CodingKey {
        case openPaths, activePath, bottomPanelOpen, expandedDirectories, sidebarCollapsed
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        openPaths = try values.decode([String].self, forKey: .openPaths)
        activePath = try values.decodeIfPresent(String.self, forKey: .activePath)
        bottomPanelOpen = try values.decode(Bool.self, forKey: .bottomPanelOpen)
        expandedDirectories = try values.decodeIfPresent([String].self, forKey: .expandedDirectories) ?? []
        sidebarCollapsed = try values.decodeIfPresent(Bool.self, forKey: .sidebarCollapsed) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(openPaths, forKey: .openPaths)
        try values.encodeIfPresent(activePath, forKey: .activePath)
        try values.encode(bottomPanelOpen, forKey: .bottomPanelOpen)
        try values.encode(expandedDirectories, forKey: .expandedDirectories)
        try values.encode(sidebarCollapsed, forKey: .sidebarCollapsed)
    }
}

public struct BridgeRequest: Codable, Equatable, Sendable {
    public let version: Int
    public let requestId: String
    public let sessionToken: String
    public let method: String
    public let params: JSONValue
}

public struct BridgeFailure: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
}

public struct BridgeResponse: Codable, Equatable, Sendable {
    public let requestId: String
    public let ok: Bool
    public let data: JSONValue?
    public let error: BridgeFailure?

    public static func success(_ requestId: String, data: JSONValue = .object([:])) -> BridgeResponse {
        BridgeResponse(requestId: requestId, ok: true, data: data, error: nil)
    }

    public static func failure(_ requestId: String, error: Error) -> BridgeResponse {
        if let innerError = error as? InnerIDEError {
            return BridgeResponse(
                requestId: requestId,
                ok: false,
                data: nil,
                error: BridgeFailure(code: innerError.code, message: innerError.localizedDescription)
            )
        }
        return BridgeResponse(
            requestId: requestId,
            ok: false,
            data: nil,
            error: BridgeFailure(code: "internal_error", message: error.localizedDescription)
        )
    }
}

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
        case .rendererAssetsMissing: "renderer_assets_missing"
        }
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

public struct IdeWindowState: Codable, Equatable, Sendable {
    public let openPaths: [String]
    public let activePath: String?
    public let bottomPanelOpen: Bool
    public let expandedDirectories: [String]

    public init(
        openPaths: [String],
        activePath: String?,
        bottomPanelOpen: Bool,
        expandedDirectories: [String] = []
    ) {
        self.openPaths = openPaths
        self.activePath = activePath
        self.bottomPanelOpen = bottomPanelOpen
        self.expandedDirectories = expandedDirectories
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

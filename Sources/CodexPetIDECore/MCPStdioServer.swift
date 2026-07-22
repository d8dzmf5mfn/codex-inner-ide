import Foundation

public enum MCPStdioServer {
    public static func run() -> Never {
        let server = Server()
        server.loop()
        exit(EXIT_SUCCESS)
    }

    private final class Server {
        private let bridge = LocalBridgeClient()
        private var attemptedLaunch = false

        func loop() {
            while let line = readLine() {
                guard let data = line.data(using: .utf8),
                      let message = try? JSONDecoder().decode(JSONValue.self, from: data),
                      let object = message.objectValue,
                      let method = object["method"]?.stringValue
                else { continue }
                let id = object["id"]
                if method.hasPrefix("notifications/") || id == nil { continue }
                let response: JSONValue
                do {
                    response = .object([
                        "jsonrpc": .string("2.0"),
                        "id": id ?? .null,
                        "result": try handle(method: method, params: object["params"] ?? .object([:]))
                    ])
                } catch {
                    response = .object([
                        "jsonrpc": .string("2.0"),
                        "id": id ?? .null,
                        "error": .object([
                            "code": .number(-32000),
                            "message": .string(error.localizedDescription)
                        ])
                    ])
                }
                write(response)
            }
        }

        private func handle(method: String, params: JSONValue) throws -> JSONValue {
            switch method {
            case "initialize":
                return .object([
                    "protocolVersion": .string(params["protocolVersion"]?.stringValue ?? "2025-06-18"),
                    "capabilities": .object([
                        "tools": .object(["listChanged": .bool(false)])
                    ]),
                    "serverInfo": .object([
                        "name": .string("codex-inner-edit"),
                        "version": .string("0.1.0")
                    ])
                ])
            case "ping":
                return .object([:])
            case "tools/list":
                return .object(["tools": .array(Self.tools)])
            case "tools/call":
                return try callTool(params)
            default:
                throw InnerIDEError.localBridgeUnavailable("unsupported MCP method: \(method)")
            }
        }

        private func callTool(_ params: JSONValue) throws -> JSONValue {
            guard let name = params["name"]?.stringValue else {
                return toolError("Tool name is required")
            }
            let arguments = params["arguments"] ?? .object([:])
            do {
                let data: JSONValue
                switch name {
                case "get_inner_ide_status":
                    data = try bridgeRequest(method: "mcp.status", params: .object([:]))
                case "propose_python_edit":
                    guard let instruction = arguments["instruction"]?.stringValue else {
                        return toolError("instruction is required")
                    }
                    let scope = arguments["scope"]?.stringValue ?? "auto"
                    guard ["auto", "selection", "file"].contains(scope) else {
                        return toolError("scope must be auto, selection, or file")
                    }
                    data = try bridgeRequest(method: "mcp.propose", params: .object([
                        "instruction": .string(instruction),
                        "scope": .string(scope)
                    ]))
                case "cancel_python_edit":
                    guard let proposalID = arguments["proposalId"]?.stringValue else {
                        return toolError("proposalId is required")
                    }
                    data = try bridgeRequest(method: "mcp.cancel", params: .object([
                        "proposalId": .string(proposalID)
                    ]))
                default:
                    return toolError("Unknown tool: \(name)")
                }
                let text = jsonText(data)
                return .object([
                    "content": .array([.object(["type": .string("text"), "text": .string(text)])]),
                    "structuredContent": data,
                    "isError": .bool(false)
                ])
            } catch {
                return toolError(error.localizedDescription)
            }
        }

        private func bridgeRequest(method: String, params: JSONValue) throws -> JSONValue {
            do {
                return try bridge.request(method: method, params: params)
            } catch {
                guard !attemptedLaunch else { throw error }
                attemptedLaunch = true
                try launchController()
                let deadline = Date().addingTimeInterval(5)
                var lastError: Error = error
                while Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                    do { return try bridge.request(method: method, params: params) }
                    catch { lastError = error }
                }
                throw lastError
            }
        }

        private func launchController() throws {
            let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            let bundle = executable
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = bundle.pathExtension == "app"
                ? [bundle.path]
                : ["-a", "Codex Inner IDE"]
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw InnerIDEError.localBridgeUnavailable("unable to launch Codex Inner IDE")
            }
        }

        private func toolError(_ message: String) -> JSONValue {
            .object([
                "content": .array([.object(["type": .string("text"), "text": .string(message)])]),
                "isError": .bool(true)
            ])
        }

        private func jsonText(_ value: JSONValue) -> String {
            guard let data = try? JSONEncoder().encode(value) else { return "{}" }
            return String(data: data, encoding: .utf8) ?? "{}"
        }

        private func write(_ value: JSONValue) {
            guard var data = try? JSONEncoder().encode(value) else { return }
            data.append(0x0A)
            try? FileHandle.standardOutput.write(contentsOf: data)
        }

        private static let tools: [JSONValue] = [
            .object([
                "name": .string("get_inner_ide_status"),
                "description": .string("Check whether Codex Inner IDE has an active editable Python document. Returns metadata only, never source code."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([:])
                ]),
                "annotations": .object([
                    "readOnlyHint": .bool(true),
                    "destructiveHint": .bool(false),
                    "idempotentHint": .bool(true)
                ])
            ]),
            .object([
                "name": .string("propose_python_edit"),
                "description": .string("Generate a read-only Codex proposal for the active Python selection or file. The user must accept it with Enter in Codex Inner IDE."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("instruction")]),
                    "properties": .object([
                        "instruction": .object([
                            "type": .string("string"),
                            "minLength": .number(1),
                            "maxLength": .number(Double(PythonEditValidator.maximumInstructionCharacters))
                        ]),
                        "scope": .object([
                            "type": .string("string"),
                            "enum": .array([.string("auto"), .string("selection"), .string("file")]),
                            "default": .string("auto")
                        ])
                    ])
                ]),
                "annotations": .object([
                    "readOnlyHint": .bool(true),
                    "destructiveHint": .bool(false),
                    "idempotentHint": .bool(false)
                ])
            ]),
            .object([
                "name": .string("cancel_python_edit"),
                "description": .string("Cancel the active Codex Inner IDE edit proposal without changing the editor or disk."),
                "inputSchema": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("proposalId")]),
                    "properties": .object([
                        "proposalId": .object(["type": .string("string")])
                    ])
                ]),
                "annotations": .object([
                    "readOnlyHint": .bool(true),
                    "destructiveHint": .bool(false),
                    "idempotentHint": .bool(true)
                ])
            ])
        ]
    }
}

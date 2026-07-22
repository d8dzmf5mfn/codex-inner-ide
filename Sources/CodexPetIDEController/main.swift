import AppKit
import CodexPetIDECore
import Foundation

if CommandLine.arguments.contains("--mcp-stdio") {
    MCPStdioServer.run()
} else {
    let application = NSApplication.shared
    let delegate = MainActor.assumeIsolated { AppDelegate() }
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}

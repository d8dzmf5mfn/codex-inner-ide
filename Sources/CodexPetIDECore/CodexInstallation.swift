import AppKit
import Foundation

public struct CompatibilityProfile: Codable, Equatable, Sendable {
    public let appVersion: String
    public let codexCLIVersionPrefix: String
    public let rendererProfile: String

    public init(
        appVersion: String,
        codexCLIVersionPrefix: String,
        rendererProfile: String = "desktop-v1"
    ) {
        self.appVersion = appVersion
        self.codexCLIVersionPrefix = codexCLIVersionPrefix
        self.rendererProfile = rendererProfile
    }

    public static let validated: [CompatibilityProfile] = [
        CompatibilityProfile(
            appVersion: "26.715.70719",
            codexCLIVersionPrefix: "codex-cli 0.145.0-alpha.27"
        ),
        CompatibilityProfile(
            appVersion: "26.715.71837",
            codexCLIVersionPrefix: "codex-cli 0.145.0-alpha.30"
        ),
        CompatibilityProfile(
            appVersion: "26.715.72028",
            codexCLIVersionPrefix: "codex-cli 0.145.0-alpha.30"
        )
    ]

    public static func match(appVersion: String, codexCLIVersion: String) -> CompatibilityProfile? {
        validated.first {
            $0.appVersion == appVersion && codexCLIVersion.hasPrefix($0.codexCLIVersionPrefix)
        }
    }
}

public struct CodexInstallation: Equatable, Sendable {
    public static let bundleIdentifier = "com.openai.codex"

    public let appURL: URL
    public let executableURL: URL
    public let codexURL: URL
    public let appVersion: String

    public static func detect(
        appURL: URL = URL(fileURLWithPath: "/Applications/ChatGPT.app")
    ) throws -> CodexInstallation {
        guard let bundle = Bundle(url: appURL),
              bundle.bundleIdentifier == bundleIdentifier,
              let executableURL = bundle.executableURL,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        else {
            throw InnerIDEError.cdpUnavailable("Codex Desktop was not found at \(appURL.path)")
        }
        let codexURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("codex", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: codexURL.path) else {
            throw InnerIDEError.appServerUnavailable("bundled codex binary is missing")
        }
        return CodexInstallation(
            appURL: appURL,
            executableURL: executableURL,
            codexURL: codexURL,
            appVersion: version
        )
    }

    public var compatibilityProfile: CompatibilityProfile? {
        CompatibilityProfile.validated.first { $0.appVersion == appVersion }
    }

    public func codexCLIVersion() throws -> String {
        let process = Process()
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = codexURL
        process.arguments = ["--version"]
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
        } catch {
            throw InnerIDEError.appServerUnavailable("could not inspect bundled Codex CLI: \(error.localizedDescription)")
        }
        process.waitUntilExit()
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        let errorOutput = stderr.fileHandleForReading.readDataToEndOfFile()
        let version = String(data: output, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0, !version.isEmpty else {
            let detail = String(data: errorOutput, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown error"
            throw InnerIDEError.appServerUnavailable("could not inspect bundled Codex CLI: \(detail)")
        }
        return version
    }

    @discardableResult
    public func validateCompatibility() throws -> CompatibilityProfile {
        guard let appProfile = compatibilityProfile else {
            throw InnerIDEError.unsupportedCodexVersion(appVersion)
        }
        let cliVersion = try codexCLIVersion()
        guard let matched = CompatibilityProfile.match(
            appVersion: appVersion,
            codexCLIVersion: cliVersion
        ) else {
            throw InnerIDEError.unsupportedCodexCLIVersion(
                actual: cliVersion,
                expected: appProfile.codexCLIVersionPrefix
            )
        }
        return matched
    }
}

@MainActor
public final class CodexLauncher {
    public private(set) var launchedPort: Int?
    public private(set) var launchedApplication: NSRunningApplication?

    public init() {}

    public var runningApplications: [NSRunningApplication] {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: CodexInstallation.bundleIdentifier
        )
    }

    public func terminateRunningApplications(timeout: TimeInterval = 10) async -> Bool {
        let applications = runningApplications
        guard !applications.isEmpty else { return true }
        applications.forEach { _ = $0.terminate() }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningApplications.isEmpty { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return false
    }

    public func launch(_ installation: CodexInstallation, port: Int) async throws {
        try installation.validateCompatibility()
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [
            "--remote-debugging-address=127.0.0.1",
            "--remote-debugging-port=\(port)"
        ]
        configuration.activates = true
        let application = try await NSWorkspace.shared.openApplication(
            at: installation.appURL,
            configuration: configuration
        )
        launchedPort = port
        launchedApplication = application
    }
}

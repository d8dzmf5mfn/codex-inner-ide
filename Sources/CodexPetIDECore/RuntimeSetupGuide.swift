import Foundation

public enum RuntimeSetupGuide {
    public static let pythonDownloadURL = "https://www.python.org/downloads/macos/"
    public static let nodeDownloadURL = "https://nodejs.org/en/download"
    public static let javaDownloadURL = "https://adoptium.net/temurin/releases/?os=mac&arch=any"

    public static func options(
        languageID: String,
        homebrewAvailable: Bool,
        nodeAvailable: Bool = true
    ) -> [RuntimeSetupOption] {
        switch languageID {
        case "python":
            return systemOption(
                id: "python",
                label: "Install Python",
                brewCommand: "brew install python",
                downloadURL: pythonDownloadURL,
                description: "Installs a system Python interpreter.",
                homebrewAvailable: homebrewAvailable
            )
        case "java":
            return systemOption(
                id: "java",
                label: "Install a Java JDK",
                brewCommand: "brew install openjdk",
                downloadURL: javaDownloadURL,
                description: "Installs a JDK that includes javac and java.",
                homebrewAvailable: homebrewAvailable
            )
        case "javascript":
            return nodeOptions(homebrewAvailable: homebrewAvailable)
        case "typescript":
            if !nodeAvailable {
                return nodeOptions(homebrewAvailable: homebrewAvailable).map { option in
                    RuntimeSetupOption(
                        id: "typescript-\(option.id)",
                        label: "Install Node.js first",
                        command: option.command,
                        downloadURL: option.downloadURL,
                        scope: option.scope,
                        description: "TypeScript setup requires Node.js. \(option.description)"
                    )
                }
            }
            return [RuntimeSetupOption(
                id: "typescript-workspace",
                label: "Add TypeScript to this Workspace",
                command: "npm install --save-dev typescript tsx",
                scope: .workspace,
                description: "Installs TypeScript and tsx in the current Workspace only."
            )]
        default:
            return []
        }
    }

    public static func homebrewExecutable(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        var candidates = [
            URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
            URL(fileURLWithPath: "/usr/local/bin/brew")
        ]
        candidates.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("brew") })
        var seen = Set<String>()
        return candidates.first { candidate in
            let path = candidate.standardizedFileURL.path
            return seen.insert(path).inserted && fileManager.isExecutableFile(atPath: path)
        }
    }

    public static func javaCompilerCandidates(
        workspaceRoot: URL,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> [URL] {
        var candidates: [URL] = []
        if let javaHome = environment["JAVA_HOME"], !javaHome.isEmpty {
            candidates.append(URL(fileURLWithPath: javaHome).appendingPathComponent("bin/javac"))
        }
        candidates.append(workspaceRoot.appendingPathComponent(".jdk/bin/javac"))
        let virtualMachines = URL(fileURLWithPath: "/Library/Java/JavaVirtualMachines", isDirectory: true)
        if let installations = try? fileManager.contentsOfDirectory(
            at: virtualMachines,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            candidates.append(contentsOf: installations.map {
                $0.appendingPathComponent("Contents/Home/bin/javac")
            })
        }
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/opt/openjdk/bin/javac"))
        candidates.append(URL(fileURLWithPath: "/usr/local/opt/openjdk/bin/javac"))
        candidates.append(contentsOf: (environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("javac") })
        return candidates
    }

    private static func nodeOptions(homebrewAvailable: Bool) -> [RuntimeSetupOption] {
        systemOption(
            id: "node",
            label: "Install Node.js",
            brewCommand: "brew install node",
            downloadURL: nodeDownloadURL,
            description: "Installs Node.js and npm.",
            homebrewAvailable: homebrewAvailable
        )
    }

    private static func systemOption(
        id: String,
        label: String,
        brewCommand: String,
        downloadURL: String,
        description: String,
        homebrewAvailable: Bool
    ) -> [RuntimeSetupOption] {
        if homebrewAvailable {
            return [RuntimeSetupOption(
                id: "\(id)-homebrew",
                label: "\(label) with Homebrew",
                command: brewCommand,
                scope: .system,
                description: description
            )]
        }
        return [RuntimeSetupOption(
            id: "\(id)-download",
            label: "\(label) from the official site",
            downloadURL: downloadURL,
            scope: .system,
            description: description
        )]
    }
}

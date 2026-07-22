import CodexPetIDECore
import Foundation

struct WorkspaceStateStore {
    private let fileManager: FileManager
    private let defaults: UserDefaults

    init(fileManager: FileManager = .default, defaults: UserDefaults = .standard) {
        self.fileManager = fileManager
        self.defaults = defaults
    }

    func cachedWorkspace(for taskKey: String) -> URL? {
        guard !taskKey.isEmpty,
              let path = defaults.string(forKey: taskWorkspaceKey(taskKey))
        else { return nil }
        return URL(fileURLWithPath: path)
    }

    func lastWorkspace() -> URL? {
        defaults.string(forKey: "lastWorkspace").map(URL.init(fileURLWithPath:))
    }

    func recordWorkspace(_ url: URL, taskKey: String) {
        defaults.set(url.path, forKey: "lastWorkspace")
        if !taskKey.isEmpty {
            defaults.set(url.path, forKey: taskWorkspaceKey(taskKey))
        }
    }

    func isDirectory(_ url: URL) -> Bool {
        var value: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &value) && value.boolValue
    }

    func loadWindowState(workspaceID: String) throws -> JSONValue {
        let current = stateURL(workspaceID: workspaceID, legacy: false)
        let legacy = stateURL(workspaceID: workspaceID, legacy: true)
        let url = fileManager.fileExists(atPath: current.path) ? current : legacy
        guard fileManager.fileExists(atPath: url.path) else { return .null }
        return try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: url))
    }

    func saveWindowState(_ state: JSONValue, workspaceID: String) throws {
        try fileManager.createDirectory(at: applicationSupportURL, withIntermediateDirectories: true)
        try JSONEncoder().encode(state).write(
            to: stateURL(workspaceID: workspaceID, legacy: false),
            options: [.atomic]
        )
    }

    private var applicationSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexInnerIDE", isDirectory: true)
    }

    private var legacyApplicationSupportURL: URL {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexPetIDE", isDirectory: true)
    }

    private func stateURL(workspaceID: String, legacy: Bool) -> URL {
        (legacy ? legacyApplicationSupportURL : applicationSupportURL)
            .appendingPathComponent("state-\(workspaceID).json")
    }

    private func taskWorkspaceKey(_ taskKey: String) -> String {
        "workspace.\(WorkspaceService.sha256(Data(taskKey.utf8)))"
    }
}

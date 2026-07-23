import Foundation

public final class RecentWorkspaceStore: @unchecked Sendable {
    public static let maximumCount = 10

    private struct Record: Codable, Equatable {
        let id: String
        let path: String
        let name: String
        let rootLabel: String
    }

    private let fileManager: FileManager
    private let defaults: UserDefaults
    private let storageKey: String
    private let lock = NSLock()

    public init(
        fileManager: FileManager = .default,
        defaults: UserDefaults = .standard,
        storageKey: String = "CodexInnerIDE.RecentWorkspaces.v1"
    ) {
        self.fileManager = fileManager
        self.defaults = defaults
        self.storageKey = storageKey
    }

    public func list() -> [RecentWorkspace] {
        lock.withLock {
            loadRecords().map { record in
                RecentWorkspace(
                    id: record.id,
                    name: record.name,
                    rootLabel: record.rootLabel,
                    available: isDirectory(URL(fileURLWithPath: record.path))
                )
            }
        }
    }

    @discardableResult
    public func record(_ url: URL) throws -> RecentWorkspace {
        let standardized = url.standardizedFileURL.resolvingSymlinksInPath()
        guard isDirectory(standardized) else { throw InnerIDEError.workspaceUnavailable }
        let value = makeRecord(standardized)
        lock.withLock {
            var records = loadRecords().filter { $0.id != value.id }
            records.insert(value, at: 0)
            saveRecords(Array(records.prefix(Self.maximumCount)))
        }
        return RecentWorkspace(
            id: value.id,
            name: value.name,
            rootLabel: value.rootLabel,
            available: true
        )
    }

    public func authorizedURL(for id: String) -> URL? {
        lock.withLock {
            guard let record = loadRecords().first(where: { $0.id == id }) else { return nil }
            return URL(fileURLWithPath: record.path)
        }
    }

    public func remove(id: String) {
        lock.withLock {
            saveRecords(loadRecords().filter { $0.id != id })
        }
    }

    @discardableResult
    public func replace(id: String, with url: URL) throws -> RecentWorkspace {
        let replacement = try record(url)
        if replacement.id != id { remove(id: id) }
        return replacement
    }

    private func makeRecord(_ url: URL) -> Record {
        Record(
            id: WorkspaceService.sha256(Data(url.path.utf8)),
            path: url.path,
            name: url.lastPathComponent,
            rootLabel: url.deletingLastPathComponent().lastPathComponent + "/" + url.lastPathComponent
        )
    }

    private func isDirectory(_ url: URL) -> Bool {
        var value: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &value) && value.boolValue
    }

    private func loadRecords() -> [Record] {
        guard let data = defaults.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([Record].self, from: data)
        else { return [] }
        var seen = Set<String>()
        return records.filter { !$0.id.isEmpty && !$0.path.isEmpty && seen.insert($0.id).inserted }
    }

    private func saveRecords(_ records: [Record]) {
        defaults.set(try? JSONEncoder().encode(records), forKey: storageKey)
    }
}

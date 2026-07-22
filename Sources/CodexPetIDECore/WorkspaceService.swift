import AppKit
import CryptoKit
import Foundation

public final class WorkspaceService: @unchecked Sendable {
    public static let maximumEditableBytes = 5 * 1024 * 1024

    public let rootURL: URL
    public let binding: WorkspaceBinding

    private let fileManager: FileManager
    private let resolvedRootPath: String

    public init(rootURL: URL, fileManager: FileManager = .default) throws {
        let standardized = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            throw InnerIDEError.workspaceUnavailable
        }
        self.rootURL = standardized
        self.fileManager = fileManager
        self.resolvedRootPath = standardized.path
        let id = Self.sha256(Data(standardized.path.utf8))
        self.binding = WorkspaceBinding(
            id: id,
            name: standardized.lastPathComponent,
            rootLabel: standardized.deletingLastPathComponent().lastPathComponent + "/" + standardized.lastPathComponent
        )
    }

    public func list(relativePath: String = "") throws -> [FileEntry] {
        let directory = try existingURL(relativePath: relativePath, expectedDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .nameKey]
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )
        return try children.compactMap { child in
            let values = try child.resourceValues(forKeys: keys)
            guard values.isDirectory == true || values.isRegularFile == true else { return nil }
            _ = try ensureContained(child.resolvingSymlinksInPath())
            let relative = relativePath.isEmpty ? child.lastPathComponent : relativePath + "/" + child.lastPathComponent
            return FileEntry(
                name: child.lastPathComponent,
                relativePath: relative,
                kind: values.isDirectory == true ? .directory : .file
            )
        }.sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind == .directory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    public func read(relativePath: String) throws -> FileSnapshot {
        let file = try existingURL(relativePath: relativePath, expectedDirectory: false)
        let attributes = try fileManager.attributesOfItem(atPath: file.path)
        let size = (attributes[.size] as? NSNumber)?.intValue ?? 0
        if size > Self.maximumEditableBytes {
            return FileSnapshot(
                relativePath: relativePath,
                content: "",
                digest: metadataDigest(attributes: attributes),
                readonly: true,
                readonlyReason: "File is larger than 5 MB"
            )
        }

        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        if data.prefix(8_192).contains(0) {
            return FileSnapshot(
                relativePath: relativePath,
                content: "",
                digest: Self.sha256(data),
                readonly: true,
                readonlyReason: "Binary file"
            )
        }
        guard let content = String(data: data, encoding: .utf8) else {
            return FileSnapshot(
                relativePath: relativePath,
                content: "",
                digest: Self.sha256(data),
                readonly: true,
                readonlyReason: "File is not valid UTF-8"
            )
        }
        return FileSnapshot(
            relativePath: relativePath,
            content: content,
            digest: Self.sha256(data),
            readonly: false
        )
    }

    public func write(_ request: WriteFileRequest) throws -> FileSnapshot {
        let file = try existingURL(relativePath: request.relativePath, expectedDirectory: false)
        let current = try read(relativePath: request.relativePath)
        guard !current.readonly else {
            throw current.readonlyReason == "Binary file"
                ? InnerIDEError.binaryFile(request.relativePath)
                : InnerIDEError.fileTooLarge(request.relativePath)
        }
        guard current.digest == request.expectedDigest else {
            throw InnerIDEError.fileChanged(request.relativePath)
        }
        guard let data = request.content.data(using: .utf8), data.count <= Self.maximumEditableBytes else {
            throw InnerIDEError.fileTooLarge(request.relativePath)
        }

        let attributes = try fileManager.attributesOfItem(atPath: file.path)
        try data.write(to: file, options: [.atomic])
        if let permissions = attributes[.posixPermissions] {
            try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path)
        }
        return try read(relativePath: request.relativePath)
    }

    public func create(relativePath: String, kind: FileKind) throws -> FileEntry {
        let target = try newTargetURL(relativePath: relativePath)
        guard !fileManager.fileExists(atPath: target.path) else {
            throw InnerIDEError.bridgeRejected("Target already exists")
        }
        switch kind {
        case .file:
            guard fileManager.createFile(atPath: target.path, contents: Data()) else {
                throw InnerIDEError.commandFailed("Could not create (relativePath)")
            }
        case .directory:
            try fileManager.createDirectory(at: target, withIntermediateDirectories: false)
        }
        return FileEntry(name: target.lastPathComponent, relativePath: relativePath, kind: kind)
    }

    public func rename(from relativePath: String, to newRelativePath: String) throws -> FileEntry {
        let source = try operationURL(relativePath: relativePath)
        let destination = try newTargetURL(relativePath: newRelativePath)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw InnerIDEError.bridgeRejected("Target already exists")
        }
        let values = try source.resourceValues(forKeys: [.isDirectoryKey])
        try fileManager.moveItem(at: source, to: destination)
        return FileEntry(
            name: destination.lastPathComponent,
            relativePath: newRelativePath,
            kind: values.isDirectory == true ? .directory : .file
        )
    }

    @MainActor
    public func moveToTrash(relativePath: String) throws {
        let target = try operationURL(relativePath: relativePath)
        var resultingURL: NSURL?
        try fileManager.trashItem(at: target, resultingItemURL: &resultingURL)
    }

    public func isContained(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        return path == resolvedRootPath || path.hasPrefix(resolvedRootPath + "/")
    }

    private func existingURL(relativePath: String, expectedDirectory: Bool?) throws -> URL {
        let target = try lexicalURL(relativePath: relativePath)
        guard fileManager.fileExists(atPath: target.path) else {
            throw InnerIDEError.invalidRelativePath(relativePath)
        }
        let resolved = target.resolvingSymlinksInPath()
        _ = try ensureContained(resolved)
        if let expectedDirectory {
            var isDirectory: ObjCBool = false
            fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory)
            guard isDirectory.boolValue == expectedDirectory else {
                throw InnerIDEError.invalidRelativePath(relativePath)
            }
        }
        return resolved
    }

    private func newTargetURL(relativePath: String) throws -> URL {
        let target = try lexicalURL(relativePath: relativePath)
        guard !target.lastPathComponent.isEmpty,
              target.lastPathComponent != ".",
              target.lastPathComponent != "..",
              !target.lastPathComponent.contains("/")
        else {
            throw InnerIDEError.invalidRelativePath(relativePath)
        }
        let parent = target.deletingLastPathComponent().resolvingSymlinksInPath()
        _ = try ensureContained(parent)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw InnerIDEError.invalidRelativePath(relativePath)
        }
        return target
    }

    private func operationURL(relativePath: String) throws -> URL {
        guard !relativePath.isEmpty else { throw InnerIDEError.invalidRelativePath(relativePath) }
        let lexical = try lexicalURL(relativePath: relativePath)
        guard fileManager.fileExists(atPath: lexical.path) else {
            throw InnerIDEError.invalidRelativePath(relativePath)
        }
        _ = try ensureContained(lexical.resolvingSymlinksInPath())
        return lexical
    }

    private func lexicalURL(relativePath: String) throws -> URL {
        guard !relativePath.hasPrefix("/"), !relativePath.contains("\\"), !relativePath.contains("\0") else {
            throw InnerIDEError.invalidRelativePath(relativePath)
        }
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.contains(where: { $0 == ".." || $0.isEmpty && !relativePath.isEmpty }) else {
            throw InnerIDEError.invalidRelativePath(relativePath)
        }
        return rootURL.appendingPathComponent(relativePath, isDirectory: false).standardizedFileURL
    }

    @discardableResult
    private func ensureContained(_ url: URL) throws -> URL {
        guard isContained(url) else { throw InnerIDEError.pathEscapesWorkspace(url.path) }
        return url
    }

    private func metadataDigest(attributes: [FileAttributeKey: Any]) -> String {
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modification = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return Self.sha256(Data("readonly:\(size):\(modification)".utf8))
    }

    public static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

public final class WorkspaceWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable ([FileChange]) -> Void

    private let rootURL: URL
    private let handler: Handler
    private let queue = DispatchQueue(label: "com.openai.codex-inner-ide.fsevents")
    private var stream: FSEventStreamRef?

    public init(rootURL: URL, handler: @escaping Handler) {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        self.handler = handler
    }

    public func start() throws {
        guard stream == nil else { return }
        let context = UnsafeMutablePointer<FSEventStreamContext>.allocate(capacity: 1)
        context.initialize(to: FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        ))
        let callback: FSEventStreamCallback = { _, info, count, pathsPointer, flagsPointer, _ in
            guard let info else { return }
            let watcher = Unmanaged<WorkspaceWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
            var changes: [FileChange] = []
            changes.reserveCapacity(count)
            for index in 0..<min(count, paths.count) {
                let path = paths[index]
                guard path.hasPrefix(watcher.rootURL.path + "/") else { continue }
                let relativePath = String(path.dropFirst(watcher.rootURL.path.count + 1))
                let flags = flagsPointer[index]
                let kind: String
                if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 { kind = "deleted" }
                else if flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 { kind = "created" }
                else { kind = "changed" }
                changes.append(FileChange(relativePath: relativePath, kind: kind, source: "external"))
            }
            if !changes.isEmpty { watcher.handler(changes) }
        }
        guard let created = FSEventStreamCreate(
            nil,
            callback,
            context,
            [rootURL.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.2,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            context.deinitialize(count: 1)
            context.deallocate()
            throw InnerIDEError.commandFailed("Unable to start workspace file monitoring")
        }
        stream = created
        FSEventStreamSetDispatchQueue(created, queue)
        FSEventStreamStart(created)
        context.deinitialize(count: 1)
        context.deallocate()
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }
}

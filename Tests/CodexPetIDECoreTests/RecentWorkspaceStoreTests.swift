import CodexPetIDECore
import Foundation
import XCTest

final class RecentWorkspaceStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!
    private var rootURL: URL!

    override func setUpWithError() throws {
        suiteName = "RecentWorkspaceStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodexInnerIDERecentTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL { try? FileManager.default.removeItem(at: rootURL) }
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        rootURL = nil
    }

    func testDeduplicatesAndLimitsRecentWorkspacesToTen() throws {
        let store = makeStore()
        var urls: [URL] = []
        for index in 0..<12 {
            let url = rootURL.appendingPathComponent("workspace-\(index)", isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            urls.append(url)
            try store.record(url)
        }

        XCTAssertEqual(store.list().count, 10)
        XCTAssertEqual(store.list().first?.name, "workspace-11")
        try store.record(urls[5])
        XCTAssertEqual(store.list().count, 10)
        XCTAssertEqual(store.list().first?.name, "workspace-5")
    }

    func testMarksMissingDirectoriesUnavailableWithoutExposingArbitraryPaths() throws {
        let store = makeStore()
        let url = rootURL.appendingPathComponent("movable", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let recorded = try store.record(url)
        XCTAssertEqual(store.authorizedURL(for: recorded.id)?.path, url.path)
        XCTAssertNil(store.authorizedURL(for: "untrusted-id"))

        try FileManager.default.removeItem(at: url)
        XCTAssertEqual(store.list(), [RecentWorkspace(
            id: recorded.id,
            name: "movable",
            rootLabel: "\(rootURL.lastPathComponent)/movable",
            available: false
        )])
    }

    func testReplacesAndRemovesRecentWorkspaceAuthorization() throws {
        let store = makeStore()
        let oldURL = rootURL.appendingPathComponent("old", isDirectory: true)
        let newURL = rootURL.appendingPathComponent("new", isDirectory: true)
        try FileManager.default.createDirectory(at: oldURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: newURL, withIntermediateDirectories: true)
        let old = try store.record(oldURL)
        let replacement = try store.replace(id: old.id, with: newURL)

        XCTAssertNil(store.authorizedURL(for: old.id))
        XCTAssertEqual(store.authorizedURL(for: replacement.id)?.path, newURL.path)
        store.remove(id: replacement.id)
        XCTAssertTrue(store.list().isEmpty)
    }

    private func makeStore() -> RecentWorkspaceStore {
        RecentWorkspaceStore(
            defaults: defaults,
            storageKey: "recent-workspaces"
        )
    }
}

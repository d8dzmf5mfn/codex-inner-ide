import Foundation
import XCTest
@testable import CodexPetIDECore

final class GlobalPreferencesStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "CodexInnerIDE-Preferences-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsToAutomaticThemeAndNoSnippets() {
        let value = GlobalPreferencesStore(defaults: defaults).load()
        XCTAssertEqual(value, GlobalPreferences(themeMode: .auto, completionSnippets: []))
    }

    func testPersistsAndNormalizesGlobalCompletionSnippets() throws {
        let store = GlobalPreferencesStore(defaults: defaults)
        let valid = UserCompletionSnippet(
            id: "print-debug",
            languageId: "python",
            triggerPrefix: "pr",
            displayName: "Print debug value",
            description: "Local debug helper",
            body: "print(\"${1:value}\")"
        )
        let invalid = UserCompletionSnippet(
            id: "unsupported",
            languageId: "unsupported",
            triggerPrefix: "x",
            displayName: "Unsupported",
            description: "",
            body: "x"
        )

        let saved = try store.save(GlobalPreferences(
            themeMode: .dark,
            completionSnippets: [valid, valid, invalid]
        ))

        XCTAssertEqual(saved.themeMode, .dark)
        XCTAssertEqual(saved.completionSnippets, [valid])
        XCTAssertEqual(store.load(), saved)
    }

    func testRecoversFromCorruptStoredPreferences() {
        defaults.set(Data("invalid".utf8), forKey: GlobalPreferencesStore.storageKey)
        XCTAssertEqual(GlobalPreferencesStore(defaults: defaults).load(), GlobalPreferences())
    }
}

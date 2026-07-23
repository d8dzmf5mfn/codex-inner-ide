import Foundation

public final class GlobalPreferencesStore: @unchecked Sendable {
    public static let storageKey = "CodexInnerIDE.GlobalPreferences.v1"
    private static let supportedLanguages = Set([
        "python", "java", "html", "typescript", "javascript", "css", "json", "markdown", "plaintext"
    ])

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> GlobalPreferences {
        lock.lock()
        defer { lock.unlock() }
        guard let data = defaults.data(forKey: Self.storageKey),
              let value = try? decoder.decode(GlobalPreferences.self, from: data)
        else { return GlobalPreferences() }
        return normalized(value)
    }

    @discardableResult
    public func save(_ preferences: GlobalPreferences) throws -> GlobalPreferences {
        lock.lock()
        defer { lock.unlock() }
        let value = normalized(preferences)
        defaults.set(try encoder.encode(value), forKey: Self.storageKey)
        return value
    }

    private func normalized(_ preferences: GlobalPreferences) -> GlobalPreferences {
        var seen = Set<String>()
        let snippets = preferences.completionSnippets.prefix(200).compactMap { snippet -> UserCompletionSnippet? in
            let id = bounded(snippet.id, limit: 120)
            let languageID = bounded(snippet.languageId, limit: 32)
            let prefix = bounded(snippet.triggerPrefix, limit: 64).trimmingCharacters(in: .whitespacesAndNewlines)
            let name = bounded(snippet.displayName, limit: 120).trimmingCharacters(in: .whitespacesAndNewlines)
            let description = bounded(snippet.description, limit: 500)
            let body = bounded(snippet.body, limit: 20_000)
            guard !id.isEmpty,
                  seen.insert(id).inserted,
                  Self.supportedLanguages.contains(languageID),
                  !prefix.isEmpty,
                  !name.isEmpty,
                  !body.isEmpty
            else { return nil }
            return UserCompletionSnippet(
                id: id,
                languageId: languageID,
                triggerPrefix: prefix,
                displayName: name,
                description: description,
                body: body
            )
        }
        return GlobalPreferences(themeMode: preferences.themeMode, completionSnippets: snippets)
    }

    private func bounded(_ value: String, limit: Int) -> String {
        String(value.prefix(limit))
    }
}

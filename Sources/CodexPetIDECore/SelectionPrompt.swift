import Foundation

public struct SelectionRange: Codable, Equatable, Sendable {
    public let startLine: Int
    public let startColumn: Int
    public let endLine: Int
    public let endColumn: Int
}

public struct IdeSelectionContext: Codable, Equatable, Sendable {
    public let workspaceId: String
    public let relativePath: String
    public let language: String
    public let range: SelectionRange
    public let selectedText: String
    public let surroundingText: String
    public let dirty: Bool
}

public enum HandoffDestination: String, Codable, Equatable, Sendable {
    case codex
    case chatgpt
}

public enum HandoffMechanism: String, Codable, Equatable, Sendable {
    case composer
    case quickChatShortcut
    case compatibilitySignal
    case clipboard
}

public struct HandoffResult: Codable, Equatable, Sendable {
    public let destination: HandoffDestination
    public let mechanism: HandoffMechanism
    public let submitted: Bool

    public init(destination: HandoffDestination, mechanism: HandoffMechanism) {
        self.destination = destination
        self.mechanism = mechanism
        self.submitted = false
    }
}

public enum SelectionPrompt {
    public static let maximumSelectionCharacters = 40_000

    public static func renderForCodex(_ context: IdeSelectionContext) throws -> String {
        try validate(context)
        return render(
            context,
            heading: "IDE selection",
            instruction: "Use this selected code as context for my next request."
        )
    }

    public static func renderForChatGPT(_ context: IdeSelectionContext) throws -> String {
        try validate(context)
        return render(
            context,
            heading: "Python code selection",
            instruction: "Tell me more about this Python code selection."
        )
    }

    private static func validate(_ context: IdeSelectionContext) throws {
        guard !context.selectedText.isEmpty else {
            throw InnerIDEError.bridgeRejected("Selection is empty")
        }
        guard context.selectedText.count <= maximumSelectionCharacters else {
            throw InnerIDEError.bridgeRejected("Selection exceeds 40,000 characters")
        }
    }

    private static func render(
        _ context: IdeSelectionContext,
        heading: String,
        instruction: String
    ) -> String {
        let range = "L\(context.range.startLine):\(context.range.startColumn)-L\(context.range.endLine):\(context.range.endColumn)"
        return """
        # \(heading)

        - File: `\(context.relativePath)`
        - Range: \(range)
        - Language: \(context.language)
        - Unsaved buffer: \(context.dirty ? "yes" : "no")

        \(instruction)

        ```\(context.language)
        \(context.selectedText)
        ```

        Surrounding context:

        ```\(context.language)
        \(context.surroundingText)
        ```
        """
    }
}

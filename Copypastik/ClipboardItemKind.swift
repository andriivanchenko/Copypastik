import Foundation

private enum ClipboardHeuristics {
    static let webLinkPrefixes = ["http://", "https://"]
    static let terminalPromptPrefixes = ["$ ", "> "]
    static let shellCommandPrefixes = ["git ", "npm ", "pnpm ", "yarn ", "swift ", "xcodebuild ", "curl ", "uv ", "cd ", "mkdir ", "rm "]
    static let pathIndicators = ["/", "\\", ".swift", ".json", ".md", ".js", ".ts", ".py", ".sh", ".env"]
    static let codeSymbols = [" = ", " == ", " != ", "->", "::", "()", " && ", " || "]

    static func hasWebLinkPrefix(_ lowercasedText: String) -> Bool {
        webLinkPrefixes.contains(where: { lowercasedText.hasPrefix($0) })
    }

    static func hasCommandPrefix(_ lowercasedText: String, includePromptPrefixes: Bool) -> Bool {
        if includePromptPrefixes,
           terminalPromptPrefixes.contains(where: { lowercasedText.hasPrefix($0) }) {
            return true
        }
        return shellCommandPrefixes.contains(where: { lowercasedText.hasPrefix($0) })
    }

    static func hasPathIndicator(_ text: String) -> Bool {
        pathIndicators.contains(where: { text.contains($0) })
    }

    static func hasCodeSymbol(_ text: String) -> Bool {
        codeSymbols.contains(where: { text.contains($0) })
    }
}

enum ClipboardSnippetDetector {
    static func isCodeLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return false }

        let lowercased = trimmed.lowercased()
        if ClipboardHeuristics.hasWebLinkPrefix(lowercased) {
            return true
        }

        if ClipboardHeuristics.hasCommandPrefix(lowercased, includePromptPrefixes: true) ||
            trimmed.hasPrefix("./") ||
            trimmed.hasPrefix("~/") {
            return true
        }

        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return true
        }

        if ClipboardHeuristics.hasPathIndicator(trimmed) && !trimmed.contains(" ") {
            return true
        }

        return ClipboardHeuristics.hasCodeSymbol(trimmed)
    }
}

enum ClipboardItemKind: String, CaseIterable {
    case command
    case link
    case code
    case multiline
    case text
    case image

    var displayName: String {
        switch self {
        case .command:
            return "Command"
        case .link:
            return "Link"
        case .code:
            return "Code"
        case .multiline, .text:
            return "Text"
        case .image:
            return "Image"
        }
    }

    var symbolName: String {
        switch self {
        case .command:
            return "terminal"
        case .link:
            return "link"
        case .code:
            return "curlybraces"
        case .multiline:
            return "text.alignleft"
        case .text:
            return "text.quote"
        case .image:
            return "photo"
        }
    }

    var usesMonospacedPreview: Bool {
        switch self {
        case .command, .code:
            return true
        case .link, .multiline, .text, .image:
            return false
        }
    }

    static func detect(_ text: String) -> ClipboardItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if ClipboardHeuristics.hasWebLinkPrefix(lowercased) {
            return .link
        }

        if trimmed.contains(where: \.isNewline) {
            return .multiline
        }

        if ClipboardHeuristics.hasCommandPrefix(lowercased, includePromptPrefixes: true) {
            return .command
        }

        if ClipboardSnippetDetector.isCodeLike(text) {
            return .code
        }

        return .text
    }
}

/// Coarse-grained type used by picker filter chips and `type:` search syntax.
/// Distinct from `ClipboardItemKind` because "Text" chip intentionally covers
/// both single-line and multiline plain text.
enum PickerTypeFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case link
    case image
    case code
    case command

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .link:
            return "Links"
        case .image:
            return "Images"
        case .code:
            return "Code"
        case .command:
            return "Commands"
        }
    }

    var symbolName: String {
        switch self {
        case .all:
            return "square.grid.2x2"
        case .text:
            return "text.quote"
        case .link:
            return "link"
        case .image:
            return "photo"
        case .code:
            return "curlybraces"
        case .command:
            return "terminal"
        }
    }

    /// Value matched against the `type:` search token, e.g. `type:image`.
    var queryToken: String {
        rawValue
    }

    static func fromQueryToken(_ token: String) -> PickerTypeFilter? {
        PickerTypeFilter(rawValue: token.lowercased())
    }

    func matches(_ kind: ClipboardItemKind) -> Bool {
        switch self {
        case .all:
            return true
        case .text:
            return kind == .text || kind == .multiline
        case .link:
            return kind == .link
        case .image:
            return kind == .image
        case .code:
            return kind == .code
        case .command:
            return kind == .command
        }
    }
}

import Foundation

/// Parses the picker search field into its constituent filters:
///
/// - `#tag` — tagged snippet filter
/// - `@app` — source app name/bundle id filter
/// - `type:image|link|code|command|text` — coarse content-type filter
/// - remaining words — plain-text search
///
/// All filters combine with AND semantics and are matched case-insensitively.
struct PickerSearchQuery: Equatable {
    let tags: [String]
    let appQueries: [String]
    let typeFilter: PickerTypeFilter?
    let text: String

    init(_ rawQuery: String) {
        let tokens = rawQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        var tagTokens: [String] = []
        var appTokens: [String] = []
        var textTokens: [String] = []
        var parsedTypeFilter: PickerTypeFilter?

        for token in tokens {
            if token.hasPrefix("#"), token.count > 1 {
                tagTokens.append(String(token.dropFirst()))
            } else if token.hasPrefix("@"), token.count > 1 {
                appTokens.append(String(token.dropFirst()))
            } else if token.lowercased().hasPrefix("type:"), token.count > "type:".count {
                let value = String(token.dropFirst("type:".count))
                if let filter = PickerTypeFilter.fromQueryToken(value) {
                    parsedTypeFilter = filter
                } else {
                    textTokens.append(token)
                }
            } else {
                textTokens.append(token)
            }
        }

        tags = TagRules.normalize(tagTokens)
        appQueries = appTokens
        typeFilter = parsedTypeFilter
        text = textTokens.joined(separator: " ")
    }

    var isEmpty: Bool {
        tags.isEmpty && appQueries.isEmpty && typeFilter == nil && text.isEmpty
    }
}

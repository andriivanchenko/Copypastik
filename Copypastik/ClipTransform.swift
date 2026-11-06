import Foundation

/// Lightweight, non-destructive text transformations offered by the Library.
///
/// Every transform is a pure function of the clip's text: the original clip is
/// never modified and the result is not added to history unless the user later
/// copies it again themselves.
nonisolated enum ClipTransform: String, CaseIterable, Identifiable {
    case plainText
    case trimWhitespace
    case uppercase
    case lowercase
    case prettyPrintJSON
    case urlDecode
    case urlEncode
    case removeTrackingParameters
    case copyDomain
    case normalizeLineBreaks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plainText: return "Paste as Plain Text"
        case .trimWhitespace: return "Trim Whitespace"
        case .uppercase: return "Uppercase"
        case .lowercase: return "Lowercase"
        case .prettyPrintJSON: return "Pretty Print JSON"
        case .urlDecode: return "URL Decode"
        case .urlEncode: return "URL Encode"
        case .removeTrackingParameters: return "Remove URL Tracking Parameters"
        case .copyDomain: return "Copy Domain from URL"
        case .normalizeLineBreaks: return "Normalize Line Breaks"
        }
    }

    var symbolName: String {
        switch self {
        case .plainText: return "textformat"
        case .trimWhitespace: return "scissors"
        case .uppercase: return "textformat.size.larger"
        case .lowercase: return "textformat.size.smaller"
        case .prettyPrintJSON: return "curlybraces"
        case .urlDecode: return "link.badge.plus"
        case .urlEncode: return "percent"
        case .removeTrackingParameters: return "eye.slash"
        case .copyDomain: return "globe"
        case .normalizeLineBreaks: return "return"
        }
    }

    /// Short phrase used in the status line after the result is copied.
    var completionLabel: String {
        switch self {
        case .plainText: return "Copied as plain text"
        case .trimWhitespace: return "Whitespace trimmed"
        case .uppercase: return "Uppercased"
        case .lowercase: return "Lowercased"
        case .prettyPrintJSON: return "JSON formatted"
        case .urlDecode: return "URL decoded"
        case .urlEncode: return "URL encoded"
        case .removeTrackingParameters: return "Tracking parameters removed"
        case .copyDomain: return "Domain copied"
        case .normalizeLineBreaks: return "Line breaks normalized"
        }
    }

    enum Failure: Error, Equatable {
        case invalidJSON
        case invalidPercentEncoding
        case notAWebURL

        var message: String {
            switch self {
            case .invalidJSON: return "That text isn't valid JSON."
            case .invalidPercentEncoding: return "That text has invalid percent-encoding."
            case .notAWebURL: return "That text isn't a valid web link."
            }
        }
    }

    struct Output: Equatable {
        let text: String
        let didChange: Bool
    }

    /// Cheap check used to disable transforms that obviously cannot apply, so
    /// the UI never offers an action that is guaranteed to error. Content that
    /// passes this check can still fail in `apply` (for example malformed JSON).
    func isAvailable(for text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        switch self {
        case .plainText, .uppercase, .lowercase, .urlEncode:
            return true
        case .trimWhitespace:
            return Self.trimmed(text) != text
        case .prettyPrintJSON:
            return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}"))
                || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
        case .urlDecode:
            return text.contains("%")
        case .removeTrackingParameters:
            return Self.webURL(from: text) != nil && trimmed.contains("?")
        case .copyDomain:
            return Self.webURL(from: text) != nil
        case .normalizeLineBreaks:
            return Self.lineBreakCharacters.contains { text.contains($0) }
        }
    }

    func apply(to text: String) -> Result<Output, Failure> {
        func output(_ result: String) -> Result<Output, Failure> {
            .success(Output(text: result, didChange: result != text))
        }

        switch self {
        case .plainText:
            return output(text)
        case .trimWhitespace:
            return output(Self.trimmed(text))
        case .uppercase:
            return output(text.uppercased())
        case .lowercase:
            return output(text.lowercased())
        case .prettyPrintJSON:
            return Self.prettyPrintedJSON(text).map { Output(text: $0, didChange: $0 != text) }
        case .urlDecode:
            guard let decoded = text.removingPercentEncoding else {
                return .failure(.invalidPercentEncoding)
            }
            return output(decoded)
        case .urlEncode:
            return output(Self.percentEncoded(text))
        case .removeTrackingParameters:
            guard Self.webURL(from: text) != nil else { return .failure(.notAWebURL) }
            return output(Self.removingTrackingParameters(from: text.trimmingCharacters(in: .whitespacesAndNewlines)))
        case .copyDomain:
            guard let host = Self.webURL(from: text)?.host else { return .failure(.notAWebURL) }
            return output(Self.domain(fromHost: host))
        case .normalizeLineBreaks:
            return output(Self.normalizedLineBreaks(text))
        }
    }

    // MARK: Helpers (internal for tests)

    /// Characters other than `\n` that terminate a line in pasted text.
    private static let lineBreakCharacters: [Character] = ["\r", "\r\n", "\u{2028}", "\u{2029}", "\u{85}"]

    /// Query parameter names that are clearly marketing/click tracking. Kept
    /// conservative on purpose: anything not listed (or prefixed `utm_`) is
    /// preserved because it may be meaningful to the destination page.
    static let trackingParameterNames: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "msclkid", "twclid", "yclid",
        "igshid", "mc_cid", "mc_eid", "_hsenc", "_hsmi", "mkt_tok"
    ]

    static func isTrackingParameter(_ name: String) -> Bool {
        let lowered = name.lowercased()
        return lowered.hasPrefix("utm_") || trackingParameterNames.contains(lowered)
    }

    /// Whole-text http(s) URL with a host and no embedded whitespace.
    static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else {
            return nil
        }
        return url
    }

    /// Strips tracking parameters while leaving every other byte of the URL
    /// (path, fragment, encoding and order of remaining parameters) untouched.
    static func removingTrackingParameters(from urlString: String) -> String {
        var fragment = ""
        var base = urlString
        if let hashIndex = base.firstIndex(of: "#") {
            fragment = String(base[hashIndex...])
            base = String(base[..<hashIndex])
        }

        guard let queryIndex = base.firstIndex(of: "?") else { return urlString }
        let path = String(base[..<queryIndex])
        let query = String(base[base.index(after: queryIndex)...])

        let kept = query.split(separator: "&", omittingEmptySubsequences: true).filter { pair in
            let name = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let decodedName = name.removingPercentEncoding ?? name
            return !isTrackingParameter(decodedName)
        }

        let rebuiltQuery = kept.isEmpty ? "" : "?" + kept.joined(separator: "&")
        return path + rebuiltQuery + fragment
    }

    static func domain(fromHost host: String) -> String {
        let lowered = host.lowercased()
        if lowered.hasPrefix("www."), lowered.count > 4 {
            return String(lowered.dropFirst(4))
        }
        return lowered
    }

    /// Trims the whole text and removes trailing spaces/tabs on every line.
    static func trimmed(_ text: String) -> String {
        let lines = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map { line -> String in
                var trimmedLine = Substring(line)
                while let last = trimmedLine.last, last == " " || last == "\t" || last == "\r" {
                    trimmedLine = trimmedLine.dropLast()
                }
                return String(trimmedLine)
            }
        return lines.joined(separator: "\n")
    }

    /// Percent-encodes everything except RFC 3986 unreserved characters,
    /// matching what `encodeURIComponent` does for typical input.
    static func percentEncoded(_ text: String) -> String {
        // `CharacterSet.alphanumerics` includes non-ASCII letters, so spell out ASCII.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static func normalizedLineBreaks(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{2028}", with: "\n")
            .replacingOccurrences(of: "\u{2029}", with: "\n")
            .replacingOccurrences(of: "\u{85}", with: "\n")
    }

    /// Pretty-prints JSON objects/arrays with sorted keys so output is deterministic.
    static func prettyPrintedJSON(_ text: String) -> Result<String, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: []),
              object is [String: Any] || object is [Any],
              let pretty = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
              ),
              let result = String(data: pretty, encoding: .utf8) else {
            return .failure(.invalidJSON)
        }
        return .success(result)
    }
}

/// Deterministic rules for the Library's "Copy Selected" bulk action.
enum BulkCopyFormatter {
    struct Summary: Equatable {
        let text: String
        let copiedCount: Int
        let skippedImageCount: Int
    }

    /// Joins the text of every text clip with a single newline, in the order
    /// given. Image clips are skipped (and counted) because there is no
    /// plain-text representation to join; the action is unavailable when no
    /// text clips are selected.
    static func combine(_ items: [ClipboardHistoryItem]) -> Summary {
        var texts: [String] = []
        var skippedImages = 0
        for item in items {
            if let text = item.textValue {
                texts.append(text)
            } else {
                skippedImages += 1
            }
        }
        return Summary(text: texts.joined(separator: "\n"), copiedCount: texts.count, skippedImageCount: skippedImages)
    }
}

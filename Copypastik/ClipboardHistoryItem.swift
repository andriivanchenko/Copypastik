import AppKit
import Foundation

struct ClipboardImage: Hashable {
    let data: Data
    let pasteboardTypeRawValue: String
    let width: Int
    let height: Int
    let fingerprint: String

    var pasteboardType: NSPasteboard.PasteboardType {
        NSPasteboard.PasteboardType(pasteboardTypeRawValue)
    }

    var dimensionsLabel: String {
        "\(width)x\(height)"
    }

    var formatLabel: String {
        switch pasteboardType {
        case .png:
            return "PNG"
        case .tiff:
            return "TIFF"
        default:
            return pasteboardType.rawValue.uppercased()
        }
    }

    var nsImage: NSImage? {
        NSImage(data: data)
    }

    static func make(from data: Data, pasteboardType: NSPasteboard.PasteboardType) -> ClipboardImage? {
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }

        let normalizedType: NSPasteboard.PasteboardType
        let normalizedData: Data
        if let pngData = bitmap.representation(using: .png, properties: [:]) {
            normalizedType = .png
            normalizedData = pngData
        } else {
            normalizedType = pasteboardType
            normalizedData = data
        }

        return ClipboardImage(
            data: normalizedData,
            pasteboardTypeRawValue: normalizedType.rawValue,
            width: bitmap.pixelsWide,
            height: bitmap.pixelsHigh,
            fingerprint: Self.fingerprint(for: normalizedData)
        )
    }

    static func make(from image: NSImage) -> ClipboardImage? {
        guard let tiffData = image.tiffRepresentation else { return nil }
        return make(from: tiffData, pasteboardType: .tiff)
    }

    private static func fingerprint(for data: Data) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}

enum ClipboardItemContent: Hashable {
    case text(String)
    case image(ClipboardImage)
}

struct ClipboardHistoryItem: Identifiable, Hashable {
    var content: ClipboardItemContent
    var tags: [String]
    var createdAt: Date
    var updatedAt: Date
    var imageStorageID: UUID?
    var sourceAppName: String?
    var sourceAppBundleID: String?
    var isPinned: Bool
    var pinnedSlot: Int?
    /// On-device OCR result for image clips. `nil` means recognition has not
    /// run yet; an empty string means it ran and found no text.
    var ocrText: String?

    init(
        content: ClipboardItemContent,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imageStorageID: UUID? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        isPinned: Bool = false,
        pinnedSlot: Int? = nil,
        ocrText: String? = nil
    ) {
        self.content = content
        self.tags = TagRules.normalize(tags)
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.imageStorageID = imageStorageID
        self.sourceAppName = sourceAppName
        self.sourceAppBundleID = sourceAppBundleID
        self.isPinned = isPinned
        self.pinnedSlot = pinnedSlot.flatMap { (1...9).contains($0) ? $0 : nil }
        self.ocrText = ocrText
    }

    static func text(
        _ text: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            content: .text(text),
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID
        )
    }

    static func image(
        _ image: ClipboardImage,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        imageStorageID: UUID? = nil,
        sourceAppName: String? = nil,
        sourceAppBundleID: String? = nil,
        ocrText: String? = nil
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            content: .image(image),
            tags: tags,
            createdAt: createdAt,
            updatedAt: updatedAt,
            imageStorageID: imageStorageID,
            sourceAppName: sourceAppName,
            sourceAppBundleID: sourceAppBundleID,
            ocrText: ocrText
        )
    }

    var id: String {
        dedupKey
    }

    var dedupKey: String {
        switch content {
        case .text(let text):
            return "text:\(text)"
        case .image(let image):
            return "image:\(image.fingerprint)"
        }
    }

    var isTagged: Bool {
        !tags.isEmpty
    }

    var kind: ClipboardItemKind {
        switch content {
        case .text(let text):
            return ClipboardItemKind.detect(text)
        case .image:
            return .image
        }
    }

    /// True when `@app` search tokens should match this item's source app.
    func matchesSourceAppQuery(_ query: String) -> Bool {
        let name = sourceAppName?.localizedCaseInsensitiveContains(query) ?? false
        let bundleID = sourceAppBundleID?.localizedCaseInsensitiveContains(query) ?? false
        return name || bundleID
    }

    /// Compact "Safari · 2m ago" label shown on picker rows.
    var sourceAppSummaryLabel: String? {
        guard let sourceAppName else { return nil }
        return "\(sourceAppName) · \(Self.shortRelativeTime(from: createdAt))"
    }

    private static func shortRelativeTime(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        switch seconds {
        case 0..<60:
            return "Now"
        case 60..<3600:
            return "\(seconds / 60)m ago"
        case 3600..<86400:
            return "\(seconds / 3600)h ago"
        default:
            return "\(seconds / 86400)d ago"
        }
    }

    var searchText: String {
        switch content {
        case .text(let text):
            return text
        case .image(let image):
            var parts = [
                "image",
                "picture",
                "bitmap",
                image.formatLabel,
                image.dimensionsLabel,
                "\(image.width)",
                "\(image.height)"
            ]
            if let ocrText, !ocrText.isEmpty {
                parts.append(ocrText)
            }
            return parts.joined(separator: " ")
        }
    }

    /// Text recognized in an image clip, or `nil` when there is none (yet).
    var recognizedText: String? {
        guard imageValue != nil, let ocrText, !ocrText.isEmpty else { return nil }
        return ocrText
    }

    var textValue: String? {
        guard case .text(let text) = content else { return nil }
        return text
    }

    var imageValue: ClipboardImage? {
        guard case .image(let image) = content else { return nil }
        return image
    }

    func withTags(_ tags: [String], updatedAt: Date = Date()) -> ClipboardHistoryItem {
        var copy = self
        copy.tags = TagRules.normalize(tags)
        copy.updatedAt = updatedAt
        return copy
    }

    func withUpdatedAt(_ date: Date = Date()) -> ClipboardHistoryItem {
        var copy = self
        copy.updatedAt = date
        return copy
    }

    func withImageStorageID(_ imageStorageID: UUID?) -> ClipboardHistoryItem {
        var copy = self
        copy.imageStorageID = imageStorageID
        return copy
    }

    func withSourceApp(name: String?, bundleID: String?) -> ClipboardHistoryItem {
        var copy = self
        copy.sourceAppName = name
        copy.sourceAppBundleID = bundleID
        return copy
    }

    func withPinned(_ isPinned: Bool, slot: Int? = nil) -> ClipboardHistoryItem {
        var copy = self
        copy.isPinned = isPinned
        copy.pinnedSlot = isPinned ? slot : nil
        return copy
    }

    func withOCRText(_ ocrText: String?) -> ClipboardHistoryItem {
        var copy = self
        copy.ocrText = ocrText
        return copy
    }

    func withPinnedSlot(_ slot: Int?) -> ClipboardHistoryItem {
        var copy = self
        copy.pinnedSlot = slot.flatMap { (1...9).contains($0) ? $0 : nil }
        return copy
    }

    static func == (lhs: ClipboardHistoryItem, rhs: ClipboardHistoryItem) -> Bool {
        lhs.content == rhs.content && lhs.tags == rhs.tags
            && lhs.isPinned == rhs.isPinned && lhs.pinnedSlot == rhs.pinnedSlot
            && lhs.ocrText == rhs.ocrText
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(content)
        hasher.combine(tags)
        hasher.combine(isPinned)
        hasher.combine(pinnedSlot)
    }
}

enum TagRules {
    static let maxTags = 5
    static let maxTagLength = 20

    static func normalize(_ rawTags: String) -> [String] {
        normalize(rawTags.split(separator: ",").map(String.init))
    }

    static func normalize(_ rawTags: [String]) -> [String] {
        var tags: [String] = []
        var seen = Set<String>()

        for rawTag in rawTags {
            guard let trimmedLength = normalizeTag(rawTag) else { continue }
            guard !seen.contains(trimmedLength) else { continue }

            tags.append(trimmedLength)
            seen.insert(trimmedLength)

            if tags.count == maxTags {
                break
            }
        }

        return tags
    }

    static func normalizeTag(_ rawTag: String) -> String? {
        let lowercased = rawTag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !lowercased.isEmpty else { return nil }
        return String(lowercased.prefix(maxTagLength))
    }
}

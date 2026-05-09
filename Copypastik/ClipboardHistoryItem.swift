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

enum ClipboardHistoryItem: Identifiable, Hashable {
    case text(String)
    case image(ClipboardImage)

    var id: String {
        dedupKey
    }

    var dedupKey: String {
        switch self {
        case .text(let text):
            return "text:\(text)"
        case .image(let image):
            return "image:\(image.fingerprint)"
        }
    }

    var searchText: String {
        switch self {
        case .text(let text):
            return text
        case .image(let image):
            return [
                "image",
                "picture",
                "bitmap",
                image.formatLabel,
                image.dimensionsLabel,
                "\(image.width)",
                "\(image.height)"
            ].joined(separator: " ")
        }
    }

    var textValue: String? {
        guard case .text(let text) = self else { return nil }
        return text
    }

    var imageValue: ClipboardImage? {
        guard case .image(let image) = self else { return nil }
        return image
    }
}

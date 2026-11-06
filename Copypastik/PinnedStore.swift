import AppKit
import Foundation

/// Persists pinned clips (with optional Quick Slot assignment) locally.
/// Pinning does not require tags, and a pinned clip's full content is kept
/// even if the same clip is later deleted from history or tagged snippets.
final class PinnedStore {
    private struct StoredFile: Codable {
        var items: [StoredItem]
    }

    private struct StoredItem: Codable {
        enum Kind: String, Codable {
            case text
            case image
        }

        var kind: Kind
        var text: String?
        var tags: [String]
        var createdAt: Date
        var updatedAt: Date
        var imageStorageID: UUID?
        var pasteboardTypeRawValue: String?
        var width: Int?
        var height: Int?
        var fingerprint: String?
        var sourceAppName: String?
        var sourceAppBundleID: String?
        var pinnedSlot: Int?
        // Added in 1.4; optional so files written by earlier versions still decode.
        var ocrText: String?
    }

    static let fileName = "pinned-clips.json"
    static let imagesDirectoryName = "PinnedClipImages"

    private let fileManager: FileManager
    let directoryURL: URL
    let fileURL: URL
    let imagesDirectoryURL: URL

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseDirectory = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.directoryURL = baseDirectory
        fileURL = baseDirectory.appendingPathComponent(Self.fileName)
        imagesDirectoryURL = baseDirectory.appendingPathComponent(Self.imagesDirectoryName, isDirectory: true)
    }

    func load() -> [ClipboardHistoryItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let storedFile = try JSONDecoder().decode(StoredFile.self, from: data)
            return storedFile.items.compactMap(loadItem).sortedByPinnedOrder()
        } catch {
            backupCorruptedFile()
            print("[Copypastik] pinned clips store was corrupt and has been backed up")
            return []
        }
    }

    @discardableResult
    func save(_ items: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        do {
            try ensureDirectoriesExist()
            var usedImageIDs = Set<UUID>()

            let pinnedItems = items.filter(\.isPinned)
            let storedItems = try pinnedItems.map { item in
                try storedItem(for: item, usedImageIDs: &usedImageIDs)
            }

            let storedFile = StoredFile(items: storedItems)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(storedFile)
            try data.write(to: fileURL, options: .atomic)
            cleanupUnusedImages(keeping: usedImageIDs)

            return zip(pinnedItems, storedItems).map { item, storedItem in
                item.withImageStorageID(storedItem.imageStorageID)
            }
        } catch {
            print("[Copypastik] pinned clips save failed: \(error.localizedDescription)")
            return items
        }
    }

    func clear() {
        do {
            if fileManager.fileExists(atPath: fileURL.path) {
                try fileManager.removeItem(at: fileURL)
            }
            if fileManager.fileExists(atPath: imagesDirectoryURL.path) {
                try fileManager.removeItem(at: imagesDirectoryURL)
            }
        } catch {
            print("[Copypastik] pinned clips clear failed: \(error.localizedDescription)")
        }
    }

    var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleID = Bundle.main.bundleIdentifier ?? "com.ivanchenko.Copypastik"
        return (applicationSupport ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(bundleID, isDirectory: true)
    }

    private func ensureDirectoriesExist() throws {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: imagesDirectoryURL, withIntermediateDirectories: true)
    }

    private func storedItem(for item: ClipboardHistoryItem, usedImageIDs: inout Set<UUID>) throws -> StoredItem {
        switch item.content {
        case .text(let text):
            return StoredItem(
                kind: .text,
                text: text,
                tags: item.tags,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                imageStorageID: nil,
                pasteboardTypeRawValue: nil,
                width: nil,
                height: nil,
                fingerprint: nil,
                sourceAppName: item.sourceAppName,
                sourceAppBundleID: item.sourceAppBundleID,
                pinnedSlot: item.pinnedSlot,
                ocrText: nil
            )
        case .image(let image):
            let imageStorageID = item.imageStorageID ?? UUID()
            usedImageIDs.insert(imageStorageID)
            try image.data.write(to: imageURL(for: imageStorageID), options: .atomic)
            return StoredItem(
                kind: .image,
                text: nil,
                tags: item.tags,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                imageStorageID: imageStorageID,
                pasteboardTypeRawValue: image.pasteboardTypeRawValue,
                width: image.width,
                height: image.height,
                fingerprint: image.fingerprint,
                sourceAppName: item.sourceAppName,
                sourceAppBundleID: item.sourceAppBundleID,
                pinnedSlot: item.pinnedSlot,
                ocrText: item.ocrText
            )
        }
    }

    private func loadItem(_ storedItem: StoredItem) -> ClipboardHistoryItem? {
        switch storedItem.kind {
        case .text:
            guard let text = storedItem.text, !text.isEmpty else { return nil }
            return ClipboardHistoryItem(
                content: .text(text),
                tags: TagRules.normalize(storedItem.tags),
                createdAt: storedItem.createdAt,
                updatedAt: storedItem.updatedAt,
                sourceAppName: storedItem.sourceAppName,
                sourceAppBundleID: storedItem.sourceAppBundleID,
                isPinned: true,
                pinnedSlot: storedItem.pinnedSlot
            )
        case .image:
            guard let imageStorageID = storedItem.imageStorageID,
                  let pasteboardTypeRawValue = storedItem.pasteboardTypeRawValue,
                  let width = storedItem.width,
                  let height = storedItem.height,
                  let fingerprint = storedItem.fingerprint,
                  let data = try? Data(contentsOf: imageURL(for: imageStorageID)) else {
                return nil
            }

            let image = ClipboardImage(
                data: data,
                pasteboardTypeRawValue: pasteboardTypeRawValue,
                width: width,
                height: height,
                fingerprint: fingerprint
            )
            return ClipboardHistoryItem(
                content: .image(image),
                tags: TagRules.normalize(storedItem.tags),
                createdAt: storedItem.createdAt,
                updatedAt: storedItem.updatedAt,
                imageStorageID: imageStorageID,
                sourceAppName: storedItem.sourceAppName,
                sourceAppBundleID: storedItem.sourceAppBundleID,
                isPinned: true,
                pinnedSlot: storedItem.pinnedSlot,
                ocrText: storedItem.ocrText
            )
        }
    }

    private func backupCorruptedFile() {
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.moveItem(at: fileURL, to: backupURL)
        } catch {
            print("[Copypastik] failed to back up corrupt pinned clips file: \(error.localizedDescription)")
        }
    }

    private func imageURL(for id: UUID) -> URL {
        imagesDirectoryURL.appendingPathComponent(id.uuidString).appendingPathExtension("png")
    }

    private func cleanupUnusedImages(keeping usedImageIDs: Set<UUID>) {
        guard let imageFiles = try? fileManager.contentsOfDirectory(at: imagesDirectoryURL, includingPropertiesForKeys: nil) else {
            return
        }

        for imageFile in imageFiles {
            let idString = imageFile.deletingPathExtension().lastPathComponent
            guard let id = UUID(uuidString: idString), !usedImageIDs.contains(id) else { continue }
            try? fileManager.removeItem(at: imageFile)
        }
    }
}

extension Array where Element == ClipboardHistoryItem {
    /// Slotted items sort first by slot number; unslotted pinned items follow by recency.
    func sortedByPinnedOrder() -> [ClipboardHistoryItem] {
        sorted { lhs, rhs in
            switch (lhs.pinnedSlot, rhs.pinnedSlot) {
            case let (lhsSlot?, rhsSlot?):
                return lhsSlot < rhsSlot
            case (nil, nil):
                if lhs.updatedAt == rhs.updatedAt {
                    return lhs.dedupKey < rhs.dedupKey
                }
                return lhs.updatedAt > rhs.updatedAt
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            }
        }
    }
}

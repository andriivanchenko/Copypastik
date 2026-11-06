import AppKit
import Foundation

/// Persists the untagged clipboard history so the Library survives relaunches.
///
/// The store is deliberately bounded: callers pass at most `historyLimit`
/// items, oversized text clips are kept in memory only, and the image byte
/// budget is enforced by `ClipboardStore` before saving. Clips are only ever
/// handed to this store after passing the pause-capture and ignored-app gates,
/// so nothing captured while those are active reaches disk.
final class HistoryStore {
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
        var createdAt: Date
        var updatedAt: Date
        var imageStorageID: UUID?
        var pasteboardTypeRawValue: String?
        var width: Int?
        var height: Int?
        var fingerprint: String?
        var sourceAppName: String?
        var sourceAppBundleID: String?
        var ocrText: String?
    }

    static let fileName = "history.json"
    static let imagesDirectoryName = "HistoryImages"
    /// Text clips larger than this stay memory-only to keep the JSON file small.
    static let maxPersistedTextBytes = 256 * 1024

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

    var backupURL: URL {
        fileURL.appendingPathExtension("bak")
    }

    /// Loads at most `limit` of the newest saved clips.
    func load(limit: Int) -> [ClipboardHistoryItem] {
        guard fileManager.fileExists(atPath: fileURL.path) else { return [] }

        do {
            let data = try Data(contentsOf: fileURL)
            let storedFile = try JSONDecoder().decode(StoredFile.self, from: data)
            return Array(storedFile.items.compactMap(loadItem).prefix(limit))
        } catch {
            backupCorruptedFile()
            print("[Copypastik] history store was corrupt and has been backed up")
            return []
        }
    }

    /// Writes `items` (newest first) and returns them with image storage ids
    /// assigned. Items that cannot be persisted (oversized text) are kept in
    /// the returned array but skipped on disk.
    @discardableResult
    func save(_ items: [ClipboardHistoryItem]) -> [ClipboardHistoryItem] {
        do {
            try ensureDirectoriesExist()
            var usedImageIDs = Set<UUID>()
            var storedItems: [StoredItem] = []
            var result: [ClipboardHistoryItem] = []

            for item in items {
                if let stored = try storedItem(for: item, usedImageIDs: &usedImageIDs) {
                    storedItems.append(stored)
                    result.append(item.withImageStorageID(stored.imageStorageID))
                } else {
                    result.append(item)
                }
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(StoredFile(items: storedItems))
            try data.write(to: fileURL, options: .atomic)
            cleanupUnusedImages(keeping: usedImageIDs)
            return result
        } catch {
            print("[Copypastik] history save failed: \(error.localizedDescription)")
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
            print("[Copypastik] history clear failed: \(error.localizedDescription)")
        }
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

    private func storedItem(for item: ClipboardHistoryItem, usedImageIDs: inout Set<UUID>) throws -> StoredItem? {
        switch item.content {
        case .text(let text):
            guard text.utf8.count <= Self.maxPersistedTextBytes else { return nil }
            return StoredItem(
                kind: .text,
                text: text,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                imageStorageID: nil,
                pasteboardTypeRawValue: nil,
                width: nil,
                height: nil,
                fingerprint: nil,
                sourceAppName: item.sourceAppName,
                sourceAppBundleID: item.sourceAppBundleID,
                ocrText: nil
            )
        case .image(let image):
            let imageStorageID = item.imageStorageID ?? UUID()
            usedImageIDs.insert(imageStorageID)
            let url = imageURL(for: imageStorageID)
            // Image ids are unique per capture, so an existing file is current.
            if !fileManager.fileExists(atPath: url.path) {
                try image.data.write(to: url, options: .atomic)
            }
            return StoredItem(
                kind: .image,
                text: nil,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                imageStorageID: imageStorageID,
                pasteboardTypeRawValue: image.pasteboardTypeRawValue,
                width: image.width,
                height: image.height,
                fingerprint: image.fingerprint,
                sourceAppName: item.sourceAppName,
                sourceAppBundleID: item.sourceAppBundleID,
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
                createdAt: storedItem.createdAt,
                updatedAt: storedItem.updatedAt,
                sourceAppName: storedItem.sourceAppName,
                sourceAppBundleID: storedItem.sourceAppBundleID
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
                createdAt: storedItem.createdAt,
                updatedAt: storedItem.updatedAt,
                imageStorageID: imageStorageID,
                sourceAppName: storedItem.sourceAppName,
                sourceAppBundleID: storedItem.sourceAppBundleID,
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
            print("[Copypastik] failed to back up corrupt history file: \(error.localizedDescription)")
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

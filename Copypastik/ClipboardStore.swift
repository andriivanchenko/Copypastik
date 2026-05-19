import AppKit
import Combine
import Foundation

final class ClipboardStore: ObservableObject {
    static let historyLimit = AppSettings.defaultHistoryLimit

    @Published private(set) var items: [ClipboardHistoryItem] = []

    private let settings: AppSettings
    private let service = PasteboardService()
    private var cancellables = Set<AnyCancellable>()

    init(settings: AppSettings? = nil, startsService: Bool = true) {
        self.settings = settings ?? AppSettings(managesLaunchAtLogin: false)
        service.onNewItem = { [weak self] item in
            DispatchQueue.main.async { self?.ingestCopiedItem(item) }
        }
        self.settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in
                self?.trimHistory(to: limit.rawValue)
            }
            .store(in: &cancellables)

        if startsService {
            service.start()
        }
    }

    func copyAsPlainText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print("[Copypastik] selected item written to NSPasteboard as plain text")
        // Suppress PasteboardService from re-detecting this write as a new item
        service.suppressChange(atCount: NSPasteboard.general.changeCount)
    }

    func copyItem(_ item: ClipboardHistoryItem) {
        switch item {
        case .text(let text):
            copyAsPlainText(text)
        case .image(let image):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(image.data, forType: image.pasteboardType)
            print("[Copypastik] selected image written to NSPasteboard")
            service.suppressChange(atCount: NSPasteboard.general.changeCount)
        }
    }

    func clearHistory() {
        items = []
    }

    func deleteItem(_ item: ClipboardHistoryItem) {
        items = Self.historyItems(afterDeleting: item, from: items)
    }

    func ingestCopiedText(_ text: String) {
        ingestCopiedItem(.text(text))
    }

    func ingestCopiedItem(_ item: ClipboardHistoryItem) {
        guard settings.isClipboardHistoryEnabled else {
            print("[Copypastik] clipboard history disabled, item ignored")
            return
        }

        guard let normalizedItem = Self.normalizedItem(item) else {
            print("[Copypastik] duplicate/empty item ignored")
            return
        }

        let updatedItems = Self.historyItems(afterAdding: normalizedItem, to: items, maxItems: settings.historyLimit.rawValue)
        guard updatedItems != items else {
            print("[Copypastik] duplicate/empty item ignored")
            return
        }
        items = updatedItems
        print("[Copypastik] clipboard history updated")
    }

    static func historyItems(afterAdding text: String, to existingItems: [String], maxItems: Int = historyLimit) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return existingItems }

        var updatedItems = existingItems.filter { $0 != trimmed }
        updatedItems.insert(trimmed, at: 0)

        if updatedItems.count > maxItems {
            updatedItems = Array(updatedItems.prefix(maxItems))
        }

        return updatedItems
    }

    static func historyItems(afterDeleting text: String, from existingItems: [String]) -> [String] {
        existingItems.filter { $0 != text }
    }

    static func historyItems(
        afterAdding item: ClipboardHistoryItem,
        to existingItems: [ClipboardHistoryItem],
        maxItems: Int = historyLimit
    ) -> [ClipboardHistoryItem] {
        guard !item.dedupKey.isEmpty else { return existingItems }

        var updatedItems = existingItems.filter { $0.dedupKey != item.dedupKey }
        updatedItems.insert(item, at: 0)

        if updatedItems.count > maxItems {
            updatedItems = Array(updatedItems.prefix(maxItems))
        }

        return updatedItems
    }

    static func historyItems(
        afterDeleting item: ClipboardHistoryItem,
        from existingItems: [ClipboardHistoryItem]
    ) -> [ClipboardHistoryItem] {
        existingItems.filter { $0.dedupKey != item.dedupKey }
    }

    private static func normalizedItem(_ item: ClipboardHistoryItem) -> ClipboardHistoryItem? {
        switch item {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .text(trimmed)
        case .image:
            return item
        }
    }

    private func trimHistory(to maxItems: Int) {
        guard items.count > maxItems else { return }
        items = Array(items.prefix(maxItems))
    }
}

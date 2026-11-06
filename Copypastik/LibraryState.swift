import AppKit
import Combine
import Foundation

struct LibraryStatus: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let isError: Bool
}

/// A delete the user still has to confirm (more than one clip, or a pinned clip).
struct LibraryPendingDelete: Equatable, Identifiable {
    let id = UUID()
    let items: [ClipboardHistoryItem]

    var pinnedCount: Int { items.filter(\.isPinned).count }
    var unpinnedCount: Int { items.count - pinnedCount }
}

/// View model for the Library window: sidebar scope, search, selection,
/// keyboard cursor and every action the window can perform. Rendering lives
/// in `LibraryView`; this type holds the logic so it stays testable.
final class LibraryState: ObservableObject {
    @Published var scope: LibraryScope = .all {
        didSet {
            guard scope != oldValue else { return }
            recompute(resetSelection: true)
        }
    }

    @Published var query: String = "" {
        didSet {
            guard query != oldValue else { return }
            recompute(resetSelection: true)
        }
    }

    /// Selected clips by `dedupKey`. Written by the list's native
    /// click/Shift-click/Command-click handling and by keyboard navigation.
    @Published var selection = Set<String>() {
        didSet { selectionDidChange(from: oldValue) }
    }

    @Published private(set) var allClips: [ClipboardHistoryItem] = []
    @Published private(set) var sections: [LibrarySection] = []
    @Published private(set) var visibleItems: [ClipboardHistoryItem] = []
    @Published private(set) var cursorKey: String?
    @Published private(set) var appEntries: [LibraryAppEntry] = []
    @Published private(set) var tagEntries: [LibraryTagEntry] = []
    @Published private(set) var typeCounts: [PickerTypeFilter: Int] = [:]
    @Published private(set) var pinnedCount = 0

    @Published var status: LibraryStatus?
    @Published var searchFocusTrigger = 0
    @Published var pendingDelete: LibraryPendingDelete?
    @Published var isAddingTag = false
    @Published var newTagText = ""

    /// Provided by the window controller: re-activates the app the user was
    /// in and sends ⌘V when Automatic Paste is enabled and permitted. Returns
    /// whether a paste was issued.
    var pasteIntoPreviousApp: (() -> Bool)?

    let store: ClipboardStore
    let settings: AppSettings

    private var anchorKey: String?
    private var cancellables = Set<AnyCancellable>()

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings

        allClips = store.libraryItems
        recompute(resetSelection: true)

        Publishers.CombineLatest3(store.$items, store.$taggedItems, store.$pinnedItems)
            .debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
            .sink { [weak self] history, tagged, pinned in
                self?.setClips(ClipboardStore.mergedLibraryItems(history: history, tagged: tagged, pinned: pinned))
            }
            .store(in: &cancellables)
    }

    // MARK: Derived values

    var visibleKeys: [String] {
        visibleItems.map(\.dedupKey)
    }

    /// Selected clips in the order they appear in the list.
    var selectedItems: [ClipboardHistoryItem] {
        visibleItems.filter { selection.contains($0.dedupKey) }
    }

    var singleSelectedItem: ClipboardHistoryItem? {
        let items = selectedItems
        return items.count == 1 ? items[0] : nil
    }

    var hasActiveFilter: Bool {
        scope != .all || !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var scopeTitle: String {
        switch scope {
        case .all: return "All Clips"
        case .pinned: return "Pinned"
        case .app(let key): return appEntries.first { $0.key == key }?.name ?? key
        case .type(let filter): return filter.displayName
        case .tag(let tag): return "#\(tag)"
        }
    }

    /// Tags that appear on at least one selected clip (for "Remove Tag").
    var tagsInSelection: [String] {
        Array(Set(selectedItems.flatMap(\.tags))).sorted()
    }

    var allTags: [String] {
        tagEntries.map(\.tag)
    }

    // MARK: Data flow

    func setClips(_ clips: [ClipboardHistoryItem]) {
        allClips = clips
        appEntries = LibraryFilter.apps(in: clips)
        tagEntries = LibraryFilter.tags(in: clips)
        typeCounts = LibraryFilter.typeCounts(in: clips)
        pinnedCount = clips.filter(\.isPinned).count

        // A scope whose clips are all gone (last tag removed, app purged)
        // would show an empty list the user cannot navigate away from.
        switch scope {
        case .app(let key) where !appEntries.contains(where: { $0.key == key }):
            scope = .all
        case .tag(let tag) where !tagEntries.contains(where: { $0.tag == tag }):
            scope = .all
        case .pinned where pinnedCount == 0:
            scope = .all
        default:
            break
        }

        recompute(resetSelection: false)
    }

    /// Re-reads the stores immediately (used after local actions so the UI
    /// does not wait for the debounced store subscription).
    func reload() {
        setClips(store.libraryItems)
    }

    func prepareForPresentation() {
        query = ""
        reload()
        recompute(resetSelection: true)
        searchFocusTrigger += 1
    }

    private func recompute(resetSelection: Bool) {
        let filtered = LibraryFilter.apply(allClips, scope: scope, query: query)
        sections = LibraryFilter.sections(for: filtered)
        visibleItems = sections.flatMap(\.items)

        let keys = Set(visibleItems.map(\.dedupKey))
        if resetSelection {
            if let first = visibleItems.first {
                selection = [first.dedupKey]
            } else {
                selection = []
            }
        } else if !selection.isSubset(of: keys) {
            // Clips that left the list (deleted, or filtered out) must not
            // stay selected, or a bulk action could touch invisible clips.
            selection = selection.intersection(keys)
        }

        if let cursorKey, !keys.contains(cursorKey) {
            self.cursorKey = nil
        }
        if let anchorKey, !keys.contains(anchorKey) {
            self.anchorKey = nil
        }
    }

    private func selectionDidChange(from oldValue: Set<String>) {
        guard selection != oldValue else { return }

        if selection.isEmpty {
            cursorKey = nil
            anchorKey = nil
        } else if selection.count == 1 {
            cursorKey = selection.first
            anchorKey = selection.first
        } else if cursorKey == nil || !selection.contains(cursorKey ?? "") {
            // Mouse-driven multi-selection: put the cursor on the newly added clip.
            let added = selection.subtracting(oldValue)
            cursorKey = visibleItems.last { added.contains($0.dedupKey) }?.dedupKey
                ?? visibleItems.last { selection.contains($0.dedupKey) }?.dedupKey
        }
    }

    // MARK: Keyboard navigation

    func moveSelection(by delta: Int, extending: Bool = false) {
        let keys = visibleKeys
        guard !keys.isEmpty else { return }

        let currentIndex = cursorKey.flatMap { keys.firstIndex(of: $0) }
            ?? keys.lastIndex { selection.contains($0) }
        let newIndex: Int
        if let currentIndex {
            newIndex = min(max(currentIndex + delta, 0), keys.count - 1)
        } else {
            newIndex = delta >= 0 ? 0 : keys.count - 1
        }

        if extending {
            let anchorIndex = anchorKey.flatMap { keys.firstIndex(of: $0) } ?? currentIndex ?? newIndex
            let range = min(anchorIndex, newIndex)...max(anchorIndex, newIndex)
            let anchor = keys[anchorIndex]
            selection = Set(keys[range])
            anchorKey = anchor
        } else {
            selection = [keys[newIndex]]
            anchorKey = keys[newIndex]
        }
        cursorKey = keys[newIndex]
    }

    func selectAllVisible() {
        selection = Set(visibleKeys)
    }

    func clearSelection() {
        selection = []
    }

    /// Escape: clear the search first, then a multi-selection, otherwise
    /// report that nothing is left to dismiss so the window can close.
    @discardableResult
    func dismissLayer() -> Bool {
        if !query.isEmpty {
            query = ""
            return true
        }
        if selection.count > 1 {
            if let cursorKey {
                selection = [cursorKey]
            } else {
                selection = []
            }
            return true
        }
        return false
    }

    // MARK: Status

    func showStatus(_ text: String, isError: Bool = false) {
        let newStatus = LibraryStatus(text: text, isError: isError)
        status = newStatus
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 3.2 : 2.2)) { [weak self] in
            guard self?.status?.id == newStatus.id else { return }
            self?.status = nil
        }
    }

    // MARK: Copy / paste

    /// Return key: copies the selected clip (or joins several text clips) and
    /// pastes into the previous app when Automatic Paste is enabled.
    func activateSelection() {
        let items = selectedItems
        if items.count > 1 {
            copySelectedJoined()
        } else if let item = items.first {
            copy(item)
        }
    }

    func copy(_ item: ClipboardHistoryItem) {
        store.copyItem(item)
        finishCopy(label: "Copied")
    }

    func copyRecognizedText(of item: ClipboardHistoryItem) {
        guard let text = item.recognizedText else {
            showStatus("No recognized text for this image yet.", isError: true)
            return
        }
        store.copyDerivedText(text)
        finishCopy(label: "Recognized text copied")
    }

    /// Joins the text of all selected text clips with newlines, skipping images.
    func copySelectedJoined() {
        let summary = BulkCopyFormatter.combine(selectedItems)
        guard summary.copiedCount > 0 else {
            showStatus("Select at least one text clip to copy.", isError: true)
            return
        }
        store.copyDerivedText(summary.text)

        var label = "Copied \(summary.copiedCount) text \(summary.copiedCount == 1 ? "clip" : "clips")"
        if summary.skippedImageCount > 0 {
            label += " · \(summary.skippedImageCount) \(summary.skippedImageCount == 1 ? "image" : "images") skipped"
        }
        finishCopy(label: label)
    }

    private func finishCopy(label: String) {
        let didPaste = pasteIntoPreviousApp?() ?? false
        showStatus(didPaste ? "\(label) · pasted" : "\(label) · ⌘V to paste")
    }

    // MARK: Transformations

    func applyTransform(_ transform: ClipTransform, to item: ClipboardHistoryItem) {
        guard let text = item.textValue else { return }

        switch transform.apply(to: text) {
        case .success(let output):
            store.copyDerivedText(output.text)
            finishCopy(label: output.didChange ? transform.completionLabel : "\(transform.completionLabel) (no change)")
        case .failure(let failure):
            showStatus(failure.message, isError: true)
        }
    }

    // MARK: Bulk actions

    func requestDeleteSelection() {
        let items = selectedItems
        guard !items.isEmpty else { return }

        if items.count == 1, items[0].isPinned == false {
            performDelete(items, includingPinned: false)
        } else {
            pendingDelete = LibraryPendingDelete(items: items)
        }
    }

    func confirmDelete(includingPinned: Bool) {
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        performDelete(pending.items, includingPinned: includingPinned)
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    private func performDelete(_ items: [ClipboardHistoryItem], includingPinned: Bool) {
        let firstIndex = visibleItems.firstIndex { item in items.contains { $0.dedupKey == item.dedupKey } } ?? 0
        let result = store.deleteItems(items, includingPinned: includingPinned)
        reload()

        if !visibleItems.isEmpty {
            let nextIndex = min(firstIndex, visibleItems.count - 1)
            selection = [visibleItems[nextIndex].dedupKey]
        }

        var label = "Deleted \(result.deletedCount) \(result.deletedCount == 1 ? "clip" : "clips")"
        if result.preservedPinnedCount > 0 {
            label += " · kept \(result.preservedPinnedCount) pinned"
        }
        showStatus(label)
    }

    /// Pins every selected clip, or unpins them all when they are all pinned.
    func togglePinSelection() {
        let items = selectedItems
        guard !items.isEmpty else { return }

        let shouldPin = items.contains { !$0.isPinned }
        let changed = store.setPinned(shouldPin, for: items)
        reload()
        showStatus("\(shouldPin ? "Pinned" : "Unpinned") \(changed) \(changed == 1 ? "clip" : "clips")")
    }

    func assignSlot(_ slot: Int?, to item: ClipboardHistoryItem) {
        guard item.isPinned else {
            showStatus("Pin the clip first to give it a Quick Slot.", isError: true)
            return
        }
        store.assignPinnedSlot(slot, to: item)
        reload()
        if let slot {
            showStatus("Assigned · ⌃⌥\(slot) pastes it")
        } else {
            showStatus("Quick Slot cleared")
        }
    }

    func beginAddTag() {
        guard !selection.isEmpty else { return }
        newTagText = ""
        isAddingTag = true
    }

    func commitNewTag() {
        let tag = newTagText
        isAddingTag = false
        newTagText = ""
        addTagToSelection(tag)
    }

    func addTagToSelection(_ rawTag: String) {
        guard let tag = TagRules.normalizeTag(rawTag) else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }

        let result = store.addTag(tag, to: items)
        reload()

        if result.skippedCount > 0 {
            showStatus(
                "Tagged \(result.updatedCount) · \(result.skippedCount) skipped (tag limit)",
                isError: result.updatedCount == 0
            )
        } else if result.updatedCount == 0 {
            showStatus("Already tagged #\(tag)")
        } else {
            showStatus("Added #\(tag) to \(result.updatedCount) \(result.updatedCount == 1 ? "clip" : "clips")")
        }
    }

    func removeTagFromSelection(_ rawTag: String) {
        guard let tag = TagRules.normalizeTag(rawTag) else { return }
        let items = selectedItems
        guard !items.isEmpty else { return }

        let count = store.removeTag(tag, from: items)
        reload()
        showStatus("Removed #\(tag) from \(count) \(count == 1 ? "clip" : "clips")")
    }

    // MARK: Text recognition

    func isRecognizingText(in item: ClipboardHistoryItem) -> Bool {
        store.isRecognizingText(in: item)
    }
}

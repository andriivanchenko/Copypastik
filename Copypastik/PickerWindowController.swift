import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

// MARK: - Shared state

enum PickerTagChip: Equatable, Identifiable {
    case all
    case tag(String)

    var id: String {
        switch self {
        case .all:
            return "all"
        case .tag(let tag):
            return "tag:\(tag)"
        }
    }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .tag(let tag):
            return "#\(tag)"
        }
    }

    var tag: String? {
        guard case .tag(let tag) = self else { return nil }
        return tag
    }
}

final class PickerState: ObservableObject {
    @Published var items: [ClipboardHistoryItem] = []
    @Published var taggedItems: [ClipboardHistoryItem] = []
    @Published var pinnedItems: [ClipboardHistoryItem] = []
    @Published var selectedIndex: Int = 0
    @Published var query: String = ""
    @Published var searchFocusTrigger: Int = 0
    @Published var presentationID: Int = 0
    @Published var isClosing: Bool = false
    @Published var pressedIndex: Int?
    @Published var revealedDeleteItem: ClipboardHistoryItem?
    @Published var deletingItem: ClipboardHistoryItem?
    @Published var isTaggedSectionCollapsed: Bool = false
    @Published var activeTagFilters = Set<String>()
    @Published var activeTypeFilter: PickerTypeFilter = .all
    @Published var isTagBrowserActive = false
    @Published var focusedTagChipIndex: Int?
    @Published var editingTagsItem: ClipboardHistoryItem?
    @Published var tagEditorText: String = ""
    @Published var notice: String?
    @Published var hoveredItemID: String?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Reset selection to top whenever the query changes so the user
        // always starts navigating from the best match.
        $query
            .dropFirst()
            .sink { [weak self] _ in
                self?.selectedIndex = 0
                self?.focusedTagChipIndex = nil
                if self?.search.tags.isEmpty == true {
                    self?.isTagBrowserActive = false
                }
                self?.clearDeleteState()
            }
            .store(in: &cancellables)
    }

    var search: PickerSearchQuery {
        PickerSearchQuery(normalizedQuery)
    }

    var tagFilters: [String] {
        TagRules.normalize(Array(activeTagFilters) + search.tags).sorted()
    }

    var tagChips: [String] {
        Array(Set(taggedItems.flatMap(\.tags))).sorted()
    }

    var tagFilterChips: [PickerTagChip] {
        guard !tagChips.isEmpty else { return [] }
        return [.all] + tagChips.map(PickerTagChip.tag)
    }

    var filteredItemIDs: [String] {
        filteredItems.map(\.id)
    }

    var isTagFilterBarVisible: Bool {
        !tagFilterChips.isEmpty && (isTagBrowserActive || !tagFilters.isEmpty)
    }

    var isTypeFilterBarVisible: Bool {
        !(items.isEmpty && taggedItems.isEmpty && pinnedItems.isEmpty)
    }

    var shouldShowTaggedRows: Bool {
        !isTaggedSectionCollapsed || !tagFilters.isEmpty || isTagBrowserActive
    }

    var shouldFocusTagChipsOnUp: Bool {
        guard !tagFilterChips.isEmpty else { return false }
        if selectedIndex == 0 { return true }
        let pinnedCount = filteredPinnedItems.count
        if pinnedCount > 0, selectedIndex == pinnedCount { return true }
        guard !filteredHistoryItems.isEmpty else { return false }
        return selectedIndex == pinnedCount + filteredTaggedItems.count
    }

    var focusedTagChip: String? {
        focusedTagFilterChip?.tag
    }

    var focusedTagFilterChip: PickerTagChip? {
        guard let focusedTagChipIndex,
              tagFilterChips.indices.contains(focusedTagChipIndex) else {
            return nil
        }
        return tagFilterChips[focusedTagChipIndex]
    }

    var filteredPinnedItems: [ClipboardHistoryItem] {
        pinnedItems.filter { item in
            matchesCommonFilters(item, includingTags: true)
        }
    }

    var filteredTaggedItems: [ClipboardHistoryItem] {
        guard shouldShowTaggedRows else { return [] }
        let pinnedKeys = pinnedDedupKeys
        return taggedItems.filter { item in
            !pinnedKeys.contains(item.dedupKey) && matchesCommonFilters(item, includingTags: true)
        }
    }

    var filteredHistoryItems: [ClipboardHistoryItem] {
        guard !isTagBrowserActive else { return [] }
        guard tagFilters.isEmpty else { return [] }
        let pinnedKeys = pinnedDedupKeys
        return items.filter { item in
            !pinnedKeys.contains(item.dedupKey) && matchesCommonFilters(item, includingTags: false)
        }
    }

    var filteredItems: [ClipboardHistoryItem] {
        filteredPinnedItems + filteredTaggedItems + filteredHistoryItems
    }

    var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var matchCountLabel: String {
        if items.isEmpty && taggedItems.isEmpty && pinnedItems.isEmpty {
            return "0 items"
        }

        if search.isEmpty && activeTagFilters.isEmpty && activeTypeFilter == .all {
            let count = filteredItems.count
            return "\(count) \(count == 1 ? "item" : "items")"
        }

        let count = filteredItems.count
        return count == 0 ? "No matches" : "\(count) \(count == 1 ? "match" : "matches")"
    }

    private var pinnedDedupKeys: Set<String> {
        Set(pinnedItems.map(\.dedupKey))
    }

    /// Type + source-app + text filters shared by every section. Tag
    /// matching is opt-in because history items never carry tags.
    private func matchesCommonFilters(_ item: ClipboardHistoryItem, includingTags: Bool) -> Bool {
        if includingTags, !tagFilters.allSatisfy({ item.tags.contains($0) }) {
            return false
        }
        guard matchesTypeFilters(item) else { return false }
        guard search.appQueries.allSatisfy({ item.matchesSourceAppQuery($0) }) else { return false }
        guard search.text.isEmpty || item.searchText.localizedCaseInsensitiveContains(search.text) else { return false }
        return true
    }

    private func matchesTypeFilters(_ item: ClipboardHistoryItem) -> Bool {
        var filters: [PickerTypeFilter] = []
        if activeTypeFilter != .all { filters.append(activeTypeFilter) }
        if let queryType = search.typeFilter, queryType != .all { filters.append(queryType) }
        return filters.allSatisfy { $0.matches(item.kind) }
    }

    var isEditingTags: Bool {
        editingTagsItem != nil
    }

    func prepareForPresentation(
        with items: [ClipboardHistoryItem],
        taggedItems: [ClipboardHistoryItem] = [],
        pinnedItems: [ClipboardHistoryItem] = [],
        isTaggedSectionCollapsed: Bool = false,
        editing itemToEdit: ClipboardHistoryItem? = nil
    ) {
        self.items = items
        self.taggedItems = taggedItems
        self.pinnedItems = pinnedItems
        pruneTagFilterState()
        self.isTaggedSectionCollapsed = isTaggedSectionCollapsed
        query = ""
        resetTransientState()
        activeTagFilters.removeAll()
        activeTypeFilter = .all
        isClosing = false
        presentationID += 1
        searchFocusTrigger += 1

        if let itemToEdit {
            focusItem(itemToEdit)
            beginEditingTags(for: itemToEdit, currentText: itemToEdit.tags.joined(separator: ", "))
        } else {
            focusNewestHistoryItemIfAvailable()
        }
    }

    func replaceItemsPreservingQuery(
        _ items: [ClipboardHistoryItem],
        taggedItems: [ClipboardHistoryItem] = [],
        pinnedItems: [ClipboardHistoryItem] = []
    ) {
        self.items = items
        self.taggedItems = taggedItems
        self.pinnedItems = pinnedItems
        pruneTagFilterState()
        resetTransientState()
        clampSelectionToFilteredItems()
    }

    func clampSelectionToFilteredItems() {
        let count = filteredItems.count
        guard count > 0 else {
            selectedIndex = 0
            return
        }
        selectedIndex = min(max(selectedIndex, 0), count - 1)
    }

    func clearDeleteState() {
        revealedDeleteItem = nil
        deletingItem = nil
    }

    func toggleTagFilter(_ tag: String) {
        let normalizedTag = TagRules.normalizeTag(tag) ?? tag
        selectTagChip(.tag(normalizedTag))
    }

    func selectTagChip(_ chip: PickerTagChip) {
        isTagBrowserActive = true
        if let index = tagFilterChips.firstIndex(of: chip) {
            focusedTagChipIndex = index
        }
        applyTagFilterChip(chip)
    }

    func activateFocusedTagChip() {
        guard let focusedTagFilterChip else { return }
        applyTagFilterChip(focusedTagFilterChip)
    }

    func focusTagChips(selecting tag: String? = nil) {
        guard !tagFilterChips.isEmpty else {
            focusedTagChipIndex = nil
            return
        }

        isTagBrowserActive = true

        if let tag,
           let normalizedTag = TagRules.normalizeTag(tag),
           let index = tagChips.firstIndex(of: normalizedTag) {
            focusedTagChipIndex = index + 1
            applyFocusedTagFilterChip()
            return
        }

        if let activeIndex = tagChips.firstIndex(where: { activeTagFilters.contains($0) }) {
            focusedTagChipIndex = activeIndex + 1
        } else {
            focusedTagChipIndex = 0
        }
        applyFocusedTagFilterChip()
    }

    func moveFocusedTagChip(by delta: Int) {
        guard !tagFilterChips.isEmpty else {
            focusedTagChipIndex = nil
            return
        }
        let currentIndex = focusedTagChipIndex ?? 0
        focusedTagChipIndex = min(max(currentIndex + delta, 0), tagFilterChips.count - 1)
        applyFocusedTagFilterChip()
    }

    func clearTagChipFocus() {
        focusedTagChipIndex = nil
    }

    func leaveTagBrowser() {
        isTagBrowserActive = false
        activeTagFilters.removeAll()
        clearTagChipFocus()
        focusNewestHistoryItemIfAvailable()
    }

    func isTagChipActive(_ chip: PickerTagChip) -> Bool {
        switch chip {
        case .all:
            return isTagBrowserActive && activeTagFilters.isEmpty && search.tags.isEmpty
        case .tag(let tag):
            return tagFilters.contains(tag)
        }
    }

    func selectTypeFilter(_ filter: PickerTypeFilter) {
        activeTypeFilter = filter
        selectedIndex = 0
        clearDeleteState()
    }

    func beginEditingTags(for item: ClipboardHistoryItem, currentText: String) {
        editingTagsItem = item
        tagEditorText = currentText
        revealedDeleteItem = nil
        deletingItem = nil
        focusedTagChipIndex = nil
    }

    func cancelEditingTags() {
        editingTagsItem = nil
        tagEditorText = ""
    }

    func showNotice(_ text: String) {
        notice = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard self?.notice == text else { return }
            self?.notice = nil
        }
    }

    func focusItem(_ item: ClipboardHistoryItem) {
        if let index = filteredItems.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
            selectedIndex = index
        }
    }

    private func resetTransientState() {
        pressedIndex = nil
        focusedTagChipIndex = nil
        isTagBrowserActive = false
        clearDeleteState()
        editingTagsItem = nil
        tagEditorText = ""
        hoveredItemID = nil
    }

    private func pruneTagFilterState() {
        let availableTags = Set(tagChips)
        activeTagFilters.formIntersection(availableTags)
        if tagFilterChips.isEmpty {
            focusedTagChipIndex = nil
            isTagBrowserActive = false
        } else if let focusedTagChipIndex, !tagFilterChips.indices.contains(focusedTagChipIndex) {
            self.focusedTagChipIndex = tagFilterChips.count - 1
        }
    }

    private func applyFocusedTagFilterChip() {
        guard let focusedTagFilterChip else { return }
        applyTagFilterChip(focusedTagFilterChip)
    }

    private func applyTagFilterChip(_ chip: PickerTagChip) {
        switch chip {
        case .all:
            activeTagFilters.removeAll()
        case .tag(let tag):
            activeTagFilters = [tag]
        }
        selectedIndex = 0
        clearDeleteState()
    }

    private func focusNewestHistoryItemIfAvailable() {
        guard !items.isEmpty else {
            clampSelectionToFilteredItems()
            return
        }
        let historyStartIndex = filteredPinnedItems.count + filteredTaggedItems.count
        guard filteredItems.indices.contains(historyStartIndex) else {
            clampSelectionToFilteredItems()
            return
        }
        selectedIndex = historyStartIndex
    }
}

// MARK: - Borderless panel that can become key

private final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

final class PickerWindowController: NSObject, NSWindowDelegate {
    private enum Metrics {
        static let pickerSize = NSSize(width: 360, height: 420)
        static let closeAnimationDuration: TimeInterval = 0.11
        static let pressFeedbackDuration: TimeInterval = 0.08
        static let pickerCornerRadius: CGFloat = 22
    }

    private let store: ClipboardStore
    private let settings: AppSettings
    private let state = PickerState()
    private var panel: FloatingPanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var pendingDismiss: DispatchWorkItem?
    private var isSelectionInFlight = false
    private let pasteHintToast = PasteHintToastController()

    /// Set by the app coordinator; ⌘L in the picker hands off to the Library.
    var onOpenLibrary: (() -> Void)?

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    deinit {
        removeKeyMonitor()
    }

    func show(editingTagsFor itemToEdit: ClipboardHistoryItem? = nil) {
        // Prevent opening a second picker if one is already visible.
        // Also avoids overwriting previousApp with Copypastik itself.
        guard !(panel?.isVisible ?? false) else {
            if let itemToEdit {
                state.query = ""
                state.activeTagFilters.removeAll()
                state.isTagBrowserActive = false
                state.replaceItemsPreservingQuery(store.items, taggedItems: store.taggedItems, pinnedItems: store.pinnedItems)
                settings.isTaggedSectionCollapsed = false
                state.isTaggedSectionCollapsed = false
                state.focusItem(itemToEdit)
                state.beginEditingTags(for: itemToEdit, currentText: store.tagsText(for: itemToEdit))
            }
            return
        }

        // Capture frontmost app before we steal focus
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil { buildPanel() }

        isSelectionInFlight = false
        if itemToEdit != nil {
            settings.isTaggedSectionCollapsed = false
        }
        state.prepareForPresentation(
            with: store.items,
            taggedItems: store.taggedItems,
            pinnedItems: store.pinnedItems,
            isTaggedSectionCollapsed: itemToEdit == nil ? settings.isTaggedSectionCollapsed : false,
            editing: itemToEdit
        )
        removeKeyMonitor()
        positionPanel()
        panel?.alphaValue = 1
        panel?.makeKeyAndOrderFront(nil)

        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    func dismiss() {
        dismiss(animated: true)
    }

    func dismiss(animated: Bool) {
        dismiss(animated: animated, completion: nil)
    }

    private func dismiss(animated: Bool, completion: (() -> Void)?) {
        guard let panel, panel.isVisible else {
            removeKeyMonitor()
            completion?()
            return
        }

        pendingDismiss?.cancel()
        removeKeyMonitor()
        state.isClosing = true

        let finish = { [weak self, weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            self?.pendingDismiss = nil
            self?.state.isClosing = false
            completion?()
        }

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            finish()
            return
        }

        let work = DispatchWorkItem(block: finish)
        pendingDismiss = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.closeAnimationDuration, execute: work)
    }

    // MARK: Private

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func buildPanel() {
        let p = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.pickerSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = true
        p.isMovableByWindowBackground = true
        p.hidesOnDeactivate = false
        p.delegate = self

        let rootView = ClipboardPickerView(
            state: state,
            settings: settings,
            onSelect: { [weak self] index in self?.selectItem(at: index) },
            onRevealDelete: { [weak self] index in self?.revealDelete(at: index) },
            onBeginDelete: { [weak self] index in self?.beginDelete(at: index) },
            onConfirmDelete: { [weak self] item in self?.deleteItem(item) },
            onMoveSelection: { [weak self] delta in self?.moveSelection(by: delta) },
            onConfirmSelection: { [weak self] in self?.confirmSelection() },
            onToggleTaggedSection: { [weak self] in self?.toggleTaggedSection() },
            onSelectTagChip: { [weak self] chip in self?.selectTagChip(chip) },
            onSelectTypeFilter: { [weak self] filter in self?.state.selectTypeFilter(filter) },
            onTogglePin: { [weak self] item in self?.togglePin(item) },
            onBeginTagEdit: { [weak self] index in self?.beginTagEdit(at: index) },
            onCommitTagEdit: { [weak self] in self?.commitTagEdit() },
            onCancelTagEdit: { [weak self] in self?.cancelTagEdit() },
            onClearHistory: { [weak self] in self?.clearHistory() },
            onClose:  { [weak self] in self?.dismiss() }
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.cornerRadius = Metrics.pickerCornerRadius
        hostingView.layer?.masksToBounds = true
        if #available(macOS 10.15, *) {
            hostingView.layer?.cornerCurve = .continuous
        }
        p.contentView = hostingView
        panel = p
    }

    func windowDidResignKey(_ notification: Notification) {
        guard panel?.isVisible == true else { return }
        dismiss()
    }

    private func positionPanel() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let screen else { return }
        let sz = panel.frame.size
        let sf = screen.visibleFrame
        let x = min(max(mouse.x - sz.width / 2, sf.minX), sf.maxX - sz.width)
        let y = min(max(mouse.y + 20, sf.minY), sf.maxY - sz.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        if state.isEditingTags {
            switch event.keyCode {
            case 36, 76: // Return / numpad Enter
                commitTagEdit()
                return nil
            case 53: // Escape
                cancelTagEdit()
                return nil
            default:
                return event
            }
        }

        if Self.isTagEditShortcut(event) {
            state.clearTagChipFocus()
            beginTagEdit(at: state.selectedIndex)
            return nil
        }

        if Self.isLibraryShortcut(event) {
            dismiss(animated: false)
            onOpenLibrary?()
            return nil
        }

        if Self.isPinShortcut(event) {
            if let item = item(atFilteredIndex: state.selectedIndex) {
                togglePin(item)
            }
            return nil
        }

        if let slot = Self.quickSlotAssignment(for: event) {
            assignSelectedItem(toSlot: slot)
            return nil
        }

        switch event.keyCode {
        case 125: // Down arrow
            if state.focusedTagChipIndex != nil {
                state.clearTagChipFocus()
                state.clampSelectionToFilteredItems()
                return nil
            }
            if state.filteredItems.isEmpty, !state.tagFilterChips.isEmpty {
                focusTagChips()
                return nil
            }
            moveSelection(by: 1)
            return nil
        case 126: // Up arrow
            if state.focusedTagChipIndex != nil {
                return nil
            }
            if state.shouldFocusTagChipsOnUp {
                focusTagChips()
                return nil
            }
            moveSelection(by: -1)
            return nil
        case 123: // Left arrow
            if state.focusedTagChipIndex != nil {
                state.moveFocusedTagChip(by: -1)
                return nil
            }
            revealOrDeleteSelectedItem()
            return nil
        case 124: // Right arrow
            if state.focusedTagChipIndex != nil {
                state.moveFocusedTagChip(by: 1)
                return nil
            }
            state.revealedDeleteItem = nil
            return nil
        case 36, 76: // Return / numpad Enter
            if state.focusedTagChipIndex != nil {
                state.activateFocusedTagChip()
                return nil
            }
            confirmSelection()
            return nil
        case 53: // Escape
            dismiss()
            return nil
        default:
            return event
        }
    }

    static func isTagEditShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.contains(.command) && event.keyCode == UInt16(kVK_ANSI_T)
    }

    static func isLibraryShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers == .command && event.keyCode == UInt16(kVK_ANSI_L)
    }

    static func isPinShortcut(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return modifiers.contains(.command) && event.keyCode == UInt16(kVK_ANSI_P)
    }

    private static let quickSlotKeyCodes: [UInt16: Int] = [
        UInt16(kVK_ANSI_1): 1,
        UInt16(kVK_ANSI_2): 2,
        UInt16(kVK_ANSI_3): 3,
        UInt16(kVK_ANSI_4): 4,
        UInt16(kVK_ANSI_5): 5,
        UInt16(kVK_ANSI_6): 6,
        UInt16(kVK_ANSI_7): 7,
        UInt16(kVK_ANSI_8): 8,
        UInt16(kVK_ANSI_9): 9
    ]

    static func quickSlotAssignment(for event: NSEvent) -> Int? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command) else { return nil }
        return quickSlotKeyCodes[event.keyCode]
    }

    private func moveSelection(by delta: Int) {
        state.clearTagChipFocus()
        let count = state.filteredItems.count
        guard count > 0 else { return }
        state.selectedIndex = min(max(state.selectedIndex + delta, 0), count - 1)
        state.clearDeleteState()
    }

    private func clearHistory() {
        store.clearHistory()
        state.prepareForPresentation(
            with: store.items,
            taggedItems: store.taggedItems,
            pinnedItems: store.pinnedItems,
            isTaggedSectionCollapsed: settings.isTaggedSectionCollapsed
        )
    }

    private func revealDelete(at index: Int) {
        guard let item = item(atFilteredIndex: index) else { return }
        state.selectedIndex = index
        state.revealedDeleteItem = item
    }

    private func revealOrDeleteSelectedItem() {
        guard let item = item(atFilteredIndex: state.selectedIndex) else { return }
        if state.revealedDeleteItem == item {
            beginDelete(at: state.selectedIndex)
        } else {
            state.revealedDeleteItem = item
        }
    }

    private func beginDelete(at index: Int) {
        guard let item = item(atFilteredIndex: index) else { return }
        state.selectedIndex = index
        state.revealedDeleteItem = item
        state.deletingItem = item
    }

    private func item(atFilteredIndex index: Int) -> ClipboardHistoryItem? {
        let filtered = state.filteredItems
        guard filtered.indices.contains(index) else { return nil }
        return filtered[index]
    }

    private func deleteItem(_ item: ClipboardHistoryItem) {
        store.deleteItem(item)
        state.replaceItemsPreservingQuery(store.items, taggedItems: store.taggedItems, pinnedItems: store.pinnedItems)
    }

    private func togglePin(_ item: ClipboardHistoryItem) {
        let isPinned = store.togglePin(item)
        state.replaceItemsPreservingQuery(store.items, taggedItems: store.taggedItems, pinnedItems: store.pinnedItems)
        state.focusItem(item)

        if isPinned {
            if let slot = store.pinnedSlot(for: item) {
                state.showNotice("Pinned · ⌃⌥\(slot) pastes it")
            } else {
                state.showNotice("Pinned")
            }
        } else {
            state.showNotice("Unpinned")
        }
    }

    private func assignSelectedItem(toSlot slot: Int) {
        guard let item = item(atFilteredIndex: state.selectedIndex) else { return }
        guard store.isPinned(item) else {
            state.showNotice("Pin with ⌘P first")
            return
        }
        store.assignPinnedSlot(slot, to: item)
        state.replaceItemsPreservingQuery(store.items, taggedItems: store.taggedItems, pinnedItems: store.pinnedItems)
        state.focusItem(item)
        state.showNotice("Assigned · ⌃⌥\(slot) pastes it")
    }

    private func toggleTaggedSection() {
        settings.isTaggedSectionCollapsed.toggle()
        state.isTaggedSectionCollapsed = settings.isTaggedSectionCollapsed
        state.clampSelectionToFilteredItems()
    }

    private func selectTagChip(_ chip: PickerTagChip) {
        expandTaggedSectionIfNeeded()
        state.selectTagChip(chip)
        state.clampSelectionToFilteredItems()
    }

    private func focusTagChips() {
        expandTaggedSectionIfNeeded()
        state.focusTagChips()
    }

    private func expandTaggedSectionIfNeeded() {
        guard settings.isTaggedSectionCollapsed else { return }
        settings.isTaggedSectionCollapsed = false
        state.isTaggedSectionCollapsed = false
    }

    private func beginTagEdit(at index: Int) {
        guard let item = item(atFilteredIndex: index) else { return }
        state.selectedIndex = index
        state.beginEditingTags(for: item, currentText: store.tagsText(for: item))
    }

    private func commitTagEdit() {
        guard let item = state.editingTagsItem else { return }
        let result = store.setTags(for: item, rawTags: state.tagEditorText)
        state.cancelEditingTags()
        state.replaceItemsPreservingQuery(store.items, taggedItems: store.taggedItems, pinnedItems: store.pinnedItems)

        switch result {
        case .saved:
            state.showNotice("Tags saved")
        case .removed:
            state.showNotice("Tags removed")
        case .taggedLimitReached:
            state.showNotice("Tagged snippets limit reached")
        }
    }

    private func cancelTagEdit() {
        state.cancelEditingTags()
    }

    private func confirmSelection() {
        guard !isSelectionInFlight else { return }
        state.revealedDeleteItem = nil
        isSelectionInFlight = true

        let index = state.selectedIndex
        state.pressedIndex = index

        let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Metrics.pressFeedbackDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.state.pressedIndex = nil
            self?.selectItem(at: index)
        }
    }

    private func selectItem(at index: Int) {
        guard !isSelectionInFlight || state.pressedIndex == nil else { return }
        isSelectionInFlight = true

        let filtered = state.filteredItems
        guard index >= 0, index < filtered.count else {
            isSelectionInFlight = false
            return
        }
        store.copyItem(filtered[index])
        settings.refreshPasteAutomationPermission()
        let shouldPaste = settings.isAutomaticPasteEnabled && settings.hasPostEventAccess
        dismiss(animated: true) { [weak self] in
            guard let self else { return }
            if shouldPaste {
                pasteIntoPreviousApp()
            } else {
                reactivatePreviousApp()
                showManualPasteHintIfNeeded()
            }
        }
    }

    private func pasteIntoPreviousApp() {
        settings.refreshPasteAutomationPermission()
        guard settings.isAutomaticPasteEnabled, settings.hasPostEventAccess else {
            reactivatePreviousApp()
            showManualPasteHintIfNeeded()
            return
        }

        reactivatePreviousApp()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteAutomationService.postPasteCommand()
        }
    }

    private func showManualPasteHintIfNeeded() {
        guard settings.isPasteHintEnabled else { return }
        pasteHintToast.show(relativeTo: previousApp)
    }

    private func reactivatePreviousApp() {
        guard let app = previousApp else { return }

        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
    }
}

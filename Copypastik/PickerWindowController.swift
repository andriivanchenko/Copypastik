import AppKit
import Combine
import SwiftUI

// MARK: - Shared state

final class PickerState: ObservableObject {
    @Published var items: [ClipboardHistoryItem] = []
    @Published var selectedIndex: Int = 0 {
        didSet {
            guard oldValue != selectedIndex else { return }
            print("[Copypastik] selected index changed: \(selectedIndex)")
        }
    }
    @Published var query: String = "" {
        didSet {
            guard oldValue != query else { return }
            print("[Copypastik] search query changed: \(query)")
        }
    }
    @Published var searchFocusTrigger: Int = 0
    @Published var presentationID: Int = 0
    @Published var isClosing: Bool = false
    @Published var pressedIndex: Int?
    @Published var revealedDeleteItem: ClipboardHistoryItem?
    @Published var deletingItem: ClipboardHistoryItem?

    private var cancellables = Set<AnyCancellable>()

    init() {
        // Reset selection to top whenever the query changes so the user
        // always starts navigating from the best match.
        $query
            .dropFirst()
            .sink { [weak self] _ in
                self?.selectedIndex = 0
                self?.clearDeleteState()
            }
            .store(in: &cancellables)
    }

    var filteredItems: [ClipboardHistoryItem] {
        let q = normalizedQuery
        guard !q.isEmpty else { return items }
        return items.filter { $0.searchText.localizedCaseInsensitiveContains(q) }
    }

    var normalizedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var matchCountLabel: String {
        if items.isEmpty {
            return "0 items"
        }

        if normalizedQuery.isEmpty {
            return "\(items.count) \(items.count == 1 ? "item" : "items")"
        }

        let count = filteredItems.count
        return count == 0 ? "No matches" : "\(count) \(count == 1 ? "match" : "matches")"
    }

    func prepareForPresentation(with items: [ClipboardHistoryItem]) {
        self.items = items
        query = ""
        selectedIndex = 0
        resetTransientState()
        isClosing = false
        presentationID += 1
        searchFocusTrigger += 1
    }

    func replaceItemsPreservingQuery(_ items: [ClipboardHistoryItem]) {
        self.items = items
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

    private func resetTransientState() {
        pressedIndex = nil
        clearDeleteState()
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

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    deinit {
        removeKeyMonitor()
    }

    func show() {
        print("[Copypastik] picker show() called")
        // Prevent opening a second picker if one is already visible.
        // Also avoids overwriting previousApp with Copypastik itself.
        guard !(panel?.isVisible ?? false) else { return }

        // Capture frontmost app before we steal focus
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil { buildPanel() }

        isSelectionInFlight = false
        state.prepareForPresentation(with: store.items)
        removeKeyMonitor()
        positionPanel()
        panel?.alphaValue = 1
        panel?.makeKeyAndOrderFront(nil)
        if panel?.isVisible == true {
            print("[Copypastik] picker window became visible")
        }

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
        guard let panel, panel.isVisible else {
            removeKeyMonitor()
            return
        }

        pendingDismiss?.cancel()
        removeKeyMonitor()
        state.isClosing = true

        let finish = { [weak self, weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
            self?.state.isClosing = false
            print("[Copypastik] picker closed")
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
            onSelect: { [weak self] index in self?.selectItem(at: index) },
            onRevealDelete: { [weak self] index in self?.revealDelete(at: index) },
            onBeginDelete: { [weak self] index in self?.beginDelete(at: index) },
            onConfirmDelete: { [weak self] item in self?.deleteItem(item) },
            onMoveSelection: { [weak self] delta in self?.moveSelection(by: delta) },
            onConfirmSelection: { [weak self] in self?.confirmSelection() },
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
        guard let panel, let screen = NSScreen.main else { return }
        let mouse = NSEvent.mouseLocation
        let sz = panel.frame.size
        let sf = screen.visibleFrame
        let x = min(max(mouse.x - sz.width / 2, sf.minX), sf.maxX - sz.width)
        let y = min(max(mouse.y + 20, sf.minY), sf.maxY - sz.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        switch event.keyCode {
        case 125: // Down arrow
            moveSelection(by: 1)
            return nil
        case 126: // Up arrow
            moveSelection(by: -1)
            return nil
        case 123: // Left arrow
            revealOrDeleteSelectedItem()
            return nil
        case 124: // Right arrow
            state.revealedDeleteItem = nil
            return nil
        case 36, 76: // Return / numpad Enter
            confirmSelection()
            return nil
        case 53: // Escape
            dismiss()
            return nil
        default:
            return event
        }
    }

    private func moveSelection(by delta: Int) {
        let count = state.filteredItems.count
        guard count > 0 else { return }
        state.selectedIndex = min(max(state.selectedIndex + delta, 0), count - 1)
        state.clearDeleteState()
    }

    private func clearHistory() {
        store.clearHistory()
        state.prepareForPresentation(with: store.items)
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
        state.replaceItemsPreservingQuery(store.items)
        print("[Copypastik] clipboard history item deleted")
    }

    private func confirmSelection() {
        guard !isSelectionInFlight else { return }
        state.revealedDeleteItem = nil
        isSelectionInFlight = true

        print("[Copypastik] Enter pressed")
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
        print("[Copypastik] item selected for paste")
        store.copyItem(filtered[index])
        dismiss()
        pasteIntoPreviousApp()
    }

    private func pasteIntoPreviousApp() {
        guard HotkeyService.isAccessibilityGranted else {
            showAccessibilityWarning()
            return
        }
        guard let app = previousApp else { return }

        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }
        print("[Copypastik] previous app activation attempted")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            Self.simulateCmdV()
        }
    }

    private static func simulateCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        print("[Copypastik] Cmd+V simulated")
    }

    private func showAccessibilityWarning() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "Your item is on the clipboard — press ⌘V to paste manually.\n\nTo enable instant paste: System Settings → Privacy & Security → Accessibility → enable Copypastik."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "OK")
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        if alert.runModal() == .alertFirstButtonReturn {
            settings.openAccessibilitySettings()
        }
    }
}

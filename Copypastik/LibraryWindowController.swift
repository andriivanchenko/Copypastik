import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Owns the single Library window. Reopening focuses the existing window
/// instead of creating another one.
///
/// Copypastik is a menu bar (`LSUIElement`) app, so while the Library is open
/// the app temporarily becomes a regular app: it gets a Dock icon and menu
/// bar, which a normal document-style window needs for standard keyboard
/// shortcuts and window switching. It reverts to a menu bar app on close.
final class LibraryWindowController: NSObject, NSWindowDelegate {
    private enum Metrics {
        static let defaultSize = NSSize(width: 1080, height: 700)
        static let minimumSize = NSSize(width: 860, height: 480)
        static let frameAutosaveName = "CopypastikLibraryWindow"
    }

    private let store: ClipboardStore
    private let settings: AppSettings
    let state: LibraryState
    private var window: NSWindow?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(store: ClipboardStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        state = LibraryState(store: store, settings: settings)
        super.init()
        state.pasteIntoPreviousApp = { [weak self] in
            self?.pasteIntoPreviousApp() ?? false
        }
    }

    deinit {
        removeKeyMonitor()
    }

    var isVisible: Bool {
        window?.isVisible ?? false
    }

    func show() {
        let ownBundleID = Bundle.main.bundleIdentifier
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.bundleIdentifier != ownBundleID {
            previousApp = frontmost
        }

        let isAlreadyOpen = window?.isVisible ?? false

        if window == nil {
            buildWindow()
        }
        guard let window else { return }

        NSApp.setActivationPolicy(.regular)

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }

        if !isAlreadyOpen {
            LibraryDragProvider.cleanUpTemporaryFiles()
            state.prepareForPresentation()
        } else {
            state.searchFocusTrigger += 1
        }

        window.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func close() {
        window?.performClose(nil)
    }

    // MARK: Window

    private func buildWindow() {
        let hostingController = NSHostingController(
            rootView: LibraryView(state: state, store: store, settings: settings)
        )

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Copypastik Library"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = Metrics.minimumSize
        window.setContentSize(Metrics.defaultSize)
        window.center()
        window.setFrameAutosaveName(Metrics.frameAutosaveName)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.delegate = self
        self.window = window
    }

    func windowDidBecomeKey(_ notification: Notification) {
        installKeyMonitor()
    }

    func windowDidResignKey(_ notification: Notification) {
        removeKeyMonitor()
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
        state.pendingDelete = nil
        state.isAddingTag = false
        // Go back to being a menu bar app once the window is gone.
        DispatchQueue.main.async {
            if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) == false {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }

    // MARK: Paste

    private func pasteIntoPreviousApp() -> Bool {
        settings.refreshPasteAutomationPermission()
        guard settings.isAutomaticPasteEnabled,
              settings.hasPostEventAccess,
              let app = previousApp,
              !app.isTerminated else {
            return false
        }

        if #available(macOS 14.0, *) {
            app.activate()
        } else {
            app.activate(options: .activateIgnoringOtherApps)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            PasteAutomationService.postPasteCommand()
        }
        return true
    }

    // MARK: Keyboard

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) ?? event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private static let quickSlotKeyCodes: [Int: Int] = [
        kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5,
        kVK_ANSI_6: 6, kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9
    ]

    private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, window.attachedSheet == nil else { return event }

        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let keyCode = Int(event.keyCode)
        let isEditingText = (window.firstResponder as? NSText)?.isFieldEditor == true

        if modifiers.contains(.command) {
            return handleCommandKey(keyCode, isEditingText: isEditingText) ? nil : event
        }

        switch keyCode {
        case kVK_DownArrow:
            state.moveSelection(by: 1, extending: modifiers.contains(.shift))
            return nil
        case kVK_UpArrow:
            state.moveSelection(by: -1, extending: modifiers.contains(.shift))
            return nil
        case kVK_Return, kVK_ANSI_KeypadEnter:
            state.activateSelection()
            return nil
        case kVK_Escape:
            if !state.dismissLayer() {
                window.performClose(nil)
            }
            return nil
        case kVK_Delete, kVK_ForwardDelete:
            // In the search field these keys edit text.
            guard !isEditingText else { return event }
            state.requestDeleteSelection()
            return nil
        default:
            return event
        }
    }

    /// Returns true when the shortcut was handled.
    private func handleCommandKey(_ keyCode: Int, isEditingText: Bool) -> Bool {
        switch keyCode {
        case kVK_ANSI_W:
            window?.performClose(nil)
            return true
        case kVK_ANSI_F:
            state.searchFocusTrigger += 1
            return true
        case kVK_ANSI_P:
            state.togglePinSelection()
            return true
        case kVK_ANSI_T:
            state.beginAddTag()
            return true
        case kVK_ANSI_A where !isEditingText:
            state.selectAllVisible()
            return true
        case kVK_Delete, kVK_ForwardDelete:
            state.requestDeleteSelection()
            return true
        default:
            if let slot = Self.quickSlotKeyCodes[keyCode] {
                if let item = state.singleSelectedItem {
                    state.assignSlot(slot, to: item)
                }
                return true
            }
            return false
        }
    }
}

//
//  CopypastikApp.swift
//  Copypastik
//
//  Created by Andrii Ivanchenko on 27.04.2026.
//

import AppKit
import Combine
import SwiftUI

// Owns all long-lived services for the app's lifetime.
final class AppCoordinator: ObservableObject {
    let settings = AppSettings()
    let store: ClipboardStore
    private let hotkey = HotkeyService()
    private let quickSlotHotkey = QuickSlotHotkeyService()
    private let libraryHotkey = LibraryHotkeyService()
    private let quickSlotPasteHintToast = PasteHintToastController()
    private lazy var picker = PickerWindowController(store: store, settings: settings)
    private lazy var library = LibraryWindowController(store: store, settings: settings)
    private var statusItemController: StatusItemController?
    private var onboardingWindowController: OnboardingWindowController?
    private var cancellables = Set<AnyCancellable>()

    init() {
        print("[Copypastik] app launched")
        store = ClipboardStore(
            settings: settings,
            historyStore: HistoryStore(),
            textRecognizer: { data in await TextRecognizer.recognizeText(in: data) }
        )
        picker.onOpenLibrary = { [weak self] in self?.library.show() }
        hotkey.onTrigger = { [weak self] in self?.picker.show() }
        hotkey.start(shortcut: settings.pickerShortcut)
        settings.$pickerShortcut
            .dropFirst()
            .sink { [weak self] shortcut in
                self?.hotkey.updateShortcut(shortcut)
            }
            .store(in: &cancellables)

        quickSlotHotkey.onTrigger = { [weak self] slot in self?.triggerQuickSlot(slot) }
        quickSlotHotkey.start()

        libraryHotkey.onTrigger = { [weak self] in self?.library.show() }
        libraryHotkey.start()

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.settings.refreshPasteAutomationPermission()
            }
            .store(in: &cancellables)

        onboardingWindowController = OnboardingWindowController(settings: settings)
        statusItemController = StatusItemController(
            store: store,
            settings: settings,
            onOpenPicker: { [weak self] in
                self?.picker.show()
            },
            onOpenLibrary: { [weak self] in
                self?.library.show()
            },
            onEditSnippetTags: { [weak self] item in
                self?.picker.show(editingTagsFor: item)
            },
            onShowOnboarding: { [weak self] in
                self?.showOnboarding()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    private func showOnboarding() {
        onboardingWindowController?.show()
    }

    /// Pastes/copies the pinned clip assigned to `slot`. If the slot is
    /// empty, opens the picker instead of failing silently.
    private func triggerQuickSlot(_ slot: Int) {
        guard let item = store.pinnedItem(forSlot: slot) else {
            picker.show()
            return
        }

        let targetApp = NSWorkspace.shared.frontmostApplication
        store.copyItem(item)
        settings.refreshPasteAutomationPermission()

        if settings.isAutomaticPasteEnabled, settings.hasPostEventAccess {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                PasteAutomationService.postPasteCommand()
            }
        } else {
            // No picker is on screen during a Quick Slot trigger, so this
            // toast is the only signal the clip landed on the clipboard.
            // Shown regardless of the paste-hint setting.
            quickSlotPasteHintToast.show(relativeTo: targetApp, message: "Slot \(slot) copied · ⌘V to paste")
        }
    }
}

@main
struct CopypastikApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        Settings {
            EmptyView()
                .frame(width: 0, height: 0)
        }
    }
}

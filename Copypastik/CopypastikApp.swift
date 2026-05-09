//
//  CopypastikApp.swift
//  Copypastik
//
//  Created by Andrii Ivanchenko on 27.04.2026.
//

import Combine
import SwiftUI

// Owns all long-lived services for the app's lifetime.
final class AppCoordinator: ObservableObject {
    let settings = AppSettings()
    let store: ClipboardStore
    private let hotkey = HotkeyService()
    private lazy var picker = PickerWindowController(store: store, settings: settings)
    private var statusItemController: StatusItemController?
    private var onboardingWindowController: OnboardingWindowController?

    init() {
        print("[Copypastik] app launched")
        store = ClipboardStore(settings: settings)
        DispatchQueue.main.async {
            HotkeyService.requestAccessibilityIfNeeded()
        }
        hotkey.onTrigger = { [weak self] in self?.picker.show() }
        hotkey.start()

        onboardingWindowController = OnboardingWindowController(settings: settings)
        statusItemController = StatusItemController(
            store: store,
            settings: settings,
            onShowOnboarding: { [weak self] in
                self?.showOnboarding()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        if !settings.hasCompletedOnboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showOnboarding()
            }
        }
    }

    private func showOnboarding() {
        onboardingWindowController?.show()
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

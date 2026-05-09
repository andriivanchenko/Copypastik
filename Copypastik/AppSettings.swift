import AppKit
import Combine
import Foundation
import ServiceManagement

final class AppSettings: ObservableObject {
    static let defaultHistoryLimit = 20

    private enum Keys {
        static let launchAtLogin = "settings.launchAtLogin"
        static let clipboardHistory = "settings.clipboardHistory"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
    }

    @Published var isLaunchAtLoginEnabled: Bool {
        didSet {
            defaults.set(isLaunchAtLoginEnabled, forKey: Keys.launchAtLogin)
            applyLaunchAtLoginPreference()
        }
    }

    @Published var isClipboardHistoryEnabled: Bool {
        didSet {
            defaults.set(isClipboardHistoryEnabled, forKey: Keys.clipboardHistory)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    private let defaults: UserDefaults
    private let managesLaunchAtLogin: Bool

    init(defaults: UserDefaults = .standard, managesLaunchAtLogin: Bool = true) {
        self.defaults = defaults
        self.managesLaunchAtLogin = managesLaunchAtLogin

        isLaunchAtLoginEnabled = Self.boolValue(for: Keys.launchAtLogin, in: defaults, defaultValue: true)
        isClipboardHistoryEnabled = Self.boolValue(for: Keys.clipboardHistory, in: defaults, defaultValue: true)
        hasCompletedOnboarding = Self.boolValue(for: Keys.hasCompletedOnboarding, in: defaults, defaultValue: false)

        applyLaunchAtLoginPreference()
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
    }

    func openAccessibilitySettings() {
        HotkeyService.requestAccessibilityIfNeeded()

        let settingsURLs = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.SystemPreferences"
        ]

        for settingsURL in settingsURLs {
            guard let url = URL(string: settingsURL) else { continue }
            if NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    private func applyLaunchAtLoginPreference() {
        guard managesLaunchAtLogin, #available(macOS 13.0, *) else { return }

        do {
            if isLaunchAtLoginEnabled {
                try SMAppService.mainApp.register()
                print("[Copypastik] launch at login enabled")
            } else {
                try SMAppService.mainApp.unregister()
                print("[Copypastik] launch at login disabled")
            }
        } catch {
            print("[Copypastik] launch at login update skipped: \(error.localizedDescription)")
        }
    }

    private static func boolValue(for key: String, in defaults: UserDefaults, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}

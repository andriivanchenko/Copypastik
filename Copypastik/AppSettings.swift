import AppKit
import Carbon.HIToolbox
import Combine
import Foundation
import ServiceManagement

enum PickerShortcut: String, CaseIterable, Identifiable {
    case controlOptionV = "controlOptionV"
    case commandShiftV = "commandShiftV"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .controlOptionV:
            return "Control + Option + V"
        case .commandShiftV:
            return "Command + Shift + V"
        }
    }

    var keyCode: UInt32 {
        UInt32(kVK_ANSI_V)
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .controlOptionV:
            return UInt32(controlKey | optionKey)
        case .commandShiftV:
            return UInt32(cmdKey | shiftKey)
        }
    }
}

enum ClipboardHistoryLimit: Int, CaseIterable, Identifiable {
    case twenty = 20
    case fifty = 50
    case hundred = 100

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)"
    }
}

final class AppSettings: ObservableObject {
    static let defaultHistoryLimit = ClipboardHistoryLimit.twenty.rawValue

    private enum Keys {
        static let launchAtLogin = "settings.launchAtLogin"
        static let clipboardHistory = "settings.clipboardHistory"
        static let historyLimit = "settings.historyLimit"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let pickerShortcut = "settings.pickerShortcut"
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

    @Published var historyLimit: ClipboardHistoryLimit {
        didSet {
            defaults.set(historyLimit.rawValue, forKey: Keys.historyLimit)
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding)
        }
    }

    @Published var pickerShortcut: PickerShortcut {
        didSet {
            defaults.set(pickerShortcut.rawValue, forKey: Keys.pickerShortcut)
        }
    }

    private let defaults: UserDefaults
    private let managesLaunchAtLogin: Bool

    init(defaults: UserDefaults = .standard, managesLaunchAtLogin: Bool = true) {
        self.defaults = defaults
        self.managesLaunchAtLogin = managesLaunchAtLogin

        isLaunchAtLoginEnabled = Self.boolValue(for: Keys.launchAtLogin, in: defaults, defaultValue: true)
        isClipboardHistoryEnabled = Self.boolValue(for: Keys.clipboardHistory, in: defaults, defaultValue: true)
        historyLimit = Self.historyLimitValue(for: Keys.historyLimit, in: defaults)
        hasCompletedOnboarding = Self.boolValue(for: Keys.hasCompletedOnboarding, in: defaults, defaultValue: false)
        pickerShortcut = Self.shortcutValue(for: Keys.pickerShortcut, in: defaults)

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

    private static func shortcutValue(for key: String, in defaults: UserDefaults) -> PickerShortcut {
        guard let rawValue = defaults.string(forKey: key) else { return .controlOptionV }
        return PickerShortcut(rawValue: rawValue) ?? .controlOptionV
    }

    private static func historyLimitValue(for key: String, in defaults: UserDefaults) -> ClipboardHistoryLimit {
        guard defaults.object(forKey: key) != nil else { return .twenty }
        return ClipboardHistoryLimit(rawValue: defaults.integer(forKey: key)) ?? .twenty
    }
}

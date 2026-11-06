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
    case twoHundredFifty = 250
    case fiveHundred = 500

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)"
    }
}

enum CapturePauseDuration: CaseIterable, Identifiable {
    case fiveMinutes
    case thirtyMinutes
    case untilResumed

    var id: String {
        switch self {
        case .fiveMinutes: return "5m"
        case .thirtyMinutes: return "30m"
        case .untilResumed: return "untilResumed"
        }
    }

    var displayName: String {
        switch self {
        case .fiveMinutes:
            return "5 Minutes"
        case .thirtyMinutes:
            return "30 Minutes"
        case .untilResumed:
            return "Until Resumed"
        }
    }

    /// `nil` means the pause has no automatic expiry.
    var timeInterval: TimeInterval? {
        switch self {
        case .fiveMinutes:
            return 5 * 60
        case .thirtyMinutes:
            return 30 * 60
        case .untilResumed:
            return nil
        }
    }
}

enum DefaultSensitiveApps {
    /// Common password managers, ignored by default so their clipboard
    /// contents never enter history unless the user explicitly removes them.
    static let bundleIDs: Set<String> = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.agilebits.onepassword7",
        "com.agilebits.onepassword-osx",
        "com.1password.1password",
        "com.1password.1password7",
        "com.lastpass.lastpassmacdesktop",
        "com.bitwarden.desktop",
        "com.dashlane.dashlanephonefinal"
    ]
}

final class AppSettings: ObservableObject {
    static let defaultHistoryLimit = ClipboardHistoryLimit.twenty.rawValue

    private enum Keys {
        static let launchAtLogin = "settings.launchAtLogin"
        static let clipboardHistory = "settings.clipboardHistory"
        static let historyLimit = "settings.historyLimit"
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let pickerShortcut = "settings.pickerShortcut"
        static let automaticPaste = "settings.automaticPaste"
        static let pasteHint = "settings.pasteHint"
        static let taggedSectionCollapsed = "settings.taggedSectionCollapsed"
        static let tagColors = "settings.tagColors"
        static let capturePausedUntil = "settings.capturePausedUntil"
        static let capturePausedIndefinitely = "settings.capturePausedIndefinitely"
        static let ignoredAppBundleIDs = "settings.ignoredAppBundleIDs"
        static let hasSeededIgnoredApps = "settings.hasSeededIgnoredApps"
        static let imageTextRecognition = "settings.imageTextRecognition"
        static let historyPersistence = "settings.historyPersistence"
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

    /// Runs Apple Vision text recognition on copied images, entirely on-device.
    @Published var isImageTextRecognitionEnabled: Bool {
        didSet {
            defaults.set(isImageTextRecognitionEnabled, forKey: Keys.imageTextRecognition)
        }
    }

    /// Keeps clipboard history on disk between launches so the Library
    /// survives a relaunch. When off, history is memory-only like in 1.3.
    @Published var isHistoryPersistenceEnabled: Bool {
        didSet {
            defaults.set(isHistoryPersistenceEnabled, forKey: Keys.historyPersistence)
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

    @Published var isAutomaticPasteEnabled: Bool {
        didSet {
            defaults.set(isAutomaticPasteEnabled, forKey: Keys.automaticPaste)
        }
    }

    @Published var isPasteHintEnabled: Bool {
        didSet {
            defaults.set(isPasteHintEnabled, forKey: Keys.pasteHint)
        }
    }

    @Published var isTaggedSectionCollapsed: Bool {
        didSet {
            defaults.set(isTaggedSectionCollapsed, forKey: Keys.taggedSectionCollapsed)
        }
    }

    @Published private(set) var tagColorIDsByTag: [String: String] {
        didSet {
            defaults.set(tagColorIDsByTag, forKey: Keys.tagColors)
        }
    }

    @Published private(set) var hasPostEventAccess: Bool

    @Published private(set) var capturePausedUntil: Date? {
        didSet {
            defaults.set(capturePausedUntil, forKey: Keys.capturePausedUntil)
        }
    }

    @Published private(set) var isCapturePausedIndefinitely: Bool {
        didSet {
            defaults.set(isCapturePausedIndefinitely, forKey: Keys.capturePausedIndefinitely)
        }
    }

    @Published private(set) var ignoredAppBundleIDs: Set<String> {
        didSet {
            defaults.set(Array(ignoredAppBundleIDs), forKey: Keys.ignoredAppBundleIDs)
        }
    }

    private let defaults: UserDefaults
    private let managesLaunchAtLogin: Bool
    private var pauseResumeTimer: Timer?

    init(defaults: UserDefaults = .standard, managesLaunchAtLogin: Bool = true) {
        self.defaults = defaults
        self.managesLaunchAtLogin = managesLaunchAtLogin

        if managesLaunchAtLogin, #available(macOS 13.0, *) {
            isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isLaunchAtLoginEnabled = Self.boolValue(for: Keys.launchAtLogin, in: defaults, defaultValue: false)
        }
        isClipboardHistoryEnabled = Self.boolValue(for: Keys.clipboardHistory, in: defaults, defaultValue: true)
        historyLimit = Self.historyLimitValue(for: Keys.historyLimit, in: defaults)
        isImageTextRecognitionEnabled = Self.boolValue(for: Keys.imageTextRecognition, in: defaults, defaultValue: true)
        isHistoryPersistenceEnabled = Self.boolValue(for: Keys.historyPersistence, in: defaults, defaultValue: true)
        hasCompletedOnboarding = Self.boolValue(for: Keys.hasCompletedOnboarding, in: defaults, defaultValue: false)
        pickerShortcut = Self.shortcutValue(for: Keys.pickerShortcut, in: defaults)
        isAutomaticPasteEnabled = Self.boolValue(for: Keys.automaticPaste, in: defaults, defaultValue: false)
        isPasteHintEnabled = Self.boolValue(for: Keys.pasteHint, in: defaults, defaultValue: true)
        isTaggedSectionCollapsed = Self.boolValue(for: Keys.taggedSectionCollapsed, in: defaults, defaultValue: true)
        tagColorIDsByTag = Self.tagColorIDs(for: Keys.tagColors, in: defaults)
        hasPostEventAccess = PasteAutomationService.hasPostEventAccess

        capturePausedUntil = defaults.object(forKey: Keys.capturePausedUntil) as? Date
        isCapturePausedIndefinitely = Self.boolValue(for: Keys.capturePausedIndefinitely, in: defaults, defaultValue: false)

        if defaults.object(forKey: Keys.hasSeededIgnoredApps) == nil {
            ignoredAppBundleIDs = DefaultSensitiveApps.bundleIDs
            defaults.set(Array(DefaultSensitiveApps.bundleIDs), forKey: Keys.ignoredAppBundleIDs)
            defaults.set(true, forKey: Keys.hasSeededIgnoredApps)
        } else {
            ignoredAppBundleIDs = Set(defaults.stringArray(forKey: Keys.ignoredAppBundleIDs) ?? [])
        }

        if let pausedUntil = capturePausedUntil, pausedUntil > Date() {
            scheduleAutoResume(at: pausedUntil)
        } else if capturePausedUntil != nil, !isCapturePausedIndefinitely {
            capturePausedUntil = nil
        }
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
    }

    func refreshPasteAutomationPermission() {
        hasPostEventAccess = PasteAutomationService.hasPostEventAccess
    }

    func tagColor(for tag: String) -> TagColor {
        guard let normalizedTag = TagRules.normalizeTag(tag) else { return .sky }
        if let rawColor = tagColorIDsByTag[normalizedTag], let color = TagColor(rawValue: rawColor) {
            return color
        }
        return TagColor.automatic(for: normalizedTag)
    }

    func setTagColor(_ color: TagColor, for tag: String) {
        guard let normalizedTag = TagRules.normalizeTag(tag) else { return }
        tagColorIDsByTag[normalizedTag] = color.rawValue
    }

    var isCapturePaused: Bool {
        if isCapturePausedIndefinitely { return true }
        guard let capturePausedUntil else { return false }
        return capturePausedUntil > Date()
    }

    var capturePauseStatusText: String? {
        guard isCapturePaused else { return nil }
        if isCapturePausedIndefinitely {
            return "Capture paused"
        }
        guard let capturePausedUntil else { return nil }
        let minutesLeft = max(1, Int(capturePausedUntil.timeIntervalSinceNow / 60) + 1)
        return "Capture paused · \(minutesLeft) min left"
    }

    func pauseCapture(for duration: CapturePauseDuration) {
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil

        guard let interval = duration.timeInterval else {
            isCapturePausedIndefinitely = true
            capturePausedUntil = nil
            return
        }

        isCapturePausedIndefinitely = false
        let until = Date().addingTimeInterval(interval)
        capturePausedUntil = until
        scheduleAutoResume(at: until)
    }

    func resumeCapture() {
        pauseResumeTimer?.invalidate()
        pauseResumeTimer = nil
        isCapturePausedIndefinitely = false
        capturePausedUntil = nil
    }

    func addIgnoredApp(bundleID: String) {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        ignoredAppBundleIDs.insert(trimmed)
    }

    func removeIgnoredApp(bundleID: String) {
        ignoredAppBundleIDs.remove(bundleID)
    }

    func isAppIgnored(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return ignoredAppBundleIDs.contains(bundleID)
    }

    private func scheduleAutoResume(at date: Date) {
        let interval = date.timeIntervalSinceNow
        guard interval > 0 else {
            resumeCapture()
            return
        }
        pauseResumeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            DispatchQueue.main.async {
                self?.resumeCapture()
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

    private static func tagColorIDs(for key: String, in defaults: UserDefaults) -> [String: String] {
        guard let rawColors = defaults.dictionary(forKey: key) as? [String: String] else { return [:] }
        return rawColors.reduce(into: [:]) { colors, pair in
            guard let tag = TagRules.normalizeTag(pair.key),
                  TagColor(rawValue: pair.value) != nil else {
                return
            }
            colors[tag] = pair.value
        }
    }
}

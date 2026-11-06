import AppKit

/// Tracks the most recently activated app that isn't Copypastik itself.
///
/// `NSWorkspace.shared.frontmostApplication` is unreliable at the moment a
/// clipboard poll fires because Copypastik's own picker/menu bar UI briefly
/// becomes frontmost. Watching activation notifications instead keeps a
/// running record of the last real foreground app so newly captured items
/// are attributed correctly and Copypastik never attributes itself.
final class SourceAppTracker {
    struct AppInfo: Equatable {
        let name: String
        let bundleID: String?
    }

    private(set) var lastKnownForegroundApp: AppInfo?
    private var observer: NSObjectProtocol?
    private let ownBundleID = Bundle.main.bundleIdentifier

    init() {
        if let frontmost = NSWorkspace.shared.frontmostApplication, frontmost.bundleIdentifier != ownBundleID {
            lastKnownForegroundApp = AppInfo(
                name: frontmost.localizedName ?? "Unknown",
                bundleID: frontmost.bundleIdentifier
            )
        }

        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.bundleIdentifier != self.ownBundleID else {
                return
            }
            self.lastKnownForegroundApp = AppInfo(name: app.localizedName ?? "Unknown", bundleID: app.bundleIdentifier)
        }
    }

    deinit {
        if let observer {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}

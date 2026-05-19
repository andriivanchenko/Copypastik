import AppKit
import ApplicationServices
import Carbon.HIToolbox

final class HotkeyService {
    var onTrigger: (() -> Void)?
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var shortcut: PickerShortcut = .controlOptionV

    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func start(shortcut: PickerShortcut = .controlOptionV) {
        guard eventHandlerRef == nil else {
            updateShortcut(shortcut)
            return
        }
        self.shortcut = shortcut

        let eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let result = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard result == noErr else { return result }
                let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                if hotKeyID.id == 1 {
                    print("[Copypastik] global shortcut pressed")
                    DispatchQueue.main.async {
                        service.onTrigger?()
                    }
                }
                return noErr
            },
            1,
            [eventSpec],
            userData,
            &eventHandlerRef
        )

        guard status == noErr else {
            print("[Copypastik] failed to install hotkey handler: \(status)")
            return
        }

        registerHotKey()
    }

    func updateShortcut(_ shortcut: PickerShortcut) {
        guard eventHandlerRef != nil else {
            start(shortcut: shortcut)
            return
        }
        guard self.shortcut != shortcut else { return }
        self.shortcut = shortcut
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        registerHotKey()
    }

    private func registerHotKey() {
        guard hotKeyRef == nil else { return }

        let hotKeyID = EventHotKeyID(signature: fourCharCode(from: "PstP"), id: 1)
        let registerStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus == noErr {
            print("[Copypastik] global shortcut registered: \(shortcut.displayName)")
        } else {
            print("[Copypastik] failed to register global shortcut: \(registerStatus)")
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        stop()
    }

    /// Prompts the user to grant Accessibility access if not already granted.
    static func requestAccessibilityIfNeeded() {
        let granted = isAccessibilityGranted
        print("[Copypastik] Accessibility permission status: \(granted ? "granted" : "not granted")")
        guard !granted else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trustedAfterPrompt = AXIsProcessTrustedWithOptions(options)
        print("[Copypastik] Accessibility permission after prompt: \(trustedAfterPrompt ? "granted" : "not granted")")
    }

    private func fourCharCode(from string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}

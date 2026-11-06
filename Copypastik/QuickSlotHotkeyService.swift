import AppKit
import Carbon.HIToolbox

/// Registers the nine global `Control + Option + 1...9` shortcuts used to
/// paste a pinned Quick Slot from anywhere. Mirrors `HotkeyService`'s Carbon
/// `RegisterEventHotKey` approach but for a fixed bank of shortcuts instead
/// of one configurable one.
final class QuickSlotHotkeyService {
    /// Hotkey ids are offset well past `HotkeyService`'s id (1) so a shared
    /// Carbon event handler dispatch never confuses the two services.
    private static let hotKeyIDOffset: UInt32 = 100

    private static let slotKeyCodes: [Int: UInt32] = [
        1: UInt32(kVK_ANSI_1),
        2: UInt32(kVK_ANSI_2),
        3: UInt32(kVK_ANSI_3),
        4: UInt32(kVK_ANSI_4),
        5: UInt32(kVK_ANSI_5),
        6: UInt32(kVK_ANSI_6),
        7: UInt32(kVK_ANSI_7),
        8: UInt32(kVK_ANSI_8),
        9: UInt32(kVK_ANSI_9)
    ]

    var onTrigger: ((Int) -> Void)?

    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?

    func start() {
        guard eventHandlerRef == nil else { return }

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
                // Not one of ours — let the event fall through to other
                // handlers on this target (e.g. HotkeyService's picker
                // shortcut). Returning noErr here would mark it "handled"
                // and stop propagation, silently swallowing other hotkeys.
                guard hotKeyID.id > 100, hotKeyID.id <= 109 else { return OSStatus(eventNotHandledErr) }

                let service = Unmanaged<QuickSlotHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                let slot = Int(hotKeyID.id - 100)
                print("[Copypastik] quick slot \(slot) shortcut pressed")
                DispatchQueue.main.async {
                    service.onTrigger?(slot)
                }
                return noErr
            },
            1,
            [eventSpec],
            userData,
            &eventHandlerRef
        )

        guard status == noErr else {
            print("[Copypastik] failed to install quick slot hotkey handler: \(status)")
            return
        }

        registerHotKeys()
    }

    func stop() {
        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        stop()
    }

    private func registerHotKeys() {
        for slot in 1...9 {
            guard let keyCode = Self.slotKeyCodes[slot] else { continue }
            var hotKeyRef: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: fourCharCode(from: "PstQ"), id: Self.hotKeyIDOffset + UInt32(slot))
            let status = RegisterEventHotKey(
                keyCode,
                UInt32(controlKey | optionKey),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &hotKeyRef
            )
            if status == noErr, let hotKeyRef {
                hotKeyRefs.append(hotKeyRef)
            } else {
                print("[Copypastik] failed to register quick slot \(slot) shortcut: \(status)")
            }
        }
    }

    private func fourCharCode(from string: String) -> OSType {
        string.utf8.reduce(0) { ($0 << 8) | OSType($1) }
    }
}

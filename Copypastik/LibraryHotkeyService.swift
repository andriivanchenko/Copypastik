import AppKit
import Carbon.HIToolbox

/// Registers the global `Control + Option + L` shortcut that opens the Library.
/// Uses the same Carbon `RegisterEventHotKey` approach as `HotkeyService` and
/// `QuickSlotHotkeyService`, with an id that cannot collide with theirs.
final class LibraryHotkeyService {
    private static let hotKeyID: UInt32 = 200

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
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
                // Not ours: let the picker and Quick Slot handlers see it.
                guard hotKeyID.id == 200 else { return OSStatus(eventNotHandledErr) }

                let service = Unmanaged<LibraryHotkeyService>.fromOpaque(userData).takeUnretainedValue()
                print("[Copypastik] library shortcut pressed")
                DispatchQueue.main.async {
                    service.onTrigger?()
                }
                return noErr
            },
            1,
            [eventSpec],
            userData,
            &eventHandlerRef
        )

        guard status == noErr else {
            print("[Copypastik] failed to install library hotkey handler: \(status)")
            return
        }

        let signature = "PstL".utf8.reduce(OSType(0)) { ($0 << 8) | OSType($1) }
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_L),
            UInt32(controlKey | optionKey),
            EventHotKeyID(signature: signature, id: Self.hotKeyID),
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if registerStatus != noErr {
            print("[Copypastik] failed to register library shortcut: \(registerStatus)")
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
}

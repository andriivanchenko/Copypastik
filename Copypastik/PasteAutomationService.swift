import CoreGraphics

enum PasteAutomationService {
    static var hasPostEventAccess: Bool {
        CGPreflightPostEventAccess()
    }

    static func postPasteCommand() {
        let src = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
        print("[Copypastik] Cmd+V simulated")
    }
}

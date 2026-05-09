import AppKit

/// Polls NSPasteboard every 0.5s using changeCount to detect new clipboard items.
final class PasteboardService {
    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var timer: Timer?
    private var skipCount: Int?

    var onNewItem: ((ClipboardHistoryItem) -> Void)?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    deinit {
        stop()
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Suppress the next clipboard change notification for a specific changeCount.
    /// Call immediately after writing to NSPasteboard to avoid re-adding the item we just pasted.
    func suppressChange(atCount count: Int) {
        skipCount = count
    }

    private func poll() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // Skip changes that we ourselves initiated
        if skipCount == currentCount {
            skipCount = nil
            print("[Copypastik] self-write suppressed")
            return
        }
        skipCount = nil

        if isFileURLCopy {
            print("[Copypastik] file clipboard item ignored")
            return
        }

        if let text = pasteboard.string(forType: .string) {
            print("[Copypastik] clipboard item detected")
            onNewItem?(.text(text))
            return
        }

        if let image = imageItemFromPasteboard() {
            print("[Copypastik] clipboard image detected")
            onNewItem?(.image(image))
        }
    }

    private var isFileURLCopy: Bool {
        pasteboard.types?.contains(.fileURL) == true
    }

    private func imageItemFromPasteboard() -> ClipboardImage? {
        if let pngData = pasteboard.data(forType: .png),
           let image = ClipboardImage.make(from: pngData, pasteboardType: .png) {
            return image
        }

        if let tiffData = pasteboard.data(forType: .tiff),
           let image = ClipboardImage.make(from: tiffData, pasteboardType: .tiff) {
            return image
        }

        if let nsImage = NSImage(pasteboard: pasteboard) {
            return ClipboardImage.make(from: nsImage)
        }

        return nil
    }
}

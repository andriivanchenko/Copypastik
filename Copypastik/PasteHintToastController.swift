import AppKit
import CoreGraphics

@MainActor
final class PasteHintToastController {
    private enum Metrics {
        static let size = NSSize(width: 214, height: 42)
        static let horizontalPadding: CGFloat = 14
        static let bottomOffset: CGFloat = 72
        static let fadeInDuration: TimeInterval = 0.15
        static let visibleDuration: TimeInterval = 1.5
        static let fadeOutDuration: TimeInterval = 0.3
    }

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?
    private var presentationID = 0

    func show(relativeTo application: NSRunningApplication?) {
        guard let screen = screen(for: application) else { return }

        presentationID += 1
        let currentPresentationID = presentationID
        hideWorkItem?.cancel()

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel, on: screen)

        if panel.isVisible {
            panel.alphaValue = 1
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Metrics.fadeInDuration
                panel.animator().alphaValue = 1
            }
        }

        scheduleHide(for: currentPresentationID)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Metrics.size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.contentView = makeContentView()
        return panel
    }

    private func makeContentView() -> NSView {
        let backdrop = NSVisualEffectView(frame: NSRect(origin: .zero, size: Metrics.size))
        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .vibrantDark)
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.32).cgColor
        backdrop.layer?.cornerRadius = Metrics.size.height / 2
        backdrop.layer?.masksToBounds = true
        if #available(macOS 10.15, *) {
            backdrop.layer?.cornerCurve = .continuous
        }

        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(
            systemSymbolName: "checkmark.circle.fill",
            accessibilityDescription: "Copied"
        )?.withSymbolConfiguration(symbolConfiguration)

        let imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = .systemGreen
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.setContentHuggingPriority(.required, for: .horizontal)

        let label = NSTextField(labelWithString: "Copied! ⌘V to paste")
        label.font = .systemFont(ofSize: 13.5, weight: .semibold)
        label.textColor = .white
        label.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
            shadow.shadowOffset = NSSize(width: 0, height: -1)
            shadow.shadowBlurRadius = 2
            return shadow
        }()
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [imageView, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        backdrop.addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 17),
            imageView.heightAnchor.constraint(equalToConstant: 17),
            stack.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: backdrop.leadingAnchor, constant: Metrics.horizontalPadding),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: backdrop.trailingAnchor, constant: -Metrics.horizontalPadding)
        ])

        return backdrop
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {
        let frame = screen.visibleFrame
        let origin = NSPoint(
            x: frame.midX - Metrics.size.width / 2,
            y: frame.minY + Metrics.bottomOffset
        )
        panel.setFrame(NSRect(origin: origin, size: Metrics.size), display: true)
    }

    private func scheduleHide(for presentationID: Int) {
        let workItem = DispatchWorkItem { [weak self] in
            self?.hide(presentationID: presentationID)
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.visibleDuration, execute: workItem)
    }

    private func hide(presentationID: Int) {
        guard presentationID == self.presentationID, let panel else { return }
        hideWorkItem = nil

        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            Task { @MainActor [weak self, weak panel] in
                guard let self, presentationID == self.presentationID else { return }
                panel?.close()
                self.panel = nil
            }
        }
    }

    private func screen(for application: NSRunningApplication?) -> NSScreen? {
        guard let application else { return NSScreen.main ?? NSScreen.screens.first }

        if let windowBounds = keyWindowBounds(for: application),
           let windowScreen = screen(containing: windowBounds) {
            return windowScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
    }

    private func keyWindowBounds(for application: NSRunningApplication) -> CGRect? {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return windows.first { windowInfo in
            guard let ownerPID = intValue(windowInfo[kCGWindowOwnerPID as String]),
                  ownerPID == Int(application.processIdentifier),
                  let layer = intValue(windowInfo[kCGWindowLayer as String]),
                  layer == 0,
                  let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                  bounds.width > 0,
                  bounds.height > 0 else {
                return false
            }

            return true
        }
        .flatMap { windowInfo in
            guard let boundsDictionary = windowInfo[kCGWindowBounds as String] as? [String: Any] else {
                return nil
            }
            return CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
        }
    }

    private func screen(containing rect: CGRect) -> NSScreen? {
        let center = NSPoint(x: rect.midX, y: rect.midY)
        if let containingScreen = NSScreen.screens.first(where: { $0.frame.contains(center) }) {
            return containingScreen
        }

        return NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
    }

    private func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int {
            return value
        }

        if let value = value as? NSNumber {
            return value.intValue
        }

        return nil
    }
}

private extension CGRect {
    var area: CGFloat {
        guard !isNull, !isEmpty else { return 0 }
        return width * height
    }
}

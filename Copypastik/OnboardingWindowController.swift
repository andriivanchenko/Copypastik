import AppKit
import SwiftUI

final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let settings: AppSettings
    private var window: NSWindow?

    init(settings: AppSettings) {
        self.settings = settings
    }

    func show() {
        if window == nil {
            buildWindow()
        }

        window?.center()
        window?.makeKeyAndOrderFront(nil)
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func buildWindow() {
        let rootView = OnboardingView(
            settings: settings,
            onClose: { [weak self] in
                self?.window?.close()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Copypastik"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: rootView)
        self.window = window
    }

    func windowDidBecomeKey(_ notification: Notification) {
    }

    func windowDidClose(_ notification: Notification) {
        window = nil
    }
}

private struct OnboardingStep: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let symbolName: String
}

struct OnboardingView: View {
    @ObservedObject var settings: AppSettings
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            hero

            VStack(spacing: 14) {
                VStack(spacing: 9) {
                    Text(currentStep.title)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)

                    Text(currentStep.body)
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .frame(maxWidth: 620)
                }

                if selectedIndex == 1 {
                    ShortcutKeycapsView(shortcut: settings.pickerShortcut)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if selectedIndex == 3 || selectedIndex == 4 {
                    TagKeycapsView(selectedIndex: selectedIndex)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }

                if isLastStep {
                    LaunchAtLoginToggleRow(isOn: $settings.isLaunchAtLoginEnabled)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .frame(maxWidth: 480)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 56)

            footer
        }
        .frame(width: 860, height: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
        )
        .animation(pageAnimation, value: selectedIndex)
    }

    private var hero: some View {
        ZStack {
            OnboardingHeroSurface()

            Group {
                if isLastStep {
                    OnboardingLaunchHeroPreview(
                        isEnabled: settings.isLaunchAtLoginEnabled,
                        reduceMotion: reduceMotion
                    )
                } else {
                    OnboardingPickerPreview(
                        selectedIndex: selectedIndex,
                        shortcutDisplayName: settings.pickerShortcut.displayName,
                        reduceMotion: reduceMotion
                    )
                }
            }
            .id(currentStep.title)
            .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.985)))
        }
        .frame(height: 310)
        .clipped()
    }

    private var footer: some View {
        HStack {
            HStack(spacing: 11) {
                ForEach(steps.indices, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? Color.accentColor : Color.secondary.opacity(0.30))
                        .frame(width: 10, height: 10)
                        .scaleEffect(index == selectedIndex && !reduceMotion ? 1.12 : 1)
                        .animation(pageAnimation, value: selectedIndex)
                }
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Back") {
                    selectedIndex = max(selectedIndex - 1, 0)
                }
                .disabled(selectedIndex == 0)
                .buttonStyle(.bordered)
                .controlSize(.large)

                Button(isLastStep ? "Done" : "Next") {
                    if isLastStep {
                        settings.markOnboardingCompleted()
                        DispatchQueue.main.async {
                            onClose()
                        }
                    } else {
                        selectedIndex += 1
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 28)
        .frame(height: 76)
    }

    private var currentStep: OnboardingStep {
        steps[selectedIndex]
    }

    private var steps: [OnboardingStep] {
        [
            OnboardingStep(
                title: "Welcome to Copypastik",
                body: "Keep a small, searchable clipboard history for text and images right in your menu bar.",
                symbolName: "menubar.rectangle"
            ),
            OnboardingStep(
                title: "Open the Picker",
                body: "Press \(settings.pickerShortcut.displayName) anywhere to bring up your latest clipboard items.",
                symbolName: "keyboard"
            ),
            OnboardingStep(
                title: "Paste the Latest",
                body: "The newest history item is selected first. Press Enter to copy it back, then paste with Command-V.",
                symbolName: "photo.on.rectangle"
            ),
            OnboardingStep(
                title: "Keep Tagged Snippets",
                body: "Press Command-T on an item to add tags. Tagged snippets are kept locally on this Mac and survive restarts.",
                symbolName: "tag"
            ),
            OnboardingStep(
                title: "Browse Tags Fast",
                body: "From the first history row, press Up to reach All and your tags, then use Left and Right to switch the list.",
                symbolName: "number"
            ),
            OnboardingStep(
                title: "Search and Manage",
                body: "Search content, type #tag filters, delete rows, or clear regular history without touching tagged snippets.",
                symbolName: "magnifyingglass"
            ),
            OnboardingStep(
                title: "Always Ready",
                body: "Enable launch at login so Copypastik starts with your Mac — always there when you need it.",
                symbolName: "power"
            )
        ]
    }

    private var isLastStep: Bool {
        selectedIndex == steps.count - 1
    }

    private var pageAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.25, dampingFraction: 0.84)
    }
}

private struct OnboardingHeroSurface: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(nsColor: .windowBackgroundColor),
                    CopypastikTheme.accentGlow.opacity(0.20),
                    CopypastikTheme.accentDeep.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(0.18),
                    Color.clear
                ],
                center: .topTrailing,
                startRadius: 30,
                endRadius: 420
            )

            VStack(spacing: 0) {
                Color.white.opacity(0.16)
                    .frame(height: 1)
                Spacer()
            }
        }
    }
}

private struct OnboardingPickerPreview: View {
    let selectedIndex: Int
    let shortcutDisplayName: String
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text(previewQuery)
                    .font(.system(size: 12.5))
                    .foregroundStyle(previewQuery == "Search history..." ? .secondary : .primary)

                Spacer()

                Text("3 items")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            VStack(spacing: 5) {
                if showsTagBrowser {
                    PreviewTagBar(activeChip: activeTagChip)
                        .padding(.bottom, 1)
                }

                if showsTaggedPreview {
                    PreviewSectionLabel(title: "Tagged", count: selectedIndex == 4 ? 1 : 3)

                    PreviewRow(
                        symbolName: "terminal",
                        title: "select * from snippets",
                        isSelected: selectedPreviewRow == 0,
                        tags: ["sql"]
                    )
                }

                PreviewRow(
                    symbolName: historyFirstSymbol,
                    title: historyFirstTitle,
                    isSelected: selectedPreviewRow == 2,
                    showsThumbnail: selectedIndex == 2
                )

                if !showsTaggedPreview {
                    PreviewRow(
                        symbolName: "link",
                        title: "https://developer.apple.com/design",
                        isSelected: selectedPreviewRow == 1
                    )
                    PreviewRow(
                        symbolName: trailingHistorySymbol,
                        title: trailingHistoryTitle,
                        isSelected: selectedPreviewRow == 3,
                        showsThumbnail: trailingHistorySymbol == "photo"
                    )
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                KeycapToken(text: "↑↓", minWidth: 33)
                KeycapToken(text: "↵")
                if selectedIndex == 3 || selectedIndex == 4 {
                    KeycapToken(text: "⌘T", minWidth: 35)
                }
                KeycapToken(text: "esc", minWidth: 34)
            }
            .padding(.bottom, 9)
        }
        .frame(width: 382, height: 242)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 16)
        .scaleEffect(reduceMotion ? 1 : 1.0)
    }

    private var previewQuery: String {
        switch selectedIndex {
        case 1:
            return shortcutDisplayName
        case 4:
            return "#sql"
        case 3:
            return "Search history or #tag..."
        case 5:
            return "design"
        default:
            return "Search history..."
        }
    }

    private var selectedPreviewRow: Int {
        switch selectedIndex {
        case 2:
            return 2
        case 3:
            return 0
        case 4:
            return 0
        case 5:
            return 1
        default:
            return 2
        }
    }

    private var showsTaggedPreview: Bool {
        selectedIndex == 3 || selectedIndex == 4
    }

    private var showsTagBrowser: Bool {
        selectedIndex == 4
    }

    private var activeTagChip: String {
        selectedIndex == 4 ? "#sql" : "All"
    }

    private var historyFirstTitle: String {
        selectedIndex == 2 ? "Screenshot" : "xcodebuild build -scheme Copypastik"
    }

    private var historyFirstSymbol: String {
        selectedIndex == 2 ? "photo" : "terminal"
    }

    private var trailingHistoryTitle: String {
        selectedIndex == 2 ? "xcodebuild build -scheme Copypastik" : "Screenshot"
    }

    private var trailingHistorySymbol: String {
        selectedIndex == 2 ? "terminal" : "photo"
    }
}

private struct OnboardingLaunchHeroPreview: View {
    let isEnabled: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "wifi")
                    Image(systemName: "battery.100")
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.accentColor.opacity(isEnabled ? 0.18 : 0.08))
                        Image(systemName: "doc.on.clipboard")
                            .foregroundStyle(Color.accentColor)
                    }
                    .frame(width: 28, height: 20)
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
                .padding(.trailing, 18)
            }

            Spacer()

            ZStack {
                Circle()
                    .fill(isEnabled ? Color.accentColor.opacity(0.14) : Color.primary.opacity(0.055))
                    .frame(width: 72, height: 72)
                    .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.72), value: isEnabled)

                Image(systemName: isEnabled ? "checkmark.circle.fill" : "power")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                    .symbolRenderingMode(.hierarchical)
                    .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.7), value: isEnabled)
            }

            Text(isEnabled ? "Launch at login enabled" : "Not set to launch at login")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary.opacity(0.72))
                .padding(.top, 12)
                .animation(.easeOut(duration: 0.18), value: isEnabled)

            Spacer()
        }
        .frame(width: 382, height: 242)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 0.75)
        )
        .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 16)
    }
}

private struct ShortcutKeycapsView: View {
    let shortcut: PickerShortcut

    var body: some View {
        HStack(spacing: 10) {
            ForEach(shortcut.keycapTokens, id: \.self) { token in
                Text(token)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .frame(minWidth: 52, minHeight: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.primary.opacity(0.055))
                            .overlay(
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.75)
                            )
                    )
                    .shadow(color: .black.opacity(0.07), radius: 3, x: 0, y: 2)
            }
        }
        .padding(.top, 4)
    }
}

private struct TagKeycapsView: View {
    let selectedIndex: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(tokens, id: \.self) { token in
                KeycapToken(text: token, minWidth: token.count > 1 ? 42 : 32)
            }
        }
        .padding(.top, 4)
    }

    private var tokens: [String] {
        selectedIndex == 3 ? ["⌘T", "↵", "esc"] : ["↑", "←→", "↵"]
    }
}

private struct LaunchAtLoginToggleRow: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(isOn ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.055))
                    .frame(width: 36, height: 36)
                Image(systemName: isOn ? "checkmark.circle.fill" : "power")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isOn)

            VStack(alignment: .leading, spacing: 2) {
                Text("Launch at Login")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Copypastik starts automatically with macOS.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(isOn ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(
                    isOn ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.08),
                    lineWidth: 0.75
                )
        )
        .animation(.easeOut(duration: 0.18), value: isOn)
    }
}

private struct PreviewTagBar: View {
    let activeChip: String

    private let chips = ["All", "#sql", "#hello"]

    var body: some View {
        HStack(spacing: 5) {
            ForEach(chips, id: \.self) { chip in
                let isActive = chip == activeChip
                Text(chip)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(
                        Capsule()
                            .fill(isActive ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.045))
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(isActive ? Color.accentColor.opacity(0.36) : Color.primary.opacity(0.08), lineWidth: 0.65)
                    )
            }
            Spacer(minLength: 0)
        }
        .frame(height: 20)
    }
}

private struct PreviewSectionLabel: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.down")
                .font(.system(size: 7.5, weight: .bold))
            Text(title)
                .textCase(.uppercase)
            Text("\(count)")
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .frame(height: 15)
    }
}

private extension PickerShortcut {
    var keycapTokens: [String] {
        switch self {
        case .controlOptionV: return ["⌃", "⌥", "V"]
        case .commandShiftV: return ["⌘", "⇧", "V"]
        }
    }
}

private struct PreviewRow: View {
    let symbolName: String
    let title: String
    let isSelected: Bool
    var showsThumbnail = false
    var tags: [String] = []

    var body: some View {
        HStack(spacing: 9) {
            if showsThumbnail {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                CopypastikTheme.accentGlow.opacity(0.34),
                                Color.primary.opacity(0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 34)
                    .overlay(
                        Image(systemName: symbolName)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color.accentColor.opacity(0.82))
                    )
            } else {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.055))
                    Image(systemName: symbolName)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                .frame(width: 26, height: 26)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium, design: symbolName == "terminal" ? .monospaced : .default))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if !tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            Text("#\(tag)")
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(Color.accentColor.opacity(0.86))
                                .padding(.horizontal, 5)
                                .frame(height: 14)
                                .background(
                                    Capsule()
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        }
                    }
                }
            }

            Spacer()

            if isSelected {
                Text("↵")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.84))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.13))
                    )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: rowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.06), lineWidth: 0.75)
        )
    }

    private var rowHeight: CGFloat {
        if showsThumbnail {
            return 56
        }
        return tags.isEmpty ? 46 : 50
    }
}

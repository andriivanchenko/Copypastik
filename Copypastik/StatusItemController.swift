import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let historyPopover = NSPopover()
    private let settingsPopover = NSPopover()
    private let settings: AppSettings
    private let store: ClipboardStore
    private let onShowOnboarding: () -> Void
    private let onQuit: () -> Void

    init(
        store: ClipboardStore,
        settings: AppSettings,
        onShowOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onShowOnboarding = onShowOnboarding
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopovers()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        guard let image = NSImage(named: "menubar-copy-tight") else {
            print("Missing menubar-copy-tight image")
            return
        }
        image.isTemplate = true
        image.size = NSSize(width: 44, height: 18)
        button.image = image
        button.imagePosition = .imageOnly
        button.title = ""
        button.alignment = .center
        button.toolTip = "Copypastik"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configurePopovers() {
        historyPopover.behavior = .transient
        historyPopover.animates = true
        historyPopover.contentSize = NSSize(width: 320, height: 420)
        historyPopover.contentViewController = NSHostingController(
            rootView: ContentView()
                .environmentObject(store)
        )

        settingsPopover.behavior = .transient
        settingsPopover.animates = true
        settingsPopover.contentSize = NSSize(width: 320, height: 420)
        refreshSettingsPopoverContent()
    }

    private func refreshSettingsPopoverContent() {
        settingsPopover.contentViewController = NSHostingController(
            rootView: SettingsPopoverView(
                settings: settings,
                store: store,
                onShowOnboarding: { [weak self] in
                    self?.settingsPopover.performClose(nil)
                    self?.onShowOnboarding()
                },
                onQuit: onQuit
            )
        )
    }

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            toggleHistoryPopover(from: sender)
            return
        }

        switch event.type {
        case .rightMouseUp:
            toggleSettingsPopover(from: sender)
        default:
            toggleHistoryPopover(from: sender)
        }
    }

    private func toggleHistoryPopover(from button: NSStatusBarButton) {
        if historyPopover.isShown {
            historyPopover.performClose(nil)
        } else {
            settingsPopover.performClose(nil)
            historyPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func toggleSettingsPopover(from button: NSStatusBarButton) {
        if settingsPopover.isShown {
            settingsPopover.performClose(nil)
        } else {
            historyPopover.performClose(nil)
            refreshSettingsPopoverContent()
            settingsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

struct SettingsPopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore

    let onShowOnboarding: () -> Void
    let onQuit: () -> Void

    @State private var accessibilityGranted = HotkeyService.isAccessibilityGranted
    @State private var isPopoverVisible = false
    @State private var showsLaunchAtLoginConfirmation = false
    private let accessibilityRefreshTimer = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()
                .opacity(0.55)

            ScrollView {
                VStack(spacing: 12) {
                    onboardingBanner
                    statusSection
                    behaviorSection
                    actionsSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 320, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            isPopoverVisible = true
            refreshAccessibilityStatus()
        }
        .onDisappear {
            isPopoverVisible = false
        }
        .onReceive(accessibilityRefreshTimer) { _ in
            guard isPopoverVisible else { return }
            refreshAccessibilityStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityStatus()
        }
        .alert("Launch at Login?", isPresented: $showsLaunchAtLoginConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Enable") {
                settings.isLaunchAtLoginEnabled = true
            }
        } message: {
            Text("Open Copypastik automatically when you log in to your Mac?")
        }
    }

    private var header: some View {
        HStack(spacing: 9) {
            Image(systemName: "gearshape")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 1) {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Text("Copypastik")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
    }

    private var statusSection: some View {
        SettingsSection(title: "Status") {
            SettingsShortcutRow(shortcut: $settings.pickerShortcut)

            SettingsRowDivider()

            SettingsInfoRow(
                symbolName: accessibilityGranted ? "checkmark.shield" : "exclamationmark.shield",
                title: "Accessibility",
                subtitle: accessibilityGranted ? "Granted" : "Needed for instant paste",
                tint: accessibilityGranted ? CopypastikTheme.success : CopypastikTheme.warning,
                trailing: {
                    if !accessibilityGranted {
                        Button("Open") {
                            settings.openAccessibilitySettings()
                            refreshAccessibilityStatus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            )

            SettingsRowDivider()

            SettingsInfoRow(
                symbolName: "lock",
                title: "Privacy",
                subtitle: "Clipboard history stays on this Mac.",
                tint: Color.accentColor
            )
        }
    }

    private func refreshAccessibilityStatus() {
        let granted = HotkeyService.isAccessibilityGranted
        guard accessibilityGranted != granted else { return }
        accessibilityGranted = granted
    }

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
            SettingsToggleRow(
                symbolName: "power",
                title: "Launch at Login",
                subtitle: "Open Copypastik when you log in to your Mac.",
                tint: Color.accentColor,
                isOn: launchAtLoginBinding
            )

            SettingsRowDivider()

            SettingsToggleRow(
                symbolName: "doc.on.clipboard",
                title: "Clipboard History",
                subtitle: "Save newly copied text and images.",
                tint: Color.accentColor,
                isOn: $settings.isClipboardHistoryEnabled
            )

            SettingsRowDivider()

            SettingsHistoryLimitRow(historyLimit: $settings.historyLimit)
        }
    }

    private var onboardingBanner: some View {
        Button(action: onShowOnboarding) {
            HStack(spacing: 13) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 38, height: 38)
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .symbolRenderingMode(.hierarchical)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Quick Setup Guide")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Replay the onboarding walkthrough")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.76))
                }

                Spacer()

                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.white.opacity(0.52))
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(
                LinearGradient(
                    colors: [CopypastikTheme.accentDeep, CopypastikTheme.accent.opacity(0.90)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.14), lineWidth: 0.75)
            )
            .shadow(color: CopypastikTheme.accentDeep.opacity(0.28), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var actionsSection: some View {
        SettingsSection(title: "Actions") {
            Button {
                store.clearHistory()
            } label: {
                SettingsActionContent(
                    symbolName: "trash",
                    title: "Clear History",
                    subtitle: store.items.isEmpty ? "History is already empty." : "Remove \(store.items.count) saved items.",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
            .disabled(store.items.isEmpty)
            .opacity(store.items.isEmpty ? 0.55 : 1)

            SettingsRowDivider()

            Button(action: onQuit) {
                SettingsActionContent(
                    symbolName: "xmark.circle",
                    title: "Quit Copypastik",
                    subtitle: "Stop the menu bar app.",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                settings.isLaunchAtLoginEnabled
            },
            set: { newValue in
                if newValue, !settings.isLaunchAtLoginEnabled {
                    showsLaunchAtLoginConfirmation = true
                } else {
                    settings.isLaunchAtLoginEnabled = newValue
                }
            }
        )
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.92))
                .textCase(.uppercase)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.75)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }
}

private struct SettingsRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.07))
            .frame(height: 0.75)
            .padding(.leading, 42)
    }
}

private struct SettingsInfoRow<Trailing: View>: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let tint: Color
    @ViewBuilder let trailing: Trailing

    init(
        symbolName: String,
        title: String,
        subtitle: String,
        tint: Color,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.symbolName = symbolName
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 10) {
            SettingsIcon(symbolName: symbolName, tint: tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

private struct SettingsToggleRow: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let tint: Color
    @Binding var isOn: Bool

    var body: some View {
        SettingsInfoRow(
            symbolName: symbolName,
            title: title,
            subtitle: subtitle,
            tint: tint,
            trailing: {
                Toggle(title, isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
        )
    }
}

private struct SettingsShortcutRow: View {
    @Binding var shortcut: PickerShortcut

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsIcon(symbolName: "keyboard", tint: Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Shortcut")
                        .font(.system(size: 12.5, weight: .medium))
                    Text(shortcut.displayName)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            SettingsOptionRail(selection: $shortcut, options: PickerShortcut.allCases) { shortcut, isSelected in
                HStack(spacing: 7) {
                    Text(shortcut.keycapDisplayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospaced()

                    Text(shortcut.modifierDisplayName)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.78) : Color.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("Shortcut")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct SettingsHistoryLimitRow: View {
    @Binding var historyLimit: ClipboardHistoryLimit

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsIcon(symbolName: "list.number", tint: Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("History Limit")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Keep up to \(historyLimit.rawValue) items.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)
            }

            SettingsOptionRail(selection: $historyLimit, options: ClipboardHistoryLimit.allCases) { limit, isSelected in
                VStack(spacing: 1) {
                    Text(limit.displayName)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()

                    Text("items")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.72) : Color.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .accessibilityLabel("History Limit")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct SettingsOptionRail<Option: Hashable, Label: View>: View {
    @Binding var selection: Option
    let options: [Option]
    @ViewBuilder let label: (Option, Bool) -> Label

    var body: some View {
        HStack(spacing: 5) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection

                Button {
                    withAnimation(.easeOut(duration: 0.14)) {
                        selection = option
                    }
                } label: {
                    label(option, isSelected)
                        .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.86))
                        .padding(.horizontal, 9)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.055))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    isSelected ? Color.white.opacity(0.22) : Color.primary.opacity(0.06),
                                    lineWidth: 0.75
                                )
                        )
                        .shadow(color: isSelected ? Color.accentColor.opacity(0.18) : .clear, radius: 4, y: 1)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.055), lineWidth: 0.75)
        )
    }
}

private extension PickerShortcut {
    var keycapDisplayName: String {
        switch self {
        case .controlOptionV:
            return "⌃⌥V"
        case .commandShiftV:
            return "⌘⇧V"
        }
    }

    var modifierDisplayName: String {
        switch self {
        case .controlOptionV:
            return "Control Option"
        case .commandShiftV:
            return "Command Shift"
        }
    }
}

private struct SettingsActionContent: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let tint: Color

    var body: some View {
        SettingsInfoRow(
            symbolName: symbolName,
            title: title,
            subtitle: subtitle,
            tint: tint,
            trailing: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        )
    }
}

private struct SettingsIcon: View {
    let symbolName: String
    let tint: Color

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint)
            .symbolRenderingMode(.hierarchical)
            .frame(width: 24, height: 24)
            .background(
                Circle()
                    .fill(tint.opacity(0.11))
            )
    }
}

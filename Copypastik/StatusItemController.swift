import AppKit
import Combine
import SwiftUI

final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let historyPopover = NSPopover()
    private let settingsPopover = NSPopover()
    private let pasteHintToast = PasteHintToastController()
    private let settings: AppSettings
    private let store: ClipboardStore
    private let onOpenPicker: () -> Void
    private let onOpenLibrary: () -> Void
    private let onEditSnippetTags: (ClipboardHistoryItem) -> Void
    private let onShowOnboarding: () -> Void
    private let onQuit: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        store: ClipboardStore,
        settings: AppSettings,
        onOpenPicker: @escaping () -> Void,
        onOpenLibrary: @escaping () -> Void,
        onEditSnippetTags: @escaping (ClipboardHistoryItem) -> Void,
        onShowOnboarding: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.store = store
        self.settings = settings
        self.onOpenPicker = onOpenPicker
        self.onOpenLibrary = onOpenLibrary
        self.onEditSnippetTags = onEditSnippetTags
        self.onShowOnboarding = onShowOnboarding
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configureStatusItem()
        configurePopovers()
        observeCaptureState()
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

    private func observeCaptureState() {
        settings.$capturePausedUntil
            .combineLatest(settings.$isCapturePausedIndefinitely)
            .sink { [weak self] _, _ in
                self?.refreshPausedIndicator()
            }
            .store(in: &cancellables)
        refreshPausedIndicator()
    }

    private func refreshPausedIndicator() {
        guard let button = statusItem.button else { return }
        if settings.isCapturePaused {
            button.imagePosition = .imageLeading
            button.title = " ⏸"
            button.toolTip = settings.capturePauseStatusText ?? "Capture paused"
        } else {
            button.imagePosition = .imageOnly
            button.title = ""
            button.toolTip = "Copypastik"
        }
    }

    private func configurePopovers() {
        historyPopover.behavior = .transient
        historyPopover.animates = true
        historyPopover.contentSize = NSSize(width: 320, height: 420)
        historyPopover.contentViewController = NSHostingController(
            rootView: ContentView(onOpenLibrary: { [weak self] in
                self?.historyPopover.performClose(nil)
                self?.onOpenLibrary()
            })
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
            showCommandMenu(from: sender, event: event)
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

    private func showCommandMenu(from button: NSStatusBarButton, event: NSEvent) {
        historyPopover.performClose(nil)
        settingsPopover.performClose(nil)
        NSMenu.popUpContextMenu(makeCommandMenu(), with: event, for: button)
    }

    private func makeCommandMenu() -> NSMenu {
        let menu = NSMenu()

        let openPickerItem = NSMenuItem(title: "Open Picker", action: #selector(openPickerFromMenu), keyEquivalent: "")
        openPickerItem.target = self
        menu.addItem(openPickerItem)

        let openLibraryItem = NSMenuItem(title: "Open Library", action: #selector(openLibraryFromMenu), keyEquivalent: "")
        openLibraryItem.target = self
        menu.addItem(openLibraryItem)

        let snippetsItem = NSMenuItem(title: "Snippets", action: nil, keyEquivalent: "")
        snippetsItem.submenu = makeSnippetsMenu()
        menu.addItem(snippetsItem)

        menu.addItem(.separator())

        if settings.isCapturePaused {
            let statusItem = NSMenuItem(title: settings.capturePauseStatusText ?? "Capture paused", action: nil, keyEquivalent: "")
            statusItem.isEnabled = false
            menu.addItem(statusItem)

            let resumeItem = NSMenuItem(title: "Resume Capture", action: #selector(resumeCaptureFromMenu), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
        } else {
            let pauseItem = NSMenuItem(title: "Pause Capture", action: nil, keyEquivalent: "")
            pauseItem.submenu = makePauseCaptureMenu()
            menu.addItem(pauseItem)
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings", action: #selector(openSettingsFromMenu), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit Copypastik", action: #selector(quitFromMenu), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func makePauseCaptureMenu() -> NSMenu {
        let menu = NSMenu()
        for duration in CapturePauseDuration.allCases {
            let item = NSMenuItem(title: duration.displayName, action: #selector(pauseCaptureFromMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = duration
            menu.addItem(item)
        }
        return menu
    }

    @objc private func pauseCaptureFromMenu(_ sender: NSMenuItem) {
        guard let duration = sender.representedObject as? CapturePauseDuration else { return }
        settings.pauseCapture(for: duration)
    }

    @objc private func resumeCaptureFromMenu() {
        settings.resumeCapture()
    }

    private func makeSnippetsMenu() -> NSMenu {
        let menu = NSMenu()
        let tags = store.allTags

        guard !tags.isEmpty else {
            let hint = NSMenuItem(title: "Tag items in the picker with Cmd+T", action: nil, keyEquivalent: "")
            hint.isEnabled = false
            menu.addItem(hint)
            return menu
        }

        for tag in tags {
            let tagItem = NSMenuItem(title: "#\(tag)", action: nil, keyEquivalent: "")
            let tagMenu = NSMenu()

            for item in store.taggedItems(for: tag) {
                let snippetItem = NSMenuItem(title: menuPreview(for: item), action: #selector(handleSnippetMenuItem(_:)), keyEquivalent: "")
                snippetItem.target = self
                snippetItem.representedObject = item
                snippetItem.image = menuImage(for: item)
                tagMenu.addItem(snippetItem)
            }

            tagItem.submenu = tagMenu
            menu.addItem(tagItem)
        }

        return menu
    }

    private func menuPreview(for item: ClipboardHistoryItem) -> String {
        if let text = item.textValue {
            let singleLine = text
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\t", with: " ")
            guard singleLine.count > 40 else { return singleLine }
            return "\(singleLine.prefix(39))…"
        }

        return "[Image]"
    }

    private func menuImage(for item: ClipboardHistoryItem) -> NSImage? {
        guard let image = item.imageValue?.nsImage else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }

    @objc private func openPickerFromMenu() {
        onOpenPicker()
    }

    @objc private func openLibraryFromMenu() {
        onOpenLibrary()
    }

    @objc private func openSettingsFromMenu() {
        guard let button = statusItem.button else { return }
        toggleSettingsPopover(from: button)
    }

    @objc private func quitFromMenu() {
        onQuit()
    }

    @objc private func handleSnippetMenuItem(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardHistoryItem else { return }

        if NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            showSnippetContextMenu(for: item)
            return
        }

        copySnippet(item)
    }

    private func showSnippetContextMenu(for item: ClipboardHistoryItem) {
        guard let button = statusItem.button, let event = NSApp.currentEvent else { return }
        let menu = NSMenu()

        let editItem = NSMenuItem(title: "Edit Tags...", action: #selector(editSnippetTags(_:)), keyEquivalent: "")
        editItem.target = self
        editItem.representedObject = item
        menu.addItem(editItem)

        let removeTagsItem = NSMenuItem(title: "Remove All Tags", action: #selector(removeSnippetTags(_:)), keyEquivalent: "")
        removeTagsItem.target = self
        removeTagsItem.representedObject = item
        menu.addItem(removeTagsItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteSnippet(_:)), keyEquivalent: "")
        deleteItem.target = self
        deleteItem.representedObject = item
        menu.addItem(deleteItem)

        NSMenu.popUpContextMenu(menu, with: event, for: button)
    }

    private func copySnippet(_ item: ClipboardHistoryItem) {
        let previousApp = NSWorkspace.shared.frontmostApplication
        store.copyItem(item)
        guard settings.isPasteHintEnabled else { return }
        pasteHintToast.show(relativeTo: previousApp)
    }

    @objc private func editSnippetTags(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardHistoryItem else { return }
        onEditSnippetTags(item)
    }

    @objc private func removeSnippetTags(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardHistoryItem else { return }
        store.removeAllTags(from: item)
    }

    @objc private func deleteSnippet(_ sender: NSMenuItem) {
        guard let item = sender.representedObject as? ClipboardHistoryItem else { return }
        store.deleteItem(item)
    }
}

struct SettingsPopoverView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: ClipboardStore

    let onShowOnboarding: () -> Void
    let onQuit: () -> Void

    @State private var showsLaunchAtLoginConfirmation = false
    @State private var showsAutomaticPastePermissionSheet = false
    @State private var shouldRevertAutomaticPasteOnPermissionSheetDismiss = false
    @State private var showsClearTaggedConfirmation = false

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
                    privacySection
                    actionsSection
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.never)
        }
        .frame(width: 320, height: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("Launch at Login?", isPresented: $showsLaunchAtLoginConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Enable") {
                settings.isLaunchAtLoginEnabled = true
            }
        } message: {
            Text("Open Copypastik automatically when you log in to your Mac?")
        }
        .alert("Clear Tagged Snippets?", isPresented: $showsClearTaggedConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                store.clearTaggedItems()
            }
        } message: {
            Text("Remove all locally stored tagged snippets from this Mac?")
        }
        .sheet(
            isPresented: $showsAutomaticPastePermissionSheet,
            onDismiss: handleAutomaticPastePermissionSheetDismiss
        ) {
            AutomaticPastePermissionSheet(
                onOpenSystemSettings: openAutomaticPasteSystemSettings,
                onNotNow: cancelAutomaticPasteEnablement
            )
        }
        .onAppear {
            settings.refreshPasteAutomationPermission()
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
                symbolName: "lock",
                title: "Privacy",
                subtitle: settings.isHistoryPersistenceEnabled
                    ? "Everything stays on this Mac. History is saved locally for the Library; paused and ignored apps are never recorded."
                    : "History is memory-only; tagged snippets and pins are stored locally.",
                tint: Color.accentColor
            )
        }
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

            SettingsToggleRow(
                symbolName: "command",
                title: "Automatic Paste",
                subtitle: automaticPasteSubtitle,
                tint: Color.accentColor,
                isOn: automaticPasteBinding
            )

            SettingsRowDivider()

            SettingsToggleRow(
                symbolName: "text.viewfinder",
                title: "Recognize Text in Images",
                subtitle: "Finds text in copied images so you can search it. Runs on this Mac with Apple Vision; nothing is uploaded.",
                tint: Color.accentColor,
                isOn: $settings.isImageTextRecognitionEnabled
            )

            SettingsRowDivider()

            SettingsToggleRow(
                symbolName: "externaldrive",
                title: "Keep History Between Launches",
                subtitle: "Saves history in this app's local storage for the Library. Off keeps it in memory only.",
                tint: Color.accentColor,
                isOn: $settings.isHistoryPersistenceEnabled
            )

            SettingsRowDivider()

            SettingsToggleRow(
                symbolName: "text.bubble",
                title: "Show paste hint",
                subtitle: "Show a brief hint after copying for manual paste.",
                tint: Color.accentColor,
                isOn: $settings.isPasteHintEnabled
            )

            SettingsRowDivider()

            SettingsHistoryLimitRow(historyLimit: $settings.historyLimit)
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            pauseCaptureRow

            SettingsRowDivider()

            IgnoredAppsEditor(settings: settings)
        }
    }

    private var pauseCaptureRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsIcon(
                    symbolName: settings.isCapturePaused ? "pause.circle.fill" : "pause.circle",
                    tint: settings.isCapturePaused ? .orange : Color.accentColor
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pause Capture")
                        .font(.system(size: 12.5, weight: .medium))
                    Text(settings.capturePauseStatusText ?? "New clipboard items are being saved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }

            if settings.isCapturePaused {
                Button("Resume Capture") {
                    settings.resumeCapture()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    ForEach(CapturePauseDuration.allCases) { duration in
                        Button(duration.displayName) {
                            settings.pauseCapture(for: duration)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var automaticPasteSubtitle: String {
        if !settings.isAutomaticPasteEnabled {
            return "Off by default; selected items stay on the clipboard."
        }

        if settings.hasPostEventAccess {
            return "Pastes into the previous app after selection."
        }

        return "Allow Copypastik in System Settings to paste automatically."
    }

    private var automaticPasteBinding: Binding<Bool> {
        Binding(
            get: {
                settings.isAutomaticPasteEnabled
            },
            set: { newValue in
                guard newValue else {
                    shouldRevertAutomaticPasteOnPermissionSheetDismiss = false
                    showsAutomaticPastePermissionSheet = false
                    settings.isAutomaticPasteEnabled = false
                    return
                }

                settings.refreshPasteAutomationPermission()
                settings.isAutomaticPasteEnabled = true

                if !settings.hasPostEventAccess {
                    shouldRevertAutomaticPasteOnPermissionSheetDismiss = true
                    showsAutomaticPastePermissionSheet = true
                }
            }
        )
    }

    private func openAutomaticPasteSystemSettings() {
        shouldRevertAutomaticPasteOnPermissionSheetDismiss = false
        showsAutomaticPastePermissionSheet = false

        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func cancelAutomaticPasteEnablement() {
        shouldRevertAutomaticPasteOnPermissionSheetDismiss = false
        settings.isAutomaticPasteEnabled = false
        showsAutomaticPastePermissionSheet = false
    }

    private func handleAutomaticPastePermissionSheetDismiss() {
        guard shouldRevertAutomaticPasteOnPermissionSheetDismiss else { return }
        settings.isAutomaticPasteEnabled = false
        shouldRevertAutomaticPasteOnPermissionSheetDismiss = false
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

            Button {
                showsClearTaggedConfirmation = true
            } label: {
                SettingsActionContent(
                    symbolName: "tag.slash",
                    title: "Clear Tagged Snippets",
                    subtitle: store.taggedItems.isEmpty ? "No tagged snippets saved." : "Remove \(store.taggedItems.count) local snippets.",
                    tint: .red
                )
            }
            .buttonStyle(.plain)
            .disabled(store.taggedItems.isEmpty)
            .opacity(store.taggedItems.isEmpty ? 0.55 : 1)

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

private struct AutomaticPastePermissionSheet: View {
    let onOpenSystemSettings: () -> Void
    let onNotNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Enable Automatic Paste")
                .font(.system(size: 18, weight: .semibold))

            Text("To paste automatically, macOS requires you to allow Copypastik in System Settings → Privacy & Security → Accessibility. Without this, selected items are still copied to the clipboard and you can paste them with ⌘V.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()

                Button("Not Now", role: .cancel, action: onNotNow)
                    .keyboardShortcut(.cancelAction)

                Button("Open System Settings", action: onOpenSystemSettings)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 440)
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

private struct IgnoredAppsEditor: View {
    @ObservedObject var settings: AppSettings
    @State private var newBundleID: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SettingsIcon(symbolName: "eye.slash", tint: .red)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Ignored Apps")
                        .font(.system(size: 12.5, weight: .medium))
                    Text("Clipboard changes from these apps are never saved.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
            }

            if settings.ignoredAppBundleIDs.isEmpty {
                Text("No ignored apps.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 4) {
                    ForEach(settings.ignoredAppBundleIDs.sorted(), id: \.self) { bundleID in
                        HStack(spacing: 6) {
                            Text(bundleID)
                                .font(.system(size: 10.5, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            Button {
                                settings.removeIgnoredApp(bundleID: bundleID)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("com.example.app", text: $newBundleID)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11.5))
                    .onSubmit(addIgnoredApp)

                Button("Add", action: addIgnoredApp)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func addIgnoredApp() {
        guard !newBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        settings.addIgnoredApp(bundleID: newBundleID)
        newBundleID = ""
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

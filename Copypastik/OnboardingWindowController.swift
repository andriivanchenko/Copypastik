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
        print("[Copypastik] onboarding window became key")
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.window = nil
            print("[Copypastik] onboarding window closed")
        }
    }
}

private struct OnboardingStep: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let symbolName: String
}

struct OnboardingView: View {
    let settings: AppSettings
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIndex = 0

    var body: some View {
        VStack(spacing: 0) {
            hero

            VStack(spacing: 18) {
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

            OnboardingPickerPreview(
                selectedIndex: selectedIndex,
                shortcutDisplayName: settings.pickerShortcut.displayName,
                reduceMotion: reduceMotion
            )
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
                body: "Keep a clean text and image clipboard history right in your menu bar.",
                symbolName: "menubar.rectangle"
            ),
            OnboardingStep(
                title: "Use the Shortcut",
                body: "Press \(settings.pickerShortcut.displayName) anywhere to open the floating picker.",
                symbolName: "keyboard"
            ),
            OnboardingStep(
                title: "Paste Text or Images",
                body: "Choose an item and Copypastik writes it back to your clipboard.",
                symbolName: "photo.on.rectangle"
            ),
            OnboardingStep(
                title: "Search and Manage History",
                body: "Filter copied text and images, use the arrow keys, delete rows, or clear everything.",
                symbolName: "magnifyingglass"
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
                PreviewRow(
                    symbolName: "terminal",
                    title: "xcodebuild build -scheme Copypastik",
                    isSelected: selectedPreviewRow == 0
                )
                PreviewRow(
                    symbolName: "link",
                    title: "https://developer.apple.com/design",
                    isSelected: selectedPreviewRow == 1
                )
                PreviewRow(
                    symbolName: "photo",
                    title: "Screenshot",
                    isSelected: selectedPreviewRow == 2,
                    showsThumbnail: true
                )
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 0)

            HStack(spacing: 5) {
                KeycapToken(text: "↑↓", minWidth: 33)
                KeycapToken(text: "↵")
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
        case 3:
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
            return 1
        default:
            return 0
        }
    }
}

private struct PreviewRow: View {
    let symbolName: String
    let title: String
    let isSelected: Bool
    var showsThumbnail = false

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
        .frame(height: showsThumbnail ? 56 : 50)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.62) : Color.primary.opacity(0.06), lineWidth: 0.75)
        )
    }
}

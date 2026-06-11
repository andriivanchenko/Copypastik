import AppKit
import SwiftUI

enum CopypastikTheme {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let accentDeep = Color(red: 0.0, green: 0.32, blue: 0.72)
    static let accentGlow = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let warning = Color(red: 0.98, green: 0.58, blue: 0.16)
    static let success = Color(red: 0.18, green: 0.68, blue: 0.35)
}

private enum ClipboardHeuristics {
    static let webLinkPrefixes = ["http://", "https://"]
    static let terminalPromptPrefixes = ["$ ", "> "]
    static let shellCommandPrefixes = ["git ", "npm ", "pnpm ", "yarn ", "swift ", "xcodebuild ", "curl ", "uv ", "cd ", "mkdir ", "rm "]
    static let pathIndicators = ["/", "\\", ".swift", ".json", ".md", ".js", ".ts", ".py", ".sh", ".env"]
    static let codeSymbols = [" = ", " == ", " != ", "->", "::", "()", " && ", " || "]

    static func hasWebLinkPrefix(_ lowercasedText: String) -> Bool {
        webLinkPrefixes.contains(where: { lowercasedText.hasPrefix($0) })
    }

    static func hasCommandPrefix(_ lowercasedText: String, includePromptPrefixes: Bool) -> Bool {
        if includePromptPrefixes,
           terminalPromptPrefixes.contains(where: { lowercasedText.hasPrefix($0) }) {
            return true
        }
        return shellCommandPrefixes.contains(where: { lowercasedText.hasPrefix($0) })
    }

    static func hasPathIndicator(_ text: String) -> Bool {
        pathIndicators.contains(where: { text.contains($0) })
    }

    static func hasCodeSymbol(_ text: String) -> Bool {
        codeSymbols.contains(where: { text.contains($0) })
    }
}

enum ClipboardSnippetDetector {
    static func isCodeLike(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isNewline) else { return false }

        let lowercased = trimmed.lowercased()
        if ClipboardHeuristics.hasWebLinkPrefix(lowercased) {
            return true
        }

        if ClipboardHeuristics.hasCommandPrefix(lowercased, includePromptPrefixes: true) ||
            trimmed.hasPrefix("./") ||
            trimmed.hasPrefix("~/") {
            return true
        }

        if (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || (trimmed.hasPrefix("[") && trimmed.hasSuffix("]")) {
            return true
        }

        if ClipboardHeuristics.hasPathIndicator(trimmed) && !trimmed.contains(" ") {
            return true
        }

        return ClipboardHeuristics.hasCodeSymbol(trimmed)
    }
}

enum ClipboardItemKind {
    case command
    case link
    case code
    case multiline
    case text

    var displayName: String {
        switch self {
        case .command:
            return "Command"
        case .link:
            return "Link"
        case .code:
            return "Code"
        case .multiline, .text:
            return "Text"
        }
    }

    var symbolName: String {
        switch self {
        case .command:
            return "terminal"
        case .link:
            return "link"
        case .code:
            return "curlybraces"
        case .multiline:
            return "text.alignleft"
        case .text:
            return "text.quote"
        }
    }

    var usesMonospacedPreview: Bool {
        switch self {
        case .command, .code:
            return true
        case .link, .multiline, .text:
            return false
        }
    }

    static func detect(_ text: String) -> ClipboardItemKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        if ClipboardHeuristics.hasWebLinkPrefix(lowercased) {
            return .link
        }

        if trimmed.contains(where: \.isNewline) {
            return .multiline
        }

        if ClipboardHeuristics.hasCommandPrefix(lowercased, includePromptPrefixes: true) {
            return .command
        }

        if ClipboardSnippetDetector.isCodeLike(text) {
            return .code
        }

        return .text
    }
}

struct ClipboardItemPresentation {
    let text: String
    let kind: ClipboardItemKind
    let characterCount: Int
    let lineCount: Int

    init(text: String) {
        self.text = text
        kind = ClipboardItemKind.detect(text)
        characterCount = text.trimmingCharacters(in: .whitespacesAndNewlines).count
        lineCount = max(1, text.split(whereSeparator: \.isNewline).count)
    }

    var previewFont: Font {
        kind.usesMonospacedPreview ? .system(size: 12.5, design: .monospaced) : .system(size: 13)
    }

    func metadata(isNewest: Bool) -> String {
        var parts = [kind.displayName]

        if lineCount > 1 {
            parts.append("\(lineCount) lines")
        } else {
            parts.append("\(characterCount) \(characterCount == 1 ? "char" : "chars")")
        }

        if isNewest {
            parts.append("Now")
        }

        return parts.joined(separator: " · ")
    }
}

struct ClipboardImagePresentation {
    let image: ClipboardImage

    func metadata(isNewest: Bool) -> String {
        var parts = ["Image", image.dimensionsLabel, image.formatLabel]
        if isNewest {
            parts.append("Now")
        }
        return parts.joined(separator: " · ")
    }
}

private struct LiquidGlassBackdrop: NSViewRepresentable {
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = true
        configure(view)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        configure(nsView)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.masksToBounds = true
        if #available(macOS 10.15, *) {
            view.layer?.cornerCurve = .continuous
        }
    }
}

struct ClipboardPickerView: View {
    @ObservedObject var state: PickerState
    let onSelect: (Int) -> Void
    let onRevealDelete: (Int) -> Void
    let onBeginDelete: (Int) -> Void
    let onConfirmDelete: (ClipboardHistoryItem) -> Void
    let onMoveSelection: (Int) -> Void
    let onConfirmSelection: () -> Void
    let onClearHistory: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
    @Namespace private var selectionNamespace
    @State private var hasAppeared = false
    @State private var clearingItems = Set<ClipboardHistoryItem>()
    @State private var isClearingHistory = false

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()
                .opacity(0.55)

            pickerContent

            Divider()
                .opacity(0.45)

            footer
        }
        .frame(width: PickerTheme.width, height: PickerTheme.height)
        .background(windowBackground)
        .clipShape(RoundedRectangle(cornerRadius: PickerTheme.cornerRadius, style: .continuous))
        .overlay(windowGlassOverlay)
        .overlay(windowBorder)
        .shadow(color: .black.opacity(rootShadowOpacity), radius: rootShadowRadius, x: 0, y: rootShadowYOffset)
        .scaleEffect(rootScale)
        .opacity(rootOpacity)
        .animation(closeAnimation, value: state.isClosing)
        .onMoveCommand { direction in
            switch direction {
            case .down:
                onMoveSelection(1)
            case .up:
                onMoveSelection(-1)
            default:
                break
            }
        }
        .onExitCommand(perform: onClose)
        .onAppear(perform: beginPresentation)
        .onChange(of: state.presentationID) { _, _ in
            beginPresentation()
        }
        .onChange(of: state.searchFocusTrigger) { _, _ in
            focusSearchField()
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))

                TextField("Search history...", text: $state.query)
                    .onSubmit(onConfirmSelection)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isSearchFocused)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(searchFieldTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(searchFieldStroke, lineWidth: 0.75)
            )
            .shadow(color: Color.white.opacity(colorScheme == .dark ? 0.02 : 0.28), radius: 5, x: 0, y: 1)
            .animation(.easeOut(duration: 0.12), value: isSearchFocused)

            Text(state.matchCountLabel)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 64, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
    }

    @ViewBuilder
    private var pickerContent: some View {
        if state.filteredItems.isEmpty {
            EmptyPickerState(
                hasQuery: !state.normalizedQuery.isEmpty,
                reduceMotion: reduceMotion
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(Array(state.filteredItems.enumerated()), id: \.element) { index, item in
                            ClipboardItemRow(
                                item: item,
                                isSelected: index == state.selectedIndex,
                                isPressed: index == state.pressedIndex,
                                isNewest: state.normalizedQuery.isEmpty && index == 0,
                                isDeleteRevealed: state.revealedDeleteItem == item,
                                isDeleting: state.deletingItem == item,
                                showsReturnGlyph: true,
                                showsCardFill: false,
                                selectionNamespace: reduceMotion ? nil : selectionNamespace,
                                revealDelay: revealDelay(for: index),
                                isClearing: clearingItems.contains(item),
                                clearDelay: clearDelay(for: index),
                                showsCopiedConfirmation: false,
                                reduceMotion: reduceMotion,
                                onRevealDelete: {
                                    onRevealDelete(index)
                                },
                                onBeginDelete: {
                                    onBeginDelete(index)
                                },
                                onConfirmDelete: {
                                    onConfirmDelete(item)
                                }
                            ) {
                                onSelect(index)
                            }
                            .id(item.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .animation(selectionAnimation, value: state.selectedIndex)
                }
                .scrollIndicators(.never)
                .animation(filterAnimation, value: state.filteredItems)
                .onChange(of: state.selectedIndex) { _, newIndex in
                    scroll(to: newIndex, with: proxy)
                }
                .onChange(of: state.filteredItems) { _, _ in
                    scroll(to: state.selectedIndex, with: proxy)
                }
            }
        }
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 13) {
                FooterHint(keys: "↑↓", label: "Move")
                FooterHint(keys: "↵", label: "Copy/Paste")
                FooterHint(keys: "esc", label: "Close")
            }

            HStack {
                Spacer()

                Button(action: beginClearHistory) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(state.items.isEmpty || isClearingHistory ? Color.secondary.opacity(0.25) : Color.secondary.opacity(0.62))
                .disabled(state.items.isEmpty || isClearingHistory)
                .help("Clear history")
            }
            .padding(.trailing, 10)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .opacity(0.72)
    }

    private var windowBackground: some View {
        ZStack {
            LiquidGlassBackdrop(cornerRadius: PickerTheme.cornerRadius)

            RoundedRectangle(cornerRadius: PickerTheme.cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(colorScheme == .dark ? 0.40 : 0.62)

            LinearGradient(
                colors: tintColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    CopypastikTheme.accentGlow.opacity(colorScheme == .dark ? 0.14 : 0.18),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 18,
                endRadius: 360
            )

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.12 : 0.40),
                    Color.white.opacity(colorScheme == .dark ? 0.030 : 0.11),
                    Color.clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var windowGlassOverlay: some View {
        RoundedRectangle(cornerRadius: PickerTheme.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.28 : 0.72),
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.20),
                        Color.black.opacity(colorScheme == .dark ? 0.22 : 0.07)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1.35
            )
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: PickerTheme.cornerRadius - 2, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.34), lineWidth: 0.7)
                    .padding(2)
                    .blendMode(.screen)
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: PickerTheme.cornerRadius - 3, style: .continuous)
                    .stroke(Color.white.opacity(colorScheme == .dark ? 0.14 : 0.55), lineWidth: 1)
                    .padding(.horizontal, 3)
                    .padding(.top, 3)
                    .frame(height: 88)
                    .mask(
                        LinearGradient(
                            colors: [
                                Color.white,
                                Color.white.opacity(0.35),
                                Color.clear
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .blendMode(.screen)
            }
            .allowsHitTesting(false)
    }

    private var windowBorder: some View {
        RoundedRectangle(cornerRadius: PickerTheme.cornerRadius, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.10 : 0.26),
                        Color(nsColor: .separatorColor).opacity(colorScheme == .dark ? 0.34 : 0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 0.75
            )
    }

    private var tintColors: [Color] {
        if colorScheme == .dark {
            return [
                Color.white.opacity(0.07),
                CopypastikTheme.accentGlow.opacity(0.06),
                CopypastikTheme.accentDeep.opacity(0.045)
            ]
        }
        return [
            Color.white.opacity(0.28),
            CopypastikTheme.accentGlow.opacity(0.07),
            CopypastikTheme.accentDeep.opacity(0.025)
        ]
    }

    private var searchFieldTint: LinearGradient {
        LinearGradient(
            colors: [
                Color.white.opacity(colorScheme == .dark ? 0.06 : 0.30),
                CopypastikTheme.accentGlow.opacity(isSearchFocused ? 0.10 : 0.045),
                Color.primary.opacity(colorScheme == .dark ? 0.035 : 0.018)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var searchFieldStroke: Color {
        if isSearchFocused {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.54 : 0.42)
        }
        return Color.white.opacity(colorScheme == .dark ? 0.08 : 0.24)
    }

    private var rootScale: CGFloat {
        guard !reduceMotion else { return 1 }
        if state.isClosing { return 0.985 }
        return hasAppeared ? 1 : 0.96
    }

    private var rootOpacity: Double {
        if state.isClosing { return 0 }
        return hasAppeared ? 1 : 0
    }

    private var rootShadowOpacity: Double {
        guard !reduceMotion else { return 0.24 }
        return hasAppeared ? 0.24 : 0.18
    }

    private var rootShadowRadius: CGFloat {
        guard !reduceMotion else { return 34 }
        return hasAppeared ? 34 : 42
    }

    private var rootShadowYOffset: CGFloat {
        guard !reduceMotion else { return 14 }
        return hasAppeared ? 14 : 18
    }

    private var closeAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.08) : .easeOut(duration: 0.11)
    }

    private var filterAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.24, dampingFraction: 0.86)
    }

    private var selectionAnimation: Animation? {
        reduceMotion ? nil : .spring(response: 0.20, dampingFraction: 0.86)
    }

    private func beginPresentation() {
        hasAppeared = false
        focusSearchField()

        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.08)
            : .spring(response: 0.22, dampingFraction: 0.82)

        DispatchQueue.main.async {
            withAnimation(animation) {
                hasAppeared = true
            }
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.async {
            isSearchFocused = true
        }
    }

    private func revealDelay(for index: Int) -> Double {
        guard !reduceMotion, index < 7 else { return 0 }
        return Double(index) * 0.018
    }

    private func beginClearHistory() {
        guard !state.items.isEmpty, !isClearingHistory else { return }

        let itemsToClear = state.filteredItems
        HistoryClearAnimation.run(
            items: itemsToClear,
            reduceMotion: reduceMotion,
            onStart: { items in
                isClearingHistory = true
                clearingItems = items
            },
            onFinish: {
                onClearHistory()
                clearingItems.removeAll()
                isClearingHistory = false
            }
        )
    }

    private func clearDelay(for index: Int) -> Double {
        HistoryClearAnimation.clearDelay(for: index, reduceMotion: reduceMotion)
    }

    private func scroll(to index: Int, with proxy: ScrollViewProxy) {
        guard state.filteredItems.indices.contains(index) else { return }
        let item = state.filteredItems[index]

        let action = {
            proxy.scrollTo(item.id, anchor: .center)
        }

        DispatchQueue.main.async {
            if reduceMotion {
                action()
            } else {
                withAnimation(.easeOut(duration: 0.16), action)
            }
        }
    }
}

enum PickerTheme {
    static let width: CGFloat = 360
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 22
    static let rowRadius: CGFloat = 9
    static let clearRippleStep: Double = 0.016
    static let clearRippleDuration: Double = 0.16
    static let selectionHighlightID = "selected-row-highlight"
}

enum HistoryClearAnimation {
    static func clearDelay(for index: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion else { return 0 }
        return Double(index) * PickerTheme.clearRippleStep
    }

    static func completionDelay(for itemCount: Int, reduceMotion: Bool) -> Double {
        guard !reduceMotion, itemCount > 0 else { return 0.01 }
        return Double(itemCount - 1) * PickerTheme.clearRippleStep + PickerTheme.clearRippleDuration
    }

    static func run<Item: Hashable>(
        items: [Item],
        reduceMotion: Bool,
        onStart: (Set<Item>) -> Void,
        onFinish: @escaping () -> Void
    ) {
        guard !items.isEmpty else {
            onFinish()
            return
        }

        onStart(Set(items))
        DispatchQueue.main.asyncAfter(deadline: .now() + completionDelay(for: items.count, reduceMotion: reduceMotion)) {
            onFinish()
        }
    }
}

struct ClipboardItemRow: View {
    let item: ClipboardHistoryItem
    let isSelected: Bool
    let isPressed: Bool
    let isNewest: Bool
    let isDeleteRevealed: Bool
    let isDeleting: Bool
    let showsReturnGlyph: Bool
    let showsCardFill: Bool
    let selectionNamespace: Namespace.ID?
    let revealDelay: Double
    let isClearing: Bool
    let clearDelay: Double
    let showsCopiedConfirmation: Bool
    let reduceMotion: Bool
    let onRevealDelete: () -> Void
    let onBeginDelete: () -> Void
    let onConfirmDelete: () -> Void
    let onSelect: () -> Void

    @State private var isHovered = false
    @State private var isRevealed = false
    @State private var hasScheduledDelete = false

    private var textPresentation: ClipboardItemPresentation? {
        guard let text = item.textValue else { return nil }
        return ClipboardItemPresentation(text: text)
    }

    private var imagePresentation: ClipboardImagePresentation? {
        guard let image = item.imageValue else { return nil }
        return ClipboardImagePresentation(image: image)
    }

    private var isImageItem: Bool {
        item.imageValue != nil
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            deleteButton

            Button(action: onSelect) {
                rowContent
            }
            .buttonStyle(.plain)
            .offset(x: rowOffset)
            .opacity(isDeleting ? 0 : 1)
            .animation(rowSlideAnimation, value: isDeleteRevealed)
            .animation(rowSlideAnimation, value: isDeleting)
        }
        .contentShape(RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous))
        .background(RightClickReader(onRightClick: onRevealDelete))
        .clipped()
        .allowsHitTesting(!isClearing)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHovered = hovering
            }
        }
        .opacity(rowOpacity)
        .offset(y: rowVerticalOffset)
        .scaleEffect(rowScale, anchor: .top)
        .animation(clearAnimation, value: isClearing)
        .onAppear(perform: reveal)
        .onChange(of: item) { _, _ in
            reveal()
        }
        .onChange(of: isDeleting) { _, deleting in
            guard deleting else {
                hasScheduledDelete = false
                return
            }
            scheduleDelete()
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            itemIcon

            ZStack(alignment: .trailing) {
                rowPreview
                .padding(.trailing, copiedConfirmationReservedWidth)
                .frame(maxWidth: .infinity, alignment: .leading)

                copiedConfirmationBadge
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsReturnGlyph {
                Text("↵")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.accentColor.opacity(0.74))
                    .frame(width: 18, height: 18)
                    .background(
                        Circle()
                            .fill(Color.accentColor.opacity(0.13))
                    )
                    .opacity(isSelected && !isDeleteRevealed ? 1 : 0)
                    .scaleEffect(isSelected && !isDeleteRevealed ? 1 : 0.92)
                    .offset(x: returnGlyphOffset)
                    .animation(returnGlyphAnimation, value: isSelected)
                    .animation(.easeOut(duration: 0.10), value: isDeleteRevealed)
            }
        }
        .frame(minHeight: rowMinimumHeight, alignment: .center)
        .padding(.horizontal, showsCardFill ? 11 : 10)
        .padding(.vertical, showsCardFill ? 5 : 2)
        .contentShape(RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous))
        .background(rowBackgroundLayer)
        .clipShape(RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous))
        .scaleEffect(isPressed ? 0.985 : 1)
        .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    @ViewBuilder
    private var rowPreview: some View {
        if let imagePresentation {
            HStack(spacing: 8) {
                imageThumbnail(imagePresentation.image)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Image")
                        .lineLimit(1)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let textPresentation {
            VStack(alignment: .leading, spacing: 0) {
                Text(textPresentation.text)
                    .lineLimit(2)
                    .font(textPresentation.previewFont)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func imageThumbnail(_ image: ClipboardImage) -> some View {
        if let nsImage = image.nsImage {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .frame(width: 54, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.75)
                )
        } else {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: 54, height: 40)
                .overlay(
                    Image(systemName: "photo")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.82))
                )
        }
    }

    private var rowMinimumHeight: CGFloat {
        if isImageItem {
            return showsCardFill ? 60 : 54
        }
        return showsCardFill ? 48 : 44
    }

    private var deleteButton: some View {
        Button(action: onBeginDelete) {
            Image(systemName: "trash")
                .font(.system(size: 12, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(Color.red.opacity(0.88))
                )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 9)
        .opacity(isDeleteRevealed ? 1 : 0)
        .scaleEffect(isDeleteRevealed ? 1 : 0.84)
        .disabled(!isDeleteRevealed || isDeleting || isClearing)
        .allowsHitTesting(isDeleteRevealed && !isDeleting && !isClearing)
        .accessibilityLabel("Delete item")
        .help("Delete item")
        .animation(rowSlideAnimation, value: isDeleteRevealed)
    }

    private var rowOffset: CGFloat {
        if isDeleting { return -96 }
        return isDeleteRevealed ? -42 : 0
    }

    private var rowSlideAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.01) : .easeOut(duration: 0.14)
    }

    private var clearAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.01) : .easeInOut(duration: PickerTheme.clearRippleDuration).delay(clearDelay)
    }

    private var returnGlyphOffset: CGFloat {
        guard !reduceMotion else { return 0 }
        return isSelected && !isDeleteRevealed ? 0 : 7
    }

    private var returnGlyphAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.01) : .spring(response: 0.18, dampingFraction: 0.78)
    }

    private var rowOpacity: Double {
        guard isRevealed else { return 0 }
        return isClearing ? 0 : 1
    }

    private var rowVerticalOffset: CGFloat {
        if isClearing {
            return reduceMotion ? 0 : -5
        }
        return isRevealed ? 0 : 4
    }

    private var rowScale: CGFloat {
        guard isClearing, !reduceMotion else { return 1 }
        return 0.985
    }

    private var itemIcon: some View {
        ZStack {
            Circle()
                .fill(iconFill)

            Image(systemName: iconSymbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconForeground)
                .symbolRenderingMode(.hierarchical)
        }
        .frame(width: 26, height: 26)
        .overlay(alignment: .topTrailing) {
            if isNewest {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .overlay(
                        Circle()
                            .strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.85), lineWidth: 1)
                    )
                    .offset(x: 1, y: -1)
            }
        }
    }

    private var iconFill: Color {
        if isSelected {
            return Color.accentColor.opacity(0.22)
        }

        return isImageItem ? Color.accentColor.opacity(0.10) : Color.primary.opacity(0.055)
    }

    private var iconForeground: Color {
        if isSelected {
            return Color.accentColor.opacity(0.95)
        }

        return isImageItem ? Color.accentColor.opacity(0.76) : Color.secondary.opacity(0.86)
    }

    private var iconSymbolName: String {
        textPresentation?.kind.symbolName ?? "photo"
    }

    @ViewBuilder
    private var rowBackgroundLayer: some View {
        if isSelected {
            if let selectionNamespace, !reduceMotion {
                selectedRowBackground
                    .matchedGeometryEffect(id: PickerTheme.selectionHighlightID, in: selectionNamespace)
            } else {
                selectedRowBackground
            }
        } else if isHovered || showsCardFill {
            passiveRowBackground
        } else {
            Color.clear
        }
    }

    private var selectedRowBackground: some View {
        ZStack {
            RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                .fill(.regularMaterial)

            RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.20),
                            Color.accentColor.opacity(0.20),
                            CopypastikTheme.accentGlow.opacity(0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay(
            RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.42),
                            Color.accentColor.opacity(0.58),
                            Color.accentColor.opacity(0.24)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
        )
        .shadow(color: rowGlowColor, radius: 10, x: 0, y: 1)
    }

    private var passiveRowBackground: some View {
        ZStack {
            if isHovered {
                RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                    .fill(.thinMaterial)
            }

            RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                .fill(passiveRowFill)
        }
        .overlay(
            RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                .strokeBorder(rowStroke, lineWidth: showsCardFill || isHovered ? 0.75 : 0)
        )
    }

    private var passiveRowFill: Color {
        if isHovered {
            return Color.white.opacity(0.055)
        }
        if showsCardFill {
            return Color.primary.opacity(0.035)
        }
        return Color.clear
    }

    private var rowStroke: Color {
        if isHovered {
            return Color.white.opacity(0.20)
        }
        if showsCardFill {
            return Color.primary.opacity(0.065)
        }
        return Color.clear
    }

    private var rowGlowColor: Color {
        isSelected ? CopypastikTheme.accentGlow.opacity(0.22) : .clear
    }

    private var copiedConfirmationReservedWidth: CGFloat {
        showsCardFill ? 84 : 0
    }

    @ViewBuilder
    private var copiedConfirmationBadge: some View {
        if showsCardFill {
            HStack(spacing: 4) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9.5, weight: .bold))

                Text("Copied!")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor.opacity(0.95))
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.13))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.24), lineWidth: 0.5)
            )
            .opacity(showsCopiedConfirmation ? 1 : 0)
            .scaleEffect(copiedConfirmationScale)
            .offset(y: copiedConfirmationOffset)
            .animation(copiedConfirmationAnimation, value: showsCopiedConfirmation)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private var copiedConfirmationScale: CGFloat {
        reduceMotion ? 1 : (showsCopiedConfirmation ? 1 : 0.96)
    }

    private var copiedConfirmationOffset: CGFloat {
        reduceMotion ? 0 : (showsCopiedConfirmation ? 0 : 2)
    }

    private var copiedConfirmationAnimation: Animation? {
        reduceMotion ? .easeOut(duration: 0.08) : .spring(response: 0.22, dampingFraction: 0.82)
    }

    private func reveal() {
        isRevealed = false
        hasScheduledDelete = false

        guard !reduceMotion else {
            isRevealed = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + revealDelay) {
            withAnimation(.easeOut(duration: 0.16)) {
                isRevealed = true
            }
        }
    }

    private func scheduleDelete() {
        guard !hasScheduledDelete else { return }
        hasScheduledDelete = true

        let delay = reduceMotion ? 0 : 0.14
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            onConfirmDelete()
        }
    }
}

private struct RightClickReader: NSViewRepresentable {
    let onRightClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = RightClickView()
        view.onRightClick = onRightClick
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? RightClickView else { return }
        view.onRightClick = onRightClick
    }

    private final class RightClickView: NSView {
        var onRightClick: (() -> Void)?

        override func rightMouseDown(with event: NSEvent) {
            onRightClick?()
        }
    }
}

private struct EmptyPickerState: View {
    let hasQuery: Bool
    let reduceMotion: Bool

    var body: some View {
        ClipboardEmptyState(
            symbolName: hasQuery ? "magnifyingglass" : "doc.on.clipboard",
            title: hasQuery ? "No matches" : "Nothing copied yet",
            subtitle: hasQuery ? "Try a shorter search." : "Copy text or images anywhere and they will appear here.",
            reduceMotion: reduceMotion
        )
    }
}

struct ClipboardEmptyState: View {
    let symbolName: String
    let title: String
    let subtitle: String
    let reduceMotion: Bool

    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(.regularMaterial)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Circle()
                            .strokeBorder(.white.opacity(0.16), lineWidth: 0.5)
                    )

                Image(systemName: symbolName)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(.secondary)
                    .symbolRenderingMode(.hierarchical)
            }
            .scaleEffect(iconScale)

            VStack(spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 28)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: reduceMotion ? 0 : (hasAppeared ? 0 : 5))
        .onAppear(perform: beginArrival)
        .onChange(of: symbolName) { _, _ in
            beginArrival()
        }
    }

    private var iconScale: CGFloat {
        reduceMotion ? 1 : (hasAppeared ? 1 : 0.94)
    }

    private func beginArrival() {
        hasAppeared = false

        let animation: Animation = reduceMotion
            ? .easeOut(duration: 0.08)
            : .spring(response: 0.24, dampingFraction: 0.72)

        DispatchQueue.main.async {
            withAnimation(animation) {
                hasAppeared = true
            }
        }
    }
}

struct FooterHint: View {
    let keys: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Color.secondary.opacity(0.86))
                .monospacedDigit()

            Text(label)
                .font(.system(size: 10.5, weight: .regular))
                .foregroundStyle(Color.secondary.opacity(0.62))
        }
        .lineLimit(1)
    }
}

struct KeycapToken: View {
    let text: String
    var minWidth: CGFloat = 25

    var body: some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(Color.secondary.opacity(0.72))
            .lineLimit(1)
            .frame(minWidth: minWidth)
            .frame(height: 18)
    }
}

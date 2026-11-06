import AppKit
import SwiftUI

enum CopypastikTheme {
    static let accent = Color(red: 0.04, green: 0.52, blue: 1.0)
    static let accentDeep = Color(red: 0.0, green: 0.32, blue: 0.72)
    static let accentGlow = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let warning = Color(red: 0.98, green: 0.58, blue: 0.16)
    static let success = Color(red: 0.18, green: 0.68, blue: 0.35)
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
    @ObservedObject var settings: AppSettings
    let onSelect: (Int) -> Void
    let onRevealDelete: (Int) -> Void
    let onBeginDelete: (Int) -> Void
    let onConfirmDelete: (ClipboardHistoryItem) -> Void
    let onMoveSelection: (Int) -> Void
    let onConfirmSelection: () -> Void
    let onToggleTaggedSection: () -> Void
    let onSelectTagChip: (PickerTagChip) -> Void
    let onSelectTypeFilter: (PickerTypeFilter) -> Void
    let onTogglePin: (ClipboardHistoryItem) -> Void
    let onBeginTagEdit: (Int) -> Void
    let onCommitTagEdit: () -> Void
    let onCancelTagEdit: () -> Void
    let onClearHistory: () -> Void
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var isSearchFocused: Bool
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
        .overlay(alignment: .bottom) {
            if let notice = state.notice {
                PickerNotice(text: notice)
                    .padding(.bottom, 34)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
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
        .onChange(of: state.editingTagsItem) { _, newItem in
            if newItem != nil {
                isSearchFocused = false
            } else {
                focusSearchField()
            }
        }
    }

    private var searchHeader: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))

                TextField("Search, #tag, @app, type:...", text: $state.query)
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
        if state.filteredItems.isEmpty && state.taggedItems.isEmpty && state.pinnedItems.isEmpty {
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
                        if state.isTypeFilterBarVisible {
                            typeFilterBar
                                .padding(.bottom, 2)
                        }

                        if state.isTagFilterBarVisible {
                            tagFilterBar
                                .padding(.bottom, 2)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if !state.filteredPinnedItems.isEmpty {
                            SectionHeader(
                                title: "Pinned",
                                count: state.filteredPinnedItems.count,
                                isCollapsed: false,
                                onToggle: {}
                            )
                            .allowsHitTesting(false)
                        }

                        ForEach(Array(state.filteredPinnedItems.enumerated()), id: \.element.id) { index, item in
                            pickerRow(item: item, index: index, section: "pinned", isHistoryNewest: false)
                        }

                        if !state.taggedItems.isEmpty {
                            SectionHeader(
                                title: "Tagged",
                                count: state.shouldShowTaggedRows ? state.filteredTaggedItems.count : state.taggedItems.count,
                                isCollapsed: !state.shouldShowTaggedRows,
                                onToggle: onToggleTaggedSection
                            )
                        }

                        if state.shouldShowTaggedRows {
                            ForEach(Array(state.filteredTaggedItems.enumerated()), id: \.element.id) { index, item in
                                pickerRow(item: item, index: state.filteredPinnedItems.count + index, section: "tagged", isHistoryNewest: false)
                            }
                        }

                        if !state.filteredHistoryItems.isEmpty {
                            SectionHeader(
                                title: "History",
                                count: state.filteredHistoryItems.count,
                                isCollapsed: false,
                                onToggle: {}
                            )
                            .allowsHitTesting(false)
                        }

                        ForEach(Array(state.filteredHistoryItems.enumerated()), id: \.element.id) { localIndex, item in
                            pickerRow(
                                item: item,
                                index: state.filteredPinnedItems.count + state.filteredTaggedItems.count + localIndex,
                                section: "history",
                                isHistoryNewest: state.normalizedQuery.isEmpty
                                    && state.activeTagFilters.isEmpty
                                    && state.activeTypeFilter == .all
                                    && localIndex == 0
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .animation(selectionAnimation, value: state.selectedIndex)
                    .animation(filterAnimation, value: state.isTagFilterBarVisible)
                }
                .scrollIndicators(.never)
                .animation(filterAnimation, value: state.filteredItemIDs)
                .onChange(of: state.selectedIndex) { _, newIndex in
                    scroll(to: newIndex, with: proxy)
                }
                .onChange(of: state.filteredItemIDs) { _, _ in
                    guard state.editingTagsItem == nil else { return }
                    scroll(to: state.selectedIndex, with: proxy)
                }
            }
        }
    }

    private var footer: some View {
        ZStack {
            HStack(spacing: 10) {
                FooterHint(keys: "↑↓", label: "Move")
                FooterHint(keys: "↵", label: "Copy")
                FooterHint(keys: "⌘P", label: "Pin")
                FooterHint(keys: "⌘T", label: "Tags")
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

    private var typeFilterBar: some View {
        HStack(spacing: 6) {
            ForEach(PickerTypeFilter.allCases) { filter in
                let isActive = state.activeTypeFilter == filter
                Button {
                    onSelectTypeFilter(filter)
                } label: {
                    Image(systemName: filter.symbolName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isActive ? Color.white.opacity(0.95) : Color.secondary.opacity(0.86))
                        .frame(maxWidth: .infinity)
                        .frame(height: 24)
                        .background(
                            Capsule()
                                .fill(isActive ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.055))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(isActive ? Color.accentColor.opacity(0.5) : Color.primary.opacity(0.08), lineWidth: 0.75)
                        )
                }
                .buttonStyle(.plain)
                .help(filter.displayName)
                .accessibilityLabel(filter.displayName)
                .accessibilityAddTraits(isActive ? .isSelected : [])
            }
        }
        .padding(.horizontal, 1)
        .padding(.vertical, 1)
    }

    private var tagFilterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(Array(state.tagFilterChips.enumerated()), id: \.element.id) { index, chip in
                    let isActive = state.isTagChipActive(chip)
                    let isFocused = state.focusedTagChipIndex == index
                    let tagColor = chip.tag.map { settings.tagColor(for: $0) } ?? .graphite
                    Button {
                        onSelectTagChip(chip)
                    } label: {
                        Text(chip.title)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(tagChipForeground(tagColor, isActive: isActive))
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(
                                Capsule()
                                    .fill(tagChipFill(tagColor, isActive: isActive))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(tagChipStroke(tagColor, isActive: isActive, isFocused: isFocused), lineWidth: isFocused ? 1.35 : 0.75)
                            )
                            .shadow(color: isFocused ? tagColor.base.opacity(0.24) : .clear, radius: 5, x: 0, y: 1)
                    }
                    .buttonStyle(.plain)
                    .scaleEffect(isFocused ? 1.04 : 1)
                    .contextMenu {
                        tagColorMenu(for: chip)
                    }
                    .accessibilityAddTraits(isActive ? .isSelected : [])
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
        }
        .scrollIndicators(.never)
    }

    private func tagChipForeground(_ color: TagColor, isActive: Bool) -> Color {
        if isActive {
            return colorScheme == .dark ? Color.white.opacity(0.94) : color.foreground
        }
        return color.foreground.opacity(colorScheme == .dark ? 0.92 : 0.88)
    }

    private func tagChipFill(_ color: TagColor, isActive: Bool) -> Color {
        if isActive {
            return color.base.opacity(colorScheme == .dark ? 0.42 : 0.30)
        }
        return color.base.opacity(colorScheme == .dark ? 0.16 : 0.20)
    }

    private func tagChipStroke(_ color: TagColor, isActive: Bool, isFocused: Bool) -> Color {
        if isFocused {
            return color.base.opacity(colorScheme == .dark ? 0.82 : 0.72)
        }
        return color.base.opacity(isActive ? 0.42 : 0.26)
    }

    @ViewBuilder
    private func tagColorMenu(for chip: PickerTagChip) -> some View {
        if let tag = chip.tag {
            ForEach(TagColor.allCases) { color in
                Button {
                    settings.setTagColor(color, for: tag)
                } label: {
                    Label(color.displayName, systemImage: settings.tagColor(for: tag) == color ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        }
    }

    @ViewBuilder
    private func pickerRow(item: ClipboardHistoryItem, index: Int, section: String, isHistoryNewest: Bool) -> some View {
        if state.editingTagsItem?.dedupKey == item.dedupKey {
            TagEditorRow(
                item: item,
                text: $state.tagEditorText,
                reduceMotion: reduceMotion,
                onCommit: onCommitTagEdit,
                onCancel: onCancelTagEdit
            )
            .id("editor-\(item.id)")
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        } else {
            ClipboardItemRow(
                item: item,
                isSelected: index == state.selectedIndex,
                isPressed: index == state.pressedIndex,
                isNewest: isHistoryNewest,
                isDeleteRevealed: state.revealedDeleteItem == item,
                isDeleting: state.deletingItem == item,
                showsReturnGlyph: true,
                showsCardFill: false,
                revealDelay: revealDelay(for: index),
                isClearing: clearingItems.contains(item),
                clearDelay: clearDelay(for: index),
                showsCopiedConfirmation: false,
                reduceMotion: reduceMotion,
                isHoveredOverride: state.hoveredItemID == item.id,
                tagColorProvider: { settings.tagColor(for: $0) },
                onRevealDelete: {
                    onRevealDelete(index)
                },
                onBeginDelete: {
                    onBeginDelete(index)
                },
                onConfirmDelete: {
                    onConfirmDelete(item)
                },
                onBeginTagEdit: {
                    onBeginTagEdit(index)
                },
                onTogglePin: {
                    onTogglePin(item)
                },
                onHoverChanged: { hovering in
                    state.hoveredItemID = hovering ? item.id : nil
                }
            ) {
                onSelect(index)
            }
            // Section-prefixed identity: when an item moves between sections
            // (pin/unpin), LazyVStack must treat it as a new row. Reusing the
            // bare item.id across sections left stale rows rendering outdated
            // selection state.
            .id("\(section)-\(item.id)")
            .transition(.opacity.combined(with: .move(edge: .bottom)))
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

        let itemsToClear = state.filteredHistoryItems
        guard !itemsToClear.isEmpty else { return }
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
        let rowID = rowID(for: index, item: item)

        let action = {
            proxy.scrollTo(rowID, anchor: .center)
        }

        DispatchQueue.main.async {
            if reduceMotion {
                action()
            } else {
                withAnimation(.easeOut(duration: 0.16), action)
            }
        }
    }

    private func rowID(for index: Int, item: ClipboardHistoryItem) -> String {
        let pinnedCount = state.filteredPinnedItems.count
        if index < pinnedCount {
            return "pinned-\(item.id)"
        }
        if index < pinnedCount + state.filteredTaggedItems.count {
            return "tagged-\(item.id)"
        }
        return "history-\(item.id)"
    }
}

enum PickerTheme {
    static let width: CGFloat = 360
    static let height: CGFloat = 420
    static let cornerRadius: CGFloat = 22
    static let rowRadius: CGFloat = 9
    static let clearRippleStep: Double = 0.016
    static let clearRippleDuration: Double = 0.16
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

private struct SectionHeader: View {
    let title: String
    let count: Int
    let isCollapsed: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 6) {
                Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)

                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                Text("\(count)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)

                Spacer()
            }
            .padding(.horizontal, 6)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PickerNotice: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.74))
            )
            .shadow(color: .black.opacity(0.22), radius: 8, y: 2)
            .accessibilityLabel(text)
    }
}

private struct TagEditorRow: View {
    let item: ClipboardHistoryItem
    @Binding var text: String
    let reduceMotion: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "tag")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor.opacity(0.92))
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.14))
                )

            VStack(alignment: .leading, spacing: 5) {
                TextField("tag, another-tag", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit(onCommit)

                Text("Enter saves · Esc cancels · max 5 tags")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Button(action: onCommit) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor.opacity(0.92))
            .help("Save tags")

            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 10.5, weight: .bold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.secondary)
            .help("Cancel")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.38), lineWidth: 0.9)
        )
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                isFocused = true
            }
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
    let revealDelay: Double
    let isClearing: Bool
    let clearDelay: Double
    let showsCopiedConfirmation: Bool
    let reduceMotion: Bool
    var isHoveredOverride: Bool? = nil
    let tagColorProvider: (String) -> TagColor
    let onRevealDelete: () -> Void
    let onBeginDelete: () -> Void
    let onConfirmDelete: () -> Void
    var onBeginTagEdit: () -> Void = {}
    var onTogglePin: () -> Void = {}
    var onHoverChanged: ((Bool) -> Void)? = nil
    let onSelect: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHoveredLocal = false
    @State private var isRevealed = false
    @State private var hasScheduledDelete = false

    private var isHovered: Bool { isHoveredOverride ?? isHoveredLocal }

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

            if showsReturnGlyph {
                HStack(spacing: 8) {
                    pinButton

                    tagEditButton

                    Color.clear
                        .frame(width: 18, height: 18)
                }
                .padding(.trailing, showsCardFill ? 11 : 10)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .offset(x: rowOffset)
                .opacity(showsTagEditButton ? 1 : 0)
                .scaleEffect(showsTagEditButton ? 1 : 0.9)
                .allowsHitTesting(showsTagEditButton)
                .animation(.easeOut(duration: 0.10), value: showsTagEditButton)
                .animation(rowSlideAnimation, value: isDeleteRevealed)
                .animation(rowSlideAnimation, value: isDeleting)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: PickerTheme.rowRadius, style: .continuous))
        .background(RightClickReader(onRightClick: onRevealDelete))
        .clipped()
        .allowsHitTesting(!isClearing)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.10)) {
                isHoveredLocal = hovering
            }
            onHoverChanged?(hovering)
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
                Color.clear
                    .frame(width: 18, height: 18)

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

                VStack(alignment: .leading, spacing: 3) {
                    Text("Image")
                        .lineLimit(1)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    tagLabels
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else if let textPresentation {
            VStack(alignment: .leading, spacing: 3) {
                Text(textPresentation.text)
                    .lineLimit(2)
                    .font(textPresentation.previewFont)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                tagLabels
            }
        }
    }

    @ViewBuilder
    private var tagLabels: some View {
        if item.pinnedSlot != nil || !item.tags.isEmpty || item.sourceAppSummaryLabel != nil {
            HStack(spacing: 4) {
                if let slot = item.pinnedSlot {
                    Text("⌃⌥\(slot)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(CopypastikTheme.accent.opacity(colorScheme == .dark ? 0.95 : 0.9))
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(
                            Capsule()
                                .fill(CopypastikTheme.accent.opacity(colorScheme == .dark ? 0.18 : 0.13))
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(CopypastikTheme.accent.opacity(0.30), lineWidth: 0.5)
                        )
                        .help("Control+Option+\(slot) pastes this clip from anywhere")
                }

                if !item.tags.isEmpty {
                    ForEach(item.tags, id: \.self) { tag in
                        let tagColor = tagColorProvider(tag)
                        Text("#\(tag)")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(tagColor.foreground.opacity(colorScheme == .dark ? 0.92 : 0.86))
                            .lineLimit(1)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(
                                Capsule()
                                    .fill(tagColor.base.opacity(colorScheme == .dark ? 0.16 : 0.18))
                            )
                            .overlay(
                                Capsule()
                                    .strokeBorder(tagColor.base.opacity(0.22), lineWidth: 0.5)
                            )
                    }
                } else if let sourceAppSummaryLabel = item.sourceAppSummaryLabel {
                    Text(sourceAppSummaryLabel)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var showsTagEditButton: Bool {
        (isHovered || isSelected) && !isDeleteRevealed && !isDeleting && !isClearing
    }

    private var tagEditButton: some View {
        Button(action: onBeginTagEdit) {
            Image(systemName: "tag")
                .font(.system(size: 10.5, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor.opacity(0.78))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(Color.accentColor.opacity(0.11))
                )
        }
        .buttonStyle(.plain)
        .help("Edit tags")
        .accessibilityLabel("Edit tags")
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: item.isPinned ? "pin.fill" : "pin")
                .font(.system(size: 10.5, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(item.isPinned ? CopypastikTheme.accent : Color.secondary.opacity(0.82))
                .frame(width: 18, height: 18)
                .background(
                    Circle()
                        .fill(item.isPinned ? CopypastikTheme.accent.opacity(0.16) : Color.primary.opacity(0.07))
                )
        }
        .buttonStyle(.plain)
        .help(item.isPinned ? "Unpin (⌘P)" : "Pin (⌘P)")
        .accessibilityLabel(item.isPinned ? "Unpin" : "Pin")
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

            if let sourceAppIcon {
                Image(nsImage: sourceAppIcon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .clipShape(RoundedRectangle(cornerRadius: 3.5, style: .continuous))
            } else {
                Image(systemName: iconSymbolName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(iconForeground)
                    .symbolRenderingMode(.hierarchical)
            }
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
        .overlay(alignment: .bottomTrailing) {
            if item.isPinned {
                pinBadge
            }
        }
    }

    private var pinBadge: some View {
        Group {
            if let slot = item.pinnedSlot {
                Text("\(slot)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Image(systemName: "pin.fill")
                    .font(.system(size: 6.5, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 12, height: 12)
        .background(Circle().fill(CopypastikTheme.accent))
        .overlay(
            Circle().strokeBorder(Color(nsColor: .windowBackgroundColor).opacity(0.85), lineWidth: 1)
        )
        .offset(x: 2, y: 2)
    }

    private var sourceAppIcon: NSImage? {
        SourceAppIconProvider.icon(forBundleID: item.sourceAppBundleID)
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
            selectedRowBackground
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
                            Color.white.opacity(colorScheme == .dark ? 0.10 : 0.28),
                            Color.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.26),
                            CopypastikTheme.accentGlow.opacity(colorScheme == .dark ? 0.18 : 0.16)
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
                            Color.white.opacity(colorScheme == .dark ? 0.34 : 0.60),
                            Color.accentColor.opacity(0.76),
                            Color.accentColor.opacity(0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: rowGlowColor, radius: 12, x: 0, y: 1)
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
        isSelected ? CopypastikTheme.accentGlow.opacity(colorScheme == .dark ? 0.30 : 0.26) : .clear
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

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard NSApp.currentEvent?.type == .rightMouseDown else { return nil }
            return super.hitTest(point)
        }

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

import AppKit
import SwiftUI

enum LibraryFormat {
    static func timestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    static func byteCount(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    static func clipCount(_ count: Int) -> String {
        "\(count) \(count == 1 ? "clip" : "clips")"
    }
}

// MARK: - Root

struct LibraryView: View {
    @ObservedObject var state: LibraryState
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            LibrarySidebar(state: state)
                .navigationSplitViewColumnWidth(min: 180, ideal: 205, max: 280)
        } content: {
            LibraryListColumn(state: state, store: store, settings: settings)
                .navigationSplitViewColumnWidth(min: 340, ideal: 430, max: 640)
        } detail: {
            LibraryDetailColumn(state: state, store: store, settings: settings)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 860, minHeight: 480)
        .alert("Add Tag", isPresented: $state.isAddingTag) {
            TextField("Tag name", text: $state.newTagText)
            Button("Add") { state.commitNewTag() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Adds the tag to \(LibraryFormat.clipCount(state.selection.count)). Tags are lowercase, up to \(TagRules.maxTagLength) characters, and a clip can have \(TagRules.maxTags).")
        }
        .alert(
            deleteTitle,
            isPresented: Binding(
                get: { state.pendingDelete != nil },
                set: { isPresented in
                    if !isPresented { state.cancelDelete() }
                }
            ),
            presenting: state.pendingDelete
        ) { pending in
            if pending.unpinnedCount > 0 {
                Button(
                    pending.pinnedCount > 0 ? "Delete \(pending.unpinnedCount) Unpinned" : "Delete",
                    role: .destructive
                ) {
                    state.confirmDelete(includingPinned: false)
                }
            }
            if pending.pinnedCount > 0 {
                Button("Delete Everywhere", role: .destructive) {
                    state.confirmDelete(includingPinned: true)
                }
            }
            Button("Cancel", role: .cancel) { state.cancelDelete() }
        } message: { pending in
            Text(deleteMessage(for: pending))
        }
    }

    private var deleteTitle: String {
        guard let pending = state.pendingDelete else { return "Delete Clips?" }
        if pending.pinnedCount > 0, pending.unpinnedCount == 0 {
            return pending.items.count == 1 ? "Delete Pinned Clip?" : "Delete Pinned Clips?"
        }
        return "Delete \(LibraryFormat.clipCount(pending.items.count))?"
    }

    private func deleteMessage(for pending: LibraryPendingDelete) -> String {
        if pending.pinnedCount == 0 {
            return "This removes \(LibraryFormat.clipCount(pending.items.count)) from Copypastik. This can't be undone."
        }
        if pending.unpinnedCount == 0 {
            return "Pinned clips are kept by default. Delete Everywhere also removes \(LibraryFormat.clipCount(pending.pinnedCount)) and their Quick Slots. This can't be undone."
        }
        return "\(pending.pinnedCount) of the selected clips are pinned. Delete removes only the \(pending.unpinnedCount) unpinned and keeps the pinned ones. Delete Everywhere removes all \(pending.items.count), including Quick Slots. This can't be undone."
    }
}

// MARK: - Sidebar

private struct LibrarySidebar: View {
    @ObservedObject var state: LibraryState

    var body: some View {
        List(selection: scopeBinding) {
            Section("Library") {
                sidebarRow("All Clips", symbol: "tray.full", count: state.allClips.count)
                    .tag(LibraryScope.all)
                sidebarRow("Pinned", symbol: "pin", count: state.pinnedCount)
                    .tag(LibraryScope.pinned)
            }

            if !state.appEntries.isEmpty {
                Section("Apps") {
                    ForEach(state.appEntries) { entry in
                        appRow(entry)
                            .tag(LibraryScope.app(entry.key))
                    }
                }
            }

            Section("Types") {
                ForEach(PickerTypeFilter.allCases.filter { $0 != .all }) { filter in
                    sidebarRow(filter.displayName, symbol: filter.symbolName, count: state.typeCounts[filter] ?? 0)
                        .tag(LibraryScope.type(filter))
                }
            }

            if !state.tagEntries.isEmpty {
                Section("Tags") {
                    ForEach(state.tagEntries) { entry in
                        tagRow(entry)
                            .tag(LibraryScope.tag(entry.tag))
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .accessibilityLabel("Library sidebar")
    }

    private var scopeBinding: Binding<LibraryScope?> {
        Binding(
            get: { state.scope },
            set: { newValue in
                if let newValue { state.scope = newValue }
            }
        )
    }

    private func sidebarRow(_ title: String, symbol: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Label(title, systemImage: symbol)
            Spacer(minLength: 4)
            countBadge(count)
        }
    }

    private func appRow(_ entry: LibraryAppEntry) -> some View {
        HStack(spacing: 8) {
            Group {
                if let icon = SourceAppIconProvider.icon(forBundleID: entry.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "app")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 16, height: 16)

            Text(entry.name)
                .lineLimit(1)
            Spacer(minLength: 4)
            countBadge(entry.count)
        }
    }

    private func tagRow(_ entry: LibraryTagEntry) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "number")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.settings.tagColor(for: entry.tag).base)
                .frame(width: 16)
            Text(entry.tag)
                .lineLimit(1)
            Spacer(minLength: 4)
            countBadge(entry.count)
        }
    }

    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }
}

// MARK: - List column

private struct LibraryListColumn: View {
    @ObservedObject var state: LibraryState
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider()

            content

            if !state.selection.isEmpty {
                Divider()
                LibraryBulkBar(state: state)
            }

            statusLine
        }
        .onChange(of: state.searchFocusTrigger) {
            isSearchFocused = true
        }
        .onAppear {
            isSearchFocused = true
        }
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TextField("Search clips", text: $state.query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                    .accessibilityLabel("Search clips")
                    .help("Plain text, #tag, @app, type:image, type:link, type:code, type:command, type:text")

                if !state.query.isEmpty {
                    Button {
                        state.query = ""
                        isSearchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )

            HStack(spacing: 4) {
                Text(state.scopeTitle)
                    .font(.system(size: 11, weight: .semibold))
                Text("· \(LibraryFormat.clipCount(state.visibleItems.count))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.scope != .all {
                    Button("Show All") { state.scope = .all }
                        .buttonStyle(.link)
                        .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(10)
    }

    @ViewBuilder
    private var content: some View {
        if state.sections.isEmpty {
            emptyState
        } else {
            ScrollViewReader { proxy in
                List(selection: $state.selection) {
                    ForEach(state.sections) { section in
                        Section {
                            ForEach(section.items) { item in
                                LibraryRow(
                                    item: item,
                                    isRecognizing: store.isRecognizingText(in: item),
                                    isSelected: state.selection.contains(item.dedupKey),
                                    tagColor: { settings.tagColor(for: $0) }
                                )
                            }
                        } header: {
                            Text(section.group.title)
                                .font(.system(size: 11, weight: .semibold))
                                .textCase(.uppercase)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .listStyle(.inset)
                .contextMenu(forSelectionType: String.self) { keys in
                    LibraryContextMenu(state: state, keys: keys)
                } primaryAction: { _ in
                    state.activateSelection()
                }
                .onChange(of: state.cursorKey) {
                    if let key = state.cursorKey {
                        proxy.scrollTo(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if state.allClips.isEmpty {
            ContentUnavailableView(
                "Your Library is empty",
                systemImage: "tray",
                description: Text("Copy text or images anywhere and they'll show up here.")
            )
        } else {
            ContentUnavailableView(
                "No matching clips",
                systemImage: "magnifyingglass",
                description: Text("Try fewer filters. Search supports #tag, @app and type:image / link / code / command / text, and combines with the sidebar selection.")
            )
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        if let status = state.status {
            HStack(spacing: 6) {
                Image(systemName: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(status.isError ? Color.orange : CopypastikTheme.success)
                Text(status.text)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .transition(.opacity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(status.text)
        }
    }
}

// MARK: - Row

private struct LibraryRow: View {
    let item: ClipboardHistoryItem
    let isRecognizing: Bool
    let isSelected: Bool
    let tagColor: (String) -> TagColor

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            leading

            VStack(alignment: .leading, spacing: 3) {
                preview
                metadata
                if !item.tags.isEmpty {
                    tagChips
                }
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag {
            LibraryDragProvider.itemProvider(for: item)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: Leading icon / thumbnail

    @ViewBuilder
    private var leading: some View {
        if let image = item.imageValue {
            LibraryThumbnailView(image: image, maxPixel: 160)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.75)
                )
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(0.055))

                if let icon = SourceAppIconProvider.icon(forBundleID: item.sourceAppBundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: item.kind.symbolName)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .overlay(alignment: .bottomTrailing) {
                // The kind badge keeps links/code recognizable when the
                // leading icon is the source app.
                if SourceAppIconProvider.icon(forBundleID: item.sourceAppBundleID) != nil {
                    Image(systemName: item.kind.symbolName)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color.secondary.opacity(0.85)))
                        .offset(x: 3, y: 3)
                }
            }
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var preview: some View {
        if let text = item.textValue {
            textPreview(text)
        } else if let image = item.imageValue {
            imagePreview(image)
        }
    }

    @ViewBuilder
    private func textPreview(_ text: String) -> some View {
        let snippet = String(text.prefix(400)).trimmingCharacters(in: .whitespacesAndNewlines)
        if item.kind == .link, let url = ClipTransform.webURL(from: text) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ClipTransform.domain(fromHost: url.host ?? snippet))
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(snippet)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text(snippet)
                .font(item.kind.usesMonospacedPreview ? .system(size: 12, design: .monospaced) : .system(size: 13))
                .lineLimit(item.kind == .multiline || item.kind.usesMonospacedPreview ? 3 : 2)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private func imagePreview(_ image: ClipboardImage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "Image · \(image.width)×\(image.height)")
                .font(.system(size: 13, weight: .medium))

            if isRecognizing {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Recognizing text…")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            } else if let recognized = item.recognizedText {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 10))
                    Text(recognized.replacingOccurrences(of: "\n", with: " "))
                        .lineLimit(2)
                }
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
        }
    }

    private var metadata: some View {
        HStack(spacing: 4) {
            if let sourceAppName = item.sourceAppName {
                Text(sourceAppName)
                Text("·")
            }
            Text(LibraryFormat.timestamp(item.createdAt))
            Text("·")
            Text(item.kind.displayName)
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var tagChips: some View {
        HStack(spacing: 4) {
            ForEach(item.tags, id: \.self) { tag in
                let color = tagColor(tag)
                Text("#\(tag)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color.foreground)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(color.base.opacity(0.22)))
            }
        }
    }

    // MARK: Trailing badges

    private var trailing: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if item.isPinned {
                HStack(spacing: 3) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                    if let slot = item.pinnedSlot {
                        Text("⌃⌥\(slot)")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .foregroundStyle(CopypastikTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(CopypastikTheme.accent.opacity(0.14)))
                .accessibilityHidden(true)
            }

            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .opacity(isHovered || isSelected ? 0.7 : 0)
                .help("Drag this clip into another app")
                .accessibilityHidden(true)
        }
    }

    private var accessibilityDescription: String {
        var parts = [item.kind.displayName]
        if let text = item.textValue {
            parts.append(String(text.prefix(120)))
        } else if let image = item.imageValue {
            parts.append("\(image.width) by \(image.height)")
            if let recognized = item.recognizedText { parts.append("contains text: \(recognized.prefix(80))") }
        }
        if let app = item.sourceAppName { parts.append("from \(app)") }
        parts.append(LibraryFormat.timestamp(item.createdAt))
        if item.isPinned {
            parts.append(item.pinnedSlot.map { "pinned, Quick Slot \($0)" } ?? "pinned")
        }
        if !item.tags.isEmpty { parts.append("tags \(item.tags.joined(separator: ", "))") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Context menu

private struct LibraryContextMenu: View {
    @ObservedObject var state: LibraryState
    let keys: Set<String>

    private var items: [ClipboardHistoryItem] {
        state.visibleItems.filter { keys.contains($0.dedupKey) }
    }

    var body: some View {
        if !items.isEmpty {
            let single = items.count == 1 ? items[0] : nil

            Button(items.count > 1 ? "Copy Selected" : "Copy") {
                act { state.activateSelection() }
            }

            if let single, single.recognizedText != nil {
                Button("Copy Recognized Text") {
                    act { state.copyRecognizedText(of: single) }
                }
            }

            if let single, let text = single.textValue {
                Menu("Transform") {
                    LibraryTransformMenuItems(state: state, item: single, text: text)
                }
            }

            Divider()

            Button(items.allSatisfy(\.isPinned) ? "Unpin" : "Pin") {
                act { state.togglePinSelection() }
            }

            Button("Add Tag…") {
                act { state.beginAddTag() }
            }

            Divider()

            Button("Delete…", role: .destructive) {
                act { state.requestDeleteSelection() }
            }
        }
    }

    /// Right-clicking an unselected row targets that row; right-clicking
    /// inside the selection targets the whole selection.
    private func act(_ action: () -> Void) {
        if state.selection != keys {
            state.selection = keys
        }
        action()
    }
}

struct LibraryTransformMenuItems: View {
    @ObservedObject var state: LibraryState
    let item: ClipboardHistoryItem
    let text: String

    var body: some View {
        ForEach(ClipTransform.allCases) { transform in
            Button {
                state.applyTransform(transform, to: item)
            } label: {
                Label(transform.title, systemImage: transform.symbolName)
            }
            .disabled(!transform.isAvailable(for: text))
        }
    }
}

// MARK: - Bulk action bar

private struct LibraryBulkBar: View {
    @ObservedObject var state: LibraryState

    private var items: [ClipboardHistoryItem] { state.selectedItems }
    private var allPinned: Bool { !items.isEmpty && items.allSatisfy(\.isPinned) }
    private var textCount: Int { items.filter { $0.textValue != nil }.count }
    private var canCopy: Bool { items.count == 1 || textCount > 0 }

    var body: some View {
        HStack(spacing: 6) {
            Text(items.count == 1 ? "1 selected" : "\(items.count) selected")
                .font(.system(size: 11.5, weight: .semibold))
                .monospacedDigit()

            Spacer(minLength: 8)

            Button {
                state.activateSelection()
            } label: {
                Label(items.count > 1 ? "Copy Selected" : "Copy", systemImage: "doc.on.doc")
            }
            .disabled(!canCopy)
            .help(copyHelp)

            Button {
                state.togglePinSelection()
            } label: {
                Label(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin")
            }
            .help(allPinned ? "Unpin the selected clips" : "Pin the selected clips")

            Menu {
                Button("New Tag…") { state.beginAddTag() }

                if !state.allTags.isEmpty {
                    Menu("Add Tag") {
                        ForEach(state.allTags, id: \.self) { tag in
                            Button("#\(tag)") { state.addTagToSelection(tag) }
                        }
                    }
                }

                if !state.tagsInSelection.isEmpty {
                    Menu("Remove Tag") {
                        ForEach(state.tagsInSelection, id: \.self) { tag in
                            Button("#\(tag)") { state.removeTagFromSelection(tag) }
                        }
                    }
                }
            } label: {
                Label("Tag", systemImage: "tag")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add or remove a tag on the selected clips")

            Button(role: .destructive) {
                state.requestDeleteSelection()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .help("Delete the selected clips")

            Button {
                state.clearSelection()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Clear selection")
            .accessibilityLabel("Clear selection")
        }
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private var copyHelp: String {
        if items.count <= 1 { return "Copy the clip" }
        if textCount == 0 { return "Select at least one text clip. Images can't be joined." }
        let skipped = items.count - textCount
        let base = "Joins the text of \(textCount) text clips with newlines"
        return skipped > 0 ? "\(base); \(skipped) image\(skipped == 1 ? "" : "s") will be skipped." : base + "."
    }
}

// MARK: - Detail column

private struct LibraryDetailColumn: View {
    @ObservedObject var state: LibraryState
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings

    var body: some View {
        Group {
            if let item = state.singleSelectedItem {
                LibraryItemDetail(state: state, store: store, settings: settings, item: item)
            } else if state.selection.count > 1 {
                multiSelectionSummary
            } else {
                ContentUnavailableView(
                    "No clip selected",
                    systemImage: "doc.on.clipboard",
                    description: Text("Select a clip to preview it, or press ↩ to copy.")
                )
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
    }

    private var multiSelectionSummary: some View {
        let items = state.selectedItems
        let textCount = items.filter { $0.textValue != nil }.count
        let imageCount = items.count - textCount
        let pinned = items.filter(\.isPinned).count

        return VStack(spacing: 10) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(LibraryFormat.clipCount(items.count) + " selected")
                .font(.system(size: 16, weight: .semibold))
            VStack(spacing: 3) {
                Text("\(textCount) text · \(imageCount) image\(imageCount == 1 ? "" : "s") · \(pinned) pinned")
                Text("Use the bar below the list to copy, pin, tag or delete them.")
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LibraryItemDetail: View {
    @ObservedObject var state: LibraryState
    @ObservedObject var store: ClipboardStore
    @ObservedObject var settings: AppSettings
    let item: ClipboardHistoryItem

    private static let displayedCharacterLimit = 20_000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                previewCard

                actionRow

                metadataGrid

                if item.imageValue != nil {
                    recognizedTextSection
                }
            }
            .padding(16)
        }
    }

    // MARK: Preview

    @ViewBuilder
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let text = item.textValue {
                    textPreview(text)
                } else if let image = item.imageValue {
                    LibraryThumbnailView(image: image, maxPixel: 1600, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .frame(height: 260)
                }
            }
            .onDrag {
                LibraryDragProvider.itemProvider(for: item)
            }

            Label("Drag the preview into another app to paste it there", systemImage: "arrow.up.forward.app")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        }
    }

    private func textPreview(_ text: String) -> some View {
        let shown = text.count > Self.displayedCharacterLimit ? String(text.prefix(Self.displayedCharacterLimit)) : text

        return VStack(alignment: .leading, spacing: 6) {
            if item.kind == .link, let url = ClipTransform.webURL(from: text) {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    Text(ClipTransform.domain(fromHost: url.host ?? ""))
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Link("Open in Browser", destination: url)
                        .font(.system(size: 12))
                }
            }

            Text(shown)
                .font(item.kind.usesMonospacedPreview ? .system(size: 12.5, design: .monospaced) : .system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if text.count > Self.displayedCharacterLimit {
                Text("Showing the first \(Self.displayedCharacterLimit.formatted()) characters. Copying uses the full text.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: 300, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: 8) {
            Button {
                state.copy(item)
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .help("Copy to the clipboard (↩)")

            Button {
                state.togglePinSelection()
            } label: {
                Label(item.isPinned ? "Unpin" : "Pin", systemImage: item.isPinned ? "pin.slash" : "pin")
            }

            Menu {
                Button("None") { state.assignSlot(nil, to: item) }
                Divider()
                ForEach(1...9, id: \.self) { slot in
                    Button {
                        state.assignSlot(slot, to: item)
                    } label: {
                        if item.pinnedSlot == slot {
                            Label("Slot \(slot)  ⌃⌥\(slot)", systemImage: "checkmark")
                        } else {
                            Text("Slot \(slot)  ⌃⌥\(slot)")
                        }
                    }
                }
            } label: {
                Label(item.pinnedSlot.map { "Slot \($0)" } ?? "Quick Slot", systemImage: "number.square")
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(!item.isPinned)
            .help(item.isPinned ? "Assign a Quick Slot for the ⌃⌥1–9 shortcuts" : "Pin the clip to give it a Quick Slot")

            if let text = item.textValue {
                Menu {
                    LibraryTransformMenuItems(state: state, item: item, text: text)
                } label: {
                    Label("Transform", systemImage: "wand.and.stars")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Copies a transformed version. The original clip stays unchanged.")
            }

            Spacer(minLength: 0)
        }
        .controlSize(.regular)
    }

    // MARK: Metadata

    private var metadataGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            metadataRow("Type", item.kind.displayName)
            if let app = item.sourceAppName {
                metadataRow("Source", app)
            }
            metadataRow("Captured", item.createdAt.formatted(date: .abbreviated, time: .shortened))

            if let text = item.textValue {
                let presentation = ClipboardItemPresentation(text: text)
                metadataRow("Size", "\(presentation.characterCount.formatted()) characters · \(presentation.lineCount) \(presentation.lineCount == 1 ? "line" : "lines")")
            } else if let image = item.imageValue {
                metadataRow("Size", "\(image.width)×\(image.height) · \(image.formatLabel) · \(LibraryFormat.byteCount(image.data.count))")
            }

            if let slot = item.pinnedSlot {
                metadataRow("Quick Slot", "\(slot)  (⌃⌥\(slot))")
            } else if item.isPinned {
                metadataRow("Pinned", "No Quick Slot assigned")
            }

            if !item.tags.isEmpty {
                GridRow {
                    Text("Tags")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .gridColumnAlignment(.trailing)
                    HStack(spacing: 4) {
                        ForEach(item.tags, id: \.self) { tag in
                            let color = settings.tagColor(for: tag)
                            Text("#\(tag)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(color.foreground)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(color.base.opacity(0.22)))
                        }
                    }
                }
            }
        }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .font(.system(size: 12))
                .textSelection(.enabled)
        }
    }

    // MARK: OCR

    private var recognizedTextSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Recognized Text", systemImage: "text.viewfinder")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if item.recognizedText != nil {
                    Button("Copy Recognized Text") {
                        state.copyRecognizedText(of: item)
                    }
                    .controlSize(.small)
                }
            }

            Group {
                if store.isRecognizingText(in: item) {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Recognizing text…")
                    }
                    .foregroundStyle(.secondary)
                } else if let recognized = item.recognizedText {
                    Text(recognized)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if item.ocrText != nil {
                    Text("No text found in this image.")
                        .foregroundStyle(.secondary)
                } else if !settings.isImageTextRecognitionEnabled {
                    Text("Image text recognition is turned off in Settings. It runs on this Mac only.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Text hasn't been recognized for this image.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.system(size: 12.5))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
        }
    }
}

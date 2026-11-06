import AppKit
import Combine
import Foundation

final class ClipboardStore: ObservableObject {
    static let historyLimit = AppSettings.defaultHistoryLimit
    static let taggedLimit = 50
    /// Upper bound for image bytes kept in history (memory and disk). Older
    /// image clips beyond it are dropped; text clips are never affected.
    static let historyImageByteBudget = 96 * 1024 * 1024

    /// Recognizes text in encoded image data. Returns `nil` on failure and an
    /// empty string when the image contains no text.
    typealias TextRecognition = @Sendable (Data) async -> String?

    @Published private(set) var items: [ClipboardHistoryItem] = [] {
        didSet { scheduleHistorySave() }
    }
    @Published private(set) var taggedItems: [ClipboardHistoryItem] = []
    @Published private(set) var pinnedItems: [ClipboardHistoryItem] = []
    /// Fingerprints of image clips whose text is still being recognized.
    @Published private(set) var recognizingFingerprints: Set<String> = []

    private let settings: AppSettings
    private let service = PasteboardService()
    private let taggedStore: TaggedStore
    private let pinnedStore: PinnedStore
    private let historyStore: HistoryStore?
    private let textRecognizer: TextRecognition?
    private let sourceAppTracker = SourceAppTracker()
    private var cancellables = Set<AnyCancellable>()

    private var historySaveWorkItem: DispatchWorkItem?
    private var isApplyingSavedHistory = false

    private var ocrQueue: [(fingerprint: String, data: Data)] = []
    private var isOCRRunning = false
    private var runningOCRFingerprint: String?
    private var failedOCRFingerprints = Set<String>()

    /// - Parameters:
    ///   - historyStore: Persists untagged history for the Library. `nil`
    ///     (the default) keeps history memory-only, which keeps tests and
    ///     previews from touching real user data.
    ///   - textRecognizer: On-device OCR for image clips. `nil` disables OCR
    ///     for this store; the app passes `TextRecognizer.recognizeText`.
    init(
        settings: AppSettings? = nil,
        startsService: Bool = true,
        taggedStore: TaggedStore = TaggedStore(),
        pinnedStore: PinnedStore = PinnedStore(),
        historyStore: HistoryStore? = nil,
        textRecognizer: TextRecognition? = nil
    ) {
        self.settings = settings ?? AppSettings(managesLaunchAtLogin: false)
        self.taggedStore = taggedStore
        self.pinnedStore = pinnedStore
        self.historyStore = historyStore
        self.textRecognizer = textRecognizer
        taggedItems = taggedStore.load()
        pinnedItems = pinnedStore.load()
        if let historyStore, self.settings.isHistoryPersistenceEnabled {
            let ignoredApps = self.settings.ignoredAppBundleIDs
            let loaded = historyStore.load(limit: self.settings.historyLimit.rawValue)
                .filter { !($0.sourceAppBundleID.map(ignoredApps.contains) ?? false) }
            // Restoring what is already on disk must not schedule a rewrite.
            isApplyingSavedHistory = true
            items = Self.applyingImageBudget(to: loaded)
            isApplyingSavedHistory = false
        }
        service.onNewItem = { [weak self] item in
            DispatchQueue.main.async { self?.ingestCopiedItem(item) }
        }
        self.settings.$historyLimit
            .dropFirst()
            .sink { [weak self] limit in
                self?.trimHistory(to: limit.rawValue)
            }
            .store(in: &cancellables)

        self.settings.$isHistoryPersistenceEnabled
            .dropFirst()
            .sink { [weak self] isEnabled in
                self?.historyPersistenceChanged(isEnabled: isEnabled)
            }
            .store(in: &cancellables)

        self.settings.$ignoredAppBundleIDs
            .dropFirst()
            .sink { [weak self] ignoredApps in
                self?.purgeHistory(fromApps: ignoredApps)
            }
            .store(in: &cancellables)

        self.settings.$isImageTextRecognitionEnabled
            .dropFirst()
            .sink { [weak self] isEnabled in
                guard let self else { return }
                if isEnabled {
                    // `$` publishers fire before the property changes; wait one
                    // turn so the enqueue guards see the new value.
                    DispatchQueue.main.async { [weak self] in
                        self?.recognizeTextInUnprocessedImages()
                    }
                } else {
                    self.ocrQueue.removeAll()
                    self.recognizingFingerprints = self.runningOCRFingerprint.map { [$0] } ?? []
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in
                self?.flushPendingHistorySave()
            }
            .store(in: &cancellables)

        if startsService {
            service.start()
        }

        recognizeTextInUnprocessedImages()
    }

    func copyAsPlainText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        print("[Copypastik] selected item written to NSPasteboard as plain text")
        // Suppress PasteboardService from re-detecting this write as a new item
        service.suppressChange(atCount: NSPasteboard.general.changeCount)
    }

    func copyItem(_ item: ClipboardHistoryItem) {
        switch item.content {
        case .text(let text):
            copyAsPlainText(text)
        case .image(let image):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setData(image.data, forType: image.pasteboardType)
            print("[Copypastik] selected image written to NSPasteboard")
            service.suppressChange(atCount: NSPasteboard.general.changeCount)
        }

        markTaggedItemUsedIfNeeded(item)
    }

    func clearHistory() {
        items = []
        // Wipe disk right away rather than waiting for the debounce.
        flushPendingHistorySave()
    }

    func clearTaggedItems() {
        taggedItems = []
        taggedStore.clear()
    }

    func clearPinnedItems() {
        pinnedItems = []
        pinnedStore.clear()
    }

    func deleteItem(_ item: ClipboardHistoryItem) {
        if pinnedItems.contains(where: { $0.dedupKey == item.dedupKey }) {
            pinnedItems = pinnedItems.filter { $0.dedupKey != item.dedupKey }
            savePinnedItems()
            // Trash is destructive: also purge the hidden history copy so the
            // "deleted" clip does not pop back into the History section.
            items = Self.historyItems(afterDeleting: item, from: items)
        } else if taggedItems.contains(where: { $0.dedupKey == item.dedupKey }) {
            taggedItems = taggedItems.filter { $0.dedupKey != item.dedupKey }
            saveTaggedItems()
        } else {
            items = Self.historyItems(afterDeleting: item, from: items)
        }
    }

    func isPinned(_ item: ClipboardHistoryItem) -> Bool {
        pinnedItems.contains { $0.dedupKey == item.dedupKey }
    }

    /// Pins or unpins `item`. Pinning auto-assigns the lowest free Quick Slot
    /// (1-9) so the global shortcut works immediately; the 10th+ pin gets no
    /// slot. Unpinning frees the slot and, if the clip no longer exists in
    /// history or tagged snippets, reinserts it into history so it is not
    /// silently lost. Returns the new pinned state.
    @discardableResult
    func togglePin(_ item: ClipboardHistoryItem) -> Bool {
        if let index = pinnedItems.firstIndex(where: { $0.dedupKey == item.dedupKey }) {
            let unpinned = pinnedItems[index].withPinned(false)
            pinnedItems.remove(at: index)
            savePinnedItems()

            let existsElsewhere = items.contains { $0.dedupKey == unpinned.dedupKey }
                || taggedItems.contains { $0.dedupKey == unpinned.dedupKey }
            if !existsElsewhere {
                items = Self.historyItems(afterAdding: unpinned, to: items, maxItems: settings.historyLimit.rawValue)
            }
            return false
        }

        let pinnedItem = item.withPinned(true, slot: lowestFreeSlot()).withUpdatedAt()
        pinnedItems.append(pinnedItem)
        savePinnedItems()
        return true
    }

    func pinnedSlot(for item: ClipboardHistoryItem) -> Int? {
        pinnedItems.first { $0.dedupKey == item.dedupKey }?.pinnedSlot
    }

    private func lowestFreeSlot() -> Int? {
        let usedSlots = Set(pinnedItems.compactMap(\.pinnedSlot))
        return (1...9).first { !usedSlots.contains($0) }
    }

    func assignPinnedSlot(_ slot: Int?, to item: ClipboardHistoryItem) {
        guard let index = pinnedItems.firstIndex(where: { $0.dedupKey == item.dedupKey }) else { return }

        if let slot {
            for otherIndex in pinnedItems.indices where otherIndex != index && pinnedItems[otherIndex].pinnedSlot == slot {
                pinnedItems[otherIndex] = pinnedItems[otherIndex].withPinnedSlot(nil)
            }
        }

        pinnedItems[index] = pinnedItems[index].withPinnedSlot(slot)
        savePinnedItems()
    }

    func pinnedItem(forSlot slot: Int) -> ClipboardHistoryItem? {
        pinnedItems.first { $0.pinnedSlot == slot }
    }

    func ingestCopiedText(_ text: String) {
        ingestCopiedItem(.text(text))
    }

    func ingestCopiedItem(_ item: ClipboardHistoryItem) {
        guard settings.isClipboardHistoryEnabled else {
            print("[Copypastik] clipboard history disabled, item ignored")
            return
        }

        guard !settings.isCapturePaused else {
            print("[Copypastik] capture paused, item ignored")
            return
        }

        let sourceAppName = item.sourceAppName ?? sourceAppTracker.lastKnownForegroundApp?.name
        let sourceAppBundleID = item.sourceAppBundleID ?? sourceAppTracker.lastKnownForegroundApp?.bundleID

        guard !settings.isAppIgnored(bundleID: sourceAppBundleID) else {
            print("[Copypastik] source app is ignored, item discarded")
            return
        }

        guard var normalizedItem = Self.normalizedItem(item) else {
            print("[Copypastik] duplicate/empty item ignored")
            return
        }

        if normalizedItem.sourceAppName == nil {
            normalizedItem = normalizedItem.withSourceApp(name: sourceAppName, bundleID: sourceAppBundleID)
        }

        if normalizedItem.ocrText == nil {
            normalizedItem.ocrText = knownOCRText(forKey: normalizedItem.dedupKey)
        }

        if pinnedItems.contains(where: { $0.dedupKey == normalizedItem.dedupKey }) {
            print("[Copypastik] pinned clip reused, not re-added to history")
            return
        }

        if let taggedIndex = taggedItems.firstIndex(where: { $0.dedupKey == normalizedItem.dedupKey }) {
            taggedItems[taggedIndex] = taggedItems[taggedIndex].withUpdatedAt()
            saveTaggedItems()
            print("[Copypastik] tagged snippet reused")
            return
        }

        let updatedItems = Self.historyItems(afterAdding: normalizedItem, to: items, maxItems: settings.historyLimit.rawValue)
        guard updatedItems != items else {
            print("[Copypastik] duplicate/empty item ignored")
            return
        }
        items = updatedItems
        print("[Copypastik] clipboard history updated")
        enqueueTextRecognition(for: normalizedItem)
    }

    enum TagEditResult: Equatable {
        case saved
        case removed
        case taggedLimitReached
    }

    @discardableResult
    func setTags(for item: ClipboardHistoryItem, rawTags: String) -> TagEditResult {
        let normalizedTags = TagRules.normalize(rawTags)
        guard !normalizedTags.isEmpty else {
            removeAllTags(from: item)
            return .removed
        }

        let now = Date()
        let existingTaggedIndex = taggedItems.firstIndex { $0.dedupKey == item.dedupKey }
        let isNewTaggedItem = existingTaggedIndex == nil
        guard !isNewTaggedItem || taggedItems.count < Self.taggedLimit else {
            return .taggedLimitReached
        }

        if let existingTaggedIndex {
            let existing = taggedItems[existingTaggedIndex]
            let tags = item.isTagged ? normalizedTags : TagRules.normalize(existing.tags + normalizedTags)
            taggedItems[existingTaggedIndex] = existing.withTags(tags, updatedAt: now)
        } else if let normalizedItem = Self.normalizedItem(item) {
            let taggedItem = normalizedItem.withTags(normalizedTags, updatedAt: now)
            taggedItems.insert(taggedItem, at: 0)
        }

        items = Self.historyItems(afterDeleting: item, from: items)
        saveTaggedItems()
        if let savedTags = taggedItems.first(where: { $0.dedupKey == item.dedupKey })?.tags {
            syncPinnedTags(savedTags, forKey: item.dedupKey)
        }
        return .saved
    }

    func removeAllTags(from item: ClipboardHistoryItem, reinsertInHistory: Bool = true) {
        guard let taggedIndex = taggedItems.firstIndex(where: { $0.dedupKey == item.dedupKey }) else { return }
        let untaggedItem = taggedItems[taggedIndex].withTags([], updatedAt: Date())
        taggedItems.remove(at: taggedIndex)
        saveTaggedItems()
        syncPinnedTags([], forKey: untaggedItem.dedupKey)

        if reinsertInHistory {
            items = Self.historyItems(
                afterAdding: untaggedItem,
                to: items,
                maxItems: settings.historyLimit.rawValue
            )
        }
    }

    func tagsText(for item: ClipboardHistoryItem) -> String {
        if let taggedItem = taggedItems.first(where: { $0.dedupKey == item.dedupKey }) {
            return taggedItem.tags.joined(separator: ", ")
        }
        return item.tags.joined(separator: ", ")
    }

    var allTags: [String] {
        Array(Set(taggedItems.flatMap(\.tags))).sorted()
    }

    func taggedItems(for tag: String) -> [ClipboardHistoryItem] {
        let normalizedTag = TagRules.normalizeTag(tag) ?? tag.lowercased()
        return taggedItems
            .filter { $0.tags.contains(normalizedTag) }
            .sortedByTaggedRecency()
    }

    static func historyItems(
        afterAdding item: ClipboardHistoryItem,
        to existingItems: [ClipboardHistoryItem],
        maxItems: Int = historyLimit,
        imageByteBudget: Int = historyImageByteBudget
    ) -> [ClipboardHistoryItem] {
        guard !item.dedupKey.isEmpty else { return existingItems }

        var untaggedItem = item
        untaggedItem.tags = []
        untaggedItem.imageStorageID = nil

        var updatedItems = existingItems.filter { $0.dedupKey != item.dedupKey && !$0.isTagged }
        updatedItems.insert(untaggedItem.withUpdatedAt(), at: 0)

        if updatedItems.count > maxItems {
            updatedItems = Array(updatedItems.prefix(maxItems))
        }

        return applyingImageBudget(to: updatedItems, budget: imageByteBudget)
    }

    /// Drops the oldest image clips once their combined size passes `budget`.
    /// The newest image is always kept, and text clips are never removed.
    static func applyingImageBudget(
        to historyItems: [ClipboardHistoryItem],
        budget: Int = historyImageByteBudget
    ) -> [ClipboardHistoryItem] {
        var imageBytes = 0
        return historyItems.filter { item in
            guard let image = item.imageValue else { return true }
            let size = image.data.count
            if imageBytes > 0, imageBytes + size > budget { return false }
            imageBytes += size
            return true
        }
    }

    static func historyItems(
        afterDeleting item: ClipboardHistoryItem,
        from existingItems: [ClipboardHistoryItem]
    ) -> [ClipboardHistoryItem] {
        existingItems.filter { $0.dedupKey != item.dedupKey }
    }

    private static func normalizedItem(_ item: ClipboardHistoryItem) -> ClipboardHistoryItem? {
        switch item.content {
        case .text(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            var copy = item
            copy.content = .text(trimmed)
            copy.tags = TagRules.normalize(item.tags)
            return copy
        case .image:
            return item
        }
    }

    private func trimHistory(to maxItems: Int) {
        guard items.count > maxItems else { return }
        items = Array(items.prefix(maxItems))
    }

    private func markTaggedItemUsedIfNeeded(_ item: ClipboardHistoryItem) {
        guard let taggedIndex = taggedItems.firstIndex(where: { $0.dedupKey == item.dedupKey }) else { return }
        taggedItems[taggedIndex] = taggedItems[taggedIndex].withUpdatedAt()
        saveTaggedItems()
    }

    private func saveTaggedItems() {
        taggedItems = taggedStore.save(taggedItems).sortedByTaggedRecency()
    }

    private func savePinnedItems() {
        pinnedItems = pinnedStore.save(pinnedItems).sortedByPinnedOrder()
    }

    private func syncPinnedTags(_ tags: [String], forKey key: String) {
        guard let index = pinnedItems.firstIndex(where: { $0.dedupKey == key }),
              pinnedItems[index].tags != tags else {
            return
        }
        pinnedItems[index].tags = tags
        savePinnedItems()
    }

    // MARK: - History persistence

    private func scheduleHistorySave() {
        guard historyStore != nil, settings.isHistoryPersistenceEnabled, !isApplyingSavedHistory else { return }

        historySaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.persistHistoryNow()
        }
        historySaveWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Writes any debounced history change immediately (used on quit and clear).
    func flushPendingHistorySave() {
        guard let work = historySaveWorkItem else { return }
        work.cancel()
        persistHistoryNow()
    }

    private func persistHistoryNow() {
        historySaveWorkItem = nil
        guard let historyStore, settings.isHistoryPersistenceEnabled else { return }

        let saved = historyStore.save(items)
        guard saved != items || zip(saved, items).contains(where: { $0.imageStorageID != $1.imageStorageID }) else {
            return
        }
        // Adopt the storage ids assigned while saving without re-triggering a save.
        isApplyingSavedHistory = true
        items = saved
        isApplyingSavedHistory = false
    }

    private func historyPersistenceChanged(isEnabled: Bool) {
        if isEnabled {
            // `$` publishers fire before the property changes; wait one turn
            // so `scheduleHistorySave` sees the new value.
            DispatchQueue.main.async { [weak self] in
                self?.scheduleHistorySave()
            }
        } else {
            historySaveWorkItem?.cancel()
            historySaveWorkItem = nil
            historyStore?.clear()
        }
    }

    /// Removes already-captured history that came from apps the user has
    /// since added to the ignore list.
    private func purgeHistory(fromApps ignoredApps: Set<String>) {
        let remaining = items.filter { item in
            guard let bundleID = item.sourceAppBundleID else { return true }
            return !ignoredApps.contains(bundleID)
        }
        if remaining.count != items.count {
            items = remaining
        }
    }

    // MARK: - Text recognition

    private func knownOCRText(forKey key: String) -> String? {
        (items + taggedItems + pinnedItems).first { $0.dedupKey == key && $0.ocrText != nil }?.ocrText
    }

    /// Queues OCR for every stored image that has not been processed yet.
    func recognizeTextInUnprocessedImages() {
        for item in items + taggedItems + pinnedItems {
            enqueueTextRecognition(for: item)
        }
    }

    private func enqueueTextRecognition(for item: ClipboardHistoryItem) {
        guard textRecognizer != nil,
              settings.isImageTextRecognitionEnabled,
              item.ocrText == nil,
              case .image(let image) = item.content,
              !recognizingFingerprints.contains(image.fingerprint),
              !failedOCRFingerprints.contains(image.fingerprint) else {
            return
        }

        recognizingFingerprints.insert(image.fingerprint)
        ocrQueue.append((image.fingerprint, image.data))
        startNextTextRecognition()
    }

    private func startNextTextRecognition() {
        guard !isOCRRunning, let textRecognizer, !ocrQueue.isEmpty else { return }

        let job = ocrQueue.removeFirst()
        isOCRRunning = true
        runningOCRFingerprint = job.fingerprint

        Task { [weak self] in
            // Recognition itself hops to a background queue; only the result
            // is applied back on the main actor.
            let text = await textRecognizer(job.data)
            self?.finishTextRecognition(fingerprint: job.fingerprint, text: text)
        }
    }

    private func finishTextRecognition(fingerprint: String, text: String?) {
        isOCRRunning = false
        runningOCRFingerprint = nil
        recognizingFingerprints.remove(fingerprint)

        if let text, settings.isImageTextRecognitionEnabled {
            applyRecognizedText(text, toImageWithFingerprint: fingerprint)
        } else if text == nil {
            failedOCRFingerprints.insert(fingerprint)
        }

        startNextTextRecognition()
    }

    /// Stores OCR output on every copy of the image (history, tagged, pinned).
    func applyRecognizedText(_ text: String, toImageWithFingerprint fingerprint: String) {
        func matches(_ item: ClipboardHistoryItem) -> Bool {
            item.imageValue?.fingerprint == fingerprint
        }

        if items.contains(where: matches) {
            items = items.map { matches($0) ? $0.withOCRText(text) : $0 }
        }
        if taggedItems.contains(where: matches) {
            taggedItems = taggedItems.map { matches($0) ? $0.withOCRText(text) : $0 }
            saveTaggedItems()
        }
        if pinnedItems.contains(where: matches) {
            pinnedItems = pinnedItems.map { matches($0) ? $0.withOCRText(text) : $0 }
            savePinnedItems()
        }
    }

    func isRecognizingText(in item: ClipboardHistoryItem) -> Bool {
        guard let fingerprint = item.imageValue?.fingerprint else { return false }
        return recognizingFingerprints.contains(fingerprint)
    }

    // MARK: - Library

    /// Every clip the Library shows: history, tagged snippets and pinned clips
    /// merged into one entry per distinct content.
    var libraryItems: [ClipboardHistoryItem] {
        Self.mergedLibraryItems(history: items, tagged: taggedItems, pinned: pinnedItems)
    }

    /// Merges the three stores by content. Tags come from tagged snippets
    /// (falling back to the pinned copy), pin state and Quick Slot come from
    /// the pinned copy, and missing metadata is filled from any copy that has
    /// it. Result is newest first.
    static func mergedLibraryItems(
        history: [ClipboardHistoryItem],
        tagged: [ClipboardHistoryItem],
        pinned: [ClipboardHistoryItem]
    ) -> [ClipboardHistoryItem] {
        let historyByKey = Dictionary(history.map { ($0.dedupKey, $0) }, uniquingKeysWith: { first, _ in first })
        let taggedByKey = Dictionary(tagged.map { ($0.dedupKey, $0) }, uniquingKeysWith: { first, _ in first })
        let pinnedByKey = Dictionary(pinned.map { ($0.dedupKey, $0) }, uniquingKeysWith: { first, _ in first })

        var orderedKeys: [String] = []
        var seen = Set<String>()
        for item in history + tagged + pinned where seen.insert(item.dedupKey).inserted {
            orderedKeys.append(item.dedupKey)
        }

        let merged: [ClipboardHistoryItem] = orderedKeys.compactMap { key in
            let copies = [pinnedByKey[key], taggedByKey[key], historyByKey[key]].compactMap { $0 }
            guard var base = copies.first else { return nil }

            base.imageStorageID = nil
            base.tags = TagRules.normalize(taggedByKey[key]?.tags ?? pinnedByKey[key]?.tags ?? [])
            base.isPinned = pinnedByKey[key] != nil
            base.pinnedSlot = pinnedByKey[key]?.pinnedSlot
            base.sourceAppName = copies.compactMap(\.sourceAppName).first
            base.sourceAppBundleID = copies.compactMap(\.sourceAppBundleID).first
            base.ocrText = copies.compactMap(\.ocrText).first
            base.createdAt = copies.map(\.createdAt).max() ?? base.createdAt
            base.updatedAt = copies.map(\.updatedAt).max() ?? base.updatedAt
            return base
        }

        return merged.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt { return lhs.dedupKey < rhs.dedupKey }
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// Copies text that is not a stored clip (a transform result or recognized
    /// OCR text) without it being re-captured into history.
    func copyDerivedText(_ text: String) {
        copyAsPlainText(text)
    }

    // MARK: - Bulk actions

    struct BulkDeleteResult: Equatable {
        let deletedCount: Int
        /// Pinned clips left untouched because pinned clips were not included.
        let preservedPinnedCount: Int
    }

    /// Deletes exactly the given clips and nothing else.
    ///
    /// With `includingPinned == false` pinned clips are skipped: they stay
    /// pinned (and keep their Quick Slot) and are reported as preserved. Pass
    /// `true` only after the user explicitly confirmed "Delete Everywhere".
    @discardableResult
    func deleteItems(_ targets: [ClipboardHistoryItem], includingPinned: Bool) -> BulkDeleteResult {
        let requestedKeys = Set(targets.map(\.dedupKey))
        let pinnedKeys = Set(pinnedItems.map(\.dedupKey))
        let doomedKeys = includingPinned ? requestedKeys : requestedKeys.subtracting(pinnedKeys)
        let preserved = includingPinned ? 0 : requestedKeys.intersection(pinnedKeys).count

        let existingKeys = Set((items + taggedItems + pinnedItems).map(\.dedupKey))
        let deletedCount = doomedKeys.intersection(existingKeys).count

        if items.contains(where: { doomedKeys.contains($0.dedupKey) }) {
            items = items.filter { !doomedKeys.contains($0.dedupKey) }
        }
        if taggedItems.contains(where: { doomedKeys.contains($0.dedupKey) }) {
            taggedItems = taggedItems.filter { !doomedKeys.contains($0.dedupKey) }
            saveTaggedItems()
        }
        if includingPinned, pinnedItems.contains(where: { doomedKeys.contains($0.dedupKey) }) {
            pinnedItems = pinnedItems.filter { !doomedKeys.contains($0.dedupKey) }
            savePinnedItems()
        }

        return BulkDeleteResult(deletedCount: deletedCount, preservedPinnedCount: preserved)
    }

    /// Pins or unpins each clip that is not already in the requested state.
    /// Returns how many clips changed.
    @discardableResult
    func setPinned(_ shouldPin: Bool, for targets: [ClipboardHistoryItem]) -> Int {
        let lookup = currentLibraryLookup()
        var changed = 0
        for target in targets where isPinned(target) != shouldPin {
            togglePin(lookup[target.dedupKey] ?? target)
            changed += 1
        }
        return changed
    }

    struct BulkTagResult: Equatable {
        let updatedCount: Int
        let skippedCount: Int
    }

    /// Adds `tag` to every given clip. Clips that already have five tags, or
    /// that would exceed the tagged-snippet limit, are skipped and counted.
    @discardableResult
    func addTag(_ rawTag: String, to targets: [ClipboardHistoryItem]) -> BulkTagResult {
        guard let tag = TagRules.normalizeTag(rawTag) else {
            return BulkTagResult(updatedCount: 0, skippedCount: targets.count)
        }

        let lookup = currentLibraryLookup()
        var updated = 0
        var skipped = 0
        for target in targets {
            let item = lookup[target.dedupKey] ?? target
            if item.tags.contains(tag) { continue }

            let newTags = TagRules.normalize(item.tags + [tag])
            guard newTags.contains(tag),
                  setTags(for: item, rawTags: newTags.joined(separator: ",")) == .saved else {
                skipped += 1
                continue
            }
            updated += 1
        }
        return BulkTagResult(updatedCount: updated, skippedCount: skipped)
    }

    /// Removes `tag` from every given clip that has it. Returns how many changed.
    @discardableResult
    func removeTag(_ rawTag: String, from targets: [ClipboardHistoryItem]) -> Int {
        guard let tag = TagRules.normalizeTag(rawTag) else { return 0 }

        let lookup = currentLibraryLookup()
        var updated = 0
        for target in targets {
            let item = lookup[target.dedupKey] ?? target
            guard item.tags.contains(tag) else { continue }

            let remaining = item.tags.filter { $0 != tag }
            if remaining.isEmpty {
                removeAllTags(from: item)
            } else {
                setTags(for: item, rawTags: remaining.joined(separator: ","))
            }
            updated += 1
        }
        return updated
    }

    /// Latest merged state of a clip, so bulk operations never act on a
    /// stale snapshot held by the UI.
    private func currentLibraryLookup() -> [String: ClipboardHistoryItem] {
        Dictionary(libraryItems.map { ($0.dedupKey, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

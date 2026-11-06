//
//  PowerLibraryTests.swift
//  CopypastikTests
//
//  Covers the 1.4 "Power Library" features: Library filtering/grouping,
//  history persistence, OCR, bulk actions, drag export and transformations.
//

import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Copypastik

@MainActor
struct PowerLibraryTests {
    // MARK: Helpers

    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "PowerLibraryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PowerLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeSettings() -> AppSettings {
        AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
    }

    private func makeStore(
        settings: AppSettings? = nil,
        historyDirectory: URL? = nil,
        taggedDirectory: URL? = nil,
        pinnedDirectory: URL? = nil,
        recognizer: ClipboardStore.TextRecognition? = nil
    ) throws -> ClipboardStore {
        ClipboardStore(
            settings: settings ?? makeSettings(),
            startsService: false,
            taggedStore: TaggedStore(directoryURL: try taggedDirectory ?? temporaryDirectory()),
            pinnedStore: PinnedStore(directoryURL: try pinnedDirectory ?? temporaryDirectory()),
            historyStore: historyDirectory.map { HistoryStore(directoryURL: $0) },
            textRecognizer: recognizer
        )
    }

    private func makeImage(width: Int = 8, height: Int = 6, color: NSColor = .red) -> ClipboardImage {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        let deviceColor = color.usingColorSpace(.deviceRGB) ?? color
        for x in 0..<width {
            for y in 0..<height {
                bitmap.setColor(deviceColor, atX: x, y: y)
            }
        }
        let data = bitmap.representation(using: .png, properties: [:])!
        return ClipboardImage.make(from: data, pasteboardType: .png)!
    }

    private func renderedTextImage(_ text: String) -> Data {
        let size = NSSize(width: 900, height: 200)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 72, weight: .bold),
            .foregroundColor: NSColor.black
        ]
        NSAttributedString(string: text, attributes: attributes).draw(at: NSPoint(x: 24, y: 60))
        image.unlockFocus()
        let tiff = image.tiffRepresentation!
        return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
    }

    private func waitUntil(timeout: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private func clip(
        _ text: String,
        at date: Date = Date(),
        app: String? = nil,
        bundleID: String? = nil,
        tags: [String] = [],
        pinned: Bool = false,
        slot: Int? = nil
    ) -> ClipboardHistoryItem {
        ClipboardHistoryItem(
            content: .text(text),
            tags: tags,
            createdAt: date,
            updatedAt: date,
            sourceAppName: app,
            sourceAppBundleID: bundleID,
            isPinned: pinned,
            pinnedSlot: slot
        )
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func utcDate(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: string)!
    }

    // MARK: Library filtering

    @Test func libraryFilterCombinesSidebarScopeWithSearchTokens() {
        let clips = [
            clip("let value = 1", app: "Xcode", bundleID: "com.apple.dt.Xcode", tags: ["swift"]),
            clip("https://apple.com", app: "Safari", bundleID: "com.apple.Safari", tags: ["swift"]),
            clip("plain note about Swift", app: "Safari", bundleID: "com.apple.Safari"),
            .image(makeImage(), sourceAppName: "Safari", sourceAppBundleID: "com.apple.Safari")
        ]

        // Plain text only.
        #expect(LibraryFilter.apply(clips, scope: .all, query: "swift").count == 1)
        // #tag
        #expect(LibraryFilter.apply(clips, scope: .all, query: "#swift").count == 2)
        // @app
        #expect(LibraryFilter.apply(clips, scope: .all, query: "@safari").count == 3)
        // type:
        #expect(LibraryFilter.apply(clips, scope: .all, query: "type:link").map(\.textValue) == ["https://apple.com"])
        #expect(LibraryFilter.apply(clips, scope: .all, query: "type:image").count == 1)
        // Everything at once.
        #expect(LibraryFilter.apply(clips, scope: .all, query: "@safari #swift type:link apple").count == 1)

        // Sidebar scope ANDs with the query instead of replacing it.
        #expect(LibraryFilter.apply(clips, scope: .app("com.apple.Safari"), query: "type:link").count == 1)
        #expect(LibraryFilter.apply(clips, scope: .app("com.apple.Safari"), query: "@xcode").isEmpty)
        #expect(LibraryFilter.apply(clips, scope: .type(.text), query: "#swift").isEmpty)
        #expect(LibraryFilter.apply(clips, scope: .tag("swift"), query: "@xcode").count == 1)
    }

    @Test func libraryFilterScopesPinnedAndCountsSidebarEntries() {
        let clips = [
            clip("a", app: "Safari", bundleID: "com.apple.Safari", pinned: true, slot: 1),
            clip("b", app: "Safari", bundleID: "com.apple.Safari", tags: ["x", "y"]),
            clip("c", app: "Notes", bundleID: "com.apple.Notes", tags: ["x"]),
            clip("d")
        ]

        #expect(LibraryFilter.apply(clips, scope: .pinned, query: "").map(\.textValue) == ["a"])

        let apps = LibraryFilter.apps(in: clips)
        #expect(apps.map(\.name) == ["Safari", "Notes"])
        #expect(apps.map(\.count) == [2, 1])

        let tags = LibraryFilter.tags(in: clips)
        #expect(tags == [LibraryTagEntry(tag: "x", count: 2), LibraryTagEntry(tag: "y", count: 1)])

        let counts = LibraryFilter.typeCounts(in: clips)
        #expect(counts[.text] == 4)
        #expect(counts[.image] == 0)
    }

    @Test func typeClassificationDrivesLibraryTypeScopes() {
        let clips = [
            clip("https://example.com/path"),
            clip("git status"),
            clip("let x = 5"),
            clip("plain words here"),
            clip("two\nlines"),
            .image(makeImage())
        ]

        #expect(LibraryFilter.apply(clips, scope: .type(.link), query: "").count == 1)
        #expect(LibraryFilter.apply(clips, scope: .type(.command), query: "").map(\.textValue) == ["git status"])
        #expect(LibraryFilter.apply(clips, scope: .type(.code), query: "").map(\.textValue) == ["let x = 5"])
        #expect(LibraryFilter.apply(clips, scope: .type(.text), query: "").count == 2)
        #expect(LibraryFilter.apply(clips, scope: .type(.image), query: "").count == 1)
    }

    @Test func libraryGroupsByDateWithPinnedFirst() {
        let calendar = utcCalendar
        let now = utcDate("2026-07-15T12:00:00Z")

        #expect(LibraryDateGroup.group(for: utcDate("2026-07-15T08:00:00Z"), now: now, calendar: calendar) == .today)
        #expect(LibraryDateGroup.group(for: utcDate("2026-07-14T23:00:00Z"), now: now, calendar: calendar) == .yesterday)
        #expect(LibraryDateGroup.group(for: utcDate("2026-07-10T12:00:00Z"), now: now, calendar: calendar) == .lastSevenDays)
        #expect(LibraryDateGroup.group(for: utcDate("2026-07-01T12:00:00Z"), now: now, calendar: calendar) == .earlier)

        let clips = [
            clip("today", at: utcDate("2026-07-15T09:00:00Z")),
            clip("old", at: utcDate("2026-06-01T09:00:00Z")),
            clip("pinned old", at: utcDate("2026-05-01T09:00:00Z"), pinned: true, slot: 2),
            clip("yesterday", at: utcDate("2026-07-14T09:00:00Z"))
        ]
        let sections = LibraryFilter.sections(for: clips, now: now, calendar: calendar)

        #expect(sections.map(\.group) == [.pinned, .today, .yesterday, .earlier])
        #expect(sections.first?.items.map(\.textValue) == ["pinned old"])
    }

    @Test func mergedLibraryItemsCombineHistoryTaggedAndPinnedCopies() {
        let created = Date(timeIntervalSince1970: 1_000)
        let history = [clip("shared", at: created, app: "Safari", bundleID: "com.apple.Safari"), clip("only history", at: created)]
        let tagged = [clip("shared", at: created, tags: ["work"])]
        let pinned = [clip("shared", at: created, tags: [], pinned: true, slot: 3)]

        let merged = ClipboardStore.mergedLibraryItems(history: history, tagged: tagged, pinned: pinned)

        #expect(merged.count == 2)
        let shared = merged.first { $0.textValue == "shared" }
        #expect(shared?.tags == ["work"])
        #expect(shared?.isPinned == true)
        #expect(shared?.pinnedSlot == 3)
        #expect(shared?.sourceAppName == "Safari")
        let onlyHistory = merged.first { $0.textValue == "only history" }
        #expect(onlyHistory?.isPinned == false)
    }

    // MARK: Library state

    @Test func libraryStateNavigatesAndDismissesLayers() throws {
        let settings = makeSettings()
        let store = try makeStore(settings: settings)
        let state = LibraryState(store: store, settings: settings)
        let now = Date()
        state.setClips([
            clip("one", at: now),
            clip("two", at: now.addingTimeInterval(-10)),
            clip("three", at: now.addingTimeInterval(-20))
        ])

        state.moveSelection(by: 1)
        #expect(state.selectedItems.map(\.textValue) == ["one"])
        state.moveSelection(by: 1)
        #expect(state.selectedItems.map(\.textValue) == ["two"])
        state.moveSelection(by: 5)
        #expect(state.selectedItems.map(\.textValue) == ["three"])
        state.moveSelection(by: -1, extending: true)
        #expect(state.selectedItems.map(\.textValue) == ["two", "three"])

        // Escape peels one layer at a time: multi-selection, then the search.
        #expect(state.dismissLayer() == true)
        #expect(state.selectedItems.map(\.textValue) == ["two"])
        #expect(state.dismissLayer() == false)

        state.query = "t"
        #expect(state.dismissLayer() == true)
        #expect(state.query.isEmpty)
        #expect(state.dismissLayer() == false)
    }

    @Test func libraryStateDropsSelectionThatLeavesTheFilteredList() throws {
        let settings = makeSettings()
        let store = try makeStore(settings: settings)
        let state = LibraryState(store: store, settings: settings)
        state.setClips([
            clip("alpha", app: "Safari", bundleID: "com.apple.Safari"),
            clip("beta", app: "Notes", bundleID: "com.apple.Notes")
        ])

        state.selectAllVisible()
        #expect(state.selection.count == 2)

        state.scope = .app("com.apple.Safari")

        #expect(state.visibleItems.map(\.textValue) == ["alpha"])
        #expect(state.selectedItems.map(\.textValue) == ["alpha"])
        #expect(state.selection.count == 1)
    }

    @Test func libraryStateRequiresConfirmationForMultipleDeletesAndKeepsPinned() throws {
        let settings = makeSettings()
        let store = try makeStore(settings: settings)
        store.ingestCopiedItem(.text("keep me"))
        store.ingestCopiedItem(.text("pinned one"))
        store.ingestCopiedItem(.text("delete a"))
        store.ingestCopiedItem(.text("delete b"))
        store.togglePin(.text("pinned one"))

        let state = LibraryState(store: store, settings: settings)
        state.reload()
        state.selection = Set(["text:pinned one", "text:delete a", "text:delete b"])

        state.requestDeleteSelection()
        #expect(state.pendingDelete != nil)
        #expect(state.pendingDelete?.pinnedCount == 1)
        #expect(store.items.count == 4) // nothing deleted before confirmation

        state.confirmDelete(includingPinned: false)

        #expect(store.items.map(\.textValue).contains("keep me"))
        #expect(!store.items.map(\.textValue).contains("delete a"))
        #expect(!store.items.map(\.textValue).contains("delete b"))
        #expect(store.pinnedItems.map(\.textValue) == ["pinned one"])
        #expect(store.items.map(\.textValue).contains("pinned one"))
    }

    @Test func libraryStateDeletesSingleUnpinnedClipWithoutPrompt() throws {
        let settings = makeSettings()
        let store = try makeStore(settings: settings)
        store.ingestCopiedItem(.text("first"))
        store.ingestCopiedItem(.text("second"))
        let state = LibraryState(store: store, settings: settings)
        state.reload()
        state.selection = ["text:second"]

        state.requestDeleteSelection()

        #expect(state.pendingDelete == nil)
        #expect(store.items.map(\.textValue) == ["first"])
    }

    // MARK: Bulk actions

    @Test func bulkTaggingOnlyTouchesTheSelectedClips() throws {
        let store = try makeStore()
        for text in ["a", "b", "c"] { store.ingestCopiedItem(.text(text)) }

        let result = store.addTag("Work", to: [.text("a"), .text("c")])

        #expect(result == ClipboardStore.BulkTagResult(updatedCount: 2, skippedCount: 0))
        #expect(Set(store.taggedItems.compactMap(\.textValue)) == ["a", "c"])
        #expect(store.items.map(\.textValue) == ["b"])
        #expect(store.taggedItems.allSatisfy { $0.tags == ["work"] })

        let removed = store.removeTag("work", from: [.text("a")])
        #expect(removed == 1)
        #expect(store.taggedItems.compactMap(\.textValue) == ["c"])
        #expect(Set(store.items.compactMap(\.textValue)) == ["a", "b"])
    }

    @Test func bulkTaggingSkipsClipsAtTheTagLimit() throws {
        let store = try makeStore()
        store.ingestCopiedItem(.text("full"))
        store.ingestCopiedItem(.text("roomy"))
        #expect(store.setTags(for: .text("full"), rawTags: "a,b,c,d,e") == .saved)

        let result = store.addTag("extra", to: [.text("full"), .text("roomy")])

        #expect(result.updatedCount == 1)
        #expect(result.skippedCount == 1)
        #expect(store.taggedItems.first { $0.textValue == "full" }?.tags == ["a", "b", "c", "d", "e"])
        #expect(store.taggedItems.first { $0.textValue == "roomy" }?.tags == ["extra"])
    }

    @Test func bulkPinAndUnpinAffectOnlyTheTargets() throws {
        let store = try makeStore()
        for text in ["a", "b", "c"] { store.ingestCopiedItem(.text(text)) }

        #expect(store.setPinned(true, for: [.text("a"), .text("b")]) == 2)
        #expect(Set(store.pinnedItems.compactMap(\.textValue)) == ["a", "b"])

        // Already-pinned targets are not counted again.
        #expect(store.setPinned(true, for: [.text("a")]) == 0)

        #expect(store.setPinned(false, for: [.text("a")]) == 1)
        #expect(store.pinnedItems.compactMap(\.textValue) == ["b"])
    }

    @Test func bulkDeletePreservesPinnedClipsUnlessExplicitlyIncluded() throws {
        let store = try makeStore()
        for text in ["a", "b", "c"] { store.ingestCopiedItem(.text(text)) }
        store.togglePin(.text("b"))

        let kept = store.deleteItems([.text("a"), .text("b")], includingPinned: false)
        #expect(kept == ClipboardStore.BulkDeleteResult(deletedCount: 1, preservedPinnedCount: 1))
        #expect(store.pinnedItems.compactMap(\.textValue) == ["b"])
        #expect(Set(store.items.compactMap(\.textValue)) == ["b", "c"])

        let everywhere = store.deleteItems([.text("b")], includingPinned: true)
        #expect(everywhere.deletedCount == 1)
        #expect(store.pinnedItems.isEmpty)
        #expect(store.items.compactMap(\.textValue) == ["c"])
    }

    @Test func taggingAPinnedClipKeepsThePinnedCopyInSync() throws {
        let store = try makeStore()
        store.ingestCopiedItem(.text("pinned"))
        store.togglePin(.text("pinned"))

        store.addTag("docs", to: [.text("pinned")])
        #expect(store.pinnedItems.first?.tags == ["docs"])
        #expect(store.libraryItems.first?.tags == ["docs"])

        store.removeTag("docs", from: [.text("pinned")])
        #expect(store.pinnedItems.first?.tags == [])
        #expect(store.libraryItems.first?.tags == [])
    }

    @Test func copySelectedJoinsTextWithNewlinesAndSkipsImages() {
        let items: [ClipboardHistoryItem] = [.text("one"), .image(makeImage()), .text("two\nlines"), .text("three")]
        let summary = BulkCopyFormatter.combine(items)

        #expect(summary.text == "one\ntwo\nlines\nthree")
        #expect(summary.copiedCount == 3)
        #expect(summary.skippedImageCount == 1)

        let imagesOnly = BulkCopyFormatter.combine([.image(makeImage())])
        #expect(imagesOnly.copiedCount == 0)
        #expect(imagesOnly.text.isEmpty)
    }

    // MARK: Persistence

    @Test func historyStoreRoundTripsTextImagesAndMetadata() throws {
        let directory = try temporaryDirectory()
        let store = HistoryStore(directoryURL: directory)
        let image = makeImage(width: 12, height: 7, color: .blue)
        let created = Date(timeIntervalSince1970: 5_000)

        let items: [ClipboardHistoryItem] = [
            ClipboardHistoryItem(
                content: .text("saved text"),
                createdAt: created,
                updatedAt: created,
                sourceAppName: "Safari",
                sourceAppBundleID: "com.apple.Safari"
            ),
            ClipboardHistoryItem(
                content: .image(image),
                createdAt: created,
                updatedAt: created,
                sourceAppName: "Preview",
                sourceAppBundleID: "com.apple.Preview",
                ocrText: "Receipt 42"
            )
        ]
        store.save(items)

        let loaded = HistoryStore(directoryURL: directory).load(limit: 100)

        #expect(loaded.count == 2)
        #expect(loaded[0].textValue == "saved text")
        #expect(loaded[0].sourceAppName == "Safari")
        #expect(loaded[0].createdAt == created)
        #expect(loaded[1].imageValue?.fingerprint == image.fingerprint)
        #expect(loaded[1].ocrText == "Receipt 42")
        #expect(loaded[1].sourceAppBundleID == "com.apple.Preview")
    }

    @Test func historyStoreHonorsLimitSkipsHugeTextAndBacksUpCorruptFiles() throws {
        let directory = try temporaryDirectory()
        let store = HistoryStore(directoryURL: directory)
        let huge = String(repeating: "x", count: HistoryStore.maxPersistedTextBytes + 1)
        store.save([.text("a"), .text(huge), .text("b"), .text("c")])

        #expect(HistoryStore(directoryURL: directory).load(limit: 2).compactMap(\.textValue) == ["a", "b"])
        #expect(!HistoryStore(directoryURL: directory).load(limit: 10).compactMap(\.textValue).contains(huge))

        try Data("not json".utf8).write(to: store.fileURL)
        #expect(store.load(limit: 10).isEmpty)
        #expect(FileManager.default.fileExists(atPath: store.backupURL.path))
    }

    @Test func historyStoreRemovesOrphanedImageFiles() throws {
        let directory = try temporaryDirectory()
        let store = HistoryStore(directoryURL: directory)
        let saved = store.save([.image(makeImage(color: .red)), .image(makeImage(width: 9, color: .green))])
        #expect((try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectoryURL.path)).count == 2)

        store.save([saved[0]])
        #expect((try FileManager.default.contentsOfDirectory(atPath: store.imagesDirectoryURL.path)).count == 1)

        store.clear()
        #expect(!FileManager.default.fileExists(atPath: store.fileURL.path))
        #expect(!FileManager.default.fileExists(atPath: store.imagesDirectoryURL.path))
    }

    @Test func clipboardStorePersistsHistoryAcrossRelaunch() throws {
        let history = try temporaryDirectory()
        let tagged = try temporaryDirectory()
        let pinned = try temporaryDirectory()

        let first = try makeStore(historyDirectory: history, taggedDirectory: tagged, pinnedDirectory: pinned)
        first.ingestCopiedItem(.text("survives relaunch"))
        first.ingestCopiedItem(.image(makeImage()))
        first.flushPendingHistorySave()

        let second = try makeStore(historyDirectory: history, taggedDirectory: tagged, pinnedDirectory: pinned)

        #expect(second.items.count == 2)
        #expect(second.items.contains { $0.textValue == "survives relaunch" })
        #expect(second.items.contains { $0.imageValue != nil })
    }

    @Test func persistedHistoryRespectsTheHistoryLimitSetting() throws {
        let history = try temporaryDirectory()
        let settings = makeSettings()
        settings.historyLimit = .fifty
        let first = try makeStore(settings: settings, historyDirectory: history)
        for index in 1...40 { first.ingestCopiedItem(.text("item \(index)")) }
        first.flushPendingHistorySave()

        let smaller = makeSettings()
        smaller.historyLimit = .twenty
        let second = try makeStore(settings: smaller, historyDirectory: history)

        #expect(second.items.count == 20)
        #expect(second.items.first?.textValue == "item 40")
    }

    @Test func pausedAndIgnoredClipsNeverReachDisk() throws {
        let history = try temporaryDirectory()
        let settings = makeSettings()
        let store = try makeStore(settings: settings, historyDirectory: history)
        let historyFile = HistoryStore(directoryURL: history).fileURL

        settings.addIgnoredApp(bundleID: "com.example.secret")
        store.ingestCopiedItem(.text("from ignored app", sourceAppName: "Secret", sourceAppBundleID: "com.example.secret"))
        settings.pauseCapture(for: .untilResumed)
        store.ingestCopiedItem(.text("while paused"))
        store.flushPendingHistorySave()

        #expect(store.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: historyFile.path))
    }

    @Test func ignoringAnAppLaterPurgesItsSavedHistory() throws {
        let history = try temporaryDirectory()
        let settings = makeSettings()
        let store = try makeStore(settings: settings, historyDirectory: history)
        store.ingestCopiedItem(.text("from later ignored", sourceAppName: "Later", sourceAppBundleID: "com.example.later"))
        store.ingestCopiedItem(.text("from other app", sourceAppName: "Other", sourceAppBundleID: "com.example.other"))

        settings.addIgnoredApp(bundleID: "com.example.later")
        store.flushPendingHistorySave()

        #expect(store.items.compactMap(\.textValue) == ["from other app"])
        let reloaded = try makeStore(settings: settings, historyDirectory: history)
        #expect(reloaded.items.compactMap(\.textValue) == ["from other app"])
    }

    @Test func turningPersistenceOffRemovesSavedHistoryAndStopsWriting() throws {
        let history = try temporaryDirectory()
        let settings = makeSettings()
        let store = try makeStore(settings: settings, historyDirectory: history)
        let historyFile = HistoryStore(directoryURL: history).fileURL

        store.ingestCopiedItem(.text("first"))
        store.flushPendingHistorySave()
        #expect(FileManager.default.fileExists(atPath: historyFile.path))

        settings.isHistoryPersistenceEnabled = false
        #expect(!FileManager.default.fileExists(atPath: historyFile.path))

        store.ingestCopiedItem(.text("second"))
        store.flushPendingHistorySave()
        #expect(!FileManager.default.fileExists(atPath: historyFile.path))
    }

    @Test func clearingHistoryWipesTheSavedFile() throws {
        let history = try temporaryDirectory()
        let store = try makeStore(historyDirectory: history)
        store.ingestCopiedItem(.text("temporary"))
        store.flushPendingHistorySave()

        store.clearHistory()

        let reloaded = try makeStore(historyDirectory: history)
        #expect(reloaded.items.isEmpty)
    }

    @Test func historyImageBudgetDropsOldestImagesButNeverText() {
        func fakeImage(_ name: String, bytes: Int) -> ClipboardHistoryItem {
            .image(ClipboardImage(
                data: Data(count: bytes),
                pasteboardTypeRawValue: NSPasteboard.PasteboardType.png.rawValue,
                width: 1,
                height: 1,
                fingerprint: name
            ))
        }

        let items: [ClipboardHistoryItem] = [fakeImage("new", bytes: 1_000), .text("text"), fakeImage("old", bytes: 1_000)]
        let trimmed = ClipboardStore.applyingImageBudget(to: items, budget: 1_500)

        #expect(trimmed.count == 2)
        #expect(trimmed.contains { $0.textValue == "text" })
        #expect(trimmed.contains { $0.imageValue?.fingerprint == "new" })

        // The newest image is kept even if it alone exceeds the budget.
        let oversize = ClipboardStore.applyingImageBudget(to: [fakeImage("big", bytes: 5_000)], budget: 100)
        #expect(oversize.count == 1)
    }

    @Test func legacyTaggedAndPinnedFilesStillLoad() throws {
        let taggedDirectory = try temporaryDirectory()
        let legacyTagged = #"{"items":[{"kind":"text","text":"old snippet","tags":["sql"],"createdAt":0,"updatedAt":0}]}"#
        try Data(legacyTagged.utf8).write(to: taggedDirectory.appendingPathComponent(TaggedStore.fileName))

        let tagged = TaggedStore(directoryURL: taggedDirectory).load()
        #expect(tagged.count == 1)
        #expect(tagged[0].textValue == "old snippet")
        #expect(tagged[0].sourceAppName == nil)

        let pinnedDirectory = try temporaryDirectory()
        let legacyPinned = #"{"items":[{"kind":"text","text":"old pin","tags":[],"createdAt":0,"updatedAt":0,"pinnedSlot":4,"sourceAppName":"Notes"}]}"#
        try Data(legacyPinned.utf8).write(to: pinnedDirectory.appendingPathComponent(PinnedStore.fileName))

        let pinned = PinnedStore(directoryURL: pinnedDirectory).load()
        #expect(pinned.count == 1)
        #expect(pinned[0].pinnedSlot == 4)
        #expect(pinned[0].sourceAppName == "Notes")
        #expect(pinned[0].ocrText == nil)
    }

    @Test func taggedAndPinnedStoresPersistSourceAppAndRecognizedText() throws {
        let taggedStore = TaggedStore(directoryURL: try temporaryDirectory())
        let tagged = ClipboardHistoryItem.image(
            makeImage(),
            tags: ["receipts"],
            sourceAppName: "Preview",
            sourceAppBundleID: "com.apple.Preview",
            ocrText: "Total 12.50"
        )
        taggedStore.save([tagged])
        let reloadedTagged = taggedStore.load()
        #expect(reloadedTagged.first?.ocrText == "Total 12.50")
        #expect(reloadedTagged.first?.sourceAppName == "Preview")

        let pinnedStore = PinnedStore(directoryURL: try temporaryDirectory())
        pinnedStore.save([tagged.withPinned(true, slot: 2)])
        let reloadedPinned = pinnedStore.load()
        #expect(reloadedPinned.first?.ocrText == "Total 12.50")
        #expect(reloadedPinned.first?.pinnedSlot == 2)
    }

    // MARK: OCR

    @Test func recognizedTextMakesImagesSearchable() {
        let image = ClipboardHistoryItem.image(makeImage(), ocrText: "Invoice 4242 from Acme")
        let plain = ClipboardHistoryItem.image(makeImage(width: 9))

        #expect(image.searchText.localizedCaseInsensitiveContains("acme"))
        #expect(!plain.searchText.localizedCaseInsensitiveContains("acme"))
        #expect(image.recognizedText == "Invoice 4242 from Acme")
        #expect(ClipboardHistoryItem.image(makeImage(), ocrText: "").recognizedText == nil)

        let results = LibraryFilter.apply([image, plain], scope: .all, query: "invoice type:image")
        #expect(results.count == 1)
    }

    @Test func pickerSearchIncludesRecognizedText() {
        let state = PickerState()
        state.prepareForPresentation(with: [
            .image(makeImage(), ocrText: "Wi-Fi password is on the fridge"),
            .text("unrelated")
        ])
        state.query = "fridge"

        #expect(state.filteredItems.count == 1)
        #expect(state.filteredItems.first?.imageValue != nil)
    }

    @Test func ocrRunsInTheBackgroundAndUpdatesTheStoredImage() async throws {
        let store = try makeStore(recognizer: { _ in "Order #1234" })
        let image = makeImage()

        store.ingestCopiedItem(.image(image))
        // Capture is immediate; recognition completes afterwards.
        #expect(store.items.count == 1)
        #expect(store.items.first?.ocrText == nil)
        #expect(store.recognizingFingerprints.contains(image.fingerprint))

        try await waitUntil { store.items.first?.ocrText != nil }

        #expect(store.items.first?.ocrText == "Order #1234")
        #expect(store.recognizingFingerprints.isEmpty)
        #expect(store.libraryItems.first?.recognizedText == "Order #1234")
    }

    @Test func ocrFailureLeavesTheImageUsable() async throws {
        let store = try makeStore(recognizer: { _ in nil })
        let image = makeImage()

        store.ingestCopiedItem(.image(image))
        try await waitUntil { store.recognizingFingerprints.isEmpty }

        #expect(store.items.count == 1)
        #expect(store.items.first?.ocrText == nil)
        #expect(store.items.first?.imageValue?.fingerprint == image.fingerprint)
    }

    @Test func ocrIsSkippedWhenTheSettingIsOff() async throws {
        let settings = makeSettings()
        settings.isImageTextRecognitionEnabled = false
        let store = try makeStore(settings: settings, recognizer: { _ in "should not run" })

        store.ingestCopiedItem(.image(makeImage()))
        try await Task.sleep(for: .milliseconds(150))

        #expect(store.items.first?.ocrText == nil)
        #expect(store.recognizingFingerprints.isEmpty)
    }

    @Test func recopyingAnImageKeepsItsRecognizedText() async throws {
        let store = try makeStore(recognizer: { _ in "Kept text" })
        let image = makeImage()
        store.ingestCopiedItem(.image(image))
        try await waitUntil { store.items.first?.ocrText != nil }

        store.ingestCopiedItem(.text("something else"))
        store.ingestCopiedItem(.image(image))

        let reCopied = store.items.first
        #expect(reCopied?.imageValue?.fingerprint == image.fingerprint)
        #expect(reCopied?.ocrText == "Kept text")
        #expect(store.recognizingFingerprints.isEmpty)
    }

    @Test func turningOcrOnBackfillsImagesCapturedWhileItWasOff() async throws {
        let settings = makeSettings()
        settings.isImageTextRecognitionEnabled = false
        let store = try makeStore(settings: settings, recognizer: { _ in "late text" })
        store.ingestCopiedItem(.image(makeImage()))

        settings.isImageTextRecognitionEnabled = true
        try await waitUntil { store.items.first?.ocrText != nil }

        #expect(store.items.first?.ocrText == "late text")
    }

    @Test func visionRecognizesTextInARenderedImage() throws {
        let text = TextRecognizer.recognizeTextSynchronously(in: renderedTextImage("HELLO WORLD"))
        let recognized = try #require(text)

        #expect(recognized.uppercased().contains("HELLO"))
        #expect(recognized.uppercased().contains("WORLD"))
        #expect(TextRecognizer.recognizeTextSynchronously(in: Data("not an image".utf8)) == nil)
    }

    @Test func recognizerNormalizesAndCapsOutput() {
        #expect(TextRecognizer.normalize(lines: ["  one ", "", "two"]) == "one\ntwo")
        let capped = TextRecognizer.normalize(lines: [String(repeating: "a", count: TextRecognizer.maxCharacters + 50)])
        #expect(capped.count == TextRecognizer.maxCharacters)
    }

    // MARK: Drag & drop

    @Test func textClipsDragAsPlainText() async throws {
        let provider = LibraryDragProvider.itemProvider(for: .text("hello drag"))

        #expect(provider.canLoadObject(ofClass: NSString.self))
        let string = try await loadString(from: provider)
        #expect(string == "hello drag")
    }

    @Test func linkClipsDragAsURLWithTextFallback() async throws {
        let provider = LibraryDragProvider.itemProvider(for: .text("https://example.com/page?a=1"))

        #expect(provider.canLoadObject(ofClass: NSURL.self))
        #expect(provider.canLoadObject(ofClass: NSString.self))
        let string = try await loadString(from: provider)
        #expect(string == "https://example.com/page?a=1")
    }

    @Test func imageClipsDragAsPNGDataAndFile() async throws {
        let image = makeImage(width: 10, height: 4)
        let provider = LibraryDragProvider.itemProvider(for: .image(image))

        #expect(provider.hasItemConformingToTypeIdentifier(UTType.png.identifier))

        let data = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.png.identifier) { data, error in
                if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(data == image.data)

        let fileExists = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
            _ = provider.loadFileRepresentation(forTypeIdentifier: UTType.png.identifier) { url, error in
                if let url {
                    continuation.resume(returning: (try? Data(contentsOf: url)) == image.data)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
        #expect(fileExists)
        #expect(LibraryDragProvider.suggestedFileName(for: image) == "Copypastik Image 10x4.png")
    }

    private func loadString(from provider: NSItemProvider) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, error in
                if let string = object as? String {
                    continuation.resume(returning: string)
                } else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                }
            }
        }
    }

    // MARK: Transformations

    private func transformed(_ transform: ClipTransform, _ text: String) -> String? {
        if case .success(let output) = transform.apply(to: text) { return output.text }
        return nil
    }

    @Test func simpleTextTransformsLeaveTheSourceStringUntouched() {
        let original = "  Hello World \t\n  second line   \n"

        #expect(transformed(.trimWhitespace, original) == "Hello World\n  second line")
        #expect(transformed(.uppercase, "MiXed") == "MIXED")
        #expect(transformed(.lowercase, "MiXed") == "mixed")
        #expect(transformed(.plainText, original) == original)
        #expect(original == "  Hello World \t\n  second line   \n")
    }

    @Test func normalizeLineBreaksHandlesCRLFCRAndUnicodeSeparators() {
        #expect(transformed(.normalizeLineBreaks, "a\r\nb\rc\u{2028}d\u{2029}e\nf") == "a\nb\nc\nd\ne\nf")
        #expect(ClipTransform.normalizeLineBreaks.isAvailable(for: "a\r\nb"))
        #expect(!ClipTransform.normalizeLineBreaks.isAvailable(for: "a\nb"))
    }

    @Test func prettyPrintJSONFormatsValidAndRejectsInvalidInput() throws {
        let pretty = try #require(transformed(.prettyPrintJSON, #"{"b":1,"a":[1,2],"url":"a/b"}"#))
        #expect(pretty.contains("\n"))
        #expect(pretty.range(of: "\"a\"")!.lowerBound < pretty.range(of: "\"b\"")!.lowerBound)
        #expect(pretty.contains("a/b"))

        #expect(ClipTransform.prettyPrintJSON.isAvailable(for: "{ not json }"))
        #expect(ClipTransform.prettyPrintJSON.apply(to: "{ not json }") == .failure(.invalidJSON))
        #expect(!ClipTransform.prettyPrintJSON.isAvailable(for: "just words"))
    }

    @Test func urlEncodeAndDecodeRoundTrip() {
        #expect(transformed(.urlEncode, "a b&c=d/é") == "a%20b%26c%3Dd%2F%C3%A9")
        #expect(transformed(.urlDecode, "a%20b%26c%3Dd%2F%C3%A9") == "a b&c=d/é")
        #expect(!ClipTransform.urlDecode.isAvailable(for: "no escapes"))
        #expect(ClipTransform.urlDecode.apply(to: "100%") == .failure(.invalidPercentEncoding))
    }

    @Test func trackingParameterRemovalIsConservative() {
        let url = "https://example.com/p?id=7&utm_source=news&UTM_Campaign=x&fbclid=abc&ref=home&gclid=1#frag"
        #expect(transformed(.removeTrackingParameters, url) == "https://example.com/p?id=7&ref=home#frag")

        // Only tracking keys: the query disappears entirely.
        #expect(transformed(.removeTrackingParameters, "https://example.com/?utm_medium=a&utm_term=b") == "https://example.com/")
        // Meaningful parameters (and their encoding/order) are untouched.
        #expect(transformed(.removeTrackingParameters, "https://example.com/s?q=a%20b&page=2&sort=asc")
            == "https://example.com/s?q=a%20b&page=2&sort=asc")
        // Lookalike names are not tracking parameters.
        #expect(ClipTransform.isTrackingParameter("utm_source"))
        #expect(!ClipTransform.isTrackingParameter("utmost"))
        #expect(!ClipTransform.isTrackingParameter("source"))

        #expect(!ClipTransform.removeTrackingParameters.isAvailable(for: "https://example.com/plain"))
        #expect(!ClipTransform.removeTrackingParameters.isAvailable(for: "not a url?utm_source=x"))
        #expect(ClipTransform.removeTrackingParameters.apply(to: "ftp://example.com/?a=1") == .failure(.notAWebURL))
    }

    @Test func copyDomainExtractsTheHost() {
        #expect(transformed(.copyDomain, "https://www.Apple.com/mac?x=1") == "apple.com")
        #expect(transformed(.copyDomain, "http://docs.github.com:8080/a") == "docs.github.com")
        #expect(!ClipTransform.copyDomain.isAvailable(for: "https://example.com is great"))
        #expect(!ClipTransform.copyDomain.isAvailable(for: "plain text"))
        #expect(ClipTransform.copyDomain.apply(to: "plain text") == .failure(.notAWebURL))
    }

    @Test func transformsReportWhetherAnythingChanged() throws {
        if case .success(let output) = ClipTransform.uppercase.apply(to: "ALREADY") {
            #expect(!output.didChange)
        } else {
            Issue.record("uppercase should not fail")
        }
        if case .success(let output) = ClipTransform.lowercase.apply(to: "Change") {
            #expect(output.didChange)
        } else {
            Issue.record("lowercase should not fail")
        }
    }

    // MARK: Settings

    @Test func settingsDefaultToLocalOcrAndPersistedHistoryAndPersistChanges() {
        let defaults = temporaryDefaults()
        let settings = AppSettings(defaults: defaults, managesLaunchAtLogin: false)
        #expect(settings.isImageTextRecognitionEnabled)
        #expect(settings.isHistoryPersistenceEnabled)

        settings.isImageTextRecognitionEnabled = false
        settings.isHistoryPersistenceEnabled = false
        settings.historyLimit = .fiveHundred

        let reloaded = AppSettings(defaults: defaults, managesLaunchAtLogin: false)
        #expect(!reloaded.isImageTextRecognitionEnabled)
        #expect(!reloaded.isHistoryPersistenceEnabled)
        #expect(reloaded.historyLimit == .fiveHundred)
        #expect(ClipboardHistoryLimit.allCases.map(\.rawValue) == [20, 50, 100, 250, 500])
    }
}

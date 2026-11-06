//
//  CopypastikTests.swift
//  CopypastikTests
//
//  Created by Andrii Ivanchenko on 27.04.2026.
//

import AppKit
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Copypastik

struct CopypastikTests {
    private func temporaryDefaults() -> UserDefaults {
        let suiteName = "CopypastikTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
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

    private func temporaryDirectory() throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CopypastikTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func temporaryTaggedStore() throws -> TaggedStore {
        TaggedStore(directoryURL: try temporaryDirectory())
    }

    private func temporaryPinnedStore() throws -> PinnedStore {
        PinnedStore(directoryURL: try temporaryDirectory())
    }

    @MainActor
    @Test func clipboardHistoryMovesRepeatedItemsToTop() async throws {
        let items: [ClipboardHistoryItem] = [.text("text 2"), .text("text 1")]

        let updatedItems = ClipboardStore.historyItems(afterAdding: .text("text 1"), to: items)

        #expect(updatedItems.map(\.textValue) == ["text 1", "text 2"])
    }

    @MainActor
    @Test func clipboardHistoryDoesNotDuplicateRepeatedItems() async throws {
        let items: [ClipboardHistoryItem] = [.text("text 2"), .text("text 1")]

        let updatedItems = ClipboardStore.historyItems(afterAdding: .text("text 1"), to: items)

        #expect(updatedItems.count == 2)
        #expect(Set(updatedItems.map(\.dedupKey)).count == 2)
    }

    @MainActor
    @Test func clipboardHistoryKeepsConfiguredItemLimit() async throws {
        let items = (1...20).map { ClipboardHistoryItem.text("item \($0)") }

        let updatedItems = ClipboardStore.historyItems(afterAdding: .text("new item"), to: items)

        #expect(updatedItems.count == ClipboardStore.historyLimit)
        #expect(updatedItems.first == .text("new item"))
        #expect(updatedItems.last == .text("item 19"))
    }

    @MainActor
    @Test func clipboardHistoryDeletesExistingItemWithoutReorderingOthers() async throws {
        let items: [ClipboardHistoryItem] = [.text("first"), .text("second"), .text("third")]

        let updatedItems = ClipboardStore.historyItems(afterDeleting: .text("second"), from: items)

        #expect(updatedItems == [.text("first"), .text("third")])
    }

    @MainActor
    @Test func clipboardHistoryIgnoresDeletingMissingItem() async throws {
        let items: [ClipboardHistoryItem] = [.text("first"), .text("second")]

        let updatedItems = ClipboardStore.historyItems(afterDeleting: .text("missing"), from: items)

        #expect(updatedItems == items)
    }

    @MainActor
    @Test func pickerStateFiltersItemsCaseInsensitively() async throws {
        let state = PickerState()
        state.items = [.text("Alpha command"), .text("beta note"), .text("Another alpha")]

        state.query = "ALPHA"

        #expect(state.filteredItems == [.text("Alpha command"), .text("Another alpha")])
        #expect(state.matchCountLabel == "2 matches")
    }

    @MainActor
    @Test func pickerStateResetsSelectionWhenQueryChanges() async throws {
        let state = PickerState()
        state.items = [.text("first"), .text("second"), .text("third")]
        state.selectedIndex = 2

        state.query = "sec"

        #expect(state.selectedIndex == 0)
        #expect(state.filteredItems == [.text("second")])
    }

    @MainActor
    @Test func pickerStateReportsEmptySearchResults() async throws {
        let state = PickerState()
        state.items = [.text("first"), .text("second")]

        state.query = "missing"

        #expect(state.filteredItems.isEmpty)
        #expect(state.matchCountLabel == "No matches")
    }

    @MainActor
    @Test func pickerStatePreservesQueryAndClampsSelectionAfterDeletion() async throws {
        let state = PickerState()
        state.items = [.text("alpha one"), .text("beta"), .text("alpha two")]
        state.query = "alpha"
        state.selectedIndex = 1

        state.replaceItemsPreservingQuery([.text("alpha one"), .text("beta")])

        #expect(state.query == "alpha")
        #expect(state.filteredItems == [.text("alpha one")])
        #expect(state.selectedIndex == 0)
    }

    @MainActor
    @Test func pickerStateHandlesDeletingLastFilteredResult() async throws {
        let state = PickerState()
        state.items = [.text("alpha"), .text("beta")]
        state.query = "alpha"

        state.replaceItemsPreservingQuery([.text("beta")])

        #expect(state.query == "alpha")
        #expect(state.filteredItems.isEmpty)
        #expect(state.selectedIndex == 0)
        #expect(state.matchCountLabel == "No matches")
    }

    @MainActor
    @Test func snippetDetectorRecognizesCodeLikeSingleLineItems() async throws {
        #expect(ClipboardSnippetDetector.isCodeLike("git status --short"))
        #expect(ClipboardSnippetDetector.isCodeLike("~/Documents/apps/Copypastik"))
        #expect(ClipboardSnippetDetector.isCodeLike("{\"plain\":true}"))
        #expect(ClipboardSnippetDetector.isCodeLike("https://example.com"))
    }

    @MainActor
    @Test func snippetDetectorLeavesNaturalTextAlone() async throws {
        #expect(!ClipboardSnippetDetector.isCodeLike("This is just a copied sentence."))
        #expect(!ClipboardSnippetDetector.isCodeLike("first line\nsecond line"))
    }

    @MainActor
    @Test func itemKindDetectsSemanticClipboardTypes() async throws {
        #expect(ClipboardItemKind.detect("git status --short") == .command)
        #expect(ClipboardItemKind.detect("https://example.com") == .link)
        #expect(ClipboardItemKind.detect("let value = true") == .code)
        #expect(ClipboardItemKind.detect("first line\nsecond line") == .multiline)
        #expect(ClipboardItemKind.detect("A normal copied sentence.") == .text)
    }

    @MainActor
    @Test func itemPresentationBuildsReadableMetadata() async throws {
        let newest = ClipboardItemPresentation(text: "git status")
        let multiline = ClipboardItemPresentation(text: "first\nsecond")

        #expect(newest.metadata(isNewest: true) == "Command · 10 chars · Now")
        #expect(multiline.metadata(isNewest: false) == "Text · 2 lines")
    }

    @MainActor
    @Test func appSettingsUseExpectedDefaults() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)

        #expect(!settings.isLaunchAtLoginEnabled)
        #expect(settings.isClipboardHistoryEnabled)
        #expect(settings.historyLimit == .twenty)
        #expect(!settings.hasCompletedOnboarding)
        #expect(settings.pickerShortcut == .controlOptionV)
        #expect(!settings.isAutomaticPasteEnabled)
        #expect(settings.isPasteHintEnabled)
        #expect(settings.isTaggedSectionCollapsed)
    }

    @MainActor
    @Test func appSettingsPersistChanges() async throws {
        let defaults = temporaryDefaults()
        let settings = AppSettings(defaults: defaults, managesLaunchAtLogin: false)

        settings.isLaunchAtLoginEnabled = true
        settings.isClipboardHistoryEnabled = false
        settings.historyLimit = .fifty
        settings.pickerShortcut = .commandShiftV
        settings.isAutomaticPasteEnabled = true
        settings.isPasteHintEnabled = false
        settings.isTaggedSectionCollapsed = false
        settings.setTagColor(.rose, for: "SQL")
        settings.markOnboardingCompleted()

        let restored = AppSettings(defaults: defaults, managesLaunchAtLogin: false)
        #expect(restored.isLaunchAtLoginEnabled)
        #expect(!restored.isClipboardHistoryEnabled)
        #expect(restored.historyLimit == .fifty)
        #expect(restored.pickerShortcut == .commandShiftV)
        #expect(restored.isAutomaticPasteEnabled)
        #expect(!restored.isPasteHintEnabled)
        #expect(!restored.isTaggedSectionCollapsed)
        #expect(restored.tagColor(for: "sql") == .rose)
        #expect(restored.hasCompletedOnboarding)
    }

    @MainActor
    @Test func appSettingsFallsBackForInvalidHistoryLimit() async throws {
        let defaults = temporaryDefaults()
        defaults.set(75, forKey: "settings.historyLimit")

        let settings = AppSettings(defaults: defaults, managesLaunchAtLogin: false)

        #expect(settings.historyLimit == .twenty)
    }

    @MainActor
    @Test func appSettingsFallsBackForInvalidPickerShortcut() async throws {
        let defaults = temporaryDefaults()
        defaults.set("not-a-shortcut", forKey: "settings.pickerShortcut")

        let settings = AppSettings(defaults: defaults, managesLaunchAtLogin: false)

        #expect(settings.pickerShortcut == .controlOptionV)
    }

    @MainActor
    @Test func pickerShortcutBuildsExpectedCarbonMetadata() async throws {
        #expect(PickerShortcut.controlOptionV.displayName == "Control + Option + V")
        #expect(PickerShortcut.controlOptionV.keyCode == UInt32(kVK_ANSI_V))
        #expect(PickerShortcut.controlOptionV.carbonModifiers == UInt32(controlKey | optionKey))

        #expect(PickerShortcut.commandShiftV.displayName == "Command + Shift + V")
        #expect(PickerShortcut.commandShiftV.keyCode == UInt32(kVK_ANSI_V))
        #expect(PickerShortcut.commandShiftV.carbonModifiers == UInt32(cmdKey | shiftKey))
    }

    @MainActor
    @Test func clipboardStoreIgnoresNewItemsWhenHistoryIsDisabled() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
        settings.isClipboardHistoryEnabled = false
        let store = ClipboardStore(settings: settings, startsService: false)

        store.ingestCopiedText("Do not keep this")

        #expect(store.items.isEmpty)
    }

    @MainActor
    @Test func clipboardStoreTrimsTypedTextItems() async throws {
        let store = ClipboardStore(settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false), startsService: false)

        store.ingestCopiedItem(.text("  Keep me clean\n"))

        #expect(store.items == [.text("Keep me clean")])
    }

    @MainActor
    @Test func clipboardStoreUsesConfiguredHistoryLimit() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
        settings.historyLimit = .fifty
        let store = ClipboardStore(settings: settings, startsService: false)

        for index in 1...25 {
            store.ingestCopiedItem(.text("item \(index)"))
        }

        #expect(store.items.count == 25)
        #expect(store.items.first == .text("item 25"))
        #expect(store.items.last == .text("item 1"))
    }

    @MainActor
    @Test func clipboardStoreTrimsHistoryWhenLimitShrinks() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
        settings.historyLimit = .fifty
        let store = ClipboardStore(settings: settings, startsService: false)

        for index in 1...30 {
            store.ingestCopiedItem(.text("item \(index)"))
        }
        settings.historyLimit = .twenty

        #expect(store.items.count == 20)
        #expect(store.items.first == .text("item 30"))
        #expect(store.items.last == .text("item 11"))
    }

    @MainActor
    @Test func imageHistoryMovesRepeatedImagesToTopWithoutDuplicating() async throws {
        let redImage = ClipboardHistoryItem.image(makeImage(color: .red))
        let blueImage = ClipboardHistoryItem.image(makeImage(width: 9, height: 6, color: .blue))
        let items: [ClipboardHistoryItem] = [blueImage, redImage]

        let updatedItems = ClipboardStore.historyItems(afterAdding: redImage, to: items)

        #expect(updatedItems == [redImage, blueImage])
        #expect(Set(updatedItems.map(\.dedupKey)).count == 2)
    }

    @MainActor
    @Test func mixedHistoryKeepsConfiguredItemLimit() async throws {
        let items = (1...20).map { ClipboardHistoryItem.text("item \($0)") }
        let image = ClipboardHistoryItem.image(makeImage())

        let updatedItems = ClipboardStore.historyItems(afterAdding: image, to: items)

        #expect(updatedItems.count == ClipboardStore.historyLimit)
        #expect(updatedItems.first == image)
        #expect(updatedItems.last == .text("item 19"))
    }

    @MainActor
    @Test func imageHistoryDeletesExistingItemWithoutAffectingText() async throws {
        let image = ClipboardHistoryItem.image(makeImage())
        let items: [ClipboardHistoryItem] = [.text("first"), image, .text("third")]

        let updatedItems = ClipboardStore.historyItems(afterDeleting: image, from: items)

        #expect(updatedItems == [.text("first"), .text("third")])
    }

    @MainActor
    @Test func pickerStateFiltersImageMetadata() async throws {
        let image = ClipboardHistoryItem.image(makeImage(width: 12, height: 10))
        let state = PickerState()
        state.items = [.text("plain note"), image]

        state.query = "12x10"

        #expect(state.filteredItems == [image])
        #expect(state.matchCountLabel == "1 match")
    }

    @MainActor
    @Test func clipboardStoreIgnoresImagesWhenHistoryIsDisabled() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
        settings.isClipboardHistoryEnabled = false
        let store = ClipboardStore(settings: settings, startsService: false)

        store.ingestCopiedItem(.image(makeImage()))

        #expect(store.items.isEmpty)
    }

    @MainActor
    @Test func tagRulesNormalizeFreeFormTags() async throws {
        let tags = TagRules.normalize(" SQL, sql,  SwiftUI  , , VeryLongTagNameThatWillTrim, Images, extra")

        #expect(tags == ["sql", "swiftui", "verylongtagnamethatw", "images", "extra"])
    }

    @MainActor
    @Test func clipboardStoreTagsItemsOutsideHistoryCap() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
        let store = ClipboardStore(settings: settings, startsService: false, taggedStore: try temporaryTaggedStore())

        store.ingestCopiedItem(.text("keep forever"))
        #expect(store.setTags(for: .text("keep forever"), rawTags: "sql") == .saved)

        for index in 1...20 {
            store.ingestCopiedItem(.text("history \(index)"))
        }

        #expect(store.taggedItems.map(\.textValue) == ["keep forever"])
        #expect(store.items.count == 20)
        #expect(!store.items.contains(.text("keep forever")))
    }

    @MainActor
    @Test func clipboardStoreMergesTagsForExistingTaggedContent() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            taggedStore: try temporaryTaggedStore()
        )

        store.ingestCopiedItem(.text("select * from users"))
        store.setTags(for: .text("select * from users"), rawTags: "sql")
        store.setTags(for: .text("select * from users"), rawTags: "database, sql")

        #expect(store.taggedItems.count == 1)
        #expect(store.taggedItems.first?.tags == ["sql", "database"])
    }

    @MainActor
    @Test func clipboardStoreEnforcesTaggedLimit() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            taggedStore: try temporaryTaggedStore()
        )

        for index in 1...ClipboardStore.taggedLimit {
            store.setTags(for: .text("tagged \(index)"), rawTags: "tag")
        }

        let result = store.setTags(for: .text("one too many"), rawTags: "tag")

        #expect(result == .taggedLimitReached)
        #expect(store.taggedItems.count == ClipboardStore.taggedLimit)
    }

    @MainActor
    @Test func removingLastTagReentersHistoryAsNewest() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            taggedStore: try temporaryTaggedStore()
        )

        store.ingestCopiedItem(.text("older"))
        store.ingestCopiedItem(.text("snippet"))
        store.setTags(for: .text("snippet"), rawTags: "sql")
        store.removeAllTags(from: .text("snippet", tags: ["sql"]))

        #expect(store.taggedItems.isEmpty)
        #expect(store.items.first == .text("snippet"))
        #expect(store.items.dropFirst().first == .text("older"))
    }

    @MainActor
    @Test func deletingTaggedItemDoesNotReenterHistory() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            taggedStore: try temporaryTaggedStore()
        )

        store.setTags(for: .text("delete me"), rawTags: "temp")
        store.deleteItem(.text("delete me", tags: ["temp"]))

        #expect(store.taggedItems.isEmpty)
        #expect(store.items.isEmpty)
    }

    @MainActor
    @Test func taggedStoreSavesAndLoadsTextAndImages() async throws {
        let taggedStore = try temporaryTaggedStore()
        let image = makeImage(width: 11, height: 7)

        taggedStore.save([
            .text("select id from users", tags: ["SQL"]),
            .image(image, tags: ["Images"])
        ])

        let loaded = taggedStore.load()

        #expect(loaded.count == 2)
        #expect(loaded.contains { $0.textValue == "select id from users" && $0.tags == ["sql"] })
        #expect(loaded.contains { $0.imageValue?.dimensionsLabel == "11x7" && $0.tags == ["images"] })
    }

    @MainActor
    @Test func taggedStoreBacksUpCorruptedJSON() async throws {
        let taggedStore = try temporaryTaggedStore()
        try FileManager.default.createDirectory(at: taggedStore.directoryURL, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: taggedStore.fileURL)

        let loaded = taggedStore.load()

        #expect(loaded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: taggedStore.backupURL.path))
        #expect(!FileManager.default.fileExists(atPath: taggedStore.fileURL.path))
    }

    @MainActor
    @Test func pickerStateFiltersTaggedAndHistorySections() async throws {
        let state = PickerState()
        state.items = [.text("select plain history"), .text("meeting notes")]
        state.taggedItems = [
            .text("select tagged sql", tags: ["sql"]),
            .text("image helper", tags: ["image"])
        ]

        state.query = "#sql select"

        #expect(state.filteredTaggedItems == [.text("select tagged sql", tags: ["sql"])])
        #expect(state.filteredHistoryItems.isEmpty)
        #expect(state.filteredItems == [.text("select tagged sql", tags: ["sql"])])
    }

    @MainActor
    @Test func pickerStateBuildsChipsFromCurrentTags() async throws {
        let state = PickerState()
        state.taggedItems = [
            .text("one", tags: ["sql", "swift"]),
            .text("two", tags: ["sql"])
        ]

        #expect(state.tagChips == ["sql", "swift"])

        state.taggedItems = [.text("two", tags: ["sql"])]

        #expect(state.tagChips == ["sql"])
    }

    @MainActor
    @Test func pickerStateKeepsTagChipsHiddenUntilFocusedOrFiltered() async throws {
        let state = PickerState()
        state.taggedItems = [.text("one", tags: ["sql"])]

        #expect(!state.isTagFilterBarVisible)

        state.focusTagChips()
        #expect(state.isTagFilterBarVisible)

        state.leaveTagBrowser()
        state.query = "#sql"
        #expect(state.isTagFilterBarVisible)
    }

    @MainActor
    @Test func pickerStateTagChipsStartWithAllAndArrowingAppliesFilters() async throws {
        let state = PickerState()
        state.isTaggedSectionCollapsed = true
        state.taggedItems = [
            .text("sql snippet", tags: ["sql"]),
            .text("swift snippet", tags: ["swift"])
        ]
        state.items = [.text("recent history")]

        #expect(state.tagFilterChips.map(\.title) == ["All", "#sql", "#swift"])

        state.focusTagChips()
        #expect(state.isTagChipActive(.all))
        #expect(state.filteredItems.compactMap(\.textValue) == ["sql snippet", "swift snippet"])

        state.moveFocusedTagChip(by: 1)
        #expect(state.isTagChipActive(.tag("sql")))
        #expect(state.filteredItems.compactMap(\.textValue) == ["sql snippet"])

        state.moveFocusedTagChip(by: 1)
        #expect(state.isTagChipActive(.tag("swift")))
        #expect(state.filteredItems.compactMap(\.textValue) == ["swift snippet"])
    }

    @MainActor
    @Test func pickerStateStartsSelectionOnNewestHistoryWhenTaggedIsExpanded() async throws {
        let state = PickerState()
        state.prepareForPresentation(
            with: [.text("newest history"), .text("older history")],
            taggedItems: [.text("tagged one", tags: ["sql"])],
            isTaggedSectionCollapsed: false
        )

        #expect(state.filteredItems.compactMap(\.textValue) == ["tagged one", "newest history", "older history"])
        #expect(state.selectedIndex == 1)
    }

    @MainActor
    @Test func pickerStateFocusesTagChipsWhenMovingUpFromFirstHistoryRow() async throws {
        let state = PickerState()
        state.prepareForPresentation(
            with: [.text("newest history"), .text("older history")],
            taggedItems: [
                .text("tagged one", tags: ["sql"]),
                .text("tagged two", tags: ["swift"])
            ],
            isTaggedSectionCollapsed: false
        )

        #expect(state.selectedIndex == 2)
        #expect(state.shouldFocusTagChipsOnUp)

        state.selectedIndex = 3
        #expect(!state.shouldFocusTagChipsOnUp)
    }

    @MainActor
    @Test func pickerStateShowsTaggedRowsForTagFiltersEvenWhenCollapsed() async throws {
        let state = PickerState()
        state.isTaggedSectionCollapsed = true
        state.taggedItems = [.text("select tagged sql", tags: ["sql"])]

        #expect(state.filteredTaggedItems.isEmpty)

        state.query = "#sql"
        #expect(state.filteredTaggedItems == [.text("select tagged sql", tags: ["sql"])])
    }

    @MainActor
    @Test func pickerStateDoesNotCapGlobalTagChips() async throws {
        let state = PickerState()
        state.taggedItems = (1...7).map { .text("item \($0)", tags: ["tag\($0)"]) }

        #expect(state.tagChips == ["tag1", "tag2", "tag3", "tag4", "tag5", "tag6", "tag7"])
    }

    @MainActor
    @Test func tagShortcutUsesPhysicalKeyWithNonLatinKeyboardLayout() async throws {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: "е",
            charactersIgnoringModifiers: "е",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_T)
        )
        #expect(event != nil)
        if let event {
            #expect(PickerWindowController.isTagEditShortcut(event))
        }
    }

    // MARK: - Smart Recall (1.3)

    @MainActor
    @Test func searchQueryParsesTagAppTypeAndText() async throws {
        let query = PickerSearchQuery("@Safari type:link #design apple")

        #expect(query.appQueries == ["Safari"])
        #expect(query.typeFilter == .link)
        #expect(query.tags == ["design"])
        #expect(query.text == "apple")
    }

    @MainActor
    @Test func searchQueryIgnoresUnknownTypeToken() async throws {
        let query = PickerSearchQuery("type:bogus hello")

        #expect(query.typeFilter == nil)
        #expect(query.text == "type:bogus hello")
    }

    @MainActor
    @Test func typeFilterMatchesTextAndMultilineUnderTextChip() async throws {
        #expect(PickerTypeFilter.text.matches(.text))
        #expect(PickerTypeFilter.text.matches(.multiline))
        #expect(!PickerTypeFilter.text.matches(.code))
        #expect(PickerTypeFilter.all.matches(.image))
    }

    @MainActor
    @Test func itemMatchesSourceAppQueryByNameOrBundleID() async throws {
        let item = ClipboardHistoryItem.text("hello", sourceAppName: "Safari", sourceAppBundleID: "com.apple.Safari")

        #expect(item.matchesSourceAppQuery("safari"))
        #expect(item.matchesSourceAppQuery("com.apple.safari"))
        #expect(!item.matchesSourceAppQuery("xcode"))
    }

    @MainActor
    @Test func pickerStateFiltersByAppAndTypeQuery() async throws {
        let state = PickerState()
        state.items = [
            .text("https://example.com", sourceAppName: "Safari", sourceAppBundleID: "com.apple.Safari"),
            .text("git status", sourceAppName: "Xcode", sourceAppBundleID: "com.apple.dt.Xcode")
        ]

        state.query = "@Safari type:link"

        #expect(state.filteredItems.map(\.textValue) == ["https://example.com"])
    }

    @MainActor
    @Test func pickerStateTypeChipFiltersHistoryItems() async throws {
        let state = PickerState()
        state.items = [.text("git status --short"), .text("a plain sentence")]

        state.selectTypeFilter(.command)

        #expect(state.filteredItems.map(\.textValue) == ["git status --short"])

        state.selectTypeFilter(.all)
        #expect(state.filteredItems.count == 2)
    }

    @MainActor
    @Test func pickerStateShowsPinnedItemsAboveTaggedAndHistory() async throws {
        let state = PickerState()
        state.items = [.text("history item")]
        state.taggedItems = [.text("tagged item", tags: ["sql"])]
        state.pinnedItems = [ClipboardHistoryItem.text("pinned item").withPinned(true)]

        #expect(state.filteredItems.compactMap(\.textValue) == ["pinned item", "tagged item", "history item"])
    }

    @MainActor
    @Test func pickerStateHidesPinnedItemFromItsOriginalSection() async throws {
        let state = PickerState()
        let item = ClipboardHistoryItem.text("shared item")
        state.items = [item]
        state.pinnedItems = [item.withPinned(true)]

        #expect(state.filteredHistoryItems.isEmpty)
        #expect(state.filteredPinnedItems.map(\.textValue) == ["shared item"])
    }

    @MainActor
    @Test func clipboardStoreTogglesPinAndPersistsAcrossRestarts() async throws {
        let pinnedStore = try temporaryPinnedStore()
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: pinnedStore
        )

        store.ingestCopiedItem(.text("keep me pinned"))
        let item = try #require(store.items.first)

        let isPinned = store.togglePin(item)
        #expect(isPinned)
        #expect(store.pinnedItems.map(\.textValue) == ["keep me pinned"])

        let reloaded = pinnedStore.load()
        #expect(reloaded.map(\.textValue) == ["keep me pinned"])
        #expect(reloaded.first?.isPinned == true)
    }

    @MainActor
    @Test func clipboardStoreAssignsAndReassignsQuickSlots() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        store.ingestCopiedItem(.text("first"))
        store.ingestCopiedItem(.text("second"))
        store.togglePin(.text("first"))
        store.togglePin(.text("second"))

        store.assignPinnedSlot(1, to: .text("first"))
        #expect(store.pinnedItem(forSlot: 1)?.textValue == "first")

        store.assignPinnedSlot(1, to: .text("second"))
        #expect(store.pinnedItem(forSlot: 1)?.textValue == "second")
        #expect(store.pinnedItems.first(where: { $0.textValue == "first" })?.pinnedSlot == nil)
    }

    @MainActor
    @Test func clipboardStoreKeepsPinnedItemAfterClearingHistory() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        store.ingestCopiedItem(.text("keep forever"))
        store.togglePin(.text("keep forever"))
        store.clearHistory()

        #expect(store.items.isEmpty)
        #expect(store.pinnedItems.map(\.textValue) == ["keep forever"])
    }

    @MainActor
    @Test func clipboardStoreDeletingPinnedRowRemovesItEverywhere() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        store.ingestCopiedItem(.text("delete me"))
        store.togglePin(.text("delete me"))

        // Trash is destructive: the pinned copy and the hidden history copy
        // both go, so the clip does not pop back into the History section.
        store.deleteItem(.text("delete me"))

        #expect(store.pinnedItems.isEmpty)
        #expect(store.items.isEmpty)
    }

    @MainActor
    @Test func togglePinAutoAssignsLowestFreeSlot() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        store.togglePin(.text("a"))
        store.togglePin(.text("b"))

        #expect(store.pinnedItem(forSlot: 1)?.textValue == "a")
        #expect(store.pinnedItem(forSlot: 2)?.textValue == "b")

        // Unpinning frees the slot; the next pin reuses it.
        store.togglePin(.text("a"))
        store.togglePin(.text("c"))

        #expect(store.pinnedItem(forSlot: 1)?.textValue == "c")
        #expect(store.pinnedItem(forSlot: 2)?.textValue == "b")
    }

    @MainActor
    @Test func togglePinKeepsSlotOrderStable() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        store.togglePin(.text("first"))
        store.togglePin(.text("second"))
        store.togglePin(.text("third"))

        // New pins append in slot order instead of jumping to the top.
        #expect(store.pinnedItems.map(\.textValue) == ["first", "second", "third"])
        #expect(store.pinnedItems.map(\.pinnedSlot) == [1, 2, 3])
    }

    @MainActor
    @Test func tenthPinGetsNoSlot() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        for index in 1...10 {
            store.togglePin(.text("clip \(index)"))
        }

        #expect(store.pinnedItems.count == 10)
        #expect(store.pinnedSlot(for: .text("clip 10")) == nil)
        #expect(store.pinnedSlot(for: .text("clip 9")) == 9)
    }

    @MainActor
    @Test func unpinningOrphanPinnedItemReinsertsIntoHistory() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        // Pinned directly without ever being in history (e.g. loaded from
        // disk after a restart). Unpinning must not silently destroy it.
        store.togglePin(.text("orphan"))
        store.togglePin(.text("orphan"))

        #expect(store.pinnedItems.isEmpty)
        #expect(store.items.map(\.textValue) == ["orphan"])
    }

    @MainActor
    @Test func ingestingPinnedContentDoesNotDuplicateHistory() async throws {
        let store = ClipboardStore(
            settings: AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false),
            startsService: false,
            pinnedStore: try temporaryPinnedStore()
        )

        store.ingestCopiedItem(.text("x"))
        store.togglePin(.text("x"))
        store.ingestCopiedItem(.text("x"))

        #expect(store.items.count == 1)
        #expect(store.pinnedItems.count == 1)
    }

    @MainActor
    @Test func clipboardStoreIgnoresItemsWhileCapturePaused() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
        let store = ClipboardStore(settings: settings, startsService: false)

        settings.pauseCapture(for: .untilResumed)
        store.ingestCopiedText("should not be saved")

        #expect(store.items.isEmpty)

        settings.resumeCapture()
        store.ingestCopiedText("should be saved")
        #expect(store.items.map(\.textValue) == ["should be saved"])
    }

    @MainActor
    @Test func clipboardStoreIgnoresItemsFromIgnoredApps() async throws {
        let settings = AppSettings(defaults: temporaryDefaults(), managesLaunchAtLogin: false)
        settings.addIgnoredApp(bundleID: "com.example.blocked")
        let store = ClipboardStore(settings: settings, startsService: false)

        store.ingestCopiedItem(.text("secret", sourceAppName: "Blocked", sourceAppBundleID: "com.example.blocked"))

        #expect(store.items.isEmpty)
    }

    @MainActor
    @Test func appSettingsSeedsDefaultSensitiveAppsAndSupportsEditing() async throws {
        let defaults = temporaryDefaults()
        let settings = AppSettings(defaults: defaults, managesLaunchAtLogin: false)

        #expect(settings.isAppIgnored(bundleID: "com.apple.Passwords"))

        settings.removeIgnoredApp(bundleID: "com.apple.Passwords")
        #expect(!settings.isAppIgnored(bundleID: "com.apple.Passwords"))

        settings.addIgnoredApp(bundleID: "com.example.app")
        let restored = AppSettings(defaults: defaults, managesLaunchAtLogin: false)
        #expect(restored.isAppIgnored(bundleID: "com.example.app"))
        #expect(!restored.isAppIgnored(bundleID: "com.apple.Passwords"))
    }

    @MainActor
    @Test func appSettingsPauseCaptureUntilResumedPersistsAndResumes() async throws {
        let defaults = temporaryDefaults()
        let settings = AppSettings(defaults: defaults, managesLaunchAtLogin: false)

        settings.pauseCapture(for: .untilResumed)
        #expect(settings.isCapturePaused)

        let restored = AppSettings(defaults: defaults, managesLaunchAtLogin: false)
        #expect(restored.isCapturePaused)

        restored.resumeCapture()
        #expect(!restored.isCapturePaused)
    }
}

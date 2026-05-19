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

    @MainActor
    @Test func clipboardHistoryMovesRepeatedItemsToTop() async throws {
        let items = ["text 2", "text 1"]

        let updatedItems = ClipboardStore.historyItems(afterAdding: "text 1", to: items)

        #expect(updatedItems == ["text 1", "text 2"])
    }

    @MainActor
    @Test func clipboardHistoryDoesNotDuplicateRepeatedItems() async throws {
        let items = ["text 2", "text 1"]

        let updatedItems = ClipboardStore.historyItems(afterAdding: "text 1", to: items)

        #expect(updatedItems.count == 2)
        #expect(Set(updatedItems).count == 2)
    }

    @MainActor
    @Test func clipboardHistoryTrimsTextAndIgnoresEmptyItems() async throws {
        let items = ["existing"]

        let trimmedItems = ClipboardStore.historyItems(afterAdding: "  new text\n", to: items)
        let emptyItems = ClipboardStore.historyItems(afterAdding: "   \n", to: items)

        #expect(trimmedItems == ["new text", "existing"])
        #expect(emptyItems == items)
    }

    @MainActor
    @Test func clipboardHistoryKeepsConfiguredItemLimit() async throws {
        let items = (1...20).map { "item \($0)" }

        let updatedItems = ClipboardStore.historyItems(afterAdding: "new item", to: items)

        #expect(updatedItems.count == ClipboardStore.historyLimit)
        #expect(updatedItems.first == "new item")
        #expect(updatedItems.last == "item 19")
    }

    @MainActor
    @Test func clipboardHistoryDeletesExistingItemWithoutReorderingOthers() async throws {
        let items = ["first", "second", "third"]

        let updatedItems = ClipboardStore.historyItems(afterDeleting: "second", from: items)

        #expect(updatedItems == ["first", "third"])
    }

    @MainActor
    @Test func clipboardHistoryIgnoresDeletingMissingItem() async throws {
        let items = ["first", "second"]

        let updatedItems = ClipboardStore.historyItems(afterDeleting: "missing", from: items)

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

        #expect(settings.isLaunchAtLoginEnabled)
        #expect(settings.isClipboardHistoryEnabled)
        #expect(settings.historyLimit == .twenty)
        #expect(!settings.hasCompletedOnboarding)
        #expect(settings.pickerShortcut == .controlOptionV)
    }

    @MainActor
    @Test func appSettingsPersistChanges() async throws {
        let defaults = temporaryDefaults()
        let settings = AppSettings(defaults: defaults, managesLaunchAtLogin: false)

        settings.isLaunchAtLoginEnabled = false
        settings.isClipboardHistoryEnabled = false
        settings.historyLimit = .fifty
        settings.pickerShortcut = .commandShiftV
        settings.markOnboardingCompleted()

        let restored = AppSettings(defaults: defaults, managesLaunchAtLogin: false)
        #expect(!restored.isLaunchAtLoginEnabled)
        #expect(!restored.isClipboardHistoryEnabled)
        #expect(restored.historyLimit == .fifty)
        #expect(restored.pickerShortcut == .commandShiftV)
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
}

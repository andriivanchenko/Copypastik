# Copypastik

A polished macOS menu bar app that keeps a text and image clipboard history and lets you paste any item with a global keyboard shortcut.

## Features

- Stores the last 20 copied text or bitmap image items
- Re-copying an existing item moves it back to the top instead of duplicating it
- Global shortcut **Control + Option + V** opens a floating picker above the current app
- Real-time search/filter across clipboard history
- Keyboard navigation (↑ ↓ ← Enter Esc), mouse selection, and inline item deletion
- Polished floating picker with native material, subtle animation, hover states, and reduced-motion support
- Semantic clipboard rows with icons for links, commands, code-like snippets, multi-line text, plain text, and image thumbnails
- Match count, keyboard hint footer, and warm empty states
- Menu bar history view with the same row style and one-click copy confirmation
- Click outside the picker to close it
- Pastes text as **plain text** and bitmap images as image data; rich text, fonts, formatting, and copied files are ignored
- No Dock icon, runs entirely in the menu bar
- Custom app icon and compact menu bar icon
- Registers itself for launch at login
- No external dependencies

## Requirements

- macOS 13 or later
- Xcode 15 or later (to build from source)
- **Accessibility permission** — required for the global hotkey and instant paste

## Setup

### 1. Build and run

Open `Copypastik.xcodeproj` in Xcode, select the `Copypastik` scheme, and press **Run**.

Copypastik is configured as a menu bar agent app, so it does not appear in the Dock after launch. Use the menu bar icon to open its history window.

### 2. Grant Accessibility permission

On first launch, Copypastik checks Accessibility access and requests it if needed.

If it does not, go to:

> System Settings → Privacy & Security → Accessibility → enable Copypastik

Restart the app after granting permission.

### 3. Optional: verify launch at login

Copypastik registers itself as a login item on launch. You can confirm this in:

> System Settings → General → Login Items

## Usage

| Action | How |
|---|---|
| Open clipboard picker | **Control + Option + V** |
| Filter history | Type in the search field |
| Navigate results | **↑ / ↓** arrow keys |
| Paste selected item | **Enter** |
| Reveal item delete action | **←** on selected row, or right-click a row |
| Delete revealed item | Press **←** again, or click the revealed trash button |
| Hide delete action | **→**, change selection, or continue typing |
| Close without pasting | **Esc** |
| Close picker | Click anywhere outside the picker |
| Paste with mouse | Click any row |
| Clear all history | Picker trash button, or menu bar icon → **Clear History** |

The selected row is the default action. Pressing **Enter** briefly confirms the row, writes it back to the clipboard, closes the picker, and simulates **Cmd + V** into the previously active app. Paste confirmation is guarded so one Enter press results in one paste.

Individual deletion is reveal-first: the first left-arrow press or right-click exposes a trash action on the row; confirming it slides the row away and removes that item from history without changing the system clipboard. Active search text stays in place after deletion.

If Accessibility permission is missing, the item is still copied to the clipboard — you can paste it manually with Cmd + V.

## Interface details

- Picker rows reserve stable space for the return glyph, so long snippets do not reflow when the selection changes.
- Picker rows expose a compact trash action with a swipe-like slide animation for individual deletion.
- The newest item gets a small accent dot when browsing the unfiltered history.
- Commands and code-like snippets use monospaced typography; links, text, and multi-line content use standard system text; image rows show compact thumbnails with dimensions.
- The picker uses subtle scale/fade open and close animations. When macOS Reduce Motion is enabled, motion is reduced to short opacity changes.
- The menu bar view mirrors the picker row language so the app feels consistent whether opened from the hotkey or menu bar icon.

## Architecture

```
CopypastikApp.swift          App entry point, MenuBarExtra scene, launch-at-login setup
AppCoordinator              Owns all long-lived services
│
├── ClipboardStore          ObservableObject — typed history list, recency dedup, delete, 20-item cap
│   └── PasteboardService   Polls NSPasteboard.changeCount every 0.5 s
│
├── HotkeyService           Carbon global hotkey registration for Ctrl+Opt+V
│
└── PickerWindowController  Floating NSPanel lifecycle, keyboard/delete routing, outside-click dismiss, CGEvent paste
    └── PickerState         ObservableObject shared with SwiftUI view
        └── ClipboardPickerView   Search field + semantic filtered picker UI + inline row deletion
```

### Key design decisions

- **Polling vs. event tap** — `NSPasteboard` has no change notification API; polling `changeCount` at 0.5 s is the standard approach and is lightweight.
- **Carbon hotkey registration** — `RegisterEventHotKey` captures `Control + Option + V` without leaking the literal `v` keystroke into the previously active app.
- **Menu bar agent mode** — `LSUIElement` is enabled through generated Info.plist build settings, so Copypastik runs without a Dock icon while keeping its `MenuBarExtra`.
- **Asset catalog icons** — the app icon lives in `AppIcon.appiconset`; the menu bar image lives in `MenuBarIcon.imageset` and is referenced from `MenuBarExtra`.
- **`FloatingPanel` subclass** — a borderless `NSPanel` with `canBecomeKey = true` allows keyboard input without showing window chrome.
- **Outside-click dismissal** — the picker panel closes on `windowDidResignKey`, so clicking anywhere else dismisses it immediately.
- **Focus trigger pattern** — `PickerState.searchFocusTrigger` is an `Int` that increments on each `show()`. The SwiftUI view's `onChange` fires and sets `@FocusState`, reliably re-focusing the search field even though the panel is reused across invocations.
- **One-shot paste confirmation** — Enter can be observed by both the local key monitor and SwiftUI submit handling, so the controller guards selection with an in-flight flag to prevent duplicate paste events.
- **Stable row layout** — the return glyph slot is always reserved and animated with opacity/scale, preventing long text from rewrapping when a row becomes selected.
- **Typed history items** — history stores plain text and normalized bitmap images in memory for the current app session.
- **Recency deduplication** — copying an item that already exists removes the old copy and inserts the item at the top, keeping history unique while preserving recency.
- **Reveal-first deletion** — individual item deletion requires an explicit reveal via left arrow or right-click, then confirmation via left arrow or the trash button. This keeps accidental deletion unlikely without adding confirmation dialogs.
- **Semantic item presentation** — clipboard text is classified as link, command, code-like snippet, multi-line text, or plain text, while image rows show thumbnails, dimensions, and format metadata.
- **Reduced motion support** — picker scale/stagger effects are disabled when macOS Reduce Motion is enabled.
- **Self-write suppression** — when Copypastik writes a selected item back to the clipboard, `PasteboardService` records the exact `changeCount` and skips that notification so the item is not re-added to history.
- **Supported clipboard payloads** — text writes use `NSPasteboard.PasteboardType.string`; bitmap images are normalized and written as image data. Rich text, copied files, and mixed payloads are ignored in this version.

## Verification

Useful local checks:

- Build app target without signing: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build -project Copypastik.xcodeproj -scheme Copypastik -destination 'platform=macOS' -derivedDataPath /tmp/CopypastikDerivedData CODE_SIGNING_ALLOWED=NO`
- Run focused unit tests: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project Copypastik.xcodeproj -scheme Copypastik -destination 'platform=macOS' -derivedDataPath /tmp/CopypastikDerivedDataUnitEsc CODE_SIGNING_ALLOWED=NO -only-testing:CopypastikTests -skip-testing:CopypastikUITests`

The full scheme includes the placeholder UI test target, which may require local signing/UI test setup before it can run end to end.

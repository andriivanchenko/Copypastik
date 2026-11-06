# App Store Submission — Copypastik 1.2.0

## Build

- App version: `1.2.0`
- Current build number: `11`
- Bundle ID: `com.ivanchenko.Copypastik`
- Platform: macOS 14 or later

Use build `11` only if it has not already been uploaded to App Store Connect. If build `11` was previously uploaded, increment `CURRENT_PROJECT_VERSION` before creating the archive.

## Description

Copypastik is a fast, local-first clipboard history and snippets app for macOS. It lives quietly in your menu bar, keeps recent text and images handy, and lets you bring them back into your workflow with a keyboard-first floating picker.

Press Control + Option + V to open the picker, search your clipboard history, choose an item with the arrow keys, and press Enter. The selected item is instantly ready to paste with Command-V.

When something is worth keeping, press Command-T to turn it into a tagged snippet. Tagged snippets stay available across app restarts, can be found with #tag search or filter chips, and can be organized with color-coded tags. You can also access saved snippets by tag directly from the menu bar.

Copypastik is built for small everyday moments: reusing a command, finding a link again, pasting a screenshot, restoring a paragraph you copied a few minutes ago, or keeping frequently used text and images close at hand.

Features:

- Text and image clipboard history
- Tagged snippets that stay available across app restarts
- Fast search across history and saved snippets
- #tag search and keyboard-friendly tag filters
- Color-coded tags for quick visual organization
- Keyboard navigation with arrow keys, Enter, Command-T, and Esc
- Plain-text paste for copied text
- Smart deduplication that keeps repeated items tidy
- Inline deletion and separate clearing for history and tagged snippets
- Configurable history size: 20, 50, or 100 items
- Configurable picker shortcut
- Optional Automatic Paste, off by default
- Optional launch at login
- Native menu bar experience with no Dock clutter

Privacy is central to Copypastik. Clipboard history is saved locally on your Mac (in the app's Application Support storage) so the Library survives restarts; it is bounded by the history-size setting and can be switched to memory-only in Settings. Clips captured while capture is paused or from ignored apps are never recorded. Image text recognition runs on-device with Apple's Vision framework. Copypastik does not use accounts, analytics, cloud sync, advertising, or external network services.

## Promotional Text

Turn important clipboard items into tagged snippets, find them with #tag search and filter chips, and organize them with color-coded tags — privately on your Mac.

## What’s New in This Version

Copypastik now lets you turn important clipboard items into tagged snippets that stay available across app restarts.

- Add and edit tags directly in the clipboard picker.
- Search with #tag or browse snippets using tag filter chips.
- Assign colors to tags for quicker visual recognition.
- Access saved snippets by tag directly from the menu bar.
- Improved picker navigation, onboarding, and manual paste hints.

Regular clipboard history remains temporary and is cleared when Copypastik quits. Only items explicitly tagged by the user are stored locally on the Mac.

## Notes for Reviewer

Copypastik is a local macOS clipboard history and snippets app. It has no account, login, subscription, analytics, advertising, cloud sync, or network service.

No privacy permission prompt appears at launch. The primary clipboard history and picker workflow does not require privacy permission.

How to test:

1. Launch Copypastik. It appears only in the macOS menu bar.
2. Copy plain text or an image in any app.
3. Click the Copypastik menu bar icon to view recent items, or press Control + Option + V to open the floating picker.
4. Select an item in the picker and press Command + T.
5. Enter one or more comma-separated tags and press Enter. The item appears in the Tagged section.
6. Search by content, type #tag, or use the tag filter chips. Right-click a tag chip to choose its color.
7. Quit and relaunch Copypastik. The tagged snippet remains available.
8. Select an item and press Enter. The item is placed on the clipboard, the picker closes, focus returns to the previously active app, and a brief “Copied! ⌘V to paste” hint appears.
9. Paste with Command + V.
10. Right-click the Copypastik menu bar icon and open Snippets to access saved snippets by tag.

The primary clipboard workflow does not require privacy permission. Copypastik detects clipboard changes through NSPasteboard.changeCount and registers its global shortcut with Carbon RegisterEventHotKey. It does not monitor general keyboard input.

Clipboard history, tagged snippets and pinned clips are stored locally in Application Support so they can persist across restarts (history persistence can be turned off in Settings, which deletes the saved file). Image text recognition uses Apple's on-device Vision framework. This data is not transmitted or shared.

Right-click the menu bar icon and open Settings to configure the shortcut, history size, launch at login, paste hint, Automatic Paste, or to clear regular history and tagged snippets separately.

Automatic Paste is off by default. Without it, choosing an item copies it to the clipboard, restores the previous app, and the user pastes manually with Command + V.

If the user enables Automatic Paste, Copypastik checks whether macOS already allows Core Graphics PostEvent access. The app never triggers a system permission prompt. If access is missing, an in-app explanation appears with Open System Settings and Not Now buttons. Choosing Not Now or closing the sheet turns Automatic Paste back off, and the app continues to work with manual Command + V paste as described above.

Copypastik does not inspect or control other apps, use event taps, record the screen, or monitor keyboard input. When Automatic Paste is enabled and access is granted, it posts only the standard Command + V shortcut after the user selects a clipboard item.

## App Privacy

- Data collected: None
- Tracking: No
- Data linked to the user: None
- Clipboard history: Stored locally on the Mac (optional; memory-only mode available in Settings)
- Tagged snippets: Stored locally on the user’s Mac only
- Network access: None

## Submission Checklist

- Run unit tests and a Release build.
- Verify tagging for both text and image items.
- Verify tagged snippets survive an app restart.
- Verify clearing history does not remove tagged snippets.
- Verify `Clear Tagged Snippets` removes persisted snippets.
- Verify the app works when Automatic Paste permission is not granted.
- Create an Xcode Archive using the `Copypastik` scheme.
- Distribute the archive with `App Store Connect` and upload it.
- Wait for App Store Connect processing, then select the uploaded build for version `1.2.0`.
- Complete export compliance, content rights, age rating, privacy, screenshots, and availability fields.
- Paste the review notes above and submit the version for review.

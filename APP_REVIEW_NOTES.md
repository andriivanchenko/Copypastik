# App Review Notes

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

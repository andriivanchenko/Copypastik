# App Review Notes

Copypastik is a local macOS clipboard history app. The primary flow does not require any privacy permission: the app records clipboard changes through `NSPasteboard.changeCount`, opens the picker with Carbon `RegisterEventHotKey`, writes the selected item back to `NSPasteboard.general`, closes its panel, and restores focus to the previously active app.

Automatic Paste is optional and off by default. If the user enables it, Copypastik checks the current Core Graphics PostEvent access state without prompting. If access is already granted, the app posts only the standard `Command-V` shortcut after a user selects a clipboard item.

Copypastik never programmatically requests this access. If access is missing, Settings shows an in-app explanation with an explicit user-controlled button to open System Settings. The app does not inspect or control other apps, monitor general keyboard input, listen with event taps, or perform screen recording. The only posted events are V key down/up events with the Command modifier for the user-initiated paste action, and only after the existing access state is granted.

If PostEvent access is denied or unavailable, selected items are still copied to the clipboard, focus returns to the previous app, and users can paste manually with the system `Command-V` shortcut.

# SpaceNameBar

Name your virtual desktops and see the current Space name in the menu bar, with click-to-switch.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License MIT](https://img.shields.io/badge/License-MIT-green)
![GitHub release](https://img.shields.io/github/v/release/turhe123/space-name-bar)

## Why

macOS only calls your Spaces "Desktop 1", "Desktop 2" and so on, and gives no visible indicator of which one you are on. SpaceNameBar is a free, open-source, 100% native, backend-free alternative to paid utilities in the *Menu Bar Utility* category (inspired by Deskspace, $6 one-time). It has no accounts, no servers, no analytics and no network access. Names are stored locally in your user defaults.

## Features

- **Current Space in the menu bar**: shows the Space number, its custom name, or both (Number and name / Number only / Name only).
- **Custom names and emoji**: double-click a Space in the dropdown to rename it and give it an optional emoji prefix. Names are saved per Space UUID, so reordering Spaces in Mission Control keeps names correct.
- **Click-to-switch**: click a row to jump to that Space. This works by posting your "Switch to Desktop N" keyboard shortcuts (the configured shortcut is read from system settings, with the macOS defaults as fallback).
- **Full-screen Spaces**: full-screen app Spaces are labeled with the app's name, and clicking one activates that app.
- **Window counts**: an optional badge on each row shows how many app windows live on that Space (windows that appear on every Space are not counted).
- **Multiple displays**: shows the Spaces of the menu bar display by default, with a setting to list every display.
- **Settings**: display format, maximum title length (5–40), window counts toggle, all-displays toggle, a shortcuts checklist with a button that opens Keyboard Shortcuts settings, and launch at login.
- **Getting-started checklist**: on first launch it shows whether Space detection, the Switch to Desktop shortcuts and Accessibility access are in place.
- **Graceful fallback**: if the window-server lookup is unavailable on a future macOS, it falls back to the Dock's saved layout (which may lag behind, with window counts disabled) and says so in Settings.
- Handles up to 16 Spaces, and debounces refreshes during the Space-switch animation.

## Screenshots

_Screenshots coming soon._

## Install

1. Download `SpaceNameBar-macOS.zip` from the [latest release](https://github.com/turhe123/space-name-bar/releases/latest).
2. Unzip it and move `SpaceNameBar.app` to `/Applications`.
3. Because the app is open source and not notarized, clear the quarantine flag:

   ```bash
   xattr -cr /Applications/SpaceNameBar.app
   ```

4. Right-click the app and choose **Open** the first time.

For click-to-switch, enable the "Switch to Desktop N" shortcuts under System Settings › Keyboard › Keyboard Shortcuts › Mission Control, and grant Accessibility access (see below).

## Build from source

Requires Xcode with a macOS 14+ SDK.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project SpaceNameBar.xcodeproj -scheme SpaceNameBar -configuration Release -derivedDataPath ./build build
```

The app is produced at `build/Build/Products/Release/SpaceNameBar.app`.

## Permissions

- **Accessibility** (only for click-to-switch): needed to post the Control+number keyboard shortcuts that make macOS change Space. The app asks for it when you first click a Space or press Grant in the checklist. Without it, the menu bar name, renaming and everything else still work.
- **Keyboard shortcuts**: not a permission, but click-to-switch needs the "Switch to Desktop N" shortcuts enabled in System Settings. The app only reads the shortcut settings and never changes them.
- **Launch at login** (optional): registered through the system login items API when you turn it on.

SpaceNameBar does **not** request Screen Recording or Microphone access, and it makes no network connections. Window counts use only window bounds and owner information, not window contents or titles.

It also reads the window server's Space information through system symbols loaded at runtime. These are not public APIs, so a future macOS update could change them (see the fallback mode above).

## Support ❤️

SpaceNameBar is free and always will be. If it's useful to you, you can support its development:

[Support Or (Leo) Davidai ❤️](https://ko-fi.com/leodavidai)

## License

MIT © Or Davidai Bachar

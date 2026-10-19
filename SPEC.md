# SpaceNameBar — specification

**Tagline:** Name your virtual desktops and see the current Space name in the menu bar, with click-to-switch.

**Category:** Menu Bar Utility

**Inspired by (paid):** Deskspace ($6 one-time)

**Frameworks:** SwiftUI, AppKit, CoreGraphics, Carbon, ServiceManagement

**Donation URL (Support button):** https://ko-fi.com/leodavidai

## Spec

(1) What the paid app does. Deskspace, listed on Setapp and sold standalone from around 6 dollars, adds a menu bar switcher for macOS Spaces and shows which apps live on each. Related small paid apps such as Desktop Space Renamer sell for about 5 dollars on the Mac App Store, and free tools like WhichSpace and Spaceman have devoted followers. Together they show steady demand because macOS names Spaces only Desktop 1, Desktop 2 and so on, and offers no visible indicator of the current one. Our clean-room version supplies naming, a current-Space indicator and quick switching.

(2) Feature set. The menu bar shows the current Space number and its custom name, for example 2 Writing. A dropdown lists every Space on the active display with its name, a dot for the current Space, and the count of visible app windows detected there. Clicking a row jumps to that Space by posting the system Control-number keyboard shortcut, which requires the user to have Switch to Desktop N shortcuts enabled. Names are editable inline. Options include showing only the number, only the name, or both, and per-Space emoji prefix.

(3) UI spec. MenuBarExtra using a text label. The menu is a vertical list of Space rows with an inline text field that becomes editable on double-click, then Settings and Quit. Settings fields: display format picker, maximum title length stepper, show window counts toggle, keyboard shortcut helper section with a button that opens the Keyboard Shortcuts pane in system settings, and launch at login toggle. Empty state: if the app cannot determine the Space index, the label shows a plain Spaces icon and the menu explains how to enable detection. First launch includes a short checklist view showing whether the Control-number shortcuts are available.

(4) Technical approach. Listen for the NSWorkspace activeSpaceDidChangeNotification to refresh. Discovering the Space index and the ordered Space list has no fully public API, so read the spaces preferences property list of the Dock domain using UserDefaults, which describes monitors and their space identifiers, and read the current Space identifier by comparing against the windows reported by CGWindowListCopyWindowInfo with the on-screen-only option and the Space-aware window numbers. A simpler robust method is to dlopen the CoreGraphics services symbols for the active Space identifier and managed display Spaces, wrapping them behind a small protocol with a graceful fallback to count-only mode if the symbols are unavailable. Names are persisted in UserDefaults keyed by Space universally unique identifier, not index, so reordering keeps names correct. Switching posts keyboard events using CGEvent with the control flag and the digit key code, which needs Accessibility permission, requested via AXIsProcessTrustedWithOptions. Launch at login uses SMAppService.

(5) Edge cases. Full-screen apps create their own Spaces and should be labeled with the app name. Multiple displays with separate Spaces enabled need one list per display, showing only the display containing the menu bar by default. Cap at sixteen Spaces. If a macOS update removes the lookup symbols, the app degrades to a name-less indicator and says so in Settings. Debounce notifications because they can fire several times during an animation.

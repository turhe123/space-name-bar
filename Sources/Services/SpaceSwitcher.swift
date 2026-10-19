import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Switches Spaces by posting the user's "Switch to Desktop N" keyboard shortcuts and
/// reports whether those shortcuts and Accessibility permission are available.
enum SpaceSwitcher {
    /// A keyboard shortcut as stored in the system's symbolic hot keys.
    struct Shortcut {
        let keyCode: CGKeyCode
        let flags: CGEventFlags
    }

    private static let digitKeys: [Int] = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
                                           kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0]

    /// Symbolic hot key IDs 118...133 correspond to "Switch to Desktop 1...16".
    private static func hotKeyEntry(for desktop: Int) -> [String: Any]? {
        CFPreferencesAppSynchronize("com.apple.symbolichotkeys" as CFString)
        let all = UserDefaults(suiteName: "com.apple.symbolichotkeys")?.dictionary(forKey: "AppleSymbolicHotKeys")
        return all?[String(117 + desktop)] as? [String: Any]
    }

    /// Whether the "Switch to Desktop N" shortcut is enabled in System Settings.
    static func isShortcutEnabled(desktop: Int) -> Bool {
        guard (1...maxSpaces).contains(desktop), let entry = hotKeyEntry(for: desktop) else { return false }
        return (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) == 1)
    }

    /// The configured shortcut, falling back to the macOS defaults (⌃N, then ⌃⌥N above 10).
    static func shortcut(desktop: Int) -> Shortcut? {
        guard (1...maxSpaces).contains(desktop) else { return nil }
        if let value = hotKeyEntry(for: desktop)?["value"] as? [String: Any],
           let params = value["parameters"] as? [Int], params.count == 3, params[1] != 65535 {
            let mods = NSEvent.ModifierFlags(rawValue: UInt(params[2]))
            var flags: CGEventFlags = []
            if mods.contains(.control) { flags.insert(.maskControl) }
            if mods.contains(.option) { flags.insert(.maskAlternate) }
            if mods.contains(.command) { flags.insert(.maskCommand) }
            if mods.contains(.shift) { flags.insert(.maskShift) }
            return Shortcut(keyCode: CGKeyCode(params[1]), flags: flags)
        }
        let index = desktop <= 10 ? desktop - 1 : desktop - 11
        let flags: CGEventFlags = desktop <= 10 ? .maskControl : [.maskControl, .maskAlternate]
        return Shortcut(keyCode: CGKeyCode(digitKeys[index]), flags: flags)
    }

    /// Whether this process may post synthetic keyboard events.
    static var isAccessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system Accessibility prompt if permission has not been granted yet.
    @discardableResult
    static func requestAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Posts the shortcut for the desktop. Returns false if permission or the shortcut is missing.
    @discardableResult
    static func switchTo(desktop: Int) -> Bool {
        guard requestAccessibility(), let shortcut = shortcut(desktop: desktop) else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false)
        down?.flags = shortcut.flags
        up?.flags = shortcut.flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        return down != nil
    }

    static func openAccessibilitySettings() {
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    static func openKeyboardShortcutsSettings() {
        open("x-apple.systempreferences:com.apple.Keyboard-Settings.extension?Shortcuts")
    }

    private static func open(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

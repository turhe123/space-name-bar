import AppKit
import Combine

/// How the menu bar title combines the Space number and its name.
enum DisplayFormat: String, CaseIterable, Identifiable {
    case both, numberOnly, nameOnly
    var id: String { rawValue }
    var label: String {
        switch self {
        case .both: return "Number and name"
        case .numberOnly: return "Number only"
        case .nameOnly: return "Name only"
        }
    }
}

/// Keys for settings stored in UserDefaults / @AppStorage.
enum PrefKey {
    static let format = "displayFormat"
    static let maxTitleLength = "maxTitleLength"
    static let showWindowCounts = "showWindowCounts"
    static let showAllDisplays = "showAllDisplays"
    static let onboardingDone = "onboardingDone"
    static let names = "spaceNames"
    static let emojis = "spaceEmojis"
}

/// Central observable state: current Space layout, user-assigned names, and refresh logic.
@MainActor
final class SpaceStore: ObservableObject {
    @Published private(set) var snapshot: SpaceSnapshot?
    @Published private(set) var windowCounts: [Int: Int] = [:]
    @Published private(set) var names: [String: String]
    @Published private(set) var emojis: [String: String]

    let provider: SpaceProvider?
    /// True when the private window-server symbols could not be loaded.
    var isDegraded: Bool { !(provider?.isLive ?? false) }

    private let defaults = UserDefaults.standard
    private var pendingRefresh: DispatchWorkItem?
    private var observers: [NSObjectProtocol] = []

    init() {
        provider = CGSSpaceProvider() ?? PlistSpaceProvider()
        names = defaults.dictionary(forKey: PrefKey.names) as? [String: String] ?? [:]
        emojis = defaults.dictionary(forKey: PrefKey.emojis) as? [String: String] ?? [:]
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.scheduleRefresh() }
            })
        refresh()
    }

    /// Coalesces bursts of notifications fired during the Space-switch animation.
    func scheduleRefresh(delay: TimeInterval = 0.3) {
        pendingRefresh?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        pendingRefresh = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func refresh() {
        snapshot = provider?.snapshot()
        if defaults.bool(forKey: PrefKey.showWindowCounts) { refreshWindowCounts() }
    }

    /// Counts normal, reasonably sized app windows per Space ID.
    func refreshWindowCounts() {
        guard let provider, provider.isLive,
              let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { windowCounts = [:]; return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var counts: [Int: Int] = [:]
        for window in list {
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  let number = window[kCGWindowNumber as String] as? Int,
                  let pid = window[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 80, bounds.height >= 60
            else { continue }
            let spaces = provider.spaces(forWindow: CGWindowID(number))
            // Windows on every Space (e.g. sticky panels) would inflate all counts; skip them.
            guard spaces.count == 1, let space = spaces.first else { continue }
            counts[space, default: 0] += 1
        }
        windowCounts = counts
    }

    // MARK: - Derived data

    /// Displays to show: the menu-bar display by default, or all of them.
    var visibleDisplays: [DisplaySpaces] {
        guard let displays = snapshot?.displays, !displays.isEmpty else { return [] }
        if defaults.bool(forKey: PrefKey.showAllDisplays) || displays.count == 1 { return displays }
        if let main = displays.first(where: { $0.id == "Main" }) { return [main] }
        if let uuid = Self.menuBarDisplayUUID, let match = displays.first(where: { $0.id == uuid }) { return [match] }
        return [displays[0]]
    }

    var activeSpace: SpaceInfo? {
        guard let snapshot, let active = snapshot.activeSpaceID else { return nil }
        return snapshot.displays.lazy.flatMap(\.spaces).first { $0.managedID == active }
    }

    func displayName(for space: SpaceInfo) -> String {
        if let custom = names[space.id], !custom.isEmpty { return custom }
        if let app = space.fullScreenAppName { return app }
        return "Desktop \(space.desktopNumber ?? 0)"
    }

    func emoji(for space: SpaceInfo) -> String { emojis[space.id] ?? "" }

    /// The text shown in the menu bar, or nil when the Space cannot be determined.
    var menuBarTitle: String? {
        guard let space = activeSpace else { return nil }
        let format = DisplayFormat(rawValue: defaults.string(forKey: PrefKey.format) ?? "") ?? .both
        let maxLength = max(3, defaults.integer(forKey: PrefKey.maxTitleLength))
        var name = displayName(for: space)
        if name.count > maxLength { name = String(name.prefix(maxLength - 1)) + "…" }
        let emoji = emoji(for: space)
        let prefixedName = emoji.isEmpty ? name : "\(emoji) \(name)"
        let number = space.desktopNumber.map(String.init) ?? "⛶"
        switch format {
        case .numberOnly: return emoji.isEmpty ? number : "\(emoji) \(number)"
        case .nameOnly: return prefixedName
        case .both: return "\(number) \(prefixedName)"
        }
    }

    // MARK: - Editing & switching

    func setName(_ name: String, emoji: String, for space: SpaceInfo) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[space.id] = trimmed.isEmpty ? nil : trimmed
        let trimmedEmoji = String(emoji.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2))
        emojis[space.id] = trimmedEmoji.isEmpty ? nil : trimmedEmoji
        defaults.set(names, forKey: PrefKey.names)
        defaults.set(emojis, forKey: PrefKey.emojis)
    }

    /// Jumps to a Space: posts the desktop shortcut, or activates the full-screen app.
    @discardableResult
    func switchTo(_ space: SpaceInfo) -> Bool {
        if let number = space.desktopNumber { return SpaceSwitcher.switchTo(desktop: number) }
        guard let pid = space.fullScreenPID, let app = NSRunningApplication(processIdentifier: pid) else { return false }
        return app.activate()
    }

    private static var menuBarDisplayUUID: String? {
        guard let number = NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }
}

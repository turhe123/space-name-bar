import AppKit
import CoreGraphics

/// A single macOS Space (virtual desktop or full-screen app Space) on one display.
struct SpaceInfo: Identifiable, Hashable {
    /// Stable key used to persist names; the Space UUID when available.
    let id: String
    /// The window-server identifier (ManagedSpaceID).
    let managedID: Int
    /// Global "Desktop N" number used by the Control-number shortcuts; nil for full-screen Spaces.
    let desktopNumber: Int?
    /// Name of the app owning a full-screen Space, if any.
    let fullScreenAppName: String?
    /// Process owning a full-screen Space, used to activate it on click.
    let fullScreenPID: pid_t?
    var isFullScreen: Bool { desktopNumber == nil }
}

/// All Spaces belonging to one physical display, in Mission Control order.
struct DisplaySpaces: Identifiable, Hashable {
    let id: String
    let spaces: [SpaceInfo]
    let currentSpaceID: Int?
}

/// A snapshot of the Space layout plus the globally active Space.
struct SpaceSnapshot {
    let displays: [DisplaySpaces]
    let activeSpaceID: Int?
}

/// Abstracts how the Space layout is discovered so the app can degrade gracefully.
protocol SpaceProvider {
    /// Human-readable description shown in Settings.
    var name: String { get }
    /// Whether the provider can identify the active Space live.
    var isLive: Bool { get }
    func snapshot() -> SpaceSnapshot?
    /// Space IDs for a window, if the provider can determine them.
    func spaces(forWindow windowID: CGWindowID) -> [Int]
}

/// Maximum number of Spaces handled, matching the 16 "Switch to Desktop" shortcuts.
let maxSpaces = 16

/// Parses the dictionaries returned by the window server or the Dock preferences.
enum SpaceParser {
    static func parse(displays raw: [[String: Any]], activeSpaceID: Int?) -> SpaceSnapshot {
        var desktopCounter = 0
        var total = 0
        var result: [DisplaySpaces] = []
        for display in raw {
            let displayID = display["Display Identifier"] as? String ?? "Main"
            let current = (display["Current Space"] as? [String: Any]).flatMap(managedID)
            var spaces: [SpaceInfo] = []
            for space in display["Spaces"] as? [[String: Any]] ?? [] where total < maxSpaces {
                guard let mid = managedID(space) else { continue }
                total += 1
                let uuid = space["uuid"] as? String ?? ""
                let key = uuid.isEmpty ? "space-\(mid)" : uuid
                let type = space["type"] as? Int ?? 0
                if type == 4 {
                    let (app, pid) = fullScreenOwner(space)
                    spaces.append(SpaceInfo(id: key, managedID: mid, desktopNumber: nil,
                                            fullScreenAppName: app, fullScreenPID: pid))
                } else {
                    desktopCounter += 1
                    spaces.append(SpaceInfo(id: key, managedID: mid, desktopNumber: desktopCounter,
                                            fullScreenAppName: nil, fullScreenPID: nil))
                }
            }
            result.append(DisplaySpaces(id: displayID, spaces: spaces, currentSpaceID: current))
        }
        return SpaceSnapshot(displays: result, activeSpaceID: activeSpaceID)
    }

    private static func managedID(_ dict: [String: Any]) -> Int? {
        (dict["ManagedSpaceID"] as? Int) ?? (dict["id64"] as? Int)
    }

    private static func fullScreenOwner(_ space: [String: Any]) -> (String, pid_t?) {
        var pid = (space["pid"] as? Int).map { pid_t($0) }
        var name: String?
        if let tiles = (space["TileLayoutManager"] as? [String: Any])?["TileSpaces"] as? [[String: Any]],
           let first = tiles.first {
            name = first["appName"] as? String ?? first["name"] as? String
            if pid == nil, let p = first["pid"] as? Int { pid = pid_t(p) }
        }
        if name == nil, let pid, let app = NSRunningApplication(processIdentifier: pid) {
            name = app.localizedName
        }
        return (name ?? "Full Screen", pid)
    }
}

/// Live provider backed by CoreGraphics Services symbols loaded at runtime with dlopen/dlsym.
final class CGSSpaceProvider: SpaceProvider {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias ActiveSpaceFn = @convention(c) (Int32) -> UInt64
    private typealias CopyDisplaysFn = @convention(c) (Int32) -> UnsafeMutableRawPointer?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> UnsafeMutableRawPointer?

    private let connection: Int32
    private let activeSpace: ActiveSpaceFn
    private let copyDisplays: CopyDisplaysFn
    private let copySpacesForWindows: CopySpacesForWindowsFn?

    let name = "Live (window server)"
    let isLive = true

    /// Returns nil if any required symbol is missing, e.g. after a macOS update.
    init?() {
        let paths = ["/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
                     "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"]
        let handles = paths.compactMap { dlopen($0, RTLD_LAZY) }
        func lookup<T>(_ symbol: String, as type: T.Type) -> T? {
            for handle in handles {
                if let ptr = dlsym(handle, symbol) { return unsafeBitCast(ptr, to: type) }
            }
            return nil
        }
        guard let conn = lookup("CGSMainConnectionID", as: ConnectionFn.self) ?? lookup("_CGSDefaultConnection", as: ConnectionFn.self),
              let active = lookup("CGSGetActiveSpace", as: ActiveSpaceFn.self),
              let displays = lookup("CGSCopyManagedDisplaySpaces", as: CopyDisplaysFn.self)
        else { return nil }
        connection = conn()
        activeSpace = active
        copyDisplays = displays
        copySpacesForWindows = lookup("CGSCopySpacesForWindows", as: CopySpacesForWindowsFn.self)
    }

    func snapshot() -> SpaceSnapshot? {
        guard let ptr = copyDisplays(connection) else { return nil }
        let array = Unmanaged<CFArray>.fromOpaque(ptr).takeRetainedValue()
        guard let raw = array as? [[String: Any]] else { return nil }
        let active = Int(activeSpace(connection))
        return SpaceParser.parse(displays: raw, activeSpaceID: active == 0 ? nil : active)
    }

    func spaces(forWindow windowID: CGWindowID) -> [Int] {
        guard let copy = copySpacesForWindows,
              let ptr = copy(connection, 0x7, [NSNumber(value: windowID)] as CFArray) else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(ptr).takeRetainedValue()
        return (array as? [NSNumber])?.map(\.intValue) ?? []
    }
}

/// Fallback provider reading the Dock's `com.apple.spaces` preferences. It may lag behind
/// the live state, so the active Space is only trusted as a hint.
final class PlistSpaceProvider: SpaceProvider {
    let name = "Fallback (Dock preferences)"
    let isLive = false

    func snapshot() -> SpaceSnapshot? {
        CFPreferencesAppSynchronize("com.apple.spaces" as CFString)
        guard let defaults = UserDefaults(suiteName: "com.apple.spaces"),
              let config = defaults.dictionary(forKey: "SpacesDisplayConfiguration"),
              let management = config["Management Data"] as? [String: Any],
              let monitors = management["Monitors"] as? [[String: Any]]
        else { return nil }
        let displays = monitors.filter { $0["Spaces"] != nil }
        guard !displays.isEmpty else { return nil }
        let snapshot = SpaceParser.parse(displays: displays, activeSpaceID: nil)
        return SpaceSnapshot(displays: snapshot.displays, activeSpaceID: snapshot.displays.first?.currentSpaceID)
    }

    func spaces(forWindow windowID: CGWindowID) -> [Int] { [] }
}

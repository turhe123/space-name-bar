import SwiftUI

/// Shared link for the Support / Donate button.
enum Support {
    static func openDonation() {
        NSWorkspace.shared.open(URL(string: "https://ko-fi.com/leodavidai")!)
    }
}

/// App entry point: a menu bar extra showing the current Space plus a Settings window.
@main
struct SpaceNameBarApp: App {
    @StateObject private var store = SpaceStore()

    init() {
        UserDefaults.standard.register(defaults: [
            PrefKey.format: DisplayFormat.both.rawValue,
            PrefKey.maxTitleLength: 20,
            PrefKey.showWindowCounts: true,
            PrefKey.showAllDisplays: false,
        ])
    }

    var body: some Scene {
        MenuBarExtra {
            MenuView()
                .environmentObject(store)
        } label: {
            MenuBarLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}

/// The menu bar label: the formatted Space title, or a plain Spaces icon if unknown.
struct MenuBarLabel: View {
    @EnvironmentObject private var store: SpaceStore
    // Observed so the label re-renders when formatting preferences change.
    @AppStorage(PrefKey.format) private var format = DisplayFormat.both.rawValue
    @AppStorage(PrefKey.maxTitleLength) private var maxTitleLength = 20

    var body: some View {
        if let title = store.menuBarTitle {
            Text(title)
        } else {
            Image(systemName: "rectangle.split.3x1")
                .accessibilityLabel("Spaces")
        }
    }
}

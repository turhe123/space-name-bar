import SwiftUI
import ServiceManagement
import Combine

/// The Settings window: title format, window counts, shortcuts helper, and launch at login.
struct SettingsView: View {
    @EnvironmentObject private var store: SpaceStore
    @AppStorage(PrefKey.format) private var format = DisplayFormat.both.rawValue
    @AppStorage(PrefKey.maxTitleLength) private var maxTitleLength = 20
    @AppStorage(PrefKey.showWindowCounts) private var showWindowCounts = true
    @AppStorage(PrefKey.showAllDisplays) private var showAllDisplays = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Picker("Display format", selection: $format) {
                    ForEach(DisplayFormat.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Stepper("Maximum title length: \(maxTitleLength)", value: $maxTitleLength, in: 5...40)
                Toggle("Show window counts", isOn: $showWindowCounts)
                    .onChange(of: showWindowCounts) { _, _ in store.refresh() }
                Toggle("Show Spaces for all displays", isOn: $showAllDisplays)
                    .onChange(of: showAllDisplays) { _, _ in store.refresh() }
            }
            Section("Detection") {
                LabeledContent("Method", value: store.provider?.name ?? "Unavailable")
                if store.isDegraded {
                    Text("The window-server Space lookup is unavailable on this macOS version. SpaceNameBar falls back to the Dock’s saved layout, which may lag behind; names may not always match the current Space, and window counts are disabled.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("Keyboard shortcuts") {
                ChecklistView(onDone: nil)
                Button("Open Keyboard Shortcuts Settings…") { SpaceSwitcher.openKeyboardShortcutsSettings() }
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Spacer()
                    Button("Support / Donate ❤️") { Support.openDonation() }
                        .controlSize(.large)
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 620)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginError = nil
        } catch {
            loginError = "Could not update login item: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}

/// A short checklist showing whether switching prerequisites are in place.
struct ChecklistView: View {
    @EnvironmentObject private var store: SpaceStore
    /// When set, shows a "Done" button that dismisses the first-launch checklist.
    let onDone: (() -> Void)?
    @State private var trusted = SpaceSwitcher.isAccessibilityTrusted
    @State private var enabledShortcuts = 0
    private let timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var desktopCount: Int {
        let count = store.snapshot?.displays.flatMap(\.spaces).filter { !$0.isFullScreen }.count ?? 0
        return min(max(count, 1), maxSpaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if onDone != nil { Text("Getting started").font(.headline) }
            item(!store.isDegraded, "Current Space detection",
                 store.isDegraded ? "Limited mode: using the Dock’s saved layout." : nil)
            item(enabledShortcuts >= desktopCount,
                 "“Switch to Desktop” shortcuts (\(enabledShortcuts)/\(desktopCount) enabled)",
                 enabledShortcuts >= desktopCount ? nil : "Enable them under Keyboard Shortcuts › Mission Control.",
                 action: ("Open", SpaceSwitcher.openKeyboardShortcutsSettings))
            item(trusted, "Accessibility access (to post the shortcuts)",
                 trusted ? nil : "Needed only for click-to-switch.",
                 action: ("Grant", { SpaceSwitcher.requestAccessibility(); SpaceSwitcher.openAccessibilitySettings() }))
            if let onDone {
                HStack { Spacer(); Button("Done", action: onDone).controlSize(.small) }
            }
        }
        .onAppear(perform: check)
        .onReceive(timer) { _ in check() }
    }

    private func check() {
        trusted = SpaceSwitcher.isAccessibilityTrusted
        enabledShortcuts = (1...desktopCount).filter(SpaceSwitcher.isShortcutEnabled(desktop:)).count
    }

    private func item(_ ok: Bool, _ title: String, _ hint: String?,
                      action: (String, () -> Void)? = nil) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if !ok, let action { Button(action.0, action: action.1).controlSize(.small) }
        }
    }
}

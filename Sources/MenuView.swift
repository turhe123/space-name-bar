import SwiftUI

/// The dropdown panel: per-display Space lists, onboarding checklist, and app actions.
struct MenuView: View {
    @EnvironmentObject private var store: SpaceStore
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrefKey.showWindowCounts) private var showWindowCounts = true
    @AppStorage(PrefKey.onboardingDone) private var onboardingDone = false
    @State private var editingID: String?
    @State private var switchFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !onboardingDone {
                ChecklistView(onDone: { onboardingDone = true })
                Divider()
            }
            if store.visibleDisplays.isEmpty {
                emptyState
            } else {
                ForEach(Array(store.visibleDisplays.enumerated()), id: \.element.id) { index, display in
                    if store.visibleDisplays.count > 1 {
                        Text("Display \(index + 1)").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(display.spaces) { space in
                        SpaceRow(space: space,
                                 isCurrent: space.managedID == display.currentSpaceID,
                                 windowCount: showWindowCounts ? store.windowCounts[space.managedID] : nil,
                                 editingID: $editingID,
                                 onSelect: { select(space) })
                    }
                }
                Text("Double-click a name to rename it.").font(.caption2).foregroundStyle(.tertiary)
            }
            if switchFailed {
                Label("Could not switch. Grant Accessibility access and enable the “Switch to Desktop” shortcuts.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack {
                Button("Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .keyboardShortcut(",")
                Spacer()
                Button("Support / Donate ❤️") { Support.openDonation() }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear {
            switchFailed = false
            store.refresh()
            if showWindowCounts { store.refreshWindowCounts() }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Current Space unavailable", systemImage: "questionmark.square.dashed").font(.headline)
            Text("SpaceNameBar could not read the Space layout. Make sure “Displays have separate Spaces” is set as you expect in Desktop & Dock settings, create at least two desktops in Mission Control, then switch Spaces once so macOS records them.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Retry") { store.refresh() }
        }
    }

    private func select(_ space: SpaceInfo) {
        guard editingID == nil else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            switchFailed = !store.switchTo(space)
        }
    }
}

/// One Space in the list; single click switches, double click edits the name inline.
struct SpaceRow: View {
    @EnvironmentObject private var store: SpaceStore
    let space: SpaceInfo
    let isCurrent: Bool
    let windowCount: Int?
    @Binding var editingID: String?
    let onSelect: () -> Void

    @State private var draftName = ""
    @State private var draftEmoji = ""
    @State private var hovering = false
    @FocusState private var nameFocused: Bool

    private var isEditing: Bool { editingID == space.id }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isCurrent ? Color.accentColor : Color.clear)
                .frame(width: 7, height: 7)
            Text(space.desktopNumber.map(String.init) ?? "⛶")
                .monospacedDigit().foregroundStyle(.secondary).frame(width: 20, alignment: .trailing)
            if isEditing {
                TextField("🙂", text: $draftEmoji).frame(width: 34)
                TextField("Name", text: $draftName)
                    .focused($nameFocused)
                    .onSubmit(commit)
                    .onExitCommand { editingID = nil }
                Button("Save", action: commit).controlSize(.small)
            } else {
                let emoji = store.emoji(for: space)
                Text(emoji.isEmpty ? store.displayName(for: space) : "\(emoji) \(store.displayName(for: space))")
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                Spacer()
                if let windowCount {
                    Text("\(windowCount)")
                        .font(.caption).monospacedDigit()
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .help("\(windowCount) app window(s) on this Space")
                }
            }
        }
        .padding(.vertical, 4).padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering && !isEditing ? Color.primary.opacity(0.08) : .clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(TapGesture(count: 2).onEnded(beginEditing).exclusively(before: TapGesture().onEnded(onSelect)))
    }

    private func beginEditing() {
        draftName = store.names[space.id] ?? ""
        draftEmoji = store.emoji(for: space)
        editingID = space.id
        nameFocused = true
    }

    private func commit() {
        store.setName(draftName, emoji: draftEmoji, for: space)
        editingID = nil
    }
}

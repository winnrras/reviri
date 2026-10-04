import SwiftUI

/// Pantry tab (Figma: "Pantry Screen"): everything at home, soonest to spoil first.
struct PantryView: View {
    @Environment(AppState.self) private var state
    @State private var editing: InventoryItem?
    @State private var removing: InventoryItem?
    @State private var showRewind = false

    private var sorted: [InventoryItem] {
        state.inventory.sorted { ($0.daysLeft ?? 999) < ($1.daysLeft ?? 999) }
    }

    var body: some View {
        NavigationStack {
            // A native List keeps swipe-to-delete and Edit; styled as the design's single white card.
            List {
                Section {
                    ForEach(sorted) { item in
                        InventoryRow(item: item)
                            .onTapGesture { editing = item }
                            .listRowBackground(Theme.surface)
                            .listRowSeparatorTint(Theme.divider)
                    }
                    .onDelete { offsets in
                        // Ask how it left the pantry (used or thrown away) before removing it.
                        if let index = offsets.first { removing = sorted[index] }
                    }
                } header: {
                    if !state.inventory.isEmpty {
                        Text("Sorted by items spoiling soonest")
                            .font(Theme.subhead)
                            .foregroundStyle(Theme.secondaryText)
                            .textCase(nil)
                            .padding(.leading, -16)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .reviriList()
            .contentMargins(.bottom, Theme.tabBarClearance, for: .scrollContent)
            .overlay {
                if state.inventory.isEmpty {
                    ContentUnavailableView(
                        "Nothing here yet",
                        systemImage: "tray",
                        description: Text("Scan a receipt to fill your pantry.")
                    )
                }
            }
            .removeItemDialog($removing)
            .navigationTitle("Pantry")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showRewind = true
                    } label: {
                        Label("Rewind", systemImage: "clock.arrow.circlepath")
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.green)
                    }
                }
                if !state.inventory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
            .sheet(isPresented: $showRewind) { RewindView() }
            // For screenshots: launch with `-openSheet Rewind` (or `Remove`) to open it straight away.
            .task {
                let sheet = UserDefaults.standard.string(forKey: "openSheet")
                guard sheet == "Rewind" || sheet == "Remove" else { return }
                try? await Task.sleep(for: .milliseconds(600))   // let the tab finish appearing first
                if sheet == "Rewind" { showRewind = true } else { removing = sorted.first }
            }
            .refreshable { await state.loadAll() }
            .sheet(item: $editing) { item in
                EditItemView(item: item)
            }
        }
    }
}

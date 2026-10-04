import SwiftUI

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
            List {
                ForEach(sorted) { item in
                    InventoryRow(item: item)
                        .onTapGesture { editing = item }
                }
                .onDelete { offsets in
                    // Ask how it left the pantry (used or thrown away) before removing it.
                    if let index = offsets.first { removing = sorted[index] }
                }
            }
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
                    }
                }
                if !state.inventory.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { EditButton() }
                }
            }
            .sheet(isPresented: $showRewind) { RewindView() }
            .refreshable { await state.loadAll() }
            .sheet(item: $editing) { item in
                EditItemView(item: item)
            }
        }
    }
}

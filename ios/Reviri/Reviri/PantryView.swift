import SwiftUI

struct PantryView: View {
    @Environment(AppState.self) private var state
    @State private var editing: InventoryItem?

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
                    let items = sorted
                    for index in offsets {
                        let item = items[index]
                        Task { await state.delete(item) }
                    }
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
            .navigationTitle("Pantry")
            .refreshable { await state.loadAll() }
            .sheet(item: $editing) { item in
                EditItemView(item: item)
            }
        }
    }
}

import SwiftUI
import UIKit

/// The normal iPhone camera for one photo. (The receipt scanner crops to a sheet of
/// paper, which is wrong for a whole fridge.)
struct CameraPicker: UIViewControllerRepresentable {
    var onPhoto: (UIImage) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onPhoto(image)
            } else {
                parent.onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}

/// Review what the fridge photo found before anything is saved.
/// Update = already in the pantry (the amount is replaced), Add = new, Not tracked = shown only.
struct FridgeReviewView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let item: FridgeItem
        var include = true
        var qty: String
        var id: String { item.id }
    }

    @State private var rows: [Row]
    private let untracked: [FridgeItem]

    init(items: [FridgeItem]) {
        _rows = State(initialValue: items.filter { $0.canonical != nil }
            .map { Row(item: $0, qty: String(format: "%g", $0.qtyBase.rounded())) })
        untracked = items.filter { $0.canonical == nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                rowSection("Update", footer: "Already in your pantry. Saving replaces the amount with what the photo shows.",
                           action: "update")
                rowSection("Add", footer: "New to your pantry.", action: "add")

                if !untracked.isEmpty {
                    Section {
                        ForEach(untracked) { item in
                            Text(item.label).foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Not tracked")
                    } footer: {
                        Text("Reviri doesn't track these yet, so they aren't saved.")
                    }
                }

                Section {
                } footer: {
                    Text("Amounts are estimated from the photo. Check them before saving.")
                }
            }
            .navigationTitle("From your fridge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private func rowSection(_ title: String, footer: String, action: String) -> some View {
        let indices = rows.indices.filter { rows[$0].item.action == action }
        if !indices.isEmpty {
            Section {
                ForEach(indices, id: \.self) { i in
                    rowView($rows[i])
                }
            } header: {
                Text(title)
            } footer: {
                Text(footer)
            }
        }
    }

    private func rowView(_ row: Binding<Row>) -> some View {
        let item = row.wrappedValue.item
        return VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: row.include) {
                VStack(alignment: .leading, spacing: 2) {
                    Text([item.displayName, item.brand].compactMap { $0 }.joined(separator: " · "))
                        .font(.headline)
                    Text(item.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            if row.wrappedValue.include {
                HStack {
                    if item.action == "update" {
                        Text("Pantry \(qtyText(item.pantryQty, item.unitBase)) →")
                            .foregroundStyle(.secondary)
                    }
                    TextField("Amount", text: row.qty)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                    Text(item.unitBase == "count" ? "pcs" : item.unitBase)
                        .foregroundStyle(.secondary)
                }
                Text(item.estimate).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private var selected: [FridgeApplyItem] {
        rows.compactMap { row in
            guard row.include, let canonical = row.item.canonical,
                  let qty = Double(row.qty.replacingOccurrences(of: ",", with: ".")), qty >= 0 else { return nil }
            return FridgeApplyItem(canonical: canonical, qtyBase: qty, brand: row.item.brand)
        }
    }

    /// On success AppState clears fridgeItems, which closes this sheet. On error it stays open.
    private func save() {
        let items = selected
        Task { await state.applyFridge(items) }
    }
}

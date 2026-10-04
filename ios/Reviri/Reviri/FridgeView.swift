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

/// Review what the fridge photo found before anything is saved (Figma: "Fridge Review Sheet").
/// Update = already in the pantry (the amount is replaced), New = added, Not tracked = shown only.
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
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Gemini detected these items. Toggle items off or tap amounts to adjust. Amounts are estimated from the photo.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    group("Update existing items", action: "update")
                    group("New items found", action: "add")
                    if !untracked.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            groupLabel("Not tracked")
                            VStack(spacing: 0) {
                                ForEach(Array(untracked.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().overlay(Theme.divider) }
                                    HStack {
                                        Text(item.label).font(Theme.subhead)
                                        Spacer()
                                        Text("(Untracked)").font(Theme.footnote.italic())
                                    }
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(minHeight: 40)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            FootnoteText("Reviri doesn't track these yet, so they aren't saved.")
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                Button("Save to Pantry") { save() }
                    .buttonStyle(PrimaryButtonStyle(height: 50))
                    .disabled(selected.isEmpty)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Theme.background)
            }
            .navigationTitle("Review Fridge Scan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.secondaryText)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.green)
                        .disabled(selected.isEmpty)
                }
            }
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Theme.secondaryText)
    }

    @ViewBuilder
    private func group(_ title: String, action: String) -> some View {
        let indices = rows.indices.filter { rows[$0].item.action == action }
        if !indices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                groupLabel(title)
                VStack(spacing: 0) {
                    ForEach(Array(indices.enumerated()), id: \.element) { position, i in
                        if position > 0 { Divider().overlay(Theme.divider) }
                        rowView($rows[i])
                    }
                }
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
        }
    }

    /// Figma "Review item": check toggle, name (+ New badge), editable amount chip.
    private func rowView(_ row: Binding<Row>) -> some View {
        let item = row.wrappedValue.item
        let on = row.wrappedValue.include
        return HStack(spacing: 10) {
            Button {
                row.include.wrappedValue.toggle()
            } label: {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(on ? Theme.green : Theme.border)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(on ? "Included" : "Skipped")

            VStack(alignment: .leading, spacing: 4) {
                Text([item.displayName, item.brand].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? Theme.text : Theme.secondaryText)
                if item.action == "add" {
                    Text("New")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.green)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Theme.greenTint, in: Capsule())
                }
                Text(item.estimate).font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if item.action == "update" {
                    Text("\(qtyText(item.pantryQty, item.unitBase)) \u{2192}")
                        .foregroundStyle(Theme.secondaryText)
                }
                TextField("0", text: row.qty)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .fixedSize()
                Text(item.unitBase == "count" ? "pcs" : item.unitBase)
                Image(systemName: "pencil").font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.text)
            .padding(8)
            .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
            .opacity(on ? 1 : 0.4)
            .disabled(!on)
        }
        .padding(.vertical, 8)
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

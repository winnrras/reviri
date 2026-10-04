import SwiftUI
import UIKit

/// One pantry row: name, amount, and a colored "days left" badge.
struct InventoryRow: View {
    let item: InventoryItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.headline)
                Text([item.brand, qtyText(item.qtyBase, item.unitBase)].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let days = item.daysLeft {
                DaysBadge(days: days)
            }
        }
        .contentShape(Rectangle())
    }
}

struct DaysBadge: View {
    let days: Int

    private var color: Color {
        if days <= 2 { return .red }
        if days <= 4 { return .orange }
        return .green
    }

    private var label: String {
        if days <= 0 { return "Use today" }
        if days > 30 { return "Stable" }
        return "\(days)d left"
    }

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

/// Sheet for fixing a wrong amount after a bad scan. Set it to 0 to remove the item.
struct EditItemView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let item: InventoryItem
    @State private var qtyString: String

    init(item: InventoryItem) {
        self.item = item
        _qtyString = State(initialValue: String(format: "%g", item.qtyBase))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section([item.displayName, item.brand].compactMap { $0 }.joined(separator: " · ")) {
                    HStack {
                        TextField("Amount", text: $qtyString)
                            .keyboardType(.decimalPad)
                        Text(item.unitBase == "count" ? "pcs" : item.unitBase)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button("Remove from pantry", role: .destructive) {
                        Task { await state.delete(item) }
                        dismiss()
                    }
                } footer: {
                    Text("Use this if it's gone or thrown away. You can also swipe left on a row in Pantry.")
                }
            }
            .navigationTitle("Fix amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        guard let qty = Double(qtyString.replacingOccurrences(of: ",", with: ".")), qty >= 0 else { return }
        var updated = item
        updated.qtyBase = qty
        Task { await state.update(updated) }
        dismiss()
    }
}

extension UIImage {
    /// Shrinks big camera photos before upload (keeps small receipt text readable).
    func jpegForUpload(maxSide: CGFloat = 2000) -> Data? {
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        let resized = renderer.image { _ in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }
}

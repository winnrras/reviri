import SwiftUI
import UIKit

/// One pantry row: food icon, name, "Brand • amount", and a solid "days left" badge.
struct InventoryRow: View {
    let item: InventoryItem

    var body: some View {
        HStack(spacing: 12) {
            IconTile(systemName: Self.symbol(for: item.category))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(Theme.headline).foregroundStyle(Theme.text)
                Text([item.brand, qtyText(item.qtyBase, item.unitBase)].compactMap { $0 }.joined(separator: " • "))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer(minLength: 8)
            if let days = item.daysLeft {
                DaysBadge(days: days)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// A food icon per category (SF Symbols, close to the Figma line icons).
    static func symbol(for category: String) -> String {
        switch category {
        case "produce": return "leaf"
        case "dairy": return "drop"
        case "protein": return "fork.knife"
        case "eggs": return "oval.portrait"
        case "grains": return "takeoutbag.and.cup.and.straw"
        case "drinks": return "waterbottle"
        default: return "basket"
        }
    }
}

/// Solid pill: "Use today" (red), "2d left" (red), "3d left" (orange), "5d left" (green), "Stable" (dark green).
struct DaysBadge: View {
    let days: Int

    private var color: Color {
        if days <= 2 { return Theme.red }
        if days <= 4 { return Theme.orange }
        if days > 30 { return Theme.stableGreen }
        return Theme.green
    }

    private var label: String {
        if days <= 0 { return "Use today" }
        if days > 30 { return "Stable" }
        return "\(days)d left"
    }

    var body: some View {
        Text(label)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.onColor)
            .padding(.horizontal, 14)
            .frame(minWidth: 66, minHeight: 28)
            .background(color, in: Capsule())
    }
}

/// Sheet for fixing a wrong amount after a bad scan. Set it to 0 to remove the item.
struct EditItemView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let item: InventoryItem
    @State private var qtyString: String
    @State private var removing: InventoryItem?

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
                        removing = item
                    }
                } footer: {
                    Text("Use this if it's gone or thrown away. You can also swipe left on a row in Pantry.")
                }
            }
            .removeItemDialog($removing) { dismiss() }
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .tint(Theme.green)
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

/// "Text me this list": sends a shopping list to the phone number in Settings, through Photon.
struct TextListButton: View {
    @Environment(AppState.self) private var state
    let title: String
    let items: [ShoppingItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if state.alerts.phone == nil {
                    state.errorMessage = "Add your phone number in Settings (gear on the Scan tab) first."
                } else {
                    Task { await state.textShoppingList(title: title, items: items) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "message").font(.system(size: 18))
                    Text("Text me this list")
                    Spacer()
                }
                .padding(.horizontal, 16)
            }
            .buttonStyle(SecondaryButtonStyle())
            FootnoteText("Powered by Photon • Sent to your registered phone number")
        }
    }
}

/// Asks how an item left the pantry (Figma: "Used or Wasted Sheet"). Tossing is recorded
/// as waste but never costs the streak, so people have no reason to lie about it.
struct RemoveItemDialog: ViewModifier {
    @Binding var item: InventoryItem?
    var onDone: () -> Void = {}

    func body(content: Content) -> some View {
        content.sheet(item: $item) { item in
            RemoveItemSheet(item: item, onDone: onDone)
                .presentationDetents([.height(380)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(24)
        }
    }
}

struct RemoveItemSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let item: InventoryItem
    var onDone: () -> Void

    private var stillGood: Bool { (item.daysLeft ?? -1) >= 0 && (item.daysLeft ?? -1) <= 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.displayName).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                Text(stillGood ? "It's still good today. Next Up has recipes that use it. If it's gone, what happened?"
                               : "You finished or removed this item. What happened to it?")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            choice(icon: "checkmark", title: "Used it", detail: "Cooked or eaten.",
                   tint: Theme.greenTint, border: Theme.usedBorder, ink: Theme.green) { remove(tossed: false) }
            choice(icon: "trash", title: "Threw it away", detail: "Spoiled or discarded. Counted on Savings, never breaks your streak.",
                   tint: Theme.tossTint, border: Theme.tossBorder, ink: Theme.tossInk) { remove(tossed: true) }
            Button("Cancel") { dismiss() }
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .padding(.horizontal, 20)
        .padding(.top, 28)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
    }

    private func choice(icon: String, title: String, detail: String, tint: Color, border: Color, ink: Color,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ink)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(title == "Used it" ? Theme.green : Theme.text)
                    Text(detail).font(Theme.footnote).foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func remove(tossed: Bool) {
        Task { await state.delete(item, tossed: tossed) }
        dismiss()
        onDone()
    }
}

extension View {
    func removeItemDialog(_ item: Binding<InventoryItem?>, onDone: @escaping () -> Void = {}) -> some View {
        modifier(RemoveItemDialog(item: item, onDone: onDone))
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

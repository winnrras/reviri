import SwiftUI

struct SavingsView: View {
    @Environment(AppState.self) private var state

    private var foodText: String { gramsText(state.stats.gramsSaved) }

    private func gramsText(_ grams: Double) -> String {
        grams >= 1000 ? String(format: "%.1f kg", grams / 1000) : "\(Int(grams.rounded())) g"
    }

    /// "Your spinach expired." Shown instead of letting check-in fail.
    private var expiredText: String? {
        let names = state.stats.expired.map { $0.lowercased() }
        guard let last = names.last else { return nil }
        let list = names.count == 1 ? last : names.dropLast().joined(separator: ", ") + " and " + last
        return "Your \(list) expired. Mark \(names.count == 1 ? "it" : "them") as used or thrown away in Pantry to check in."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    streakCard

                    HStack(spacing: 12) {
                        StatCard(title: "Food rescued", value: foodText, icon: "scalemass")
                        StatCard(title: "Money saved", value: String(format: "$%.2f", state.stats.dollarsSaved), icon: "dollarsign.circle")
                    }
                    HStack(spacing: 12) {
                        StatCard(title: "CO₂e avoided", value: String(format: "%.1f kg", state.stats.co2eSaved), icon: "leaf")
                        StatCard(title: "Food thrown away", value: gramsText(state.stats.wastedG), icon: "trash")
                    }

                    Text("Estimates use average prices and emission factors per food group. Rescued = perishable food you already owned that a suggested recipe used up.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("Savings")
            .refreshable { await state.loadAll() }
        }
    }

    private var streakCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.system(size: 48))
                .foregroundStyle(.orange)
            Text("\(state.stats.streakDays)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
            Text(state.stats.streakDays == 1 ? "day with nothing wasted" : "days with nothing wasted")
                .foregroundStyle(.secondary)
            Button {
                Task { await state.checkIn() }
            } label: {
                Text(state.stats.checkedInToday ? "Checked in today ✓" : "I wasted nothing today")
            }
            .buttonStyle(.borderedProminent)
            .disabled(state.stats.checkedInToday || expiredText != nil)
            .padding(.top, 4)
            if let expiredText, !state.stats.checkedInToday {
                Text(expiredText)
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.green)
            Text(value)
                .font(.title2.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

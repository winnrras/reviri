import SwiftUI

struct SavingsView: View {
    @Environment(AppState.self) private var state

    private var foodText: String {
        let grams = state.stats.gramsSaved
        return grams >= 1000 ? String(format: "%.1f kg", grams / 1000) : "\(Int(grams.rounded())) g"
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
                    StatCard(title: "CO₂e avoided", value: String(format: "%.1f kg", state.stats.co2eSaved), icon: "leaf")

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
            .disabled(state.stats.checkedInToday)
            .padding(.top, 4)
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

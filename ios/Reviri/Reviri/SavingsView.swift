import SwiftUI

/// Savings tab (Figma: "Savings screen"): the streak and the impact numbers.
struct SavingsView: View {
    @Environment(AppState.self) private var state

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

    private var streakLine: String {
        let days = state.stats.streakDays
        let lead = days == 0 ? "Check in once a day to start" : days == 1 ? "1 day on top of your food" : "\(days) days on top of your food"
        return "\(lead) \u{2022} Logging food used or tossed keeps your streak alive."
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 8) {
                    streakCard
                    if let expiredText, !state.stats.checkedInToday {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "exclamationmark.circle").font(.system(size: 15, weight: .semibold))
                            Text(expiredText).font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .foregroundStyle(Theme.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Theme.noticeOrange, in: RoundedRectangle(cornerRadius: 14))
                    }
                    ImpactCard(icon: "scalemass", value: gramsText(state.stats.gramsSaved), title: "Food rescued")
                    ImpactCard(icon: "dollarsign.circle", value: String(format: "$%.2f", state.stats.dollarsSaved),
                               title: "Money saved")
                    ImpactCard(icon: "leaf", value: String(format: "%.1f kg", state.stats.co2eSaved), title: "CO\u{2082}e avoided")
                    ImpactCard(icon: "trash", value: gramsText(state.stats.wastedG), title: "Food thrown away",
                               note: "Items marked as thrown away")
                    Text("Estimates. Prices: US Bureau of Labor Statistics averages. CO\u{2082}e: Poore & Nemecek (2018). Shelf lives: USDA FoodKeeper. Rescued = perishable food you already owned that a suggested recipe used up.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .contentMargins(.bottom, Theme.tabBarClearance, for: .scrollContent)
            .background(Theme.background)
            .navigationTitle("Savings")
            .refreshable { await state.loadAll() }
        }
    }

    private var streakCard: some View {
        VStack(spacing: 8) {
            HStack(spacing: 20) {
                Image("SproutIllustration")
                    .resizable()
                    .frame(width: 80, height: 88)
                    .accessibilityHidden(true)
                VStack(spacing: 4) {
                    Text("\(state.stats.streakDays)")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                    Text("day streak")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                }
            }
            Text(streakLine)
                .font(.system(size: 14))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
            Button {
                Task { await state.checkIn() }
            } label: {
                Text(state.stats.checkedInToday ? "Checked in today \u{2713}" : "I checked my food today")
                    .font(.system(size: 15, weight: .bold))
            }
            .buttonStyle(PrimaryButtonStyle(height: 48))
            .disabled(state.stats.checkedInToday || expiredText != nil)
            .padding(.top, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(LinearGradient(colors: Theme.streakGradient, startPoint: .leading, endPoint: .trailing),
                    in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Theme.streakBorder, lineWidth: 1.5))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        .animation(.snappy, value: state.stats.streakDays)
    }
}

/// One impact number: green line icon, big value, label (Figma: "Impact card").
struct ImpactCard: View {
    let icon: String
    let value: String
    let title: String
    var note: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Theme.green)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text(title).font(Theme.footnote).foregroundStyle(Theme.secondaryText)
                if let note {
                    Text(note).font(Theme.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}


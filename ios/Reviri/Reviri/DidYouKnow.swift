import SwiftUI

/// "Did you know?" card on the Scan tab: one food-waste fact at a time, each with its source.
/// Starts on a different fact each day; tap for the next. Every fact is checked against the
/// source named under it (see backend/data/SOURCES.md for the FoodKeeper ones).
struct DidYouKnowCard: View {
    struct Fact {
        let text: String
        let source: String
    }

    static let facts: [Fact] = [
        Fact(text: "The world wasted 1.05 billion tonnes of food in 2022, about a fifth of all food available to consumers.",
             source: "UNEP Food Waste Index Report 2024"),
        Fact(text: "Households cause 60% of the world's food waste, more than restaurants and shops combined.",
             source: "UNEP Food Waste Index Report 2024"),
        Fact(text: "Food loss and waste produces 8\u{2013}10% of global greenhouse gas emissions, almost five times as much as aviation.",
             source: "UNEP Food Waste Index Report 2024"),
        Fact(text: "In the US, an estimated 30\u{2013}40% of the food supply is wasted.",
             source: "USDA"),
        Fact(text: "Food is the most common material in US landfills: 24% of what's buried there.",
             source: "US EPA"),
        Fact(text: "Raw chicken keeps only 1\u{2013}2 days in the fridge. Cook it first, or freeze it the day you buy it.",
             source: "USDA FoodKeeper"),
        Fact(text: "Eggs in their shell keep 3\u{2013}5 weeks in the fridge, much longer than most people think.",
             source: "USDA FoodKeeper"),
        Fact(text: "A block of hard cheese like cheddar keeps 6 months unopened, and 3\u{2013}4 weeks once opened.",
             source: "USDA FoodKeeper"),
        Fact(text: "Keep tomatoes on the counter until ripe, then use them within 7 days. The fridge can dull their flavor.",
             source: "USDA FoodKeeper"),
        Fact(text: "A kilo of cheese causes about 24 kg of CO\u{2082}e to make, so finishing it saves far more than finishing onions (0.5 kg).",
             source: "Poore & Nemecek, Science (2018)"),
    ]

    @State private var index = Calendar.current.ordinality(of: .day, in: .year, for: Date()).map { $0 % facts.count } ?? 0

    var body: some View {
        let fact = Self.facts[index]
        Button {
            withAnimation(.snappy) { index = (index + 1) % Self.facts.count }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "lightbulb")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.tossInk)
                    .frame(width: 40, height: 40)
                    .background(Theme.amberTint, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Did you know?").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Text("Next \u{203A}").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.green)
                    }
                    Text(fact.text)
                        .font(Theme.subhead)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .id(index)
                        .transition(.opacity)
                    Text("Source: \(fact.source)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .card()
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows the next fact")
    }
}

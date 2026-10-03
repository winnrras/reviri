import SwiftUI

struct NextUpView: View {
    @Environment(AppState.self) private var state
    @State private var mealCount = 4

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if state.suggestions.isEmpty {
                        Text("Nothing urgent. Scan a receipt, or cook something, and ideas show up here.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(state.suggestions) { suggestion in
                        SuggestionRow(suggestion: suggestion)
                    }
                } header: {
                    Text("Use it before you lose it")
                }

                Section {
                    Stepper("Meals to plan: \(mealCount)", value: $mealCount, in: 1...7)
                    Button {
                        Task { await state.planNextWeek(meals: mealCount) }
                    } label: {
                        Label("Plan ahead", systemImage: "calendar")
                    }
                } header: {
                    Text("Plan ahead")
                } footer: {
                    Text("Picks meals that share ingredients and use up what you have, then builds the shopping list.")
                }

                if let plan = state.nextWeek {
                    Section("Planned meals") {
                        ForEach(plan.meals) { meal in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(meal.recipe.name).font(.headline)
                                Text(meal.reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    Section("Shopping list") {
                        if plan.shoppingList.isEmpty {
                            Text("Nothing to buy.").foregroundStyle(.secondary)
                        }
                        ForEach(plan.shoppingList) { item in
                            HStack {
                                Text(item.displayName)
                                Spacer()
                                Text(qtyText(item.qtyBase, item.unitBase))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Section {
                        HStack {
                            Text("Perishables left unused")
                            Spacer()
                            Text("\(Int(plan.projectedWasteG.rounded())) g")
                                .bold()
                                .foregroundStyle(.green)
                        }
                        HStack {
                            Text("Typical random plan")
                            Spacer()
                            Text("\(Int(plan.baselineWasteG.rounded())) g")
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("Waste forecast")
                    } footer: {
                        Text("Compared with picking the same number of recipes at random from the same recipe book.")
                    }
                }
            }
            .navigationTitle("Next Up")
            .refreshable { await state.loadSuggestions() }
            .task { await state.loadSuggestions() }
        }
    }
}

struct SuggestionRow: View {
    @Environment(AppState.self) private var state
    let suggestion: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(suggestion.recipe.name).font(.headline)
            Text(suggestion.reason)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if !suggestion.missing.isEmpty {
                Text("Need to buy: " + suggestion.missing.map { $0.displayName }.joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Button("Cook this") {
                Task {
                    await state.cook(recipeId: suggestion.recipe.id,
                                     servings: suggestion.recipe.servings,
                                     fromSuggestion: true)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 4)
    }
}

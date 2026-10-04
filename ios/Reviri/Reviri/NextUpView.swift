import SwiftUI

struct NextUpView: View {
    @Environment(AppState.self) private var state
    @State private var mealCount = 4
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                if state.isSearching {
                    Section("Recipe search") {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Writing a recipe for \u{201C}\(query)\u{201D}… this can take up to 30 seconds.")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let result = state.searchResult {
                    Section {
                        NavigationLink {
                            RecipeDetailView(suggestion: result)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.recipe.name).font(.headline)
                                Text(result.reason)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        HStack {
                            Text("Recipe search")
                            Spacer()
                            Button("Clear") { state.clearSearch() }
                                .font(.caption)
                        }
                    }
                }

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
            .searchable(text: $query, prompt: "Search any recipe")
            .onSubmit(of: .search) {
                Task { await state.searchRecipe(query) }
            }
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

/// A full recipe: what it uses from the pantry, ingredients, steps, and actions.
struct RecipeDetailView: View {
    @Environment(AppState.self) private var state
    let suggestion: Suggestion

    /// Stay up to date after cooking (the pantry changed, so "uses up / still need" did too).
    private var current: Suggestion {
        if let fresh = state.searchResult, fresh.recipe.id == suggestion.recipe.id { return fresh }
        return suggestion
    }

    var body: some View {
        let recipe = current.recipe
        List {
            Section {
                Text(current.reason)
                if !current.missing.isEmpty {
                    Text("Need to buy: " + current.missing.map { $0.displayName }.joined(separator: ", "))
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
            }

            Section("Ingredients (serves \(recipe.servings))") {
                ForEach(recipe.ingredients, id: \.canonical) { ing in
                    HStack {
                        Text(ingredientName(ing.canonical))
                        Spacer()
                        Text(qtyText(ing.qtyBase, ing.unitBase))
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(recipe.untracked, id: \.self) { line in
                    HStack {
                        Text(line)
                        Spacer()
                        Text("not tracked")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            if !recipe.steps.isEmpty {
                Section("Steps") {
                    ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1).").bold()
                            Text(step)
                        }
                    }
                }
            }

            Section {
                Button("Cook this") {
                    Task {
                        await state.cook(recipeId: recipe.id, servings: recipe.servings, fromSuggestion: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Add to plan") { state.addToPlan(recipe) }
            } footer: {
                if recipe.generated {
                    Text("Written by Gemini from your search. \u{201C}Not tracked\u{201D} items aren't in Reviri's pantry list, so cooking doesn't count them.")
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

/// Next Up tab (Figma: "Next Up screen" and "Next Up - Recipe Search Result").
/// Search any recipe, cook what's about to spoil, and plan ahead.
struct NextUpView: View {
    @Environment(AppState.self) private var state
    @State private var mealCount = 4
    @State private var query = ""
    @State private var path: [Suggestion] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Use these soon to avoid waste")
                        .font(Theme.subhead)
                        .foregroundStyle(Theme.secondaryText)
                        .padding(.top, -12)

                    VStack(alignment: .leading, spacing: 16) {
                        searchField
                        if state.isSearching {
                            GeneratingCard(query: query)
                        } else if let result = state.searchResult {
                            SearchResultCard(result: result)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Use it before you lose it").sectionTitle()
                        if state.suggestions.isEmpty {
                            Text("Nothing urgent. Scan a receipt, or cook something, and ideas show up here.")
                                .font(Theme.subhead)
                                .foregroundStyle(Theme.secondaryText)
                                .card()
                        }
                        ForEach(state.suggestions) { suggestion in
                            SuggestionCard(suggestion: suggestion)
                        }
                    }

                    planAhead
                }
                .padding(16)
            }
            .contentMargins(.bottom, Theme.tabBarClearance, for: .scrollContent)
            .background(Theme.background)
            .navigationTitle("Next Up")
            .navigationDestination(for: Suggestion.self) { RecipeDetailView(suggestion: $0) }
            .refreshable { await state.loadSuggestions() }
            .task {
                await state.loadSuggestions()
                // For screenshots: launch with `-openSheet Recipe` to open the first suggestion.
                if UserDefaults.standard.string(forKey: "openSheet") == "Recipe", let first = state.suggestions.first {
                    path = [first]
                }
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField("Search or invent a recipe with pantry items\u{2026}", text: $query)
                .font(Theme.subhead)
                .submitLabel(.search)
                .onSubmit { Task { await state.searchRecipe(query) } }
            if !query.isEmpty || state.searchResult != nil {
                Button {
                    query = ""
                    state.clearSearch()
                } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.secondaryText)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 44)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }

    private var planAhead: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Plan ahead").sectionTitle()
            HStack(spacing: 8) {
                Text("Meals to plan: \(mealCount)")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                HStack(spacing: 0) {
                    Button { mealCount = max(1, mealCount - 1) } label: {
                        Image(systemName: "minus").frame(width: 34, height: 36)
                    }
                    Rectangle().fill(Theme.divider).frame(width: 1, height: 16)
                    Button { mealCount = min(7, mealCount + 1) } label: {
                        Image(systemName: "plus").frame(width: 34, height: 36)
                    }
                }
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.green)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
                .buttonStyle(.plain)
                Spacer()
                Button {
                    Task { await state.planNextWeek(meals: mealCount) }
                } label: {
                    Text("Plan ahead").padding(.horizontal, 16)
                }
                .buttonStyle(SecondaryButtonStyle(height: 44))
                .fixedSize()
            }
            .animation(.snappy, value: mealCount)

            if let plan = state.nextWeek {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Planned meals").font(.system(size: 15, weight: .semibold))
                    ForEach(plan.meals) { meal in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(meal.recipe.name).font(Theme.headline).foregroundStyle(Theme.text)
                            Text(meal.reason).font(Theme.footnote).foregroundStyle(Theme.secondaryText)
                        }
                    }
                }
                .card()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Shopping list").font(.system(size: 15, weight: .semibold))
                    if plan.shoppingList.isEmpty {
                        Text("Nothing to buy.").foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(plan.shoppingList) { item in
                        HStack {
                            Text(item.displayName).foregroundStyle(Theme.text)
                            Spacer()
                            Text(qtyText(item.qtyBase, item.unitBase)).foregroundStyle(Theme.secondaryText)
                        }
                        .font(Theme.subhead)
                    }
                }
                .card()
                if !plan.shoppingList.isEmpty {
                    TextListButton(title: "Next \(plan.meals.count) meals", items: plan.shoppingList)
                }

                WasteForecastCard(ours: plan.projectedWasteG, random: plan.baselineWasteG)
            }
        }
    }
}

/// Our plan's waste vs a random plan, as two bars readable in one second (Figma: "Waste forecast card").
struct WasteForecastCard: View {
    let ours: Double
    let random: Double

    private func bar(_ value: Double, _ color: Color) -> some View {
        GeometryReader { geo in
            let biggest = max(ours, random, 1)
            Capsule().fill(color).frame(width: max(8, geo.size.width * value / biggest))
        }
        .frame(height: 12)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Waste forecast").font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
            VStack(alignment: .leading, spacing: 8) {
                bar(ours, Theme.green)
                Text("Our plan: \(Int(ours.rounded())) g perishable waste")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
            }
            VStack(alignment: .leading, spacing: 8) {
                bar(random, Theme.barGrey)
                Text("Typical random plan: \(Int(random.rounded())) g")
                    .font(Theme.footnote).foregroundStyle(Theme.secondaryText)
            }
            Text("Compared with picking the same number of recipes at random from the same recipe book.")
                .font(.system(size: 11)).foregroundStyle(Theme.secondaryText)
        }
        .card()
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }
}

/// "Use it before you lose it" card: tap the header for the recipe, or cook it right away.
struct SuggestionCard: View {
    @Environment(AppState.self) private var state
    let suggestion: Suggestion

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 12) {
                NavigationLink(value: suggestion) {
                    HStack(spacing: 12) {
                        RecipeIcon()
                        Text(suggestion.recipe.name)
                            .font(Theme.headline)
                            .foregroundStyle(Theme.text)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                Text(suggestion.reason)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
                if !suggestion.missing.isEmpty {
                    Text("Need to buy: " + suggestion.missing.map { $0.displayName }.joined(separator: ", "))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.orange)
                }
                Button("Cook this") {
                    Task {
                        await state.cook(recipeId: suggestion.recipe.id,
                                         servings: suggestion.recipe.servings,
                                         fromSuggestion: true)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 44))
            }
            .card()
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)

            if !suggestion.missing.isEmpty {
                TextListButton(title: suggestion.recipe.name, items: suggestion.missing)
            }
        }
    }
}

/// Shown while Gemini writes a searched recipe (10-30 seconds).
struct GeneratingCard: View {
    let query: String
    @State private var sweep = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Generating recipe with Gemini\u{2026}")
                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Writing \u{201C}\(query)\u{201D} and checking your pantry. Up to 30 seconds.")
                    .font(Theme.footnote).foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Capsule().fill(Theme.fill)
                .frame(width: 72, height: 6)
                .overlay(alignment: .leading) {
                    Capsule().fill(Theme.green).frame(width: 28, height: 6)
                        .offset(x: sweep ? 44 : 0)
                }
                .clipShape(Capsule())
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { sweep = true }
                }
                .accessibilityHidden(true)
        }
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border, lineWidth: 1))
    }
}

/// The recipe Gemini wrote for a search. Tap for the full recipe.
struct SearchResultCard: View {
    let result: Suggestion

    private var usesLine: String {
        if !result.rescued.isEmpty { return "Uses " + result.rescued.joined(separator: ", ") + " from your pantry" }
        if result.missing.isEmpty { return "Everything is in your pantry" }
        return "Still need: " + result.missing.map { $0.displayName.lowercased() }.joined(separator: ", ")
    }

    var body: some View {
        NavigationLink(value: result) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    RecipeIcon()
                    Text(result.recipe.name)
                        .font(Theme.headline)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading)
                    Spacer()
                }
                Text(usesLine)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(result.rescued.isEmpty ? Theme.secondaryText : Theme.green)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text("Tap to view full recipe and pantry deductions.")
                        .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                }
            }
            .card()
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// A full recipe (Figma: "Recipe Detail Screen"): what it uses from the pantry, ingredients,
/// steps, and actions. Opens from a search result or a suggestion card.
struct RecipeDetailView: View {
    @Environment(AppState.self) private var state
    let suggestion: Suggestion

    /// Stay up to date after cooking (the pantry changed, so "uses up / still need" did too).
    private var current: Suggestion {
        if let fresh = state.searchResult, fresh.recipe.id == suggestion.recipe.id { return fresh }
        if let fresh = state.suggestions.first(where: { $0.recipe.id == suggestion.recipe.id }) { return fresh }
        return suggestion
    }

    var body: some View {
        let recipe = current.recipe
        let missing = Set(current.missing.map(\.canonical))
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recipe.name).font(.system(size: 24, weight: .bold)).foregroundStyle(Theme.text)
                    Text(recipe.generated ? "Serves \(recipe.servings) \u{2022} Written by Gemini" : "Serves \(recipe.servings)")
                        .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
                    if !current.rescued.isEmpty {
                        Text("Uses up " + current.rescued.joined(separator: ", ") + " from your pantry")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.green)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.greenTint, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .card()

                Text("Ingredients").sectionTitle()
                VStack(spacing: 0) {
                    ForEach(Array(recipe.ingredients.enumerated()), id: \.element.canonical) { index, ing in
                        if index > 0 { Divider().overlay(Theme.divider) }
                        HStack {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(ingredientName(ing.canonical)).font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(Theme.text)
                                Text(qtyText(ing.qtyBase, ing.unitBase)).font(Theme.footnote)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            let need = missing.contains(ing.canonical)
                            Text(need ? "Need to buy" : "In Pantry")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(need ? Theme.orange : Theme.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(need ? Theme.noticeOrange : Theme.greenTint, in: Capsule())
                        }
                        .frame(minHeight: 44)
                    }
                    ForEach(Array(recipe.untracked.enumerated()), id: \.offset) { index, line in
                        if index > 0 || !recipe.ingredients.isEmpty { Divider().overlay(Theme.divider) }
                        HStack {
                            Text(line).font(.system(size: 15)).foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Text("(Untracked)").font(.system(size: 13).italic()).foregroundStyle(Theme.secondaryText)
                        }
                        .frame(minHeight: 44)
                    }
                }
                .card()

                if !current.missing.isEmpty {
                    TextListButton(title: recipe.name, items: current.missing)
                }

                if !recipe.steps.isEmpty {
                    Text("Steps").sectionTitle()
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Theme.green)
                                    .frame(width: 26, height: 26)
                                    .background(Theme.greenTint, in: Circle())
                                Text(step).font(.system(size: 15)).foregroundStyle(Theme.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .card()
                }

                if recipe.generated {
                    FootnoteText("Written by Gemini from your search. \u{201C}Untracked\u{201D} items aren't in Reviri's pantry list, so cooking doesn't count them.")
                }
            }
            .padding(16)
        }
        .background(Theme.background)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Button("Cook this & update pantry") {
                    Task { await state.cook(recipeId: recipe.id, servings: recipe.servings, fromSuggestion: true) }
                }
                .buttonStyle(PrimaryButtonStyle(height: 50))
                Button("Add to Plan") { state.addToPlan(recipe) }
                    .buttonStyle(NeutralButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, Theme.tabBarClearance)
            .background(Theme.background)
        }
        .navigationTitle("Recipe Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct PlanView: View {
    @Environment(AppState.self) private var state

    /// "Creamy Spinach Chicken, Spinach Omelette": the title of a texted shopping list.
    private var pickedNames: String {
        state.recipes.filter { state.picks[$0.id] != nil }.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(state.recipes) { recipe in
                        RecipePickRow(recipe: recipe)
                    }
                } header: {
                    Text("Pick what you'll cook")
                } footer: {
                    Text("Leftovers update as you pick. Nothing is saved until you tap \"I cooked these\".")
                }

                if let plan = state.planResult {
                    Section("Left over afterwards") {
                        if plan.leftovers.isEmpty {
                            Text("Nothing left over.").foregroundStyle(.secondary)
                        }
                        ForEach(plan.leftovers) { left in
                            HStack {
                                Text(left.displayName)
                                Spacer()
                                Text(qtyText(left.qtyBase, left.unitBase))
                                    .foregroundStyle(.secondary)
                                DaysBadge(days: left.daysUntilSpoil)
                            }
                        }
                    }

                    if !plan.missing.isEmpty {
                        Section("You'd need to buy") {
                            ForEach(plan.missing) { item in
                                HStack {
                                    Text(item.displayName)
                                    Spacer()
                                    Text(qtyText(item.qtyBase, item.unitBase))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            TextListButton(title: pickedNames, items: plan.missing)
                        }
                    }

                    Section {
                        Button {
                            Task { await state.cookPicks() }
                        } label: {
                            Label("I cooked these", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Plan")
        }
    }
}

struct RecipePickRow: View {
    @Environment(AppState.self) private var state
    let recipe: Recipe

    private var servings: Int { state.picks[recipe.id] ?? 0 }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name).font(.headline)
                Text("Serves \(recipe.servings)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if servings == 0 {
                Button("Add") {
                    state.setPick(recipe.id, servings: recipe.servings)
                }
                .buttonStyle(.bordered)
            } else {
                Stepper(
                    "\(servings) servings",
                    value: Binding(
                        get: { servings },
                        set: { state.setPick(recipe.id, servings: $0) }
                    ),
                    in: 0...12
                )
                .fixedSize()
            }
        }
    }
}

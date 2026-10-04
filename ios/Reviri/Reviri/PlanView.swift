import SwiftUI

/// Plan tab (Figma: "Plan screen"). Pick meals, watch the leftovers update live, then cook.
struct PlanView: View {
    @Environment(AppState.self) private var state

    /// "Creamy Spinach Chicken, Spinach Omelette": the title of a texted shopping list.
    private var pickedNames: String {
        state.recipes.filter { state.picks[$0.id] != nil }.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Pick what you'll cook").sectionTitle()
                    ForEach(state.recipes) { recipe in
                        RecipePickCard(recipe: recipe)
                    }
                    Text("Leftovers update as you pick. Nothing is saved until you tap \u{201C}I cooked these\u{201D}.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.secondaryText)

                    if let plan = state.planResult {
                        Text("Left over afterwards").sectionTitle().padding(.top, 12)
                        VStack(spacing: 0) {
                            if plan.leftovers.isEmpty {
                                Text("Nothing left over.").foregroundStyle(Theme.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(Array(plan.leftovers.enumerated()), id: \.element.id) { index, left in
                                if index > 0 { Divider().overlay(Theme.divider).padding(.vertical, 12) }
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(left.displayName).font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(Theme.text)
                                        Text("\(qtyText(left.qtyBase, left.unitBase)) left")
                                            .font(Theme.footnote).foregroundStyle(Theme.secondaryText)
                                    }
                                    Spacer()
                                    DaysBadge(days: left.daysUntilSpoil)
                                }
                            }
                        }
                        .card()
                        .animation(.default, value: plan)

                        if !plan.missing.isEmpty {
                            Text("You'd need to buy").sectionTitle().padding(.top, 12)
                            VStack(spacing: 0) {
                                ForEach(Array(plan.missing.enumerated()), id: \.element.id) { index, item in
                                    if index > 0 { Divider().overlay(Theme.divider).padding(.vertical, 10) }
                                    HStack {
                                        Text(item.displayName).foregroundStyle(Theme.text)
                                        Spacer()
                                        Text(qtyText(item.qtyBase, item.unitBase)).foregroundStyle(Theme.secondaryText)
                                    }
                                    .font(Theme.subhead)
                                }
                            }
                            .card()
                            TextListButton(title: pickedNames, items: plan.missing)
                        }
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                if state.planResult != nil {
                    Button("I cooked these") {
                        Task { await state.cookPicks() }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 16)
                    .padding(.bottom, Theme.tabBarClearance)
                }
            }
            .navigationTitle("Plan")
            .task {
                // For screenshots: launch with `-openSheet PlanPick` to start with the first recipe picked.
                if UserDefaults.standard.string(forKey: "openSheet") == "PlanPick", let first = state.recipes.first,
                   state.picks.isEmpty {
                    try? await Task.sleep(for: .milliseconds(500))
                    state.setPick(first.id, servings: first.servings)
                }
            }
        }
    }
}

/// One recipe: name, a servings stepper, and Add (Figma: "Recipe card").
/// Picked cards get a green outline; stepping a picked recipe to 0 removes it.
struct RecipePickCard: View {
    @Environment(AppState.self) private var state
    let recipe: Recipe
    @State private var draftServings: Int?

    private var picked: Int? { state.picks[recipe.id] }
    private var servings: Int { picked ?? draftServings ?? recipe.servings }

    private func change(by step: Int) {
        let next = servings + step
        if picked != nil {
            state.setPick(recipe.id, servings: max(0, min(12, next)))
        } else {
            draftServings = max(1, min(12, next))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(recipe.name)
                .font(Theme.headline)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
            HStack {
                HStack(spacing: 0) {
                    Button { change(by: -1) } label: {
                        Image(systemName: "minus").frame(width: 40, height: 40)
                    }
                    Text("\(servings) servings")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(minWidth: 90)
                        .contentTransition(.numericText())
                    Button { change(by: 1) } label: {
                        Image(systemName: "plus").frame(width: 40, height: 40)
                    }
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.green)
                .background(Theme.fill, in: RoundedRectangle(cornerRadius: 12))
                .buttonStyle(.plain)

                Spacer()

                if picked == nil {
                    Button("Add") { state.setPick(recipe.id, servings: servings) }
                        .buttonStyle(SmallButtonStyle())
                } else {
                    Button {
                        state.setPick(recipe.id, servings: 0)
                    } label: {
                        Label("Added", systemImage: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.green)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 40)
                            .background(Theme.greenTint, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Removes it from the plan")
                }
            }
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .stroke(Theme.green, lineWidth: picked == nil ? 0 : 1.5))
        .animation(.snappy, value: servings)
    }
}

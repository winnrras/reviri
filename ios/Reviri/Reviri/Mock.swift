import Foundation

/// Canned data so the app works with no server (Settings -> "Use mock data").
/// This is also your demo safety net if the venue wifi dies.
enum Mock {
    static func pause() async {
        try? await Task.sleep(nanoseconds: 700_000_000)
    }

    private static func item(_ id: String, _ canonical: String, _ name: String, _ qty: Double,
                             _ unit: String, _ category: String, _ shelf: Int) -> InventoryItem {
        InventoryItem(id: id, canonical: canonical, displayName: name, qtyBase: qty, unitBase: unit,
                      category: category, purchasedOn: "2026-10-03", shelfLifeDays: shelf, daysLeft: shelf)
    }

    static let inventory: [InventoryItem] = [
        item("m1", "chicken_breast", "Chicken breast", 680, "g", "protein", 2),
        item("m2", "spinach", "Spinach", 283, "g", "produce", 5),
        item("m3", "heavy_cream", "Heavy cream", 473, "ml", "dairy", 7),
        item("m4", "mushrooms", "Mushrooms", 227, "g", "produce", 7),
        item("m5", "eggs", "Eggs", 12, "count", "eggs", 28),
        item("m6", "cheddar", "Cheddar", 227, "g", "dairy", 21),
    ]

    static let recipes: [Recipe] = [
        Recipe(id: "creamy-spinach-chicken", name: "Creamy Spinach Chicken", servings: 4, ingredients: [
            RecipeIngredient(canonical: "chicken_breast", qtyBase: 680, unitBase: "g"),
            RecipeIngredient(canonical: "heavy_cream", qtyBase: 240, unitBase: "ml"),
            RecipeIngredient(canonical: "spinach", qtyBase: 150, unitBase: "g"),
        ]),
        Recipe(id: "spinach-mushroom-quiche", name: "Spinach & Mushroom Quiche", servings: 6, ingredients: [
            RecipeIngredient(canonical: "eggs", qtyBase: 4, unitBase: "count"),
            RecipeIngredient(canonical: "heavy_cream", qtyBase: 120, unitBase: "ml"),
            RecipeIngredient(canonical: "spinach", qtyBase: 100, unitBase: "g"),
            RecipeIngredient(canonical: "mushrooms", qtyBase: 150, unitBase: "g"),
        ]),
        Recipe(id: "spinach-omelette", name: "Spinach Omelette", servings: 2, ingredients: [
            RecipeIngredient(canonical: "eggs", qtyBase: 4, unitBase: "count"),
            RecipeIngredient(canonical: "spinach", qtyBase: 60, unitBase: "g"),
        ]),
    ]

    static let plan = PlanResult(
        leftovers: [
            Leftover(canonical: "spinach", displayName: "Spinach", qtyBase: 133, unitBase: "g", daysUntilSpoil: 5),
            Leftover(canonical: "heavy_cream", displayName: "Heavy cream", qtyBase: 233, unitBase: "ml", daysUntilSpoil: 7),
        ],
        missing: []
    )

    static let suggestions: [Suggestion] = [
        Suggestion(recipe: recipes[1],
                   reason: "Uses up 120 ml heavy cream, 100 g spinach, 150 g mushrooms (soonest spoils in 5 days). Nothing extra to buy.",
                   rescued: ["120 ml heavy cream", "100 g spinach", "150 g mushrooms"],
                   missing: [], score: 58.6),
        Suggestion(recipe: recipes[2],
                   reason: "Uses up 60 g spinach (soonest spoils in 5 days). Nothing extra to buy.",
                   rescued: ["60 g spinach"], missing: [], score: 12.0),
    ]

    static let nextWeek = NextWeekResponse(
        meals: [
            PlannedMeal(recipe: recipes[0], servings: 4, reason: "Uses up 680 g chicken breast (soonest spoils in 2 days). Nothing extra to buy."),
            PlannedMeal(recipe: recipes[1], servings: 6, reason: "Uses up 233 ml heavy cream, 133 g spinach. Nothing extra to buy."),
        ],
        shoppingList: [ShoppingItem(canonical: "spinach", displayName: "Spinach", qtyBase: 283, unitBase: "g")],
        projectedWasteG: 423,
        baselineWasteG: 1372
    )

    static let stats = Stats(gramsSaved: 370, dollarsSaved: 3.1, co2eSaved: 0.9, streakDays: 3, checkedInToday: false)
    static let statsCheckedIn = Stats(gramsSaved: 370, dollarsSaved: 3.1, co2eSaved: 0.9, streakDays: 4, checkedInToday: true)
}

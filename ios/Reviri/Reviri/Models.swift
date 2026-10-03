import Foundation

// These structs mirror backend/models.py one-to-one.
// The server sends snake_case (qty_base); APIClient converts it to camelCase (qtyBase) automatically.

struct RecipeIngredient: Codable, Hashable {
    let canonical: String
    let qtyBase: Double
    let unitBase: String
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let servings: Int
    let ingredients: [RecipeIngredient]
}

struct InventoryItem: Codable, Identifiable, Hashable {
    let id: String
    var canonical: String
    var displayName: String
    var qtyBase: Double
    var unitBase: String
    var category: String
    var purchasedOn: String
    var shelfLifeDays: Int
    var daysLeft: Int?
}

struct MealPick: Codable, Hashable {
    let recipeId: String
    let servings: Int
}

struct Leftover: Codable, Identifiable, Hashable {
    var id: String { canonical }
    let canonical: String
    let displayName: String
    let qtyBase: Double
    let unitBase: String
    let daysUntilSpoil: Int
}

struct ShoppingItem: Codable, Identifiable, Hashable {
    var id: String { canonical }
    let canonical: String
    let displayName: String
    let qtyBase: Double
    let unitBase: String
}

struct PlanResult: Codable, Hashable {
    let leftovers: [Leftover]
    let missing: [ShoppingItem]
}

struct Stats: Codable, Hashable {
    let gramsSaved: Double
    let dollarsSaved: Double
    let co2eSaved: Double
    let streakDays: Int
    let checkedInToday: Bool

    static let empty = Stats(gramsSaved: 0, dollarsSaved: 0, co2eSaved: 0, streakDays: 0, checkedInToday: false)
}

struct CookRequest: Codable {
    let recipeId: String
    let servings: Int
    let fromSuggestion: Bool
}

struct CookResponse: Codable {
    let leftovers: [Leftover]
    let stats: Stats
}

struct Suggestion: Codable, Identifiable, Hashable {
    var id: String { recipe.id }
    let recipe: Recipe
    let reason: String
    let rescued: [String]
    let missing: [ShoppingItem]
    let score: Double
}

struct SuggestionsResponse: Codable {
    let suggestions: [Suggestion]
}

struct PlannedMeal: Codable, Identifiable, Hashable {
    var id: String { recipe.id }
    let recipe: Recipe
    let servings: Int
    let reason: String
}

struct NextWeekResponse: Codable, Hashable {
    let meals: [PlannedMeal]
    let shoppingList: [ShoppingItem]
    let projectedWasteG: Double
    let baselineWasteG: Double
}

// MARK: - Display helper

/// 680 g, 233 ml, 12 pcs. Whole numbers when they're whole.
func qtyText(_ qty: Double, _ unit: String) -> String {
    let rounded = qty >= 10 ? qty.rounded() : (qty * 10).rounded() / 10
    let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    return unit == "count" ? "\(number) pcs" : "\(number) \(unit)"
}

import SwiftUI

/// One shared object that all screens read from. Screens never call the server directly.
@MainActor
@Observable
final class AppState {
    var inventory: [InventoryItem] = []
    var recipes: [Recipe] = []
    var picks: [String: Int] = [:]          // recipe id -> servings (missing = not picked)
    var planResult: PlanResult?
    var suggestions: [Suggestion] = []
    var nextWeek: NextWeekResponse?
    var stats: Stats = .empty
    var lastScan: [InventoryItem] = []
    var searchResult: Suggestion?           // last recipe found by search (Next Up)
    var isSearching = false
    var isLoading = false
    var errorMessage: String?
    var infoMessage: String?

    @ObservationIgnored private let api = APIClient()
    @ObservationIgnored private var planToken = 0
    @ObservationIgnored private var searchQuery: String?   // what was typed, to re-check searchResult

    /// Runs `work`, shows a spinner, and turns any thrown error into an alert.
    private func attempt(spinner: Bool = true, _ work: () async throws -> Void) async {
        if spinner { isLoading = true }
        defer { if spinner { isLoading = false } }
        do { try await work() } catch { errorMessage = error.localizedDescription }
    }

    private func refreshPantry() async throws {
        inventory = try await api.inventory()
        stats = try await api.stats()
        suggestions = try await api.suggestions()
        // The search result's "uses up / still need" depends on the pantry. Cached on the server, so instant.
        // Best effort: a failure here keeps the old result instead of showing an error.
        if let searchQuery, let fresh = try? await api.generateRecipe(name: searchQuery) {
            searchResult = fresh
        }
    }

    // MARK: - Loading

    func loadAll() async {
        await attempt {
            recipes = try await api.recipes()
            try await refreshPantry()
        }
    }

    func loadSuggestions() async {
        await attempt(spinner: false) {
            suggestions = try await api.suggestions()
        }
    }

    // MARK: - Receipts and pantry

    func scanReceipt(imageData: Data) async {
        await attempt {
            lastScan = try await api.parseReceipt(imageData)
            try await refreshPantry()
        }
    }

    func useDemoReceipt() async {
        await attempt {
            lastScan = try await api.demoReceipt()
            try await refreshPantry()
        }
    }

    func update(_ item: InventoryItem) async {
        await attempt {
            _ = try await api.updateItem(item)
            if item.qtyBase <= 0 {
                lastScan.removeAll { $0.id == item.id }
            } else {
                lastScan = lastScan.map { $0.id == item.id ? item : $0 }
            }
            try await refreshPantry()
            await previewPlan()
        }
    }

    func delete(_ item: InventoryItem) async {
        await attempt {
            try await api.deleteItem(id: item.id)
            lastScan.removeAll { $0.id == item.id }
            try await refreshPantry()
            await previewPlan()
        }
    }

    // MARK: - Planning and cooking

    func setPick(_ recipeId: String, servings: Int) {
        if servings <= 0 {
            picks.removeValue(forKey: recipeId)
        } else {
            picks[recipeId] = servings
        }
        Task { await previewPlan() }
    }

    /// Live "what will be left?" preview. Nothing is saved on the server.
    func previewPlan() async {
        planToken += 1
        let token = planToken
        guard !picks.isEmpty else {
            planResult = nil
            return
        }
        let list = picks.map { MealPick(recipeId: $0.key, servings: $0.value) }
            .sorted { $0.recipeId < $1.recipeId }
        do {
            let result = try await api.plan(list)
            if token == planToken { planResult = result }   // ignore out-of-order answers
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cookPicks() async {
        await attempt {
            for pick in picks.sorted(by: { $0.key < $1.key }) {
                _ = try await api.cook(CookRequest(recipeId: pick.key, servings: pick.value, fromSuggestion: false))
            }
            picks = [:]
            planResult = nil
            try await refreshPantry()
            infoMessage = "Nice. Check the Next Up tab to use the leftovers."
        }
    }

    func cook(recipeId: String, servings: Int, fromSuggestion: Bool) async {
        await attempt {
            let before = stats.gramsSaved
            _ = try await api.cook(CookRequest(recipeId: recipeId, servings: servings, fromSuggestion: fromSuggestion))
            try await refreshPantry()
            let rescued = stats.gramsSaved - before
            if fromSuggestion && rescued > 0 {
                infoMessage = "Nice! You rescued \(Int(rescued.rounded())) g of food."
            }
        }
    }

    // MARK: - Recipe search

    /// Gemini writes a recipe for `name`. Uses its own spinner, since it can take 10-30 seconds.
    func searchRecipe(_ name: String) async {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !isSearching else { return }
        isSearching = true
        defer { isSearching = false }
        await attempt(spinner: false) {
            let result = try await api.generateRecipe(name: query)
            searchResult = result
            searchQuery = query
            // Make it pickable on the Plan tab too.
            if !recipes.contains(where: { $0.id == result.recipe.id }) {
                recipes.append(result.recipe)
            }
        }
    }

    func addToPlan(_ recipe: Recipe) {
        setPick(recipe.id, servings: picks[recipe.id] ?? recipe.servings)
        infoMessage = "Added \(recipe.name) to the Plan tab."
    }

    func clearSearch() {
        searchResult = nil
        searchQuery = nil
    }

    func planNextWeek(meals: Int) async {
        await attempt {
            nextWeek = try await api.nextWeek(meals: meals)
        }
    }

    // MARK: - Streak and demo helpers

    func checkIn() async {
        await attempt {
            stats = try await api.checkIn()
        }
    }

    func resetDemo() async {
        await attempt {
            try await api.reset()
            picks = [:]
            planResult = nil
            nextWeek = nil
            lastScan = []
            try await refreshPantry()
        }
    }
}

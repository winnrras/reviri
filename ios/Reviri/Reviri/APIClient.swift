import Foundation

enum APIError: LocalizedError {
    case server(String)
    case badURL

    var errorDescription: String? {
        switch self {
        case .server(let message): return message
        case .badURL: return "The server address looks wrong. Check it in Settings (gear icon on the Scan tab)."
        }
    }
}

// Request bodies
private struct PlanRequest: Encodable { let picks: [MealPick] }
private struct NextWeekRequest: Encodable { let meals: Int }
private struct OK: Decodable { let ok: Bool }
private struct ErrorBody: Decodable { let detail: String }

/// Talks to the FastAPI server. Settings (mock mode, server address) live in UserDefaults
/// so the Settings screen can change them while the app is running.
struct APIClient {
    var useMock: Bool { UserDefaults.standard.bool(forKey: "useMock") }

    var baseURL: URL? {
        var text = (UserDefaults.standard.string(forKey: "baseURL") ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        if !text.hasPrefix("http") { text = "http://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        return URL(string: text)
    }

    // MARK: - Endpoints

    func recipes() async throws -> [Recipe] {
        if useMock { return Mock.recipes }
        return try await get("/recipes")
    }

    func inventory() async throws -> [InventoryItem] {
        if useMock { return Mock.inventory }
        return try await get("/inventory")
    }

    func parseReceipt(_ jpeg: Data) async throws -> [InventoryItem] {
        if useMock { await Mock.pause(); return Mock.inventory }
        return try await perform(try uploadRequest("/parse-receipt", jpeg: jpeg))
    }

    /// Fridge photo -> proposed pantry changes. Nothing is saved until applyFridge.
    func scanFridge(_ jpeg: Data) async throws -> [FridgeItem] {
        if useMock { await Mock.pause(); return Mock.fridgeItems }
        let response: FridgeScanResponse = try await perform(try uploadRequest("/scan-fridge", jpeg: jpeg))
        return response.items
    }

    func applyFridge(_ items: [FridgeApplyItem]) async throws {
        if useMock { return }
        let _: [InventoryItem] = try await send("/fridge/apply", body: FridgeApplyRequest(items: items))
    }

    func demoReceipt() async throws -> [InventoryItem] {
        if useMock { await Mock.pause(); return Mock.inventory }
        return try await sendEmpty("/demo-receipt")
    }

    func updateItem(_ item: InventoryItem) async throws -> InventoryItem {
        if useMock { return item }
        return try await send("/inventory/\(item.id)", method: "PUT", body: item)
    }

    /// tossed = true records it as wasted on the Savings tab.
    func deleteItem(id: String, tossed: Bool) async throws {
        if useMock { return }
        let _: OK = try await sendEmpty("/inventory/\(id)?reason=\(tossed ? "tossed" : "used")", method: "DELETE")
    }

    func plan(_ picks: [MealPick]) async throws -> PlanResult {
        if useMock { return Mock.plan }
        return try await send("/plan", body: PlanRequest(picks: picks))
    }

    func cook(_ request: CookRequest) async throws -> CookResponse {
        if useMock { await Mock.pause(); return CookResponse(leftovers: Mock.plan.leftovers, stats: Mock.stats) }
        return try await send("/cook", body: request)
    }

    /// Recipe search: Gemini writes a recipe for any dish name. Can take 10-30 seconds.
    func generateRecipe(name: String) async throws -> Suggestion {
        if useMock { await Mock.pause(); return Mock.searchResult(name) }
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let request = try makeRequest("/recipes/generate", method: "POST",
                                      body: try encoder.encode(GenerateRecipeRequest(name: name)), timeout: 120)
        return try await perform(request)
    }

    func suggestions() async throws -> [Suggestion] {
        if useMock { return Mock.suggestions }
        let response: SuggestionsResponse = try await get("/suggestions")
        return response.suggestions
    }

    func nextWeek(meals: Int) async throws -> NextWeekResponse {
        if useMock { await Mock.pause(); return Mock.nextWeek }
        return try await send("/next-week", body: NextWeekRequest(meals: meals))
    }

    func stats() async throws -> Stats {
        if useMock { return Mock.stats }
        return try await get("/stats")
    }

    func checkIn() async throws -> Stats {
        if useMock { return Mock.statsCheckedIn }
        return try await sendEmpty("/checkin")
    }

    // MARK: Rewind (Neon Time Travel)

    func rewindPreview(minutes: Int) async throws -> RewindPreview {
        if useMock { await Mock.pause(); return Mock.rewindPreview(minutes) }
        return try await get("/rewind/preview?minutes=\(minutes)")
    }

    func rewind(at: String) async throws {
        if useMock { return }
        let _: [InventoryItem] = try await send("/rewind", body: RewindRequest(at: at))
    }

    // MARK: Text alerts (Photon)

    func alerts() async throws -> AlertSettings {
        if useMock { return .empty }
        return try await get("/alerts")
    }

    func saveAlerts(_ settings: AlertSettings) async throws -> AlertSettings {
        if useMock { return settings }
        return try await send("/alerts", method: "PUT", body: settings)
    }

    func testAlert() async throws -> AlertSent {
        if useMock { await Mock.pause(); return AlertSent(ok: true, text: "(mock mode: nothing was sent)") }
        return try await sendEmpty("/alerts/test")
    }

    func textShoppingList(title: String, items: [ShoppingItem]) async throws -> AlertSent {
        if useMock { await Mock.pause(); return AlertSent(ok: true, text: "(mock mode: nothing was sent)") }
        return try await send("/alerts/shopping-list", body: ShoppingListRequest(title: title, items: items))
    }

    /// Demo only: age the pantry so food expires on stage. Hidden behind a swipe in Settings.
    func skipDays(_ days: Int) async throws {
        if useMock { return }
        let _: [InventoryItem] = try await sendEmpty("/demo/skip-days?days=\(days)")
    }

    func reset() async throws {
        if useMock { return }
        let _: OK = try await sendEmpty("/reset")
    }

    // MARK: - Plumbing

    private static let unreachable: Set<URLError.Code> = [
        .timedOut, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost,
    ]

    /// A photo upload (multipart field "file"). Gemini can take a while, so it waits up to 2 minutes.
    private func uploadRequest(_ path: String, jpeg: Data) throws -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        return try makeRequest(path, method: "POST", body: body,
                               contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120)
    }

    private func makeRequest(_ path: String, method: String, body: Data? = nil,
                             contentType: String = "application/json",
                             timeout: TimeInterval = 60) throws -> URLRequest {
        guard let base = baseURL, let url = URL(string: base.absoluteString + path) else {
            throw APIError.badURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where Self.unreachable.contains(error.code) {
            // Usually the Mac changed wifi and got a new address, or this network blocks phone-to-laptop traffic.
            let address = baseURL?.absoluteString ?? "(none)"
            throw APIError.server("Can't reach the server at \(address). If you changed wifi, the Mac's address changed too: "
                                  + "run ipconfig getifaddr en0 and update it in Settings (gear on the Scan tab).")
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
            // FastAPI explains errors as {"detail": "..."}: show just that sentence when we can.
            if let body = try? JSONDecoder().decode(ErrorBody.self, from: data) {
                throw APIError.server(body.detail)
            }
            let text = String(data: data, encoding: .utf8) ?? ""
            throw APIError.server("Server error \(http.statusCode): \(text)")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        try await perform(try makeRequest(path, method: "GET"))
    }

    private func sendEmpty<T: Decodable>(_ path: String, method: String = "POST") async throws -> T {
        try await perform(try makeRequest(path, method: method))
    }

    private func send<T: Decodable, B: Encodable>(_ path: String, method: String = "POST", body: B) async throws -> T {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try await perform(try makeRequest(path, method: method, body: try encoder.encode(body)))
    }
}

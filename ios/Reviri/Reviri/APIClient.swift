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
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; filename=\"receipt.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        let request = try makeRequest("/parse-receipt", method: "POST", body: body,
                                      contentType: "multipart/form-data; boundary=\(boundary)", timeout: 120)
        return try await perform(request)
    }

    func demoReceipt() async throws -> [InventoryItem] {
        if useMock { await Mock.pause(); return Mock.inventory }
        return try await sendEmpty("/demo-receipt")
    }

    func updateItem(_ item: InventoryItem) async throws -> InventoryItem {
        if useMock { return item }
        return try await send("/inventory/\(item.id)", method: "PUT", body: item)
    }

    func deleteItem(id: String) async throws {
        if useMock { return }
        let _: OK = try await sendEmpty("/inventory/\(id)", method: "DELETE")
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

    func reset() async throws {
        if useMock { return }
        let _: OK = try await sendEmpty("/reset")
    }

    // MARK: - Plumbing

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
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server("No response from the server.")
        }
        guard (200..<300).contains(http.statusCode) else {
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

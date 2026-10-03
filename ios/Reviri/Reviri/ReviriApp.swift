import SwiftUI

@main
struct ReviriApp: App {
    @State private var state = AppState()

    init() {
        // Defaults used until you change them in Settings.
        // Start in mock mode so the app works before the server is running.
        UserDefaults.standard.register(defaults: [
            "useMock": true,
            "baseURL": "http://192.168.1.10:8000",
        ])
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
        }
    }
}

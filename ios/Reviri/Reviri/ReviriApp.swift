import SwiftUI

@main
struct ReviriApp: App {
    @State private var state = AppState()
    // The logo animation plays over the app while it loads. Skipped for screenshot launches (-startTab).
    @State private var showSplash = UserDefaults.standard.string(forKey: "startTab") == nil

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
            ZStack {
                RootView()
                    .environment(state)
                if showSplash {
                    SplashView {
                        withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
                    }
                    .transition(.opacity)
                    .zIndex(1)
                }
            }
        }
    }
}

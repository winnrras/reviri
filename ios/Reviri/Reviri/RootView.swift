import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        TabView {
            ScanView()
                .tabItem { Label("Scan", systemImage: "doc.text.viewfinder") }
            PantryView()
                .tabItem { Label("Pantry", systemImage: "cart") }
            PlanView()
                .tabItem { Label("Plan", systemImage: "fork.knife") }
            NextUpView()
                .tabItem { Label("Next Up", systemImage: "lightbulb") }
            SavingsView()
                .tabItem { Label("Savings", systemImage: "leaf") }
        }
        .task { await state.loadAll() }
        .overlay {
            if state.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .alert("Done", isPresented: Binding(
            get: { state.infoMessage != nil },
            set: { if !$0 { state.infoMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.infoMessage ?? "")
        }
    }
}

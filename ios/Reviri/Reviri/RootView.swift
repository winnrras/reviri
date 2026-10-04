import SwiftUI

struct RootView: View {
    @Environment(AppState.self) private var state

    // Opens on Scan. For screenshots, launch with `-startTab Plan` (any tab name) to open elsewhere.
    @State private var tab: AppTab = AppTab(rawValue: UserDefaults.standard.string(forKey: "startTab") ?? "") ?? .scan

    var body: some View {
        // The system tab bar is hidden; ReviriTabBar (the floating bar from Figma) replaces it.
        // Attached to each tab (not the TabView) so every screen, pushed ones too, leaves room for it.
        TabView(selection: $tab) {
            withTabBar(ScanView()).tag(AppTab.scan)
            withTabBar(PantryView()).tag(AppTab.pantry)
            withTabBar(PlanView()).tag(AppTab.plan)
            withTabBar(NextUpView()).tag(AppTab.nextUp)
            withTabBar(SavingsView()).tag(AppTab.savings)
        }
        .tint(Theme.green)
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

extension RootView {
    func withTabBar<Content: View>(_ content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .safeAreaInset(edge: .bottom, spacing: 0) { ReviriTabBar(selection: $tab) }
    }
}

enum AppTab: String, CaseIterable {
    case scan = "Scan", pantry = "Pantry", plan = "Plan", nextUp = "Next Up", savings = "Savings"
}

/// Floating white bar with text tabs; the active one sits in a green pill.
struct ReviriTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                if tab != .scan { Spacer(minLength: 0) }
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selection == tab ? .bold : .medium))
                        .foregroundStyle(selection == tab ? Theme.green : Theme.secondaryText)
                        .lineLimit(1)
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(selection == tab ? Theme.greenTint : .clear, in: Capsule())
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 6)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.border, lineWidth: 1))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .background(Theme.background.opacity(0.001))   // keeps taps from falling through the gaps
    }
}

import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMock") private var useMock = true
    @AppStorage("baseURL") private var baseURL = "http://192.168.1.10:8000"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Use mock data (no server)", isOn: $useMock)
                } footer: {
                    Text("Mock mode shows canned data. Switch it off once the server is running. It's also your backup if the wifi dies during the demo.")
                }

                Section {
                    TextField("http://192.168.x.x:8000", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                } header: {
                    Text("Server address")
                } footer: {
                    Text("Your Mac's IP on the same wifi, plus :8000. Find it with ipconfig getifaddr en0 in Terminal.")
                }

                Section {
                    Button("Reset demo data", role: .destructive) {
                        Task { await state.resetDemo() }
                    }
                } footer: {
                    Text("Empties the pantry back to the starting staples and clears stats. Do this before each demo run.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onDisappear {
            Task { await state.loadAll() }
        }
    }
}

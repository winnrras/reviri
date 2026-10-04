import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMock") private var useMock = true
    @AppStorage("baseURL") private var baseURL = "http://192.168.1.10:8000"
    @State private var phone = ""
    @AppStorage("userName") private var userName = ""
    @State private var dailyAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $userName)
                        .textContentType(.givenName)
                } header: {
                    Text("You")
                } footer: {
                    Text("Shown in the greeting on the Scan tab. Stays on this phone.")
                }

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
                    TextField("Your phone number", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Toggle("Daily alert at 9 AM", isOn: $dailyAlert)
                    Button("Save") {
                        Task { await state.saveAlerts(phone: phone, enabled: dailyAlert) }
                    }
                    Button("Send test alert") {
                        Task {
                            await state.saveAlerts(phone: phone, enabled: dailyAlert)
                            if state.alerts.phone != nil { await state.sendTestAlert() }
                        }
                    }
                    .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Text alerts")
                } footer: {
                    Text("Sent over iMessage with Photon: what spoils by tomorrow every morning, and shopping lists when you tap \"Text me this list\". Needs the server (not mock mode).")
                }

                Section {
                    Button("Reset demo data", role: .destructive) {
                        Task { await state.resetDemo() }
                    }
                    // Hidden demo controls: swipe left on this row to age the pantry 3 days, or undo that.
                    .swipeActions(edge: .trailing) {
                        Button("Skip 3 days") {
                            Task { await state.skipDays(3) }
                        }
                        .tint(.orange)
                        Button("Undo skip") {
                            Task { await state.skipDays(-3) }
                        }
                        .tint(.gray)
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
        .onAppear {
            phone = state.alerts.phone ?? ""
            dailyAlert = state.alerts.enabled
        }
        .onDisappear {
            Task { await state.loadAll() }
        }
    }
}

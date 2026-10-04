import SwiftUI

/// Settings (Figma: "Screen 6 - Settings"). Text alerts first (for users), demo tools and
/// connection settings below (for the team). A native List underneath keeps the hidden
/// swipe on "Reset Demo Pantry".
struct SettingsView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @AppStorage("useMock") private var useMock = true
    @AppStorage("baseURL") private var baseURL = "http://192.168.1.10:8000"
    @AppStorage("userName") private var userName = ""
    @State private var phone = ""
    @State private var dailyAlert = false
    @State private var loaded = false

    private var phoneChanged: Bool {
        phone.trimmingCharacters(in: .whitespaces) != (state.alerts.phone ?? "") || dailyAlert != state.alerts.enabled
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Get a text each morning about food that spoils by tomorrow, and send shopping lists to your phone.")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.secondaryText)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone Number").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                            TextField("+1 (555) 000-0000", text: $phone)
                                .font(Theme.subhead)
                                .keyboardType(.phonePad)
                                .textContentType(.telephoneNumber)
                                .padding(.horizontal, 14)
                                .frame(height: 48)
                                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.border, lineWidth: 1))
                        }
                        Toggle(isOn: $dailyAlert) {
                            Text("Daily expiration alerts (9 AM)")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Theme.text)
                        }
                        .tint(Theme.green)
                        Divider().overlay(Theme.divider)
                        Button("Send test alert") {
                            Task {
                                await state.saveAlerts(phone: phone, enabled: dailyAlert)
                                if state.alerts.phone != nil { await state.sendTestAlert() }
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle(height: 46))
                        .disabled(phone.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.vertical, 8)
                } header: {
                    header("Text Alerts (via Photon)")
                } footer: {
                    FootnoteText("Sent over iMessage with Photon. Saved when you tap Done. Needs the server (not mock mode).")
                }

                Section {
                    demoRow(icon: "arrow.counterclockwise", title: "Reset Demo Pantry") {
                        Task { await state.resetDemo() }
                    }
                    // Hidden demo controls: swipe left on this row to age the pantry 3 days, or undo that.
                    .swipeActions(edge: .trailing) {
                        Button("Skip 3 days") { Task { await state.skipDays(3) } }
                            .tint(Theme.orange)
                        Button("Undo skip") { Task { await state.skipDays(-3) } }
                            .tint(.gray)
                    }
                } header: {
                    header("Demo Tools")
                } footer: {
                    FootnoteText("Back to the starting pantry with stats cleared. Your phone number and alerts are kept.")
                }

                Section {
                    TextField("Your name", text: $userName)
                        .textContentType(.givenName)
                    Toggle("Use mock data (no server)", isOn: $useMock)
                        .tint(Theme.green)
                    TextField("http://192.168.x.x:8000", text: $baseURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .font(Theme.subhead.monospaced())
                } header: {
                    header("You and the server")
                } footer: {
                    FootnoteText("Your name is shown in the greeting on Scan. The server address is your Mac's IP plus :8000 (ipconfig getifaddr en0 in Terminal). Mock mode is the demo backup if the wifi fails.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .tint(Theme.green)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            phone = state.alerts.phone ?? ""
            dailyAlert = state.alerts.enabled
            loaded = true
        }
        .onDisappear {
            let save = phoneChanged
            Task {
                if save { await state.saveAlerts(phone: phone, enabled: dailyAlert) }
                await state.loadAll()
            }
        }
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(Theme.headline)
            .foregroundStyle(Theme.text)
            .textCase(nil)
            .padding(.leading, -16)
    }

    /// Figma "Demo action": icon tile, label, chevron.
    private func demoRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                IconTile(systemName: icon, size: 34)
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

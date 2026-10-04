import SwiftUI

/// Rewind: see the pantry as it was up to 6 hours ago and bring it back.
/// The history comes from Neon Time Travel; Reviri itself stores none.
struct RewindView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var stop = 3                 // index into `stops` (10 minutes)
    @State private var confirming = false

    /// Slider positions, in minutes: fine steps near "now", coarse ones further back.
    private let stops = [1, 2, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 300, 360]

    private var minutes: Int { stops[stop] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Text(Self.agoText(minutes))
                            .font(.title2.bold())
                            .contentTransition(.numericText())
                        Slider(value: Binding(get: { Double(stop) }, set: { stop = Int($0.rounded()) }),
                               in: 0...Double(stops.count - 1), step: 1) { editing in
                            if !editing { Task { await state.previewRewind(minutes: minutes) } }
                        }
                        HStack {
                            Text("Now")
                            Spacer()
                            Text("6 hours ago")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } footer: {
                    Text("Drag to pick a moment. Reviri keeps no history of its own: Neon Time Travel opens the database as it was then.")
                }

                if state.isRewinding {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Rewinding to \(Self.agoText(minutes).lowercased())…")
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if let preview = state.rewindPreview {
                    changesSection(preview)
                    Section("Pantry then (\(preview.items.count) items)") {
                        ForEach(preview.items) { InventoryRow(item: $0) }
                    }
                    Section {
                        Button {
                            confirming = true
                        } label: {
                            Label("Restore this pantry", systemImage: "clock.arrow.circlepath")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(preview.changes.isEmpty)
                    } footer: {
                        Text("Brings back the pantry and food totals from that moment. Your streak and settings stay as they are.")
                    }
                }
            }
            .navigationTitle("Rewind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog("Restore your pantry from \(Self.agoText(minutes).lowercased())?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Restore") {
                    Task {
                        await state.applyRewind()
                        if state.rewindPreview == nil { dismiss() }
                    }
                }
            } message: {
                Text("Your current pantry is replaced. You can rewind again if you change your mind.")
            }
            .task { await state.previewRewind(minutes: minutes) }
            .onDisappear { state.rewindPreview = nil }
        }
    }

    @ViewBuilder
    private func changesSection(_ preview: RewindPreview) -> some View {
        Section("What restoring changes") {
            if preview.changes.isEmpty {
                Text("Your pantry was the same then.").foregroundStyle(.secondary)
            }
            ForEach(preview.changes) { change in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(change.displayName).font(.headline)
                        Text(changeLabel(change))
                            .font(.caption)
                            .foregroundStyle(change.qtyThen > change.qtyNow ? .green : .red)
                    }
                    Spacer()
                    Text("\(qtyText(change.qtyNow, change.unitBase)) → \(qtyText(change.qtyThen, change.unitBase))")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func changeLabel(_ change: RewindChange) -> String {
        if change.qtyNow == 0 { return "Comes back" }
        if change.qtyThen == 0 { return "Goes away" }
        return change.qtyThen > change.qtyNow ? "More then" : "Less then"
    }

    /// 1 -> "1 minute ago", 90 -> "1 h 30 min ago", 120 -> "2 hours ago".
    static func agoText(_ minutes: Int) -> String {
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let h = minutes / 60, m = minutes % 60
        if m == 0 { return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        return "\(h) h \(m) min ago"
    }
}

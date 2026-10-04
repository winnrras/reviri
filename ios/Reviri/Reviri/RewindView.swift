import SwiftUI

/// Rewind (Figma: "Sheet Rewind"): see the pantry as it was up to 6 hours ago and bring it back.
/// The history comes from Neon Time Travel; Reviri itself stores none.
struct RewindView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var stop = 3                 // index into `stops` (10 minutes)
    @State private var confirming = false

    /// Slider positions, in minutes: fine steps near "now", coarse ones further back.
    static let stops = [1, 2, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240, 300, 360]

    private var minutes: Int { Self.stops[stop] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(Self.agoText(minutes))
                        .font(Theme.largeTitle)
                        .foregroundStyle(Theme.text)
                        .contentTransition(.numericText())
                        .animation(.snappy, value: minutes)

                    VStack(spacing: 12) {
                        TimelineSlider(stop: $stop, count: Self.stops.count,
                                       label: Self.shortText(minutes)) {
                            Task { await state.previewRewind(minutes: minutes) }
                        }
                        HStack {
                            Text("Now")
                            Spacer()
                            Text("6 hours ago")
                        }
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.secondaryText)
                    }

                    Text("Drag to pick a moment. Reviri keeps no history of its own: Neon Time Travel opens the database as it was then.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)

                    if state.isRewinding {
                        HStack(spacing: 12) {
                            ProgressView()
                            Text("Rewinding to \(Self.agoText(minutes).lowercased())\u{2026}")
                                .font(Theme.subhead)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .card()
                    } else if let preview = state.rewindPreview {
                        changesCard(preview)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pantry then (\(preview.items.count) items)")
                                .font(.system(size: 15)).foregroundStyle(Theme.text)
                            ForEach(preview.items) { InventoryRow(item: $0) }
                        }
                        .card()
                    }
                }
                .padding(16)
            }
            .background(Theme.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Button("Restore this pantry") { confirming = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(state.rewindPreview?.changes.isEmpty ?? true)
                    FootnoteText("Powered by Neon \u{2022} Streak and settings stay as they are.")
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(Theme.background)
            }
            .navigationTitle("Rewind")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.green)
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
    private func changesCard(_ preview: RewindPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What restoring changes").font(.system(size: 15)).foregroundStyle(Theme.text)
            if preview.changes.isEmpty {
                Text("Your pantry was the same then.").font(Theme.subhead).foregroundStyle(Theme.secondaryText)
            }
            ForEach(Array(preview.changes.enumerated()), id: \.element.id) { index, change in
                if index > 0 { Divider().overlay(Theme.divider) }
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(change.displayName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(changeLabel(change))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.onColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(changeColor(change), in: Capsule())
                    }
                    Spacer()
                    Text("\(qtyText(change.qtyNow, change.unitBase)) \u{2192} \(qtyText(change.qtyThen, change.unitBase))")
                        .font(.system(size: 14).monospacedDigit())
                        .foregroundStyle(Theme.text)
                }
                .padding(.vertical, 4)
            }
        }
        .card()
        .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
    }

    private func changeLabel(_ change: RewindChange) -> String {
        if change.qtyNow == 0 { return "Comes back" }
        if change.qtyThen == 0 { return "Goes away" }
        return change.qtyThen > change.qtyNow ? "More then" : "Less then"
    }

    private func changeColor(_ change: RewindChange) -> Color {
        if change.qtyThen == 0 { return Theme.red }
        return change.qtyThen > change.qtyNow ? Theme.green : Theme.orange
    }

    /// 1 -> "1 minute ago", 90 -> "1 h 30 min ago", 120 -> "2 hours ago".
    static func agoText(_ minutes: Int) -> String {
        if minutes < 60 { return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago" }
        let h = minutes / 60, m = minutes % 60
        if m == 0 { return h == 1 ? "1 hour ago" : "\(h) hours ago" }
        return "\(h) h \(m) min ago"
    }

    /// The bubble over the thumb: "10 min", "1 h 30", "6 h".
    static func shortText(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = minutes / 60, m = minutes % 60
        return m == 0 ? "\(h) h" : "\(h) h \(m)"
    }
}

/// The design's timeline: a label bubble over a ringed thumb, a track with the elapsed part
/// in green, and a tick per stop. Snaps to stops; `onRelease` fires when the finger lifts.
struct TimelineSlider: View {
    @Binding var stop: Int
    let count: Int
    let label: String
    var onRelease: () -> Void

    private let inset: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let usable = geo.size.width - inset * 2
            let x = { (i: Int) in inset + usable * CGFloat(i) / CGFloat(max(count - 1, 1)) }
            ZStack(alignment: .topLeading) {
                Capsule().fill(Theme.barGrey)
                    .frame(width: usable, height: 4)
                    .offset(x: inset, y: 47)
                Capsule().fill(Theme.green)
                    .frame(width: max(4, x(stop) - inset), height: 4)
                    .offset(x: inset, y: 47)
                ForEach(0..<count, id: \.self) { i in
                    Rectangle().fill(Theme.border)
                        .frame(width: 1, height: i.isMultiple(of: 2) ? 10 : 6)
                        .offset(x: x(i), y: 64)
                }
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Theme.surface, in: Capsule())
                    .fixedSize()
                    .position(x: min(max(x(stop), 36), geo.size.width - 36), y: 13)
                Circle()
                    .fill(Theme.surface)
                    .overlay(Circle().stroke(Theme.green, lineWidth: 2))
                    .overlay(Circle().fill(Theme.text).frame(width: 6, height: 6))
                    .frame(width: 28, height: 28)
                    .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
                    .position(x: x(stop), y: 49)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let raw = (value.location.x - inset) / usable * CGFloat(count - 1)
                        let next = min(max(Int(raw.rounded()), 0), count - 1)
                        if next != stop {
                            stop = next
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    }
                    .onEnded { _ in onRelease() }
            )
            .animation(.snappy, value: stop)
        }
        .frame(height: 82)
        .accessibilityElement()
        .accessibilityLabel("Rewind time")
        .accessibilityValue(label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: stop = min(stop + 1, count - 1)
            case .decrement: stop = max(stop - 1, 0)
            @unknown default: break
            }
            onRelease()
        }
    }
}

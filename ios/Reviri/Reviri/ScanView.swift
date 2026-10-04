import SwiftUI
import PhotosUI
import VisionKit

/// Wraps Apple's built-in document camera (auto-crops and flattens the receipt).
struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: (UIImage) -> Void
    var onCancel: () -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            if scan.pageCount > 0 {
                parent.onScan(scan.imageOfPage(at: 0))
            } else {
                parent.onCancel()
            }
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}

struct ScanView: View {
    @Environment(AppState.self) private var state
    @State private var showScanner = false
    @State private var showSettings = false
    @State private var photoItem: PhotosPickerItem?
    @State private var editing: InventoryItem?
    @State private var showFridgeOptions = false
    @State private var showFridgeCamera = false
    @State private var showFridgePhotos = false
    @State private var fridgePhotoItem: PhotosPickerItem?
    @AppStorage("userName") private var userName = ""

    /// "Good morning, Winner" (or just "Good morning" before a name is set in Settings).
    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening"
        let name = userName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? part : "\(part), \(name)"
    }

    /// One useful line under the greeting: what needs eating soon.
    private var nudge: String {
        let soon = state.inventory.filter { ($0.daysLeft ?? 99) <= 1 }.count
        if state.inventory.isEmpty { return "Scan a receipt to fill your pantry." }
        if soon == 0 { return "Nothing needs using today. Nice." }
        return soon == 1 ? "1 item to use by tomorrow" : "\(soon) items to use by tomorrow"
    }

    /// Figma "Receipt scan card": hero, receipt actions, and the fridge scan box.
    private var scanCard: some View {
        VStack(spacing: 12) {
            Image("SaladIllustration")
                .resizable()
                .frame(width: 180, height: 104)
                .accessibilityHidden(true)
            VStack(spacing: 6) {
                Text("Turn your groceries into less waste")
                    .font(Theme.headline).foregroundStyle(Theme.text)
                Text("Scan a receipt to automatically add items to your pantry.")
                    .font(.system(size: 14)).foregroundStyle(Theme.secondaryText)
            }
            .multilineTextAlignment(.center)

            VStack(spacing: 8) {
                Button {
                    if VNDocumentCameraViewController.isSupported {
                        showScanner = true
                    } else {
                        state.errorMessage = "The camera scanner isn't available here (the Simulator has no camera). Use \"Choose from Photos\" or \"Use demo receipt\"."
                    }
                } label: {
                    Label("Scan receipt", systemImage: "camera").font(.system(size: 17, weight: .bold))
                }
                .buttonStyle(PrimaryButtonStyle(height: 50))

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Choose from Photos")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.border, lineWidth: 1))
                }

                Button("Use demo receipt") {
                    Task { await state.useDemoReceipt() }
                }
                .font(Theme.footnote)
                .foregroundStyle(Theme.secondaryText)
                .frame(minHeight: 32)

                fridgeBox
            }

            Text("Receipts give us exact quantities. Scan after every grocery trip.")
                .font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
    }

    /// Figma "Fridge Scan": icon, copy, and the take-photo action (or the reading state).
    private var fridgeBox: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconTile(systemName: "refrigerator", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan Fridge").font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.text)
                    Text("Photograph inside your fridge to update what's left. You check every amount before it's saved.")
                        .font(Theme.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            if state.isScanningFridge {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Looking at your fridge\u{2026} up to 30 seconds")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            } else {
                Button {
                    showFridgeOptions = true
                } label: {
                    Label("Take photo or choose from library", systemImage: "camera")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.border, lineWidth: 1))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(greeting).font(.system(size: 22, weight: .bold)).foregroundStyle(Theme.text)
                        Text(nudge).font(Theme.subhead).foregroundStyle(Theme.secondaryText)
                    }

                    scanCard

                    DidYouKnowCard()

                    if !state.lastScan.isEmpty {
                        Text("Just added (tap to fix an amount)").sectionTitle().padding(.top, 8)
                        VStack(spacing: 0) {
                            ForEach(Array(state.lastScan.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { Divider().overlay(Theme.divider).padding(.vertical, 8) }
                                InventoryRow(item: item)
                                    .onTapGesture { editing = item }
                            }
                        }
                        .card()
                    }

                    if !state.lastScanSkipped.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Not tracked (\(state.lastScanSkipped.count))").sectionTitle()
                            VStack(spacing: 0) {
                                ForEach(Array(state.lastScanSkipped.enumerated()), id: \.offset) { index, line in
                                    if index > 0 { Divider().overlay(Theme.divider) }
                                    HStack {
                                        Text(line).font(Theme.subhead)
                                        Spacer()
                                        Text("(Untracked)").font(Theme.footnote.italic())
                                    }
                                    .foregroundStyle(Theme.secondaryText)
                                    .frame(minHeight: 40)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                            FootnoteText("Read from your receipt, but Reviri doesn't track these foods yet, so they aren't in your pantry.")
                        }
                    }
                }
                .padding(16)
            }
            .contentMargins(.bottom, Theme.tabBarClearance, for: .scrollContent)
            .background(Theme.background)
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").foregroundStyle(Theme.secondaryText)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .fullScreenCover(isPresented: $showScanner) {
                DocumentScanner(
                    onScan: { image in
                        showScanner = false
                        if let data = image.jpegForUpload() {
                            Task { await state.scanReceipt(imageData: data) }
                        }
                    },
                    onCancel: { showScanner = false }
                )
                .ignoresSafeArea()
            }
            .confirmationDialog("Scan fridge", isPresented: $showFridgeOptions) {
                Button("Take photo") {
                    if CameraPicker.isAvailable {
                        showFridgeCamera = true
                    } else {
                        state.errorMessage = "No camera here (the Simulator has none). Use \"Choose from Photos\"."
                    }
                }
                Button("Choose from Photos") { showFridgePhotos = true }
            }
            .fullScreenCover(isPresented: $showFridgeCamera) {
                CameraPicker(
                    onPhoto: { image in
                        showFridgeCamera = false
                        if let data = image.jpegForUpload() {
                            Task { await state.scanFridge(imageData: data) }
                        }
                    },
                    onCancel: { showFridgeCamera = false }
                )
                .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showFridgePhotos, selection: $fridgePhotoItem, matching: .images)
            .onChange(of: fridgePhotoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpeg = image.jpegForUpload() {
                        await state.scanFridge(imageData: jpeg)
                    } else {
                        state.errorMessage = "Couldn't read that photo."
                    }
                    fridgePhotoItem = nil
                }
            }
            .sheet(isPresented: Binding(
                get: { state.fridgeItems != nil },
                set: { if !$0 { state.fridgeItems = nil } }
            )) {
                FridgeReviewView(items: state.fridgeItems ?? [])
            }
            .task {
                // For screenshots: launch with `-openSheet Settings` (or `Fridge` for sample results).
                let sheet = UserDefaults.standard.string(forKey: "openSheet")
                guard sheet == "Settings" || sheet == "Fridge" else { return }
                try? await Task.sleep(for: .milliseconds(600))
                if sheet == "Settings" { showSettings = true } else { state.fridgeItems = Mock.fridgeItems }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(item: $editing) { item in
                EditItemView(item: item)
            }
            .onChange(of: photoItem) { _, newItem in
                guard let newItem else { return }
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data),
                       let jpeg = image.jpegForUpload() {
                        await state.scanReceipt(imageData: jpeg)
                    } else {
                        state.errorMessage = "Couldn't read that photo."
                    }
                    photoItem = nil
                }
            }
        }
    }
}

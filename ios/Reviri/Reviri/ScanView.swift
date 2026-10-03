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

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        if VNDocumentCameraViewController.isSupported {
                            showScanner = true
                        } else {
                            state.errorMessage = "The camera scanner isn't available here (the Simulator has no camera). Use \"Choose from Photos\" or \"Use demo receipt\"."
                        }
                    } label: {
                        Label("Scan receipt", systemImage: "camera.viewfinder")
                    }

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose from Photos", systemImage: "photo")
                    }

                    Button {
                        Task { await state.useDemoReceipt() }
                    } label: {
                        Label("Use demo receipt", systemImage: "doc.text")
                    }
                } footer: {
                    Text("Receipts give us exact quantities. Scan after every grocery trip.")
                }

                if !state.lastScan.isEmpty {
                    Section("Just added (tap to fix an amount)") {
                        ForEach(state.lastScan) { item in
                            InventoryRow(item: item)
                                .onTapGesture { editing = item }
                        }
                    }
                }
            }
            .navigationTitle("Scan")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
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

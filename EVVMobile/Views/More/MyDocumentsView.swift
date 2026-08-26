import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - My Documents (server mode)
// Staff compliance documents — mirrors the dashboard staff-profile Documents
// section (evv-poc v0.4.194). Staff see their own requirement slots, upload a
// photo or PDF against each one, and the server's AI review does the rest.
//
// ⚠️ NO OFFLINE MODE — deliberate, per Nick 2026-08-18. Uploads happen live or
// not at all; nothing is queued. When offline the upload buttons are disabled
// with a clear message.
struct MyDocumentsView: View {
    @EnvironmentObject var appState: AppState

    @State private var slots: [StaffDocumentSlot] = []
    @State private var isLoading = false
    @State private var loadError: String?

    // Upload flow
    @State private var uploadTarget: StaffDocumentSlot?
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var isUploading = false
    @State private var uploadingTypeId: Int?
    @State private var uploadMessage: String?
    @State private var uploadError: String?

    var body: some View {
        List {
            if !appState.effectivelyOnline {
                Section {
                    Label("You're offline. Documents can only be viewed and uploaded while connected — uploads are never queued.", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundColor(Theme.danger)
                }
            }

            if let msg = uploadMessage {
                Section {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundColor(Theme.success)
                }
            }
            if let err = uploadError {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundColor(Theme.danger)
                }
            }

            if isLoading && slots.isEmpty {
                Section { HStack { ProgressView(); Text("Loading your documents…").foregroundColor(.secondary) } }
            } else if let err = loadError, slots.isEmpty {
                Section {
                    Text(err).foregroundColor(Theme.danger).font(.subheadline)
                    Button("Try Again") { Task { await load() } }
                }
            } else if slots.isEmpty && !isLoading {
                Section { Text("No document requirements apply to you right now. 🎉").foregroundColor(.secondary) }
            } else {
                Section(footer: Text("Uploads are reviewed automatically — the document type and expiration date are checked within a minute. PDF, JPG, or PNG; a clear photo works.")) {
                    ForEach(slots) { slot in
                        documentRow(slot)
                    }
                }
            }
        }
        .navigationTitle("My Documents")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .sheet(isPresented: $showPhotoPicker) {
            PhotoLibraryPicker { image in
                if let target = uploadTarget, let data = image?.jpegData(compressionQuality: 0.85) {
                    Task { await upload(slot: target, data: data, filename: "photo.jpg", mime: "image/jpeg") }
                }
            }
        }
        // Camera capture — full screen (UIImagePickerController's camera UI is
        // designed for full screen; presenting it in a sheet clips the controls).
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapturePicker { image in
                if let target = uploadTarget, let data = image?.jpegData(compressionQuality: 0.85) {
                    Task { await upload(slot: target, data: data, filename: "camera.jpg", mime: "image/jpeg") }
                }
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFilePicker,
                      allowedContentTypes: [.pdf, .jpeg, .png],
                      allowsMultipleSelection: false) { result in
            guard let target = uploadTarget, case .success(let urls) = result, let url = urls.first else { return }
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                uploadError = "Couldn't read that file — try a different one."
                return
            }
            let ext = url.pathExtension.lowercased()
            let mime = ext == "pdf" ? "application/pdf" : (ext == "png" ? "image/png" : "image/jpeg")
            Task { await upload(slot: target, data: data, filename: url.lastPathComponent, mime: mime) }
        }
    }

    @ViewBuilder
    private func documentRow(_ slot: StaffDocumentSlot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(slot.name).font(.subheadline.weight(.semibold))
                    Text(slot.category).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(slot.statusLabel)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(chipColor(slot.chip).opacity(0.15))
                    .foregroundColor(chipColor(slot.chip))
                    .cornerRadius(8)
            }
            if let expires = slot.expiresOn {
                Text("Expires \(expires)").font(.caption).foregroundColor(.secondary)
            }
            if let reason = slot.rejectReason, !reason.isEmpty {
                Text(reason).font(.caption).foregroundColor(Theme.danger)
            }
            if slot.statusKey == "reviewing" {
                Text("Checking the document type and expiration date…").font(.caption).foregroundColor(.secondary)
            }
            if slot.statusKey == "needs_review" {
                Text("Accepted pending review — an administrator will confirm the details.").font(.caption).foregroundColor(.secondary)
            }
            if let file = slot.fileName, !file.isEmpty {
                Label(file, systemImage: "doc").font(.caption).foregroundColor(.secondary).lineLimit(1)
            }

            if isUploading && uploadingTypeId == slot.typeId {
                HStack(spacing: 8) { ProgressView().scaleEffect(0.8); Text("Uploading…").font(.caption).foregroundColor(.secondary) }
            } else {
                HStack(spacing: 12) {
                    // Camera first — the fastest path when the document is in your hand.
                    // Hidden on devices without a camera (e.g. Simulator) because
                    // UIImagePickerController crashes if .camera is unavailable.
                    if CameraCapturePicker.isAvailable {
                        Button {
                            uploadTarget = slot
                            showCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    Button {
                        uploadTarget = slot
                        showPhotoPicker = true
                    } label: {
                        Label(slot.fileName == nil ? "Photos" : "Replace — Photos", systemImage: "photo")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    Button {
                        uploadTarget = slot
                        showFilePicker = true
                    } label: {
                        Label("File / PDF", systemImage: "folder")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                .disabled(!appState.effectivelyOnline || isUploading)
            }
        }
        .padding(.vertical, 4)
    }

    private func chipColor(_ chip: String) -> Color {
        switch chip {
        case "ok": return Theme.success
        case "warn": return Theme.warning
        case "danger": return Theme.danger
        default: return .secondary
        }
    }

    private func load() async {
        guard appState.effectivelyOnline else {
            if slots.isEmpty { loadError = "You're offline — reconnect to see your documents." }
            return
        }
        isLoading = true
        loadError = nil
        do {
            slots = try await APIClient.shared.fetchMyDocuments()
        } catch {
            loadError = "Couldn't load your documents: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func upload(slot: StaffDocumentSlot, data: Data, filename: String, mime: String) async {
        guard appState.effectivelyOnline else {
            uploadError = "You're offline — uploads are never queued, so reconnect and try again."
            return
        }
        isUploading = true
        uploadingTypeId = slot.typeId
        uploadMessage = nil
        uploadError = nil
        do {
            let resp = try await APIClient.shared.uploadStaffDocument(typeId: slot.typeId, fileData: data, filename: filename, mimeType: mime)
            uploadMessage = "✓ \(slot.name) uploaded. \(resp.message ?? "It's being reviewed now.") Pull to refresh for the result."
            await load()
        } catch let APIError.serverError(_, message) {
            uploadError = message
        } catch {
            uploadError = "Upload failed: \(error.localizedDescription)"
        }
        isUploading = false
        uploadingTypeId = nil
    }
}

// MARK: - Camera capture wrapper (UIImagePickerController, source = .camera)
// Used for "take a picture right there" document uploads (Nick 2026-08-26).
// Rear camera, no editing overlay — a document photo should be the full frame.
struct CameraCapturePicker: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCapture: onCapture) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage?) -> Void
        init(onCapture: @escaping (UIImage?) -> Void) { self.onCapture = onCapture }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            let image = info[.originalImage] as? UIImage
            DispatchQueue.main.async { self.onCapture(image) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            DispatchQueue.main.async { self.onCapture(nil) }
        }
    }
}

// MARK: - PHPicker wrapper (iOS 15-compatible photo library picker)
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPick: (UIImage?) -> Void
        init(onPick: @escaping (UIImage?) -> Void) { self.onPick = onPick }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider, provider.canLoadObject(ofClass: UIImage.self) else {
                onPick(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async { self.onPick(object as? UIImage) }
            }
        }
    }
}

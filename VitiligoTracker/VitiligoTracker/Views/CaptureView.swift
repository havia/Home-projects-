import SwiftUI
import SwiftData
import PhotosUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

struct CaptureView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var spots: [Spot]

    // Photo/video selection
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var selectedMediaURL: URL? = nil

    // Camera
    @State private var showCamera = false

    // Treatment form
    @State private var uvMinutes: Double = 0
    @State private var medicineDose: String = ""
    @State private var treatmentNotes: String = ""

    // Processing state
    @State private var isAnalyzing = false
    @State private var analysisError: String? = nil
    @State private var showError = false
    @State private var showTips = false

    // Navigation to result
    @State private var analyzedSession: Session? = nil
    @State private var showResult = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Tips card
                    tipsCard

                    // Photo preview or placeholder
                    photoPreviewSection

                    // Import/Camera buttons
                    captureButtons

                    if selectedImage != nil {
                        // Treatment form
                        treatmentFormSection

                        // Analyze button
                        analyzeButton
                    }
                }
                .padding()
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.large)
            .sheet(isPresented: $showCamera) {
                CameraPickerView(selectedImage: $selectedImage, selectedURL: $selectedMediaURL)
            }
            .alert("Analysis Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(analysisError ?? "Unknown error occurred.")
            }
            .navigationDestination(isPresented: $showResult) {
                if let session = analyzedSession {
                    SpotMapView(session: session)
                }
            }
        }
        .onChange(of: selectedItem) { _, newItem in
            Task {
                await loadSelectedItem(newItem)
            }
        }
    }

    // MARK: - Tips Card

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Camera Tips", systemImage: "lightbulb.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
                Button(showTips ? "Hide" : "Show") {
                    withAnimation { showTips.toggle() }
                }
                .font(.subheadline)
                .foregroundStyle(.blue)
            }

            if showTips {
                VStack(alignment: .leading, spacing: 6) {
                    tipRow(icon: "sun.max.fill", text: "Use natural daylight or bright, even indoor lighting")
                    tipRow(icon: "iphone", text: "Hold phone 30-40 cm from face — iPhone 15 Pro main camera")
                    tipRow(icon: "person.fill.viewfinder", text: "Face camera straight on, chin level, neutral expression")
                    tipRow(icon: "repeat", text: "Same distance and angle each session for accurate comparison")
                    tipRow(icon: "paintpalette.fill", text: "Avoid strong colored lights — white or daylight is best")
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.orange)
                .frame(width: 20)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Photo Preview

    private var photoPreviewSection: some View {
        Group {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.blue.opacity(0.4), lineWidth: 2)
                    )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .frame(height: 200)
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No photo selected")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Capture Buttons

    private var captureButtons: some View {
        HStack(spacing: 16) {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .font(.headline)
            }

            PhotosPicker(
                selection: $selectedItem,
                matching: .any(of: [.images, .videos]),
                photoLibrary: .shared()
            ) {
                Label("Import", systemImage: "photo.on.rectangle.angled")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundStyle(.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .font(.headline)
            }
        }
    }

    // MARK: - Treatment Form

    private var treatmentFormSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Treatment Details")
                .font(.headline)

            // UV Minutes stepper
            VStack(alignment: .leading, spacing: 6) {
                Text("UV Light Duration")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack {
                    Stepper(
                        value: $uvMinutes,
                        in: 0...60,
                        step: 0.5
                    ) {
                        Text("\(uvMinutes, specifier: "%.1f") min")
                            .font(.body)
                            .monospacedDigit()
                    }
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Medicine dose
            VStack(alignment: .leading, spacing: 6) {
                Text("Medicine / Cream Applied")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., Tacrolimus 0.1%, 2 pumps", text: $medicineDose)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Notes
            VStack(alignment: .leading, spacing: 6) {
                Text("Session Notes (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., slight redness, good response", text: $treatmentNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...5)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Analyze Button

    private var analyzeButton: some View {
        Button {
            Task { await analyzeAndSave() }
        } label: {
            HStack(spacing: 12) {
                if isAnalyzing {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    Text("Analyzing...")
                } else {
                    Image(systemName: "waveform.path.ecg")
                    Text("Analyze & Save Session")
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isAnalyzing ? Color.gray : Color.green)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .font(.headline)
        }
        .disabled(isAnalyzing)
    }

    // MARK: - Logic

    private func loadSelectedItem(_ item: PhotosPickerItem?) async {
        guard let item = item else { return }

        // Try to load as video URL first
        if let videoURL = try? await item.loadTransferable(type: VideoTransferable.self) {
            await MainActor.run {
                selectedMediaURL = videoURL.url
            }
            // Extract best frame from video
            do {
                let extractor = VideoFrameExtractor()
                let frameURL = try await extractor.extractBestFrame(from: videoURL.url)
                if let image = UIImage(contentsOfFile: frameURL.path) {
                    await MainActor.run {
                        selectedImage = image
                        selectedMediaURL = frameURL
                    }
                }
            } catch {
                await MainActor.run {
                    analysisError = error.localizedDescription
                    showError = true
                }
            }
            return
        }

        // Load as image
        if let data = try? await item.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            // Save to temp
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("imported_\(UUID().uuidString).jpg")
            if let jpeg = image.jpegData(compressionQuality: 0.90) {
                try? jpeg.write(to: tempURL)
            }
            await MainActor.run {
                selectedImage = image
                selectedMediaURL = tempURL
            }
        }
    }

    private func analyzeAndSave() async {
        guard let mediaURL = selectedMediaURL else { return }

        await MainActor.run { isAnalyzing = true }

        do {
            let processor = ImageProcessor()
            var (session, _) = try await processor.analyzePhoto(
                at: mediaURL,
                existingSpots: spots,
                modelContext: modelContext
            )

            // Update treatment info on session
            session.uvMinutes = uvMinutes
            session.medicineDose = medicineDose
            session.treatmentNotes = treatmentNotes

            try modelContext.save()

            await MainActor.run {
                isAnalyzing = false
                analyzedSession = session
                showResult = true
                resetForm()
            }
        } catch {
            await MainActor.run {
                isAnalyzing = false
                analysisError = error.localizedDescription
                showError = true
            }
        }
    }

    private func resetForm() {
        selectedItem = nil
        selectedImage = nil
        selectedMediaURL = nil
        uvMinutes = 0
        medicineDose = ""
        treatmentNotes = ""
    }
}

// MARK: - Video Transferable

struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("video_\(UUID().uuidString).mov")
            try FileManager.default.copyItem(at: received.file, to: tempURL)
            return VideoTransferable(url: tempURL)
        }
    }
}

// MARK: - Camera Picker

struct CameraPickerView: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Binding var selectedURL: URL?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"]
        picker.cameraCaptureMode = .photo
        picker.cameraDevice = .rear
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImage = image

                // Save captured image to temp file
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("camera_\(UUID().uuidString).jpg")
                if let jpeg = image.jpegData(compressionQuality: 0.90) {
                    try? jpeg.write(to: tempURL)
                    parent.selectedURL = tempURL
                }
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

#Preview {
    CaptureView()
        .modelContainer(for: [Session.self, Spot.self, SpotMeasurement.self], inMemory: true)
}

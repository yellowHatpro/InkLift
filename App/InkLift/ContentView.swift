import SwiftUI
import PhotosUI
import InkCore

struct ContentView: View {
    @StateObject private var model = ConversionModel()
    @State private var pickerItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var shareURL: URL?
    @State private var errorText: String?

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("InkLift")
        } detail: {
            detail
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in model.load(image) }
                .ignoresSafeArea()
        }
        .sheet(item: $shareURL) { url in
            ShareSheet(items: [url])
        }
        .alert("Export failed", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
            Button("OK") { errorText = nil }
        } message: { Text(errorText ?? "") }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                    model.load(img)
                }
                pickerItem = nil
            }
        }
    }

    private var sidebar: some View {
        List {
            Section("1. Photo") {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose from Photos", systemImage: "photo.on.rectangle")
                }
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button { showCamera = true } label: { Label("Take Photo", systemImage: "camera") }
                }
                if let img = model.source {
                    Image(uiImage: img)
                        .resizable().scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Section("2. Trace") {
                Toggle("Find and flatten the page", isOn: $model.rectify)
                    .onChange(of: model.rectify) { _, _ in if model.source != nil { model.run() } }
                switch model.state {
                case .idle: Text("Pick a photo of handwriting.").foregroundStyle(.secondary)
                case .processing: HStack { ProgressView(); Text("Tracing ink...") }
                case .ready: Text("\(model.strokeCount) strokes").foregroundStyle(.secondary)
                case .failed(let msg): Text(msg).foregroundStyle(.red)
                }
            }
            Section("3. Export") {
                ForEach(ConversionModel.ExportKind.allCases) { kind in
                    Button {
                        do { shareURL = try model.export(as: kind) } catch { errorText = error.localizedDescription }
                    } label: {
                        Label("Share as \(kind.label)", systemImage: kind == .goodnotes ? "pencil.and.outline" : "doc.richtext")
                    }
                    .disabled(model.state != .ready)
                }
                Text("GoodNotes: open the shared file in Goodnotes to get editable ink. PDF: flat strokes, any app.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if model.page != nil {
            let size = GoodNotesExporter.templatePage
            CanvasView(drawing: $model.drawing, pageSize: CGSize(width: size.width, height: size.height))
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView("No page yet", systemImage: "scribble.variable",
                                   description: Text("Choose or take a photo of your handwritten notes."))
        }
    }
}

extension URL: Identifiable { public var id: String { absoluteString } }

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.onImage(img) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

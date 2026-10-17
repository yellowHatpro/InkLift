import Foundation
import SwiftUI
import InkCore
import PencilKit

@MainActor
final class ConversionModel: ObservableObject {
    enum State: Equatable {
        case idle
        case processing
        case ready
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var source: UIImage?
    @Published var page: Page?
    @Published var drawing = PKDrawing()
    @Published var strokeCount = 0
    @Published var rectify = true
    @Published var exportURL: URL?

    private var task: Task<Void, Never>?

    func load(_ image: UIImage) {
        source = image
        run()
    }

    func run() {
        guard let cg = source?.normalizedCGImage() else { return }
        task?.cancel()
        state = .processing
        let rectify = self.rectify
        task = Task.detached(priority: .userInitiated) { [weak self] in
            var options = InkPipelineOptions()
            options.rectify = rectify
            options.pageSize = GoodNotesExporter.templatePage
            options.margin = 24
            let (page, _) = InkPipeline(options: options).process(cg)
            let drawing = PencilKitBridge.drawing(for: page)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.page = page
                self.drawing = drawing
                self.strokeCount = page.strokes.count
                self.state = page.strokes.isEmpty ? .failed("No ink found. Try better light or a closer shot.") : .ready
            }
        }
    }

    /// Writes the document to the app's Documents folder and returns the URL for sharing.
    func export(as kind: ExportKind) throws -> URL {
        guard let page else { throw ExportError.nothingToExport }
        let name = "InkLift " + Self.stamp.string(from: Date())
        let doc = InkDocument(title: name, pages: [page])
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = dir.appendingPathComponent(name).appendingPathExtension(kind.fileExtension)
        switch kind {
        case .goodnotes: try GoodNotesExporter().write(doc, to: url)
        case .pdf: try PDFExporter().write(doc, to: url)
        }
        exportURL = url
        return url
    }

    enum ExportKind: String, CaseIterable, Identifiable {
        case goodnotes, pdf
        var id: String { rawValue }
        var fileExtension: String { rawValue }
        var label: String { self == .goodnotes ? "GoodNotes" : "PDF" }
    }

    enum ExportError: LocalizedError {
        case nothingToExport
        var errorDescription: String? { "Convert a photo first." }
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH.mm"
        return f
    }()
}

extension UIImage {
    /// CGImage with EXIF orientation applied, so Vision and the tracer see the page upright.
    func normalizedCGImage() -> CGImage? {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return img.cgImage
    }
}

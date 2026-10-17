import SwiftUI
import AppKit
import InkCore

@MainActor
final class MacModel: ObservableObject {
    enum State: Equatable { case idle, processing, ready, failed(String) }

    @Published var state: State = .idle
    @Published var sourceURL: URL?
    @Published var source: NSImage?
    @Published var page: Page?
    @Published var preview: NSImage?
    @Published var rectify = true
    @Published var lastExport: URL?
    @Published var dropTargeted = false

    private var task: Task<Void, Never>?

    func open(_ url: URL) {
        guard let cg = try? ImageFile.load(url) else {
            state = .failed("Could not read \(url.lastPathComponent)")
            return
        }
        sourceURL = url
        source = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        run(cg)
    }

    func rerun() {
        guard let url = sourceURL, let cg = try? ImageFile.load(url) else { return }
        run(cg)
    }

    private func run(_ cg: CGImage) {
        task?.cancel()
        state = .processing
        let rectify = self.rectify
        task = Task.detached(priority: .userInitiated) { [weak self] in
            var options = InkPipelineOptions()
            options.rectify = rectify
            options.pageSize = GoodNotesExporter.templatePage
            options.margin = 24
            let (page, _) = InkPipeline(options: options).process(cg)
            let rendered = PDFExporter.render(page, scale: 2)
            await MainActor.run {
                guard let self, !Task.isCancelled else { return }
                self.page = page
                self.preview = rendered.map { NSImage(cgImage: $0, size: NSSize(width: page.size.width, height: page.size.height)) }
                self.state = page.strokes.isEmpty ? .failed("No ink found. Try a sharper, brighter photo.") : .ready
            }
        }
    }

    func export(goodnotes: Bool) {
        guard let page else { return }
        let panel = NSSavePanel()
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "InkLift"
        panel.nameFieldStringValue = base + (goodnotes ? ".goodnotes" : ".pdf")
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let doc = InkDocument(title: base, pages: [page])
        do {
            if goodnotes { try GoodNotesExporter().write(doc, to: url) } else { try PDFExporter().write(doc, to: url) }
            lastExport = url
        } catch {
            state = .failed("Export failed: \(error)")
        }
    }

    func openInGoodnotes() {
        guard let url = lastExport else { return }
        let gn = URL(fileURLWithPath: "/Applications/Goodnotes.app")
        if FileManager.default.fileExists(atPath: gn.path) {
            NSWorkspace.shared.open([url], withApplicationAt: gn, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(url)
        }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
}

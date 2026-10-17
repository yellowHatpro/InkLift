import SwiftUI
import AppKit
import UniformTypeIdentifiers
import InkCore

struct MacContentView: View {
    @ObservedObject var model: MacModel

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                pane(title: "Photo") {
                    if let img = model.source {
                        Image(nsImage: img).resizable().scaledToFit().padding()
                    } else {
                        dropHint
                    }
                }
                Divider()
                pane(title: "Ink") {
                    switch model.state {
                    case .idle:
                        Text("The traced strokes appear here.").foregroundStyle(.secondary)
                    case .processing:
                        ProgressView("Tracing ink...")
                    case .failed(let msg):
                        Text(msg).foregroundStyle(.red).padding()
                    case .ready:
                        if let p = model.preview {
                            Image(nsImage: p).resizable().scaledToFit()
                                .shadow(radius: 6).padding()
                        }
                    }
                }
            }
            Divider()
            statusBar
        }
        .frame(minWidth: 900, minHeight: 600)
        .onDrop(of: [.fileURL], isTargeted: $model.dropTargeted) { providers in
            guard let p = providers.first else { return false }
            _ = p.loadObject(ofClass: URL.self) { url, _ in
                if let url { Task { @MainActor in model.open(url) } }
            }
            return true
        }
        .overlay {
            if model.dropTargeted {
                RoundedRectangle(cornerRadius: 12).stroke(Color.accentColor, lineWidth: 4).padding(6)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button { model.chooseFile() } label: { Label("Open Photo...", systemImage: "photo") }
                .keyboardShortcut("o")
            Toggle("Find and flatten page", isOn: $model.rectify)
                .onChange(of: model.rectify) { _, _ in model.rerun() }
                .toggleStyle(.checkbox)
            Spacer()
            Button { model.export(goodnotes: true) } label: { Label("Export GoodNotes...", systemImage: "pencil.and.outline") }
                .keyboardShortcut("e")
                .disabled(model.state != .ready)
            Button { model.export(goodnotes: false) } label: { Label("Export PDF...", systemImage: "doc.richtext") }
                .disabled(model.state != .ready)
        }
        .padding(10)
    }

    private var statusBar: some View {
        HStack {
            switch model.state {
            case .ready: Text("\(model.page?.strokes.count ?? 0) strokes").foregroundStyle(.secondary)
            case .idle: Text("Drop a photo of handwritten notes, or press ⌘O.").foregroundStyle(.secondary)
            default: EmptyView()
            }
            Spacer()
            if let url = model.lastExport {
                Text("Saved \(url.lastPathComponent)").foregroundStyle(.secondary)
                Button("Open in Goodnotes") { model.openInGoodnotes() }
            }
        }
        .font(.callout)
        .padding(8)
    }

    private var dropHint: some View {
        VStack(spacing: 12) {
            Image(systemName: "scribble.variable").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Drop a photo here").font(.title3)
            Text("or press ⌘O").foregroundStyle(.secondary)
        }
    }

    private func pane<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            Text(title).font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
            ZStack { Color(nsColor: .windowBackgroundColor); content() }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

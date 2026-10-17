import Foundation
import InkCore

// inklift <photo> [-o out.pdf|out.goodnotes] [--no-rectify] [--debug-dir DIR] [--page letter|a4]

func usage() -> Never {
    FileHandle.standardError.write("""
    usage: inklift <photo> [-o out.pdf|out.goodnotes] [--no-rectify] [--debug-dir DIR] [--page letter|a4]

    """.data(using: .utf8)!)
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
guard !args.isEmpty else { usage() }

var input: String? = nil
var output: String? = nil
var debugDir: String? = nil
var options = InkPipelineOptions()

while !args.isEmpty {
    let a = args.removeFirst()
    switch a {
    case "-o": guard !args.isEmpty else { usage() }; output = args.removeFirst()
    case "--no-rectify": options.rectify = false
    case "--debug-dir": guard !args.isEmpty else { usage() }; debugDir = args.removeFirst()
    case "--page":
        guard !args.isEmpty else { usage() }
        switch args.removeFirst() {
        case "a4": options.pageSize = .a4
        case "letter": options.pageSize = .letter
        default: usage()
        }
    default:
        if a.hasPrefix("-") { usage() }
        input = a
    }
}

guard let inputPath = input else { usage() }
let inputURL = URL(fileURLWithPath: inputPath)
let outURL = URL(fileURLWithPath: output ?? inputURL.deletingPathExtension().appendingPathExtension("pdf").path)

do {
    let start = Date()
    let image = try ImageFile.load(inputURL)
    let (page, debug) = InkPipeline(options: options).process(image)
    let title = inputURL.deletingPathExtension().lastPathComponent
    let doc = InkDocument(title: title, pages: [page])

    switch outURL.pathExtension.lowercased() {
    case "goodnotes":
        try GoodNotesExporter().write(doc, to: outURL)
    case "json":
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        try enc.encode(doc).write(to: outURL)
    default:
        try PDFExporter().write(doc, to: outURL)
    }

    if let dir = debugDir {
        let d = URL(fileURLWithPath: dir)
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try ImageFile.savePNG(debug.rectified, to: d.appendingPathComponent("1-rectified.png"))
        try ImageFile.savePNG(debug.binary.toGray().cgImage(), to: d.appendingPathComponent("2-binary.png"))
        try ImageFile.savePNG(debug.skeleton.toGray().cgImage(), to: d.appendingPathComponent("3-skeleton.png"))
        if let r = PDFExporter.render(page) {
            try ImageFile.savePNG(r, to: d.appendingPathComponent("4-strokes.png"))
        }
    }
    let ms = Int(Date().timeIntervalSince(start) * 1000)
    let totalPts = page.strokes.reduce(0) { $0 + $1.points.count }
    print("\(outURL.path): \(page.strokes.count) strokes, \(totalPts) points, \(debug.gray.width)x\(debug.gray.height) px, \(ms) ms")
} catch {
    FileHandle.standardError.write("inklift: \(error)\n".data(using: .utf8)!)
    exit(1)
}

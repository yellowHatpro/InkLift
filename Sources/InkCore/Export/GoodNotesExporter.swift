import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Writes a `.goodnotes` document with editable ballpoint strokes.
///
/// The container is a ZIP of protobuf streams. This writer keeps a one-page template
/// (indexes, events, background PDF) as package resources and replaces the page's stroke
/// stream, search index and thumbnail. Format notes: docs/goodnotes-format.md.
public struct GoodNotesExporter {
    public enum Error: Swift.Error {
        case templateMissing(String)
        case emptyDocument
    }

    /// GoodNotes page coordinates per PDF point (observed: 834.24 GN units for a 455.04 pt page).
    public static let unitsPerPoint = 132.0 / 72.0
    /// Template page size in PDF points (its background PDF MediaBox).
    public static let templatePage = PageSize(width: 455.04, height: 588.45)

    static let pageUUID = "47C42002-8FC8-521C-80C0-A3C6E11DA9C1"
    static let attachmentUUID = "F8C077F2-68CA-5AFC-B1D1-EFEA5ED4D254"
    /// Opaque per-record constants copied from documents written by GoodNotes 7.1.
    static let deviceTag: UInt64 = 1_184_897_455_800_006_800
    static let appTag: UInt64 = 5381
    static let ballpointType: UInt64 = 24

    public init() {}

    public func write(_ document: InkDocument, to url: URL) throws {
        try data(for: document).write(to: url)
    }

    public func data(for document: InkDocument) throws -> Data {
        guard let page = document.pages.first else { throw Error.emptyDocument }
        let template = try Self.loadTemplate()

        var zip = ZipWriter()
        zip.add("document.info.pb", Data())
        zip.add("index.search.pb", try template("index.search.pb"))
        zip.add("index.notes.pb", try template("index.notes.pb"))
        zip.add("search/\(Self.pageUUID)", Data([0x04, 0x10, 0x01, 0x1A, 0x00]))
        zip.add("search/\(Self.attachmentUUID)", try template("search/\(Self.attachmentUUID)"))
        zip.add("notes/\(Self.pageUUID)", Self.noteStream(for: page))
        zip.add("index.events.pb", try template("index.events.pb"))
        if let thumb = Self.thumbnail(for: page) { zip.add("thumbnail.jpg", thumb) }
        zip.add("index.attachments.pb", try template("index.attachments.pb"))
        zip.add("attachments/\(Self.attachmentUUID)", try template("attachments/\(Self.attachmentUUID)"))
        zip.add("schema.pb", try template("schema.pb"))
        return zip.finish()
    }

    // MARK: Page stream

    /// Two records per stroke: a metadata record (uuid, type) and the stroke record.
    static func noteStream(for page: Page) -> Data {
        let fit = Self.fit(page.size, into: templatePage)
        var out = Data()
        var counter: UInt64 = 3_653_600
        let now = UInt64(Date().timeIntervalSince1970 * 1000)
        for stroke in page.strokes where !stroke.points.isEmpty {
            counter += 1
            var pts = stroke.points.map { p -> (Float, Float) in
                let x = (fit.offsetX + p.x * fit.scale) * unitsPerPoint
                let y = (fit.offsetY + p.y * fit.scale) * unitsPerPoint
                return (Float(x), Float(y))
            }
            if pts.count == 1 { pts.append((pts[0].0 + 0.01, pts[0].1 + 0.01)) }
            let width = Float(max(0.5, stroke.averageWidth * fit.scale * unitsPerPoint))
            let tpl = tplBallpoint(width: width, points: pts)
            guard let lz4 = try? (tpl as NSData).compressed(using: .lz4) as Data else { continue }
            out.append(strokeRecords(uuid: UUID().uuidString, lz4: lz4, color: stroke.color, counter: counter, timestamp: now))
        }
        return out
    }

    struct Fit { var scale: Double; var offsetX: Double; var offsetY: Double }

    static func fit(_ from: PageSize, into to: PageSize) -> Fit {
        let s = min(to.width / from.width, to.height / from.height)
        return Fit(scale: s, offsetX: (to.width - from.width * s) / 2, offsetY: (to.height - from.height * s) / 2)
    }

    static func strokeRecords(uuid: String, lz4: Data, color: StrokeColor, counter: UInt64, timestamp: UInt64) -> Data {
        let salt = UInt64(UInt32.random(in: 0...UInt32.max))
        var clock = ProtoWriter()
        clock.varint(1, 2)
        clock.varint(2, salt)

        var meta = ProtoWriter()
        meta.string(1, uuid)
        meta.message(2, clock)
        meta.string(6, UUID().uuidString)
        meta.varint(8, deviceTag)
        meta.varint(9, counter)
        meta.varint(14, appTag)
        meta.varint(16, ballpointType)

        var rgba = ProtoWriter()
        rgba.fixed32(1, Float(color.r))
        rgba.fixed32(2, Float(color.g))
        rgba.fixed32(3, Float(color.b))
        rgba.fixed32(4, Float(color.a))

        var stamp = ProtoWriter()
        stamp.varint(1, counter)
        stamp.varint(2, timestamp)
        var stampBox = ProtoWriter()
        stampBox.message(1, stamp)

        var inner = ProtoWriter()
        inner.string(1, uuid)
        inner.bytes(2, lz4)
        inner.message(4, rgba)
        inner.bytes(6, Data())
        inner.message(7, stampBox)
        inner.bytes(9, Data())
        inner.message(15, clock)
        inner.bytes(20, Data())
        inner.varint(21, ballpointType)

        var stroke = ProtoWriter()
        stroke.message(7, inner)
        return meta.record() + stroke.record()
    }

    // MARK: TPL

    /// `vuA(v)A(S(uu))A(S(uuuu))vA(f)`: version, width, pen-down flags, start point,
    /// then two points per tuple. Floats are stored as their IEEE-754 bit patterns.
    static func tplBallpoint(width: Float, points: [(Float, Float)]) -> Data {
        let format = Data("vuA(v)A(S(uu))A(S(uuuu))vA(f)".utf8) + Data([0])
        var body = Data()
        body.append(u16(2))
        body.append(f32(width))
        var rest = Array(points.dropFirst())
        if rest.count % 2 == 1 { rest.append(rest[rest.count - 1]) }
        let quadCount = rest.count / 2
        body.append(u32(UInt32(quadCount + 1)))
        body.append(u16(0))
        for _ in 0..<quadCount { body.append(u16(1)) }
        body.append(u32(1))
        body.append(f32(points[0].0)); body.append(f32(points[0].1))
        body.append(u32(UInt32(quadCount)))
        for i in stride(from: 0, to: rest.count, by: 2) {
            body.append(f32(rest[i].0)); body.append(f32(rest[i].1))
            body.append(f32(rest[i + 1].0)); body.append(f32(rest[i + 1].1))
        }
        body.append(u16(1))
        body.append(u32(0))
        let size = UInt32(8 + format.count + body.count)
        return Data("tpl".utf8) + Data([0]) + u32(size) + format + body
    }

    private static func u16(_ v: UInt16) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 2) }
    private static func u32(_ v: UInt32) -> Data { var x = v.littleEndian; return Data(bytes: &x, count: 4) }
    private static func f32(_ v: Float) -> Data { u32(v.bitPattern) }

    // MARK: Resources

    static func loadTemplate() throws -> (String) throws -> Data {
        guard let root = Bundle.module.url(forResource: "goodnotes-template", withExtension: nil) else {
            throw Error.templateMissing("goodnotes-template")
        }
        return { name in
            let url = root.appendingPathComponent(name)
            guard let d = try? Data(contentsOf: url) else { throw Error.templateMissing(name) }
            return d
        }
    }

    static func thumbnail(for page: Page) -> Data? {
        var scaled = page
        let fit = Self.fit(page.size, into: templatePage)
        scaled.size = templatePage
        scaled.strokes = page.strokes.map { s in
            Stroke(points: s.points.map {
                StrokePoint(x: fit.offsetX + $0.x * fit.scale, y: fit.offsetY + $0.y * fit.scale, width: $0.width * fit.scale)
            }, color: s.color)
        }
        guard let img = PDFExporter.render(scaled, scale: 1) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? out as Data : nil
    }
}

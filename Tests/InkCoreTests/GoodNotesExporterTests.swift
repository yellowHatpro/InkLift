import Testing
import Foundation
import CoreGraphics
@testable import InkCore

struct GoodNotesExporterTests {
    func sampleDoc() -> InkDocument {
        var o = InkPipelineOptions(); o.rectify = false
        let (page, _) = InkPipeline(options: o).process(Fixture.cross())
        return InkDocument(title: "cross", pages: [page])
    }

    @Test func tplImageIsSelfConsistent() {
        let pts: [(Float, Float)] = [(1, 2), (3, 4), (5, 6), (7, 8)]
        let tpl = GoodNotesExporter.tplBallpoint(width: 2.5, points: pts)
        #expect(tpl.prefix(3) == Data("tpl".utf8))
        #expect(tpl[3] == 0)
        let size = tpl[4..<8].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        #expect(Int(size) == tpl.count)
        let fmtEnd = tpl[8...].firstIndex(of: 0)!
        #expect(String(decoding: tpl[8..<fmtEnd], as: UTF8.self) == "vuA(v)A(S(uu))A(S(uuuu))vA(f)")
        // body: v(2) u(4) A(v): 4 + 2*n, A(S(uu)): 4 + 8, A(S(uuuu)): 4 + 16*q, v(2), A(f): 4
        // 3 points after start -> padded to 4 -> q = 2, flags n = q + 1 = 3
        let expectedBody = 2 + 4 + (4 + 2 * 3) + (4 + 8) + (4 + 16 * 2) + 2 + 4
        #expect(tpl.count - (fmtEnd + 1) == expectedBody)
    }

    @Test func lz4IsAppleFramed() throws {
        let tpl = GoodNotesExporter.tplBallpoint(width: 1, points: (0..<50).map { (Float($0), Float($0 * 2)) })
        let lz4 = try (tpl as NSData).compressed(using: .lz4) as Data
        #expect(lz4.prefix(4) == Data("bv41".utf8) || lz4.prefix(4) == Data("bv4-".utf8))
        #expect(lz4.suffix(4) == Data("bv4$".utf8))
        let back = try (lz4 as NSData).decompressed(using: .lz4) as Data
        #expect(back == tpl)
    }

    @Test func varintEncoding() {
        #expect(ProtoWriter.varint(0) == Data([0]))
        #expect(ProtoWriter.varint(130) == Data([0x82, 0x01]))
        #expect(ProtoWriter.varint(35) == Data([0x23]))
    }

    @Test func noteStreamHasTwoRecordsPerStroke() {
        let page = sampleDoc().pages[0]
        let stream = GoodNotesExporter.noteStream(for: page)
        var pos = 0
        var records = 0
        while pos < stream.count {
            var len: UInt64 = 0
            var shift: UInt64 = 0
            while true {
                let b = stream[pos]; pos += 1
                len |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { break }
                shift += 7
            }
            pos += Int(len)
            records += 1
        }
        #expect(pos == stream.count)
        #expect(records == page.strokes.count * 2)
    }

    @Test func archiveIsValidZipWithExpectedMembers() throws {
        let data = try GoodNotesExporter().data(for: sampleDoc())
        #expect(data.prefix(4) == Data([0x50, 0x4B, 0x03, 0x04]))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("inklift-\(UUID().uuidString).goodnotes")
        try data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #if os(macOS)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-Z1", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        try p.run()
        p.waitUntilExit()
        let names = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n").map(String.init)
        #expect(p.terminationStatus == 0)
        for required in ["schema.pb", "index.notes.pb", "index.events.pb", "index.attachments.pb",
                         "notes/\(GoodNotesExporter.pageUUID)", "attachments/\(GoodNotesExporter.attachmentUUID)", "thumbnail.jpg"] {
            #expect(names.contains(required), "missing \(required)")
        }
        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        t.arguments = ["-tq", url.path]
        t.standardOutput = FileHandle.nullDevice
        try t.run(); t.waitUntilExit()
        #expect(t.terminationStatus == 0, "zip CRC check")
        #endif
    }

    @Test func crc32KnownValue() {
        #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }
}

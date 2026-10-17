import Testing
import CoreGraphics
@testable import InkCore

struct PipelineTests {
    var noRectify: InkPipelineOptions {
        var o = InkPipelineOptions()
        o.rectify = false
        return o
    }

    // MARK: Binarizer

    @Test func testBinarizerSeparatesInkFromUnevenPaper() {
        let img = Fixture.line(from: CGPoint(x: 40, y: 150), to: CGPoint(x: 260, y: 150), width: 8)
        let truth = Fixture.inkMask(img)
        let bin = Binarizer().binarize(GrayBitmap(cgImage: img))

        var hit = 0, falseInk = 0
        for i in bin.bits.indices {
            if truth.bits[i] == 1 && bin.bits[i] == 1 { hit += 1 }
            if truth.bits[i] == 0 && bin.bits[i] == 1 { falseInk += 1 }
        }
        #expect(Double(hit) / Double(truth.inkCount) > 0.9, "recall")
        #expect(falseInk < truth.inkCount / 4, "false ink on paper despite the lighting gradient")
    }

    @Test func testSpeckleRemoval() {
        var bmp = BinaryBitmap(width: 20, height: 20)
        bmp[3, 3] = 1; bmp[4, 3] = 1          // 2-pixel speck
        for x in 5..<15 { bmp[x, 10] = 1 }    // 10-pixel line
        Binarizer().removeSmallComponents(&bmp, minPixels: 5)
        #expect(bmp[3, 3] == 0)
        #expect(bmp[10, 10] == 1)
        #expect(bmp.inkCount == 10)
    }

    // MARK: Skeleton

    @Test func testSkeletonIsThin() {
        let img = Fixture.line(from: CGPoint(x: 40, y: 150), to: CGPoint(x: 260, y: 150), width: 9)
        let bin = Binarizer().binarize(GrayBitmap(cgImage: img))
        let sk = Skeletonizer().skeletonize(bin)
        // A 220 px long, 9 px wide line reduces to roughly 220 pixels.
        #expect(sk.inkCount < 260)
        #expect(sk.inkCount > 190)
        // Every skeleton pixel has at most two 8-neighbours, except near the ends.
        var fat = 0
        for y in 1..<(sk.height - 1) {
            for x in 1..<(sk.width - 1) where sk[x, y] == 1 {
                var n = 0
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 { n += Int(sk[x + dx, y + dy]) } }
                if n > 2 { fat += 1 }
            }
        }
        #expect(fat < 4)
    }

    @Test func testWidthEstimate() {
        let img = Fixture.line(from: CGPoint(x: 40, y: 150), to: CGPoint(x: 260, y: 150), width: 9)
        let bin = Binarizer().binarize(GrayBitmap(cgImage: img))
        let w = Skeletonizer.width(at: 150, 150, in: bin)
        #expect(abs((w) - (9)) <= 2)
    }

    // MARK: Tracer

    @Test func testStraightLineBecomesOneStroke() {
        let img = Fixture.line(from: CGPoint(x: 40, y: 150), to: CGPoint(x: 260, y: 150), width: 8)
        let (page, dbg) = InkPipeline(options: noRectify).process(img)
        #expect(dbg.rawStrokeCount == 1)
        #expect(page.strokes.count == 1)
        let s = page.strokes[0]
        // Page layout maps 300 px onto 540 pt (1 px = 1.8 pt), centred vertically in 720 pt.
        let scale = (612.0 - 72) / 300
        let y = 36 + (720 - 300 * scale) / 2 + 150 * scale
        for p in s.points { #expect(abs((p.y) - (y)) <= 2.5) }
        #expect(abs((s.length) - (220 * scale)) <= 20)
        #expect(abs((s.averageWidth) - (8 * scale)) <= 4)
    }

    @Test func testCrossingLinesStayTwoStrokes() {
        let img = Fixture.cross()
        let (page, _) = InkPipeline(options: noRectify).process(img)
        #expect(page.strokes.count == 2, "junction merge should rejoin the two diagonals")
        let diag = (180.0 * 2.0.squareRoot()) * ((612.0 - 72) / 300)
        for s in page.strokes { #expect(abs((s.length) - (diag)) <= diag * 0.15) }
    }

    @Test func testCircleBecomesOneClosedStroke() {
        let img = Fixture.circle()
        let (page, _) = InkPipeline(options: noRectify).process(img)
        #expect(page.strokes.count == 1)
        let s = page.strokes[0]
        let first = s.points.first!, last = s.points.last!
        let gap = ((first.x - last.x) * (first.x - last.x) + (first.y - last.y) * (first.y - last.y)).squareRoot()
        #expect(gap < 6, "loop should close on itself")
        #expect(abs((s.length) - (Double.pi * 160 * ((612.0 - 72) / 300))) <= 60)
    }

    @Test func dotBecomesOnePointStroke() {
        let img = Fixture.canvas(width: 200, height: 200) { ctx in
            ctx.fillEllipse(in: CGRect(x: 95, y: 95, width: 9, height: 9))
        }
        let (page, _) = InkPipeline(options: noRectify).process(img)
        #expect(page.strokes.count == 1)
        #expect(page.strokes.first?.points.count == 1)
        #expect((page.strokes.first?.averageWidth ?? 0) > 9 * 2.7 * 0.6)
    }

    // MARK: Smoother

    @Test func testSimplifyKeepsEndpointsAndDropsCollinear() {
        let pts = (0..<50).map { StrokePoint(x: Double($0), y: 0, width: 2) }
        let out = Smoother().simplify(pts, tolerance: 0.5)
        #expect(out.count == 2)
        #expect(out.first == pts.first)
        #expect(out.last == pts.last)
    }

    // MARK: End to end on cursive text

    @Test func testHandwritingRoundTripCoversTheInk() throws {
        let img = Fixture.handwriting("Hello notes")
        let (page, dbg) = InkPipeline(options: noRectify).process(img)
        #expect(page.strokes.count > 3)

        // Re-render the strokes at image resolution and compare with the binarized input.
        var opts = noRectify
        opts.margin = 0
        opts.pageSize = PageSize(width: Double(dbg.gray.width), height: Double(dbg.gray.height))
        let (pixelPage, _) = InkPipeline(options: opts).process(img)
        let rendered = try #require(PDFExporter.render(pixelPage, scale: 1))
        let r = GrayBitmap(cgImage: rendered)
        let renderedInk = BinaryBitmap(width: r.width, height: r.height, bits: r.pixels.map { $0 < 128 ? 1 : 0 })

        var inter = 0, union = 0
        for i in renderedInk.bits.indices {
            let a = dbg.binary.bits[i], b = renderedInk.bits[i]
            if a == 1 && b == 1 { inter += 1 }
            if a == 1 || b == 1 { union += 1 }
        }
        let iou = Double(inter) / Double(max(1, union))
        #expect(iou > 0.55, "rendered strokes should cover the original ink, IoU=\(iou)")
    }

    // MARK: PDF

    @Test func testPDFExportProducesAPage() throws {
        let img = Fixture.line(from: CGPoint(x: 40, y: 150), to: CGPoint(x: 260, y: 150), width: 8)
        let (page, _) = InkPipeline(options: noRectify).process(img)
        let data = PDFExporter().data(for: InkDocument(title: "t", pages: [page]))
        #expect(data.starts(with: Array("%PDF".utf8)))
        let provider = try #require(CGDataProvider(data: data as CFData))
        let pdf = try #require(CGPDFDocument(provider))
        #expect(pdf.numberOfPages == 1)
        let box = try #require(pdf.page(at: 1)?.getBoxRect(.mediaBox))
        #expect(abs((box.width) - (612)) <= 0.01)
        #expect(abs((box.height) - (792)) <= 0.01)
    }
}

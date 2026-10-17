import Testing
import CoreGraphics
import CoreImage
@testable import InkCore

struct RectifierTests {
    /// Puts the handwriting sheet on a dark desk, tilts it, and checks that the pipeline
    /// still finds about the same ink as on the flat sheet.
    @Test func tiltedSheetIsFlattened() throws {
        let sheet = Fixture.handwriting("Hello notes", noise: 6)
        let sw = CGFloat(sheet.width), sh = CGFloat(sheet.height)

        let desk = CGContext(
            data: nil, width: Int(sw * 1.5), height: Int(sh * 1.8), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        desk.setFillColor(CGColor(red: 0.25, green: 0.18, blue: 0.12, alpha: 1))
        desk.fill(CGRect(x: 0, y: 0, width: desk.width, height: desk.height))
        let deskImage = desk.makeImage()!

        // Warp the sheet with a perspective transform and composite it over the desk.
        let ci = CIImage(cgImage: sheet)
        let warp = CIFilter(name: "CIPerspectiveTransform")!
        warp.setValue(ci, forKey: kCIInputImageKey)
        let ox: CGFloat = 120, oy: CGFloat = 150
        warp.setValue(CIVector(x: ox + 60, y: oy + sh * 1.15), forKey: "inputTopLeft")
        warp.setValue(CIVector(x: ox + sw * 1.25, y: oy + sh * 1.3), forKey: "inputTopRight")
        warp.setValue(CIVector(x: ox, y: oy), forKey: "inputBottomLeft")
        warp.setValue(CIVector(x: ox + sw * 1.35, y: oy - 20), forKey: "inputBottomRight")
        let warped = try #require(warp.outputImage)
        let composite = warped.composited(over: CIImage(cgImage: deskImage))
        let ctx = CIContext()
        let photo = try #require(ctx.createCGImage(composite, from: CGRect(x: 0, y: 0, width: desk.width, height: desk.height)))

        let flat = try #require(DocumentRectifier().rectify(photo), "Vision should find the sheet")
        // The flattened sheet keeps roughly the original aspect ratio (2:1).
        let aspect = Double(flat.width) / Double(flat.height)
        #expect(abs(aspect - 2.0) < 0.35, "aspect \(aspect)")

        var o = InkPipelineOptions()
        o.rectify = true
        let (page, _) = InkPipeline(options: o).process(photo)
        var flatOpts = InkPipelineOptions()
        flatOpts.rectify = false
        let (reference, _) = InkPipeline(options: flatOpts).process(sheet)

        let ratio = Double(page.strokes.count) / Double(reference.strokes.count)
        #expect(ratio > 0.6 && ratio < 1.6, "strokes \(page.strokes.count) vs flat \(reference.strokes.count)")
        let inkLen = page.strokes.reduce(0) { $0 + $1.length }
        let refLen = reference.strokes.reduce(0) { $0 + $1.length }
        #expect(abs(inkLen / refLen - 1) < 0.3, "ink length \(inkLen) vs flat \(refLen)")
    }
}

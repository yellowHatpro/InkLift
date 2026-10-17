import Foundation
import CoreGraphics

/// Draws strokes as round-capped vector paths. One PDF page per `Page`.
public struct PDFExporter {
    public init() {}

    public func data(for document: InkDocument) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var box = CGRect(x: 0, y: 0, width: document.pages.first?.size.width ?? 612, height: document.pages.first?.size.height ?? 792)
        let info: [CFString: Any] = [kCGPDFContextTitle: document.title, kCGPDFContextCreator: "InkLift"]
        guard let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary) else { return Data() }
        for page in document.pages {
            var pageBox = CGRect(x: 0, y: 0, width: page.size.width, height: page.size.height)
            let pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: Data(bytes: &pageBox, count: MemoryLayout<CGRect>.size)]
            ctx.beginPDFPage(pageInfo as CFDictionary)
            // PDF origin is bottom-left; the model is top-left.
            ctx.translateBy(x: 0, y: page.size.height)
            ctx.scaleBy(x: 1, y: -1)
            Self.draw(page, in: ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    public func write(_ document: InkDocument, to url: URL) throws {
        try data(for: document).write(to: url)
    }

    /// Draws each stroke as a chain of segments so width can vary along the path.
    public static func draw(_ page: Page, in ctx: CGContext) {
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        for stroke in page.strokes where !stroke.points.isEmpty {
            ctx.setStrokeColor(CGColor(red: stroke.color.r, green: stroke.color.g, blue: stroke.color.b, alpha: stroke.color.a))
            let pts = stroke.points
            if pts.count == 1 {
                ctx.setLineWidth(pts[0].width)
                ctx.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
                ctx.addLine(to: CGPoint(x: pts[0].x, y: pts[0].y))
                ctx.strokePath()
                continue
            }
            for i in 1..<pts.count {
                ctx.setLineWidth((pts[i - 1].width + pts[i].width) / 2)
                ctx.move(to: CGPoint(x: pts[i - 1].x, y: pts[i - 1].y))
                ctx.addLine(to: CGPoint(x: pts[i].x, y: pts[i].y))
                ctx.strokePath()
            }
        }
    }

    /// Rasterizes a page for previews and tests.
    public static func render(_ page: Page, scale: CGFloat = 2) -> CGImage? {
        let w = Int(page.size.width * scale), h = Int(page.size.height * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: scale, y: -scale)
        draw(page, in: ctx)
        return ctx.makeImage()
    }
}

import Foundation
import CoreGraphics
import CoreText
import InkCore

/// Draws known ink on a paper-like background so pipeline output can be checked
/// against ground truth.
enum Fixture {
    static func canvas(width: Int, height: Int, gradient: Bool = true, noise: UInt8 = 0, draw: (CGContext) -> Void) -> CGImage {
        let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 0.92, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if gradient {
            // Uneven lighting: darker on one side, like a lamp off to the left.
            let colors = [CGColor(gray: 0.55, alpha: 1), CGColor(gray: 0.95, alpha: 1)] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(), colors: colors, locations: [0, 1])!
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: width, y: height), options: [])
        }
        // Flip to top-left origin so fixture coordinates match the model.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(CGColor(gray: 0.08, alpha: 1))
        ctx.setFillColor(CGColor(gray: 0.08, alpha: 1))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        draw(ctx)
        var img = ctx.makeImage()!
        if noise > 0 { img = addNoise(img, amplitude: noise) }
        return img
    }

    static func addNoise(_ img: CGImage, amplitude: UInt8, seed: UInt64 = 42) -> CGImage {
        var g = GrayBitmap(cgImage: img)
        var state = seed
        for i in g.pixels.indices {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let n = Int(state >> 33) % (2 * Int(amplitude) + 1) - Int(amplitude)
            g.pixels[i] = UInt8(max(0, min(255, Int(g.pixels[i]) + n)))
        }
        return g.cgImage()
    }

    static func line(from a: CGPoint, to b: CGPoint, width: CGFloat, size: Int = 300) -> CGImage {
        canvas(width: size, height: size) { ctx in
            ctx.setLineWidth(width)
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }
    }

    static func cross(size: Int = 300, width: CGFloat = 7) -> CGImage {
        canvas(width: size, height: size) { ctx in
            ctx.setLineWidth(width)
            ctx.move(to: CGPoint(x: 60, y: 60)); ctx.addLine(to: CGPoint(x: 240, y: 240))
            ctx.move(to: CGPoint(x: 240, y: 60)); ctx.addLine(to: CGPoint(x: 60, y: 240))
            ctx.strokePath()
        }
    }

    static func circle(size: Int = 300, width: CGFloat = 6) -> CGImage {
        canvas(width: size, height: size) { ctx in
            ctx.setLineWidth(width)
            ctx.strokeEllipse(in: CGRect(x: 70, y: 70, width: 160, height: 160))
        }
    }

    /// Text in a cursive system font stands in for handwriting.
    static func handwriting(_ text: String, size: Int = 900, fontSize: CGFloat = 72, noise: UInt8 = 10) -> CGImage {
        canvas(width: size, height: size / 2, noise: noise) { ctx in
            let font = CTFontCreateWithName("Snell Roundhand" as CFString, fontSize, nil)
            let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.08, alpha: 1)]
            let attributed = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
            let lineRef = CTLineCreateWithAttributedString(attributed)
            ctx.saveGState()
            // CoreText draws with a bottom-left origin; undo the flip for the glyphs.
            ctx.translateBy(x: 60, y: CGFloat(size) / 4 + fontSize / 3)
            ctx.scaleBy(x: 1, y: -1)
            ctx.textPosition = .zero
            CTLineDraw(lineRef, ctx)
            ctx.restoreGState()
        }
    }

    /// Ink mask of a fixture: pixels darker than mid-gray.
    static func inkMask(_ img: CGImage) -> BinaryBitmap {
        let g = GrayBitmap(cgImage: img)
        return BinaryBitmap(width: g.width, height: g.height, bits: g.pixels.map { $0 < 70 ? 1 : 0 })
    }
}

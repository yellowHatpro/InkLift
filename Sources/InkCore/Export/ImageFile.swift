import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ImageFile {
    public enum Error: Swift.Error { case unreadable(URL), unwritable(URL) }

    /// Loads any ImageIO-supported file, applying EXIF orientation.
    public static func load(_ url: URL) throws -> CGImage {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { throw Error.unreadable(url) }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let orientation = (props?[kCGImagePropertyOrientation] as? UInt32) ?? 1
        return orientation == 1 ? img : applyOrientation(img, orientation)
    }

    public static func savePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw Error.unwritable(url) }
        CGImageDestinationAddImage(dest, image, nil)
        if !CGImageDestinationFinalize(dest) { throw Error.unwritable(url) }
    }

    static func applyOrientation(_ img: CGImage, _ o: UInt32) -> CGImage {
        let w = CGFloat(img.width), h = CGFloat(img.height)
        let swaps = o >= 5
        let outW = Int(swaps ? h : w), outH = Int(swaps ? w : h)
        guard let ctx = CGContext(
            data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return img }
        switch o {
        case 2: ctx.translateBy(x: w, y: 0); ctx.scaleBy(x: -1, y: 1)
        case 3: ctx.translateBy(x: w, y: h); ctx.rotate(by: .pi)
        case 4: ctx.translateBy(x: 0, y: h); ctx.scaleBy(x: 1, y: -1)
        case 5: ctx.rotate(by: .pi / 2); ctx.scaleBy(x: 1, y: -1)
        case 6: ctx.translateBy(x: h, y: 0); ctx.rotate(by: .pi / 2)
        case 7: ctx.translateBy(x: h, y: w); ctx.rotate(by: -.pi / 2); ctx.scaleBy(x: -1, y: 1)
        case 8: ctx.translateBy(x: 0, y: w); ctx.rotate(by: -.pi / 2)
        default: break
        }
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? img
    }
}

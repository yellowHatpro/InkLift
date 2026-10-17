import Foundation
import CoreGraphics

/// 8-bit grayscale raster, row-major, origin top-left.
public struct GrayBitmap {
    public let width: Int
    public let height: Int
    public var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) {
        precondition(pixels.count == width * height)
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: UInt8 = 255) {
        self.init(width: width, height: height, pixels: [UInt8](repeating: fill, count: width * height))
    }

    @inline(__always) public subscript(x: Int, y: Int) -> UInt8 {
        get { pixels[y * width + x] }
        set { pixels[y * width + x] = newValue }
    }

    /// Draws `image` into a grayscale buffer.
    public init(cgImage: CGImage) {
        let w = cgImage.width
        let h = cgImage.height
        var buf = [UInt8](repeating: 0, count: w * h)
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(
                data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        self.init(width: w, height: h, pixels: buf)
    }

    public func cgImage() -> CGImage {
        let data = Data(pixels)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

/// 1 = ink, 0 = paper. Row-major, origin top-left.
public struct BinaryBitmap: Equatable {
    public let width: Int
    public let height: Int
    public var bits: [UInt8]

    public init(width: Int, height: Int, bits: [UInt8]) {
        precondition(bits.count == width * height)
        self.width = width
        self.height = height
        self.bits = bits
    }

    public init(width: Int, height: Int) {
        self.init(width: width, height: height, bits: [UInt8](repeating: 0, count: width * height))
    }

    @inline(__always) public subscript(x: Int, y: Int) -> UInt8 {
        get { bits[y * width + x] }
        set { bits[y * width + x] = newValue }
    }

    /// Returns 0 outside the raster.
    @inline(__always) public func at(_ x: Int, _ y: Int) -> UInt8 {
        if x < 0 || y < 0 || x >= width || y >= height { return 0 }
        return bits[y * width + x]
    }

    public var inkCount: Int { bits.reduce(0) { $0 + Int($1) } }

    public func toGray() -> GrayBitmap {
        GrayBitmap(width: width, height: height, pixels: bits.map { $0 == 0 ? 255 : 0 })
    }
}

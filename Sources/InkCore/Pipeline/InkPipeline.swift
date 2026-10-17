import Foundation
import CoreGraphics

public struct InkPipelineOptions {
    /// Longest image side is scaled down to this before processing.
    public var maxDimension: Int = 2200
    /// Detect the paper and flatten it first.
    public var rectify: Bool = true
    public var pageSize: PageSize = .letter
    /// Margin around the ink on the page, in points.
    public var margin: Double = 36
    public var color: StrokeColor = .black
    public var binarizer = Binarizer()
    public var tracer = Tracer()
    public var smoother = Smoother()

    public init() {}
}

/// Intermediate rasters, kept for debugging and tests.
public struct InkPipelineDebug {
    public var rectified: CGImage
    public var gray: GrayBitmap
    public var binary: BinaryBitmap
    public var skeleton: BinaryBitmap
    public var rawStrokeCount: Int
}

public struct InkPipeline {
    public var options: InkPipelineOptions

    public init(options: InkPipelineOptions = InkPipelineOptions()) {
        self.options = options
    }

    public func process(_ image: CGImage) -> (page: Page, debug: InkPipelineDebug) {
        var working = image
        if options.rectify, let flat = DocumentRectifier().rectify(working) {
            working = flat
        }
        working = Self.downscale(working, maxDimension: options.maxDimension)

        let gray = GrayBitmap(cgImage: working)
        let binary = options.binarizer.binarize(gray)
        let skeleton = Skeletonizer().skeletonize(binary)
        let raw = options.tracer.trace(skeleton: skeleton, ink: binary)
        let smoothed = raw.map { options.smoother.smooth($0) }

        let page = Self.layout(smoothed, imageWidth: gray.width, imageHeight: gray.height, options: options)
        let debug = InkPipelineDebug(rectified: working, gray: gray, binary: binary, skeleton: skeleton, rawStrokeCount: raw.count)
        return (page, debug)
    }

    /// Fits the whole image onto the page, preserving aspect ratio, inside the margin.
    static func layout(_ strokes: [RawStroke], imageWidth: Int, imageHeight: Int, options: InkPipelineOptions) -> Page {
        let availW = options.pageSize.width - 2 * options.margin
        let availH = options.pageSize.height - 2 * options.margin
        let scale = min(availW / Double(imageWidth), availH / Double(imageHeight))
        let offX = options.margin + (availW - Double(imageWidth) * scale) / 2
        let offY = options.margin + (availH - Double(imageHeight) * scale) / 2
        let out = strokes.map { raw in
            Stroke(points: raw.points.map {
                StrokePoint(x: offX + $0.x * scale, y: offY + $0.y * scale, width: max(0.5, $0.width * scale))
            }, color: options.color)
        }
        return Page(size: options.pageSize, strokes: out)
    }

    static func downscale(_ image: CGImage, maxDimension: Int) -> CGImage {
        let longest = max(image.width, image.height)
        if longest <= maxDimension { return image }
        let scale = Double(maxDimension) / Double(longest)
        let w = Int(Double(image.width) * scale), h = Int(Double(image.height) * scale)
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage() ?? image
    }
}

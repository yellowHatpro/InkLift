import Foundation
import CoreGraphics
import CoreImage
import Vision

/// Finds the sheet of paper in a photo and warps it to a flat rectangle.
public struct DocumentRectifier {
    /// Minimum Vision confidence to accept the detected quad.
    public var minConfidence: Float = 0.5

    public init() {}

    /// Returns the rectified page, or `nil` when no document is detected. The input is
    /// returned unchanged when the quad covers nearly the whole frame.
    public func rectify(_ image: CGImage) -> CGImage? {
        let request = VNDetectDocumentSegmentationRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let obs = request.results?.first, obs.confidence >= minConfidence else { return nil }

        let w = CGFloat(image.width), h = CGFloat(image.height)
        // Vision points are normalized with origin bottom-left, which matches CIImage space.
        func pt(_ p: CGPoint) -> CIVector { CIVector(x: p.x * w, y: p.y * h) }

        let ci = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
        filter.setValue(ci, forKey: kCIInputImageKey)
        filter.setValue(pt(obs.topLeft), forKey: "inputTopLeft")
        filter.setValue(pt(obs.topRight), forKey: "inputTopRight")
        filter.setValue(pt(obs.bottomLeft), forKey: "inputBottomLeft")
        filter.setValue(pt(obs.bottomRight), forKey: "inputBottomRight")
        guard let out = filter.outputImage else { return nil }
        let context = CIContext(options: [.useSoftwareRenderer: false])
        return context.createCGImage(out, from: out.extent)
    }
}

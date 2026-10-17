import PencilKit
import InkCore

enum PencilKitBridge {
    /// Converts traced strokes to a PKDrawing. Width maps to the pen tool's width and to
    /// per-point size, so the preview shows the same variable width as the export.
    static func drawing(for page: Page) -> PKDrawing {
        var strokes: [PKStroke] = []
        for s in page.strokes where !s.points.isEmpty {
            let color = UIColor(red: s.color.r, green: s.color.g, blue: s.color.b, alpha: s.color.a)
            let ink = PKInk(.pen, color: color)
            var points: [PKStrokePoint] = []
            var t: TimeInterval = 0
            for p in s.points {
                let w = CGFloat(max(0.5, p.width))
                points.append(PKStrokePoint(
                    location: CGPoint(x: p.x, y: p.y), timeOffset: t,
                    size: CGSize(width: w, height: w), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2))
                t += 0.005
            }
            if points.count == 1 {
                var q = points[0]
                q = PKStrokePoint(location: CGPoint(x: q.location.x + 0.1, y: q.location.y), timeOffset: 0.005,
                                  size: q.size, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
                points.append(q)
            }
            let path = PKStrokePath(controlPoints: points, creationDate: Date())
            strokes.append(PKStroke(ink: ink, path: path))
        }
        return PKDrawing(strokes: strokes)
    }
}

struct CanvasView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var pageSize: CGSize

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.backgroundColor = .white
        v.isOpaque = true
        v.tool = PKInkingTool(.pen, color: .black, width: 2)
        v.delegate = context.coordinator
        v.minimumZoomScale = 0.5
        v.maximumZoomScale = 4
        v.contentSize = pageSize
        v.drawing = drawing
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        if v.drawing != drawing { v.drawing = drawing }
        v.contentSize = pageSize
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: CanvasView
        init(_ parent: CanvasView) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.drawing = canvasView.drawing
        }
    }
}

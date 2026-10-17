import Foundation

/// Turns pixel-stepped centerlines into smooth pen paths.
public struct Smoother {
    /// Ramer-Douglas-Peucker tolerance in pixels.
    public var tolerance: Double = 0.9
    /// Chaikin corner-cutting iterations after simplification.
    public var chaikinIterations: Int = 2
    /// Moving-average window for widths (odd).
    public var widthWindow: Int = 5

    public init() {}

    public func smooth(_ raw: RawStroke) -> RawStroke {
        var pts = raw.points
        guard pts.count > 2 else { return raw }
        pts = smoothWidths(pts)
        pts = simplify(pts, tolerance: tolerance)
        for _ in 0..<chaikinIterations { pts = chaikin(pts) }
        return RawStroke(points: pts)
    }

    func smoothWidths(_ pts: [StrokePoint]) -> [StrokePoint] {
        let half = max(0, widthWindow / 2)
        var out = pts
        for i in pts.indices {
            let lo = max(0, i - half), hi = min(pts.count - 1, i + half)
            var s = 0.0
            for j in lo...hi { s += pts[j].width }
            out[i].width = s / Double(hi - lo + 1)
        }
        return out
    }

    func simplify(_ pts: [StrokePoint], tolerance: Double) -> [StrokePoint] {
        guard pts.count > 2 else { return pts }
        var keep = [Bool](repeating: false, count: pts.count)
        keep[0] = true
        keep[pts.count - 1] = true
        var stack: [(Int, Int)] = [(0, pts.count - 1)]
        while let (a, b) = stack.popLast() {
            if b - a < 2 { continue }
            var maxD = -1.0, maxI = a
            for i in (a + 1)..<b {
                let d = perpendicularDistance(pts[i], pts[a], pts[b])
                if d > maxD { maxD = d; maxI = i }
            }
            if maxD > tolerance {
                keep[maxI] = true
                stack.append((a, maxI))
                stack.append((maxI, b))
            }
        }
        return pts.indices.filter { keep[$0] }.map { pts[$0] }
    }

    private func perpendicularDistance(_ p: StrokePoint, _ a: StrokePoint, _ b: StrokePoint) -> Double {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        if len2 < 1e-12 { return ((p.x - a.x) * (p.x - a.x) + (p.y - a.y) * (p.y - a.y)).squareRoot() }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        let px = a.x + t * dx, py = a.y + t * dy
        return ((p.x - px) * (p.x - px) + (p.y - py) * (p.y - py)).squareRoot()
    }

    /// Chaikin's corner cutting. Keeps the first and last points fixed.
    func chaikin(_ pts: [StrokePoint]) -> [StrokePoint] {
        guard pts.count > 2 else { return pts }
        var out: [StrokePoint] = [pts[0]]
        for i in 0..<(pts.count - 1) {
            let p = pts[i], q = pts[i + 1]
            out.append(StrokePoint(x: 0.75 * p.x + 0.25 * q.x, y: 0.75 * p.y + 0.25 * q.y, width: 0.75 * p.width + 0.25 * q.width))
            out.append(StrokePoint(x: 0.25 * p.x + 0.75 * q.x, y: 0.25 * p.y + 0.75 * q.y, width: 0.25 * p.width + 0.75 * q.width))
        }
        out.append(pts[pts.count - 1])
        return out
    }
}

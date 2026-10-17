import Foundation

/// A traced centerline in pixel coordinates.
public struct RawStroke {
    public var points: [StrokePoint]
}

/// Walks a skeleton bitmap into polylines. Splits at junctions, prunes spurs, then
/// re-joins segments that continue straight through a junction (a crossing "t" bar stays
/// one stroke).
public struct Tracer {
    /// Segments shorter than this many pixels with one free end are removed.
    public var spurLength: Int = 6
    /// Final strokes shorter than this (pixels) are dropped.
    public var minStrokeLength: Double = 4
    /// Minimum cosine-angle between two segments at a junction for them to be merged.
    /// -0.5 means the turn is at most 60 degrees.
    public var mergeMaxDot: Double = -0.5

    public init() {}

    private struct Seg {
        var pts: [(Int, Int)]
        var startNode: Int?   // pixel index of node at pts.first, nil for loops
        var endNode: Int?
    }

    public func trace(skeleton: BinaryBitmap, ink: BinaryBitmap) -> [RawStroke] {
        let w = skeleton.width, h = skeleton.height
        let bits = skeleton.bits

        @inline(__always) func neighbors(_ idx: Int) -> [Int] {
            let x = idx % w, y = idx / w
            var out: [Int] = []
            for dy in -1...1 {
                for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                    let ni = ny * w + nx
                    if bits[ni] == 1 { out.append(ni) }
                }
            }
            return out
        }

        var degree = [UInt8](repeating: 0, count: w * h)
        var nodes: [Int] = []
        for i in 0..<(w * h) where bits[i] == 1 {
            let d = neighbors(i).count
            degree[i] = UInt8(d)
            if d != 2 { nodes.append(i) }
        }

        var visited = [Bool](repeating: false, count: w * h)
        var segs: [Seg?] = []
        var nodeEdges = Set<Int64>() // unordered pair key for direct node-node edges

        func pairKey(_ a: Int, _ b: Int) -> Int64 {
            let lo = Int64(min(a, b)), hi = Int64(max(a, b))
            return lo << 32 | hi
        }

        // Edges that start at a node.
        for n in nodes {
            for first in neighbors(n) {
                if degree[first] != 2 {
                    // Node directly touching node.
                    let key = pairKey(n, first)
                    if nodeEdges.contains(key) { continue }
                    nodeEdges.insert(key)
                    segs.append(Seg(pts: [(n % w, n / w), (first % w, first / w)], startNode: n, endNode: first))
                    continue
                }
                if visited[first] { continue }
                var pts: [(Int, Int)] = [(n % w, n / w)]
                var prev = n
                var cur = first
                var endNode: Int? = nil
                while true {
                    visited[cur] = true
                    pts.append((cur % w, cur / w))
                    let nb = neighbors(cur)
                    // Continue to the neighbor that is not where we came from.
                    guard let next = nb.first(where: { $0 != prev && !(degree[$0] == 2 && visited[$0]) }) else { break }
                    if degree[next] != 2 {
                        pts.append((next % w, next / w))
                        endNode = next
                        break
                    }
                    prev = cur
                    cur = next
                }
                segs.append(Seg(pts: pts, startNode: n, endNode: endNode))
            }
        }

        // Closed loops: degree-2 pixels never reached from a node.
        for i in 0..<(w * h) where bits[i] == 1 && degree[i] == 2 && !visited[i] {
            var pts: [(Int, Int)] = []
            var prev = -1
            var cur = i
            while !visited[cur] {
                visited[cur] = true
                pts.append((cur % w, cur / w))
                let nb = neighbors(cur)
                guard let next = nb.first(where: { $0 != prev && !visited[$0] }) else { break }
                prev = cur
                cur = next
            }
            if pts.count > 2 { pts.append(pts[0]) }
            segs.append(Seg(pts: pts, startNode: nil, endNode: nil))
        }

        // Prune spurs: short segment with exactly one free end.
        for i in segs.indices {
            guard let s = segs[i] else { continue }
            let startFree = s.startNode.map { degree[$0] == 1 } ?? false
            let endFree = s.endNode.map { degree[$0] == 1 } ?? false
            if startFree != endFree && s.pts.count <= spurLength {
                segs[i] = nil
            }
        }

        // Merge straight continuations at junctions.
        let junctions = nodes.filter { degree[$0] >= 3 }
        for j in junctions {
            var merged = true
            while merged {
                merged = false
                var incident: [(id: Int, atStart: Bool)] = []
                for (id, s) in segs.enumerated() {
                    guard let s = s else { continue }
                    if s.startNode == j { incident.append((id, true)) }
                    if s.endNode == j { incident.append((id, false)) }
                }
                if incident.count < 2 { break }
                func outDir(_ e: (id: Int, atStart: Bool)) -> (Double, Double) {
                    let pts = segs[e.id]!.pts
                    let k = min(4, pts.count - 1)
                    let a = e.atStart ? pts[0] : pts[pts.count - 1]
                    let b = e.atStart ? pts[k] : pts[pts.count - 1 - k]
                    let dx = Double(b.0 - a.0), dy = Double(b.1 - a.1)
                    let len = max(1e-9, (dx * dx + dy * dy).squareRoot())
                    return (dx / len, dy / len)
                }
                var best: (Int, Int, Double)? = nil
                for a in 0..<incident.count {
                    for b in (a + 1)..<incident.count where incident[a].id != incident[b].id {
                        let da = outDir(incident[a]), db = outDir(incident[b])
                        let dot = da.0 * db.0 + da.1 * db.1
                        if dot <= mergeMaxDot && (best == nil || dot < best!.2) { best = (a, b, dot) }
                    }
                }
                guard let (ia, ib, _) = best else { break }
                var A = segs[incident[ia].id]!
                var B = segs[incident[ib].id]!
                // Orient A to end at j, B to start at j.
                if incident[ia].atStart { A.pts.reverse(); swap(&A.startNode, &A.endNode) }
                if !incident[ib].atStart { B.pts.reverse(); swap(&B.startNode, &B.endNode) }
                A.pts.append(contentsOf: B.pts.dropFirst())
                A.endNode = B.endNode
                segs[incident[ia].id] = A
                segs[incident[ib].id] = nil
                merged = true
            }
        }

        // Short bridges between two junctions are knots in the skeleton, not ink.
        for i in segs.indices {
            guard let s = segs[i], let a = s.startNode, let b = s.endNode else { continue }
            if degree[a] >= 3 && degree[b] >= 3 && s.pts.count <= spurLength { segs[i] = nil }
        }

        var out: [RawStroke] = []
        // Isolated skeleton pixels are dots (i-dots, punctuation). Keep them as one-point strokes.
        for n in nodes where degree[n] == 0 {
            let x = n % w, y = n / w
            let width = Skeletonizer.width(at: x, y, in: ink)
            if width >= 2 {
                out.append(RawStroke(points: [StrokePoint(x: Double(x), y: Double(y), width: width)]))
            }
        }
        for s in segs {
            guard let s = s, s.pts.count >= 2 else { continue }
            let pts = s.pts.map { p in
                StrokePoint(x: Double(p.0), y: Double(p.1), width: Skeletonizer.width(at: p.0, p.1, in: ink))
            }
            if Stroke(points: pts).length >= minStrokeLength {
                out.append(RawStroke(points: pts))
                continue
            }
            // A short free-standing piece (both ends are line ends) is a dot drawn by hand.
            let startFree = s.startNode.map { degree[$0] <= 1 } ?? true
            let endFree = s.endNode.map { degree[$0] <= 1 } ?? true
            if startFree && endFree {
                let cx = pts.reduce(0.0) { $0 + $1.x } / Double(pts.count)
                let cy = pts.reduce(0.0) { $0 + $1.y } / Double(pts.count)
                let w = pts.reduce(0.0) { $0 + $1.width } / Double(pts.count)
                if w >= 2 { out.append(RawStroke(points: [StrokePoint(x: cx, y: cy, width: w)])) }
            }
        }
        return out
    }
}

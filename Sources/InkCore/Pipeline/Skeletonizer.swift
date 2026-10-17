import Foundation

/// Zhang-Suen thinning: reduces each ink blob to a one-pixel-wide centerline.
public struct Skeletonizer {
    public init() {}

    public func skeletonize(_ input: BinaryBitmap) -> BinaryBitmap {
        var img = input
        let w = img.width, h = img.height
        var toClear: [Int] = []
        var changed = true
        while changed {
            changed = false
            for pass in 0..<2 {
                toClear.removeAll(keepingCapacity: true)
                for y in 1..<(h - 1) {
                    for x in 1..<(w - 1) where img.bits[y * w + x] == 1 {
                        let p2 = img.bits[(y - 1) * w + x]
                        let p3 = img.bits[(y - 1) * w + x + 1]
                        let p4 = img.bits[y * w + x + 1]
                        let p5 = img.bits[(y + 1) * w + x + 1]
                        let p6 = img.bits[(y + 1) * w + x]
                        let p7 = img.bits[(y + 1) * w + x - 1]
                        let p8 = img.bits[y * w + x - 1]
                        let p9 = img.bits[(y - 1) * w + x - 1]
                        let b = Int(p2) + Int(p3) + Int(p4) + Int(p5) + Int(p6) + Int(p7) + Int(p8) + Int(p9)
                        if b < 2 || b > 6 { continue }
                        var a = 0
                        if p2 == 0 && p3 == 1 { a += 1 }
                        if p3 == 0 && p4 == 1 { a += 1 }
                        if p4 == 0 && p5 == 1 { a += 1 }
                        if p5 == 0 && p6 == 1 { a += 1 }
                        if p6 == 0 && p7 == 1 { a += 1 }
                        if p7 == 0 && p8 == 1 { a += 1 }
                        if p8 == 0 && p9 == 1 { a += 1 }
                        if p9 == 0 && p2 == 1 { a += 1 }
                        if a != 1 { continue }
                        let cond: Bool
                        if pass == 0 {
                            cond = (p2 & p4 & p6) == 0 && (p4 & p6 & p8) == 0
                        } else {
                            cond = (p2 & p4 & p8) == 0 && (p2 & p6 & p8) == 0
                        }
                        if cond { toClear.append(y * w + x) }
                    }
                }
                if !toClear.isEmpty {
                    changed = true
                    for i in toClear { img.bits[i] = 0 }
                }
            }
        }
        // Border pixels are never thinned; drop them so they cannot form false strokes.
        for x in 0..<w { img.bits[x] = 0; img.bits[(h - 1) * w + x] = 0 }
        for y in 0..<h { img.bits[y * w] = 0; img.bits[y * w + w - 1] = 0 }
        removeRedundantPixels(&img)
        return img
    }

    /// Removes pixels whose 8-neighbours stay connected to each other without them
    /// (staircase corners and small knots). The line is still 8-connected afterwards and
    /// almost every pixel has exactly two neighbours.
    func removeRedundantPixels(_ img: inout BinaryBitmap) {
        let w = img.width, h = img.height
        // Ring order: N, NE, E, SE, S, SW, W, NW.
        let ring = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
        var changed = true
        while changed {
            changed = false
            for y in 1..<(h - 1) {
                for x in 1..<(w - 1) where img.bits[y * w + x] == 1 {
                    var set: [Bool] = []
                    var count = 0
                    for (dx, dy) in ring {
                        let on = img.bits[(y + dy) * w + (x + dx)] == 1
                        set.append(on)
                        if on { count += 1 }
                    }
                    if count < 2 { continue }
                    // Only consider pixels that have at least one 4-neighbour pair forming a corner,
                    // or that sit in a knot (degree >= 3).
                    let corner = (set[0] && set[2]) || (set[2] && set[4]) || (set[4] && set[6]) || (set[6] && set[0])
                    if !corner && count < 3 { continue }
                    if Self.ringComponents(set) == 1 {
                        img.bits[y * w + x] = 0
                        changed = true
                    }
                }
            }
        }
    }

    /// Number of 8-connected groups among the set ring cells, ignoring the centre.
    static func ringComponents(_ set: [Bool]) -> Int {
        let pos = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
        var parent = Array(0..<8)
        func find(_ i: Int) -> Int { var i = i; while parent[i] != i { i = parent[i] }; return i }
        for a in 0..<8 where set[a] {
            for b in (a + 1)..<8 where set[b] {
                if abs(pos[a].0 - pos[b].0) <= 1 && abs(pos[a].1 - pos[b].1) <= 1 {
                    let ra = find(a), rb = find(b)
                    if ra != rb { parent[ra] = rb }
                }
            }
        }
        var roots = Set<Int>()
        for i in 0..<8 where set[i] { roots.insert(find(i)) }
        return roots.count
    }

    /// Full stroke width at (x, y): twice the shortest distance to paper in the
    /// original binary image, measured along 8 rays.
    public static func width(at x: Int, _ y: Int, in ink: BinaryBitmap, maxRadius: Int = 64) -> Double {
        let dirs: [(Int, Int, Double)] = [
            (1, 0, 1), (-1, 0, 1), (0, 1, 1), (0, -1, 1),
            (1, 1, 2.0.squareRoot()), (-1, -1, 2.0.squareRoot()), (1, -1, 2.0.squareRoot()), (-1, 1, 2.0.squareRoot()),
        ]
        var best = Double(maxRadius)
        for (dx, dy, step) in dirs {
            var d = 1
            while d < maxRadius {
                if ink.at(x + dx * d, y + dy * d) == 0 { break }
                d += 1
            }
            best = min(best, Double(d) * step)
        }
        // best is the distance to the first paper pixel, so the half-width is best - 0.5.
        return max(1, 2 * best - 1)
    }
}

import Foundation

/// Sauvola local thresholding. Works on uneven lighting, which is the normal case for
/// a phone photo of paper.
public struct Binarizer {
    /// Window side as a fraction of the shorter image side.
    public var windowFraction: Double = 1.0 / 24.0
    /// Sauvola k. Larger drops more faint pixels.
    public var k: Double = 0.2
    /// Dynamic range of the standard deviation (128 for 8-bit).
    public var r: Double = 128
    /// Connected components with fewer ink pixels than this are removed.
    public var minComponentPixels: Int = 12

    public init() {}

    public func binarize(_ gray: GrayBitmap) -> BinaryBitmap {
        let w = gray.width, h = gray.height
        var win = Int(Double(min(w, h)) * windowFraction)
        if win < 7 { win = 7 }
        if win % 2 == 0 { win += 1 }
        let half = win / 2

        // Integral images of value and value^2, (w+1)x(h+1).
        let stride = w + 1
        var sum = [Double](repeating: 0, count: (w + 1) * (h + 1))
        var sq = [Double](repeating: 0, count: (w + 1) * (h + 1))
        for y in 0..<h {
            var rowSum = 0.0, rowSq = 0.0
            for x in 0..<w {
                let v = Double(gray.pixels[y * w + x])
                rowSum += v
                rowSq += v * v
                let i = (y + 1) * stride + (x + 1)
                sum[i] = sum[i - stride] + rowSum
                sq[i] = sq[i - stride] + rowSq
            }
        }

        var out = BinaryBitmap(width: w, height: h)
        for y in 0..<h {
            let y0 = max(0, y - half), y1 = min(h - 1, y + half)
            for x in 0..<w {
                let x0 = max(0, x - half), x1 = min(w - 1, x + half)
                let n = Double((x1 - x0 + 1) * (y1 - y0 + 1))
                let a = (y1 + 1) * stride + (x1 + 1)
                let b = y0 * stride + (x1 + 1)
                let c = (y1 + 1) * stride + x0
                let d = y0 * stride + x0
                let s = sum[a] - sum[b] - sum[c] + sum[d]
                let s2 = sq[a] - sq[b] - sq[c] + sq[d]
                let mean = s / n
                let variance = max(0, s2 / n - mean * mean)
                let std = variance.squareRoot()
                let t = mean * (1 + k * (std / r - 1))
                if Double(gray.pixels[y * w + x]) < t {
                    out.bits[y * w + x] = 1
                }
            }
        }
        if minComponentPixels > 1 {
            removeSmallComponents(&out, minPixels: minComponentPixels)
        }
        return out
    }

    /// Flood-fills each 8-connected ink component and clears those below `minPixels`.
    public func removeSmallComponents(_ bmp: inout BinaryBitmap, minPixels: Int) {
        let w = bmp.width, h = bmp.height
        var seen = [Bool](repeating: false, count: w * h)
        var stack: [Int] = []
        var component: [Int] = []
        for start in 0..<(w * h) where bmp.bits[start] == 1 && !seen[start] {
            stack.removeAll(keepingCapacity: true)
            component.removeAll(keepingCapacity: true)
            stack.append(start)
            seen[start] = true
            while let idx = stack.popLast() {
                component.append(idx)
                let x = idx % w, y = idx / w
                for dy in -1...1 {
                    for dx in -1...1 where dx != 0 || dy != 0 {
                        let nx = x + dx, ny = y + dy
                        if nx < 0 || ny < 0 || nx >= w || ny >= h { continue }
                        let ni = ny * w + nx
                        if bmp.bits[ni] == 1 && !seen[ni] {
                            seen[ni] = true
                            stack.append(ni)
                        }
                    }
                }
            }
            if component.count < minPixels {
                for i in component { bmp.bits[i] = 0 }
            }
        }
    }
}

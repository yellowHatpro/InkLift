import Foundation

/// One sample on a pen path. Coordinates are in page points, origin top-left.
public struct StrokePoint: Equatable, Codable {
    public var x: Double
    public var y: Double
    /// Pen width at this sample, in page points.
    public var width: Double

    public init(x: Double, y: Double, width: Double) {
        self.x = x
        self.y = y
        self.width = width
    }
}

public struct StrokeColor: Equatable, Codable {
    public var r: Double
    public var g: Double
    public var b: Double
    public var a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public static let black = StrokeColor(r: 0, g: 0, b: 0)
}

/// A continuous pen path.
public struct Stroke: Equatable, Codable {
    public var points: [StrokePoint]
    public var color: StrokeColor

    public init(points: [StrokePoint], color: StrokeColor = .black) {
        self.points = points
        self.color = color
    }

    public var averageWidth: Double {
        guard !points.isEmpty else { return 0 }
        return points.reduce(0) { $0 + $1.width } / Double(points.count)
    }

    public var length: Double {
        guard points.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<points.count {
            let dx = points[i].x - points[i - 1].x
            let dy = points[i].y - points[i - 1].y
            total += (dx * dx + dy * dy).squareRoot()
        }
        return total
    }
}

public struct PageSize: Equatable, Codable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }

    /// US Letter in PDF points.
    public static let letter = PageSize(width: 612, height: 792)
    /// A4 in PDF points.
    public static let a4 = PageSize(width: 595.28, height: 841.89)
}

public struct Page: Equatable, Codable {
    public var size: PageSize
    public var strokes: [Stroke]

    public init(size: PageSize, strokes: [Stroke]) {
        self.size = size
        self.strokes = strokes
    }
}

public struct InkDocument: Equatable, Codable {
    public var title: String
    public var pages: [Page]

    public init(title: String, pages: [Page]) {
        self.title = title
        self.pages = pages
    }
}

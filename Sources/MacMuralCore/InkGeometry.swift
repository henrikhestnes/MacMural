import Foundation
import CoreGraphics

extension DrawingGeometry {
    /// Filled paths shared by rendering and eraser hit testing, including the
    /// actual smoothed pen curve and the filled arrowhead.
    public static func inkPaths(for annotation: Annotation) -> [CGPath] {
        guard let start = annotation.points.first, let end = annotation.points.last else { return [] }
        let stroke = CGMutablePath()
        func outline() -> CGPath {
            stroke.copy(strokingWithWidth: annotation.width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        }
        switch annotation.tool {
        case .arrow:
            let distance = hypot(end.x - start.x, end.y - start.y)
            guard distance >= 2 else { return [] }
            let angle = atan2(end.y - start.y, end.x - start.x)
            let head = arrowheadLength(for: distance, lineWidth: annotation.width)
            stroke.move(to: start)
            stroke.addLine(to: CGPoint(x: end.x - cos(angle) * head * 0.78, y: end.y - sin(angle) * head * 0.78))
            let triangle = CGMutablePath()
            triangle.move(to: end)
            triangle.addLine(to: CGPoint(x: end.x - cos(angle - .pi / 6) * head, y: end.y - sin(angle - .pi / 6) * head))
            triangle.addLine(to: CGPoint(x: end.x - cos(angle + .pi / 6) * head, y: end.y - sin(angle + .pi / 6) * head))
            triangle.closeSubpath()
            return [outline(), triangle]
        case .rectangle:
            stroke.addRect(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                                  width: abs(end.x - start.x), height: abs(end.y - start.y)))
            return [outline()]
        case .pen:
            if annotation.points.count == 1 {
                return [CGPath(ellipseIn: CGRect(x: start.x - annotation.width / 2, y: start.y - annotation.width / 2,
                                                width: annotation.width, height: annotation.width), transform: nil)]
            }
            stroke.move(to: start)
            for index in 1..<annotation.points.count {
                let previous = annotation.points[index - 1]
                let point = annotation.points[index]
                stroke.addQuadCurve(to: CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2), control: previous)
            }
            stroke.addLine(to: end)
            return [outline()]
        case .laser, .eraser: return []
        }
    }
}

public enum DrawingHitTest {
    public static func touches(_ annotation: Annotation, from start: CGPoint, to end: CGPoint, radius: CGFloat) -> Bool {
        let radius = max(0.5, radius)
        let sweep = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                           width: abs(end.x - start.x), height: abs(end.y - start.y)).insetBy(dx: -radius, dy: -radius)
        for path in DrawingGeometry.inkPaths(for: annotation) {
            guard path.boundingBoxOfPath.intersects(sweep) else { continue }
            if path.contains(start) || path.contains(end) { return true }
            for (a, b) in edges(of: path) {
                if segmentDistanceSquared(start, end, a, b) <= radius * radius { return true }
            }
        }
        return false
    }

    private static func pointDistanceSquared(_ point: CGPoint, _ start: CGPoint, _ end: CGPoint) -> CGFloat {
        let dx = end.x - start.x, dy = end.y - start.y
        let length = dx * dx + dy * dy
        let t = length == 0 ? 0 : max(0, min(1, ((point.x - start.x) * dx + (point.y - start.y) * dy) / length))
        let x = point.x - start.x - t * dx, y = point.y - start.y - t * dy
        return x * x + y * y
    }

    private static func segmentDistanceSquared(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint) -> CGFloat {
        let rx = b.x - a.x, ry = b.y - a.y
        let sx = d.x - c.x, sy = d.y - c.y
        let denominator = rx * sy - ry * sx
        if denominator != 0 {
            let t = ((c.x - a.x) * sy - (c.y - a.y) * sx) / denominator
            let u = ((c.x - a.x) * ry - (c.y - a.y) * rx) / denominator
            if (0...1).contains(t), (0...1).contains(u) { return 0 }
        }
        return min(pointDistanceSquared(a, c, d), pointDistanceSquared(b, c, d),
                   pointDistanceSquared(c, a, b), pointDistanceSquared(d, a, b))
    }

    /// Flatten the filled outline to within a quarter point for swept-circle
    /// intersection. This handles both Bézier pen curves and round stroke caps.
    private static func edges(of path: CGPath) -> [(CGPoint, CGPoint)] {
        var result: [(CGPoint, CGPoint)] = []
        var current = CGPoint.zero, first = CGPoint.zero
        func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        func quadratic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ depth: Int = 0) {
            if depth >= 12 || pointDistanceSquared(b, a, c) <= 0.0625 {
                result.append((a, c)); return
            }
            let ab = midpoint(a, b), bc = midpoint(b, c)
            let center = midpoint(ab, bc)
            quadratic(a, ab, center, depth + 1)
            quadratic(center, bc, c, depth + 1)
        }
        func cubic(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint, _ d: CGPoint, _ depth: Int = 0) {
            if depth >= 12 || max(pointDistanceSquared(b, a, d), pointDistanceSquared(c, a, d)) <= 0.0625 {
                result.append((a, d)); return
            }
            let ab = midpoint(a, b), bc = midpoint(b, c), cd = midpoint(c, d)
            let abc = midpoint(ab, bc), bcd = midpoint(bc, cd)
            let center = midpoint(abc, bcd)
            cubic(a, ab, abc, center, depth + 1)
            cubic(center, bcd, cd, d, depth + 1)
        }
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            switch element.type {
            case .moveToPoint: current = element.points[0]; first = current
            case .addLineToPoint:
                result.append((current, element.points[0])); current = element.points[0]
            case .addQuadCurveToPoint:
                quadratic(current, element.points[0], element.points[1]); current = element.points[1]
            case .addCurveToPoint:
                cubic(current, element.points[0], element.points[1], element.points[2]); current = element.points[2]
            case .closeSubpath:
                result.append((current, first)); current = first
            @unknown default: break
            }
        }
        return result
    }
}

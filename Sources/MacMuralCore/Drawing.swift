import Foundation
import CoreGraphics

public enum DrawingTool: String, CaseIterable {
    case arrow, rectangle, laser, pen, eraser

    public var title: String {
        switch self {
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .laser: return "Laser"
        case .pen: return "Pen"
        case .eraser: return "Eraser"
        }
    }

    public var key: String {
        switch self {
        case .arrow: return "a"
        case .rectangle: return "r"
        case .laser: return "l"
        case .pen: return "d"
        case .eraser: return "e"
        }
    }
}

public enum InkColor: String, CaseIterable {
    case coral, gold, mint, blue, white

    public var rgb: (Double, Double, Double) {
        switch self {
        case .coral: return (1, 0.31, 0.32)
        case .gold: return (1, 0.78, 0.22)
        case .mint: return (0.23, 0.90, 0.71)
        case .blue: return (0.32, 0.66, 1)
        case .white: return (1, 1, 1)
        }
    }
}

public struct Annotation: Equatable {
    public let id: UUID
    public let tool: DrawingTool
    public let color: InkColor
    public let width: CGFloat
    public var points: [CGPoint]

    public init(tool: DrawingTool, color: InkColor, width: CGFloat, points: [CGPoint]) {
        id = UUID()
        self.tool = tool
        self.color = color
        self.width = width
        self.points = points
    }

    public var isVisible: Bool {
        guard let first = points.first, let last = points.last else { return false }
        if tool == .pen { return true }
        return hypot(last.x - first.x, last.y - first.y) >= 2
    }
}

/// Stores only completed gestures in history. A clear is one undoable operation.
public final class DrawingStore {
    private enum Edit {
        case add(Annotation)
        case clear([Annotation])
        case erase(before: [Annotation], after: [Annotation])
    }

    public private(set) var annotations: [Annotation] = []
    private var undoStack: [Edit] = []
    private var redoStack: [Edit] = []
    private var isErasing = false
    private var erasureStart: [Annotation]?
    public var onChange: (() -> Void)?
    public var canUndo: Bool { !undoStack.isEmpty || erasureStart != nil }
    public var canRedo: Bool { !redoStack.isEmpty && erasureStart == nil }

    public init() {}

    public func add(_ annotation: Annotation) {
        finishErasing()
        guard annotation.tool != .laser, annotation.tool != .eraser, annotation.isVisible else { return }
        annotations.append(annotation)
        record(.add(annotation))
    }

    public func clear() {
        finishErasing()
        guard !annotations.isEmpty else { return }
        let previous = annotations
        annotations.removeAll()
        record(.clear(previous))
    }

    public func beginErasing() {
        finishErasing()
        isErasing = true
    }

    /// A swept segment prevents fast drags from skipping thin marks.
    public func erase(from start: CGPoint, to end: CGPoint, radius: CGFloat) {
        if !isErasing { beginErasing() }
        let ids = Set(annotations.filter {
            DrawingHitTest.touches($0, from: start, to: end, radius: radius)
        }.map(\.id))
        guard !ids.isEmpty else { return }
        if erasureStart == nil { erasureStart = annotations }
        annotations.removeAll { ids.contains($0.id) }
        onChange?()
    }

    /// All objects removed during one drag form a single undo step.
    public func finishErasing() {
        isErasing = false
        guard let previous = erasureStart else { return }
        erasureStart = nil
        record(.erase(before: previous, after: annotations))
    }

    /// Finishing a drawing session removes its ink and its undo/redo history.
    public func reset() {
        isErasing = false
        erasureStart = nil
        annotations.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        onChange?()
    }

    public func undo() {
        finishErasing()
        guard let edit = undoStack.popLast() else { return }
        switch edit {
        case .add(let annotation): annotations.removeAll { $0.id == annotation.id }
        case .clear(let previous): annotations = previous
        case .erase(let before, _): annotations = before
        }
        redoStack.append(edit)
        onChange?()
    }

    public func redo() {
        finishErasing()
        guard let edit = redoStack.popLast() else { return }
        switch edit {
        case .add(let annotation): annotations.append(annotation)
        case .clear: annotations.removeAll()
        case .erase(_, let after): annotations = after
        }
        undoStack.append(edit)
        onChange?()
    }

    private func record(_ edit: Edit) {
        undoStack.append(edit)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack.removeAll()
        onChange?()
    }
}

public enum DrawingGeometry {
    /// Prominent heads grow gradually with length and never swallow short arrows.
    public static func arrowheadLength(for length: CGFloat, lineWidth: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        let size = max(26, lineWidth * 6) + sqrt(length) * 1.25
        return min(length * 0.48, min(120, size))
    }

    /// Shift constrains rectangles to squares and arrows to 45-degree directions.
    public static func endpoint(from start: CGPoint, to end: CGPoint, tool: DrawingTool, constrained: Bool) -> CGPoint {
        guard constrained else { return end }
        let dx = end.x - start.x
        let dy = end.y - start.y
        if tool == .rectangle {
            let side = max(abs(dx), abs(dy))
            return CGPoint(x: start.x + (dx < 0 ? -side : side), y: start.y + (dy < 0 ? -side : side))
        }
        if tool == .arrow {
            let angle = (atan2(dy, dx) / (.pi / 4)).rounded() * (.pi / 4)
            let length = hypot(dx, dy)
            return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
        }
        return end
    }
}

public struct LaserSample {
    public let point: CGPoint
    public let time: TimeInterval
    public let startsSegment: Bool
}

public struct LaserTrail {
    public static let lifetime: TimeInterval = 0.65
    public private(set) var samples: [LaserSample] = []
    private var startsSegment = true
    public init() {}

    public mutating func append(_ point: CGPoint, at time: TimeInterval) {
        prune(at: time)
        samples.append(LaserSample(point: point, time: time, startsSegment: startsSegment || samples.isEmpty))
        startsSegment = false
    }

    public mutating func prune(at time: TimeInterval) {
        samples.removeAll { time - $0.time >= Self.lifetime }
    }

    public mutating func endStroke() { startsSegment = true }

    public mutating func clear() {
        samples.removeAll()
        startsSegment = true
    }
}

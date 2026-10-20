import XCTest
import CoreGraphics
@testable import MacMuralCore

final class DrawingTests: XCTestCase {
    private func shape(_ tool: DrawingTool = .arrow) -> Annotation {
        Annotation(tool: tool, color: .coral, width: 4, points: [.zero, CGPoint(x: 100, y: 50)])
    }

    func testUndoRedoAndNewGestureInvalidatesRedo() {
        let store = DrawingStore()
        let first = shape()
        let second = shape(.rectangle)
        store.add(first)
        store.add(second)
        store.undo()
        XCTAssertEqual(store.annotations, [first])
        store.redo()
        XCTAssertEqual(store.annotations, [first, second])
        store.undo()
        let third = shape(.pen)
        store.add(third)
        XCTAssertFalse(store.canRedo)
        store.redo()
        XCTAssertEqual(store.annotations, [first, third])
    }

    func testClearIsOneUndoableOperationAndRestoresOrder() {
        let store = DrawingStore()
        let first = shape()
        let second = shape(.rectangle)
        store.add(first)
        store.add(second)
        store.clear()
        XCTAssertTrue(store.annotations.isEmpty)
        store.clear() // Clearing an empty canvas must not consume another undo step.
        store.undo()
        XCTAssertEqual(store.annotations, [first, second])
        store.redo()
        XCTAssertTrue(store.annotations.isEmpty)
        store.undo()
        store.undo()
        XCTAssertEqual(store.annotations, [first])
    }

    func testLaserAndAccidentalShapeClicksDoNotEnterHistory() {
        let store = DrawingStore()
        store.add(shape(.laser))
        store.add(Annotation(tool: .arrow, color: .blue, width: 4, points: [.zero]))
        XCTAssertFalse(store.canUndo)
        store.add(Annotation(tool: .pen, color: .blue, width: 4, points: [.zero]))
        XCTAssertEqual(store.annotations.count, 1) // A pen tap is a dot.
    }

    func testSquareConstraintWorksInEveryDirectionAndWithNegativeCoordinates() {
        let start = CGPoint(x: -300, y: -50)
        for end in [CGPoint(x: -290, y: 0), CGPoint(x: -350, y: 0),
                    CGPoint(x: -290, y: -100), CGPoint(x: -350, y: -60)] {
            let constrained = DrawingGeometry.endpoint(from: start, to: end, tool: .rectangle, constrained: true)
            XCTAssertEqual(abs(constrained.x - start.x), abs(constrained.y - start.y))
            XCTAssertEqual(constrained.x < start.x, end.x < start.x)
            XCTAssertEqual(constrained.y < start.y, end.y < start.y)
        }
    }

    func testArrowConstraintSnapsAngleAndPreservesLength() {
        let end = CGPoint(x: 90, y: 70)
        let constrained = DrawingGeometry.endpoint(from: .zero, to: end, tool: .arrow, constrained: true)
        XCTAssertEqual(constrained.x, constrained.y, accuracy: 0.00001)
        XCTAssertEqual(hypot(constrained.x, constrained.y), hypot(end.x, end.y), accuracy: 0.00001)
        XCTAssertEqual(DrawingGeometry.endpoint(from: .zero, to: end, tool: .arrow, constrained: false), end)
    }

    func testLaserExpiresWithoutLeavingPermanentSamples() {
        var trail = LaserTrail()
        trail.append(.zero, at: 10)
        trail.append(CGPoint(x: 10, y: 20), at: 10.5)
        trail.prune(at: 10.7)
        XCTAssertEqual(trail.samples.count, 1)
        trail.prune(at: 11.2)
        XCTAssertTrue(trail.samples.isEmpty)
        trail.append(.zero, at: 12)
        trail.clear()
        XCTAssertTrue(trail.samples.isEmpty)
    }

    func testLongHistoryRemainsBoundedAndClearRemainsUndoable() {
        let store = DrawingStore()
        for _ in 0..<130 { store.add(shape()) }
        for _ in 0..<110 { store.undo() }
        XCTAssertEqual(store.annotations.count, 30)
        XCTAssertFalse(store.canUndo)
        store.clear()
        store.undo()
        XCTAssertEqual(store.annotations.count, 30)
    }

    func testFinishingSessionRemovesInkAndBothHistoryStacks() {
        let store = DrawingStore()
        store.add(shape())
        store.add(shape(.rectangle))
        store.undo()
        XCTAssertTrue(store.canUndo)
        XCTAssertTrue(store.canRedo)
        store.reset()
        store.undo()
        store.redo()
        XCTAssertTrue(store.annotations.isEmpty)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)
        let fresh = shape(.pen)
        store.add(fresh)
        store.undo()
        XCTAssertTrue(store.annotations.isEmpty)
    }

    func testArrowheadsGrowWithLengthAndRemainProportionalOnShortArrows() {
        let medium = DrawingGeometry.arrowheadLength(for: 100, lineWidth: 4)
        let long = DrawingGeometry.arrowheadLength(for: 800, lineWidth: 4)
        XCTAssertGreaterThan(medium, 30)
        XCTAssertGreaterThan(long, medium)
        XCTAssertGreaterThan(DrawingGeometry.arrowheadLength(for: 800, lineWidth: 7), long)
        for length: CGFloat in [0, 2, 10, 25, 50, 100, 500, 2000, 10000] {
            let head = DrawingGeometry.arrowheadLength(for: length, lineWidth: 4)
            XCTAssertTrue(head.isFinite)
            XCTAssertGreaterThanOrEqual(head, 0)
            XCTAssertLessThanOrEqual(head, length * 0.48)
            XCTAssertLessThanOrEqual(head, 120)
        }
    }

    func testSeparateLaserGesturesNeverConnectAcrossMouseRelease() {
        var trail = LaserTrail()
        trail.append(.zero, at: 10)
        trail.append(CGPoint(x: 20, y: 20), at: 10.01)
        trail.endStroke()
        trail.append(CGPoint(x: 80, y: 80), at: 10.02)
        XCTAssertEqual(trail.samples.count, 3)
        XCTAssertTrue(trail.samples[0].startsSegment)
        XCTAssertFalse(trail.samples[1].startsSegment)
        XCTAssertTrue(trail.samples[2].startsSegment)
    }
}

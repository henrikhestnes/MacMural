import XCTest
import CoreGraphics
@testable import MacMuralCore

final class EraserTests: XCTestCase {
    private func shape(_ tool: DrawingTool, _ points: [CGPoint], width: CGFloat = 4) -> Annotation {
        Annotation(tool: tool, color: .coral, width: width, points: points)
    }

    func testArrowheadIsErasableAwayFromTheShaft() {
        let arrow = shape(.arrow, [.zero, CGPoint(x: 200, y: 0)])
        let insideHead = CGPoint(x: 170, y: 15)
        XCTAssertTrue(DrawingHitTest.touches(arrow, from: insideHead, to: insideHead, radius: 1))
        let outside = CGPoint(x: 170, y: 40)
        XCTAssertFalse(DrawingHitTest.touches(arrow, from: outside, to: outside, radius: 1))
    }

    func testHollowRectangleInteriorIsNotErasableButItsBorderIs() {
        let rectangle = shape(.rectangle, [.zero, CGPoint(x: 200, y: 100)])
        XCTAssertFalse(DrawingHitTest.touches(rectangle, from: CGPoint(x: 60, y: 30), to: CGPoint(x: 140, y: 70), radius: 8))
        let edge = CGPoint(x: 100, y: 101)
        XCTAssertTrue(DrawingHitTest.touches(rectangle, from: edge, to: edge, radius: 2))
    }

    func testFastSweepCannotSkipAThinStroke() {
        let arrow = shape(.arrow, [CGPoint(x: -100, y: -50), CGPoint(x: 100, y: -50)], width: 2)
        XCTAssertTrue(DrawingHitTest.touches(arrow, from: CGPoint(x: 0, y: -200), to: CGPoint(x: 0, y: 100), radius: 3))
        XCTAssertFalse(DrawingHitTest.touches(arrow, from: CGPoint(x: 0, y: -200), to: CGPoint(x: 0, y: -60), radius: 3))
    }

    func testHitTestingFollowsTheRenderedPenCurveRatherThanItsControlPoints() {
        let pen = shape(.pen, [.zero, CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 0)])
        let onCurve = CGPoint(x: 100, y: 75)
        let controlPoint = CGPoint(x: 100, y: 100)
        XCTAssertTrue(DrawingHitTest.touches(pen, from: onCurve, to: onCurve, radius: 1))
        XCTAssertFalse(DrawingHitTest.touches(pen, from: controlPoint, to: controlPoint, radius: 1))
    }

    func testPenDotsAndEraserRadiusAreRespected() {
        let dot = shape(.pen, [CGPoint(x: -40, y: 10)], width: 8)
        let nearby = CGPoint(x: -29, y: 10)
        XCTAssertTrue(DrawingHitTest.touches(dot, from: nearby, to: nearby, radius: 8))
        XCTAssertFalse(DrawingHitTest.touches(dot, from: nearby, to: nearby, radius: 3))
    }

    func testOneEraseDragRestoresAllRemovedObjectsInTheirOriginalOrder() {
        let store = DrawingStore()
        let first = shape(.arrow, [.zero, CGPoint(x: 100, y: 0)])
        let second = shape(.pen, [CGPoint(x: 50, y: 100)])
        let third = shape(.rectangle, [CGPoint(x: 200, y: 200), CGPoint(x: 300, y: 300)])
        [first, second, third].forEach { store.add($0) }
        store.beginErasing()
        store.erase(from: CGPoint(x: 50, y: -20), to: CGPoint(x: 50, y: 20), radius: 5)
        store.erase(from: CGPoint(x: 50, y: 20), to: CGPoint(x: 50, y: 120), radius: 5)
        store.finishErasing()
        XCTAssertEqual(store.annotations, [third])
        store.undo()
        XCTAssertEqual(store.annotations, [first, second, third])
        store.redo()
        XCTAssertEqual(store.annotations, [third])
    }

    func testEmptyEraserGestureDoesNotDiscardRedo() {
        let store = DrawingStore()
        let arrow = shape(.arrow, [.zero, CGPoint(x: 100, y: 0)])
        store.add(arrow)
        store.undo()
        store.beginErasing()
        store.erase(from: CGPoint(x: 500, y: 500), to: CGPoint(x: 600, y: 600), radius: 16)
        store.finishErasing()
        XCTAssertTrue(store.canRedo)
        store.redo()
        XCTAssertEqual(store.annotations, [arrow])
    }

    func testUndoDuringErasureCompletesAndReversesTheGesture() {
        let store = DrawingStore()
        let dot = shape(.pen, [.zero])
        store.add(dot)
        store.beginErasing()
        store.erase(from: .zero, to: .zero, radius: 10)
        XCTAssertTrue(store.annotations.isEmpty)
        store.undo()
        XCTAssertEqual(store.annotations, [dot])
        store.redo()
        XCTAssertTrue(store.annotations.isEmpty)
    }

    func testClearAndResetHandleAnUnfinishedEraseGesture() {
        let store = DrawingStore()
        let first = shape(.pen, [.zero])
        let second = shape(.pen, [CGPoint(x: 100, y: 100)])
        store.add(first)
        store.add(second)
        store.erase(from: .zero, to: .zero, radius: 10)
        store.clear()
        store.undo()
        XCTAssertEqual(store.annotations, [second])
        store.undo()
        XCTAssertEqual(store.annotations, [first, second])
        store.erase(from: .zero, to: .zero, radius: 10)
        store.reset()
        store.finishErasing()
        store.undo()
        XCTAssertTrue(store.annotations.isEmpty)
        XCTAssertFalse(store.canUndo)
        XCTAssertFalse(store.canRedo)
    }
}

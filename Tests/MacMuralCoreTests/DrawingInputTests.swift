import XCTest
@testable import MacMuralCore

final class DrawingInputTests: XCTestCase {
    func testLaserEmitsOnlyDuringAnExplicitCanvasPress() {
        var input = DrawingInputState()
        XCTAssertFalse(input.beginPointer())
        input.setEnabled(true)
        XCTAssertFalse(input.canEmitLaser) // Hovering never emits ink.
        XCTAssertTrue(input.beginPointer())
        XCTAssertTrue(input.canEmitLaser)
        input.endPointer()
        XCTAssertFalse(input.canEmitLaser)
        input.setEnabled(false)
        XCTAssertFalse(input.beginPointer())
    }

    func testSpaceCancelsGestureWithoutEndingTheSession() {
        var input = DrawingInputState()
        input.setEnabled(true)
        input.beginPointer()
        XCTAssertTrue(input.updateInteractionKey(held: true, anyMouseButtonDown: true))
        XCTAssertTrue(input.isEnabled)
        XCTAssertTrue(input.isPassingThrough)
        XCTAssertFalse(input.isPointerDown)
        XCTAssertFalse(input.canEmitLaser)
        XCTAssertFalse(input.beginPointer())
        input.updateInteractionKey(held: false, anyMouseButtonDown: false)
        XCTAssertTrue(input.acceptsDrawingInput)
        XCTAssertFalse(input.canEmitLaser) // Never continue the cancelled gesture.
        XCTAssertTrue(input.beginPointer())
        XCTAssertTrue(input.canEmitLaser)
    }

    func testSpaceReleaseWaitsForUnderlyingDragToEnd() {
        var input = DrawingInputState()
        input.setEnabled(true)
        input.updateInteractionKey(held: true, anyMouseButtonDown: false)
        input.updateInteractionKey(held: false, anyMouseButtonDown: true)
        XCTAssertTrue(input.isPassingThrough)
        XCTAssertFalse(input.acceptsDrawingInput)
        input.updateInteractionKey(held: false, anyMouseButtonDown: false)
        XCTAssertFalse(input.isPassingThrough)
        XCTAssertTrue(input.acceptsDrawingInput)
        XCTAssertFalse(input.isPointerDown)
    }

    func testRepeatedSpacePressDoesNotToggleDrawingBackOn() {
        var input = DrawingInputState()
        input.setEnabled(true)
        input.updateInteractionKey(held: true, anyMouseButtonDown: false)
        input.updateInteractionKey(held: true, anyMouseButtonDown: false)
        XCTAssertTrue(input.isPassingThrough)
        input.updateInteractionKey(held: false, anyMouseButtonDown: false)
        XCTAssertTrue(input.acceptsDrawingInput)
        XCTAssertFalse(input.canEmitLaser)
    }

    func testClosingDuringPassThroughCannotResumeTheClosedSession() {
        var input = DrawingInputState()
        input.setEnabled(true)
        input.updateInteractionKey(held: true, anyMouseButtonDown: false)
        input.setEnabled(false)
        input.updateInteractionKey(held: false, anyMouseButtonDown: false)
        XCTAssertFalse(input.isEnabled)
        XCTAssertFalse(input.isPassingThrough)
        XCTAssertFalse(input.acceptsDrawingInput)
        input.setEnabled(true)
        XCTAssertTrue(input.acceptsDrawingInput)
        XCTAssertFalse(input.canEmitLaser)
    }

    func testSpaceDoesNotActivateADisabledOverlay() {
        var input = DrawingInputState()
        input.updateInteractionKey(held: true, anyMouseButtonDown: true)
        XCTAssertFalse(input.isPassingThrough)
        XCTAssertFalse(input.beginPointer())
    }

    func testEnablingSessionWaitsForAnExplicitSpacePressToPassThrough() {
        var input = DrawingInputState()
        input.setEnabled(true)
        XCTAssertTrue(input.acceptsDrawingInput)
        XCTAssertFalse(input.isPassingThrough)
        input.updateInteractionKey(held: true, anyMouseButtonDown: false)
        XCTAssertTrue(input.isPassingThrough)
    }
}

/// The drawing session stays open during Space pass-through. Only a fresh
/// mouse-down on the canvas may start ink after a cancelled or underlying drag.
public struct DrawingInputState {
    public private(set) var isEnabled = false
    public private(set) var isPassingThrough = false
    public private(set) var isPointerDown = false
    public var acceptsDrawingInput: Bool { isEnabled && !isPassingThrough }
    public var canEmitLaser: Bool { acceptsDrawingInput && isPointerDown }

    public init() {}

    public mutating func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        isPassingThrough = false
        isPointerDown = false
    }

    @discardableResult
    public mutating func updateInteractionKey(held: Bool, anyMouseButtonDown: Bool) -> Bool {
        let previous = isPassingThrough
        if !isEnabled {
            isPassingThrough = false
        } else if held {
            isPassingThrough = true
            isPointerDown = false
        } else if !anyMouseButtonDown {
            // Do not interrupt a drag that began in the underlying app.
            isPassingThrough = false
        }
        return previous != isPassingThrough
    }

    @discardableResult
    public mutating func beginPointer() -> Bool {
        guard acceptsDrawingInput else { return false }
        isPointerDown = true
        return true
    }

    public mutating func endPointer() { isPointerDown = false }
}

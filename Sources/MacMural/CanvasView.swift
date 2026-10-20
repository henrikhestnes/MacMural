import AppKit
import MacMuralCore

extension InkColor {
    var nsColor: NSColor {
        let (r, g, b) = rgb
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class CanvasView: NSView {
    weak var controller: AppDelegate?
    var screenOrigin = CGPoint.zero
    private var eraserCursor: (radius: CGFloat, cursor: NSCursor)?
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() {
        guard let controller, controller.tool == .eraser else {
            addCursorRect(bounds, cursor: .crosshair)
            return
        }
        let radius = controller.eraserRadius
        if eraserCursor?.radius != radius {
            let size = radius * 2 + 6
            let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3))
                NSColor.white.setStroke()
                ring.lineWidth = 3
                ring.stroke()
                NSColor.black.setStroke()
                ring.lineWidth = 1
                ring.stroke()
                return true
            }
            eraserCursor = (radius, NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2)))
        }
        addCursorRect(bounds, cursor: eraserCursor!.cursor)
    }

    private func point(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? .zero
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.beginStroke(at: point(event))
    }

    override func mouseDragged(with event: NSEvent) {
        controller?.continueStroke(at: point(event), shift: event.modifierFlags.contains(.shift))
    }

    override func mouseUp(with event: NSEvent) {
        controller?.endStroke(at: point(event), shift: event.modifierFlags.contains(.shift))
    }

    override func rightMouseDown(with event: NSEvent) { controller?.setEnabled(false) }
    override func keyDown(with event: NSEvent) {} // Drawing shortcuts never type into the underlying app.

    override func draw(_ dirtyRect: NSRect) {
        guard let controller, let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(dirtyRect)
        context.saveGState()
        context.translateBy(x: -screenOrigin.x, y: -screenOrigin.y)
        for annotation in controller.store.annotations { Self.draw(annotation, in: context) }
        if let pending = controller.pendingStroke { Self.draw(pending, in: context) }
        drawLaser(controller.laser, pointer: controller.laserPointer, in: context)
        context.restoreGState()
    }

    static func draw(_ annotation: Annotation, in context: CGContext) {
        context.saveGState()
        context.setFillColor(annotation.color.nsColor.cgColor)
        context.setShadow(offset: CGSize(width: 0, height: -1), blur: 3, color: NSColor.black.withAlphaComponent(0.35).cgColor)
        for path in DrawingGeometry.inkPaths(for: annotation) {
            context.addPath(path)
            context.fillPath()
        }
        context.restoreGState()
    }

    private func drawLaser(_ trail: LaserTrail, pointer: CGPoint?, in context: CGContext) {
        let now = ProcessInfo.processInfo.systemUptime
        let points = trail.samples
        guard pointer != nil || !points.isEmpty else { return }
        context.saveGState()
        context.setLineCap(.round)
        for index in points.indices.dropFirst() {
            let previous = points[index - 1]
            let current = points[index]
            // Do not connect separate movements after a pause or display jump.
            guard !current.startsSegment, current.time - previous.time < 0.12,
                  hypot(current.point.x - previous.point.x, current.point.y - previous.point.y) < 220 else { continue }
            let alpha = max(0, 1 - (now - current.time) / LaserTrail.lifetime)
            context.setStrokeColor(NSColor.systemRed.withAlphaComponent(alpha).cgColor)
            context.setShadow(offset: .zero, blur: 9, color: NSColor.systemRed.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(2 + alpha * 3)
            context.move(to: previous.point)
            context.addLine(to: current.point)
            context.strokePath()
        }
        if let point = pointer ?? points.last?.point {
            let alpha = pointer != nil ? 1 : max(0, 1 - (now - points.last!.time) / LaserTrail.lifetime)
            context.setFillColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            context.setShadow(offset: .zero, blur: 10, color: NSColor.systemRed.withAlphaComponent(alpha).cgColor)
            context.fillEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
        }
        context.restoreGState()
    }
}

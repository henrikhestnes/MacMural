import AppKit
import MacMuralCore

final class WelcomeWindow: NSObject {
    let window: NSWindow
    private weak var controller: AppDelegate?
    private let message = NSTextField(wrappingLabelWithString: "")
    private let loginNotice = NSTextField(labelWithString: "")

    init(controller: AppDelegate) {
        self.controller = controller
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 654),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "Welcome to MacMural"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.backgroundColor = NSColor(srgbRed: 0.965, green: 0.96, blue: 0.94, alpha: 1)
        window.appearance = NSAppearance(named: .aqua)
        guard let content = window.contentView else { return }

        func label(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat,
                   weight: NSFont.Weight = .regular, color: NSColor = .labelColor) {
            let field = NSTextField(labelWithString: text)
            field.frame = NSRect(x: x, y: y, width: width, height: size + 10)
            field.font = .systemFont(ofSize: size, weight: weight)
            field.textColor = color
            content.addSubview(field)
        }

        label("MACMURAL", x: 36, y: 592, width: 300, size: 11, weight: .bold, color: .secondaryLabelColor)
        label("Draw on anything.", x: 36, y: 535, width: 530, size: 37, weight: .bold)
        label("A little ink. A clearer point.", x: 38, y: 502, width: 520, size: 16, color: .secondaryLabelColor)

        let preview = PreviewView(frame: NSRect(x: 36, y: 332, width: 528, height: 147))
        content.addSubview(preview)

        let shortcutRows: [(String, String, String, String)] = [
            (controller.shortcutLabel(.toggle), "Start / finish drawing", controller.shortcutLabel(.arrow), "Arrow"),
            (controller.shortcutLabel(.laser), "Click + drag laser", controller.shortcutLabel(.rectangle), "Rectangle"),
            (controller.shortcutLabel(.clear), "Clear all drawings", controller.shortcutLabel(.undo), "Undo · \(controller.shortcutLabel(.redo)) to redo"),
            (controller.shortcutLabel(.pen), "Freehand pen", controller.shortcutLabel(.eraser), "Eraser" )
        ]
        for (index, row) in shortcutRows.enumerated() {
            let y = CGFloat(284 - index * 39)
            for (x, key, description) in [(CGFloat(36), row.0, row.1), (CGFloat(312), row.2, row.3)] {
                let cap = NSTextField(labelWithString: key)
                cap.frame = NSRect(x: x, y: y, width: 69, height: 27)
                cap.font = .monospacedSystemFont(ofSize: 12, weight: .semibold)
                cap.alignment = .center
                cap.lineBreakMode = .byTruncatingMiddle
                cap.toolTip = key
                cap.drawsBackground = true
                cap.backgroundColor = NSColor.black.withAlphaComponent(0.055)
                cap.wantsLayer = true
                cap.layer?.cornerRadius = 6
                cap.layer?.masksToBounds = true
                content.addSubview(cap)
                label(description, x: x + 80, y: y + 1, width: 191, size: 12)
            }
        }

        message.frame = NSRect(x: 38, y: 104, width: 524, height: 46)
        message.font = .systemFont(ofSize: 12)
        message.textColor = .secondaryLabelColor
        content.addSubview(message)
        setShortcutErrors([])
        loginNotice.frame = NSRect(x: 38, y: 88, width: 524, height: 16)
        loginNotice.font = .systemFont(ofSize: 10)
        loginNotice.textColor = .secondaryLabelColor
        loginNotice.lineBreakMode = .byTruncatingTail
        content.addSubview(loginNotice)

        let start = NSButton(title: "Start drawing   \(controller.shortcutLabel(.toggle))", target: self, action: #selector(startDrawing))
        start.frame = NSRect(x: 36, y: 43, width: 528, height: 44)
        start.bezelStyle = .rounded
        start.controlSize = .large
        start.font = .systemFont(ofSize: 15, weight: .semibold)
        start.bezelColor = NSColor(srgbRed: 0.12, green: 0.27, blue: 0.23, alpha: 1)
        start.contentTintColor = .white
        start.keyEquivalent = "\r"
        content.addSubview(start)
        label("Lives in your menu bar. No account. No network. Just draw.", x: 38, y: 11, width: 524, size: 11, color: .secondaryLabelColor)
    }

    func setShortcutErrors(_ errors: [String]) {
        if errors.isEmpty {
            let hyperHint = controller?.shortcuts.hyperEnabled == true ? "Hyper+D also toggles drawing. " : ""
            let interactionKey = controller?.shortcutLabel(.interact) ?? "Space"
            message.stringValue = "\(hyperHint)Hold \(interactionKey) to interact underneath. Esc finishes and clears. Change keys in the menu bar’s Keyboard Shortcuts… settings."
            message.textColor = .secondaryLabelColor
        } else {
            message.stringValue = "Unavailable shortcuts: \(errors.joined(separator: ", ")). Another app may be using them. Other shortcuts and the menu bar remain available."
            message.textColor = .systemRed
        }
    }

    func setLoginNotice(_ text: String) {
        loginNotice.stringValue = text
        loginNotice.toolTip = text
    }

    @objc private func startDrawing() {
        window.orderOut(nil)
        controller?.setEnabled(true)
    }
}

/// Code-drawn artwork keeps the application self-contained and resolution independent.
private final class PreviewView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 14, yRadius: 14).fill()
        NSColor.black.withAlphaComponent(0.06).setStroke()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 14, yRadius: 14).stroke()

        for index in 0..<3 {
            NSColor.black.withAlphaComponent(0.12).setFill()
            NSBezierPath(ovalIn: NSRect(x: 18 + index * 14, y: 122, width: 6, height: 6)).fill()
        }
        let text: NSString = "Your next bright idea."
        text.draw(at: NSPoint(x: 30, y: 77), withAttributes: [
            .font: NSFont.systemFont(ofSize: 21, weight: .semibold),
            .foregroundColor: NSColor.labelColor.withAlphaComponent(0.8)
        ])
        for (y, width) in [(CGFloat(54), CGFloat(175)), (CGFloat(38), CGFloat(128))] {
            NSColor.black.withAlphaComponent(0.07).setFill()
            NSBezierPath(roundedRect: NSRect(x: 31, y: y, width: width, height: 6), xRadius: 3, yRadius: 3).fill()
        }
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        CanvasView.draw(Annotation(tool: .rectangle, color: .mint, width: 3,
                                   points: [CGPoint(x: 302, y: 27), CGPoint(x: 493, y: 104)]), in: context)
        CanvasView.draw(Annotation(tool: .arrow, color: .coral, width: 3.5,
                                   points: [CGPoint(x: 251, y: 32), CGPoint(x: 327, y: 78)]), in: context)
        let note: NSString = "right here"
        note.draw(at: NSPoint(x: 350, y: 54), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18, weight: .medium),
            .foregroundColor: NSColor(srgbRed: 0.1, green: 0.42, blue: 0.34, alpha: 1)
        ])
    }
}

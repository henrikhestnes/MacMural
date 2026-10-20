import AppKit
import MacMuralCore

final class ActionButton: NSButton {
    var actionBlock: (() -> Void)?
    var selected = false {
        didSet {
            setAccessibilityValue(selected ? 1 : 0)
            needsDisplay = true
        }
    }
    var swatch: NSColor?

    init(symbol: String, label: String, action: @escaping () -> Void) {
        super.init(frame: NSRect(x: 0, y: 0, width: 38, height: 38))
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        imagePosition = .imageOnly
        isBordered = false
        focusRingType = .none
        contentTintColor = .white
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        self.action = #selector(performAction)
        actionBlock = action
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func performAction() { actionBlock?() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }

    override func draw(_ dirtyRect: NSRect) {
        if let swatch {
            if selected {
                NSColor.white.withAlphaComponent(0.9).setStroke()
                let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 4, dy: 4))
                ring.lineWidth = 1.5
                ring.stroke()
            }
            swatch.setFill()
            NSBezierPath(ovalIn: bounds.insetBy(dx: 9, dy: 9)).fill()
        } else {
            if selected || isHighlighted {
                NSColor.white.withAlphaComponent(isHighlighted ? 0.22 : 0.14).setFill()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 9, yRadius: 9).fill()
            }
            super.draw(dirtyRect)
        }
    }
}

private final class ToolbarView: NSVisualEffectView {
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {}
    override func mouseMoved(with event: NSEvent) {}
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
}

final class DrawingToolbar {
    private let background = ToolbarView(frame: NSRect(x: 0, y: 0, width: 626, height: 88))
    private var tools: [DrawingTool: ActionButton] = [:]
    private var colors: [InkColor: ActionButton] = [:]
    private var undoButton: ActionButton!
    private var redoButton: ActionButton!
    private var clearButton: ActionButton!
    private var widthButton: ActionButton!
    private let caption = NSTextField(labelWithString: "")

    init(controller: AppDelegate) {
        background.appearance = NSAppearance(named: .darkAqua)
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 18
        background.layer?.borderWidth = 1
        background.layer?.borderColor = NSColor.white.withAlphaComponent(0.15).cgColor
        background.setAccessibilityElement(true)
        background.setAccessibilityRole(.toolbar)
        background.setAccessibilityLabel("Drawing tools")

        var x: CGFloat = 12
        func add(_ button: ActionButton) {
            button.frame.origin = NSPoint(x: x, y: 38)
            background.addSubview(button)
            x += 40
        }
        func divider() {
            let line = NSView(frame: NSRect(x: x + 5, y: 45, width: 1, height: 24))
            line.wantsLayer = true
            line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
            background.addSubview(line)
            x += 14
        }

        for (tool, symbol) in [(DrawingTool.arrow, "arrow.up.right"), (.rectangle, "rectangle"),
                                (.laser, "laser.burst"), (.pen, "pencil.tip"), (.eraser, "eraser")] {
            let button = ActionButton(symbol: symbol, label: "\(tool.title) (\(tool.key.uppercased()))") { [weak controller] in
                controller?.selectTool(tool)
            }
            // Keep tools visible when a symbol is missing on older macOS versions.
            if button.image == nil {
                let fallback = tool == .eraser ? "rectangle.slash" : "sparkle"
                button.image = NSImage(systemSymbolName: fallback, accessibilityDescription: tool.title)
            }
            tools[tool] = button
            add(button)
        }
        divider()
        for color in InkColor.allCases {
            let button = ActionButton(symbol: "circle.fill", label: "\(color.rawValue.capitalized) ink") { [weak controller] in
                controller?.selectColor(color)
            }
            button.swatch = color.nsColor
            colors[color] = button
            add(button)
        }
        divider()
        widthButton = ActionButton(symbol: "lineweight", label: "Change line width (1 / 2 / 3)") { [weak controller] in
            controller?.cycleWidth()
        }
        add(widthButton)
        divider()
        undoButton = ActionButton(symbol: "arrow.uturn.backward", label: "Undo (⌘Z)") { [weak controller] in controller?.undo() }
        add(undoButton)
        redoButton = ActionButton(symbol: "arrow.uturn.forward", label: "Redo (⇧⌘Z)") { [weak controller] in controller?.redo() }
        add(redoButton)
        clearButton = ActionButton(symbol: "trash", label: "Clear drawings (C)") { [weak controller] in controller?.clear() }
        add(clearButton)
        divider()
        let done = ActionButton(symbol: "checkmark", label: "Finish drawing (⌘⌥D, Hyper+D, or Esc)") { [weak controller] in
            controller?.setEnabled(false)
        }
        add(done)

        let width = x + 10
        background.frame.size = NSSize(width: width, height: 88)
        caption.frame = NSRect(x: 18, y: 12, width: width - 36, height: 16)
        caption.font = .systemFont(ofSize: 11, weight: .medium)
        caption.textColor = NSColor.white.withAlphaComponent(0.62)
        caption.alignment = .center
        background.addSubview(caption)
    }

    func refresh(controller: AppDelegate) {
        for (tool, button) in tools { button.selected = tool == controller.tool }
        for (color, button) in colors { button.selected = color == controller.color }
        undoButton.isEnabled = controller.store.canUndo || controller.pendingStroke != nil
        redoButton.isEnabled = controller.store.canRedo
        clearButton.isEnabled = !controller.store.annotations.isEmpty || controller.pendingStroke != nil
        if controller.tool == .eraser {
            widthButton.toolTip = "Eraser diameter: \(Int(controller.eraserRadius * 2)) pt · click to cycle · 1 / 2 / 3"
            widthButton.setAccessibilityLabel("Change eraser size (1 / 2 / 3)")
        } else {
            widthButton.toolTip = "Line width: \(Int(controller.lineWidth)) pt · click to cycle · 1 / 2 / 3"
            widthButton.setAccessibilityLabel("Change line width (1 / 2 / 3)")
        }
        let hint: String
        switch controller.tool {
        case .laser: hint = "Click and drag to point"
        case .eraser: hint = "Drag to erase · ⌘Z to restore"
        default: hint = "Drag to draw · Shift to constrain"
        }
        let interactionHint = controller.interactionShortcutError == nil ? "Hold Space to interact" : "Space unavailable · see Help"
        caption.stringValue = "\(controller.tool.title)  ·  \(hint)  ·  \(interactionHint)  ·  Esc to finish"
    }

    func show(on screen: NSScreen, in canvas: NSView) {
        let area = screen.visibleFrame
        background.removeFromSuperview()
        background.setFrameOrigin(NSPoint(x: area.midX - screen.frame.minX - background.frame.width / 2,
                                           y: area.minY - screen.frame.minY + 24))
        canvas.addSubview(background)
    }

    func hide() { background.removeFromSuperview() }
}

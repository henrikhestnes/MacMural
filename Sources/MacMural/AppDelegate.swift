import AppKit
import MacMuralCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = DrawingStore()
    private(set) var tool = DrawingTool(rawValue: UserDefaults.standard.string(forKey: "tool") ?? "") ?? .arrow
    private(set) var color = InkColor(rawValue: UserDefaults.standard.string(forKey: "color") ?? "") ?? .coral
    private(set) var lineWidth: CGFloat = {
        let value = UserDefaults.standard.double(forKey: "width")
        return [2.0, 4.0, 7.0].contains(value) ? value : 4
    }()
    private var inputState = DrawingInputState()
    var isEnabled: Bool { inputState.isEnabled }
    var isPassingThrough: Bool { inputState.isPassingThrough }
    private(set) var pendingStroke: Annotation?
    private var previousEraserPoint: CGPoint?
    var eraserRadius: CGFloat { max(10, lineWidth * 4) }
    private(set) var laser = LaserTrail()
    private(set) var laserPointer: CGPoint?
    private var laserTimer: Timer?
    private var interactionReleaseTimer: Timer?
    private var isInteractionKeyHeld = false
    private(set) var interactionShortcutError: String?
    private var overlays: [OverlayPanel] = []
    private var toolbar: DrawingToolbar!
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var clearItem: NSMenuItem!
    private var hotKey = GlobalHotKey()
    private(set) var shortcuts = ShortcutConfiguration.load()
    private var shortcutSettings: ShortcutSettingsWindow?
    var toggleShortcutHint: String {
        shortcuts[.toggle].display + (shortcuts.hyperEnabled ? " or Hyper+D" : "")
    }
    func shortcutLabel(_ action: ShortcutAction) -> String { shortcuts[action].display }
    private var keyMonitor: Any?
    private var previousApplication: NSRunningApplication?
    private var welcome: WelcomeWindow?
    private var shortcutErrors: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureMenu()
        toolbar = DrawingToolbar(controller: self)
        rebuildOverlays()
        store.onChange = { [weak self] in self?.refresh() }
        hotKey.onPress = { [weak self] in
            guard let self else { return }
            self.setEnabled(!self.isEnabled)
        }
        hotKey.onInteractionKeyChange = { [weak self] held in
            self?.updateInteractionKey(held: held)
        }
        shortcutErrors = hotKey.register(shortcuts).map { "\($0.shortcut) (\($0.status))" }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isEnabled else { return event }
            guard !self.isPassingThrough else { return event }
            return self.handleKey(event) ? nil : event
        }
        NotificationCenter.default.addObserver(self, selector: #selector(screensChanged),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep),
                                                         name: NSWorkspace.willSleepNotification, object: nil)
        refresh()
        if CommandLine.arguments.contains("--demo") {
            showDemo()
        } else {
            showWelcome()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        laserTimer?.invalidate()
        interactionReleaseTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if inputState.acceptsDrawingInput { focusCanvas() }
        else if !isEnabled { showWelcome() }
        return true
    }

    private func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit MacMural", action: #selector(quit), keyEquivalent: "q").target = self
        appItem.submenu = appMenu
        main.addItem(appItem)
        NSApp.mainMenu = main

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pencil.tip.crop.circle", accessibilityDescription: "MacMural")
        let menu = NSMenu()
        let name = NSMenuItem(title: "MacMural", action: nil, keyEquivalent: "")
        name.isEnabled = false
        menu.addItem(name)
        menu.addItem(.separator())
        toggleItem = NSMenuItem(title: "Start Drawing", action: #selector(toggleDrawing), keyEquivalent: "d")
        toggleItem.keyEquivalent = shortcuts[.toggle].menuKey
        toggleItem.keyEquivalentModifierMask = shortcuts[.toggle].modifiers.cocoa
        toggleItem.target = self
        menu.addItem(toggleItem)
        clearItem = NSMenuItem(title: "Clear Drawings", action: #selector(clearFromMenu), keyEquivalent: "")
        clearItem.target = self
        menu.addItem(clearItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Keyboard Shortcuts…", action: #selector(showShortcutSettings), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Shortcuts & Help…", action: #selector(showWelcome), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit MacMural", action: #selector(quit), keyEquivalent: "q").target = self
        statusItem.menu = menu
    }

    @objc private func toggleDrawing() { setEnabled(!isEnabled) }
    @objc private func clearFromMenu() { clear() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func willSleep() { setEnabled(false) }
    @objc private func screensChanged() {
        finishEraserGesture()
        inputState.endPointer()
        pendingStroke = nil
        stopLaser()
        rebuildOverlays()
        if inputState.acceptsDrawingInput { focusCanvas() }
    }

    private func rebuildOverlays() {
        for panel in overlays { panel.orderOut(nil); panel.close() }
        overlays.removeAll()
        for screen in NSScreen.screens {
            let panel = OverlayPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: false)
            panel.title = "MacMural Canvas"
            panel.isReleasedWhenClosed = false
            panel.isOpaque = false
            panel.backgroundColor = inputState.acceptsDrawingInput ? NSColor.black.withAlphaComponent(0.001) : .clear
            panel.hasShadow = false
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.isFloatingPanel = true
            panel.acceptsMouseMovedEvents = false
            panel.ignoresMouseEvents = !inputState.acceptsDrawingInput
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            let canvas = CanvasView(frame: NSRect(origin: .zero, size: screen.frame.size))
            canvas.screenOrigin = screen.frame.origin
            canvas.controller = self
            canvas.setAccessibilityElement(true)
            canvas.setAccessibilityRole(.group)
            canvas.setAccessibilityLabel("Screen drawing canvas")
            canvas.autoresizingMask = [.width, .height]
            panel.contentView = canvas
            overlays.append(panel)
            if isEnabled || !store.annotations.isEmpty { panel.orderFrontRegardless() }
        }
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        if enabled {
            previousApplication = NSWorkspace.shared.frontmostApplication
            welcome?.window.orderOut(nil)
            shortcutSettings?.window.orderOut(nil)
        }
        inputState.setEnabled(enabled)
        previousEraserPoint = nil
        pendingStroke = nil
        stopLaser()
        interactionReleaseTimer?.invalidate()
        interactionReleaseTimer = nil
        let status = hotKey.setInteractionKeyEnabled(enabled)
        isInteractionKeyHeld = enabled && hotKey.isInteractionKeyHeld
        if enabled {
            interactionShortcutError = status == noErr ? nil : "\(shortcutLabel(.interact)) (\(status))"
            inputState.updateInteractionKey(held: isInteractionKeyHeld,
                                            anyMouseButtonDown: NSEvent.pressedMouseButtons != 0)
        } else {
            store.reset()
        }
        applyInputRouting()
    }

    private func applyInputRouting() {
        for panel in overlays {
            panel.ignoresMouseEvents = !inputState.acceptsDrawingInput
            panel.backgroundColor = inputState.acceptsDrawingInput ? NSColor.black.withAlphaComponent(0.001) : .clear
            if isEnabled { panel.orderFrontRegardless() }
            else { panel.orderOut(nil) }
        }
        if inputState.acceptsDrawingInput {
            if let current = NSWorkspace.shared.frontmostApplication,
               current.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication = current
            }
            focusCanvas()
        } else {
            toolbar.hide()
            for panel in overlays where panel.isKeyWindow { panel.resignKey() }
            if let previousApplication, previousApplication.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApplication.activate(options: [])
            }
            if !isEnabled { previousApplication = nil }
            NSCursor.arrow.set()
        }
        updateInteractionReleaseTimer()
        refresh()
    }

    private func updateInteractionReleaseTimer() {
        if isPassingThrough, !isInteractionKeyHeld, interactionReleaseTimer == nil {
            // Space release arrives through Carbon even with another app focused.
            // Only poll mouse-button state while waiting for an underlying drag.
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                self?.updateInteractionKey(held: false)
            }
            interactionReleaseTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        } else if !isPassingThrough || isInteractionKeyHeld {
            interactionReleaseTimer?.invalidate()
            interactionReleaseTimer = nil
        }
    }

    private func updateInteractionKey(held: Bool) {
        guard isEnabled else { return }
        isInteractionKeyHeld = held
        let changed = inputState.updateInteractionKey(held: held, anyMouseButtonDown: NSEvent.pressedMouseButtons != 0)
        guard changed else { updateInteractionReleaseTimer(); return }
        finishEraserGesture()
        pendingStroke = nil
        stopLaser()
        applyInputRouting()
    }

    private func focusCanvas() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        let panel = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
        panel?.makeKeyAndOrderFront(nil)
        if let view = panel?.contentView { panel?.makeFirstResponder(view) }
        if let screen, let canvas = panel?.contentView { toolbar.show(on: screen, in: canvas) }
    }

    func selectTool(_ tool: DrawingTool) {
        finishEraserGesture()
        inputState.endPointer()
        pendingStroke = nil
        stopLaser()
        self.tool = tool
        UserDefaults.standard.set(tool.rawValue, forKey: "tool")
        refresh()
    }

    func selectColor(_ color: InkColor) {
        self.color = color
        UserDefaults.standard.set(color.rawValue, forKey: "color")
        refresh()
    }

    func cycleWidth() {
        setWidth(lineWidth == 2 ? 4 : lineWidth == 4 ? 7 : 2)
    }

    private func setWidth(_ width: CGFloat) {
        lineWidth = width
        UserDefaults.standard.set(Double(width), forKey: "width")
        refresh()
    }

    func beginStroke(at point: CGPoint) {
        guard inputState.beginPointer() else { return }
        laser.endStroke()
        if tool == .eraser {
            store.beginErasing()
            previousEraserPoint = point
            store.erase(from: point, to: point, radius: eraserRadius)
            return
        }
        if tool == .laser { moveLaser(to: point); return }
        pendingStroke = Annotation(tool: tool, color: color, width: lineWidth, points: [point])
        refresh()
    }

    func continueStroke(at point: CGPoint, shift: Bool) {
        guard inputState.acceptsDrawingInput, inputState.isPointerDown else { return }
        if tool == .eraser {
            store.erase(from: previousEraserPoint ?? point, to: point, radius: eraserRadius)
            previousEraserPoint = point
            return
        }
        if tool == .laser { moveLaser(to: point); return }
        guard var stroke = pendingStroke, let start = stroke.points.first else { return }
        if stroke.tool == .pen {
            if let last = stroke.points.last, hypot(point.x - last.x, point.y - last.y) < 0.7 { return }
            stroke.points.append(point)
        } else {
            stroke.points = [start, DrawingGeometry.endpoint(from: start, to: point, tool: stroke.tool, constrained: shift)]
        }
        pendingStroke = stroke
        redrawCanvases()
    }

    func endStroke(at point: CGPoint, shift: Bool) {
        continueStroke(at: point, shift: shift)
        finishEraserGesture()
        inputState.endPointer()
        laserPointer = nil
        laser.endStroke()
        redrawCanvases()
        guard let stroke = pendingStroke else { return }
        pendingStroke = nil
        store.add(stroke)
        refresh()
    }

    private func moveLaser(to point: CGPoint) {
        guard inputState.canEmitLaser, tool == .laser else { return }
        laserPointer = point
        laser.append(point, at: ProcessInfo.processInfo.systemUptime)
        if laserTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                guard let self else { return }
                self.laser.prune(at: ProcessInfo.processInfo.systemUptime)
                self.redrawCanvases()
                if self.laser.samples.isEmpty {
                    self.laserTimer?.invalidate()
                    self.laserTimer = nil
                }
            }
            laserTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        redrawCanvases()
    }

    private func stopLaser() {
        laserTimer?.invalidate()
        laserTimer = nil
        laserPointer = nil
        laser.clear()
    }

    private func finishEraserGesture() {
        previousEraserPoint = nil
        store.finishErasing()
    }

    func undo() {
        inputState.endPointer()
        previousEraserPoint = nil
        stopLaser()
        if pendingStroke != nil { pendingStroke = nil; refresh(); return }
        store.undo()
        refresh()
    }

    func redo() { inputState.endPointer(); previousEraserPoint = nil; pendingStroke = nil; stopLaser(); store.redo(); refresh() }
    func clear() { inputState.endPointer(); previousEraserPoint = nil; pendingStroke = nil; stopLaser(); store.clear(); refresh() }

    private func handleKey(_ event: NSEvent) -> Bool {
        let shortcut = KeyboardShortcut(event)
        // Escape is always a way out, even after customizing the finish shortcut.
        if shortcut == .escape { setEnabled(false); return true }
        if let action = shortcuts.action(for: shortcut) {
            if event.isARepeat && action != .undo && action != .redo { return true }
            switch action {
            case .arrow: selectTool(.arrow)
            case .rectangle: selectTool(.rectangle)
            case .laser: selectTool(.laser)
            case .pen: selectTool(.pen)
            case .eraser: selectTool(.eraser)
            case .clear: clear()
            case .undo: undo()
            case .redo: redo()
            case .thin: setWidth(2)
            case .medium: setWidth(4)
            case .thick: setWidth(7)
            case .finish: setEnabled(false)
            case .toggle, .interact: break // Handled globally by Carbon.
            }
            return true
        }
        if shortcut == KeyboardShortcut(12, .command) { quit(); return true }
        // Keep system Command shortcuts available; consume other typing on the canvas.
        return !event.modifierFlags.contains(.command)
    }

    private func redrawCanvases() {
        for panel in overlays { panel.contentView?.needsDisplay = true }
    }

    private func refresh() {
        redrawCanvases()
        for panel in overlays {
            if let canvas = panel.contentView { panel.invalidateCursorRects(for: canvas) }
            let state = !isEnabled ? "Drawing closed" : isPassingThrough ? "Interaction key held or underlying drag in progress; interacting with underlying screen" : "Drawing enabled"
            panel.contentView?.setAccessibilityValue("\(state); \(tool.title) mode; \(store.annotations.count) drawings; \(color.rawValue) ink; \(Int(lineWidth)) pt")
        }
        toolbar?.refresh(controller: self)
        toggleItem?.title = isEnabled ? "Finish Drawing" : "Start Drawing"
        toggleItem?.state = isEnabled ? .on : .off
        clearItem?.isEnabled = !store.annotations.isEmpty
        statusItem?.button?.contentTintColor = isEnabled ? .systemMint : nil
        statusItem?.button?.toolTip = "MacMural · \(toggleShortcutHint) to \(isEnabled ? "finish" : "draw")"
        if !isEnabled, store.annotations.isEmpty {
            for panel in overlays { panel.orderOut(nil) }
        }
    }

    @objc private func showShortcutSettings() {
        setEnabled(false)
        welcome?.window.orderOut(nil)
        if shortcutSettings == nil {
            shortcutSettings = ShortcutSettingsWindow(configuration: shortcuts, onApply: { [weak self] proposed in
                guard let self else { return "MacMural is unavailable." }
                return self.applyShortcuts(proposed)
            }, onRecordingChange: { [weak self] recording in
                guard let self else { return }
                self.shortcutErrors = self.hotKey.suspendTogglesForRecording(recording).map {
                    "\($0.shortcut) (\($0.status))"
                }
            })
        }
        NSApp.activate(ignoringOtherApps: true)
        shortcutSettings?.window.center()
        shortcutSettings?.window.makeKeyAndOrderFront(nil)
    }

    private func applyShortcuts(_ proposed: ShortcutConfiguration) -> String? {
        if let error = proposed.validationError ?? SystemShortcuts.error(for: proposed, reserved: SystemShortcuts.current()) { return error }
        guard !hotKey.isInteractionKeyHeld else { return "Release the hold-to-interact key before applying changes." }
        let errors = hotKey.register(proposed)
        guard errors.isEmpty else {
            return "Could not register \(errors.map { "\($0.shortcut) (\($0.status))" }.joined(separator: ", ")). Another app or macOS may be using it. Your previous shortcuts are still active."
        }
        shortcuts = proposed
        shortcuts.save()
        shortcutErrors = []
        interactionShortcutError = nil
        toggleItem.keyEquivalent = shortcuts[.toggle].menuKey
        toggleItem.keyEquivalentModifierMask = shortcuts[.toggle].modifiers.cocoa
        welcome?.window.close()
        welcome = nil // Recreate help with the current bindings.
        refresh()
        return nil
    }

    @objc func showWelcome() {
        setEnabled(false)
        if welcome == nil { welcome = WelcomeWindow(controller: self) }
        welcome?.setShortcutErrors(shortcutErrors + [interactionShortcutError].compactMap { $0 })
        NSApp.activate(ignoringOtherApps: true)
        welcome?.window.center()
        welcome?.window.makeKeyAndOrderFront(nil)
    }

    private func showDemo() {
        setEnabled(true)
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        store.add(Annotation(tool: .arrow, color: .coral, width: 4,
                             points: [CGPoint(x: frame.midX - 190, y: frame.midY - 40), CGPoint(x: frame.midX - 50, y: frame.midY + 85)]))
        store.add(Annotation(tool: .rectangle, color: .mint, width: 4,
                             points: [CGPoint(x: frame.midX + 5, y: frame.midY - 50), CGPoint(x: frame.midX + 240, y: frame.midY + 110)]))
    }
}

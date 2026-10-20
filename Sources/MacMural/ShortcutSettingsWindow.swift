import AppKit
import MacMuralCore

private final class ShortcutRecorder: NSButton {
    var shortcut: KeyboardShortcut { didSet { if !recording { title = shortcut.display } } }
    var onChange: ((KeyboardShortcut) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    private(set) var recording = false

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        super.init(frame: .zero)
        title = shortcut.display
        bezelStyle = .rounded
        font = .monospacedSystemFont(ofSize: 13, weight: .medium)
        target = self
        action = #selector(startRecording)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }
    @objc private func startRecording() { window?.makeFirstResponder(self) }
    override func mouseDown(with event: NSEvent) { startRecording() }
    override func becomeFirstResponder() -> Bool {
        recording = true
        title = "Press keys…"
        setAccessibilityValue("Recording shortcut. Escape cancels.")
        onRecordingChange?(true)
        return true
    }
    override func resignFirstResponder() -> Bool {
        if recording {
            recording = false
            title = shortcut.display
            setAccessibilityValue(shortcut.display)
            onRecordingChange?(false)
        }
        return true
    }
    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }
        if event.keyCode != 53 {
            let candidate = KeyboardShortcut(event)
            guard KeyboardShortcut.keyNames[candidate.keyCode] != nil else { NSSound.beep(); return }
            shortcut = candidate
            onChange?(candidate)
        }
        window?.makeFirstResponder(nil)
    }
}

private final class ShortcutEditorWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if let recorder = firstResponder as? ShortcutRecorder, recorder.recording {
            recorder.keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class ShortcutSettingsWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    private var draft: ShortcutConfiguration
    private let systemShortcuts = SystemShortcuts.current()
    private var recorders: [ShortcutAction: ShortcutRecorder] = [:]
    private let hyper = NSButton(checkboxWithTitle: "Also enable Hyper+D (with or without Shift)", target: nil, action: nil)
    private let status = NSTextField(wrappingLabelWithString: "")
    private let applyButton = NSButton(title: "Apply", target: nil, action: nil)
    private let onApply: (ShortcutConfiguration) -> String?
    private let onRecordingChange: (Bool) -> Void

    init(configuration: ShortcutConfiguration, onApply: @escaping (ShortcutConfiguration) -> String?,
         onRecordingChange: @escaping (Bool) -> Void) {
        draft = configuration
        self.onApply = onApply
        self.onRecordingChange = onRecordingChange
        window = ShortcutEditorWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 700),
                                      styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "MacMural Shortcuts"
        window.isReleasedWhenClosed = false
        window.delegate = self
        guard let content = window.contentView else { return }
        func label(_ text: String, _ rect: NSRect, size: CGFloat = 13, weight: NSFont.Weight = .regular, parent: NSView? = nil) {
            let field = NSTextField(wrappingLabelWithString: text)
            field.frame = rect
            field.font = .systemFont(ofSize: size, weight: weight)
            (parent ?? content).addSubview(field)
        }
        label("Keyboard shortcuts", NSRect(x: 24, y: 646, width: 570, height: 30), size: 23, weight: .semibold)
        label("Start / finish works from any app. Other shortcuts work while drawing.\nChoose a shortcut below, then press the keys you want to use.",
              NSRect(x: 24, y: 592, width: 570, height: 44))
        let scroll = NSScrollView(frame: NSRect(x: 24, y: 196, width: 572, height: 390))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let rows = NSView(frame: NSRect(x: 0, y: 0, width: 552, height: 462))
        scroll.documentView = rows
        content.addSubview(scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 72))
        for (index, action) in ShortcutAction.allCases.enumerated() {
            let y = CGFloat(429 - index * 33)
            let title = action.title + (action == .toggle ? " (global)" : "")
            label(title, NSRect(x: 2, y: y + 3, width: 320, height: 24), parent: rows)
            let recorder = ShortcutRecorder(shortcut: configuration[action])
            recorder.frame = NSRect(x: 332, y: y, width: 216, height: 28)
            recorder.setAccessibilityLabel("Shortcut for \(action.title)")
            recorder.onChange = { [weak self] shortcut in
                self?.draft[action] = shortcut
                self?.validate()
            }
            recorder.onRecordingChange = onRecordingChange
            recorders[action] = recorder
            rows.addSubview(recorder)
        }
        label("Esc cancels recording and always remains available to finish drawing.",
              NSRect(x: 24, y: 167, width: 570, height: 24), size: 11)
        hyper.frame = NSRect(x: 24, y: 133, width: 570, height: 26)
        hyper.state = configuration.hyperEnabled ? .on : .off
        hyper.target = self
        hyper.action = #selector(hyperChanged)
        content.addSubview(hyper)
        status.frame = NSRect(x: 26, y: 62, width: 568, height: 62)
        status.font = .systemFont(ofSize: 12)
        content.addSubview(status)
        let reset = NSButton(title: "Restore Defaults", target: self, action: #selector(restoreDefaults))
        reset.bezelStyle = .rounded
        reset.frame = NSRect(x: 20, y: 20, width: 150, height: 32)
        content.addSubview(reset)
        let done = NSButton(title: "Done", target: self, action: #selector(close))
        done.bezelStyle = .rounded
        done.frame = NSRect(x: 408, y: 20, width: 90, height: 32)
        content.addSubview(done)
        applyButton.target = self
        applyButton.action = #selector(apply)
        applyButton.bezelStyle = .rounded
        applyButton.frame = NSRect(x: 500, y: 20, width: 98, height: 32)
        applyButton.keyEquivalent = "\r"
        content.addSubview(applyButton)
        validate()
    }
    private func validate() {
        let error = draft.validationError ?? SystemShortcuts.error(for: draft, reserved: systemShortcuts)
        status.stringValue = error ?? "Changes take effect when you click Apply and are remembered after quitting. Hold-to-interact requires a single key without modifiers."
        status.textColor = error == nil ? .secondaryLabelColor : .systemRed
        applyButton.isEnabled = error == nil
    }
    @objc private func hyperChanged() { draft.hyperEnabled = hyper.state == .on; validate() }
    @objc private func restoreDefaults() {
        window.makeFirstResponder(nil)
        draft = .defaults
        for (action, recorder) in recorders { recorder.shortcut = draft[action] }
        hyper.state = .on
        validate()
    }
    @objc private func apply() {
        window.makeFirstResponder(nil)
        guard draft.validationError == nil else { validate(); return }
        if let error = onApply(draft) {
            status.stringValue = error
            status.textColor = .systemRed
        } else {
            status.stringValue = "Shortcuts saved."
            status.textColor = .systemGreen
        }
    }
    @objc private func close() { window.close() }
    func windowWillClose(_ notification: Notification) { window.makeFirstResponder(nil) }
    func windowDidResignKey(_ notification: Notification) { window.makeFirstResponder(nil) }
}

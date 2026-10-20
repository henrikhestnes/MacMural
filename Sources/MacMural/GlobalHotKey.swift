import AppKit
import Carbon

final class GlobalHotKey {
    struct Registration {
        let shortcut: String
        let status: OSStatus
    }

    private static let signature: OSType = 0x4D4D524C // MMRL
    private static let shortcuts: [(name: String, modifiers: UInt32)] = [
        ("⌘⌥D", UInt32(cmdKey | optionKey)),
        ("Hyper+D (⌃⌥⌘D)", UInt32(controlKey | optionKey | cmdKey)),
        ("Hyper+D (⌃⌥⌘⇧D)", UInt32(controlKey | optionKey | cmdKey | shiftKey))
    ]
    private var hotKeys: [EventHotKeyRef] = []
    private static let interactionID: UInt32 = 100
    private var interactionKey: EventHotKeyRef?
    private var unregisterInteractionOnRelease = false
    private(set) var isInteractionKeyHeld = false
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    var onInteractionKeyChange: ((Bool) -> Void)?

    func register() -> [Registration] {
        unregister()
        let events = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var pressed = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                          nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            guard result == noErr, pressed.signature == GlobalHotKey.signature else {
                return OSStatus(eventNotHandledErr)
            }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            let isPressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            if pressed.id == GlobalHotKey.interactionID {
                hotKey.handleInteractionKey(held: isPressed)
            } else if isPressed, (1...UInt32(GlobalHotKey.shortcuts.count)).contains(pressed.id) {
                hotKey.onPress?()
            }
            return noErr
        }
        let status = events.withUnsafeBufferPointer {
            InstallEventHandler(GetApplicationEventTarget(), callback, 2, $0.baseAddress, context, &handler)
        }
        guard status == noErr else {
            return Self.shortcuts.map { Registration(shortcut: $0.name, status: status) }
        }
        return Self.shortcuts.enumerated().map { index, shortcut in
            let id = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var reference: EventHotKeyRef?
            let result = RegisterEventHotKey(UInt32(kVK_ANSI_D), shortcut.modifiers, id,
                                             GetApplicationEventTarget(), 0, &reference)
            if result == noErr, let reference { hotKeys.append(reference) }
            return Registration(shortcut: shortcut.name, status: result)
        }
    }

    /// Bare Space is captured only during a drawing session. Carbon consumes
    /// the key globally, including repeats after the underlying app gains focus.
    func setInteractionKeyEnabled(_ enabled: Bool) -> OSStatus {
        if enabled {
            unregisterInteractionOnRelease = false
            if interactionKey != nil { return noErr }
            guard handler != nil else { return OSStatus(eventNotHandledErr) }
            let id = EventHotKeyID(signature: Self.signature, id: Self.interactionID)
            return RegisterEventHotKey(UInt32(kVK_Space), 0, id, GetApplicationEventTarget(),
                                       OptionBits(kEventHotKeyExclusive), &interactionKey)
        }
        if isInteractionKeyHeld {
            // Keep swallowing repeats if drawing closes before Space is released.
            unregisterInteractionOnRelease = true
        } else {
            unregisterInteractionKey()
        }
        return noErr
    }

    private func handleInteractionKey(held: Bool) {
        guard interactionKey != nil, held != isInteractionKeyHeld else { return }
        isInteractionKeyHeld = held
        if !held, unregisterInteractionOnRelease { unregisterInteractionKey() }
        onInteractionKeyChange?(held)
    }

    private func unregisterInteractionKey() {
        if let interactionKey { UnregisterEventHotKey(interactionKey) }
        interactionKey = nil
        unregisterInteractionOnRelease = false
        isInteractionKeyHeld = false
    }

    private func unregister() {
        unregisterInteractionKey()
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { unregister() }
}

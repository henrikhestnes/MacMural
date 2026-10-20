import AppKit
import Carbon
import MacMuralCore

final class GlobalHotKey {
    struct Registration {
        let shortcut: String
        let status: OSStatus
    }

    private static let signature: OSType = 0x4D4D524C // MMRL
    private var hotKeys: [KeyboardShortcut: (reference: EventHotKeyRef, id: UInt32)] = [:]
    private var nextID: UInt32 = 1000
    private var configuration = ShortcutConfiguration.defaults
    private static let interactionID: UInt32 = 100
    private var interactionKey: EventHotKeyRef?
    private var unregisterInteractionOnRelease = false
    private(set) var isInteractionKeyHeld = false
    private var handler: EventHandlerRef?
    var onPress: (() -> Void)?
    var onInteractionKeyChange: ((Bool) -> Void)?

    func register(_ configuration: ShortcutConfiguration) -> [Registration] {
        if handler != nil { return replaceShortcuts(configuration) }

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
            } else if isPressed, hotKey.hotKeys.values.contains(where: { $0.id == pressed.id }) {
                hotKey.onPress?()
            }
            return noErr
        }
        let status = events.withUnsafeBufferPointer {
            InstallEventHandler(GetApplicationEventTarget(), callback, 2, $0.baseAddress, context, &handler)
        }
        guard status == noErr else {
            return configuration.toggleShortcuts.map { Registration(shortcut: $0.display, status: status) }
        }
        return replaceShortcuts(configuration, preserveOnFailure: false)
    }

    /// Register new chords before releasing old ones so a conflict cannot remove a working shortcut.
    private func replaceShortcuts(_ proposed: ShortcutConfiguration, preserveOnFailure: Bool = true) -> [Registration] {
        var replacements: [KeyboardShortcut: (reference: EventHotKeyRef, id: UInt32)] = [:]
        var errors: [Registration] = []
        for shortcut in proposed.toggleShortcuts {
            if let existing = hotKeys[shortcut] {
                replacements[shortcut] = existing
                continue
            }
            let id = nextID
            nextID += 1
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.modifiers.carbon,
                                            EventHotKeyID(signature: Self.signature, id: id),
                                            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &reference)
            if status == noErr, let reference { replacements[shortcut] = (reference, id) }
            else { errors.append(Registration(shortcut: shortcut.display, status: status)) }
        }
        if preserveOnFailure && !errors.isEmpty {
            for (shortcut, registration) in replacements where hotKeys[shortcut] == nil {
                UnregisterEventHotKey(registration.reference)
            }
            return errors
        }
        for (shortcut, registration) in hotKeys where replacements[shortcut] == nil {
            UnregisterEventHotKey(registration.reference)
        }
        hotKeys = replacements
        configuration = proposed
        return errors
    }

    func suspendTogglesForRecording(_ suspended: Bool) -> [Registration] {
        if suspended {
            for registration in hotKeys.values { UnregisterEventHotKey(registration.reference) }
            hotKeys.removeAll()
            return []
        }
        if handler == nil { return register(configuration) }
        return replaceShortcuts(configuration, preserveOnFailure: false)
    }

    /// The interaction key is captured only during a drawing session. Carbon consumes
    /// the key globally, including repeats after the underlying app gains focus.
    func setInteractionKeyEnabled(_ enabled: Bool) -> OSStatus {
        if enabled {
            unregisterInteractionOnRelease = false
            if interactionKey != nil { return noErr }
            guard handler != nil else { return OSStatus(eventNotHandledErr) }
            let id = EventHotKeyID(signature: Self.signature, id: Self.interactionID)
            return RegisterEventHotKey(UInt32(configuration[.interact].keyCode), 0, id, GetApplicationEventTarget(),
                                       OptionBits(kEventHotKeyExclusive), &interactionKey)
        }
        if isInteractionKeyHeld {
            // Keep swallowing repeats if drawing closes before the interaction key is released.
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
        for registration in hotKeys.values { UnregisterEventHotKey(registration.reference) }
        hotKeys.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }

    deinit { unregister() }
}

import Foundation

public struct ShortcutModifiers: OptionSet, Codable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    public static let control = Self(rawValue: 1)
    public static let option = Self(rawValue: 2)
    public static let shift = Self(rawValue: 4)
    public static let command = Self(rawValue: 8)
    public static let all: Self = [.control, .option, .shift, .command]
}

public struct KeyboardShortcut: Codable, Hashable {
    public var keyCode: UInt16
    public var modifiers: ShortcutModifiers
    public init(_ keyCode: UInt16, _ modifiers: ShortcutModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // Virtual key codes stay consistent between recording and event dispatch.
    public static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
        64: "F17", 79: "F18", 80: "F19", 90: "F20", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12", 115: "Home", 116: "Page Up",
        117: "Forward Delete", 118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
    public var keyName: String { Self.keyNames[keyCode] ?? "Unknown" }
    public var display: String {
        (modifiers.contains(.control) ? "⌃" : "") +
        (modifiers.contains(.option) ? "⌥" : "") +
        (modifiers.contains(.shift) ? "⇧" : "") +
        (modifiers.contains(.command) ? "⌘" : "") + keyName
    }
    public static let escape = Self(53)
    public static let hyperD = Self(2, [.control, .option, .command])
    public static let hyperShiftD = Self(2, [.control, .option, .command, .shift])
}

public enum ShortcutAction: String, Codable, CaseIterable {
    case toggle, arrow, rectangle, laser, pen, eraser, clear, undo, redo, thin, medium, thick, finish, interact

    public var title: String {
        switch self {
        case .toggle: return "Start / finish drawing"
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .laser: return "Laser"
        case .pen: return "Freehand pen"
        case .eraser: return "Eraser"
        case .clear: return "Clear drawings"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .thin: return "Thin line / small eraser"
        case .medium: return "Medium line / eraser"
        case .thick: return "Thick line / large eraser"
        case .finish: return "Finish drawing"
        case .interact: return "Hold to interact underneath"
        }
    }
    public static func tool(_ tool: DrawingTool) -> Self {
        switch tool {
        case .arrow: return .arrow
        case .rectangle: return .rectangle
        case .laser: return .laser
        case .pen: return .pen
        case .eraser: return .eraser
        }
    }
}

public struct ShortcutConfiguration: Codable, Equatable {
    public var bindings: [ShortcutAction: KeyboardShortcut]
    public var hyperEnabled: Bool
    public init(bindings: [ShortcutAction: KeyboardShortcut], hyperEnabled: Bool = true) {
        self.bindings = bindings
        self.hyperEnabled = hyperEnabled
    }
    public static let defaults = Self(bindings: [
        .toggle: KeyboardShortcut(2, [.control, .shift]), .arrow: KeyboardShortcut(0),
        .rectangle: KeyboardShortcut(15), .laser: KeyboardShortcut(37), .pen: KeyboardShortcut(2),
        .eraser: KeyboardShortcut(14), .clear: KeyboardShortcut(8), .undo: KeyboardShortcut(6, .command),
        .redo: KeyboardShortcut(6, [.command, .shift]), .thin: KeyboardShortcut(18),
        .medium: KeyboardShortcut(19), .thick: KeyboardShortcut(20), .finish: .escape,
        .interact: KeyboardShortcut(49)
    ])
    public subscript(_ action: ShortcutAction) -> KeyboardShortcut {
        get { bindings[action] ?? Self.defaults.bindings[action]! }
        set { bindings[action] = newValue }
    }
    public var toggleShortcuts: [KeyboardShortcut] {
        var shortcuts = [self[.toggle]]
        if hyperEnabled {
            for shortcut in [KeyboardShortcut.hyperD, .hyperShiftD] where !shortcuts.contains(shortcut) {
                shortcuts.append(shortcut)
            }
        }
        return shortcuts
    }
    public func action(for shortcut: KeyboardShortcut) -> ShortcutAction? {
        ShortcutAction.allCases.first { $0 != .toggle && $0 != .interact && self[$0] == shortcut }
    }
    public func conflicts(with reserved: Set<KeyboardShortcut>) -> [KeyboardShortcut] {
        var result: [KeyboardShortcut] = []
        for shortcut in toggleShortcuts + ShortcutAction.allCases.map({ self[$0] }) {
            if reserved.contains(shortcut), !result.contains(shortcut) { result.append(shortcut) }
        }
        return result
    }
    public var validationError: String? {
        var used: [KeyboardShortcut: ShortcutAction] = [:]
        for action in ShortcutAction.allCases {
            let shortcut = self[action]
            guard KeyboardShortcut.keyNames[shortcut.keyCode] != nil,
                  shortcut.modifiers.subtracting(.all).isEmpty else {
                return "Choose a supported key for \(action.title)."
            }
            if shortcut == KeyboardShortcut(12, .command) {
                return "⌘Q is reserved for quitting MacMural."
            }
            if shortcut == .escape && action != .finish {
                return "Esc is always available to finish drawing."
            }
            if action == .toggle && shortcut.modifiers.intersection([.control, .command]).isEmpty {
                return "The global drawing shortcut must include Control or Command."
            }
            if action == .interact && !shortcut.modifiers.isEmpty {
                return "Use a single key without modifiers for hold-to-interact."
            }
            if let other = used[shortcut] {
                return "\(shortcut.display) is assigned to both \(other.title) and \(action.title)."
            }
            if hyperEnabled && action != .toggle && [KeyboardShortcut.hyperD, .hyperShiftD].contains(shortcut) {
                return "\(shortcut.display) is already used by Hyper+D."
            }
            used[shortcut] = action
        }
        return nil
    }
    private static let defaultsKey = "shortcuts.v1"
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: defaultsKey),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.validationError == nil else { return .defaults }
        return value
    }
    public func save(to defaults: UserDefaults = .standard) {
        guard validationError == nil, let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

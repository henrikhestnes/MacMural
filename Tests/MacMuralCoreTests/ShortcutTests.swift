import XCTest
@testable import MacMuralCore

final class ShortcutTests: XCTestCase {
    func testDefaultsRetainToolsAndAvoidDockToggle() {
        let config = ShortcutConfiguration.defaults
        XCTAssertNil(config.validationError)
        XCTAssertEqual(config[.toggle], KeyboardShortcut(2, [.control, .shift]))
        XCTAssertFalse(config.toggleShortcuts.contains(KeyboardShortcut(2, [.option, .command])))
        XCTAssertEqual(config.action(for: KeyboardShortcut(0)), .arrow)
        XCTAssertEqual(config.action(for: KeyboardShortcut(6, [.command, .shift])), .redo)
    }

    func testRebindingChangesDispatchAndRemovesPreviousKey() {
        var config = ShortcutConfiguration.defaults
        config[.arrow] = KeyboardShortcut(35, .option)
        XCTAssertNil(config.validationError)
        XCTAssertEqual(config.action(for: KeyboardShortcut(35, .option)), .arrow)
        XCTAssertNil(config.action(for: KeyboardShortcut(0)))
        XCTAssertNil(config.action(for: KeyboardShortcut(35)))
        XCTAssertNil(config.action(for: config[.toggle]))
        XCTAssertNil(config.action(for: config[.interact]))
    }

    func testDuplicateBindingsIncludeGlobalAndHoldKeys() {
        for action in [ShortcutAction.toggle, .interact, .clear] {
            var config = ShortcutConfiguration.defaults
            config[.arrow] = config[action]
            XCTAssertNotNil(config.validationError)
        }
    }

    func testGlobalShortcutRequiresControlOrCommand() {
        for modifiers: ShortcutModifiers in [[], .shift, .option, [.option, .shift]] {
            var config = ShortcutConfiguration.defaults
            config[.toggle] = KeyboardShortcut(35, modifiers)
            XCTAssertNotNil(config.validationError)
        }
    }

    func testInteractionKeyMustBeUnmodifiedAndCannotTakeEscape() {
        var config = ShortcutConfiguration.defaults
        config[.interact] = KeyboardShortcut(48)
        XCTAssertNil(config.validationError)
        config[.interact] = KeyboardShortcut(48, .control)
        XCTAssertNotNil(config.validationError)
        config[.interact] = .escape
        XCTAssertNotNil(config.validationError)
    }

    func testQuitAndEscapeRemainReserved() {
        var config = ShortcutConfiguration.defaults
        config[.finish] = KeyboardShortcut(3)
        XCTAssertNil(config.validationError)
        config[.arrow] = .escape
        XCTAssertNotNil(config.validationError)
        config[.arrow] = KeyboardShortcut(12, .command)
        XCTAssertNotNil(config.validationError)
    }

    func testHyperAliasesCanBeDisabledAndAreNotRegisteredTwice() {
        var config = ShortcutConfiguration.defaults
        XCTAssertEqual(config.toggleShortcuts.count, 3)
        config[.toggle] = .hyperD
        XCTAssertNil(config.validationError)
        XCTAssertEqual(config.toggleShortcuts.count, 2)
        config.hyperEnabled = false
        XCTAssertEqual(config.toggleShortcuts, [.hyperD])
        config[.toggle] = ShortcutConfiguration.defaults[.toggle]
        config[.arrow] = .hyperD
        XCTAssertNil(config.validationError)
        config.hyperEnabled = true
        XCTAssertNotNil(config.validationError)
    }

    func testSystemConflictsIncludeAliasesAndDeduplicate() {
        var config = ShortcutConfiguration.defaults
        let dock = KeyboardShortcut(2, [.option, .command])
        let reserved: Set<KeyboardShortcut> = [dock, .hyperD]
        XCTAssertEqual(config.conflicts(with: reserved), [.hyperD])
        config.hyperEnabled = false
        XCTAssertTrue(config.conflicts(with: reserved).isEmpty)
        config[.toggle] = dock
        XCTAssertEqual(config.conflicts(with: reserved), [dock])
    }

    func testUnsupportedKeysAndModifierBitsAreRejected() {
        var config = ShortcutConfiguration.defaults
        config[.arrow] = KeyboardShortcut(65535)
        XCTAssertNotNil(config.validationError)
        config[.arrow] = KeyboardShortcut(0, ShortcutModifiers(rawValue: 128))
        XCTAssertNotNil(config.validationError)
    }

    func testPreferencesRoundTripAndRejectCorruptOrInvalidData() throws {
        let name = "MacMural.shortcuts.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        XCTAssertEqual(ShortcutConfiguration.load(from: defaults), .defaults)
        var config = ShortcutConfiguration.defaults
        config[.arrow] = KeyboardShortcut(35)
        config[.interact] = KeyboardShortcut(48)
        config.hyperEnabled = false
        config.save(to: defaults)
        XCTAssertEqual(ShortcutConfiguration.load(from: defaults), config)
        config[.clear] = config[.arrow]
        config.save(to: defaults) // Invalid saves must preserve the last valid configuration.
        XCTAssertNotEqual(ShortcutConfiguration.load(from: defaults), config)
        defaults.set(try JSONEncoder().encode(config), forKey: "shortcuts.v1")
        XCTAssertEqual(ShortcutConfiguration.load(from: defaults), .defaults)
        defaults.set(Data("broken".utf8), forKey: "shortcuts.v1")
        XCTAssertEqual(ShortcutConfiguration.load(from: defaults), .defaults)
    }

    func testMissingBindingsFallBackToDefaults() throws {
        let partial = ShortcutConfiguration(bindings: [.toggle: KeyboardShortcut(35, .command)])
        let restored = try JSONDecoder().decode(ShortcutConfiguration.self, from: JSONEncoder().encode(partial))
        XCTAssertNil(restored.validationError)
        XCTAssertEqual(restored[.undo], ShortcutConfiguration.defaults[.undo])
        XCTAssertEqual(restored[.toggle], partial[.toggle])
    }
}

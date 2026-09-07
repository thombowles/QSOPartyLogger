import XCTest
@testable import QSOPartyLogger

/// Shortcut hints (⌘/): the preference, the key that toggles it, and the
/// legend of keys that have no button to wear a badge.
@MainActor
final class ShortcutHintsTests: XCTestCase {
    nonisolated(unsafe) private var suiteName: String!
    nonisolated(unsafe) private var scratch: UserDefaults!

    override func setUp() {
        suiteName = "ShortcutHintsTests-\(UUID().uuidString)"
        scratch = UserDefaults(suiteName: suiteName)
        scratch.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() { scratch.removePersistentDomain(forName: suiteName) }

    // MARK: The preference

    /// Off by default: a contest window is busy enough, and hints are for
    /// learning the keys, not for keeping.
    func testHintsAreOffByDefault() {
        XCTAssertFalse(AppSettings(defaults: scratch).showShortcutHints)
    }

    func testHintsPersist() {
        AppSettings(defaults: scratch).showShortcutHints = true
        XCTAssertTrue(AppSettings(defaults: scratch).showShortcutHints)
    }

    // MARK: The key

    /// ⌘/ toggles — through the gate like every other document key, so it is
    /// consumed from the document and left to the menu bar from a sheet.
    func testCommandSlashTogglesHints() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 44, command: true), .toggleShortcutHints)
        XCTAssertNil(KeyMonitorGate.action(keyCode: 44, command: false), "a plain / is part of a callsign")
        XCTAssertNil(KeyMonitorGate.action(keyCode: 44, command: false, shift: true), "? is typeable too")
    }

    func testCommandSlashIsConsumedFromTheDocumentOnly() {
        let fromDocument = KeyMonitorGate.response(
            keyCode: 44, command: true, focus: .document, repeatRunning: false)
        XCTAssertEqual(fromDocument.action, .toggleShortcutHints)
        XCTAssertTrue(fromDocument.consumesEvent)
        let fromSheet = KeyMonitorGate.response(
            keyCode: 44, command: true, focus: .sheet, repeatRunning: false)
        XCTAssertNil(fromSheet.action)
        XCTAssertFalse(fromSheet.consumesEvent, "the Help menu's own ⌘/ handles it there")
    }

    // MARK: The legend

    /// Keys with no button of their own are listed once, in the order the
    /// operating loop uses them, and the legend says how to hide itself.
    func testLegendNamesEveryButtonlessKey() {
        let text = ShortcutLegend.line
        for expected in ["F12", "Esc", "⌘↑", "⌘↓", "⌘J", "⌘=", "⌘-", "⇧⌘←", "⇧⌘→", "⇧⌘B", "⇧⌘L", "⌘A", "⌘/"] {
            XCTAssertTrue(text.contains(expected), "legend lacks \(expected): \(text)")
        }
    }

    func testLegendKeysAreUnique() {
        let keys = ShortcutLegend.items.map(\.keys)
        XCTAssertEqual(keys.count, Set(keys).count, "a key listed twice reads as two actions")
    }

    /// The last-key line: says what to do before a key has been pressed, and
    /// shows the readout after.
    func testLastKeyLine() {
        XCTAssertEqual(ShortcutLegend.lastKeyLine(nil), "Last key: — (press one)")
        XCTAssertEqual(ShortcutLegend.lastKeyLine("F1 — message F1"), "Last key: F1 — message F1")
    }

    func testDescribeNamesTheToggle() {
        XCTAssertEqual(KeyDiagnostics.describe(.toggleShortcutHints), "shortcut hints")
    }

    /// ⇧⌘B's control lives inside the map's popover, so the legend is where
    /// the key is found; the readout says what it did.
    func testDescribeNamesTheBandMapBolt() {
        XCTAssertEqual(KeyDiagnostics.describe(.toggleBandMapBolt), "band map bolt")
    }
}

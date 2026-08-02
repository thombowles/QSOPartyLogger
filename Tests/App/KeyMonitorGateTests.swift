import XCTest
@testable import QSOPartyLogger

/// `MainView` installs an app-wide `NSEvent` local key monitor. The event
/// plumbing cannot be driven from a unit test — an `NSEvent` built here and
/// dispatched by hand never traverses a local monitor — so these cover the two
/// pure decisions the monitor delegates to `KeyMonitorGate`.
final class KeyMonitorGateTests: XCTestCase {

    private let host = 100
    private let ourSheet = 101
    private let ourBandMap = 102
    private let otherDoc = 200
    private let otherSheet = 201

    // MARK: Focus — whose keystroke is it

    func testOurWindowWithNoSheetOwnsTheKeyboard() {
        XCTAssertEqual(
            KeyMonitorGate.focus(.init(host: host, key: host)),
            .document
        )
    }

    /// Regression: Esc was swallowed while a sheet was up, so the sheet's
    /// Cancel never saw it and the sheet stayed open.
    func testSheetOnOurWindowOwnsTheKeyboard() {
        XCTAssertEqual(
            KeyMonitorGate.focus(
                .init(
                    host: host,
                    key: ourSheet,
                    keySheetParent: host,
                    hostHasAttachedSheet: true
                )
            ),
            .sheet
        )
    }

    /// Regression: with two logs open, the last-installed monitor consumed the
    /// key no matter which window the operator was typing in.
    func testAnotherDocumentsWindowIsNotOurs() {
        XCTAssertEqual(
            KeyMonitorGate.focus(.init(host: host, key: otherDoc)),
            .elsewhere
        )
    }

    func testAnotherDocumentsSheetIsNotOurs() {
        XCTAssertEqual(
            KeyMonitorGate.focus(
                .init(host: host, key: otherSheet, keySheetParent: otherDoc)
            ),
            .elsewhere
        )
    }

    /// The band map is this document's own panel — clicking a spot must not
    /// disable the F-keys.
    func testOurBandMapPanelStillCountsAsOurs() {
        XCTAssertEqual(
            KeyMonitorGate.focus(.init(host: host, key: ourBandMap, bandMap: ourBandMap)),
            .document
        )
    }

    /// The band map is `becomesKeyOnlyIfNeeded`, so it can hold focus with a
    /// sheet up behind it. The sheet still wins.
    func testBandMapFocusDoesNotDefeatAnOpenSheet() {
        XCTAssertEqual(
            KeyMonitorGate.focus(
                .init(
                    host: host,
                    key: ourBandMap,
                    bandMap: ourBandMap,
                    hostHasAttachedSheet: true
                )
            ),
            .sheet
        )
    }

    func testHostWindowWithAnAttachedSheetNeverCountsAsPlainDocumentFocus() {
        XCTAssertEqual(
            KeyMonitorGate.focus(.init(host: host, key: host, hostHasAttachedSheet: true)),
            .sheet
        )
    }

    func testNoHostWindowYetIsNotOurs() {
        XCTAssertEqual(KeyMonitorGate.focus(.init(host: nil, key: host)), .elsewhere)
    }

    func testNoKeyWindowIsNotOurs() {
        XCTAssertEqual(KeyMonitorGate.focus(.init(host: host, key: nil)), .elsewhere)
    }

    // MARK: Action — the key table

    func testFunctionKeysOneThroughEightMapToMessageIndices() {
        let codes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100]
        for (index, code) in codes.enumerated() {
            XCTAssertEqual(
                KeyMonitorGate.action(keyCode: code, command: false),
                .sendMessage(index: index),
                "F\(index + 1) (keyCode \(code))"
            )
        }
    }

    func testF12ClearsTheEntry() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 111, command: false), .clearEntry)
    }

    func testEscapeAbortsCW() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 53, command: false), .abortCW)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 53, command: true), .abortCW)
    }

    func testCommandChords() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 24, command: true), .adjustWPM(by: 2))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 69, command: true), .adjustWPM(by: 2))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 27, command: true), .adjustWPM(by: -2))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 78, command: true), .adjustWPM(by: -2))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 38, command: true), .jumpToCQFrequency)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 11, command: true), .toggleBandMap)
    }

    /// Those same keys unmodified are ordinary typing and must reach the entry
    /// field: '=' and '-' are characters, 'j' and 'b' are letters in a callsign.
    func testCommandChordKeysAreInertWithoutCommand() {
        for code: UInt16 in [24, 69, 27, 78, 38, 11] {
            XCTAssertNil(
                KeyMonitorGate.action(keyCode: code, command: false),
                "keyCode \(code) must pass through without ⌘"
            )
        }
    }

    /// Long-standing behaviour worth pinning: a ⌘ chord with no command mapping
    /// falls through to the plain key table.
    func testCommandFunctionKeyStillSendsItsMessage() {
        XCTAssertEqual(
            KeyMonitorGate.action(keyCode: 120, command: true),
            .sendMessage(index: 1)
        )
    }

    func testOrdinaryTypingIsNotOurs() {
        for code: UInt16 in [0, 1, 2, 36, 48, 49] {  // a, s, d, return, tab, space
            XCTAssertNil(KeyMonitorGate.action(keyCode: code, command: false), "keyCode \(code)")
        }
    }

    // MARK: Vertical spot stepping

    /// The band map draws high frequency at the top, so ⌘↑ means "up the map",
    /// which is the higher frequency.
    func testCommandUpAndDownStepSpots() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 126, command: true), .nextSpot)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 125, command: true), .previousSpot)
    }

    /// Stepping spots is the vertical axis only. ⌘← / ⌘→ are macOS's own
    /// beginning/end-of-line keys, and the entry field gets to keep them.
    func testCommandLeftAndRightDoNotStepSpots() {
        XCTAssertNil(
            KeyMonitorGate.action(keyCode: 123, command: true),
            "⌘← belongs to the text field, not the band map"
        )
        XCTAssertNil(
            KeyMonitorGate.action(keyCode: 124, command: true),
            "⌘→ belongs to the text field, not the band map"
        )
        XCTAssertNil(KeyMonitorGate.action(keyCode: 123, command: true, shift: true))
        XCTAssertNil(KeyMonitorGate.action(keyCode: 124, command: true, shift: true))
    }

    /// Without ⌘ the arrows belong to whatever has focus — a text field, the
    /// log table — and the monitor must not consume them.
    func testPlainArrowsAreNotOurs() {
        XCTAssertNil(KeyMonitorGate.action(keyCode: 126, command: false))
        XCTAssertNil(KeyMonitorGate.action(keyCode: 125, command: false))
    }

    // MARK: Export shortcuts (2026-07-28)

    /// ⌘E and ⇧⌘E moved into the gate when the toolbar buttons became one
    /// Export menu — SwiftUI shortcuts on toolbar-menu items are not a
    /// dependable path, and the gate already enforces the sheet and
    /// which-window rules the exports should obey anyway.
    func testCommandEExportsADIF() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 14, command: true), .exportADIF)
    }

    func testShiftedCommandEExportsCabrillo() {
        XCTAssertEqual(
            KeyMonitorGate.action(keyCode: 14, command: true, shift: true),
            .exportCabrillo
        )
    }

    /// A bare or shifted 'e' is the operator typing a callsign.
    func testPlainEStaysTypeable() {
        XCTAssertNil(KeyMonitorGate.action(keyCode: 14, command: false))
        XCTAssertNil(KeyMonitorGate.action(keyCode: 14, command: false, shift: true))
    }

    /// ⇧ must only ever distinguish the E chord: ⌘⇧= is how a '+' actually
    /// arrives on the keyboard, and it has always meant WPM up.
    func testShiftDoesNotDisturbOtherCommandChords() {
        XCTAssertEqual(
            KeyMonitorGate.action(keyCode: 24, command: true, shift: true),
            .adjustWPM(by: 2)
        )
    }
}

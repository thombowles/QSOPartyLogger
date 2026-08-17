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

    func testEscapeAbortsTransmission() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 53, command: false), .abortTransmission)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 53, command: true), .abortTransmission)
    }

    /// ⌘= / ⌘- (and the keypad pair) step the speed by one WPM; with ⇧ as
    /// well, by two — asked for by name on 2026-08-16 ("Cmd + shift +/- to
    /// change cw speed by 2 wpm, Cmd +/- to change by 1 wpm"). Until then the
    /// unshifted chord stepped by two.
    func testCommandChords() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 24, command: true), .adjustWPM(by: 1))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 69, command: true), .adjustWPM(by: 1))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 27, command: true), .adjustWPM(by: -1))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 78, command: true), .adjustWPM(by: -1))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 38, command: true), .jumpToCQFrequency)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 11, command: true), .toggleBandMap)
    }

    /// ⇧⌘= is how a '+' actually arrives on the keyboard, and ⇧⌘- is '_':
    /// the shifted pair is the coarse step, on the keypad too.
    func testShiftedWPMChordsStepByTwo() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 24, command: true, shift: true), .adjustWPM(by: 2))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 69, command: true, shift: true), .adjustWPM(by: 2))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 27, command: true, shift: true), .adjustWPM(by: -2))
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 78, command: true, shift: true), .adjustWPM(by: -2))
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
    }

    // MARK: VFO nudge (2026-08-15)

    /// ⇧⌘← / ⇧⌘→ move the VFO 100 Hz — asked for by name. The shifted pair
    /// was "select to line start/end" in the entry fields, which a callsign
    /// never needs; the plain ⌘ arrows stay with the field.
    func testShiftedCommandArrowsNudgeTheVFO() {
        XCTAssertEqual(
            KeyMonitorGate.action(keyCode: 123, command: true, shift: true),
            .nudgeVFO(byHz: -100)
        )
        XCTAssertEqual(
            KeyMonitorGate.action(keyCode: 124, command: true, shift: true),
            .nudgeVFO(byHz: 100)
        )
    }

    /// ⇧← alone extends a text selection — the field's, not ours.
    func testShiftedArrowsWithoutCommandStayWithTheField() {
        XCTAssertNil(KeyMonitorGate.action(keyCode: 123, command: false, shift: true))
        XCTAssertNil(KeyMonitorGate.action(keyCode: 124, command: false, shift: true))
    }

    /// The nudge is a document key like the rest: refused from a sheet,
    /// consumed from the document.
    func testNudgeIsConsumedFromTheDocumentAndRefusedFromASheet() {
        let fromDocument = KeyMonitorGate.response(
            keyCode: 124, command: true, shift: true, focus: .document, repeatRunning: false)
        XCTAssertEqual(fromDocument.action, .nudgeVFO(byHz: 100))
        XCTAssertTrue(fromDocument.consumesEvent)
        let fromSheet = KeyMonitorGate.response(
            keyCode: 124, command: true, shift: true, focus: .sheet, repeatRunning: false)
        XCTAssertNil(fromSheet.action)
        XCTAssertFalse(fromSheet.consumesEvent)
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

    /// ⇧ distinguishes only the E chord and the WPM step: the rest of the
    /// command table ignores it.
    func testShiftDoesNotDisturbOtherCommandChords() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 38, command: true, shift: true), .jumpToCQFrequency)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 11, command: true, shift: true), .toggleBandMap)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 126, command: true, shift: true), .nextSpot)
    }

    // MARK: Response — the whole decision for one key down

    private let letterA: UInt16 = 0
    private let f1: UInt16 = 122
    private let f2: UInt16 = 120
    private let escape: UInt16 = 53

    private func response(
        _ keyCode: UInt16,
        command: Bool = false,
        shift: Bool = false,
        focus: KeyMonitorGate.Focus = .document,
        repeatRunning: Bool = false
    ) -> KeyMonitorGate.Response {
        KeyMonitorGate.response(
            keyCode: keyCode,
            command: command,
            shift: shift,
            focus: focus,
            repeatRunning: repeatRunning
        )
    }

    /// The point of the whole feature: a repeating CQ is answered, you start
    /// typing the call, and the CQ stops *mid-character* rather than talking
    /// over him. The letter is not consumed — it still lands in the field.
    func testAnyKeyDuringARepeatingCQHaltsTheMessageOnAir() {
        XCTAssertEqual(
            response(letterA, repeatRunning: true),
            .init(stopsRepeat: true, abortsTransmission: true, action: nil, consumesEvent: false)
        )
    }

    /// A key that has a job still does it — after the abort, so F2 replaces the
    /// CQ on air instead of queueing behind it.
    func testAFunctionKeyDuringARepeatingCQAbortsThenSendsItsOwnMessage() {
        XCTAssertEqual(
            response(f2, repeatRunning: true),
            .init(
                stopsRepeat: true,
                abortsTransmission: true,
                action: .sendMessage(index: 1),
                consumesEvent: true
            )
        )
    }

    /// F1 during a repeating CQ is "start that CQ over", not "stack a second
    /// one behind the first".
    func testF1DuringARepeatingCQRestartsTheCQFromTheTop() {
        XCTAssertEqual(
            response(f1, repeatRunning: true),
            .init(
                stopsRepeat: true,
                abortsTransmission: true,
                action: .sendMessage(index: 0),
                consumesEvent: true
            )
        )
    }

    /// The guard rail on the feature. With no repeat running, typing the next
    /// call while your F2 exchange goes out must not cut the exchange off.
    func testTypingDoesNotAbortTransmissionWhenNoRepeatIsRunning() {
        XCTAssertEqual(response(letterA), .init())
    }

    /// Esc has always aborted on its own, repeat or no repeat, and is consumed
    /// so it never also does something to the focused control.
    func testEscapeAbortsWithNoRepeatRunning() {
        XCTAssertEqual(
            response(escape),
            .init(stopsRepeat: false, abortsTransmission: true, action: nil, consumesEvent: true)
        )
    }

    /// Regression (Article 11): Esc aborts wherever it is pressed, but a sheet
    /// keystroke is never consumed — otherwise Cancel never sees it.
    func testEscapeOnOneOfOurSheetsAbortsButIsNeverConsumed() {
        XCTAssertEqual(
            response(escape, focus: .sheet),
            .init(stopsRepeat: false, abortsTransmission: true, action: nil, consumesEvent: false)
        )
    }

    /// Opening a sheet does not license the repeat to keep calling CQ.
    func testASheetKeystrokeStillStopsARunningRepeat() {
        XCTAssertEqual(
            response(letterA, focus: .sheet, repeatRunning: true),
            .init(stopsRepeat: true, abortsTransmission: true, action: nil, consumesEvent: false)
        )
    }

    /// Regression: revising F2 in the Messages editor and pressing it must not
    /// key the saved macro.
    func testFunctionKeysNeverTransmitFromASheet() {
        XCTAssertEqual(response(f2, focus: .sheet), .init())
    }

    /// Regression: with two logs open, typing in the other one used to stop
    /// this one's CQ. It must not abort this one's CW either.
    func testAKeystrokeInAnotherWindowLeavesOurRepeatAlone() {
        XCTAssertEqual(response(letterA, focus: .elsewhere, repeatRunning: true), .init())
    }

    /// Even Esc, which aborts everywhere else, belongs to the window it was
    /// pressed in.
    func testEscapeInAnotherWindowIsNotOurs() {
        XCTAssertEqual(response(escape, focus: .elsewhere, repeatRunning: true), .init())
    }
}

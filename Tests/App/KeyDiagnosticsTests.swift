import XCTest
@testable import QSOPartyLogger

/// The pure half of the key trace: what a keystroke is called, how a media
/// key is decoded, and the one notice the messages row shows when the F row
/// arrives as brightness or Mission Control instead of F1–F12.
final class KeyDiagnosticsTests: XCTestCase {

    // MARK: Names

    func testFunctionKeysAreNamedByPosition() {
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 122), "F1")
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 100), "F8")
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 111), "F12")
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 53), "Esc")
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 123), "←")
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 44), "/")
    }

    func testUnknownKeyCodesAreStillNamed() {
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 999), "key 999")
    }

    /// The system's own function-row keys — Mission Control, Launchpad — reach
    /// an app as key downs with their own codes, never as F3/F4.
    func testSystemFunctionRowKeysAreNamedForWhatTheyAre() {
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 160), "Mission Control")
        XCTAssertEqual(KeyDiagnostics.keyName(keyCode: 131), "Launchpad")
    }

    func testChordsReadLikeTheMenuBar() {
        XCTAssertEqual(KeyDiagnostics.chordName(keyCode: 122, command: false, shift: false), "F1")
        XCTAssertEqual(KeyDiagnostics.chordName(keyCode: 11, command: true, shift: false), "⌘B")
        XCTAssertEqual(KeyDiagnostics.chordName(keyCode: 14, command: true, shift: true), "⇧⌘E")
        XCTAssertEqual(KeyDiagnostics.chordName(keyCode: 123, command: true, shift: true), "⇧⌘←")
    }

    // MARK: Media keys (NSEvent.systemDefined, subtype 8)

    /// `data1` packs the aux key type in the high 16 bits and the key state
    /// (0xA down, 0xB up) in bits 8–15 — IOKit's ev_keymap.h layout.
    private func data1(type: Int, down: Bool) -> Int {
        (type << 16) | ((down ? 0xA : 0xB) << 8)
    }

    func testBrightnessDownDecodesAsAKeyDown() {
        let key = KeyDiagnostics.mediaKey(subtype: 8, data1: data1(type: 3, down: true))
        XCTAssertEqual(key, .init(kind: .brightnessDown, isDown: true))
    }

    func testKeyUpIsDecodedButMarkedUp() {
        let key = KeyDiagnostics.mediaKey(subtype: 8, data1: data1(type: 16, down: false))
        XCTAssertEqual(key, .init(kind: .play, isDown: false))
    }

    func testOtherSystemDefinedSubtypesAreNotMediaKeys() {
        XCTAssertNil(KeyDiagnostics.mediaKey(subtype: 7, data1: data1(type: 3, down: true)))
    }

    func testUnknownAuxTypesStillDecode() {
        let key = KeyDiagnostics.mediaKey(subtype: 8, data1: data1(type: 42, down: true))
        XCTAssertEqual(key?.kind, .other(42))
        XCTAssertEqual(key?.name, "media key 42")
    }

    func testMediaKeyNamesSayWhereTheyLiveOnTheFRow() {
        XCTAssertEqual(KeyDiagnostics.MediaKey.Kind.brightnessDown.name, "Brightness ▼")
        XCTAssertEqual(KeyDiagnostics.MediaKey.Kind.brightnessDown.fRowPosition, "F1")
        XCTAssertEqual(KeyDiagnostics.MediaKey.Kind.brightnessUp.fRowPosition, "F2")
        XCTAssertEqual(KeyDiagnostics.MediaKey.Kind.illuminationDown.fRowPosition, "F5")
        XCTAssertEqual(KeyDiagnostics.MediaKey.Kind.play.fRowPosition, "F8")
        XCTAssertNil(KeyDiagnostics.MediaKey.Kind.other(42).fRowPosition)
    }

    // MARK: The F-row notice

    /// The whole point: a brightness key where an F-key was expected is
    /// named, placed, and comes with the fix for both kinds of keyboard.
    func testAMediaKeyOnTheFRowExplainsItself() {
        let notice = KeyDiagnostics.fRowNotice(for: .init(kind: .brightnessDown, isDown: true))
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice!.contains("Brightness ▼"), notice!)
        XCTAssertTrue(notice!.contains("F1"), notice!)
        XCTAssertTrue(notice!.contains("multimedia"), notice!)
        XCTAssertTrue(notice!.contains("fn"), notice!)
        XCTAssertTrue(notice!.contains("System Settings"), notice!)
    }

    func testAMediaKeyOffTheFRowGetsNoNotice() {
        XCTAssertNil(KeyDiagnostics.fRowNotice(for: .init(kind: .other(42), isDown: true)))
        XCTAssertNil(KeyDiagnostics.fRowNotice(for: .init(kind: .soundUp, isDown: true)),
                     "volume keys are F10–F12 territory, which the app never uses")
    }

    func testAKeyUpNeverRaisesTheNotice() {
        XCTAssertNil(KeyDiagnostics.fRowNotice(for: .init(kind: .brightnessDown, isDown: false)))
    }

    func testMissionControlAndLaunchpadKeyDownsExplainThemselvesToo() {
        let notice = KeyDiagnostics.fRowNotice(forKeyCode: 160)
        XCTAssertNotNil(notice)
        XCTAssertTrue(notice!.contains("Mission Control"), notice!)
        XCTAssertTrue(notice!.contains("F3"), notice!)
        XCTAssertNil(KeyDiagnostics.fRowNotice(forKeyCode: 122), "a real F1 is not a symptom")
        XCTAssertNil(KeyDiagnostics.fRowNotice(forKeyCode: 0), "nor is a letter")
    }

    // MARK: Trace lines

    func testTraceLineNamesEveryDecision() {
        let line = KeyDiagnostics.traceLine(
            keyCode: 122, command: false, shift: false, focus: .document,
            response: .init(stopsRepeat: false, abortsTransmission: false,
                            action: .sendMessage(index: 0), consumesEvent: true)
        )
        XCTAssertEqual(line, "F1 (122) focus=document → sendMessage(index: 0) consumed")
    }

    func testTraceLineForAKeyThatIsNotOurs() {
        let line = KeyDiagnostics.traceLine(
            keyCode: 0, command: false, shift: false, focus: .document,
            response: .init()
        )
        XCTAssertEqual(line, "A (0) focus=document → — passed on")
    }

    /// What the legend shows after a keystroke: the key, and what it did.
    func testLastKeyReadout() {
        XCTAssertEqual(
            KeyDiagnostics.lastKeyReadout(keyCode: 122, command: false, shift: false, action: .sendMessage(index: 0)),
            "F1 — message F1")
        XCTAssertEqual(
            KeyDiagnostics.lastKeyReadout(keyCode: 11, command: true, shift: false, action: .toggleBandMap),
            "⌘B — band map")
        XCTAssertEqual(
            KeyDiagnostics.lastKeyReadout(keyCode: 0, command: false, shift: false, action: nil),
            "A — not a shortcut")
    }
}

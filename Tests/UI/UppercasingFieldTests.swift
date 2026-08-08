import AppKit
import SwiftUI
import XCTest
@testable import QSOPartyLogger

/// The one thing about an entry field that no pure function can pin: what
/// AppKit's own field editor holds while the operator is typing into it.
///
/// The bug, reported 2026-08-08: type the tail of a call, click to the front to
/// type the prefix, and the first character lands correctly — then the caret
/// jumps to the end and the rest of the prefix is appended. `KE5CW` typed
/// tail-first came out `K5CWE`. The cause was the field editor holding `k5cw`
/// while the model held `K5CW`: two texts that disagree, and the next redraw
/// resolves the disagreement by replacing the editor's text, which drops the
/// insertion point at the end.
///
/// **What this suite pins is the disagreement, not the jump.** Every assertion
/// on `editor.string` below fails the moment folding goes back to being a
/// property of the value alone — that is the whole cause, and it is catchable
/// here. The jump itself is not: a test host is never the active application,
/// and inside one SwiftUI never performs the push at all — the broken code was
/// run against these tests and the caret assertions passed while every
/// `editor.string` assertion failed. They are kept because they are true and
/// cost nothing, not because they are the guard.
///
/// The jump was reproduced and the fix confirmed red-to-green outside XCTest,
/// in a standalone SwiftUI app driven by synthesized key events: unfixed,
/// `K5CWE` with the caret at 4; fixed, `KE5CW` with the caret at 1. See the
/// commit that introduced this file.
@MainActor
final class UppercasingFieldCaretTests: XCTestCase {

    private var window: NSWindow?

    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        super.tearDown()
    }

    /// A callsign copied tail-first, the way a call arrives on a weak signal:
    /// the suffix lands, then the operator clicks to the head for the prefix.
    func testTypingAtTheHeadOfACallLeavesTheCaretThere() throws {
        let entry = EntryState()
        let editor = try openCallField(entry: entry)

        for character in "5cw" { press(character) }
        settle()
        XCTAssertEqual(entry.call, "5CW", "the fold itself still works")
        XCTAssertEqual(editor.string, "5CW", "and the field shows what will be logged")

        // The operator clicks to the front of the call.
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        settle()

        press("k")
        settle()
        XCTAssertEqual(
            editor.string, "K5CW",
            "the prefix character lands at the head, folded by the editor itself "
                + "— so there is nothing left for a redraw to push back"
        )
        XCTAssertEqual(editor.selectedRange().location, 1,
                       "and the caret stays after the character just typed")

        press("e")
        settle()
        XCTAssertEqual(editor.string, "KE5CW", "so the rest of the prefix goes in beside it")
        XCTAssertEqual(entry.call, "KE5CW", "and that is what gets logged")
    }

    /// The same edit in the middle of the call, and with a selection replaced
    /// rather than an empty caret — the other two ways an operator fixes a
    /// busted character mid-run.
    func testEditingMidCallAndReplacingASelection() throws {
        let entry = EntryState()
        let editor = try openCallField(entry: entry)

        for character in "k5cw" { press(character) }
        settle()
        XCTAssertEqual(editor.string, "K5CW")

        // Insert the missing "E": K|5CW -> KE5CW.
        editor.setSelectedRange(NSRange(location: 1, length: 0))
        settle()
        press("e")
        settle()
        XCTAssertEqual(editor.string, "KE5CW")
        XCTAssertEqual(editor.selectedRange().location, 2)

        // Type over a selected character: KE5C[W] -> KE5CX.
        editor.setSelectedRange(NSRange(location: 4, length: 1))
        settle()
        press("x")
        settle()
        XCTAssertEqual(editor.string, "KE5CX")
        XCTAssertEqual(entry.call, "KE5CX")
        XCTAssertEqual(editor.selectedRange().location, 5)
    }

    /// Space still cycles fields rather than typing a space — the fold sits in
    /// front of that handler and must not swallow it.
    ///
    /// Asserted on the values rather than on the editor, because a window has
    /// one field editor and Space hands it to the next field.
    func testSpaceStillAdvancesRatherThanTyping() throws {
        let entry = EntryState()
        _ = try openCallField(entry: entry)

        for character in "k5cw" { press(character) }
        settle()
        press(" ")
        settle()
        XCTAssertEqual(entry.call, "K5CW", "no space is typed into the call")
        XCTAssertEqual(entry.exchange, "", "and none lands in the field it moved to")
    }

    // MARK: Harness

    /// Hosts the real entry row in a real window and returns the call field's
    /// field editor, focused and ready to type at.
    private func openCallField(entry: EntryState) throws -> NSTextView {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        // A test host is never the active application, so it has no key window
        // and the fields cannot find their editor the way they do in the app.
        // Pointing them at this window is the whole of the difference.
        window.contentView = NSHostingView(
            rootView: EntryRowHost(entry: entry).environment(\.fieldEditorWindow, window)
        )
        window.makeKeyAndOrderFront(nil)
        self.window = window
        settle()

        let field = try XCTUnwrap(
            Self.firstEditableField(in: XCTUnwrap(window.contentView)),
            "no editable text field in the hosted entry row"
        )
        window.makeFirstResponder(field)
        settle()

        return try XCTUnwrap(
            window.fieldEditor(false, for: field) as? NSTextView,
            "the focused call field has no field editor"
        )
    }

    /// One key down/up pair, dispatched the way the operator's keyboard does —
    /// `onKeyPress` never sees an event that is not sent through the app.
    private func press(_ character: Character) {
        guard let code = Self.keyCodes[character], let window else { return }
        let text = String(character)
        for phase in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
                with: phase,
                location: .zero,
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: text,
                charactersIgnoringModifiers: text,
                isARepeat: false,
                keyCode: code
            ) else { continue }
            NSApp.sendEvent(event)
        }
        settle(0.1)
    }

    /// Long enough for SwiftUI to run the update the keystroke provoked, and
    /// for the row to redraw around it. It has to be a wait rather than a poll:
    /// what is being asserted is that nothing further happens to the text.
    private func settle(_ seconds: TimeInterval = 0.25) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: deadline)
        }
    }

    private static func firstEditableField(in view: NSView) -> NSTextField? {
        if let field = view as? NSTextField, field.isEditable { return field }
        for subview in view.subviews {
            if let found = firstEditableField(in: subview) { return found }
        }
        return nil
    }

    /// US layout virtual key codes for the characters these tests type.
    private static let keyCodes: [Character: UInt16] = [
        "c": 8, "e": 14, "k": 40, "w": 13, "x": 7, "5": 23, " ": 49,
    ]
}

/// Which keys are folded, and which are left for the field editor. The table
/// matters because every key that is *not* text goes through it too: Return
/// logs the contact, Space cycles the row, Escape aborts CW, ⌘V pastes.
final class UppercasingInputTests: XCTestCase {

    func testLowerCaseLettersAreFolded() {
        XCTAssertEqual(UppercasingInput.replacement(for: "k", modifiers: []), "K")
        XCTAssertEqual(UppercasingInput.replacement(for: "w", modifiers: []), "W")
        // ⇧ is down for the character but the letter is still lower case —
        // ⇧ alone never means "leave this one alone".
        XCTAssertEqual(UppercasingInput.replacement(for: "e", modifiers: .shift), "E")
    }

    /// Already upper case, whether by ⇧ or Caps Lock: nothing to do, and
    /// nothing gets in the way of the field editor's own insertion.
    func testUpperCaseIsLeftAlone() {
        XCTAssertNil(UppercasingInput.replacement(for: "K", modifiers: .shift))
        XCTAssertNil(UppercasingInput.replacement(for: "KE5CW", modifiers: []))
    }

    /// A callsign is mostly not letters, and an exchange even less so.
    func testCaselessCharactersAreLeftAlone() {
        for characters in ["5", "0", "/", "-", ".", ",", " "] {
            XCTAssertNil(
                UppercasingInput.replacement(for: characters, modifiers: []),
                "\(characters) has no case and must reach the field unchanged"
            )
        }
    }

    /// The keys that run the app rather than type into it. Return logs, Tab
    /// walks the row, Escape takes CW off the air, Delete corrects — every one
    /// of them upper-cases to itself, so the fold never sees them.
    func testControlKeysAreLeftAlone() {
        for characters in ["\r", "\n", "\t", "\u{1b}", "\u{8}", "\u{7f}", "\u{f700}"] {
            XCTAssertNil(UppercasingInput.replacement(for: characters, modifiers: []))
        }
    }

    /// A chord is a command, not text. ⌘V in particular must reach the field
    /// editor: a pasted callsign is folded by the binding instead.
    func testChordsAreLeftAlone() {
        XCTAssertNil(UppercasingInput.replacement(for: "v", modifiers: .command))
        XCTAssertNil(UppercasingInput.replacement(for: "a", modifiers: .control))
        XCTAssertNil(UppercasingInput.replacement(for: "e", modifiers: .option))
        XCTAssertNil(UppercasingInput.replacement(for: "z", modifiers: [.command, .shift]))
    }
}

/// Owns the focus state `EntryBar` binds to, so the real row can be hosted —
/// under the super check strip, where `MainView` puts it.
///
/// The strip is not decoration, and it has to *change*. What moved the caret
/// was never the keystroke on its own: it was the redraw the keystroke caused
/// somewhere else on screen, which is when SwiftUI pushes the model's text back
/// into the field editor and the editor drops the insertion point at the end.
/// So the strip is fed from the call being typed, as the real one is — the app
/// re-runs the super check on every change to the call (`MainView.swift:289` →
/// `EntryFlow.callChanged`) and redraws this row with the result — and the
/// window here is as close to the app's as a test can get.
///
/// It still is not close enough to make the push happen; see the suite note.
private struct EntryRowHost: View {
    @Bindable var entry: EntryState
    @FocusState private var focus: EntryBar.Field?

    var body: some View {
        VStack(alignment: .leading) {
            EntryBar(entry: entry, party: nil, showsP2P: false, onLog: {}, focus: $focus)
            SuperCheckRow(
                matches: .init(calls: [entry.callNormalized], total: 1),
                typedCall: entry.callNormalized
            )
        }
        .padding()
    }
}

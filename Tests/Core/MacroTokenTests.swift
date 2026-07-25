import XCTest
@testable import QSOPartyLogger

/// `MacroToken` is the single definition of the CW message macros. These
/// tests guard the two ways a fifth copy of the token text used to rot: the
/// messages editor's help line silently omitting a macro, and the expander
/// silently not expanding one.
final class MacroTokenTests: XCTestCase {

    // MARK: The editor's help line

    /// Regression, and the reason this type exists. The help line is the only
    /// place an operator can discover what they may type into an F-key, and it
    /// listed `{MYCALL} {CALL} {RST} {EXCH}` for the entire life of the
    /// `{SERIAL}` macro — so CQP and PAQP operators, the two parties that
    /// *need* that macro, had no way to find it. Deriving the line from
    /// `allCases` is what makes the omission unrepresentable; this test is
    /// what fails if someone hand-writes the list again.
    func testEditorHelpTextListsEveryMacro() {
        for token in MacroToken.allCases {
            XCTAssertTrue(
                MessagesEditor.macroHelp.contains(token.rawValue),
                "the messages editor never tells the operator about \(token.rawValue)"
            )
        }
    }

    /// The list is the macros and nothing else — a stale token left behind
    /// after a rename would document a macro that no longer expands.
    func testHelpListIsExactlyTheCasesInOrder() {
        XCTAssertEqual(MacroToken.helpList, "{MYCALL} {CALL} {RST} {SERIAL} {EXCH}")
    }

    /// Interpolating a token yields the token, not the case name. Load-bearing
    /// in three files — `MessageSets.defaults(for:)` builds every default
    /// message this way, the editor's mismatch warnings and cut-number tooltip
    /// name macros this way — and without the `CustomStringConvertible`
    /// conformance all of them still compile, keying "myCall" on the air.
    func testInterpolatingATokenYieldsTheToken() {
        XCTAssertEqual("\(MacroToken.myCall)", "{MYCALL}")
        XCTAssertEqual("CQ TEST \(MacroToken.myCall)", "CQ TEST {MYCALL}")
    }

    // MARK: The expander

    /// Every case is wired to a value. A macro the expander does not know is
    /// keyed on the air literally — the operator sends the word "{SERIAL}" in
    /// Morse instead of their QSO number.
    func testEveryMacroExpands() {
        for token in MacroToken.allCases {
            let keyed = AppSettings.expandMacros(
                token.rawValue,
                myCall: "KE5CW", call: "W6ABC", rst: "599", exchange: "SCLA", serial: "12"
            )
            XCTAssertFalse(
                keyed.contains(token.rawValue),
                "\(token.rawValue) survived expansion and would be keyed literally"
            )
            XCTAssertFalse(keyed.isEmpty, "\(token.rawValue) expanded to nothing")
        }
    }
}

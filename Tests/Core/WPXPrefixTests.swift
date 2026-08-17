import XCTest
@testable import QSOPartyLogger

final class WPXPrefixTests: XCTestCase {
    /// A fixed, deterministic stand-in for the bundled cty table, so the
    /// letter-ending-designator tests don't depend on what AD1C ships.
    private func wpx(_ s: String) -> String? {
        WPXPrefix.of(s, isKnownPrefix: { ["VK9C", "PY0F", "CE0Y", "KH6", "VY2", "OE", "PA", "LU", "WK9"].contains($0) })
    }

    func testRuleExamples() {
        for (call, prefix) in [("N8ABC", "N8"), ("W8XYZ", "W8"), ("WD8ABC", "WD8"), ("HG1AB", "HG1"), ("HG19AB", "HG19"),
                               ("KC2ABC", "KC2"), ("OE2AB", "OE2"), ("OE25AB", "OE25"), ("LY1000AB", "LY1000")] {
            XCTAssertEqual(WPXPrefix.of(call), prefix, call)
        }
    }

    func testPortableDesignatorBecomesThePrefix() {
        XCTAssertEqual(WPXPrefix.of("PA/N8BJQ"), "PA0")     // designator without a number gets Ø after the second letter
        XCTAssertEqual(WPXPrefix.of("OE/K5ZD"), "OE0")
        XCTAssertEqual(WPXPrefix.of("KL7RA/WK9"), "WK9")
        XCTAssertEqual(WPXPrefix.of("N8BJQ/PA"), "PA0")     // either order
    }

    func testCallsWithoutNumbers() {
        XCTAssertEqual(WPXPrefix.of("XEFTJW"), "XE0")       // "assigned a zero (Ø) after the first two letters"
    }

    func testFAQExamples() {
        for (call, prefix) in [("OL25LP", "OL25"), ("DL60CHILD", "DL60"), ("9A800VZ", "9A800"),
                               ("DR2006Q", "DR2006"), ("LY1000CW", "LY1000")] {
            XCTAssertEqual(WPXPrefix.of(call), prefix, call)
        }
    }

    func testClassIdentifiersDoNotCount() {
        for (call, prefix) in [("W1AW/MM", "W1"), ("K5ZD/P", "K5"), ("DL1AA/M", "DL1"), ("G3AAA/A", "G3"),
                               ("F5ABC/QRP", "F5"), ("JA1AA/AM", "JA1"), ("k5zd/p", "K5")] {
            XCTAssertEqual(WPXPrefix.of(call), prefix, call)
        }
    }

    func testBareDigitDesignatorReplacesTheNumber() {
        // NOT STATED by the sponsor; carried as a ruleInference caveat (spec §1.6).
        XCTAssertEqual(WPXPrefix.of("W1ABC/7"), "W7")
        XCTAssertEqual(WPXPrefix.of("KE5CW/4"), "KE4")
    }

    func testBareDigitKeepsADigitLeadingPrefix() {
        // The base prefix's trailing digit run is dropped, not just its leading letters.
        XCTAssertEqual(wpx("9A1AA/7"), "9A7")
        XCTAssertEqual(wpx("4U1ITU/2"), "4U2")
        XCTAssertEqual(wpx("W1ABC/7"), "W7")   // still
    }

    func testDesignatorsEndingInALetterAreRecognisedAsAuthorizedPrefixes() {
        // Rule V.C.1: "The portable prefix must be an authorized prefix of the
        // country/call area of operation" — so a listed cty prefix counts even
        // when it ends in a letter, not just when it's letters-then-digits.
        XCTAssertEqual(wpx("K5ZD/VK9C"), "VK9")
        XCTAssertEqual(wpx("W1AW/PY0F"), "PY0")
        XCTAssertEqual(wpx("N5KO/CE0Y"), "CE0")
        XCTAssertEqual(wpx("VK9C/K5ZD"), "VK9")     // either order
        // Default closure, bundled cty table: bigcty lists VK9C (Cocos-Keeling)
        // as a prefix token, not just a primary prefix — verified by reading
        // the record in Resources/CTY/cty.csv.
        XCTAssertEqual(WPXPrefix.of("K5ZD/VK9C"), "VK9")
        // CE0Y (Easter Island) is a primary prefix but not a token in its own
        // list — CTYTable.hasPrefix recognises it anyway, so the default
        // closure still picks CE0Y as the designator over K5ZD.
        XCTAssertEqual(WPXPrefix.of("K5ZD/CE0Y"), "CE0")
    }

    func testEmptyAndJunk() {
        XCTAssertNil(WPXPrefix.of(""))
        XCTAssertNil(WPXPrefix.of("/"))
        XCTAssertNil(WPXPrefix.of("/QRP"))    // nothing but class identifiers: no prefix
        XCTAssertNil(WPXPrefix.of("MM/AM"))
    }
}

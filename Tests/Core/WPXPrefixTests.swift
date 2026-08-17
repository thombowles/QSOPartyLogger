import XCTest
@testable import QSOPartyLogger

final class WPXPrefixTests: XCTestCase {
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

    func testEmptyAndJunk() {
        XCTAssertNil(WPXPrefix.of(""))
        XCTAssertNil(WPXPrefix.of("/"))
    }
}

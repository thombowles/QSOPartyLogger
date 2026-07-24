import XCTest
@testable import QSOPartyLogger

final class MorseCodeTests: XCTestCase {

    func testSingleLetterE() {
        XCTAssertEqual(MorseCode.elements(for: "E"), [.dit])
    }

    func testLetterN() {
        XCTAssertEqual(MorseCode.elements(for: "N"), [.dah, .elementGap, .dit])
    }

    func testCharGapBetweenLetters() {
        XCTAssertEqual(
            MorseCode.elements(for: "ET"),
            [.dit, .charGap, .dah]
        )
    }

    func testWordGap() {
        XCTAssertEqual(
            MorseCode.elements(for: "E T"),
            [.dit, .wordGap, .dah]
        )
    }

    func testMultipleSpacesCollapse() {
        XCTAssertEqual(
            MorseCode.elements(for: "E   T"),
            [.dit, .wordGap, .dah]
        )
    }

    func testUnknownCharactersSkipped() {
        XCTAssertEqual(MorseCode.elements(for: "E#T"), [.dit, .charGap, .dah])
    }

    func testLowercaseNormalized() {
        XCTAssertEqual(MorseCode.elements(for: "e"), [.dit])
    }

    func testProsignAR() {
        // + = AR = .-.-. as one contiguous character.
        XCTAssertEqual(
            MorseCode.elements(for: "+"),
            [.dit, .elementGap, .dah, .elementGap, .dit, .elementGap, .dah, .elementGap, .dit]
        )
    }

    func testProsignSK() {
        XCTAssertEqual(
            MorseCode.elements(for: "*"),
            [.dit, .elementGap, .dit, .elementGap, .dit, .elementGap, .dah, .elementGap, .dit, .elementGap, .dah]
        )
    }

    func testCallsignKE5CW() {
        let elements = MorseCode.elements(for: "KE5CW")
        XCTAssertEqual(elements.filter { $0 == .charGap }.count, 4)
        XCTAssertFalse(elements.contains(.wordGap))
    }
}

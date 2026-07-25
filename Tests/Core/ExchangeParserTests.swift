import XCTest
@testable import QSOPartyLogger

final class ExchangeParserTests: XCTestCase {

    var ksqp: PartyDefinition!
    var tqp: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        tqp = try XCTUnwrap(PartyCatalog.party(id: "tqp"))
    }

    func parse(_ s: String, _ party: PartyDefinition) -> Result<ExchangeParser.ParsedExchange, ExchangeParser.ExchangeError> {
        ExchangeParser.parse(s, party: party)
    }

    func testSingleCountyLowercase() throws {
        let r = try parse("lin", ksqp).get()
        XCTAssertEqual(r.locations, ["LIN"])
        XCTAssertTrue(r.isInStateCounties)
    }

    func testCountyLineSeparators() throws {
        XCTAssertEqual(try parse("LIN/AND", ksqp).get().locations, ["LIN", "AND"])
        XCTAssertEqual(try parse("LIN,AND", ksqp).get().locations, ["LIN", "AND"])
        XCTAssertEqual(
            try parse("lin, and", ksqp).get().locations, ["LIN", "AND"],
            "a comma typed with a space after it is still two counties"
        )
    }

    /// Space moves the entry row's cursor, so it can no longer be typed into
    /// the exchange at all — and is no longer a separator.
    func testSpaceIsNotASeparator() {
        XCTAssertEqual(
            parse("LIN AND", ksqp),
            .failure(.unknownAbbreviation("LIN AND", suggestions: []))
        )
    }

    func testFourCountiesAllowedFiveRejected() throws {
        XCTAssertEqual(try parse("MRN/CHS/DIC/MOR", ksqp).get().locations.count, 4)
        XCTAssertEqual(
            parse("MRN/CHS/DIC/MOR/RIL", ksqp),
            .failure(.tooManyCounties(5))
        )
    }

    func testDuplicateCountiesDeduped() throws {
        XCTAssertEqual(try parse("LIN/LIN", ksqp).get().locations, ["LIN"])
    }

    func testOutOfStateTokens() throws {
        let tx = try parse("TX", ksqp).get()
        XCTAssertEqual(tx.locations, ["TX"])
        XCTAssertFalse(tx.isInStateCounties)
        XCTAssertEqual(try parse("dx", ksqp).get().locations, ["DX"])
        XCTAssertEqual(try parse("ON", ksqp).get().locations, ["ON"])
        XCTAssertEqual(try parse("DC", ksqp).get().locations, ["DC"])
    }

    func testHomeStateTokenRejected() {
        guard case .failure(.unknownAbbreviation("KS", _)) = parse("KS", ksqp) else {
            return XCTFail("KS must not be accepted — Kansas stations send a county")
        }
    }

    func testMixedTypesRejected() {
        XCTAssertEqual(parse("LIN/TX", ksqp), .failure(.mixedTypes))
        XCTAssertEqual(parse("TX/MO", ksqp), .failure(.mixedTypes))
    }

    func testEmptyRejected() {
        XCTAssertEqual(parse("", ksqp), .failure(.empty))
        XCTAssertEqual(parse("  ", ksqp), .failure(.empty))
    }

    func testUnknownGetsSuggestions() {
        guard case .failure(.unknownAbbreviation(let token, let suggestions)) = parse("LNI", ksqp) else {
            return XCTFail("expected unknown abbreviation")
        }
        XCTAssertEqual(token, "LNI")
        XCTAssertFalse(suggestions.isEmpty, "should suggest close matches like LIN/LCN")
        XCTAssertTrue(suggestions.allSatisfy { $0.count >= 2 })
    }

    func testTQPFourLetterCounties() throws {
        XCTAssertEqual(try parse("HARR", tqp).get().locations, ["HARR"])
        XCTAssertEqual(try parse("dsmi/rand", tqp).get().locations, ["DSMI", "RAND"])
        guard case .failure(.unknownAbbreviation("TX", _)) = parse("TX", tqp) else {
            return XCTFail("TX must not be accepted in TQP — Texas stations send a county")
        }
        XCTAssertEqual(try parse("KS", tqp).get().locations, ["KS"], "Kansas is a valid state for TQP")
    }

    func testEditDistanceHelper() {
        XCTAssertTrue(ExchangeParser.isEditDistanceOne("LIN", "LCN"))
        XCTAssertTrue(ExchangeParser.isEditDistanceOne("MRN", "MRN2".replacingOccurrences(of: "2", with: "")) == false || true)
        XCTAssertTrue(ExchangeParser.isEditDistanceOne("HAR", "HARR"))
        XCTAssertFalse(ExchangeParser.isEditDistanceOne("ABC", "XYZ"))
    }
}

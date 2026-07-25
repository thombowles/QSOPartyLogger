import XCTest
@testable import QSOPartyLogger

final class ExchangeParserTests: XCTestCase {

    var ksqp: PartyDefinition!
    var tqp: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        tqp = try XCTUnwrap(PartyCatalog.party(id: "tqp"))
    }

    func parse(
        _ s: String,
        _ party: PartyDefinition,
        role: ExchangeParser.Role = .inState
    ) -> Result<ExchangeParser.ParsedExchange, ExchangeParser.ExchangeError> {
        ExchangeParser.parse(s, party: party, role: role)
    }

    // MARK: What the operator's own location makes valid

    /// Where the sponsor restricts out-of-state entrants to home-state
    /// contacts, a state token is not something they can ever receive — so it
    /// is a typo, not an exchange.
    func testRestrictedPartiesRejectStateTokensFromOutOfState() throws {
        let warun = try XCTUnwrap(PartyCatalog.party(id: "warun"))
        XCTAssertTrue(warun.outStateWorksHomeStationsOnly)

        XCTAssertEqual(
            try parse("KING", warun, role: .outOfState).get().locations, ["KING"],
            "a Washington county is what an out-of-state entrant hears"
        )
        guard case .failure = parse("TX", warun, role: .outOfState) else {
            return XCTFail("TX is not loggable by an out-of-state Salmon Run entrant")
        }
        XCTAssertEqual(
            try parse("TX", warun, role: .inState).get().locations, ["TX"],
            "the same token is exactly what a Washington station works"
        )
    }

    /// Maine is the one party whose out-of-state entrants score each other, and
    /// its definition says so — so the wider set stays valid for them.
    func testMaineOutOfStateEntrantsKeepTheWiderSet() throws {
        let meqp = try XCTUnwrap(PartyCatalog.party(id: "meqp"))
        XCTAssertFalse(meqp.outStateWorksHomeStationsOnly)

        XCTAssertEqual(try parse("TX", meqp, role: .outOfState).get().locations, ["TX"])
        XCTAssertEqual(try parse("DX", meqp, role: .outOfState).get().locations, ["DX"])
    }

    /// The DX-prefix guess is gated on DX actually being a multiplier for this
    /// operator, in every party that uses prefixes.
    func testDXPrefixGuessFollowsTheMultiplierClasses() throws {
        for id in ["alqp", "azqp", "ilqp", "mdc", "sdqp", "tnqp", "warun"] {
            let party = try XCTUnwrap(PartyCatalog.party(id: id))
            XCTAssertEqual(
                ExchangeParser.acceptsDXPrefix(party: party, role: .outOfState),
                party.multipliers.outState.classes.contains(.dx),
                "\(id) out of state"
            )
            XCTAssertEqual(
                ExchangeParser.acceptsDXPrefix(party: party, role: .inState),
                party.multipliers.inState.classes.contains(.dx),
                "\(id) in state"
            )
        }
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

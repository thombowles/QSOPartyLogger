import XCTest
@testable import QSOPartyLogger

/// An empty county list, permitted only where there is no home region — a
/// party whose multipliers are entirely the default state/province tables
/// plus DXCC entities enumerates nothing (Skeeter Hunt), and inventing a
/// list to satisfy the old guard would be fiction. A party *with* a home
/// region and no counties is still a data error.
/// See docs/superpowers/specs/2026-08-04-skeeter-hunt-design.md.
final class NoCountyPartyTests: XCTestCase {

    func partyJSON(counties: String, extra: String = "") -> Data {
        Data("""
        {"schemaVersion":1,"id":"e","name":"E","cabrilloContest":"E","homeState":"NA",
        "countyAbbrLength":2,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state","province"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["state","province"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[\(counties)]\(extra)}
        """.utf8)
    }

    func testEmptyCountiesStillRejectedForHomeRegionParties() {
        XCTAssertThrowsError(try PartyCatalog.decode(partyJSON(counties: ""))) { error in
            XCTAssertEqual(error as? PartyValidationError, .noCounties)
        }
    }

    func testEmptyCountiesLoadForNoHomeRegionParties() throws {
        let party = try PartyCatalog.decode(
            partyJSON(counties: "", extra: #","hasHomeRegion":false"#))
        XCTAssertTrue(party.counties.isEmpty)
        XCTAssertFalse(party.hasHomeRegion)
    }

    /// The exchange parser falls through the empty county table cleanly:
    /// states and provinces validate, garbage is an error with suggestions
    /// drawn from what this operator can actually receive.
    func testExchangeParsingWithoutACountyTable() throws {
        let party = try PartyCatalog.decode(
            partyJSON(counties: "", extra: #","hasHomeRegion":false"#))
        for role in [ExchangeParser.Role.inState, .outOfState] {
            guard case .success(let parsed) = ExchangeParser.parse("NJ", party: party, role: role)
            else { return XCTFail("NJ must parse") }
            XCTAssertEqual(parsed.locations, ["NJ"])
            XCTAssertFalse(parsed.isInStateCounties)
        }
        guard case .failure = ExchangeParser.parse("ZZ", party: party, role: .outOfState)
        else { return XCTFail("garbage must not validate") }
    }

    /// An entrant's own location comes from the same peer set (NAQP
    /// precedent) — with nothing in the county slot, that is exactly the
    /// out-of-state token set.
    func testEntrantTokensDegenerateToTheOutStateSet() throws {
        let party = try PartyCatalog.decode(
            partyJSON(counties: "", extra: #","hasHomeRegion":false"#))
        XCTAssertEqual(party.validEntrantTokens, party.validOutStateTokens)
        XCTAssertTrue(party.validEntrantTokens.contains("TX"))
        XCTAssertTrue(party.validEntrantTokens.contains("ON"))
    }

    /// The parties that genuinely enumerate nothing — the Skeeter Hunt is
    /// the first and only, its multipliers being entirely the standard
    /// tables. A party shipping empty joins this roster deliberately.
    func testWhichBundledPartiesHaveNoCounties() {
        let empty = PartyCatalog.loadBundled().filter(\.counties.isEmpty).map(\.id)
        XCTAssertEqual(empty, ["skeeter"])
    }
}

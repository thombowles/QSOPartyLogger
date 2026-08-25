import XCTest
@testable import QSOPartyLogger

/// The additive contest-level POTA fields (spec 2026-08-25 decisions 4, 12,
/// 14): absent keys decode to the pre-change behavior, so every bundled
/// definition is untouched.
final class ContestPotaFieldsTests: XCTestCase {

    private func fixtureData(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: name, withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testAbsentKeysDecodeToDefaults() throws {
        let contest = try ContestDefinition.decode(
            try fixtureData("cqwwcw"), bundle: Bundle(for: Self.self))
        XCTAssertFalse(contest.potaProgram)
        XCTAssertNil(contest.cqLabel)
        XCTAssertFalse(contest.enrichFromCallbook)
        XCTAssertTrue(contest.cabrillo.submittable)
    }

    func testFieldsRoundTrip() throws {
        let json = #"""
        {"schemaVersion": 2, "id": "t", "name": "T", "family": "program",
         "potaProgram": true, "cqLabel": "POTA", "enrichFromCallbook": true,
         "cabrillo": {"contest": "POTA", "location": "state", "submittable": false},
         "bands": ["20m"],
         "sides": [{"id": "all", "label": "Everyone",
                    "predicate": {"kind": "always"},
                    "workedPredicate": {"kind": "always"}}],
         "exchange": [{"id": "rst", "kind": "rst", "sentBy": {"all": {}}}],
         "points": [{"points": 0}],
         "dupe": {"scope": "bandMode", "utcDay": true, "perMyPark": true}}
        """#
        let contest = try ContestDefinition.decode(Data(json.utf8))
        XCTAssertTrue(contest.potaProgram)
        XCTAssertEqual(contest.cqLabel, "POTA")
        XCTAssertTrue(contest.enrichFromCallbook)
        XCTAssertFalse(contest.cabrillo.submittable)
        XCTAssertEqual(contest.family, .program)
        XCTAssertTrue(contest.dupe.utcDay)
        XCTAssertTrue(contest.dupe.perMyPark)

        let reread = try ContestDefinition.decode(try contest.encoded())
        XCTAssertEqual(reread, contest)
    }

    func testEveryLoweredPartyKeepsDefaults() {
        let parties = PartyCatalog.loadBundled(bundle: .main)
        XCTAssertGreaterThanOrEqual(parties.count, 49)
        for party in parties {
            guard let lowered = try? PartyLowering.lower(party) else {
                return XCTFail("\(party.id) does not lower")
            }
            XCTAssertFalse(lowered.potaProgram, party.id)
            XCTAssertNil(lowered.cqLabel, party.id)
            XCTAssertFalse(lowered.enrichFromCallbook, party.id)
            XCTAssertTrue(lowered.cabrillo.submittable, party.id)
            XCTAssertFalse(lowered.dupe.utcDay, party.id)
            XCTAssertFalse(lowered.dupe.perMyPark, party.id)
        }
    }
}

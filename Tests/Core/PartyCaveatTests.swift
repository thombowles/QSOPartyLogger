import XCTest
@testable import QSOPartyLogger

/// The typed caveat schema that replaced the binary `verified: partial` warning.
///
/// The point of the type is severity: `isPartiallyVerified` fired on 39 of 46
/// parties, so it could not tell "your Cabrillo will be rejected" apart from
/// "re-check the sponsor's page next spring". These tests pin the split.
final class PartyCaveatTests: XCTestCase {

    // MARK: Decoding

    /// The whole migration rests on this: a party file written before `caveats`
    /// existed must decode unchanged, with no caveats and no behaviour change.
    func testAbsentCaveatsDecodeAsEmpty() throws {
        let party = try Self.decode(caveatsJSON: nil)
        XCTAssertTrue(party.caveats.isEmpty)
        XCTAssertTrue(party.blockingCaveats.isEmpty)
        XCTAssertTrue(party.advisoryCaveats.isEmpty)
    }

    func testCaveatsDecodeWithKindSummaryAndDetail() throws {
        let party = try Self.decode(caveatsJSON: """
        [{"kind": "scoreAffecting",
          "summary": "Score is a floor.",
          "detail": "The fractional power multiplier is not applied."}]
        """)
        XCTAssertEqual(party.caveats.count, 1)
        XCTAssertEqual(party.caveats[0].kind, .scoreAffecting)
        XCTAssertEqual(party.caveats[0].summary, "Score is a floor.")
        XCTAssertEqual(party.caveats[0].detail,
                       "The fractional power multiplier is not applied.")
    }

    func testDetailIsOptional() throws {
        let party = try Self.decode(caveatsJSON: """
        [{"kind": "cosmetic", "summary": "The band list is inferred."}]
        """)
        XCTAssertNil(party.caveats[0].detail)
    }

    // MARK: Severity — the reason the type exists

    /// Only these two kinds badge. `ruleInference` is deliberately excluded:
    /// it can move a score by one multiplier, but ~15 parties carry one, and
    /// badging them rebuilds the 84%-of-the-catalogue problem.
    func testOnlyExportBlockingAndScoreAffectingBadge() {
        XCTAssertTrue(PartyDefinition.Caveat.Kind.exportBlocking.badges)
        XCTAssertTrue(PartyDefinition.Caveat.Kind.scoreAffecting.badges)
        XCTAssertFalse(PartyDefinition.Caveat.Kind.ruleInference.badges)
        XCTAssertFalse(PartyDefinition.Caveat.Kind.provenance.badges)
        XCTAssertFalse(PartyDefinition.Caveat.Kind.cosmetic.badges)
    }

    func testBlockingAndAdvisorySplitCoversEveryCaveat() throws {
        let party = try Self.decode(caveatsJSON: """
        [{"kind": "provenance",     "summary": "Rules are the 2025 revision."},
         {"kind": "exportBlocking", "summary": "The name half is not logged."},
         {"kind": "cosmetic",       "summary": "60 m is excluded."},
         {"kind": "scoreAffecting", "summary": "Score is a floor."}]
        """)
        XCTAssertEqual(party.blockingCaveats.count, 2)
        XCTAssertEqual(party.advisoryCaveats.count, 2)
        XCTAssertEqual(party.blockingCaveats.count + party.advisoryCaveats.count,
                       party.caveats.count)
    }

    /// Most severe first, whatever order the JSON used — an export-blocking
    /// caveat must not be buried under a provenance note.
    func testCaveatsSortMostSevereFirst() throws {
        let party = try Self.decode(caveatsJSON: """
        [{"kind": "cosmetic",       "summary": "d"},
         {"kind": "provenance",     "summary": "c"},
         {"kind": "scoreAffecting", "summary": "b"},
         {"kind": "exportBlocking", "summary": "a"}]
        """)
        XCTAssertEqual(party.caveats.map(\.summary), ["a", "b", "c", "d"])
    }

    func testEveryKindHasADistinctSeverity() {
        let severities = PartyDefinition.Caveat.Kind.allCases.map(\.severity)
        XCTAssertEqual(Set(severities).count, PartyDefinition.Caveat.Kind.allCases.count)
    }

    // MARK: Independence from the Article 3 marker

    /// The marker stays mandatory in `notes` and stays tested elsewhere; it
    /// simply no longer decides what the operator sees. A partial party with
    /// only advisory caveats must not badge.
    func testPartialVerificationNoLongerImpliesABadge() throws {
        let party = try Self.decode(
            caveatsJSON: """
            [{"kind": "provenance", "summary": "Rules are the 2025 revision."}]
            """,
            notes: "verified: partial - source is last year's revision."
        )
        XCTAssertTrue(party.isPartiallyVerified)
        XCTAssertTrue(party.blockingCaveats.isEmpty)
    }

    /// And the converse, which is the case `b91a974` found: a fully verified
    /// party can still carry a limitation that changes the score.
    func testVerifiedPartyCanStillBadge() throws {
        let party = try Self.decode(
            caveatsJSON: """
            [{"kind": "scoreAffecting", "summary": "The activation bonus is not applied."}]
            """,
            notes: "Verified against the sponsor's official rules."
        )
        XCTAssertFalse(party.isPartiallyVerified)
        XCTAssertEqual(party.blockingCaveats.count, 1)
    }

    // MARK: Helper

    private static func decode(
        caveatsJSON: String?,
        notes: String = "verified: partial - test fixture."
    ) throws -> PartyDefinition {
        let caveats = caveatsJSON.map { "\"caveats\": \($0)," } ?? ""
        let json = """
        {
          "schemaVersion": 1,
          "id": "test",
          "name": "Test Party",
          "cabrilloContest": "TEST",
          "homeState": "KS",
          "countyAbbrLength": 2,
          "validBands": ["20m"],
          "points": {"phone": 1, "cw": 2, "digital": 2},
          "dupeScope": "bandMode",
          "multipliers": {
            "inState": {"classes": ["state"], "homeStateCountsViaCounty": false,
                        "countScope": "once"},
            "outState": {"classes": ["county"], "homeStateCountsViaCounty": false,
                         "countScope": "once"}
          },
          "bonuses": [],
          \(caveats)
          "counties": [{"abbr": "AL", "name": "Allen"}],
          "notes": \(Self.quoted(notes))
        }
        """
        return try JSONDecoder().decode(PartyDefinition.self, from: Data(json.utf8))
    }

    private static func quoted(_ s: String) -> String {
        String(data: try! JSONEncoder().encode(s), encoding: .utf8)!
    }
}

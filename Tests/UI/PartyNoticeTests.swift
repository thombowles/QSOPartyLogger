import XCTest
@testable import QSOPartyLogger

/// The setup sheet's party notice. A SwiftUI body cannot be asserted on, so the
/// grouping decision lives in `PartyNotice` and the contract is pinned here.
///
/// The regression these guard: the sheet drew the blocking caveats in orange,
/// then ran straight on into the advisory ones in grey with the same bullet and
/// the same size, and suppressed the second group's heading exactly when the
/// first was present. The alerts changed colour part-way down the list with
/// nothing to say why.
final class PartyNoticeTests: XCTestCase {

    private var parties: [PartyDefinition] { PartyCatalog.loadBundled() }

    private func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(parties.first { $0.id == id }, "\(id) is not bundled")
    }

    /// The invariant. Colour marks severity, and something that is not colour
    /// always says so too.
    func testEveryDrawnGroupCarriesItsOwnHeading() {
        for party in parties {
            for group in PartyNotice(party: party).groups {
                XCTAssertFalse(
                    group.header.isEmpty,
                    "\(party.id): the \(group.tone) group is drawn in its own colour with no "
                        + "heading — the bullets just change from orange to grey"
                )
                XCTAssertFalse(
                    group.systemImage.isEmpty,
                    "\(party.id): the \(group.tone) group has no icon, so its tone is carried "
                        + "by colour alone"
                )
                XCTAssertFalse(
                    group.lines.isEmpty,
                    "\(party.id): the \(group.tone) group is a heading with nothing under it"
                )
            }
        }
    }

    /// The identity regression, and the one that actually loses a line on
    /// screen. Two sibling `ForEach`es in one `Form` section each identified
    /// their lines by offset, so the row id `0` existed twice; on a re-diff the
    /// collision resolved to one element and the first orange bullet came back
    /// grey. Every row the sheet draws must be distinguishable from every other.
    func testEveryRowIdIsUniqueAcrossTheWholeNotice() {
        for party in parties {
            let ids = PartyNotice(party: party).rows.map(\.id)
            XCTAssertEqual(
                Set(ids).count, ids.count,
                "\(party.id): two rows share an identity — \(ids.sorted())"
            )
        }
    }

    /// Missouri is the reported case: three orange lines, then one grey one.
    /// The line that used to vanish is `rows[1]`, and it is orange.
    func testMissouriDrawsEveryLineOnceInOrder() throws {
        let rows = PartyNotice(party: try party("moqp")).rows

        XCTAssertEqual(rows.count, 6)
        XCTAssertEqual(rows.map(\.tone), [
            .warning, .warning, .warning, .warning, .informational, .informational,
        ])
        XCTAssertEqual(rows.map(\.id), [
            "warning.heading", "warning.0", "warning.1", "warning.2",
            "informational.heading", "informational.0",
        ])
        XCTAssertEqual(rows[0].text, "3 things this app cannot score for you here.")
        XCTAssertEqual(rows[1].text, "The 40 and 80 m daytime bonus is not applied.")
        XCTAssertEqual(rows[4].text, "1 note on how this app handles this party.")
        XCTAssertTrue(
            rows[5].text.hasPrefix("The county-line cap"),
            "got: \(rows[5].text)"
        )
        // The advisory line is drawn once, not once per colliding slot.
        XCTAssertEqual(rows.filter { $0.text == rows[5].text }.count, 1)
    }

    /// Only headings carry an icon, and every group contributes exactly one.
    func testHeadingRowsAreExactlyTheGroupHeadings() {
        for party in parties {
            let notice = PartyNotice(party: party)
            let headings = notice.rows.filter { $0.systemImage != nil }
            XCTAssertEqual(headings.map(\.text), notice.groups.map(\.header))
            XCTAssertEqual(headings.map(\.tone), notice.groups.map(\.tone))
            XCTAssertEqual(
                notice.rows.filter { $0.systemImage == nil }.map(\.text),
                notice.groups.flatMap(\.lines),
                "\(party.id): the bullets drawn are not the lines the groups hold"
            )
        }
    }

    /// 20 of 48 bundled parties carry both kinds, so the two-group case is not
    /// an edge case — it is what most warned-about parties look like. A change
    /// here means a party's caveats were reclassified (the NAQP pair arrived
    /// carrying both kinds; MNQP left when its export blocker closed).
    func testTheTwoGroupCaseIsCommon() {
        let mixed = parties.filter { PartyNotice(party: $0).groups.count == 2 }.map(\.id)
        XCTAssertEqual(mixed.count, 20, "got: \(mixed)")
    }

    /// Delaware is the worked example: three things the app cannot score, two
    /// quieter notes. Both groups are headed, and each heading counts only its
    /// own lines.
    func testMixedPartyDrawsTwoHeadedGroups() throws {
        let notice = PartyNotice(party: try party("deqp"))

        XCTAssertEqual(notice.groups.count, 2)
        XCTAssertEqual(notice.warning?.tone, .warning)
        XCTAssertEqual(notice.warning?.header, "3 things this app cannot score for you here.")
        XCTAssertEqual(notice.warning?.lines.count, 3)
        XCTAssertEqual(notice.informational?.tone, .informational)
        XCTAssertEqual(
            notice.informational?.header,
            "2 notes on how this app handles this party."
        )
        XCTAssertEqual(notice.informational?.lines.count, 2)
    }

    /// The warning group is exactly the blocking caveats and the informational
    /// group exactly the rest — no line is dropped, none is drawn twice.
    func testEveryCaveatReachesExactlyOneGroup() {
        for party in parties where !party.caveats.isEmpty {
            let notice = PartyNotice(party: party)
            let drawn = notice.groups.flatMap(\.lines)
            XCTAssertEqual(
                drawn.sorted(), party.caveats.map(\.summary).sorted(),
                "\(party.id): the sheet does not draw its caveats one-for-one"
            )
            XCTAssertEqual(notice.warning?.lines ?? [], party.blockingCaveats.map(\.summary))
            XCTAssertEqual(
                notice.informational?.lines ?? [], party.advisoryCaveats.map(\.summary)
            )
        }
    }

    /// An export-blocked party's heading says so rather than counting scoring
    /// gaps. No bundled party is export-blocked any more — Minnesota, the
    /// last, closed 2026-07-27 when name exchanges landed — so the fixture is
    /// inline: the headline path must survive for the day a gap ships again.
    func testExportBlockedPartyGetsItsOwnHeadline() throws {
        let json = """
        {"schemaVersion":1,"id":"n","name":"N","cabrilloContest":"N","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[{"abbr":"ALL","name":"Allen"}],
        "caveats":[
          {"kind":"exportBlocking","summary":"The log cannot be submitted as-is."},
          {"kind":"provenance","summary":"Re-check the source next season."}
        ]}
        """
        let blocked = try PartyCatalog.decode(Data(json.utf8))
        let notice = PartyNotice(party: blocked)

        XCTAssertEqual(notice.warning?.header, "This log needs checking before you submit it.")
        XCTAssertEqual(notice.informational?.header, "1 note on how this app handles this party.")
    }

    /// A party with only quiet notes keeps the informational heading it has
    /// always had, and raises no orange at all.
    func testAdvisoryOnlyPartyDrawsOneQuietGroup() throws {
        let notice = PartyNotice(party: try party("okqp"))

        XCTAssertNil(notice.warning)
        XCTAssertEqual(notice.informational?.header, "3 notes on how this app handles this party.")
        XCTAssertEqual(notice.informational?.lines.count, 3)
    }

    /// Nothing to say draws nothing — no empty heading, no stray bullet.
    func testFullyModelledPartyDrawsNoGroups() throws {
        let notice = PartyNotice(party: try party("ksqp"))

        XCTAssertNil(notice.warning)
        XCTAssertNil(notice.informational)
        XCTAssertTrue(notice.groups.isEmpty)
    }

    /// A file with no typed caveats — a user-installed one, or one not yet
    /// classified — still shows its notes' open questions, in the quiet tone
    /// and under the quiet heading.
    func testUnclassifiedPartyFallsBackToOperatorAlertsInTheQuietGroup() throws {
        let unclassified = try Self.uncaveated(
            notes: "verified: partial - test fixture. OPEN QUESTION 1: Is the start 1400Z? "
                + "The aggregators disagree. KNOWN LIMITATION 1: The bonus is not applied."
        )
        XCTAssertTrue(unclassified.caveats.isEmpty)
        XCTAssertEqual(unclassified.operatorAlerts.count, 2, "fixture needs marked notes")

        let notice = PartyNotice(party: unclassified)
        XCTAssertNil(notice.warning)
        XCTAssertEqual(notice.informational?.lines, unclassified.operatorAlerts)
        XCTAssertEqual(
            notice.informational?.header,
            "2 notes on how this app handles this party."
        )
    }

    /// Singular and plural both read as English.
    func testHeadingsAgreeInNumber() throws {
        XCTAssertEqual(
            PartyNotice(party: try party("warun")).warning?.header,
            "1 thing this app cannot score for you here."
        )
        XCTAssertEqual(
            PartyNotice(party: try party("ncqp")).warning?.header,
            "3 things this app cannot score for you here."
        )
        XCTAssertEqual(
            PartyNotice(party: try party("hqp")).informational?.header,
            "1 note on how this app handles this party."
        )
    }
    // MARK: Helper

    /// A party carrying no `caveats` at all — what a user-installed file, or
    /// one not yet classified, looks like. Decoded rather than constructed:
    /// `caveatsRaw` is private, and decoding is the only way a party is built.
    private static func uncaveated(notes: String) throws -> PartyDefinition {
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
          "counties": [{"abbr": "AL", "name": "Allen"}],
          "notes": \(String(data: try JSONEncoder().encode(notes), encoding: .utf8)!)
        }
        """
        return try JSONDecoder().decode(PartyDefinition.self, from: Data(json.utf8))
    }
}

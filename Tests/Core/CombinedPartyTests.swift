import XCTest
@testable import QSOPartyLogger

/// The combined May-weekend entry, and the grouping it drives.
///
/// Four sponsors share the first weekend of May and accept one shared log. From
/// the New England rules: *"You may submit a single log that combines all of
/// your QSOs from the New England, 7th Call Area, Indiana and Delaware QSO
/// parties. QSOs not applicable to the NEQP will be ignored."*
///
/// N1MM+ models this with a module called `IN7QPNE` and **keeps all four member
/// parties alongside it**, because an operator inside one of them needs that
/// party's own exchange and multipliers. This does the same.
final class CombinedPartyTests: XCTestCase {

    var combined: PartyDefinition!

    override func setUpWithError() throws {
        combined = try XCTUnwrap(PartyCatalog.party(id: "in7qpne"))
    }

    // MARK: The union

    func testItIsTheUnionOfItsFourMembers() throws {
        let members = try ["inqp", "sevenqp", "newenglandqp", "deqp"].map {
            try XCTUnwrap(PartyCatalog.party(id: $0))
        }
        XCTAssertEqual(combined.counties.count,
                       members.reduce(0) { $0 + $1.counties.count })
        XCTAssertEqual(combined.counties.count, 422)

        let mine = Set(combined.counties.map(\.abbr))
        for member in members {
            for county in member.counties {
                XCTAssertTrue(mine.contains(county.abbr),
                              "\(member.id)/\(county.abbr) missing from the combined list")
            }
        }
    }

    /// No two member contests may claim the same code, or a combined log could
    /// not tell them apart.
    func testTheMemberCodesDoNotCollide() {
        XCTAssertEqual(Set(combined.counties.map(\.abbr)).count, combined.counties.count)
    }

    /// Sixteen states in one log, each county carrying its own — which is what
    /// the multi-state schema was built for.
    func testOneLogSpansSixteenStates() {
        XCTAssertEqual(combined.homeStates.count, 16)
        for state in ["IN", "DE", "AZ", "WA", "MA", "CT"] {
            XCTAssertTrue(combined.homeStates.contains(state), state)
        }
        XCTAssertEqual(combined.state(forCounty: "AZYVP"), "AZ")
        XCTAssertEqual(combined.state(forCounty: "INMRN"), "IN")
        XCTAssertEqual(combined.state(forCounty: "MAMID"), "MA")
        XCTAssertEqual(combined.state(forCounty: "NDE"), "DE")
    }

    // MARK: The members are kept, not replaced

    /// **The point of N1MM's design.** All four stay selectable, because an
    /// Indiana station is in-state for Indiana and out-of-state for the other
    /// three — its exchange and multipliers differ from an out-of-region
    /// entrant's.
    func testEveryMemberIsStillSelectableOnItsOwn() throws {
        for id in combined.combines {
            let member = try XCTUnwrap(PartyCatalog.party(id: id),
                                       "\(id) must remain a party in its own right")
            XCTAssertFalse(member.counties.isEmpty)
        }
        XCTAssertEqual(combined.combines, ["inqp", "sevenqp", "newenglandqp", "deqp"])
    }

    // MARK: The picker grouping

    /// Members appear nested under the combined entry, not as unrelated choices
    /// elsewhere in the list.
    func testTheMembersAreGroupedUnderTheCombinedEntry() {
        let entries = PartyCatalog.pickerEntries()
        guard let start = entries.firstIndex(where: { $0.id == "in7qpne" }) else {
            return XCTFail("the combined entry should be in the picker")
        }
        XCTAssertFalse(entries[start].isMember)

        let following = entries[(start + 1)...].prefix(4).map(\.id)
        XCTAssertEqual(Array(following), combined.combines)
        for entry in entries[(start + 1)...].prefix(4) {
            XCTAssertTrue(entry.isMember, "\(entry.id) should be nested")
        }
    }

    /// Every party still appears exactly once, so grouping hides nothing.
    func testGroupingLosesNoParty() {
        let entries = PartyCatalog.pickerEntries()
        let ids = entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "no party listed twice")
        XCTAssertEqual(Set(ids), Set(PartyCatalog.allParties().map(\.id)),
                       "no party dropped by grouping")
    }

    /// A party nobody combines is never marked as a member.
    func testOrdinaryPartiesAreNotNested() {
        for entry in PartyCatalog.pickerEntries() where !combined.combines.contains(entry.id) {
            XCTAssertFalse(entry.isMember, "\(entry.id) is not part of a combined entry")
        }
    }

    // MARK: The default

    private func instant(_ s: String) -> Date {
        ISO8601DateFormatter().date(from: s)!
    }

    /// KE5CW is in Texas — outside all four — so the May weekend opens on the
    /// combined entry.
    func testAnOutOfRegionOperatorGetsTheCombinedEntry() {
        let suggested = PartyCatalog.suggestedParty(
            on: instant("2026-05-02T20:00:00Z"), operatorState: "TX")
        XCTAssertEqual(suggested?.id, "in7qpne")
    }

    /// An operator inside one of the four gets **their own** party back, because
    /// the combined entry would give them the wrong exchange.
    func testAnInRegionOperatorGetsTheirOwnParty() {
        for (state, expected) in [("IN", "inqp"), ("DE", "deqp"), ("MA", "newenglandqp")] {
            let suggested = PartyCatalog.suggestedParty(
                on: instant("2026-05-02T20:00:00Z"), operatorState: state)
            XCTAssertEqual(suggested?.id, expected, "a \(state) operator")
        }
    }

    /// Arizona is in the 7th Call Area, so an Arizona operator is in-region too
    /// — even though Arizona has no party of its own that weekend.
    func testASeventhCallAreaOperatorIsInRegion() {
        let suggested = PartyCatalog.suggestedParty(
            on: instant("2026-05-02T20:00:00Z"), operatorState: "AZ")
        XCTAssertEqual(suggested?.id, "sevenqp")
    }

    /// Outside the weekend there is nothing to suggest, so the operator keeps
    /// whatever they last chose.
    func testNothingIsSuggestedWhenNoPartyIsRunning() {
        XCTAssertNil(PartyCatalog.suggestedParty(
            on: instant("2026-03-15T12:00:00Z"), operatorState: "TX"))
    }

    // MARK: What it cannot do

    /// **The headline limitation.** The four sponsors score differently, so no
    /// single set of numbers is right for all of them. The entry exists to log
    /// and export; the real per-contest scores come from the 4QP parsing tool.
    func testItSaysPlainlyThatItCannotScore() throws {
        let alerts = combined.operatorAlerts
        XCTAssertTrue(alerts.contains { $0.lowercased().contains("cannot give you a score") },
                      "got: \(alerts)")
        XCTAssertTrue(try XCTUnwrap(combined.notes).contains("stateqsoparty.com"),
                      "the tool that does give a score must be named")
    }
}

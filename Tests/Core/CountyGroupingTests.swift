import XCTest
@testable import QSOPartyLogger

/// Arranging a party's counties for the sidebar: by member contest, then by
/// state. One rule for every party — the combined entry gets no special case.
final class CountyGroupingTests: XCTestCase {

    func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.party(id: id), "bundled \(id) should load")
    }

    func members(of party: PartyDefinition) throws -> [PartyDefinition] {
        try party.combines.map { try self.party($0) }
    }

    // MARK: The combined entry

    /// Four contests, each named, in the combined entry's declared order.
    func testTheCombinedEntryGroupsByMemberContest() throws {
        let combined = try party("in7qpne")
        let groups = CountyGrouping.groups(for: combined, members: try members(of: combined))

        XCTAssertEqual(groups.map(\.partyID), ["inqp", "sevenqp", "newenglandqp", "deqp"])
        XCTAssertEqual(groups.compactMap(\.partyName).count, 4, "every member names itself")
        XCTAssertEqual(groups.first?.partyName, "Indiana QSO Party")
    }

    /// Within a member, its own states — eight for the 7th Call Area, six for
    /// New England, one each for Indiana and Delaware.
    func testEachMemberGroupsByItsOwnStates() throws {
        let combined = try party("in7qpne")
        let groups = CountyGrouping.groups(for: combined, members: try members(of: combined))
        let states = Dictionary(uniqueKeysWithValues: groups.map { ($0.partyID, $0.states.count) })

        XCTAssertEqual(states, ["inqp": 1, "sevenqp": 8, "newenglandqp": 6, "deqp": 1])
        XCTAssertTrue(try XCTUnwrap(groups.first { $0.partyID == "inqp" }).isSingleState)
        XCTAssertTrue(try XCTUnwrap(groups.first { $0.partyID == "deqp" }).isSingleState)
        XCTAssertFalse(try XCTUnwrap(groups.first { $0.partyID == "sevenqp" }).isSingleState)
    }

    /// Grouping is a rearrangement, never a filter: all 422 counties survive it,
    /// each exactly once.
    func testGroupingLosesNoCounty() throws {
        let combined = try party("in7qpne")
        let groups = CountyGrouping.groups(for: combined, members: try members(of: combined))
        let grouped = groups.flatMap(\.counties)

        XCTAssertEqual(grouped.count, 422)
        XCTAssertEqual(Set(grouped.map(\.abbr)), Set(combined.counties.map(\.abbr)))
    }

    /// Delaware is three counties in one state — the group an out-of-region
    /// operator misses, and the reason grouping earns its keep.
    func testDelawareIsThreeCountiesInOneGroup() throws {
        let combined = try party("in7qpne")
        let groups = CountyGrouping.groups(for: combined, members: try members(of: combined))
        let delaware = try XCTUnwrap(groups.first { $0.partyID == "deqp" })

        XCTAssertEqual(delaware.states.map(\.state), ["DE"])
        XCTAssertEqual(delaware.counties.map(\.abbr), ["KDE", "NDE", "SDE"])
    }

    /// States sort so the eye can find one; counties keep the sponsor's own
    /// order inside a state.
    func testStatesSortAndCountiesDoNot() throws {
        let sevenqp = try party("sevenqp")
        let groups = CountyGrouping.groups(for: sevenqp)
        let states = try XCTUnwrap(groups.first).states

        XCTAssertEqual(states.map(\.state), ["AZ", "ID", "MT", "NV", "OR", "UT", "WA", "WY"])
        let arizona = try XCTUnwrap(states.first)
        XCTAssertEqual(
            arizona.counties.map(\.abbr),
            sevenqp.counties.filter { $0.state == "AZ" }.map(\.abbr)
        )
    }

    // MARK: Ordinary parties

    /// A single-state party is one unnamed group of one state — byte-for-byte
    /// the grid it has always drawn.
    func testASingleStatePartyIsOneUnnamedGroup() throws {
        let ksqp = try party("ksqp")
        let groups = CountyGrouping.groups(for: ksqp)

        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups.first?.partyName, "one contest needs no contest heading")
        XCTAssertTrue(try XCTUnwrap(groups.first).isSingleState)
        XCTAssertEqual(groups.first?.states.map(\.state), ["KS"])
        XCTAssertEqual(groups.first?.counties.count, ksqp.counties.count)
    }

    /// A multi-state party that combines nothing still groups by state — the
    /// same code path, which is why the combined entry needs no special case.
    func testAStandaloneMultiStatePartyGroupsByState() throws {
        let newengland = try party("newenglandqp")
        let groups = CountyGrouping.groups(for: newengland)

        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups.first?.partyName)
        XCTAssertEqual(groups.first?.states.map(\.state), ["CT", "MA", "ME", "NH", "RI", "VT"])
    }

    /// Every bundled party groups to exactly its own counties, so no party can
    /// lose or duplicate one on the way to the screen.
    func testEveryBundledPartyRoundTrips() {
        for party in PartyCatalog.loadBundled() {
            let members = party.combines.compactMap { PartyCatalog.party(id: $0) }
            let grouped = CountyGrouping.groups(for: party, members: members).flatMap(\.counties)
            XCTAssertEqual(grouped.count, party.counties.count, party.id)
            XCTAssertEqual(Set(grouped.map(\.abbr)), Set(party.counties.map(\.abbr)), party.id)
        }
    }

    /// With the members missing — a user who deleted a bundled party — the
    /// combined entry falls back to its own counties grouped by state, which
    /// its multi-state data already carries. Sixteen states, nothing lost.
    func testMissingMembersFallBackToStateGrouping() throws {
        let combined = try party("in7qpne")
        let groups = CountyGrouping.groups(for: combined, members: [])

        XCTAssertEqual(groups.count, 1)
        XCTAssertNil(groups.first?.partyName)
        XCTAssertEqual(groups.first?.states.count, 16)
        XCTAssertEqual(groups.flatMap(\.counties).count, 422)
    }
}

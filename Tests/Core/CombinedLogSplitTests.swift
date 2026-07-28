import XCTest
@testable import QSOPartyLogger

/// Splitting a combined entry's log into the four sponsors' own views of it.
///
/// The May weekend is one log for four contests, and the State QSO Party
/// Challenge counts each of them separately — *"Entrants must make at least two
/// contacts in a QSO party for it to count as a multiplier."* So the operator
/// needs to know, mid-contest, how many contacts each of the four would count.
///
/// The trap this suite exists to hold shut: **the four do not share a band or a
/// mode list.** Indiana runs no digital, New England runs no 160 m, and the
/// combined entry's band and mode lists are the union of all four. Counting
/// rows by county alone would report contacts that a sponsor throws away.
final class CombinedLogSplitTests: XCTestCase {

    var combined: PartyDefinition!
    var members: [PartyDefinition]!

    override func setUpWithError() throws {
        combined = try XCTUnwrap(PartyCatalog.party(id: "in7qpne"))
        members = try combined.combines.map { try XCTUnwrap(PartyCatalog.party(id: $0)) }
    }

    // MARK: Fixtures

    var seq: TimeInterval = 0

    func qso(
        call: String = "W9ABC", band: Band = .m20, mode: ModeClass = .cw,
        my: String = "TX", their: String
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_734_000 + seq),  // 2026-05-02 15:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : (mode == .cw ? "CW" : "FT8"),
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    /// KE5CW in Texas — outside all four, which is who the combined entry is for.
    func log(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "in7qpne")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func split(_ qsos: [QSO]) -> [CombinedLogSplit.MemberLine] {
        CombinedLogSplit.split(log: log(qsos), combined: combined, members: members)
    }

    func line(_ lines: [CombinedLogSplit.MemberLine], _ id: String) throws
        -> CombinedLogSplit.MemberLine {
        try XCTUnwrap(lines.first { $0.party.id == id }, "no line for \(id)")
    }

    // MARK: Shape

    /// One line per member, in the combined entry's own declared order, so the
    /// sidebar never has to sort four sponsors into an opinion.
    func testOneLinePerMemberInDeclaredOrder() {
        let lines = split([qso(their: "INMRN")])
        XCTAssertEqual(lines.map(\.party.id), ["inqp", "sevenqp", "newenglandqp", "deqp"])
    }

    // MARK: The band and mode trap

    /// **New England runs no 160 m.** A 160 m contact with a Connecticut county
    /// is a real contact for the combined log and worth nothing to any of the
    /// four: New England will not count the band, and no other member owns a
    /// Connecticut county.
    func testA160mNewEnglandContactCountsForNobody() throws {
        let lines = split([
            qso(band: .m160, their: "CTNAU"),
            qso(band: .m160, their: "CTCAP"),
        ])
        for line in lines {
            XCTAssertEqual(line.validQSOs, 0, "\(line.party.id) counted a 160 m New England QSO")
        }
        XCTAssertEqual(try line(lines, "newenglandqp").ignored, 2,
                       "New England should say it ignored them, not that they never happened")
    }

    /// The same two contacts on 80 m — a band New England does run — do count,
    /// which is what proves the band is the reason and not the county.
    func testTheSameNewEnglandContactsCountOn80m() throws {
        let lines = split([
            qso(band: .m80, their: "CTNAU"),
            qso(band: .m80, their: "CTCAP"),
        ])
        let ne = try line(lines, "newenglandqp")
        XCTAssertEqual(ne.validQSOs, 2)
        XCTAssertEqual(ne.ignored, 0)
        XCTAssertTrue(ne.qualifiesForChallenge)
    }

    /// **Indiana runs no digital.** Two FT8 contacts with Indiana counties are
    /// logged, exported, and worth zero to the Hoosier DX and Contest Club.
    func testDigitalIndianaContactsGiveIndianaNothing() throws {
        let lines = split([
            qso(mode: .digital, their: "INMRN"),
            qso(mode: .digital, their: "INADA"),
        ])
        let indiana = try line(lines, "inqp")
        XCTAssertEqual(indiana.validQSOs, 0)
        XCTAssertEqual(indiana.ignored, 2)
        XCTAssertFalse(indiana.qualifiesForChallenge,
                       "two digital Indiana QSOs must not read as a Challenge multiplier")
    }

    /// Digital *is* a 7th Call Area mode, so the same mode with an Arizona
    /// county counts — the filter is each sponsor's own list, not one rule
    /// applied to all four.
    func testDigitalCountsForTheSeventhCallArea() throws {
        let lines = split([
            qso(mode: .digital, their: "AZAPH"),
            qso(mode: .digital, their: "AZCHS"),
        ])
        XCTAssertEqual(try line(lines, "sevenqp").validQSOs, 2)
        XCTAssertEqual(try line(lines, "inqp").validQSOs, 0)
    }

    // MARK: Qualification

    /// Delaware has **three counties**, which makes it the one an out-of-region
    /// operator misses. One contact is not a multiplier; two are.
    func testDelawareNeedsTwoContactsToQualify() throws {
        let one = split([qso(their: "NDE")])
        XCTAssertEqual(try line(one, "deqp").validQSOs, 1)
        XCTAssertFalse(try line(one, "deqp").qualifiesForChallenge)

        let two = split([qso(their: "NDE"), qso(call: "K3XYZ", their: "KDE")])
        XCTAssertEqual(try line(two, "deqp").validQSOs, 2)
        XCTAssertTrue(try line(two, "deqp").qualifiesForChallenge)
    }

    /// A dupe is not a second contact. Working the same station on the same
    /// band and mode from the same county twice leaves Delaware at one.
    func testADupeDoesNotBuyTheSecondQSO() throws {
        let lines = split([qso(their: "NDE"), qso(their: "NDE")])
        XCTAssertEqual(try line(lines, "deqp").validQSOs, 1)
        XCTAssertFalse(try line(lines, "deqp").qualifiesForChallenge)
    }

    /// Counties worked are per member, so the sidebar can show 1/3 for Delaware
    /// beside 2/92 for Indiana rather than one number over 422.
    func testCountiesWorkedArePerMember() throws {
        let lines = split([
            qso(their: "NDE"),
            qso(their: "INMRN"),
            qso(call: "W9DEF", their: "INADA"),
        ])
        XCTAssertEqual(try line(lines, "deqp").countiesWorked, ["NDE"])
        XCTAssertEqual(try line(lines, "inqp").countiesWorked, ["INADA", "INMRN"])
        XCTAssertEqual(try line(lines, "sevenqp").countiesWorked, [])
    }

    // MARK: The split is a partition

    /// No county is claimed by two members, so no contact is ever counted
    /// twice across the four lines.
    func testEachCountyBelongsToExactlyOneMember() {
        var owner: [String: String] = [:]
        for member in members {
            for county in member.counties {
                XCTAssertNil(owner[county.abbr],
                             "\(county.abbr) is in both \(owner[county.abbr] ?? "") and \(member.id)")
                owner[county.abbr] = member.id
            }
        }
        XCTAssertEqual(owner.count, combined.counties.count)
        XCTAssertEqual(Set(owner.keys), Set(combined.counties.map(\.abbr)))
    }

    /// The four never add up to more than the combined entry counts, whatever
    /// the mix of bands and modes.
    func testTheMembersNeverOutrunTheCombinedTotal() {
        let qsos = [
            qso(band: .m160, their: "CTNAU"),        // NE ignores 160 m
            qso(mode: .digital, their: "INMRN"),     // IN ignores digital
            qso(band: .m6, their: "AZAPH"),          // 7QP has no 6 m
            qso(band: .m6, their: "NDE"),            // DE does
            qso(their: "INADA"),
            qso(their: "ORDES"),
            qso(their: "MAMID"),
            qso(their: "TX"),                        // not in the region at all
        ]
        let lines = split(qsos)
        let memberTotal = lines.reduce(0) { $0 + $1.validQSOs }
        let combinedTotal = ScoreEngine.score(log: log(qsos), party: combined).validQSOs
        XCTAssertLessThanOrEqual(memberTotal, combinedTotal)
        XCTAssertGreaterThan(memberTotal, 0)
    }

    /// A contact outside all four regions belongs to no member — the combined
    /// entry already gives an out-of-region entrant no credit for it either.
    func testAContactOutsideAllFourBelongsToNobody() {
        let lines = split([qso(their: "TX"), qso(their: "DX")])
        for line in lines {
            XCTAssertEqual(line.validQSOs, 0, line.party.id)
        }
    }

    /// The combined entry tells an in-region operator to pick their own party,
    /// but nothing stops them selecting it. Scoping by county has to hold
    /// anyway, or `outStateWorksHomeStationsOnly` stops filtering and every
    /// contact counts for all four at once.
    func testAnInRegionLogStillScopesEachMemberToItsOwnCounties() throws {
        var inRegion = log([qso(my: "INMRN", their: "AZAPH"), qso(my: "INMRN", their: "NDE")])
        inRegion.myLocation = .inState(counties: ["INMRN"])
        let lines = CombinedLogSplit.split(log: inRegion, combined: combined, members: members)

        XCTAssertEqual(try line(lines, "sevenqp").validQSOs, 1)
        XCTAssertEqual(try line(lines, "deqp").validQSOs, 1)
        XCTAssertEqual(try line(lines, "inqp").validQSOs, 0, "no Indiana county was worked")
        XCTAssertEqual(try line(lines, "newenglandqp").validQSOs, 0)
    }

    /// An ordinary party combines nothing, so it splits into nothing and every
    /// caller can ask without checking first.
    func testAnOrdinaryPartySplitsIntoNothing() throws {
        let inqp = try XCTUnwrap(PartyCatalog.party(id: "inqp"))
        var log = ContestLog(partyID: "inqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [qso(their: "INMRN")]
        XCTAssertTrue(CombinedLogSplit.split(log: log, combined: inqp, members: []).isEmpty)
    }

    // MARK: The Challenge

    private func combinedRecord(_ qsos: [QSO]) -> ContestRecord {
        let log = log(qsos)
        return ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.make(log: log, party: combined),
            updatedAt: Date(timeIntervalSince1970: 1_777_800_000),
            sourceFileName: nil
        )!
    }

    /// **The headline.** `in7qpne` is not on the Challenge's approved list and
    /// never will be — it is an entry, not a contest — so a combined record
    /// counts for nothing until it is split into the four contests it is made
    /// of.
    func testACombinedRecordCountsForNothingUnsplit() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        let record = combinedRecord([
            qso(their: "INMRN"), qso(call: "W9DEF", their: "INADA"),
            qso(call: "K7ABC", their: "AZAPH"), qso(call: "K7DEF", their: "ORDES"),
            qso(call: "W1ABC", band: .m80, their: "MAMID"),
            qso(call: "W1DEF", band: .m80, their: "CTNAU"),
            qso(call: "K3ABC", their: "NDE"), qso(call: "K3DEF", their: "KDE"),
        ])
        let unsplit = ChallengeStanding.compute(
            records: [record], calendar: calendar, year: 2026,
            partyNames: ["in7qpne": combined.name]
        )
        XCTAssertEqual(unsplit.multiplier, 0)
        XCTAssertEqual(unsplit.qsoSum, 0)
        XCTAssertEqual(unsplit.notApproved.count, 1)
    }

    /// Expanded, the same weekend is what the sponsors say it is: four entries,
    /// four multipliers, every QSO counted once.
    func testACombinedRecordExpandsIntoFourApprovedLines() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        let record = combinedRecord([
            qso(their: "INMRN"), qso(call: "W9DEF", their: "INADA"),
            qso(call: "K7ABC", their: "AZAPH"), qso(call: "K7DEF", their: "ORDES"),
            qso(call: "W1ABC", band: .m80, their: "MAMID"),
            qso(call: "W1DEF", band: .m80, their: "CTNAU"),
            qso(call: "K3ABC", their: "NDE"), qso(call: "K3DEF", their: "KDE"),
        ])
        let expanded = CombinedLogSplit.expand(
            records: [record], parties: [combined] + members
        )
        XCTAssertEqual(Set(expanded.map(\.partyID)),
                       ["inqp", "sevenqp", "newenglandqp", "deqp"],
                       "the combined record is replaced, not added to")

        let standing = ChallengeStanding.compute(
            records: expanded, calendar: calendar, year: 2026
        )
        XCTAssertEqual(standing.multiplier, 4)
        XCTAssertEqual(standing.qsoSum, 8)
        XCTAssertTrue(standing.notApproved.isEmpty)
        XCTAssertTrue(standing.qualifiedForAwards)
    }

    /// A member with only one contact still appears — it is a real entry with a
    /// real QSO, it just does not multiply. The Challenge's own formula counts
    /// QSOs and qualifying entries separately, so the QSO must still sum.
    func testAMemberWithOneQSOSumsButDoesNotMultiply() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        let record = combinedRecord([
            qso(their: "INMRN"), qso(call: "W9DEF", their: "INADA"),
            qso(call: "K3ABC", their: "NDE"),
        ])
        let standing = ChallengeStanding.compute(
            records: CombinedLogSplit.expand(records: [record], parties: [combined] + members),
            calendar: calendar, year: 2026
        )
        XCTAssertEqual(standing.qsoSum, 3)
        XCTAssertEqual(standing.multiplier, 1, "Delaware's single QSO does not multiply")
    }

    /// A member the operator never worked contributes no line at all, rather
    /// than a zero the dashboard would have to explain.
    func testUnworkedMembersProduceNoRecord() {
        let expanded = CombinedLogSplit.expand(
            records: [combinedRecord([qso(their: "NDE"), qso(call: "K3DEF", their: "KDE")])],
            parties: [combined] + members
        )
        XCTAssertEqual(expanded.map(\.partyID), ["deqp"])
        XCTAssertEqual(expanded.first?.snapshot.validQSOs, 2)
    }

    /// Expansion leaves ordinary records exactly as they were — the same
    /// object, not a rebuilt one.
    func testOrdinaryRecordsPassThroughUntouched() throws {
        var log = ContestLog(partyID: "inqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [qso(their: "INMRN"), qso(call: "W9DEF", their: "INADA")]
        let inqp = try XCTUnwrap(PartyCatalog.party(id: "inqp"))
        let record = ContestRecord.make(
            from: log, snapshot: ScoreSnapshot.make(log: log, party: inqp),
            updatedAt: Date(timeIntervalSince1970: 1_777_800_000), sourceFileName: nil
        )!
        XCTAssertEqual(CombinedLogSplit.expand(records: [record], parties: [inqp]), [record])
    }

    /// The identity a member record carries is the member's own, so two years
    /// of combined weekends never collide and a member record merges with a
    /// standalone entry for the same party under the same callsign.
    func testExpandedRecordsCarryTheMembersOwnIdentity() throws {
        let record = combinedRecord([qso(their: "NDE"), qso(call: "K3DEF", their: "KDE")])
        let expanded = try XCTUnwrap(
            CombinedLogSplit.expand(records: [record], parties: [combined] + members).first
        )
        XCTAssertEqual(expanded.identity,
                       ContestRecord.Identity(partyID: "deqp", year: 2026, callsign: "KE5CW"))
        XCTAssertEqual(expanded.qsos.count, 2, "only the rows Delaware counts")
        XCTAssertEqual(expanded.updatedAt, record.updatedAt)
    }
}

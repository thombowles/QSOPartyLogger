import XCTest
@testable import QSOPartyLogger

final class UpcomingContestsTests: XCTestCase {

    private var calendar: ChallengeCalendar!
    private var parties: [PartyDefinition]!

    override func setUpWithError() throws {
        calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        parties = PartyCatalog.loadBundled()
    }

    private func instant(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func upcoming(now: String, records: [ContestRecord] = []) -> [UpcomingContest] {
        UpcomingContests.upcoming(
            now: instant(now), parties: parties, calendar: calendar, records: records
        )
    }

    func testNextContestOnJulyMorningIsAlabama() {
        let list = upcoming(now: "2026-07-25T12:00:00Z")
        let first = try? XCTUnwrap(list.first)
        XCTAssertEqual(first?.partyID, "alqp")
        XCTAssertEqual(first?.dateSource, .partyDefinition)
        XCTAssertEqual(first?.isLive, false)
        XCTAssertEqual(first?.isApproved, true)
        XCTAssertEqual(first?.nextWindow.start, instant("2026-07-25T15:00:00Z"))
        // Sorted by next start: NAQP CW follows on Aug 1 — a bundled
        // non-Challenge contest takes its place in the list like any other —
        // and Maryland-DC after it on Aug 8.
        XCTAssertEqual(list.dropFirst().first?.partyID, "naqpcw")
        XCTAssertEqual(list.dropFirst().first?.isApproved, false)
        XCTAssertEqual(list.dropFirst(2).first?.partyID, "mdc")
    }

    func testLiveWindowIsFlaggedAndStaysFirst() {
        let list = upcoming(now: "2026-07-25T16:00:00Z")   // inside ALQP's window
        XCTAssertEqual(list.first?.partyID, "alqp")
        XCTAssertEqual(list.first?.isLive, true)
    }

    /// Contests the app has no definition for still appear, dated by the
    /// challenge's own calendar and labeled as such.
    ///
    /// **The example is computed, not named.** This test used to hard-code
    /// Louisiana, which stopped being calendar-only the moment LAQP was bundled
    /// — the same rot that moved the user-party fixture three times in one day.
    /// It now asks the calendar for any contest with no bundled party, so it
    /// keeps testing the real behaviour as parties land. When every approved
    /// contest is bundled there is nothing left to test, and it says so rather
    /// than passing vacuously.
    func testCalendarOnlyContestsAppearAsCalendarSourced() throws {
        let bundledIDs = Set(parties.map(\.id))
        let unmapped = calendar.approvedContests.filter {
            $0.partyID == nil || !bundledIDs.contains($0.partyID!)
        }
        try XCTSkipIf(
            unmapped.isEmpty,
            "every approved contest now has a bundled party — nothing is calendar-only"
        )

        let list = UpcomingContests.upcoming(
            now: instant("2026-01-01T00:00:00Z"),
            parties: parties, calendar: calendar, records: []
        )
        let names = Set(unmapped.map(\.name))
        let row = try XCTUnwrap(list.first { names.contains($0.name) },
                                "a calendar-only contest should still be listed")
        XCTAssertNil(row.partyID)
        XCTAssertEqual(row.dateSource, .challengeCalendar)
        XCTAssertEqual(row.isApproved, true)

        // ...while a bundled party in the same list comes from its own schedule.
        let alabama = try XCTUnwrap(list.first { $0.partyID == "alqp" })
        XCTAssertEqual(alabama.dateSource, .partyDefinition)
    }

    /// The calendar's NJQP row is known-wrong (Sep 19); the sponsor says
    /// Sep 12 and the bundled schedule must win.
    func testSponsorScheduleBeatsCalendarForNJQP() throws {
        let list = upcoming(now: "2026-09-01T00:00:00Z")
        let njqp = try XCTUnwrap(list.first { $0.partyID == "njqp" })
        let party = try XCTUnwrap(parties.first { $0.id == "njqp" })
        XCTAssertEqual(njqp.dateSource, .partyDefinition)
        XCTAssertEqual(njqp.nextWindow, party.schedule?.first)
        XCTAssertEqual(njqp.nextWindow.start, instant("2026-09-12T14:00:00Z"))
        // And no phantom duplicate row from the calendar's name.
        XCTAssertEqual(list.filter { $0.name == "New Jersey QSO Party" }.count, 1)
    }

    /// The challenge's approved list spells two contests differently than
    /// their sponsors do: "Maryland/DC QSO Party" for the sponsor's
    /// "Maryland-DC QSO Party", "Washington State Salmon Run" for "Washington
    /// Salmon Run". Both spellings are sourced — the site's list and the
    /// sponsor's own rules — so neither may be hand-edited into agreement, and
    /// dedup by name alone listed each of those contests twice. The calendar
    /// row already carries the bundled party's id; that is what has to claim it.
    ///
    /// **Computed, not named.** Every id-mapped contest is checked, so a
    /// spelling that diverges in some future calendar is caught for free.
    func testCalendarNeverAddsAPhantomRowForABundledParty() throws {
        let scheduled = Set(parties.filter { !($0.schedule ?? []).isEmpty }.map(\.id))
        let mapped = calendar.approvedContests.filter { $0.partyID.map(scheduled.contains) ?? false }
        XCTAssertFalse(mapped.isEmpty, "the calendar maps bundled parties by id")

        let list = upcoming(now: "2026-01-01T00:00:00Z")   // whole season ahead
        let byName = Dictionary(grouping: list, by: \.name)

        for contest in mapped {
            let party = try XCTUnwrap(parties.first { $0.id == contest.partyID })
            let rows = byName[contest.name, default: []]
                + (contest.name == party.name ? [] : byName[party.name, default: []])
            XCTAssertEqual(
                rows.count, 1,
                "\(party.name) (\(party.id)) should list once, got \(rows.map(\.name))"
            )
            XCTAssertEqual(rows.first?.partyID, party.id)
            XCTAssertEqual(rows.first?.dateSource, .partyDefinition)
        }

        // `UpcomingContest.id` is the name — a repeat would also collide in
        // any SwiftUI ForEach over this list.
        XCTAssertEqual(Set(list.map(\.id)).count, list.count, "row ids must be unique")
    }

    func testEnteredThisYearComesFromRecords() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.qsos = [QSO(
            timestampUTC: instant("2026-08-29T15:00:00Z"),
            call: "W0AAA", band: .m20, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "SED"
        )]
        let record = try XCTUnwrap(ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.countsOnly(log: log),
            updatedAt: instant("2026-08-29T15:00:00Z"),
            sourceFileName: nil
        ))

        let list = upcoming(now: "2026-08-01T00:00:00Z", records: [record])
        XCTAssertEqual(list.first { $0.partyID == "ksqp" }?.enteredThisYear, true)
        XCTAssertEqual(list.first { $0.partyID == "tqp" }?.enteredThisYear, false)
    }

    func testSeasonOverYieldsEmptyList() {
        XCTAssertTrue(upcoming(now: "2026-12-01T00:00:00Z").isEmpty)
    }

    /// A user-installed party whose name matches a calendar contest takes
    /// over that row — its (sponsor-sourced) schedule wins, no duplicate.
    ///
    /// **This fixture no longer depends on any party staying unbundled.** It was
    /// Minnesota, then Wisconsin, then Virginia, and each in turn got bundled
    /// and broke it — three rotations in one day. The invariant under test is
    /// only that a party the calendar cannot map *by id* is still matched *by
    /// name*, so the durable way to stage it is to drop the bundled party from
    /// the input and hand in a same-named one under an id the calendar has never
    /// heard of. Nothing here rots when the next party lands.
    func testUserPartyReplacesCalendarRowByName() throws {
        let withoutVirginia = parties.filter { $0.id != "vaqp" }
        XCTAssertEqual(withoutVirginia.count, parties.count - 1, "VAQP is bundled and removed")

        let virginia = try PartyCatalog.decode(Data("""
        {
          "schemaVersion": 1,
          "id": "my-own-virginia",
          "name": "Virginia QSO Party",
          "cabrilloContest": "VAQP",
          "homeState": "VA",
          "countyAbbrLength": 3,
          "validBands": ["80m", "40m", "20m"],
          "points": { "phone": 1, "cw": 2, "digital": 2 },
          "dupeScope": "bandMode",
          "multipliers": {
            "inState":  { "classes": ["county", "state"], "homeStateCountsViaCounty": true, "countScope": "once" },
            "outState": { "classes": ["county"], "homeStateCountsViaCounty": false, "countScope": "once" }
          },
          "bonuses": [],
          "schedule": [ { "start": "2026-03-21T14:00:00Z", "end": "2026-03-22T04:00:00Z" } ],
          "counties": [ { "abbr": "ACC", "name": "Accomack" } ]
        }
        """.utf8))

        let list = UpcomingContests.upcoming(
            now: instant("2026-02-01T00:00:00Z"),
            parties: withoutVirginia + [virginia],
            calendar: calendar,
            records: []
        )
        let rows = list.filter { $0.name == "Virginia QSO Party" }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.partyID, "my-own-virginia")
        XCTAssertEqual(rows.first?.dateSource, .partyDefinition)
        XCTAssertEqual(rows.first?.isApproved, true)
    }
}

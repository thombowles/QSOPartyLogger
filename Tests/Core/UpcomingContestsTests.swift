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
        // Sorted by next start: Maryland-DC follows on Aug 8.
        XCTAssertEqual(list.dropFirst().first?.partyID, "mdc")
    }

    func testLiveWindowIsFlaggedAndStaysFirst() {
        let list = upcoming(now: "2026-07-25T16:00:00Z")   // inside ALQP's window
        XCTAssertEqual(list.first?.partyID, "alqp")
        XCTAssertEqual(list.first?.isLive, true)
    }

    /// Contests the app has no definition for still appear, dated by the
    /// challenge's own calendar and labeled as such.
    func testCalendarOnlyContestsAppearInSpring() {
        let list = upcoming(now: "2026-04-01T00:00:00Z")
        let louisiana = list.first { $0.name == "Louisiana QSO Party" }
        XCTAssertNotNil(louisiana)
        XCTAssertNil(louisiana?.partyID)
        XCTAssertEqual(louisiana?.dateSource, .challengeCalendar)
        XCTAssertEqual(louisiana?.isApproved, true)

        // Bundled parties in the same list come from their own schedules.
        let alabama = list.first { $0.partyID == "alqp" }
        XCTAssertEqual(alabama?.dateSource, .partyDefinition)
        XCTAssertLessThan(
            try XCTUnwrap(louisiana?.nextWindow.start),
            try XCTUnwrap(alabama?.nextWindow.start)
        )
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
    /// Wisconsin stands in for the user-installed party because it is on the
    /// 2026 approved list and **not bundled**, which is what this test needs.
    /// It used to be Minnesota; MNQP became a bundled party on 2026-07-26 and
    /// is now mapped by `partyID`, so it no longer exercises the name path.
    /// Whichever party is used here must be one the calendar cannot map by id.
    func testUserPartyReplacesCalendarRowByName() throws {
        let bundledIDs = Set(parties.map(\.id))
        XCTAssertFalse(bundledIDs.contains("wiqp"),
                       "pick another unbundled approved contest — Wisconsin has been bundled")

        let wisconsin = try PartyCatalog.decode(Data("""
        {
          "schemaVersion": 1,
          "id": "wiqp",
          "name": "Wisconsin QSO Party",
          "cabrilloContest": "WIQP",
          "homeState": "WI",
          "countyAbbrLength": 3,
          "validBands": ["80m", "40m", "20m"],
          "points": { "phone": 1, "cw": 2, "digital": 2 },
          "dupeScope": "bandMode",
          "multipliers": {
            "inState":  { "classes": ["county", "state"], "homeStateCountsViaCounty": true, "countScope": "once" },
            "outState": { "classes": ["county"], "homeStateCountsViaCounty": false, "countScope": "once" }
          },
          "bonuses": [],
          "schedule": [ { "start": "2026-03-15T18:00:00Z", "end": "2026-03-16T01:00:00Z" } ],
          "counties": [ { "abbr": "ADA", "name": "Adams" } ]
        }
        """.utf8))

        let list = UpcomingContests.upcoming(
            now: instant("2026-02-01T00:00:00Z"),
            parties: parties + [wisconsin],
            calendar: calendar,
            records: []
        )
        let rows = list.filter { $0.name == "Wisconsin QSO Party" }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.partyID, "wiqp")
        XCTAssertEqual(rows.first?.dateSource, .partyDefinition)
        XCTAssertEqual(rows.first?.isApproved, true)
    }
}

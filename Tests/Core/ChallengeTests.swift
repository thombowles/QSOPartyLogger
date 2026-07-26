import XCTest
@testable import QSOPartyLogger

final class ChallengeTests: XCTestCase {

    // MARK: Calendar resource

    /// The generated resource carries exactly what the generator asserted:
    /// 47 approved contests, 61 windows, 18 mapped to bundled parties, and
    /// no Maine (not approved for 2026 — see docs/research/sqp_challenge_rules.md).
    func testBundledCalendarLoadsWithAssertedShape() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        XCTAssertEqual(calendar.year, 2026)
        XCTAssertEqual(calendar.approvedContests.count, 47)
        XCTAssertEqual(calendar.approvedContests.flatMap(\.windows).count, 61)

        let mapped = calendar.approvedContests.compactMap(\.partyID)
        XCTAssertEqual(mapped.count, 35)
        let bundledIDs = Set(PartyCatalog.loadBundled().map(\.id))
        XCTAssertEqual(Set(mapped), bundledIDs.subtracting(["meqp"]))

        XCTAssertNil(calendar.approvedContests.first { $0.name.localizedCaseInsensitiveContains("maine") })
        XCTAssertEqual(calendar.contest(partyID: "njqp")?.name, "New Jersey QSO Party")
        for contest in calendar.approvedContests {
            XCTAssertFalse(contest.windows.isEmpty, contest.name)
            for window in contest.windows {
                XCTAssertLessThan(window.start, window.end, contest.name)
            }
        }
    }

    // MARK: Standing fixtures

    private func record(
        partyID: String,
        qsoCount: Int,
        year: Int = 2026,
        callsign: String = "KE5CW"
    ) -> ContestRecord {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = callsign
        log.myLocation = .outOfState(location: "TX")
        let base = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: year, month: 6, day: 1
        ).date!
        log.qsos = (0..<qsoCount).map { index in
            QSO(
                timestampUTC: base.addingTimeInterval(TimeInterval(index) * 60),
                call: "W\(index)ABC",
                band: .m20,
                modeClass: .cw,
                rawMode: "CW",
                rstSent: "599",
                rstRcvd: "599",
                myLoc: "TX",
                theirLoc: "MO"
            )
        }
        return ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.countsOnly(log: log),
            updatedAt: base,
            sourceFileName: nil
        )!
    }

    private func standing(
        _ records: [ContestRecord],
        year: Int = 2026,
        partyNames: [String: String] = [:]
    ) throws -> ChallengeStanding {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        return ChallengeStanding.compute(
            records: records, calendar: calendar, year: year, partyNames: partyNames
        )
    }

    // MARK: The sponsor's formula

    /// "Total Points = (Sum of Individual state QSO party contest QSOs) x
    /// (Number of ... form submission)" with the homepage's floor: a party
    /// needs two contacts "to count as a multiplier" — but its QSOs still sum.
    func testFormulaMatchesSponsorSemantics() throws {
        let result = try standing([
            record(partyID: "ksqp", qsoCount: 100),
            record(partyID: "tqp", qsoCount: 50),
            record(partyID: "cqp", qsoCount: 1),      // adds QSOs, not a multiplier
        ])
        XCTAssertEqual(result.qsoSum, 151)
        XCTAssertEqual(result.multiplier, 2)
        XCTAssertEqual(result.points, 302)
        XCTAssertTrue(result.qualifiedForAwards)      // two parties with ≥ 2 QSOs
        XCTAssertNil(result.level)                    // 302 < Bronze's 500
        XCTAssertEqual(result.nextLevel, ChallengeStanding.awardLevels[0])
        XCTAssertEqual(result.lines.count, 3)
        XCTAssertFalse(try XCTUnwrap(result.lines.first { $0.partyID == "cqp" }).qualifies)
    }

    /// Levels straight from the rules PDF: Bronze 500 | Silver 5,000 |
    /// Gold 10,000 | Platinum 25,000 | Diamond 100,000.
    func testAwardLevelThresholds() throws {
        let expectations: [(qsosPerParty: Int, level: String?)] = [
            (124, nil),          // 496 points
            (125, "Bronze"),     // 500 exactly
            (1_250, "Silver"),   // 5,000
            (2_500, "Gold"),     // 10,000
            (6_250, "Platinum"), // 25,000
            (25_000, "Diamond"), // 100,000
        ]
        for expectation in expectations {
            let result = try standing([
                record(partyID: "ksqp", qsoCount: expectation.qsosPerParty),
                record(partyID: "tqp", qsoCount: expectation.qsosPerParty),
            ])
            XCTAssertEqual(result.points, expectation.qsosPerParty * 4)
            XCTAssertEqual(result.level?.name, expectation.level, "\(expectation)")
        }
    }

    /// "the participant must have participated in at least two state QSO
    /// party contest" — points without two qualifying parties earn no level.
    func testSingleQualifyingPartyGetsNoAwardLevel() throws {
        let result = try standing([record(partyID: "ksqp", qsoCount: 600)])
        XCTAssertEqual(result.points, 600)
        XCTAssertFalse(result.qualifiedForAwards)
        XCTAssertNil(result.level)
    }

    /// Maine is logged and shown, never silently dropped — but it is not on
    /// the 2026 approved list, so it contributes nothing to the score.
    func testMaineIsListedButExcludedFromScore() throws {
        let result = try standing(
            [
                record(partyID: "meqp", qsoCount: 40),
                record(partyID: "ksqp", qsoCount: 10),
            ],
            partyNames: ["meqp": "Maine QSO Party"]
        )
        XCTAssertEqual(result.qsoSum, 10)
        XCTAssertEqual(result.multiplier, 1)
        XCTAssertEqual(result.lines.map(\.partyID), ["ksqp"])
        XCTAssertEqual(result.notApproved.map(\.partyID), ["meqp"])
        XCTAssertEqual(result.notApproved.first?.validQSOs, 40)
    }

    /// A user-installed party the calendar doesn't map by id still counts
    /// when its name matches an approved contest (Minnesota, say).
    func testUserPartyCountsViaNameMatch() throws {
        let result = try standing(
            [
                record(partyID: "mnqp", qsoCount: 30),
                record(partyID: "ksqp", qsoCount: 20),
            ],
            partyNames: ["mnqp": "Minnesota QSO Party"]
        )
        XCTAssertEqual(result.qsoSum, 50)
        XCTAssertEqual(result.multiplier, 2)
        XCTAssertEqual(
            result.lines.first { $0.partyID == "mnqp" }?.contestName,
            "Minnesota QSO Party"
        )
    }

    func testOtherYearsRecordsAreIgnored() throws {
        let result = try standing([
            record(partyID: "ksqp", qsoCount: 100, year: 2025),
            record(partyID: "tqp", qsoCount: 10),
        ])
        XCTAssertEqual(result.qsoSum, 10)
        XCTAssertEqual(result.multiplier, 1)
    }
}

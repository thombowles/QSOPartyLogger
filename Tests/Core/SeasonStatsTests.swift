import XCTest
@testable import QSOPartyLogger

final class SeasonStatsTests: XCTestCase {

    private func snapshot(valid: Int, total: Int?, minutes: Int = 60, mode: String = "cw") -> ScoreSnapshot {
        ScoreSnapshot(
            validQSOs: valid,
            dupeCount: 0,
            invalidModeCount: 0,
            outOfScopeCount: 0,
            qsosByMode: [mode: valid],
            qsosByBand: ["20m": valid],
            countiesWorked: valid / 2,
            operatingMinutes: minutes,
            figures: total.map {
                ScoreSnapshot.Figures(
                    qsoPoints: valid, multiplierCount: 1, multiplierCap: nil,
                    bonusPoints: 0, categoryFactor: 1, total: $0, multsByClass: [:]
                )
            }
        )
    }

    private func record(
        partyID: String,
        year: Int,
        month: Int = 6,
        snapshot: ScoreSnapshot
    ) -> ContestRecord {
        let date = DateComponents(
            calendar: Calendar(identifier: .gregorian),
            timeZone: TimeZone(identifier: "UTC"),
            year: year, month: month, day: 10
        ).date!
        return ContestRecord(
            partyID: partyID,
            year: year,
            callsign: "KE5CW",
            station: StationProfile(),
            myLocation: .outOfState(location: "TX"),
            qsos: [QSO(
                timestampUTC: date,
                call: "W0AAA", band: .m20, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MO"
            )],
            snapshot: snapshot,
            updatedAt: date,
            sourceFileName: nil
        )
    }

    func testSeasonTotalsAggregateAcrossContests() {
        let records = [
            record(partyID: "ksqp", year: 2026, month: 8, snapshot: snapshot(valid: 100, total: 5000, minutes: 300)),
            record(partyID: "tqp", year: 2026, month: 9, snapshot: snapshot(valid: 50, total: 1200, minutes: 120, mode: "phone")),
            record(partyID: "mnqp", year: 2026, month: 2, snapshot: snapshot(valid: 10, total: nil, minutes: 30)),
        ]
        let stats = SeasonStats.compute(records: records, year: 2026)

        XCTAssertEqual(stats.contests, 3)
        XCTAssertEqual(stats.validQSOs, 160)
        XCTAssertEqual(stats.combinedScore, 6200)
        XCTAssertEqual(stats.scoredContests, 2)          // the counts-only one isn't scored
        XCTAssertEqual(stats.operatingMinutes, 450)
        XCTAssertEqual(stats.qsosByMode, ["cw": 110, "phone": 50])
        XCTAssertEqual(stats.countiesWorked, 80)
        // Rows in season order (February first).
        XCTAssertEqual(stats.rows.map(\.partyID), ["mnqp", "ksqp", "tqp"])
    }

    func testOtherYearsExcluded() {
        let records = [
            record(partyID: "ksqp", year: 2025, snapshot: snapshot(valid: 100, total: 5000)),
            record(partyID: "tqp", year: 2026, snapshot: snapshot(valid: 5, total: 100)),
        ]
        let stats = SeasonStats.compute(records: records, year: 2026)
        XCTAssertEqual(stats.contests, 1)
        XCTAssertEqual(stats.validQSOs, 5)
    }

    func testEmptyYearIsAllZeroes() {
        let stats = SeasonStats.compute(records: [], year: 2026)
        XCTAssertEqual(stats.contests, 0)
        XCTAssertEqual(stats.validQSOs, 0)
        XCTAssertEqual(stats.combinedScore, 0)
        XCTAssertEqual(stats.operatingMinutes, 0)
        XCTAssertTrue(stats.rows.isEmpty)
    }

    /// The all-years view for one party: ascending years for the trend chart.
    func testPartyTrendAscendingYears() {
        let records = [
            record(partyID: "ksqp", year: 2026, snapshot: snapshot(valid: 120, total: 6000)),
            record(partyID: "ksqp", year: 2024, snapshot: snapshot(valid: 80, total: 3000)),
            record(partyID: "tqp", year: 2025, snapshot: snapshot(valid: 9, total: 90)),
            record(partyID: "ksqp", year: 2025, snapshot: snapshot(valid: 100, total: 4500)),
        ]
        let trend = SeasonStats.partyTrend(records: records, partyID: "ksqp")
        XCTAssertEqual(trend.map(\.year), [2024, 2025, 2026])
        XCTAssertEqual(trend.map(\.snapshot.validQSOs), [80, 100, 120])
    }
}

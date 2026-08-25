import XCTest
@testable import QSOPartyLogger

/// The activation panel's arithmetic (spec 2026-08-25 §activation panel):
/// unique (call, band, mode) per own park per UTC day, the stricter reading
/// of POTA's ten-QSO rule — the open question is banked in
/// docs/research/pota/SOURCES.md.
final class PotaStatsTests: XCTestCase {

    private func qso(call: String, band: Band = .m20, mode: ModeClass = .cw,
                     day: Int = 0, second: TimeInterval = 0,
                     groupID: UUID = UUID(),
                     myParks: [String]? = ["US-1111"],
                     theirParks: [String]? = nil) -> QSO {
        QSO(groupID: groupID,
            timestampUTC: Date(timeIntervalSince1970: Double(day) * 86_400 + second),
            call: call, band: band, modeClass: mode, rawMode: "CW",
            sent: [:], rcvd: [:], myPotaRefs: myParks, theirPotaRefs: theirParks)
    }

    func testCountsUniqueTriplesForTodayOnly() {
        let now = Date(timeIntervalSince1970: 86_400 + 7200) // day 1, 02:00Z
        let stats = PotaStats.compute(
            qsos: [
                qso(call: "W1AW", day: 0),                    // yesterday
                qso(call: "W1AW", day: 1),                    // today
                qso(call: "W1AW", day: 1, second: 600),       // dupe triple
                qso(call: "W1AW", band: .m40, day: 1),        // new band
                qso(call: "K5X", mode: .phone, day: 1),       // new call+mode
            ],
            ownParks: ["US-1111"], now: now)
        XCTAssertEqual(stats.parks.count, 1)
        XCTAssertEqual(stats.parks[0].park, "US-1111")
        XCTAssertEqual(stats.parks[0].uniqueToday, 3)
    }

    func testEachParkCountsItsOwnRows() {
        let now = Date(timeIntervalSince1970: 3600)
        let stats = PotaStats.compute(
            qsos: [
                qso(call: "W1AW", myParks: ["US-1111", "US-2222"]),
                qso(call: "K5X", myParks: ["US-2222"]),
            ],
            ownParks: ["US-1111", "US-2222"], now: now)
        XCTAssertEqual(stats.parks.map(\.park), ["US-1111", "US-2222"])
        XCTAssertEqual(stats.parks.map(\.uniqueToday), [1, 2])
    }

    func testP2PTalliesWholeLogByContactNotRow() {
        let now = Date(timeIntervalSince1970: 0)
        let shared = UUID()
        let stats = PotaStats.compute(
            qsos: [
                // Two rows of one county-line contact share a groupID and
                // must count once.
                qso(call: "W1AW", groupID: shared, theirParks: ["US-3333", "US-4444"]),
                qso(call: "W1AW", second: 60, groupID: shared, theirParks: ["US-3333"]),
                qso(call: "N0C", second: 120),
            ],
            ownParks: ["US-1111"], now: now)
        XCTAssertEqual(stats.p2pContacts, 1)
        XCTAssertEqual(stats.p2pDistinctParks, 2)
    }

    func testUTCMidnightCountdown() {
        XCTAssertEqual(PotaStats.secondsToUTCMidnight(
            now: Date(timeIntervalSince1970: 86_400 - 1800)), 1800)
        XCTAssertEqual(PotaStats.secondsToUTCMidnight(
            now: Date(timeIntervalSince1970: 0)), 86_400)
    }
}

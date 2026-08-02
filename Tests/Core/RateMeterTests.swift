import XCTest
@testable import QSOPartyLogger

/// What the sidebar's rate column reports, and — more importantly — when it
/// refuses to report anything.
///
/// A rate meter's failure mode is not being wrong by a few per hour. It is
/// showing a number from twenty minutes ago as though it were current, or
/// claiming 120/hr off two contacts ten seconds apart. Both read as fact at a
/// glance and both change what the operator does next, so the thresholds below
/// are the point of the type, not defensive trimming around it.
///
/// Every fixture pins a fixed `now`. `RateMeter` never reads a clock, which is
/// why these can assert exact figures instead of ranges.
final class RateMeterTests: XCTestCase {

    /// Exactly the top of a UTC hour: 1_791_000_000 / 3600 = 497_500.0.
    /// The clock-hour tests depend on that, so it is asserted rather than
    /// trusted.
    private let hourTop = Date(timeIntervalSince1970: 1_791_000_000)

    func testFixtureBaseIsATopOfHour() {
        XCTAssertEqual(hourTop.timeIntervalSince1970.truncatingRemainder(dividingBy: 3600), 0)
    }

    /// `n` timestamps bound `n−1` intervals: ten QSOs one minute apart span
    /// nine minutes, not ten. Counting them as ten reports 66.7/hr for an
    /// operator who is plainly running exactly one per minute.
    func testTenQSOsOneMinuteApartReadSixtyPerHour() {
        let stamps = (0..<10).map { hourTop.addingTimeInterval(Double($0) * 60) }
        let reading = RateMeter.reading(timestamps: stamps, now: stamps.last!)

        XCTAssertEqual(reading.lastTen, 60)
    }

    /// The window ends at `now`, not at the last QSO — so it decays while the
    /// operator sits idle instead of reporting a dead run as a live one. Nine
    /// QSOs in eighteen minutes is half of nine in nine.
    func testLastTenDecaysWhileIdle() {
        let stamps = (0..<10).map { hourTop.addingTimeInterval(Double($0) * 60) }
        let reading = RateMeter.reading(
            timestamps: stamps, now: hourTop.addingTimeInterval(1080)
        )

        XCTAssertEqual(reading.lastTen, 30)
    }

    func testEmptyLogReportsNoExtrapolationsAndZeroCounts() {
        let reading = RateMeter.reading(timestamps: [], now: hourTop)

        XCTAssertNil(reading.lastTen)
        XCTAssertNil(reading.onAir)
        XCTAssertEqual(reading.lastHour, 0)
        XCTAssertEqual(reading.thisHour.count, 0)
        XCTAssertNil(reading.thisHour.projected)
    }

    /// One contact is a count, never a rate: there is no interval to divide by.
    func testSingleQSOCountsButExtrapolatesNothing() {
        let reading = RateMeter.reading(
            timestamps: [hourTop], now: hourTop.addingTimeInterval(600)
        )

        XCTAssertNil(reading.lastTen)
        XCTAssertNil(reading.onAir)
        XCTAssertEqual(reading.lastHour, 1)
        XCTAssertEqual(reading.thisHour.count, 1)
    }

    /// Two QSOs are enough for `lastTen`: one interval is a real measurement.
    func testLastTenNeedsOnlyTwoQSOs() {
        let stamps = [hourTop, hourTop.addingTimeInterval(60)]
        let reading = RateMeter.reading(timestamps: stamps, now: stamps.last!)

        XCTAssertEqual(reading.lastTen, 60)
    }

    /// `ScoreSnapshot.operatingMinutes` floors at one minute, so without a
    /// threshold two QSOs ten seconds apart would claim 120/hr.
    func testOnAirStaysSilentBelowFiveOperatingMinutes() {
        let stamps = [hourTop, hourTop.addingTimeInterval(10)]
        let reading = RateMeter.reading(timestamps: stamps, now: stamps.last!)

        XCTAssertNil(reading.onAir)
    }

    func testOnAirReportsOnceThereAreFiveOperatingMinutes() {
        let stamps = [hourTop, hourTop.addingTimeInterval(360)]
        let reading = RateMeter.reading(timestamps: stamps, now: stamps.last!)

        // Two QSOs across six on-air minutes.
        XCTAssertEqual(reading.onAir, 20)
    }

    /// Two QSOs three minutes into the hour project to 40/hr on almost no
    /// evidence, so the projection waits.
    func testHourProjectionWaitsForFiveElapsedMinutes() {
        let stamps = [hourTop, hourTop.addingTimeInterval(120)]
        let early = RateMeter.reading(
            timestamps: stamps, now: hourTop.addingTimeInterval(240)
        )
        let later = RateMeter.reading(
            timestamps: stamps, now: hourTop.addingTimeInterval(300)
        )

        XCTAssertNil(early.thisHour.projected)
        XCTAssertEqual(early.thisHour.count, 2)
        XCTAssertEqual(later.thisHour.projected, 24)
    }

    /// An hour with nothing in it yet projects nothing — "0 → 0" is noise.
    func testHourProjectionStaysSilentWithNoContacts() {
        let reading = RateMeter.reading(
            timestamps: [], now: hourTop.addingTimeInterval(1800)
        )

        XCTAssertEqual(reading.thisHour.count, 0)
        XCTAssertNil(reading.thisHour.projected)
    }

    /// A county-line contact expands into several rows sharing one timestamp.
    /// A window made entirely of them has no span at all, and dividing by it
    /// yields infinity — which formats as a number and reads as a fact.
    func testCountyLineBurstWithNoSpanReportsNothing() {
        let stamps = Array(repeating: hourTop, count: 10)
        let reading = RateMeter.reading(timestamps: stamps, now: hourTop)

        XCTAssertNil(reading.lastTen)
        XCTAssertEqual(reading.lastHour, 10)
    }

    /// The clock-hour count resets at the top of the hour; the trailing
    /// 60-minute window does not — that is why both rows exist.
    func testClockHourResetsWhereTheTrailingWindowDoesNot() {
        let stamps = [
            hourTop.addingTimeInterval(-600),
            hourTop.addingTimeInterval(300),
        ]
        let reading = RateMeter.reading(
            timestamps: stamps, now: hourTop.addingTimeInterval(300)
        )

        XCTAssertEqual(reading.thisHour.count, 1)
        XCTAssertEqual(reading.lastHour, 2)
    }

    /// Six QSOs, ten hours off, six more. Wall-clock elapsed would report
    /// 1/hr; the 30-minute off-time rule reports what the operator actually
    /// did while in the chair.
    func testOnAirIgnoresAnOvernightBreak() {
        let first = (0..<6).map { hourTop.addingTimeInterval(Double($0) * 60) }
        let resume = hourTop.addingTimeInterval(36_000)
        let second = (0..<6).map { resume.addingTimeInterval(Double($0) * 60) }
        let reading = RateMeter.reading(timestamps: first + second, now: second.last!)

        // Two five-minute sessions: 12 QSOs across 10 on-air minutes.
        XCTAssertEqual(reading.onAir, 72)
    }

    /// The trailing window is the one figure that falls to zero when the
    /// operator walks away, which is the whole reason it is not extrapolated.
    func testTrailingHourFallsToZeroAfterAnHourOffTheAir() {
        let stamps = (0..<6).map { hourTop.addingTimeInterval(Double($0) * 60) }
        // An hour past the *last* QSO, not the first — the window trails `now`.
        let reading = RateMeter.reading(
            timestamps: stamps, now: stamps.last!.addingTimeInterval(3700)
        )

        XCTAssertEqual(reading.lastHour, 0)
    }

    /// Clock skew or a hand-edited log can stamp a row in the future. It must
    /// not inflate a window it has not happened in yet.
    func testFutureStampedRowsAreExcluded() {
        let stamps = [
            hourTop,
            hourTop.addingTimeInterval(300),
            hourTop.addingTimeInterval(7200),
        ]
        let reading = RateMeter.reading(
            timestamps: stamps, now: hourTop.addingTimeInterval(600)
        )

        XCTAssertEqual(reading.lastHour, 2)
        XCTAssertEqual(reading.thisHour.count, 2)
    }

    /// Timestamps arrive in whatever order the log holds them.
    func testUnsortedTimestampsAreHandled() {
        let stamps = (0..<10).map { hourTop.addingTimeInterval(Double($0) * 60) }
        let reading = RateMeter.reading(timestamps: stamps.reversed(), now: stamps.last!)

        XCTAssertEqual(reading.lastTen, 60)
    }
}

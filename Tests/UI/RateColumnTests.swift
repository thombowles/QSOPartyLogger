import XCTest
@testable import QSOPartyLogger

/// How a `RateMeter.Reading` reads in the score card's right-hand column.
///
/// The distinction these tests exist to protect: a **count** always shows a
/// number, because zero is a true and useful answer — the run died — while an
/// **extrapolation** with nothing behind it shows `—` and says why in its
/// tooltip. A rate meter that prints a confident figure from one contact is
/// worse than one that prints nothing.
final class RateColumnTests: XCTestCase {

    private func reading(
        lastTen: Int? = nil,
        lastHour: Int = 0,
        thisHour: RateMeter.ThisHour = RateMeter.ThisHour(),
        onAir: Int? = nil
    ) -> RateMeter.Reading {
        RateMeter.Reading(
            lastTen: lastTen, lastHour: lastHour, thisHour: thisHour, onAir: onAir
        )
    }

    func testFourRowsInAFixedOrder() {
        let rows = RateColumn.rows(reading())

        XCTAssertEqual(rows.map(\.label), ["Last 10", "60 min", "Hour", "On air"])
    }

    func testRatesRenderAsBareNumbers() {
        let rows = RateColumn.rows(
            reading(
                lastTen: 42,
                lastHour: 38,
                thisHour: RateMeter.ThisHour(count: 15, minutesElapsed: 23, projected: 39),
                onAir: 31
            )
        )

        XCTAssertEqual(rows.map(\.value), ["42", "38", "15→39", "31"])
    }

    /// Zero contacts in the last hour is the single most actionable thing this
    /// column can say, so it must never be blanked.
    func testTrailingHourShowsZeroRatherThanADash() {
        let rows = RateColumn.rows(reading(lastHour: 0))

        XCTAssertEqual(rows[1].value, "0")
    }

    func testExtrapolationsWithoutEvidenceShowADash() {
        let rows = RateColumn.rows(reading(lastTen: nil, onAir: nil))

        XCTAssertEqual(rows[0].value, "—")
        XCTAssertEqual(rows[3].value, "—")
    }

    /// A dash with no explanation is just a broken-looking display.
    func testADashExplainsItselfInTheTooltip() {
        let rows = RateColumn.rows(reading(lastTen: nil, onAir: nil))

        XCTAssertTrue(rows[0].help.contains("two contacts"), rows[0].help)
        XCTAssertTrue(rows[3].help.contains("five minutes"), rows[3].help)
    }

    /// The elapsed minutes were dropped from the label to keep the column
    /// aligned, so the tooltip is the only place they survive.
    func testHourTooltipCarriesTheElapsedMinutesAndThePace() {
        let rows = RateColumn.rows(
            reading(thisHour: RateMeter.ThisHour(count: 15, minutesElapsed: 23, projected: 39))
        )

        XCTAssertTrue(rows[2].help.contains("23 minutes"), rows[2].help)
        XCTAssertTrue(rows[2].help.contains("39"), rows[2].help)
    }

    func testHourShowsTheCountAloneBeforeItCanProject() {
        let rows = RateColumn.rows(
            reading(thisHour: RateMeter.ThisHour(count: 2, minutesElapsed: 3, projected: nil))
        )

        XCTAssertEqual(rows[2].value, "2")
        XCTAssertFalse(rows[2].help.contains("on pace"), rows[2].help)
    }

    /// The off-time rule is the reason this figure differs from wall-clock
    /// average, so it is named where the operator can find it.
    func testOnAirTooltipNamesTheOffTimeRule() {
        let rows = RateColumn.rows(reading(onAir: 31))

        XCTAssertTrue(rows[3].help.contains("30 minutes"), rows[3].help)
    }
}

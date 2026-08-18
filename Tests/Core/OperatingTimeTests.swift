import XCTest
@testable import QSOPartyLogger

final class OperatingTimeTests: XCTestCase {
    private func row(_ hhmm: String, day: Int = 1) -> QSO {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"; f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return QSO(timestampUTC: f.date(from: "2026-11-0\(day) \(hhmm)")!, call: "W1AW", band: .m20, modeClass: .cw,
                   rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "NTX", theirLoc: "CT")
    }

    func testSweepstakesPackageExample() {
        let ss = OperatingTimeRule(maxMinutes: 24 * 60, minOffMinutes: 30)
        let counted = OperatingTime.compute(rows: [row("0100"), row("0114"), row("0145")], rule: ss)
        XCTAssertEqual(counted.offMinutes, 30)          // 0115 … 0144
        XCTAssertEqual(counted.operatedMinutes, 14)
        XCTAssertTrue(counted.outOfTimeRowIDs.isEmpty)
        let notOff = OperatingTime.compute(rows: [row("0100"), row("0114"), row("0144")], rule: ss)
        XCTAssertEqual(notOff.offMinutes, 0)            // 29 empty minutes count as operating
        XCTAssertEqual(notOff.operatedMinutes, 44)
    }

    func testWPXFAQExample() {
        let wpx = OperatingTimeRule(maxMinutes: 36 * 60, minOffMinutes: 60)
        XCTAssertEqual(OperatingTime.compute(rows: [row("0900"), row("1001")], rule: wpx).offMinutes, 60)
        XCTAssertEqual(OperatingTime.compute(rows: [row("0900"), row("1001")], rule: wpx).operatedMinutes, 0)
        XCTAssertEqual(OperatingTime.compute(rows: [row("0900"), row("1000")], rule: wpx).operatedMinutes, 60)
    }

    func testRowsPastTheLimitAreOutOfTime() {
        let rule = OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30)
        let rows = [row("0000"), row("0030"), row("0100"), row("0101"), row("0300"), row("0301")]
        let r = OperatingTime.compute(rows: rows, rule: rule)
        XCTAssertEqual(r.outOfTimeRowIDs, Set([rows[3].id, rows[4].id, rows[5].id]))
        XCTAssertEqual(r.operatedMinutes, 60)           // the meter stops at the limit
        XCTAssertEqual(r.cutoff, rows[2].timestampUTC)  // the last row that still counted
    }

    func testEmptyAndSingleRow() {
        let rule = OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30)
        XCTAssertEqual(OperatingTime.compute(rows: [], rule: rule), .zero)
        let one = OperatingTime.compute(rows: [row("0000")], rule: rule)
        XCTAssertEqual(one.operatedMinutes, 0)
        XCTAssertNil(one.cutoff)
    }

    func testCrossesMidnight() {
        let rule = OperatingTimeRule(maxMinutes: 24 * 60, minOffMinutes: 30)
        let r = OperatingTime.compute(rows: [row("2350"), row("0010", day: 2)], rule: rule)
        XCTAssertEqual(r.operatedMinutes, 20)
    }

    func testOffPeriodsAreTheEmptyMinutesBetweenTwoRows() {
        // SS package: rows at 0114 and 0145 → 0115–0144 is 30 empty minutes and counts as off time.
        let day = Date(timeIntervalSince1970: 1_793_491_200)   // 2026-11-01 00:00:00Z
        func at(_ hhmm: Int) -> Date { day.addingTimeInterval(TimeInterval((hhmm / 100) * 3600 + (hhmm % 100) * 60)) }
        let rows = [QSO(timestampUTC: at(0114), call: "A", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "KS"),
                    QSO(timestampUTC: at(0145), call: "B", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "KS"),
                    QSO(timestampUTC: at(0200), call: "C", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "KS")]
        let r = OperatingTime.compute(rows: rows, rule: OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 30))
        XCTAssertEqual(r.offMinutes, 30)
        XCTAssertEqual(r.offPeriods, [OperatingTime.OffPeriod(start: at(0115), end: at(0144))])
        let short = OperatingTime.compute(rows: rows, rule: OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 31))
        XCTAssertEqual(short.offPeriods, [], "0115–0144 is 30 minutes; a 31-minute rule does not count it")
    }

    /// `ContestDefinition.validate` refuses a rule with `minOffMinutes` below
    /// 1, but a rule built in code can still say 0: two rows a minute apart
    /// have no empty minute between them, and that must not become an
    /// inverted off period (start after end) — nor any off period at all.
    func testZeroEmptyMinutesNeverMakeAnOffPeriod() {
        let r = OperatingTime.compute(rows: [row("0100"), row("0101"), row("0102")], rule: OperatingTimeRule(maxMinutes: 60, minOffMinutes: 0))
        XCTAssertEqual(r.offPeriods, [])
        XCTAssertEqual(r.offMinutes, 0)
    }
}

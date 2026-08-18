import XCTest
@testable import QSOPartyLogger

final class OperatingTimeTests: XCTestCase {
    private func row(_ hhmm: String, day: Int = 1) -> QSO {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"; f.timeZone = TimeZone(identifier: "UTC")
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
}

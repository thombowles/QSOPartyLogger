import XCTest
@testable import QSOPartyLogger

/// The additive POTA dupe dimensions (spec 2026-08-25 decision 9): the UTC
/// day and the own-park set join the key only when the rule asks. Both
/// default false, so every party's key is byte-for-byte today's.
final class DupeRuleScopeTests: XCTestCase {

    private func qso(call: String = "W1AW", band: Band = .m20,
                     mode: ModeClass = .cw, at t: TimeInterval,
                     myParks: [String]? = nil) -> QSO {
        QSO(timestampUTC: Date(timeIntervalSince1970: t), call: call,
            band: band, modeClass: mode, rawMode: "CW",
            sent: [:], rcvd: [:], myPotaRefs: myParks)
    }

    func testFlagsDefaultFalseAndDecodeAbsent() throws {
        let rule = try JSONDecoder().decode(
            DupeRule.self, from: Data(#"{"scope": "bandMode"}"#.utf8))
        XCTAssertFalse(rule.utcDay)
        XCTAssertFalse(rule.perMyPark)
        XCTAssertEqual(rule, DupeRule(scope: .bandMode))
    }

    func testPartyDefaultKeyUnchangedByNewFields() {
        let a = qso(at: 0), b = qso(at: 86_400 * 3, myParks: ["US-1111"])
        // Same call/band/mode: with .partyDefault these were dupes before
        // the fields existed and must still be.
        XCTAssertEqual(DupeChecker.key(a, rule: .partyDefault),
                       DupeChecker.key(b, rule: .partyDefault))
    }

    func testUtcDaySplitsTheKeyAtMidnightUTC() {
        let rule = DupeRule(scope: .bandMode, utcDay: true)
        let lateSunday = qso(at: 86_399)          // 1970-01-01 23:59:59Z
        let earlyMonday = qso(at: 86_401)         // 1970-01-02 00:00:01Z
        let sameDay = qso(at: 3600)
        XCTAssertNotEqual(DupeChecker.key(lateSunday, rule: rule),
                          DupeChecker.key(earlyMonday, rule: rule))
        XCTAssertEqual(DupeChecker.key(lateSunday, rule: rule),
                       DupeChecker.key(sameDay, rule: rule))
    }

    func testPerMyParkSplitsARove() {
        let rule = DupeRule(scope: .bandMode, perMyPark: true)
        let atFirstPark = qso(at: 0, myParks: ["US-1111"])
        let atSecondPark = qso(at: 60, myParks: ["US-2222"])
        let backAtFirst = qso(at: 120, myParks: ["US-1111"])
        XCTAssertNotEqual(DupeChecker.key(atFirstPark, rule: rule),
                          DupeChecker.key(atSecondPark, rule: rule))
        XCTAssertEqual(DupeChecker.key(atFirstPark, rule: rule),
                       DupeChecker.key(backAtFirst, rule: rule))
    }

    func testPerMyParkIsOrderAndCaseInsensitive() {
        let rule = DupeRule(scope: .bandMode, perMyPark: true)
        let a = qso(at: 0, myParks: ["US-1111", "US-2222"])
        let b = qso(at: 60, myParks: ["us-2222", "us-1111"])
        XCTAssertEqual(DupeChecker.key(a, rule: rule),
                       DupeChecker.key(b, rule: rule))
    }

    func testPotaShapeEndToEnd() {
        // POTA's rule: bandMode + utcDay + perMyPark. Second contact same
        // day/park/band/mode is the dupe; a new UTC day or a new park is not.
        let rule = DupeRule(scope: .bandMode, utcDay: true, perMyPark: true)
        let log = [
            qso(at: 0, myParks: ["US-1111"]),
            qso(at: 600, myParks: ["US-1111"]),            // dupe
            qso(at: 1200, myParks: ["US-2222"]),           // rove: counts
            qso(at: 86_500, myParks: ["US-1111"]),         // next day: counts
        ]
        let firsts = DupeChecker.firstOccurrenceIDs(log, rule: rule)
        XCTAssertEqual(firsts.count, 3)
        XCTAssertFalse(firsts.contains(log[1].id))
    }

    func testUtcDayIndexIsPlainUnixArithmetic() {
        XCTAssertEqual(DupeChecker.utcDayIndex(Date(timeIntervalSince1970: 0)), 0)
        XCTAssertEqual(DupeChecker.utcDayIndex(Date(timeIntervalSince1970: 86_399)), 0)
        XCTAssertEqual(DupeChecker.utcDayIndex(Date(timeIntervalSince1970: 86_400)), 1)
        XCTAssertEqual(DupeChecker.utcDayIndex(Date(timeIntervalSince1970: -1)), -1)
    }
}

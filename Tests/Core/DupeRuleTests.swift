import XCTest
@testable import QSOPartyLogger

final class DupeRuleTests: XCTestCase {
    private func qso(_ call: String, _ band: Band, _ mode: ModeClass, my: String = "LIN", their: String = "TX", minute: Int) -> QSO {
        QSO(timestampUTC: Date(timeIntervalSince1970: TimeInterval(minute * 60)), call: call, band: band, modeClass: mode,
            rawMode: mode == .cw ? "CW" : "SSB", rstSent: "599", rstRcvd: "599", myLoc: my, theirLoc: their)
    }

    func testPartyDefaultEqualsTheLegacyKey() {
        let log = [qso("W1AW", .m20, .cw, minute: 0), qso("W1AW", .m20, .cw, minute: 1),
                   qso("W1AW", .m20, .cw, their: "OK", minute: 2), qso("W1AW", .m40, .cw, minute: 3),
                   qso("W1AW", .m20, .phone, minute: 4)]
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: .partyDefault), DupeChecker.firstOccurrenceIDs(log))
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: .partyDefault).count, 4)
    }

    func testContestScopeIsOncePerContest() {
        let log = [qso("W1AW", .m20, .cw, minute: 0), qso("W1AW", .m40, .cw, minute: 1), qso("W1AW", .m20, .phone, minute: 2),
                   qso("W1AW", .m20, .cw, their: "OK", minute: 3), qso("K5ZD", .m20, .cw, minute: 4)]
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .contest)).map { $0 }.count, 2)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .contest, locationSensitive: true)).count, 3)
    }

    func testBandScopeIgnoresMode() {
        let log = [qso("W1AW", .m20, .cw, minute: 0), qso("W1AW", .m20, .phone, minute: 1), qso("W1AW", .m40, .phone, minute: 2)]
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .band)).count, 2)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .bandMode)).count, 3)
    }
}

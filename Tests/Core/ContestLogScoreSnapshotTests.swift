import XCTest
@testable import QSOPartyLogger

/// The score a log carries in its own file — computed at save time with the
/// rules installed then — so the dashboard's past seasons stay frozen when
/// next year's rules land.
final class ContestLogScoreSnapshotTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_770_000_000)  // 2026-02-02

    private func qso(_ call: String, their: String, offset: TimeInterval = 0) -> QSO {
        QSO(
            timestampUTC: t0.addingTimeInterval(offset),
            call: call,
            band: .m20,
            modeClass: .cw,
            rawMode: "CW",
            rstSent: "599",
            rstRcvd: "599",
            myLoc: "SED",
            theirLoc: their
        )
    }

    private func log(partyID: String = "ksqp", qsos: [QSO], completed: Bool = true) -> ContestLog {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = "KE5CW"
        log.myLocation = .inState(counties: ["SED"])
        log.qsos = qsos
        log.setupCompleted = completed
        return log
    }

    // MARK: Codable

    func testSnapshotRoundTripsThroughTheFile() throws {
        var log = log(qsos: [qso("W0AAA", their: "MO")])
        log.scoreSnapshot = ScoreSnapshot.countsOnly(log: log)
        let decoded = try ContestLog.decode(from: try log.encoded())
        XCTAssertEqual(decoded, log)
        XCTAssertEqual(decoded.scoreSnapshot?.validQSOs, 1)

        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: try log.encoded()) as? [String: Any])
        XCTAssertNotNil(object["scoreSnapshot"])
    }

    func testAbsentSnapshotDecodesNilAndNilIsNotWritten() throws {
        let log = log(qsos: [qso("W0AAA", their: "MO")])
        XCTAssertNil(log.scoreSnapshot)
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: try log.encoded()) as? [String: Any])
        XCTAssertNil(object["scoreSnapshot"], "nil is omitted, not written as null")
        XCTAssertNil(try ContestLog.decode(from: try log.encoded()).scoreSnapshot)
    }

    // MARK: Stamping at save

    /// The save path writes the engine's figures when the party is installed.
    func testStampingUsesTheEngineForAnInstalledParty() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        let base = log(qsos: [qso("W0AAA", their: party.counties[0].abbr)])
        let stamped = base.stampingScoreSnapshot()
        let snapshot = try XCTUnwrap(stamped.scoreSnapshot)
        XCTAssertEqual(snapshot.validQSOs, 1)
        XCTAssertGreaterThan(try XCTUnwrap(snapshot.figures).total, 0)
        // Everything else is untouched.
        var expected = stamped
        expected.scoreSnapshot = nil
        XCTAssertEqual(expected, base)
    }

    /// Counts survive when the party's rules aren't installed here; the
    /// score shows as unavailable rather than zero.
    func testStampingIsCountsOnlyForAnUnknownParty() throws {
        let stamped = log(partyID: "no-such-party", qsos: [qso("W0AAA", their: "MO")]).stampingScoreSnapshot()
        let snapshot = try XCTUnwrap(stamped.scoreSnapshot)
        XCTAssertEqual(snapshot.validQSOs, 1)
        XCTAssertNil(snapshot.figures)
    }

    /// A draft — not set up, or nothing logged — carries no score.
    func testStampingLeavesDraftsAlone() {
        XCTAssertNil(log(qsos: [qso("W0AAA", their: "MO")], completed: false).stampingScoreSnapshot().scoreSnapshot)
        XCTAssertNil(log(qsos: []).stampingScoreSnapshot().scoreSnapshot)
    }

    /// Re-stamping replaces a stale snapshot rather than keeping it.
    func testStampingReplacesAStaleSnapshot() throws {
        var log = log(qsos: [qso("W0AAA", their: "MO"), qso("K5BBB", their: "TX", offset: 60)])
        var stale = ScoreSnapshot.countsOnly(log: log)
        stale.validQSOs = 999
        log.scoreSnapshot = stale
        XCTAssertEqual(log.stampingScoreSnapshot().scoreSnapshot?.validQSOs, 2)
    }
}

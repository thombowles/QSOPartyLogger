import XCTest
@testable import QSOPartyLogger

/// The in-memory history value: records read from the logs folder, their
/// identity, and the year/query helpers the dashboard leans on.
final class ContestArchiveTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_770_000_000)  // 2026-02-02

    private func qso(_ call: String, offset: TimeInterval = 0, their: String = "MO") -> QSO {
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

    private func log(partyID: String = "ksqp", callsign: String = "ke5cw", qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = callsign
        log.myLocation = .inState(counties: ["SED"])
        log.qsos = qsos
        return log
    }

    private func record(
        _ log: ContestLog,
        updatedAt: Date,
        sourceFileName: String? = nil
    ) throws -> ContestRecord {
        try XCTUnwrap(ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.countsOnly(log: log),
            updatedAt: updatedAt,
            sourceFileName: sourceFileName
        ))
    }

    // MARK: Identity

    func testRecordIdentityComesFromLog() throws {
        let rec = try record(log(qsos: [qso("W0AAA")]), updatedAt: t0)
        XCTAssertEqual(rec.partyID, "ksqp")
        XCTAssertEqual(rec.callsign, "KE5CW")             // uppercased
        XCTAssertEqual(rec.year, 2026)                    // UTC year of earliest QSO
        XCTAssertEqual(rec.identity, ContestRecord.Identity(partyID: "ksqp", year: 2026, callsign: "KE5CW"))
        XCTAssertEqual(rec.scoreOrigin, .computedNow)     // the default; the folder reader says otherwise
    }

    func testRecordRequiresQSOsAndCallsign() {
        let empty = log(qsos: [])
        XCTAssertNil(ContestRecord.make(
            from: empty, snapshot: ScoreSnapshot.countsOnly(log: empty), updatedAt: t0, sourceFileName: nil
        ))
        let noCall = log(callsign: "", qsos: [qso("W0AAA")])
        XCTAssertNil(ContestRecord.make(
            from: noCall, snapshot: ScoreSnapshot.countsOnly(log: noCall), updatedAt: t0, sourceFileName: nil
        ))
    }

    /// Rows are kept in a deterministic order whatever order the log held them.
    func testRecordRowsAreInCanonicalOrder() throws {
        let later = qso("K5BBB", offset: 60)
        let earlier = qso("W0AAA")
        let rec = try record(log(qsos: [later, earlier]), updatedAt: t0)
        XCTAssertEqual(rec.qsos.map(\.call), ["W0AAA", "K5BBB"])
    }

    // MARK: Year/query helpers

    func testYearsAndRecordsByYear() throws {
        let y2025 = try record(
            log(qsos: [QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_755_400_000),  // 2025 UTC
                call: "W0OLD", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "SED", theirLoc: "MO"
            )]),
            updatedAt: t0
        )
        let y2026 = try record(log(partyID: "tqp", qsos: [qso("N5NEW")]), updatedAt: t0)
        let archive = ContestArchive(records: [y2026, y2025])

        XCTAssertEqual(archive.years, [2026, 2025])        // newest first
        XCTAssertEqual(archive.records(year: 2025).map(\.partyID), ["ksqp"])
        XCTAssertEqual(archive.records(year: 2026).map(\.partyID), ["tqp"])
    }

    /// Season order: chronological, then party, then callsign.
    func testCanonicalOrderIsChronologicalThenPartyThenCall() throws {
        let tqpLater = try record(log(partyID: "tqp", qsos: [qso("N5NEW", offset: 3600)]), updatedAt: t0)
        let ksqp = try record(log(qsos: [qso("W0AAA")]), updatedAt: t0)
        let cqpSameTime = try record(log(partyID: "cqp", qsos: [qso("K6AAA")]), updatedAt: t0)
        XCTAssertEqual(
            ContestArchive.canonicalOrder([tqpLater, ksqp, cqpSameTime]).map(\.partyID),
            ["cqp", "ksqp", "tqp"]
        )
    }
}

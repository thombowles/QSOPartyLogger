import XCTest
@testable import QSOPartyLogger

final class ContestArchiveTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_787_000_000)  // whole seconds

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

    // MARK: Upsert

    func testUpsertReplacesSameIdentityAndAppendsNewOnes() throws {
        // The document keeps stable QSO ids across saves — model that.
        let w0 = qso("W0AAA")
        let first = try record(log(qsos: [w0]), updatedAt: t0)
        var archive = ContestArchive.empty.upserting(first)
        XCTAssertEqual(archive.records.count, 1)

        // Same contest, more QSOs: replaces (union), not a second record.
        let updated = try record(
            log(qsos: [w0, qso("K5BBB", offset: 60)]),
            updatedAt: t0.addingTimeInterval(10)
        )
        archive = archive.upserting(updated)
        XCTAssertEqual(archive.records.count, 1)
        XCTAssertEqual(archive.records[0].qsos.count, 2)

        // Different party: its own record.
        let other = try record(log(partyID: "tqp", qsos: [qso("N5XYZ")]), updatedAt: t0)
        archive = archive.upserting(other)
        XCTAssertEqual(archive.records.count, 2)
    }

    // MARK: Merge (the two-Mac story)

    func testMergeUnionsQSOsByIDWithNewerEditWinning() throws {
        let shared = qso("W0AAA")
        var editedShared = shared
        editedShared.theirLoc = "TX"                       // busted-call/exchange fix on Mac B

        let macA = try record(log(qsos: [shared, qso("K5BBB", offset: 60)]), updatedAt: t0)
        let macB = try record(
            log(qsos: [editedShared, qso("N5CCC", offset: 120)]),
            updatedAt: t0.addingTimeInterval(100)          // B saved later
        )

        let merged = macA.merging(macB)
        XCTAssertEqual(merged.qsos.count, 3)               // union by QSO id
        XCTAssertEqual(merged.qsos.first { $0.id == shared.id }?.theirLoc, "TX")
        XCTAssertEqual(merged.updatedAt, macB.updatedAt)

        // The older side's edit loses.
        let mergedOtherWay = macB.merging(macA)
        XCTAssertEqual(mergedOtherWay.qsos.first { $0.id == shared.id }?.theirLoc, "TX")
    }

    func testMergeIsCommutativeForDistinctTimestamps() throws {
        let a = try record(log(qsos: [qso("W0AAA"), qso("K5BBB", offset: 60)]), updatedAt: t0)
        let b = try record(log(qsos: [qso("N5CCC", offset: 120)]), updatedAt: t0.addingTimeInterval(50))
        XCTAssertEqual(a.merging(b), b.merging(a))
    }

    func testArchiveMergeKeepsBothIdentitiesAndUnionsMatching() throws {
        let ksqpA = try record(log(qsos: [qso("W0AAA")]), updatedAt: t0)
        let ksqpB = try record(log(qsos: [qso("K5BBB", offset: 60)]), updatedAt: t0.addingTimeInterval(5))
        let tqp = try record(log(partyID: "tqp", qsos: [qso("N5XYZ")]), updatedAt: t0)

        let one = ContestArchive.empty.upserting(ksqpA)
        let two = ContestArchive.empty.upserting(ksqpB).upserting(tqp)
        let merged = one.merging(two)

        XCTAssertEqual(merged.records.count, 2)
        let ksqp = try XCTUnwrap(merged.records.first { $0.partyID == "ksqp" })
        XCTAssertEqual(ksqp.qsos.count, 2)
        XCTAssertEqual(merged.merging(one), merged)        // idempotent re-merge
    }

    func testMergeRebuildsSnapshotOnlyWhenQSOSetChanged() throws {
        // Each Mac logged a contact the other doesn't have, so the union
        // outgrows BOTH sides' snapshots.
        let base = qso("W0AAA")
        let recA = try record(log(qsos: [base, qso("K5BBB", offset: 60)]), updatedAt: t0)
        let recB = try record(log(qsos: [base, qso("N5CCC", offset: 120)]), updatedAt: t0.addingTimeInterval(5))

        var rebuiltFor: [String] = []
        let rebuilt = ScoreSnapshot.countsOnly(log: log(qsos: [base]))
        let one = ContestArchive.empty.upserting(recA)

        // Union grows the QSO set beyond what either side's snapshot described.
        let merged = one.merging(ContestArchive.empty.upserting(recB)) { record in
            rebuiltFor.append(record.partyID)
            return rebuilt
        }
        XCTAssertEqual(rebuiltFor, ["ksqp"])
        XCTAssertEqual(merged.records[0].snapshot, rebuilt)

        // Same QSO set on both sides: the newer snapshot stands, no rebuild.
        rebuiltFor = []
        let same = one.merging(ContestArchive.empty.upserting(recA)) { record in
            rebuiltFor.append(record.partyID)
            return rebuilt
        }
        XCTAssertTrue(rebuiltFor.isEmpty)
        XCTAssertEqual(same.records[0].snapshot, recA.snapshot)
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
        let archive = ContestArchive.empty.upserting(y2025).upserting(y2026)

        XCTAssertEqual(archive.years, [2026, 2025])        // newest first
        XCTAssertEqual(archive.records(year: 2025).map(\.partyID), ["ksqp"])
        XCTAssertEqual(archive.records(year: 2026).map(\.partyID), ["tqp"])
    }

    // MARK: Round-trip + forward compatibility

    func testRoundTripPreservesUnknownKeys() throws {
        let rec = try record(log(qsos: [qso("W0AAA")]), updatedAt: t0, sourceFileName: "2026 KSQP.qplog")
        let archive = ContestArchive.empty.upserting(rec)

        // A newer build wrote fields this build doesn't know about.
        var object = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: archive.encoded()) as? [String: Any]
        )
        object["futureEnvelopeField"] = ["nested": ["a", 7]]
        var records = try XCTUnwrap(object["records"] as? [[String: Any]])
        records[0]["futureRecordField"] = "keep-me"
        records[0]["futureNumber"] = 42.5
        object["records"] = records

        let foreign = try JSONSerialization.data(withJSONObject: object)
        let decoded = try ContestArchive.decode(from: foreign)

        // Known fields still decode…
        XCTAssertEqual(decoded.records.count, 1)
        XCTAssertEqual(decoded.records[0].callsign, "KE5CW")
        XCTAssertEqual(decoded.records[0].sourceFileName, "2026 KSQP.qplog")

        // …and the unknown ones survive a rewrite by this build.
        let rewritten = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: decoded.encoded()) as? [String: Any]
        )
        XCTAssertEqual(
            rewritten["futureEnvelopeField"] as? NSObject,
            object["futureEnvelopeField"] as? NSObject
        )
        let rewrittenRecord = try XCTUnwrap((rewritten["records"] as? [[String: Any]])?.first)
        XCTAssertEqual(rewrittenRecord["futureRecordField"] as? String, "keep-me")
        XCTAssertEqual(rewrittenRecord["futureNumber"] as? Double, 42.5)
    }

    func testRoundTripEquality() throws {
        let rec = try record(log(qsos: [qso("W0AAA"), qso("K5BBB", offset: 60)]), updatedAt: t0)
        let archive = ContestArchive.empty.upserting(rec)
        let decoded = try ContestArchive.decode(from: archive.encoded())
        XCTAssertEqual(decoded, archive)
    }
}

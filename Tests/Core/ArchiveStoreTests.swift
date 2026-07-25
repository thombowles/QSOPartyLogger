import XCTest
@testable import QSOPartyLogger

final class ArchiveStoreTests: XCTestCase {

    private var folder: URL!
    private var store: ArchiveStore!
    private let t0 = Date(timeIntervalSince1970: 1_787_000_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchiveStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        store = ArchiveStore(folder: folder)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func record(
        partyID: String = "ksqp",
        qsos: [QSO],
        updatedAt: Date? = nil
    ) throws -> ContestRecord {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = "KE5CW"
        log.myLocation = .inState(counties: ["SED"])
        log.qsos = qsos
        return try XCTUnwrap(ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.countsOnly(log: log),
            updatedAt: updatedAt ?? t0,
            sourceFileName: nil
        ))
    }

    private func qso(_ call: String, offset: TimeInterval = 0) -> QSO {
        QSO(
            timestampUTC: t0.addingTimeInterval(offset),
            call: call,
            band: .m20,
            modeClass: .cw,
            rawMode: "CW",
            rstSent: "599",
            rstRcvd: "599",
            myLoc: "SED",
            theirLoc: "MO"
        )
    }

    func testLoadMissingFileReturnsEmptyArchive() throws {
        let archive = try store.load()
        XCTAssertEqual(archive, .empty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))
    }

    func testUpsertCreatesFileAndRoundTrips() throws {
        let rec = try record(qsos: [qso("W0AAA")])
        let written = try store.upsert(rec)
        XCTAssertEqual(written.records.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.fileURL.path(percentEncoded: false)))
        XCTAssertEqual(try store.load(), written)
    }

    /// The file is shared: a record another Mac synced in between our loads
    /// must survive our next upsert (write path re-reads the disk).
    func testUpsertMergesWithWhatIsAlreadyOnDisk() throws {
        // "Another Mac" wrote a TQP record directly into the shared file.
        let other = ContestArchive.empty.upserting(try record(partyID: "tqp", qsos: [qso("N5XYZ")]))
        try other.encoded().write(to: store.fileURL, options: .atomic)

        // This Mac, whose in-memory view never saw TQP, upserts KSQP.
        let mine = try record(qsos: [qso("W0AAA")])
        let merged = try store.upsert(mine)

        XCTAssertEqual(Set(merged.records.map(\.partyID)), ["ksqp", "tqp"])
        XCTAssertEqual(try store.load(), merged)
    }

    func testSequentialUpsertsFromTwoStoresUnion() throws {
        let storeB = ArchiveStore(folder: folder)
        let shared = qso("W0AAA")

        _ = try store.upsert(try record(qsos: [shared]))
        _ = try storeB.upsert(try record(partyID: "tqp", qsos: [qso("N5XYZ")]))
        let final = try store.upsert(
            try record(qsos: [shared, qso("K5BBB", offset: 60)], updatedAt: t0.addingTimeInterval(10))
        )

        XCTAssertEqual(final.records.count, 2)
        let ksqp = try XCTUnwrap(final.records.first { $0.partyID == "ksqp" })
        XCTAssertEqual(ksqp.qsos.count, 2)
    }

    func testLoadCorruptFileThrows() throws {
        try Data("not json at all {{{".utf8).write(to: store.fileURL, options: .atomic)
        XCTAssertThrowsError(try store.load()) { error in
            guard case ArchiveStoreError.corruptArchive = error else {
                return XCTFail("expected corruptArchive, got \(error)")
            }
        }
    }

    /// A corrupt file is never overwritten — the last good bytes are the
    /// user's to recover.
    func testUpsertRefusesToClobberCorruptFile() throws {
        let garbage = Data("not json at all {{{".utf8)
        try garbage.write(to: store.fileURL, options: .atomic)

        XCTAssertThrowsError(try store.upsert(try record(qsos: [qso("W0AAA")])))
        XCTAssertEqual(try Data(contentsOf: store.fileURL), garbage)
    }

    /// When the disk merge grows the QSO set, the snapshot rebuild hook runs
    /// and its result is what lands in the file.
    func testUpsertRebuildHookRunsWhenDiskMergeGrowsQSOSet() throws {
        let shared = qso("W0AAA")
        // Disk copy is NEWER and carries a QSO we don't have…
        let disk = ContestArchive.empty.upserting(
            try record(qsos: [shared, qso("N5CCC", offset: 120)], updatedAt: t0.addingTimeInterval(100))
        )
        try disk.encoded().write(to: store.fileURL, options: .atomic)

        // …and our upsert carries one the disk doesn't have.
        var marker = ScoreSnapshot.countsOnly(log: ContestLog(partyID: "ksqp"))
        marker.operatingMinutes = 999
        var rebuilds = 0
        let merged = try store.upsert(
            try record(qsos: [shared, qso("K5BBB", offset: 60)])
        ) { _ in
            rebuilds += 1
            return marker
        }

        XCTAssertEqual(rebuilds, 1)
        let ksqp = try XCTUnwrap(merged.records.first { $0.partyID == "ksqp" })
        XCTAssertEqual(ksqp.qsos.count, 3)
        XCTAssertEqual(ksqp.snapshot, marker)
        XCTAssertEqual(try store.load(), merged)
    }

    func testMergeInFoldsWholeArchive() throws {
        _ = try store.upsert(try record(qsos: [qso("W0AAA")]))
        let other = ContestArchive.empty
            .upserting(try record(partyID: "tqp", qsos: [qso("N5XYZ")]))
            .upserting(try record(partyID: "cqp", qsos: [qso("K6AAA")]))

        let merged = try store.mergeIn(other)
        XCTAssertEqual(Set(merged.records.map(\.partyID)), ["cqp", "ksqp", "tqp"])
        XCTAssertEqual(try store.load(), merged)
    }
}

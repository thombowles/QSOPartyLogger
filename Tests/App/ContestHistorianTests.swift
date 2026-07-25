import XCTest
@testable import QSOPartyLogger

final class ContestHistorianTests: XCTestCase {

    private var folder: URL!
    private let t0 = Date(timeIntervalSince1970: 1_787_000_000)

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContestHistorianTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func historian(debounceNanos: UInt64 = 50_000_000) -> ContestHistorian {
        ContestHistorian(folderOverride: folder, debounceNanos: debounceNanos)
    }

    private func qso(_ call: String, their: String = "MO", offset: TimeInterval = 0) -> QSO {
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

    private func makeLog(
        partyID: String = "ksqp",
        qsos: [QSO],
        callsign: String = "KE5CW",
        completed: Bool = true
    ) -> ContestLog {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = callsign
        log.myLocation = .inState(counties: ["SED"])
        log.qsos = qsos
        log.setupCompleted = completed
        return log
    }

    // MARK: Debounced archiving

    func testDebounceCoalescesRapidSaves() async throws {
        let historian = historian()
        var log = makeLog(qsos: [qso("W0AAA")])
        await historian.archive(log: log, sourceFileName: "a.qplog")
        log.qsos.append(qso("K5BBB", offset: 60))
        await historian.archive(log: log, sourceFileName: "a.qplog")
        await historian.drain()

        let archive = try ArchiveStore(folder: folder).load()
        XCTAssertEqual(archive.records.count, 1)
        let record = try XCTUnwrap(archive.records.first)
        XCTAssertEqual(record.qsos.count, 2)
        XCTAssertEqual(record.sourceFileName, "a.qplog")
        let writes = await historian.writeCount
        XCTAssertEqual(writes, 1, "two saves inside the debounce window are one write")
    }

    /// With the party installed, the archived snapshot is the engine's — the
    /// dashboard shows exactly what the score sidebar showed.
    func testSnapshotUsesEngineWhenPartyInstalled() async throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        let county = party.counties[0].abbr
        let historian = historian()
        await historian.archive(
            log: makeLog(qsos: [qso("W0AAA", their: county)]),
            sourceFileName: nil
        )
        await historian.drain()

        let record = try XCTUnwrap(ArchiveStore(folder: folder).load().records.first)
        let figures = try XCTUnwrap(record.snapshot.figures)
        XCTAssertGreaterThan(figures.total, 0)
        XCTAssertEqual(record.snapshot.validQSOs, 1)
    }

    func testUnfinishedOrEmptyLogsAreNotArchived() async throws {
        let historian = historian()
        await historian.archive(log: makeLog(qsos: [qso("W0AAA")], completed: false), sourceFileName: nil)
        await historian.archive(log: makeLog(qsos: []), sourceFileName: nil)
        await historian.archive(log: makeLog(qsos: [qso("W0AAA")], callsign: ""), sourceFileName: nil)
        await historian.drain()

        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ArchiveStore(folder: folder).fileURL.path(percentEncoded: false)
        ))
    }

    // MARK: Import

    func testImportFolderIsIdempotentAndReportsFailures() async throws {
        try makeLog(qsos: [qso("W0AAA"), qso("K5BBB", offset: 60)]).encoded()
            .write(to: folder.appendingPathComponent("good1.qplog"))
        try makeLog(partyID: "tqp", qsos: [qso("N5XYZ", their: "HARR")]).encoded()
            .write(to: folder.appendingPathComponent("good2.qplog"))
        try makeLog(qsos: []).encoded()
            .write(to: folder.appendingPathComponent("empty draft.qplog"))
        try Data("junk{{{".utf8)
            .write(to: folder.appendingPathComponent("bad.qplog"))

        let historian = historian()
        let result = await historian.importLogs(from: folder)
        XCTAssertEqual(result.imported, 2)
        XCTAssertEqual(result.failed, ["bad.qplog"])

        let archive = try ArchiveStore(folder: folder).load()
        XCTAssertEqual(archive.records.count, 2)
        XCTAssertEqual(
            archive.records.first { $0.partyID == "ksqp" }?.sourceFileName,
            "good1.qplog"
        )

        // Re-import changes nothing (identity + QSO-id union).
        let again = await historian.importLogs(from: folder)
        XCTAssertEqual(again.imported, 2)
        XCTAssertEqual(try ArchiveStore(folder: folder).load(), archive)
    }

    // MARK: Local → cloud migration

    func testMigrateLocalArchiveIntoChosenFolder() throws {
        let local = FileManager.default.temporaryDirectory
            .appendingPathComponent("ContestHistorianTests-local-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: local) }

        let localLog = makeLog(qsos: [qso("W0AAA")])
        try ArchiveStore(folder: local).upsert(XCTUnwrap(ContestRecord.make(
            from: localLog, snapshot: .countsOnly(log: localLog), updatedAt: t0, sourceFileName: nil
        )))
        let cloudLog = makeLog(partyID: "tqp", qsos: [qso("N5XYZ")])
        try ArchiveStore(folder: folder).upsert(XCTUnwrap(ContestRecord.make(
            from: cloudLog, snapshot: .countsOnly(log: cloudLog), updatedAt: t0, sourceFileName: nil
        )))

        XCTAssertTrue(try ContestHistorian.migrate(localFolder: local, into: folder))
        let merged = try ArchiveStore(folder: folder).load()
        XCTAssertEqual(Set(merged.records.map(\.partyID)), ["ksqp", "tqp"])
        // The local file is marked migrated so it never re-merges…
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: ArchiveStore(folder: local).fileURL.path(percentEncoded: false)
        ))
        // …and a second call is a no-op.
        XCTAssertFalse(try ContestHistorian.migrate(localFolder: local, into: folder))
    }
}

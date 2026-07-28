import XCTest
@testable import QSOPartyLogger

/// The dashboard's per-row ADIF export: an archived record plus the logs
/// folder in, ADIF text and a save-panel filename out. The saved .qplog is
/// the source — never the archive's embedded QSO copy, which can lag a save
/// synced from another Mac.
final class ArchivedAdifExportTests: XCTestCase {

    private var folder: URL!
    private let t = Date(timeIntervalSince1970: 1_788_013_920)  // 2026-08-29 14:32:00Z

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchivedAdifExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeLog(partyID: String = "ksqp") -> ContestLog {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [
            QSO(
                timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14042, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"
            )
        ]
        return log
    }

    private func record(from log: ContestLog, sourceFileName: String?) throws -> ContestRecord {
        try XCTUnwrap(ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.countsOnly(log: log),
            updatedAt: t,
            sourceFileName: sourceFileName
        ))
    }

    func testExportReadsTheSavedFileNotTheArchivedCopy() throws {
        // The record was archived from a one-QSO log; the file on disk has
        // since gained a second contact. Both must export.
        let archived = makeLog()
        var saved = archived
        saved.qsos.append(QSO(
            timestampUTC: t.addingTimeInterval(60), call: "N0R", band: .m40, modeClass: .cw,
            rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MO"
        ))
        try saved.encoded().write(to: folder.appendingPathComponent("2026-08-29 KSQP KE5CW.qplog"))

        let export = try AdifExporter.exportArchived(
            record: record(from: archived, sourceFileName: "2026-08-29 KSQP KE5CW.qplog"),
            folder: folder
        )
        XCTAssertEqual(export.fileName, "2026-08-29 KSQP KE5CW.adi")
        XCTAssertTrue(export.text.contains("<call:4>W0BH"))
        XCTAssertTrue(export.text.contains("<call:3>N0R"))
        XCTAssertTrue(export.text.contains("<contest_id:12>KS-QSO-PARTY"))
        XCTAssertTrue(export.text.contains("<cnty:9>KS,Marion"))
        XCTAssertTrue(export.text.contains("<eor>"))
    }

    func testFileNameSwapsQplogExtensionForAdi() throws {
        let log = makeLog()
        try log.encoded().write(to: folder.appendingPathComponent("My Renamed Log.qplog"))
        let export = try AdifExporter.exportArchived(
            record: record(from: log, sourceFileName: "My Renamed Log.qplog"),
            folder: folder
        )
        XCTAssertEqual(export.fileName, "My Renamed Log.adi")
    }

    func testMissingFileThrows() throws {
        let rec = try record(from: makeLog(), sourceFileName: "gone.qplog")
        XCTAssertThrowsError(try AdifExporter.exportArchived(record: rec, folder: folder)) {
            XCTAssertEqual($0 as? AdifExporter.ArchiveFailure, .logFileMissing)
        }
    }

    func testRecordWithoutSourceFileThrows() throws {
        let rec = try record(from: makeLog(), sourceFileName: nil)
        XCTAssertThrowsError(try AdifExporter.exportArchived(record: rec, folder: folder)) {
            XCTAssertEqual($0 as? AdifExporter.ArchiveFailure, .logFileMissing)
        }
    }

    func testNoLogsFolderThrows() throws {
        let rec = try record(from: makeLog(), sourceFileName: "a.qplog")
        XCTAssertThrowsError(try AdifExporter.exportArchived(record: rec, folder: nil)) {
            XCTAssertEqual($0 as? AdifExporter.ArchiveFailure, .logFileMissing)
        }
    }

    func testUninstalledPartyThrows() throws {
        let log = makeLog(partyID: "zzqp")
        try log.encoded().write(to: folder.appendingPathComponent("z.qplog"))
        let rec = try record(from: log, sourceFileName: "z.qplog")
        XCTAssertThrowsError(try AdifExporter.exportArchived(record: rec, folder: folder)) {
            XCTAssertEqual($0 as? AdifExporter.ArchiveFailure, .partyNotInstalled)
        }
    }

    func testCorruptFileThrows() throws {
        try Data("not a log".utf8).write(to: folder.appendingPathComponent("bad.qplog"))
        let rec = try record(from: makeLog(), sourceFileName: "bad.qplog")
        XCTAssertThrowsError(try AdifExporter.exportArchived(record: rec, folder: folder)) {
            XCTAssertEqual($0 as? AdifExporter.ArchiveFailure, .logUnreadable)
        }
    }
}

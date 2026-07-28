import XCTest
@testable import QSOPartyLogger

/// The dashboard model's export action: reads the row's saved .qplog out of
/// the configured logs folder and stages ADIF for the section's save panel.
@MainActor
final class DashboardModelExportTests: XCTestCase {

    private var folder: URL!
    private let t = Date(timeIntervalSince1970: 1_788_013_920)  // 2026-08-29 14:32:00Z

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardModelExportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // The app container's temp dir is already accessible, so a
        // security-scoped bookmark for it can be minted inside the test host
        // (same pattern as CloudMirrorTests).
        let bookmark: Data
        do {
            bookmark = try folder.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
        } catch {
            throw XCTSkip("cannot mint security-scoped bookmark in this environment: \(error)")
        }
        // Into the redirected test suite, never `.standard` — removing this
        // key against the real domain would delete the operator's configured
        // iCloud logs folder.
        Preferences.store.set(bookmark, forKey: "iCloudFolderBookmark")
        CloudMirror._resetHeldAccessForTesting()
    }

    override func tearDownWithError() throws {
        Preferences.store.removeObject(forKey: "iCloudFolderBookmark")
        CloudMirror._resetHeldAccessForTesting()
        try? FileManager.default.removeItem(at: folder)
    }

    private func makeRecord(sourceFileName: String?, writeFile: Bool) throws -> ContestRecord {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [
            QSO(
                timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14042, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"
            )
        ]
        if writeFile, let sourceFileName {
            try log.encoded().write(to: folder.appendingPathComponent(sourceFileName))
        }
        return try XCTUnwrap(ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.countsOnly(log: log),
            updatedAt: t,
            sourceFileName: sourceFileName
        ))
    }

    func testExportADIFStagesSavedLogAsADIF() throws {
        let record = try makeRecord(sourceFileName: "2026-08-29 KSQP KE5CW.qplog", writeFile: true)
        let model = DashboardModel()
        model.exportADIF(record)

        let export = try XCTUnwrap(model.adifExport)
        XCTAssertEqual(export.fileName, "2026-08-29 KSQP KE5CW.adi")
        XCTAssertTrue(export.text.contains("<call:4>W0BH"))
        XCTAssertTrue(export.text.contains("<contest_id:12>KS-QSO-PARTY"))
    }

    func testExportADIFWithMissingFileStagesNothing() throws {
        let record = try makeRecord(sourceFileName: "gone.qplog", writeFile: false)
        let model = DashboardModel()
        model.exportADIF(record)
        XCTAssertNil(model.adifExport)
    }
}

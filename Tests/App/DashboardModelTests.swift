import XCTest
@testable import QSOPartyLogger

/// The dashboard model over a logs folder it is handed: refresh reads the
/// `.qplog` files there as the history, and the footer facts — duplicates,
/// unreadable files, undownloaded placeholders — come straight from the read.
@MainActor
final class DashboardModelTests: XCTestCase {

    private var folder: URL!
    private let t0 = Date(timeIntervalSince1970: 1_770_000_000)  // 2026-02-02

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DashboardModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func log(partyID: String = "ksqp") -> ContestLog {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.setupCompleted = true
        log.qsos = [
            QSO(
                timestampUTC: t0, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14042, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"
            )
        ]
        return log
    }

    private func write(_ log: ContestLog, as name: String, modified: Date? = nil) throws {
        let url = folder.appendingPathComponent(name)
        try log.encoded().write(to: url, options: .atomic)
        if let modified {
            try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path(percentEncoded: false))
        }
    }

    func testRefreshReadsTheLogsFolder() async throws {
        try write(log(), as: "2026-08-29 KSQP KE5CW.qplog")
        try write(log(partyID: "tqp"), as: "2026-09-19 TQP KE5CW.qplog")
        let model = DashboardModel(logsFolder: { [folder] in folder })
        await model.refresh()
        XCTAssertEqual(Set(model.archive.records.map(\.partyID)), ["ksqp", "tqp"])
        XCTAssertNil(model.loadError)
        XCTAssertEqual(model.duplicates, [])
        XCTAssertEqual(model.unreadable, [])
        XCTAssertEqual(model.downloading, 0)
        XCTAssertEqual(model.logsFolderURL, folder)
    }

    func testDuplicatesAndUnreadableFilesAreSurfaced() async throws {
        try write(log(), as: "2026-08-29 KSQP KE5CW.qplog", modified: t0)
        try write(log(), as: "2026-08-29 KSQP KE5CW 2.qplog", modified: t0.addingTimeInterval(60))
        try Data("junk{{{".utf8).write(to: folder.appendingPathComponent("bad.qplog"))
        let model = DashboardModel(logsFolder: { [folder] in folder })
        await model.refresh()
        XCTAssertEqual(model.archive.records.count, 1)
        XCTAssertEqual(model.duplicates.map(\.shown), ["2026-08-29 KSQP KE5CW 2.qplog"])
        XCTAssertEqual(model.unreadable, ["bad.qplog"])
        XCTAssertNil(model.loadError)
    }

    /// No logs folder chosen: nothing to read, and not an error — the empty
    /// state offers the chooser.
    func testNoFolderIsEmptyNotAnError() async {
        let model = DashboardModel(logsFolder: { nil })
        await model.refresh()
        XCTAssertEqual(model.archive, .empty)
        XCTAssertNil(model.loadError)
        XCTAssertNil(model.logsFolderURL)
    }
}

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

    // MARK: POTA partition

    private func potaLog(park: String, call: String, offset: TimeInterval = 0) -> ContestLog {
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "MO")
        log.setupCompleted = true
        log.qsos = [
            QSO(
                timestampUTC: t0.addingTimeInterval(offset), call: call, band: .m20,
                modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599",
                myPotaRefs: [park], myLoc: "", theirLoc: ""
            )
        ]
        return log
    }

    /// Program records (POTA) feed the POTA widgets and stay out of every
    /// contest one — season cards, contests table, charts.
    func testProgramRecordsFeedPotaNotTheContestWidgets() async throws {
        try write(log(), as: "2026-08-29 KSQP KE5CW.qplog")
        try write(potaLog(park: "US-1234", call: "W0AAA"), as: "2026-02-02-KE5CW@US-1234.qplog")
        try write(potaLog(park: "US-5678", call: "K5BBB", offset: 86_400), as: "2026-02-03-KE5CW@US-5678.qplog")

        let model = DashboardModel(logsFolder: { [folder] in folder })
        await model.refresh()
        model.selectedYear = 2026

        // Contest widgets: KSQP alone.
        XCTAssertEqual(model.stats.contests, 1)
        XCTAssertEqual(model.stats.validQSOs, 1)
        XCTAssertEqual(model.stats.rows.map(\.partyID), ["ksqp"])

        // POTA widgets: the two outings alone.
        XCTAssertEqual(model.potaSeason.outings.count, 2)
        XCTAssertEqual(model.potaSeason.qsos, 2)
        XCTAssertEqual(model.potaSeason.parksActivated, 2)

        // The whole folder is still one history: every record read, every
        // year listed.
        XCTAssertEqual(model.archive.records.count, 3)
    }

    /// A contest worked from a park — KSQP from a state park, the park in
    /// the log's Setup — is both: a contest entry in every contest widget,
    /// and an outing in the POTA cards and list, counting the contacts made
    /// from the park.
    func testAContestWorkedFromAParkIsAlsoAnOuting() async throws {
        var paired = log()
        paired.qsos = [
            QSO(
                timestampUTC: t0, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14042, rstSent: "599", rstRcvd: "599", myPotaRefs: ["US-1234"],
                myLoc: "TX", theirLoc: "MRN"
            ),
            QSO(
                timestampUTC: t0.addingTimeInterval(60), call: "K0A", band: .m20, modeClass: .cw,
                rawMode: "CW", freqKHz: 14043, rstSent: "599", rstRcvd: "599",
                myPotaRefs: ["US-1234"], myLoc: "TX", theirLoc: "ALL"
            ),
            // Before the park was set — not a POTA contact, still a contest one.
            QSO(
                timestampUTC: t0.addingTimeInterval(-3600), call: "N0X", band: .m40, modeClass: .cw,
                rawMode: "CW", freqKHz: 7042, rstSent: "599", rstRcvd: "599",
                myLoc: "TX", theirLoc: "BAR"
            ),
        ]
        try write(paired, as: "2026-08-29 KSQP KE5CW.qplog")
        try write(potaLog(park: "US-5678", call: "K5BBB"), as: "2026-02-02-KE5CW@US-5678.qplog")

        let model = DashboardModel(logsFolder: { [folder] in folder })
        await model.refresh()
        model.selectedYear = 2026

        // Contest widgets: KSQP, whole — three contacts.
        XCTAssertEqual(model.stats.contests, 1)
        XCTAssertEqual(model.stats.validQSOs, 3)
        XCTAssertEqual(model.stats.rows.map(\.partyID), ["ksqp"])

        // POTA widgets: the park outing and the contest's park contacts.
        XCTAssertEqual(model.potaSeason.outings.count, 2)
        let ksqp = try XCTUnwrap(model.potaSeason.outings.first { $0.record.partyID == "ksqp" })
        XCTAssertEqual(ksqp.parks, ["US-1234"])
        XCTAssertEqual(ksqp.qsos, 2, "only the contacts made from the park")
        XCTAssertEqual(model.potaSeason.qsos, 3)
        XCTAssertEqual(model.potaSeason.parksActivated, 2)
        XCTAssertEqual(model.archive.records.count, 2, "still one record per log")
    }

    /// The POTA list names each park from the downloaded park list; a park
    /// the list does not know, or no list yet, is the reference alone.
    func testParkNamesComeFromTheDownloadedParkList() async throws {
        try write(potaLog(park: "US-1234", call: "W0AAA"), as: "2026-02-02-KE5CW@US-1234.qplog")
        let directory = PotaParkDirectory(parks: [
            PotaPark(reference: "US-1234", name: "Cedar Hill State Park", latitude: nil,
                     longitude: nil, grid: nil, locationDesc: "US-TX"),
        ])
        let model = DashboardModel(logsFolder: { [folder] in folder }, parkDirectory: { directory })
        await model.refresh()
        XCTAssertEqual(model.parkLabel("US-1234"), "Cedar Hill State Park · TX")
        XCTAssertEqual(model.parkLabel("us-1234"), "Cedar Hill State Park · TX", "references are case-blind")
        XCTAssertNil(model.parkLabel("US-9999"))

        let withoutList = DashboardModel(logsFolder: { [folder] in folder }, parkDirectory: { nil })
        await withoutList.refresh()
        XCTAssertNil(withoutList.parkLabel("US-1234"))
    }

    /// A year with no POTA is simply an empty season — nothing throws, the
    /// section says so or is hidden.
    func testYearWithoutPotaIsAnEmptySeason() async throws {
        try write(log(), as: "2026-08-29 KSQP KE5CW.qplog")
        let model = DashboardModel(logsFolder: { [folder] in folder })
        await model.refresh()
        model.selectedYear = 2026
        XCTAssertEqual(model.potaSeason.outings, [])
        XCTAssertEqual(model.stats.contests, 1)
    }
}

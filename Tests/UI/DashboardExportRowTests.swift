import XCTest
@testable import QSOPartyLogger

/// A dashboard row can export ADIF only when both halves are present: the
/// saved .qplog on disk to read, and the party's installed rules to render
/// county names and the contest id.
final class DashboardExportRowTests: XCTestCase {

    private func row(fileAvailable: Bool, partyInstalled: Bool) -> DashboardContestsSection.ContestRow {
        let record = ContestRecord(
            partyID: "ksqp",
            year: 2026,
            callsign: "KE5CW",
            station: StationProfile(),
            myLocation: .inState(counties: ["SED"]),
            qsos: [],
            snapshot: ScoreSnapshot.countsOnly(log: ContestLog(partyID: "ksqp")),
            scoreOrigin: .computedNow,
            updatedAt: Date(timeIntervalSince1970: 1_788_013_920),
            sourceFileName: fileAvailable ? "2026-08-29 KSQP KE5CW.qplog" : nil
        )
        return DashboardContestsSection.ContestRow(
            record: record,
            partyName: "Kansas QSO Party",
            fileAvailable: fileAvailable,
            partyInstalled: partyInstalled
        )
    }

    func testExportableRequiresFileAndInstalledParty() {
        XCTAssertTrue(row(fileAvailable: true, partyInstalled: true).exportable)
        XCTAssertFalse(row(fileAvailable: false, partyInstalled: true).exportable)
        XCTAssertFalse(row(fileAvailable: true, partyInstalled: false).exportable)
        XCTAssertFalse(row(fileAvailable: false, partyInstalled: false).exportable)
    }
}

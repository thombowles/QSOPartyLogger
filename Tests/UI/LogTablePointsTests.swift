import XCTest
@testable import QSOPartyLogger

/// What the log list's `Pts` column prints for a row.
///
/// Regression (2026-08-16, NJQRP Skeeter Hunt, on the air): the score card
/// said 70 points — 22 Skeeters at 3 and two QRP stations at 2 — while every
/// row in the list read `1`. The column was recomputing each row from the
/// party's mode/location table, which cannot see the received Skeeter number
/// or power, so the list disagreed with the engine on the one party whose
/// points depend on it. The column now prints what the engine paid the row
/// and computes nothing of its own — the layout table forbids party-specific
/// scoring in the UI for exactly this reason.
final class LogTablePointsTests: XCTestCase {

    private var skeeter: PartyDefinition!

    override func setUpWithError() throws {
        skeeter = try XCTUnwrap(PartyCatalog.party(id: "skeeter"))
    }

    private var seq: TimeInterval = 0
    private func qso(call: String, their: String, memberRcvd: String?, band: Band = .m20) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_786_899_600 + seq),
            call: call, band: band, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599",
            memberSent: "20", memberRcvd: memberRcvd,
            myLoc: "TX", theirLoc: their
        )
    }

    private func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "skeeter",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "20",
            entryClassID: "X1"
        )
    }

    /// The report itself: a Skeeter row must read 3, a QRP row 2, a QRO row 1.
    func testSkeeterRowsReadThreeTwoOne() {
        let rows = [
            qso(call: "W2LJ", their: "NJ", memberRcvd: "13"),
            qso(call: "K1SW", their: "NH", memberRcvd: "5W"),
            qso(call: "W9XYZ", their: "IL", memberRcvd: "100W"),
            qso(call: "K4POTA", their: "GA", memberRcvd: nil),
        ]
        let score = ScoreEngine.score(log: log(rows), party: skeeter)
        XCTAssertEqual(
            rows.map { LogTable.pointsText(for: $0, score: score, party: skeeter) },
            ["3", "2", "1", "1"]
        )
    }

    /// A row the engine paid nothing for reads 0, not a recomputed guess.
    func testADupeReadsZero() {
        let first = qso(call: "W2LJ", their: "NJ", memberRcvd: "13")
        let again = qso(call: "W2LJ", their: "NJ", memberRcvd: "13")
        let score = ScoreEngine.score(log: log([first, again]), party: skeeter)
        XCTAssertEqual(LogTable.pointsText(for: first, score: score, party: skeeter), "3")
        XCTAssertEqual(LogTable.pointsText(for: again, score: score, party: skeeter), "0")
    }

    /// No party, no points to show.
    func testNoPartyReadsADash() {
        let row = qso(call: "W2LJ", their: "NJ", memberRcvd: "13")
        XCTAssertEqual(LogTable.pointsText(for: row, score: .init(), party: nil), "-")
    }
}

import XCTest
import UniformTypeIdentifiers
@testable import QSOPartyLogger

/// The save path may be handed the window's already-computed score snapshot
/// (`LiveScore`'s fold); the bytes it writes must be identical to the legacy
/// compute-at-save path, and the draft rule must hold either way.
final class SaveSnapshotReuseTests: XCTestCase {

    var ksqp: PartyDefinition!
    var counties: [String] = []

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        counties = ksqp.counties.map(\.abbr)
    }

    func seededLog(rows: Int) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.setupCompleted = true
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        log.qsos = (0..<rows).map { i in
            QSO(timestampUTC: start.addingTimeInterval(Double(i) * 60),
                call: "W0X\(String(format: "%03d", i % 23))",
                band: i % 2 == 0 ? .m20 : .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: 14040, rstSent: "599", rstRcvd: "599",
                myLoc: "TX", theirLoc: counties[i % 30])
        }
        return log
    }

    private func windowSnapshot(for log: ContestLog) -> ScoreSnapshot {
        ScoreSnapshot.make(
            breakdown: ScoreEngine.score(log: log, party: ksqp),
            bandModeCounts: ScoreEngine.bandModeCounts(log: log, party: ksqp),
            log: log
        )
    }

    func testPartsMakeMatchesComputingMake() {
        let log = seededLog(rows: 40)
        XCTAssertEqual(windowSnapshot(for: log),
                       ScoreSnapshot.make(log: log, party: ksqp))
    }

    func testSuppliedSnapshotWritesTheLegacyBytes() throws {
        let log = seededLog(rows: 40)
        XCTAssertEqual(try LogDocument.dataForSaving(log, score: windowSnapshot(for: log)),
                       try LogDocument.dataForSaving(log))
    }

    func testDraftStampsNilWhateverTheCallerHolds() throws {
        var log = seededLog(rows: 3)
        log.setupCompleted = false
        let written = try ContestLog.decode(
            from: try LogDocument.dataForSaving(log, score: windowSnapshot(for: log)))
        XCTAssertNil(written.scoreSnapshot)
    }

    @MainActor
    func testDocumentSnapshotCarriesTheProviderScore() throws {
        let document = LogDocument()
        document.log = seededLog(rows: 5)
        let supplied = windowSnapshot(for: document.log)
        document.scoreSnapshotProvider = { supplied }
        let snapshot = try document.snapshot(contentType: .qplog)
        XCTAssertEqual(snapshot.score, supplied)
        XCTAssertEqual(snapshot.log, document.log)
    }

    @MainActor
    func testNilProviderFallsBackToLegacyCompute() throws {
        let document = LogDocument()
        document.log = seededLog(rows: 5)
        let snapshot = try document.snapshot(contentType: .qplog)
        XCTAssertNil(snapshot.score)
        // The write itself still stamps — through the legacy path.
        let written = try ContestLog.decode(
            from: try LogDocument.dataForSaving(snapshot.log, score: snapshot.score))
        XCTAssertNotNil(written.scoreSnapshot)
    }
}

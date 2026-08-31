import XCTest
@testable import QSOPartyLogger

/// `LiveScore` must serve exactly what the engine computes, fold exactly once
/// per log change, and follow a party change.
final class LiveScoreTests: XCTestCase {

    var ksqp: PartyDefinition!
    var counties: [String] = []

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        counties = ksqp.counties.map(\.abbr)
    }

    @MainActor
    private func seededDocument(rows: Int) -> LogDocument {
        let document = LogDocument()
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let bands: [Band] = [.m20, .m40]
        log.qsos = (0..<rows).map { i in
            QSO(timestampUTC: start.addingTimeInterval(Double(i) * 60),
                call: "W0X\(String(format: "%03d", i % 37))",
                band: bands[i % 2], modeClass: .cw, rawMode: "CW", freqKHz: 14040,
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: counties[i % 40])
        }
        document.log = log
        return document
    }

    private func probeQSO(call: String = "W0NEW") -> QSO {
        QSO(timestampUTC: Date(timeIntervalSince1970: 1_788_100_000),
            call: call, band: .m15, modeClass: .cw, rawMode: "CW", freqKHz: 21040,
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: counties[90])
    }

    @MainActor
    func testGenerationBumpsPerLogMutationOnly() {
        let document = LogDocument()
        let before = document.generation
        _ = document.log
        XCTAssertEqual(document.generation, before, "a read must not bump")
        document.log.qsos.append(probeQSO())
        XCTAssertEqual(document.generation, before + 1)
    }

    @MainActor
    func testServesExactlyWhatTheEngineComputes() {
        let document = seededDocument(rows: 60)
        let live = LiveScore(document: document)
        XCTAssertEqual(live.breakdown, ScoreEngine.score(log: document.log, party: ksqp))
        XCTAssertEqual(live.bandModeCounts, ScoreEngine.bandModeCounts(log: document.log, party: ksqp))
        XCTAssertEqual(live.dupeKeys, Set(document.log.qsos.map(DupeChecker.key)))
        XCTAssertNil(live.ruleDupeKeys, "a party log has no rule-keyed set")
    }

    @MainActor
    func testFoldsOncePerGeneration() {
        let document = seededDocument(rows: 40)
        let live = LiveScore(document: document)
        _ = live.breakdown
        _ = live.multiplierKeys
        _ = live.bandModeCounts
        XCTAssertEqual(live.foldCount, 1)
        document.log.qsos.append(probeQSO())
        _ = live.breakdown
        XCTAssertEqual(live.foldCount, 2)
        _ = live.dupeKeys
        XCTAssertEqual(live.foldCount, 2)
    }

    @MainActor
    func testRefoldsWhenThePartyChanges() {
        let document = seededDocument(rows: 12)
        let live = LiveScore(document: document)
        _ = live.breakdown
        XCTAssertEqual(live.foldCount, 1)
        document.log.partyID = "arqp"
        XCTAssertEqual(live.breakdown, ScoreEngine.score(
            log: document.log,
            party: PartyCatalog.party(id: "arqp")!))
        XCTAssertEqual(live.foldCount, 2)
    }

    @MainActor
    func testV2ContestCarriesRuleKeys() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        let document = LogDocument()
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        log.qsos = [
            QSO(timestampUTC: Date(timeIntervalSince1970: 1_788_000_000),
                call: "K1ABC", band: .m20, modeClass: .cw, rawMode: "CW",
                sent: [ExchangeElementID.rst: "599"], rcvd: [ExchangeElementID.rst: "599"]),
        ]
        document.log = log
        let live = LiveScore(document: document)
        XCTAssertEqual(live.ruleDupeKeys,
                       Set(document.log.qsos.map { DupeChecker.key($0, rule: contest.dupe) }))
        XCTAssertEqual(live.breakdown, ScoreEngine.score(log: document.log, contest: contest))
    }

    @MainActor
    func testWorkedSetsMatchHandBuiltAndFollowTheLog() {
        let document = seededDocument(rows: 30)
        let live = LiveScore(document: document)
        let byHand = Set(document.log.qsos
            .filter { $0.band == .m20 && $0.modeClass == .cw }
            .map { $0.call.uppercased() })
        XCTAssertEqual(live.workedCalls(band: .m20, modeClass: .cw), byHand)
        let pairs = Set(document.log.qsos
            .filter { $0.band == .m20 && $0.modeClass == .cw }
            .map { "\($0.call.uppercased())|\($0.theirLoc.uppercased())" })
        XCTAssertEqual(live.workedCallCounties(band: .m20, modeClass: .cw), pairs)
        XCTAssertEqual(live.foldCount, 0, "worked sets never fold the score")

        document.log.qsos.append(probeQSO(call: "W0FRESH"))
        XCTAssertTrue(live.workedCalls(band: .m15, modeClass: .cw).contains("W0FRESH"))
    }

    @MainActor
    func testDisplayRowsAndGroupSizesFollowTheLog() {
        let document = seededDocument(rows: 20)
        let live = LiveScore(document: document)
        let expected = Array(document.log.qsos.sortedChronologically().reversed())
        XCTAssertEqual(live.displayRows.map(\.id), expected.map(\.id))
        XCTAssertEqual(live.groupSizes,
                       Dictionary(grouping: document.log.qsos, by: \.groupID).mapValues(\.count))
        XCTAssertEqual(live.foldCount, 0, "table data never folds the score")

        // A county-line contact joins: two rows, one groupID, newest first.
        let group = UUID()
        let t = Date(timeIntervalSince1970: 1_788_200_000)
        for county in [counties[60], counties[61]] {
            document.log.qsos.append(QSO(
                groupID: group, timestampUTC: t, call: "N0CL", band: .m20,
                modeClass: .cw, rawMode: "CW", freqKHz: 14040,
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: county))
        }
        XCTAssertEqual(live.groupSizes[group], 2)
        XCTAssertEqual(live.displayRows.first?.call, "N0CL")
    }
}

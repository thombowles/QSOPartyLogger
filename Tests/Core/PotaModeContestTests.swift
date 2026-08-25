import XCTest
@testable import QSOPartyLogger

/// The bundled POTA contest definition — the first v2 file in
/// Resources/Contests. Spec: docs/superpowers/specs/
/// 2026-08-25-pota-mode-and-callbook-design.md; rules provenance in
/// docs/research/pota/SOURCES.md ("POTA rules for the dedicated mode").
final class PotaModeContestTests: XCTestCase {

    private var pota: ContestDefinition {
        get throws {
            try XCTUnwrap(ContestCatalog.loadBundled(bundle: .main)
                .first { $0.id == "pota" },
                "pota.json must be bundled and decodable")
        }
    }

    func testBundledAndValid() throws {
        let contest = try pota
        XCTAssertNoThrow(try contest.validate())
        XCTAssertEqual(contest.name, "Parks on the Air (POTA)")
        XCTAssertEqual(contest.family, .program)
    }

    func testProgramShape() throws {
        let contest = try pota
        XCTAssertTrue(contest.potaProgram)
        XCTAssertEqual(contest.cqLabel, "POTA")
        XCTAssertTrue(contest.enrichFromCallbook)
        XCTAssertFalse(contest.cabrillo.submittable)
        XCTAssertNil(contest.schedule, "POTA is always on")
        XCTAssertTrue(contest.multipliers.isEmpty)
        XCTAssertEqual(contest.points.map(\.points), [0])
        XCTAssertTrue(contest.bonuses.isEmpty)
        XCTAssertNil(contest.scoreFactors)
    }

    func testAllFourteenBandsIncludingWARCAndSixty() throws {
        XCTAssertEqual(try pota.bands, Band.allCases,
                       "POTA is legal on every band the app knows, WARC and 60 m included")
    }

    func testDupeRuleIsPerDayPerPark() throws {
        let dupe = try pota.dupe
        XCTAssertEqual(dupe.scope, .bandMode)
        XCTAssertTrue(dupe.utcDay)
        XCTAssertTrue(dupe.perMyPark)
        XCTAssertFalse(dupe.locationSensitive)
    }

    func testExchangeIsRSTOnly() throws {
        let contest = try pota
        XCTAssertEqual(contest.exchange.map(\.kind), [.rst])
        XCTAssertFalse(contest.exchange.contains { $0.id == ExchangeElementID.location },
                       "no location element is what folds the entry row's exchange field away")
    }

    func testZeroScoreOnACraftedLog() throws {
        let contest = try pota
        var log = ContestLog(partyID: "pota")
        log.qsos = [
            QSO(call: "W1AW", band: .m20, modeClass: .cw, rawMode: "CW",
                sent: [ExchangeElementID.rst: "599"],
                rcvd: [ExchangeElementID.rst: "599"],
                myPotaRefs: ["US-1111"], theirPotaRefs: ["US-2222"]),
        ]
        let score = ScoreEngine.score(log: log, contest: contest)
        XCTAssertEqual(score.total, 0)
        XCTAssertEqual(score.validQSOs, 1)
    }

    func testNotesCarryProvenanceAndTheOpenQuestion() throws {
        let notes = try XCTUnwrap(try pota.notes)
        XCTAssertTrue(notes.contains("docs.pota.app"))
        XCTAssertTrue(notes.contains("fetched 2026-08-25"))
        XCTAssertTrue(notes.contains("OPEN QUESTION"))
    }
}

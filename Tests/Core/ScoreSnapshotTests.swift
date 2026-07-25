import XCTest
@testable import QSOPartyLogger

final class ScoreSnapshotTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_787_000_000)  // whole seconds (ISO8601-safe)

    private func qso(
        _ call: String,
        their: String,
        my: String,
        band: Band = .m20,
        mode: ModeClass = .cw,
        offset: TimeInterval = 0
    ) -> QSO {
        QSO(
            timestampUTC: t0.addingTimeInterval(offset),
            call: call,
            band: band,
            modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode.defaultRST,
            rstRcvd: mode.defaultRST,
            myLoc: my,
            theirLoc: their
        )
    }

    /// The dashboard must never disagree with the score sidebar: every figure
    /// in a snapshot equals the engine's output for the same log.
    func testSnapshotParityWithEngine() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        let home = party.counties[0].abbr
        let mine = party.counties[1].abbr

        var log = ContestLog(partyID: party.id)
        log.station.callsign = "KE5CW"
        log.myLocation = .inState(counties: [mine])
        log.qsos = [
            qso("W0AAA", their: home, my: mine, offset: 0),
            qso("W0AAA", their: home, my: mine, offset: 60),        // dupe (same band+mode)
            qso("K5BBB", their: "MO", my: mine, mode: .phone, offset: 120),
            qso("N5CCC", their: "TX", my: mine, band: .m40, offset: 300),
        ]

        let breakdown = ScoreEngine.score(log: log, party: party)
        let snapshot = ScoreSnapshot.make(log: log, party: party)

        XCTAssertEqual(snapshot.validQSOs, breakdown.validQSOs)
        XCTAssertEqual(snapshot.dupeCount, breakdown.dupeCount)
        XCTAssertEqual(snapshot.invalidModeCount, breakdown.invalidModeCount)
        XCTAssertEqual(snapshot.outOfScopeCount, breakdown.outOfScopeCount)
        XCTAssertEqual(snapshot.countiesWorked, breakdown.workedValues(.county).count)

        let figures = try XCTUnwrap(snapshot.figures)
        XCTAssertEqual(figures.qsoPoints, breakdown.qsoPoints)
        XCTAssertEqual(figures.multiplierCount, breakdown.multiplierCount)
        XCTAssertEqual(figures.bonusPoints, breakdown.bonusPoints)
        XCTAssertEqual(figures.categoryFactor, breakdown.categoryFactor)
        XCTAssertEqual(figures.multiplierCap, breakdown.multiplierCap)
        XCTAssertEqual(figures.total, breakdown.total)
        XCTAssertEqual(
            figures.multsByClass,
            Dictionary(uniqueKeysWithValues: breakdown.classCounts.map { ($0.key.rawValue, $0.value) })
        )

        // Per-mode / per-band valid counts equal the engine's matrix, flattened.
        let matrix = ScoreEngine.bandModeCounts(log: log, party: party)
        var byMode: [String: Int] = [:]
        var byBand: [String: Int] = [:]
        for (band, modes) in matrix {
            for (mode, n) in modes {
                byMode[mode.rawValue, default: 0] += n
                byBand[band.rawValue, default: 0] += n
            }
        }
        XCTAssertEqual(snapshot.qsosByMode, byMode)
        XCTAssertEqual(snapshot.qsosByBand, byBand)
    }

    /// A log whose party definition is not installed still keeps its counts —
    /// score figures are absent, not zero.
    func testCountsOnlySnapshotHasNoFigures() {
        var log = ContestLog(partyID: "not-installed")
        log.qsos = [
            qso("W1AAA", their: "NH", my: "TX", offset: 0),
            qso("W1BBB", their: "ME", my: "TX", mode: .phone, offset: 60),
        ]
        let snapshot = ScoreSnapshot.countsOnly(log: log)
        XCTAssertNil(snapshot.figures)
        XCTAssertEqual(snapshot.validQSOs, 2)
        XCTAssertEqual(snapshot.qsosByMode, ["cw": 1, "phone": 1])
        XCTAssertEqual(snapshot.qsosByBand, ["20m": 2])
    }

    /// Operating time is the contest convention: gaps of 30 minutes or more
    /// are off-time and don't count.
    func testOperatingMinutesClipsBreaksOfThirtyMinutesOrMore() {
        let minutes = ScoreSnapshot.operatingMinutes(timestamps: [
            t0,
            t0.addingTimeInterval(600),      // +10 min
            t0.addingTimeInterval(1200),     // +10 min
            t0.addingTimeInterval(7200),     // +100 min → break (≥ 30 min), excluded
            t0.addingTimeInterval(7500),     // +5 min
        ])
        XCTAssertEqual(minutes, 25)
    }

    func testOperatingMinutesEdgeCases() {
        XCTAssertEqual(ScoreSnapshot.operatingMinutes(timestamps: []), 0)
        // A single contact is a minute on the air, not zero.
        XCTAssertEqual(ScoreSnapshot.operatingMinutes(timestamps: [t0]), 1)
        // A gap of exactly 30:00 is a break (the convention is "less than 30").
        XCTAssertEqual(
            ScoreSnapshot.operatingMinutes(timestamps: [t0, t0.addingTimeInterval(1800)]),
            1
        )
    }
}

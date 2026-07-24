import XCTest
@testable import QSOPartyLogger

final class ScoreEngineTests: XCTestCase {

    var ksqp: PartyDefinition!
    var tqp: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        tqp = try XCTUnwrap(PartyCatalog.party(id: "tqp"))
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W0BH",
        band: Band = .m20,
        mode: ModeClass = .cw,
        rawMode: String? = nil,
        my: String = "TX",
        their: String = "MRN"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000 + seq),
            call: call,
            band: band,
            modeClass: mode,
            rawMode: rawMode ?? (mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY"),
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my,
            theirLoc: their
        )
    }

    func outStateLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inStateLog(_ qsos: [QSO], counties: [String] = ["MRN"]) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.myLocation = .inState(counties: counties)
        log.qsos = qsos
        return log
    }

    // MARK: Out-of-state (Tom's typical KSQP entry)

    func testPointsByMode() {
        let log = outStateLog([
            qso(call: "W0A", mode: .phone, their: "MRN"),
            qso(call: "W0B", mode: .cw, their: "MRN"),
            qso(call: "W0C", mode: .digital, their: "MRN"),
        ])
        let s = ScoreEngine.score(log: log, party: ksqp)
        XCTAssertEqual(s.qsoPoints, 2 + 3 + 3)
        XCTAssertEqual(s.validQSOs, 3)
    }

    func testOutOfStateMultsAreCountiesOnce() {
        let log = outStateLog([
            qso(call: "W0A", band: .m20, their: "MRN"),
            qso(call: "W0B", band: .m40, their: "MRN"),   // same county, other band — still 1 mult
            qso(call: "W0C", their: "CHS"),
        ])
        let s = ScoreEngine.score(log: log, party: ksqp)
        XCTAssertEqual(s.workedValues(.county), ["MRN", "CHS"])
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertEqual(s.total, 9 * 2)
    }

    func testDupesExcludedFromPointsAndScore() {
        let a = qso(call: "W0A", their: "MRN")
        var b = a
        b.id = UUID()
        b.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let log = outStateLog([a, b])
        let s = ScoreEngine.score(log: log, party: ksqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.qsoPoints, 3)
        XCTAssertTrue(s.dupeRowIDs.contains(b.id))
    }

    func testKS0KSBonusOnceAndCountsForQSOCredit() {
        let log = outStateLog([
            qso(call: "KS0KS", band: .m20, their: "SHA"),
            qso(call: "KS0KS", band: .m40, their: "SHA"),  // different band: valid QSO, but bonus stays 100
        ])
        let s = ScoreEngine.score(log: log, party: ksqp)
        XCTAssertEqual(s.bonusPoints, 100)
        XCTAssertEqual(s.qsoPoints, 6, "bonus contacts also count for QSO credit")
        XCTAssertEqual(s.total, 6 * 1 + 100)
    }

    func testCountyLineRowsBothScore() {
        // W0BH on LIN/AND line: two rows, both score, two mults.
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W0BH", rstSent: "599", rstRcvd: "599",
                band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14042, timestampUTC: Date(timeIntervalSince1970: 1_787_500_000)
            ),
            myLocs: ["TX"], theirLocs: ["LIN", "AND"]
        )
        let s = ScoreEngine.score(log: outStateLog(rows), party: ksqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 6)
        XCTAssertEqual(s.workedValues(.county), ["LIN", "AND"])
        XCTAssertEqual(s.total, 6 * 2)
    }

    // MARK: In-state

    func testInStateHomeStateViaCounty() {
        // KS op works another KS station: first KS county logged = KS state mult.
        let log = inStateLog([
            qso(call: "K0AAA", my: "MRN", their: "SHA"),
            qso(call: "W5XYZ", my: "MRN", their: "TX"),
            qso(call: "VE4AAA", my: "MRN", their: "MB"),
            qso(call: "DL1AA", my: "MRN", their: "DX"),
        ])
        let s = ScoreEngine.score(log: log, party: ksqp)
        XCTAssertEqual(s.workedValues(.state), ["KS", "TX"])
        XCTAssertEqual(s.workedValues(.province), ["MB"])
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        XCTAssertEqual(s.multiplierCount, 4)
        XCTAssertTrue(s.workedValues(.county).isEmpty, "KSQP in-state rule counts no county class")
    }

    func testInStateSecondCountyAddsNoMult() {
        let log = inStateLog([
            qso(call: "K0AAA", my: "MRN", their: "SHA"),
            qso(call: "K0BBB", my: "MRN", their: "RIL"),
        ])
        let s = ScoreEngine.score(log: log, party: ksqp)
        XCTAssertEqual(s.multiplierCount, 1, "KS state mult only, once")
    }

    // MARK: TQP

    func testTQPInStateCountsCountiesAndStates() {
        var log = ContestLog(partyID: "tqp")
        log.myLocation = .inState(counties: ["GRAY"])
        log.qsos = [
            qso(call: "N5AAA", my: "GRAY", their: "HARR"),
            qso(call: "K5BBB", my: "GRAY", their: "DSMI"),
            qso(call: "W0CCC", my: "GRAY", their: "OK"),
        ]
        let s = ScoreEngine.score(log: log, party: tqp)
        XCTAssertEqual(s.workedValues(.county), ["HARR", "DSMI"])
        XCTAssertEqual(s.workedValues(.state), ["OK"], "homeStateCountsViaCounty=false for TQP")
        XCTAssertEqual(s.multiplierCount, 3)
    }

    func testTQPMobileCountyBonus() {
        var log = ContestLog(partyID: "tqp")
        log.myLocation = .outOfState(location: "KS")
        // N5NA mobile worked in 5 counties → 500; 4 counties → 0; 10 → 1000.
        let mobile5 = ["ANDE", "ANDR", "ANGE", "ARAN", "ARCH"].map {
            qso(call: "N5NA", my: "KS", their: $0)
        }
        let mobile4 = ["AUST", "BAIL", "BAND", "BAST"].map {
            qso(call: "K5OT", my: "KS", their: $0)
        }
        log.qsos = mobile5 + mobile4
        XCTAssertEqual(ScoreEngine.score(log: log, party: tqp).bonusPoints, 500)

        let five_more = ["BAYL", "BEE", "BELL", "BEXA", "BLAN"].map {
            qso(call: "N5NA", my: "KS", their: $0)
        }
        log.qsos += five_more
        XCTAssertEqual(ScoreEngine.score(log: log, party: tqp).bonusPoints, 1000)
    }

    func testTQPMobileBonusSameCountyRepeatDoesNotAdvance() {
        var log = ContestLog(partyID: "tqp")
        log.myLocation = .outOfState(location: "KS")
        // 5 contacts but only 4 distinct counties (one on a different band to avoid dupe).
        log.qsos = ["ANDE", "ANDR", "ANGE", "ARAN"].map { qso(call: "N5NA", my: "KS", their: $0) }
            + [qso(call: "N5NA", band: .m40, my: "KS", their: "ANDE")]
        XCTAssertEqual(ScoreEngine.score(log: log, party: tqp).bonusPoints, 0)
    }

    // MARK: New-mult detection

    func testWouldAddMultiplier() {
        let log = outStateLog([qso(call: "W0A", their: "MRN")])
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(theirLocs: ["CHS"], band: .m20, modeClass: .cw, log: log, party: ksqp))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(theirLocs: ["MRN"], band: .m20, modeClass: .cw, log: log, party: ksqp))
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(theirLocs: ["MRN", "CHS"], band: .m20, modeClass: .cw, log: log, party: ksqp))
    }
}

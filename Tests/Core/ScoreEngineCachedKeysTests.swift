import XCTest
@testable import QSOPartyLogger

/// The cheap overloads — the NEW MULT badge and the dupe warning answered
/// against a caller-supplied key set — must agree exactly with the
/// re-scoring overloads they replace on the hot path.
final class ScoreEngineCachedKeysTests: XCTestCase {

    var ksqp: PartyDefinition!
    var counties: [String] = []

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        counties = ksqp.counties.map(\.abbr)
    }

    func makeLog(rows: Int) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let bands: [Band] = [.m20, .m40]
        log.qsos = (0..<rows).map { i in
            QSO(timestampUTC: start.addingTimeInterval(Double(i) * 60),
                call: "W0X\(String(format: "%03d", i % 97))",
                band: bands[i % 2], modeClass: .cw, rawMode: "CW", freqKHz: 14040,
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: counties[i % 40])
        }
        return log
    }

    func testCheapBadgeMatchesFullRescore() {
        let log = makeLog(rows: 300)
        let current = ScoreEngine.score(log: log, party: ksqp).multiplierKeys
        for county in [counties[0], counties[39], counties[80]] {
            for band in [Band.m20, .m15] {
                for mode in [ModeClass.cw, .phone] {
                    let slow = ScoreEngine.wouldAddMultiplier(
                        theirLocs: [county], band: band, modeClass: mode,
                        log: log, party: ksqp)
                    let fast = ScoreEngine.wouldAddMultiplier(
                        theirLocs: [county], band: band, modeClass: mode,
                        log: log, party: ksqp, current: current)
                    XCTAssertEqual(slow, fast, "\(county) \(band.rawValue) \(mode.rawValue)")
                }
            }
        }
    }

    /// The county-line shape too: several received locations at once, and the
    /// worked-station element riding along, exactly as `EntryState.revalidate`
    /// asks the question.
    func testCheapBadgeMatchesFullRescoreOnCountyLinePairs() {
        let log = makeLog(rows: 120)
        let current = ScoreEngine.score(log: log, party: ksqp).multiplierKeys
        let pairs = [
            [counties[0], counties[1]],
            [counties[50], counties[51]],
        ]
        for pair in pairs {
            let slow = ScoreEngine.wouldAddMultiplier(
                theirLocs: pair, band: .m40, modeClass: .cw,
                log: log, party: ksqp, call: "W0BH")
            let fast = ScoreEngine.wouldAddMultiplier(
                theirLocs: pair, band: .m40, modeClass: .cw,
                log: log, party: ksqp, call: "W0BH", current: current)
            XCTAssertEqual(slow, fast, pair.joined(separator: "/"))
        }
    }

    func testCheapDupePairsMatchFullScan() {
        let log = makeLog(rows: 300)
        let logged = Set(log.qsos.map(DupeChecker.key))
        for (call, county) in [("W0X001", counties[1]), ("NOTINLOG", counties[2])] {
            let slow = DupeChecker.existingDupePairs(
                call: call, band: .m20, modeClass: .cw,
                myLocs: ["TX"], theirLocs: [county], log: log.qsos)
            let fast = DupeChecker.existingDupePairs(
                call: call, band: .m20, modeClass: .cw,
                myLocs: ["TX"], theirLocs: [county], logged: logged)
            XCTAssertEqual(slow.map { "\($0.myLoc)|\($0.theirLoc)" },
                           fast.map { "\($0.myLoc)|\($0.theirLoc)" },
                           call)
        }
        // A worked pair really answers as a dupe through the cheap path.
        let worked = log.qsos[0]
        let dupes = DupeChecker.existingDupePairs(
            call: worked.call, band: worked.band, modeClass: worked.modeClass,
            myLocs: ["TX"], theirLocs: [worked.theirLoc], logged: logged)
        XCTAssertEqual(dupes.count, 1)
    }

    func testCheapBadgeHonorsScoredCeiling() throws {
        // A synthetic current set at the side's ceiling: nothing further is
        // new. Probed on whichever CQP side actually declares the ceiling.
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let contest = PartyLowering.lowered(cqp)
        let capped = try XCTUnwrap(
            contest.sides.first { contest.rules(for: $0.id).maxScoredMultipliers != nil },
            "CQP should declare a scored ceiling on some side")
        let cap = try XCTUnwrap(contest.rules(for: capped.id).maxScoredMultipliers)
        var log = ContestLog(partyID: "cqp")
        log.station.callsign = "KE5CW"
        log.sideID = capped.id
        let full = Set((0..<cap).map {
            ScoreEngine.MultKey(multClass: .county, value: "FAKE\($0)", scope: "")
        })
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["ALAM"], band: .m20, modeClass: .cw,
            log: log, party: cqp, current: full))
    }
}

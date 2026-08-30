import XCTest
@testable import QSOPartyLogger

/// `EntryState.revalidate` fed the log's current multiplier and dupe keys
/// must land on exactly the state the re-scoring path lands on — badge,
/// dupe warning and validation alike.
final class EntryStateCachedKeysTests: XCTestCase {

    var ksqp: PartyDefinition!
    var counties: [String] = []

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        counties = ksqp.counties.map(\.abbr)
    }

    func makeLog() -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let t = Date(timeIntervalSince1970: 1_788_000_000)
        log.qsos = [
            QSO(timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14040, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: counties[0]),
            QSO(timestampUTC: t.addingTimeInterval(60), call: "K0AAA", band: .m40, modeClass: .cw,
                rawMode: "CW", freqKHz: 7040, rstSent: "599", rstRcvd: "599",
                myLoc: "TX", theirLoc: counties[1]),
        ]
        return log
    }

    private struct Outcome: Equatable {
        let status: EntryState.ExchangeStatus
        let dupe: String?
        let newMult: Bool
    }

    private func outcome(
        call: String, exchange: String, band: Band, log: ContestLog,
        keys: (mult: Set<ScoreEngine.MultKey>, dupes: Set<DupeChecker.DupeKey>)?
    ) -> Outcome {
        let entry = EntryState()
        entry.callTyped = call
        entry.exchangeTyped = exchange
        entry.revalidate(party: ksqp, log: log, band: band, modeClass: .cw,
                         currentMultKeys: keys?.mult, loggedDupeKeys: keys?.dupes)
        return Outcome(status: entry.exchangeStatus, dupe: entry.dupeWarning, newMult: entry.isNewMult)
    }

    func testCachedKeysMatchLegacyRescore() {
        let log = makeLog()
        let keys = (mult: ScoreEngine.score(log: log, party: ksqp).multiplierKeys,
                    dupes: Set(log.qsos.map(DupeChecker.key)))
        // A worked pair, a fresh county from a fresh station, and a worked
        // county from a fresh station — the three shapes typing meets.
        let cases: [(String, String, Band)] = [
            ("W0BH", counties[0], .m20),
            ("W0NEW", counties[5], .m20),
            ("W0NEW", counties[0], .m20),
        ]
        for (call, exchange, band) in cases {
            let legacy = outcome(call: call, exchange: exchange, band: band, log: log, keys: nil)
            let cached = outcome(call: call, exchange: exchange, band: band, log: log, keys: keys)
            XCTAssertEqual(legacy, cached, "\(call) \(exchange)")
        }
        // Sanity on the shape, not only the equality.
        XCTAssertNotNil(outcome(call: "W0BH", exchange: counties[0], band: .m20, log: log, keys: keys).dupe)
        XCTAssertTrue(outcome(call: "W0NEW", exchange: counties[5], band: .m20, log: log, keys: keys).newMult)
        XCTAssertNil(outcome(call: "W0NEW", exchange: counties[5], band: .m20, log: log, keys: keys).dupe)
    }

    func testV2RuleKeysMatchLegacyScan() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        let t = Date(timeIntervalSince1970: 1_788_000_000)
        log.qsos = [
            QSO(timestampUTC: t, call: "K1ABC", band: .m20, modeClass: .cw, rawMode: "CW",
                sent: [ExchangeElementID.rst: "599"], rcvd: [ExchangeElementID.rst: "599"]),
        ]
        let ruleKeys = Set(log.qsos.map { DupeChecker.key($0, rule: contest.dupe) })

        for (call, wantDupe) in [("K1ABC", true), ("K2XYZ", false)] {
            let legacy = EntryState()
            legacy.callTyped = call
            legacy.revalidate(contest: contest, log: log, band: .m20, modeClass: .cw, now: t)
            let cached = EntryState()
            cached.callTyped = call
            cached.revalidate(contest: contest, log: log, band: .m20, modeClass: .cw, now: t,
                              loggedRuleKeys: ruleKeys)
            XCTAssertEqual(legacy.dupeWarning, cached.dupeWarning, call)
            XCTAssertEqual(cached.dupeWarning != nil, wantDupe, call)
        }
    }
}

import XCTest
@testable import QSOPartyLogger

/// `BonusRule.callAreaSum` — Skeeter Hunt Blackjack. "Work enough call sign
/// numbers to add up to exactly 21 and you can earn a one time 1,000 Bonus
/// Points! Each call area number is worth that many points with the '0' area
/// call signs being worth 10 points. … You can use any call sign worked
/// ONCE."
/// See docs/superpowers/specs/2026-08-04-skeeter-hunt-design.md.
///
/// **Party-free by design** (constitution Article 4): the party is synthetic.
final class CallAreaSumBonusTests: XCTestCase {

    func party(bonuses: String = "") throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"b","name":"B","cabrilloContest":"B","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode","allowedModes":["phone","cw"],
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[\(bonuses)],"counties":[{"abbr":"ALL","name":"Allen"}]}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    func blackjackParty() throws -> PartyDefinition {
        try party(bonuses: #"{"type":"callAreaSum","target":21,"points":1000}"#)
    }

    var seq: TimeInterval = 0
    func qso(call: String, band: Band = .m40, mode: ModeClass = .cw) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : (mode == .digital ? "FT8" : "CW"),
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "NY"
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "b", station: StationProfile(),
            myLocation: .outOfState(location: "TX"), qsos: qsos
        )
    }

    // MARK: The digit values

    func testCallAreaValues() {
        XCTAssertEqual(ScoreEngine.callAreaValue("W2LJ"), 2)
        XCTAssertEqual(ScoreEngine.callAreaValue("WD8RIF"), 8)
        XCTAssertEqual(ScoreEngine.callAreaValue("N0SS"), 10, "0 counts as 10")
        XCTAssertEqual(ScoreEngine.callAreaValue("KE5CW"), 5)
        XCTAssertNil(ScoreEngine.callAreaValue("XYZZY"), "no digit, no value")
    }

    // MARK: The subset-sum predicate

    func testSubsetSumFindsAnExactCombination() {
        XCTAssertTrue(ScoreEngine.subsetSumsExactly([10, 2, 8, 1], target: 21),
                      "the sponsor's own example: N0SS + W2LJ + WD8RIF + W1PID")
        XCTAssertTrue(ScoreEngine.subsetSumsExactly([2, 2, 2, 2, 2, 2, 2, 2, 2, 3], target: 21),
                      "the sponsor's other example: nine 2-land stations and one 3")
        XCTAssertTrue(ScoreEngine.subsetSumsExactly([10, 2, 8, 1, 5, 7], target: 21),
                      "extra values never hurt — a subset is enough")
    }

    func testSubsetSumRejectsWhatCannotReachTheTarget() {
        XCTAssertFalse(ScoreEngine.subsetSumsExactly([], target: 21))
        XCTAssertFalse(ScoreEngine.subsetSumsExactly([2, 2, 2], target: 21),
                       "three 2s top out at 6")
        XCTAssertFalse(ScoreEngine.subsetSumsExactly([2, 4, 6, 8, 10], target: 21),
                       "even values cannot make an odd sum")
        XCTAssertTrue(ScoreEngine.subsetSumsExactly([5], target: 5))
        XCTAssertFalse(ScoreEngine.subsetSumsExactly([5], target: 4),
                       "exactly means exactly — overshooting is not achieving")
    }

    // MARK: Scoring

    func testBlackjackPaysOnceWhenAchieved() throws {
        let party = try blackjackParty()
        let rows = [qso(call: "N0SS"), qso(call: "W2LJ"), qso(call: "WD8RIF"), qso(call: "W1PID")]
        let score = ScoreEngine.score(log: log(rows), party: party)
        XCTAssertEqual(score.bonusPoints, 1000)

        let short = ScoreEngine.score(log: log(Array(rows.dropLast())), party: party)
        XCTAssertEqual(short.bonusPoints, 0, "10+2+8 is 20, not 21")
    }

    /// "You can use any call sign worked ONCE" — a call worked on three bands
    /// still contributes its digit a single time.
    func testEachDistinctCallContributesOnce() throws {
        let party = try blackjackParty()
        let rows = [
            qso(call: "W7AAA", band: .m40),
            qso(call: "W7AAA", band: .m20),
            qso(call: "W7AAA", band: .m15),
        ]
        let score = ScoreEngine.score(log: log(rows), party: party)
        XCTAssertEqual(score.bonusPoints, 0,
                       "three QSOs with one 7 is a 7, not 21")
    }

    /// The sidebar's badge is the same computation the score pays on — and
    /// both ignore rows the party gives no credit for.
    func testAchievedPredicateMatchesTheScore() throws {
        let party = try blackjackParty()
        var rows = [qso(call: "N0SS"), qso(call: "W2LJ"), qso(call: "WD8RIF")]
        XCTAssertFalse(ScoreEngine.callAreaSumAchieved(target: 21, log: log(rows), party: party))

        rows.append(qso(call: "W1PID"))
        XCTAssertTrue(ScoreEngine.callAreaSumAchieved(target: 21, log: log(rows), party: party))

        // An invalid-mode row is not a contest QSO: its call must not fill
        // the last seat at the table.
        let invalid = [qso(call: "N0SS"), qso(call: "W2LJ"), qso(call: "WD8RIF"),
                       qso(call: "W1PID", mode: .digital)]
        XCTAssertFalse(
            ScoreEngine.callAreaSumAchieved(target: 21, log: log(invalid), party: party))
        XCTAssertEqual(ScoreEngine.score(log: log(invalid), party: party).bonusPoints, 0)
    }

    // MARK: Codec

    func testBonusRoundTripsThroughJSON() throws {
        let bonus = BonusRule.callAreaSum(target: 21, points: 1000)
        let data = try JSONEncoder().encode([bonus])
        let decoded = try JSONDecoder().decode([BonusRule].self, from: data)
        XCTAssertEqual(decoded, [bonus])
    }

    /// No bundled party carries the bonus yet — the capability lands
    /// party-free (Article 9).
    func testWhichPartiesCarryACallAreaSumBonus() {
        let carriers = PartyCatalog.loadBundled().filter { party in
            party.bonuses.contains {
                if case .callAreaSum = $0 { return true }
                return false
            }
        }.map(\.id)
        XCTAssertEqual(carriers, [])
    }
}

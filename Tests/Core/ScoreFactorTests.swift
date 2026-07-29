import XCTest
@testable import QSOPartyLogger

/// Final-score factors that are **not whole numbers**.
///
/// Two sponsors print one, with the identical three values. Vermont rule
/// 7(D)(1): *"If all QSO's were made using more than 5W and less than or equal
/// to 150W output, multiply your score by 1.5"*. Wisconsin's POWER LEVEL table:
/// *"Low — 5 to 100 watts — Power Mult = 1.5"*. `ScoreMultipliers` held
/// `[String: Int]`, so neither party shipped a power multiplier at all: the
/// score was a floor, and both files told the operator to do the arithmetic by
/// hand.
///
/// **Party-free by design** (constitution Article 4): every party in this file
/// is synthetic, so the structural change is proved without a sponsor's rules
/// riding along in the same commit.
final class ScoreFactorTests: XCTestCase {

    // MARK: A synthetic party whose only interesting feature is its factors

    /// Three counties, one point each, and a 100-point bonus station — small
    /// enough that every expected total is arithmetic you can do in your head.
    private func party(power: String? = nil, stationCategory: String? = nil) throws -> PartyDefinition {
        var factors = ""
        var parts: [String] = []
        if let power { parts.append("\"power\":\(power)") }
        if let stationCategory { parts.append("\"stationCategory\":\(stationCategory)") }
        if !parts.isEmpty { factors = ",\"scoreMultipliers\":{\(parts.joined(separator: ","))}" }

        let json = """
        {"schemaVersion":1,"id":"factor","name":"Factor Test","cabrilloContest":"FACTOR",
         "homeState":"KS","countyAbbrLength":3,"validBands":["20m"],
         "points":{"phone":1,"cw":1,"digital":1},"dupeScope":"bandMode",
         "multipliers":{
           "inState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"},
           "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
         "bonuses":[{"type":"workStation","call":"W0BONUS","points":100,"scope":"once"}],
         "counties":[{"abbr":"AAA","name":"Alpha"},{"abbr":"BBB","name":"Beta"},
                     {"abbr":"CCC","name":"Gamma"}]\(factors)}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    /// Three QSOs in three counties: 3 QSO points, 3 multipliers, 100 bonus.
    private func log(
        power: StationProfile.CategoryPower = .low,
        station: StationProfile.CategoryStation = .fixed
    ) -> ContestLog {
        var log = ContestLog(partyID: "factor")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.station.categoryStation = station
        log.qsos = ["AAA", "BBB", "CCC"].enumerated().map { index, county in
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_770_000_000 + Double(index) * 60),
                call: index == 0 ? "W0BONUS" : "W0\(index)",
                band: .m20, modeClass: .phone, rawMode: "SSB",
                rstSent: "59", rstRcvd: "59",
                myLoc: "TX", theirLoc: county
            )
        }
        return log
    }

    // MARK: The gap this closes

    /// The ×1.5 both sponsors print, applied. 3 points × 3 multipliers = 9,
    /// ×1.5 = 13.5 → 13, and the bonus is added after.
    func testALowPowerFactorOfOnePointFiveIsApplied() throws {
        let s = ScoreEngine.score(log: log(power: .low), party: try party(power: #"{"QRP":2,"LOW":1.5,"HIGH":1}"#))

        XCTAssertEqual(s.qsoPoints, 3)
        XCTAssertEqual(s.multiplierCount, 3)
        XCTAssertEqual(s.bonusPoints, 100)
        XCTAssertEqual(s.total, 113)
    }

    /// The fraction is resolved **once**, against the whole points × multipliers
    /// product — never step by step. Wisconsin's stated order is *"Add CW, Phone
    /// and Digital points. Then multiply by Power Level multiplier. Then
    /// multiply by your multiplier count"*, and rounding at the intermediate
    /// step would score 12 here (⌊3 × 1.5⌋ × 3) rather than 13 (⌊9 × 1.5⌋).
    func testTheFractionIsResolvedOnceRatherThanAtEveryStep() throws {
        let s = ScoreEngine.score(log: log(power: .low), party: try party(power: #"{"LOW":1.5}"#))
        XCTAssertEqual(s.total - s.bonusPoints, 13, "⌊9 × 1.5⌋, not ⌊3 × 1.5⌋ × 3 = 12")
    }

    /// **Neither sponsor states a rounding rule for the final score.** Vermont's
    /// only rounding instruction anywhere in its document is rule 7(B)(f), which
    /// rounds a fractional *multiplier* count DOWN; Wisconsin's rules, multiplier
    /// list and Cabrillo guide contain no rounding language at all. Down is
    /// therefore the sponsors' own idiom where one exists, and the direction that
    /// cannot overstate a `CLAIMED-SCORE:` where none does.
    func testAHalfIsRoundedDown() throws {
        let party = try party(power: #"{"LOW":1.5}"#)
        var log = self.log(power: .low)
        log.qsos = Array(log.qsos.prefix(1))  // 1 point × 1 mult = 1, ×1.5 = 1.5
        let s = ScoreEngine.score(log: log, party: party)

        XCTAssertEqual(s.qsoPoints, 1)
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.total - s.bonusPoints, 1, "1.5 rounds down to 1, never up to 2")
    }

    /// The factor multiplies QSO points × multipliers and stops there. Wisconsin
    /// is explicit about the order: *"Then multiply by your multiplier count
    /// under MULTIPLIERS. Finally, add your bonus points."*
    func testBonusPointsAreNotScaledByTheFactor() throws {
        let s = ScoreEngine.score(log: log(power: .low), party: try party(power: #"{"LOW":2}"#))
        XCTAssertEqual(s.total, 3 * 3 * 2 + 100, "the 100-point bonus is added, not doubled")
    }

    // MARK: Nothing that worked before changes

    /// Whole-number factors — every one in the catalogue today — behave exactly
    /// as they did when the field was `[String: Int]`.
    func testWholeNumberFactorsScoreExactlyAsBefore() throws {
        let party = try party(power: #"{"QRP":5,"LOW":2,"HIGH":1}"#)
        for (power, factor) in [(StationProfile.CategoryPower.qrp, 5), (.low, 2), (.high, 1)] {
            let s = ScoreEngine.score(log: log(power: power), party: party)
            XCTAssertEqual(s.total, s.qsoPoints * s.multiplierCount * factor + s.bonusPoints,
                           "\(power.rawValue) should score the plain integer product")
        }
    }

    /// A party with no `scoreMultipliers` is untouched: the factor is 1 and the
    /// total is the product it always was.
    func testAPartyWithNoFactorIsUnaffected() throws {
        let s = ScoreEngine.score(log: log(power: .qrp), party: try party())
        XCTAssertEqual(s.total, 3 * 3 + 100)
    }

    /// Power × station category still compose by multiplication, and the product
    /// of a fraction and a whole number is exact: 1.5 × 2 = 3.
    func testPowerAndStationCategoryFactorsCompose() throws {
        let party = try party(power: #"{"LOW":1.5}"#, stationCategory: #"{"MOBILE":2}"#)
        let s = ScoreEngine.score(log: log(power: .low, station: .mobile), party: party)
        XCTAssertEqual(s.total, 3 * 3 * 3 + 100, "1.5 × 2 = 3, exactly")
    }

    /// **Article 4's roster.** Every bundled party's factor is a whole number
    /// except the ones listed here, so a party gaining a fraction is an edit to
    /// this line rather than a silent change of scoring shape.
    func testOnlyTheRosteredPartiesShipAFractionalFactor() {
        var fractional: Set<String> = []
        for party in PartyCatalog.loadBundled() {
            guard let mults = party.scoreMultipliers else { continue }
            for power in StationProfile.CategoryPower.allCases {
                for station in StationProfile.CategoryStation.allCases
                where !mults.factor(power: power, station: station).isWholeNumber {
                    fractional.insert(party.id)
                }
            }
        }
        XCTAssertEqual(fractional, [], "no bundled party ships a fractional factor yet")
    }

    // MARK: The wire form

    /// A party file writes what the sponsor prints. `2` and `1.5` are both
    /// numbers, and both land as exact fractions.
    func testAPartyFileCarriesTheNumberTheSponsorPrints() throws {
        let party = try party(power: #"{"QRP":2,"LOW":1.5,"HIGH":1,"X":1.25}"#)
        let power = try XCTUnwrap(party.scoreMultipliers?.power)

        XCTAssertEqual(power["QRP"], ScoreFactor(numerator: 2, denominator: 1))
        XCTAssertEqual(power["LOW"], ScoreFactor(numerator: 3, denominator: 2))
        XCTAssertEqual(power["HIGH"], .one)
        XCTAssertEqual(power["X"], ScoreFactor(numerator: 5, denominator: 4), "1.25 = 5⁄4")
    }

    /// A fraction survives an encode/decode round trip, and is written back as
    /// the decimal it was authored as rather than as a pair of integers.
    func testAFactorRoundTripsAsTheDecimalItWasAuthoredAs() throws {
        let original = try XCTUnwrap(try party(power: #"{"LOW":1.5,"HIGH":1}"#).scoreMultipliers)
        let data = try JSONEncoder().encode(original)

        XCTAssertEqual(
            try JSONDecoder().decode(PartyDefinition.ScoreMultipliers.self, from: data),
            original
        )
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(text.contains("1.5"), "written as a number, not {\"numerator\":3,…}: \(text)")
    }

    // MARK: The contest archive (constitution Article 4 — stored history)

    /// A snapshot written before fractional factors existed carries a bare
    /// whole number under `categoryFactor`, which is exactly what it meant.
    func testASnapshotWrittenBeforeFractionalFactorsDecodesUnchanged() throws {
        let legacy = """
        {"qsoPoints":100,"multiplierCount":20,"bonusPoints":500,
         "categoryFactor":4,"total":8500,"multsByClass":{"county":20}}
        """
        let figures = try JSONDecoder().decode(
            ScoreSnapshot.Figures.self, from: Data(legacy.utf8)
        )
        XCTAssertEqual(figures.categoryFactor, 4)
        XCTAssertEqual(figures.total, 8500, "the archived total is never recomputed")
    }

    /// A fractional factor survives the archive — and the whole-number key an
    /// older build reads is still there, holding the ×1 that build would have
    /// applied rather than a number that cannot be true.
    func testAFractionalFactorSurvivesTheArchive() throws {
        let figures = ScoreSnapshot.Figures(
            qsoPoints: 100, multiplierCount: 20, multiplierCap: nil, bonusPoints: 500,
            categoryFactor: ScoreFactor(numerator: 3, denominator: 2),
            total: 3500, multsByClass: [:]
        )
        let data = try JSONEncoder().encode(figures)
        XCTAssertEqual(try JSONDecoder().decode(ScoreSnapshot.Figures.self, from: data), figures)

        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        XCTAssertEqual(json["categoryFactor"] as? Int, 1,
                       "the legacy key holds what a build without fractions would have applied")
        XCTAssertNotNil(json["categoryFactorExact"], "the exact factor rides alongside it")
    }

    /// Every archive in the field today has a whole-number factor, and its bytes
    /// must not change: no `categoryFactorExact` key appears where the factor is
    /// a whole number.
    func testAWholeNumberFactorWritesTheSameBytesAsBefore() throws {
        let figures = ScoreSnapshot.Figures(
            qsoPoints: 100, multiplierCount: 20, multiplierCap: nil, bonusPoints: 500,
            categoryFactor: 4, total: 8500, multsByClass: [:]
        )
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(figures))
                as? [String: Any]
        )
        XCTAssertEqual(json["categoryFactor"] as? Int, 4)
        XCTAssertNil(json["categoryFactorExact"])
    }
}

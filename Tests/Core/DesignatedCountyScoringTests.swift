import XCTest
@testable import QSOPartyLogger

/// The two shapes a sponsor uses to make a **named subset of counties** score
/// differently, pinned on a synthetic party so the arithmetic is visible in one
/// place rather than inside whichever sponsor happens to use each:
///
/// - `countyPointFactor` — those counties pay a multiple of the ordinary QSO
///   points, **inside** the multiplication;
/// - `BonusRule.designatedCountySweep` — working `need` of them pays once,
///   **after** the multiplication.
///
/// North Carolina has both ("Rarest of NC": 10× QSO points, and 500 for five of
/// the ten), and the placement either side of the multiplier is the sponsor's
/// own distinction, not a modelling convenience. Its own commit under Article 4,
/// adding no party — `testTheBundledRosterForBothShapesIsPinned` is the proof
/// that every already-bundled party still scores identically.
final class DesignatedCountyScoringTests: XCTestCase {

    /// A synthetic party: six counties, two of them designated at 10×, and a
    /// sweep needing two of a designated three. Points differ per mode so a
    /// scaled table cannot be confused with a flat one.
    func party(
        factor: String? = #"{"counties":["ALL","BAR"],"factor":10}"#,
        bonus: String = #"{"type":"designatedCountySweep","counties":["ALL","BAR","CHA"],"need":2,"points":500}"#,
        homeStationPoints: String? = nil
    ) throws -> PartyDefinition {
        let extras = [
            factor.map { #""countyPointFactor":\#($0)"# },
            homeStationPoints.map { #""homeStationPoints":\#($0)"# },
        ].compactMap { $0 }.map { ",\($0)" }.joined()
        let json = """
        {"schemaVersion":1,"id":"dc","name":"Designated County","cabrilloContest":"DC",
        "homeState":"KS","countyAbbrLength":3,
        "validBands":["80m","40m","20m"],
        "points":{"phone":1,"cw":2,"digital":3},"dupeScope":"bandMode",
        "multipliers":{
          "inState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"},
          "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[\(bonus)],
        "counties":[{"abbr":"ALL","name":"Allen"},{"abbr":"BAR","name":"Barton"},
                    {"abbr":"CHA","name":"Chase"},{"abbr":"DOU","name":"Douglas"},
                    {"abbr":"ELK","name":"Elk"},{"abbr":"FIN","name":"Finney"}]\(extras)}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    var seq: TimeInterval = 0
    func qso(_ county: String, call: String = "W0X", band: Band = .m20, mode: ModeClass = .cw) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: county
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "dc")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    // MARK: countyPointFactor — the multiple, and where it lands

    /// Every mode scales; an undesignated county is untouched.
    func testADesignatedCountyPaysTheFactorAndAnOrdinaryOneDoesNot() throws {
        let p = try party()
        let abbrs = Set(p.counties.map(\.abbr))
        for (mode, base) in [(ModeClass.phone, 1), (.cw, 2), (.digital, 3)] {
            XCTAssertEqual(
                p.pointsTable(forTheirLoc: "ALL", countyAbbrs: abbrs).points(for: mode),
                base * 10, "\(mode) in a designated county"
            )
            XCTAssertEqual(
                p.pointsTable(forTheirLoc: "DOU", countyAbbrs: abbrs).points(for: mode),
                base, "\(mode) in an ordinary county"
            )
        }
    }

    /// A lowercase received location still matches — the exchange is normalised
    /// elsewhere, and a points rule that silently depended on that would be a
    /// wrong number with no symptom.
    func testTheLookupIsCaseInsensitive() throws {
        let p = try party()
        let abbrs = Set(p.counties.map(\.abbr))
        XCTAssertEqual(p.pointsTable(forTheirLoc: "all", countyAbbrs: abbrs).cw, 20)
    }

    /// **The reason this is not a `BonusRule`.** The sponsor: "These points are
    /// added to the rest of the regular QSO Points **prior to MULT
    /// multiplication**."
    ///
    /// One designated and one ordinary county, both CW, so two multipliers:
    ///
    /// | | QSO points | × mults | total |
    /// | --- | --- | --- | --- |
    /// | no factor | 2 + 2 = 4 | × 2 | **8** |
    /// | 10× factor | 20 + 2 = 22 | × 2 | **44** |
    ///
    /// The gain is 36 — `9 × 2 points × 2 mults`. Added *after* the
    /// multiplication it would have been 18, so this assertion is what
    /// distinguishes the two placements.
    func testTheFactorLandsInsideTheMultiplication() throws {
        let rows = [qso("ALL", call: "W0A"), qso("CHA", call: "W0C")]

        // No bonus rule on either side, so `total` is the points half alone.
        let without = ScoreEngine.score(log: log(rows), party: try party(factor: nil, bonus: ""))
        XCTAssertEqual(without.qsoPoints, 4)
        XCTAssertEqual(without.multiplierCount, 2)
        XCTAssertEqual(without.total, 8)

        let with = ScoreEngine.score(log: log(rows), party: try party(bonus: ""))
        XCTAssertEqual(with.qsoPoints, 22, "20 for the designated county, 2 for the ordinary one")
        XCTAssertEqual(with.multiplierCount, 2, "the factor must not touch the multiplier tally")
        XCTAssertEqual(with.total, 44)

        XCTAssertEqual(with.total - without.total, 9 * 2 * 2,
                       "9 × points × mults — a bonus placement would gain only 9 × points")
        XCTAssertEqual(with.bonusPoints, without.bonusPoints,
                       "the factor is not a bonus and must not appear as one")
    }

    /// Both location-keyed points rules on one party: `homeStationPoints`
    /// chooses the base table, the factor then scales *that* — "10× QSO points"
    /// meaning ten times whatever the contact was otherwise worth.
    func testTheFactorScalesTheHomeStationTableWhenBothApply() throws {
        let p = try party(homeStationPoints: #"{"phone":5,"cw":7,"digital":9}"#)
        let abbrs = Set(p.counties.map(\.abbr))
        XCTAssertEqual(p.pointsTable(forTheirLoc: "DOU", countyAbbrs: abbrs).cw, 7,
                       "ordinary home-state county — the home table, unscaled")
        XCTAssertEqual(p.pointsTable(forTheirLoc: "ALL", countyAbbrs: abbrs).cw, 70,
                       "designated home-state county — the home table, scaled")
        XCTAssertEqual(p.pointsTable(forTheirLoc: "TX", countyAbbrs: abbrs).cw, 2,
                       "not a county at all — the ordinary table")
    }

    /// The Article 4 guarantee for the points half: a file with no
    /// `countyPointFactor` decodes to `nil` and pays exactly what it paid before
    /// the field existed, for every county and every mode.
    func testAbsentFactorLeavesEveryPointsValueUnchanged() throws {
        let p = try party(factor: nil)
        XCTAssertNil(p.countyPointFactor)
        let abbrs = Set(p.counties.map(\.abbr))
        for county in p.counties.map(\.abbr) + ["TX", "DX"] {
            for (mode, base) in [(ModeClass.phone, 1), (.cw, 2), (.digital, 3)] {
                XCTAssertEqual(
                    p.pointsTable(forTheirLoc: county, countyAbbrs: abbrs).points(for: mode),
                    base, "\(county)/\(mode)"
                )
            }
        }
    }

    func testTheFactorRoundTripsThroughJSON() throws {
        let p = try party()
        let factor = try XCTUnwrap(p.countyPointFactor)
        XCTAssertEqual(factor.counties, ["ALL", "BAR"])
        XCTAssertEqual(factor.factor, 10)
        XCTAssertTrue(factor.applies(to: "BAR"))
        XCTAssertFalse(factor.applies(to: "CHA"))

        let round = try JSONDecoder().decode(
            PartyDefinition.CountyPointFactor.self, from: JSONEncoder().encode(factor)
        )
        XCTAssertEqual(round, factor)
    }

    // MARK: designatedCountySweep — the threshold, and what counts toward it

    /// Pays at `need`, not before, and **once** however far past it the log
    /// goes: "at least one QSO … in five of the counties, 500 additional bonus
    /// points … This would constitute a sweep."
    func testTheSweepPaysAtTheThresholdAndOnlyOnce() throws {
        let p = try party()
        let one = ScoreEngine.score(log: log([qso("ALL", call: "W0A")]), party: p)
        XCTAssertEqual(one.bonusPoints, 0, "one of the designated three is short of two")

        let two = ScoreEngine.score(
            log: log([qso("ALL", call: "W0A"), qso("BAR", call: "W0B")]), party: p)
        XCTAssertEqual(two.bonusPoints, 500)

        let all = ScoreEngine.score(
            log: log([qso("ALL", call: "W0A"), qso("BAR", call: "W0B"), qso("CHA", call: "W0C")]),
            party: p)
        XCTAssertEqual(all.bonusPoints, 500, "all three still pays the one 500, not 1000")
    }

    /// The distinction from `sweepTiers`, which counts *any* county: four
    /// counties outside the designated list pay nothing.
    func testCountiesOutsideTheDesignatedListDoNotAdvanceTheSweep() throws {
        let rows = ["CHA", "DOU", "ELK", "FIN"].enumerated().map { i, c in qso(c, call: "W0\(i)") }
        let outside = try party(
            bonus: #"{"type":"designatedCountySweep","counties":["ALL","BAR"],"need":2,"points":500}"#
        )
        let s = ScoreEngine.score(log: log(rows), party: outside)
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.multiplierCount, 4)
        XCTAssertEqual(s.bonusPoints, 0, "four counties, none of them designated")
    }

    /// One designated county worked twice is one county, not two — the sponsor
    /// counts stations *in* five counties, not five QSOs.
    func testTwoQSOsInOneDesignatedCountyAreNotASweep() throws {
        let rows = [
            qso("ALL", call: "W0A", band: .m20),
            qso("ALL", call: "W0B", band: .m40),
        ]
        XCTAssertEqual(ScoreEngine.score(log: log(rows), party: try party()).bonusPoints, 0)
    }

    /// A dupe is not a contest QSO, so it cannot be the one that reaches the
    /// threshold — and the county it names was already counted from its first
    /// occurrence, so the result is unchanged either way.
    func testADupeNeitherAddsNorRemovesTheSweep() throws {
        var dupe = qso("BAR", call: "W0B")
        dupe.id = UUID()
        let rows = [qso("ALL", call: "W0A"), qso("BAR", call: "W0B"), dupe]
        let s = ScoreEngine.score(log: log(rows), party: try party())
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.bonusPoints, 500)
    }

    /// The sidebar's progress readout and the score are the same computation,
    /// so a log one short of the threshold cannot show a completed sweep.
    func testTheProgressHelperMatchesWhatTheBonusPaysOn() throws {
        let p = try party()
        let short = log([qso("ALL", call: "W0A"), qso("DOU", call: "W0D")])
        XCTAssertEqual(
            ScoreEngine.designatedCountiesWorked(["ALL", "BAR", "CHA"], log: short, party: p),
            ["ALL"]
        )
        XCTAssertEqual(ScoreEngine.score(log: short, party: p).bonusPoints, 0)

        let swept = log([qso("ALL", call: "W0A"), qso("bar", call: "W0B")])
        XCTAssertEqual(
            ScoreEngine.designatedCountiesWorked(["ALL", "BAR", "CHA"], log: swept, party: p),
            ["ALL", "BAR"], "the received location is matched case-insensitively"
        )
        XCTAssertEqual(ScoreEngine.score(log: swept, party: p).bonusPoints, 500)
    }

    func testTheSweepRoundTripsThroughJSON() throws {
        let p = try party()
        XCTAssertEqual(
            p.bonuses,
            [.designatedCountySweep(counties: ["ALL", "BAR", "CHA"], need: 2, points: 500)]
        )
        let round = try JSONDecoder().decode(
            [BonusRule].self, from: JSONEncoder().encode(p.bonuses)
        )
        XCTAssertEqual(round, p.bonuses)
    }

    /// The Article 4 guarantee, stated as a test. Adding these two shapes cannot
    /// move any bundled party's score, because this roster is what uses them —
    /// a party joining it is a deliberate edit with its own commit.
    func testTheBundledRosterForBothShapesIsPinned() {
        let parties = PartyCatalog.loadBundled()
        XCTAssertGreaterThan(parties.count, 40, "the catalogue loaded")

        let withFactor = Set(parties.filter { $0.countyPointFactor != nil }.map(\.id))
        XCTAssertEqual(withFactor, [], "no bundled party pays by county yet")

        let withSweep = Set(parties.filter { party in
            party.bonuses.contains {
                if case .designatedCountySweep = $0 { return true }
                return false
            }
        }.map(\.id))
        XCTAssertEqual(withSweep, [], "no bundled party sweeps a named subset yet")
    }
}

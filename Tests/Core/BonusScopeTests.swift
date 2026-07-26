import XCTest
@testable import QSOPartyLogger

/// `BonusRule.workStation`'s four scopes, pinned against one another on a single
/// synthetic log — so the arithmetic that separates them is visible in one place
/// rather than spread across the parties that happen to use each.
///
/// `perBandMode` was added for SCQP: "Bonus Stations may be worked ONCE per BAND
/// per MODE for bonus points. You may work a bonus station more than once per
/// band per mode for additional QSO points and multipliers." Its own commit
/// under Article 4, adding no party — `testTheOtherThreeScopesAreUnchanged`
/// is the proof that every already-bundled party still scores identically.
final class BonusScopeTests: XCTestCase {

    /// A synthetic party, so the scopes can be compared without waiting for four
    /// sponsors to publish one each.
    func party(scope: String) throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"bs","name":"Bonus Scope","cabrilloContest":"BS",
        "homeState":"KS","countyAbbrLength":3,
        "validBands":["160m","80m","40m","20m"],
        "points":{"phone":1,"cw":1,"digital":1},"dupeScope":"bandMode",
        "multipliers":{
          "inState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"},
          "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[{"type":"workStation","call":"W0BONUS","points":100,"scope":"\(scope)"}],
        "counties":[{"abbr":"ALL","name":"Allen"},{"abbr":"BAR","name":"Barton"}]}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    var seq: TimeInterval = 0
    func qso(band: Band, mode: ModeClass, county: String = "ALL") -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_000_000 + seq),
            call: "W0BONUS", band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: county
        )
    }

    func log(_ qsos: [QSO], party id: String = "bs") -> ContestLog {
        var log = ContestLog(partyID: id)
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    /// The bonus station worked on **two bands × two modes**, plus a second
    /// county on one of those band/mode slots. Six QSOs, and every scope reads
    /// a different number out of them:
    ///
    /// | scope | slots counted | bonus |
    /// | --- | --- | --- |
    /// | `once` | 1 | 100 |
    /// | `perMode` | CW, phone | 200 |
    /// | `perBandMode` | 40/CW, 40/PH, 20/CW, 20/PH | 400 |
    /// | `perQSO` | all six QSOs | 600 |
    func rows() -> [QSO] {
        [
            qso(band: .m40, mode: .cw, county: "ALL"),
            qso(band: .m40, mode: .cw, county: "BAR"),   // mobile changed county
            qso(band: .m40, mode: .phone, county: "ALL"),
            qso(band: .m20, mode: .cw, county: "ALL"),
            qso(band: .m20, mode: .phone, county: "ALL"),
            qso(band: .m20, mode: .phone, county: "BAR"),
        ]
    }

    func testTheFourScopesReadDifferentNumbersFromTheSameLog() throws {
        let expected: [(scope: String, bonus: Int)] = [
            ("once", 100),
            ("perMode", 200),
            ("perBandMode", 400),
            ("perQSO", 600),
        ]
        for e in expected {
            let s = ScoreEngine.score(log: log(rows()), party: try party(scope: e.scope))
            XCTAssertEqual(s.validQSOs, 6, e.scope)
            XCTAssertEqual(s.bonusPoints, e.bonus, "\(e.scope) should pay \(e.bonus)")
        }
    }

    /// The distinction SCQP's own example draws: "You can work WW4SF/CHAR,
    /// WW4SF/GVIL, WW4SF/JASP and WW4SF/HORR on 40m CW, but **only the first
    /// contact with WW4SF on 40m CW will qualify for Bonus Station points**."
    func testPerBandModePaysOnceHoweverManyCountiesTheMobileWorksFrom() throws {
        let p = try party(scope: "perBandMode")
        let fourCounties = [
            qso(band: .m40, mode: .cw, county: "ALL"),
            qso(band: .m40, mode: .cw, county: "BAR"),
            qso(band: .m40, mode: .cw, county: "ALL"),
            qso(band: .m40, mode: .cw, county: "BAR"),
        ]
        let s = ScoreEngine.score(log: log(fourCounties), party: p)
        XCTAssertEqual(s.bonusPoints, 100, "one band, one mode — one bonus")

        // …and a second band/mode slot does add another.
        let plusAnotherBand = fourCounties + [qso(band: .m20, mode: .cw, county: "ALL")]
        XCTAssertEqual(ScoreEngine.score(log: log(plusAnotherBand), party: p).bonusPoints, 200)
    }

    /// Only rows that are valid contest QSOs can pay a bonus, in every scope —
    /// a dupe must not earn one twice.
    func testADupeDoesNotPayTheBonusAgain() throws {
        let p = try party(scope: "perBandMode")
        var dupe = qso(band: .m40, mode: .cw, county: "ALL")
        dupe.id = UUID()
        let rows = [qso(band: .m40, mode: .cw, county: "ALL"), dupe]
        let s = ScoreEngine.score(log: log(rows), party: p)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.bonusPoints, 100)
    }

    /// The Article 4 guarantee, stated as a test: adding a case to
    /// `WorkStationScope` cannot move any bundled party's score, because no
    /// bundled party used the new case before this commit. Every party that has
    /// a `workStation` bonus keeps the scope it shipped with.
    func testTheOtherThreeScopesAreUnchanged() throws {
        let expected: [String: [BonusRule.WorkStationScope]] = [
            "ksqp": [.once],
            "mdc": [.once],
            "warun": [.perMode],
            "tnqp": [.perQSO],
            "ilqp": [.once, .once],
            "vtqp": [.perQSO],
            "bcqp": [.perQSO],
        ]
        for (id, scopes) in expected {
            let party = try XCTUnwrap(PartyCatalog.party(id: id), id)
            let actual: [BonusRule.WorkStationScope] = party.bonuses.compactMap {
                if case .workStation(_, _, let scope) = $0 { return scope }
                return nil
            }
            XCTAssertEqual(actual, scopes, "\(id)'s bonus scopes must not have moved")
        }
    }

    /// The raw value is what a party JSON writes, so it is storage and must not
    /// drift; `once` remains the decoder's default for a bonus with no `scope`.
    func testScopeRawValuesAndTheDecodeDefault() throws {
        XCTAssertEqual(BonusRule.WorkStationScope.perBandMode.rawValue, "perBandMode")
        XCTAssertEqual(BonusRule.WorkStationScope.perMode.rawValue, "perMode")
        XCTAssertEqual(BonusRule.WorkStationScope.perQSO.rawValue, "perQSO")
        XCTAssertEqual(BonusRule.WorkStationScope.once.rawValue, "once")

        let noScope = """
        {"schemaVersion":1,"id":"n","name":"N","cabrilloContest":"N","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[{"type":"workStation","call":"W0X","points":50}],
        "counties":[{"abbr":"ALL","name":"Allen"}]}
        """
        let p = try PartyCatalog.decode(Data(noScope.utf8))
        XCTAssertEqual(p.bonuses, [.workStation(call: "W0X", points: 50, scope: .once)])
    }
}

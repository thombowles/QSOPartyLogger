import XCTest
@testable import QSOPartyLogger

final class ContestRulesTests: XCTestCase {
    func testDupeRuleDefaultsAndDecoding() throws {
        XCTAssertEqual(DupeRule.partyDefault, DupeRule(scope: .bandMode, locationSensitive: true))
        let r = try JSONDecoder().decode(DupeRule.self, from: Data(#"{"scope":"band"}"#.utf8))
        XCTAssertEqual(r, DupeRule(scope: .band, locationSensitive: false))
    }

    func testOperatingTimeAppliesToCategory() throws {
        let rule = try JSONDecoder().decode(OperatingTimeRule.self, from: Data(
            #"{"maxMinutes":1440,"minOffMinutes":60,"appliesTo":{"overlay":"CLASSIC"}}"#.utf8))
        XCTAssertTrue(rule.applies(to: ["overlay": "CLASSIC", "operator": "SINGLE-OP"]))
        XCTAssertFalse(rule.applies(to: ["operator": "SINGLE-OP"]))
        XCTAssertTrue(OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 30).applies(to: [:]))
    }

    func testCategoriesFallBackToTheFullEnums() throws {
        let c = try JSONDecoder().decode(Categories.self, from: Data(#"{"power":["HIGH","LOW"],"overlay":["CLASSIC"]}"#.utf8))
        XCTAssertEqual(c.power, ["HIGH", "LOW"])
        XCTAssertEqual(c.overlay, ["CLASSIC"])
        XCTAssertNil(c.operator)
        XCTAssertEqual(c.allowedOperators, StationProfile.CategoryOperator.allCases.map(\.rawValue))
        XCTAssertEqual(c.allowedPowers, ["HIGH", "LOW"])
        XCTAssertEqual(Categories.all.allowedOverlays, [])
    }

    func testCabrilloSpecDefaults() throws {
        let s = try JSONDecoder().decode(CabrilloSpec.self, from: Data(#"{"contest":"CQ-WW-CW","location":"state"}"#.utf8))
        XCTAssertEqual(s.contest, "CQ-WW-CW")
        XCTAssertEqual(s.location, .state)
        XCTAssertFalse(s.transmitterColumn)
        XCTAssertEqual(s.serialSequence, .contest)
        XCTAssertNil(s.categoryMode)
    }

    func testScoreFactorsAndSideRulesRoundTrip() throws {
        let f = ScoreFactors(power: ["QRP": ScoreFactor(2)], station: nil,
                             entryClasses: [.init(id: "X4", label: "Portable homebrew", factor: ScoreFactor(4))],
                             objectives: [.init(id: "away", label: "Operate away from home", om: 3)],
                             declaredBonuses: [.init(id: "media", label: "Media publicity", points: 100, perCount: nil),
                                               .init(id: "youth", label: "Youth", points: 20, perCount: .init(label: "participants", max: 5))])
        let back = try JSONDecoder().decode(ScoreFactors.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
        let s = SideRules(maxScoredMultipliers: 58, multiplierFloor: 1,
                          granted: [.init(classID: "section", value: "EPA")],
                          activated: .init(classID: "county", minCount: 10, countUnit: .qsos, countScope: .once,
                                           categories: [.mobile, .rover], notOtherwiseWorked: true))
        XCTAssertEqual(try JSONDecoder().decode(SideRules.self, from: JSONEncoder().encode(s)), s)
        XCTAssertEqual(SideRules.none.multiplierFloor, 0)
        XCTAssertNil(SideRules.none.activated)
    }

    func testFamilyRawValues() {
        XCTAssertEqual(ContestFamily.stateQSOParty.rawValue, "stateQSOParty")
        XCTAssertEqual(ContestFamily.allCases.count, 8)  // + .program, 2026-08-25
    }
}

import XCTest
@testable import QSOPartyLogger

final class PointRuleTests: XCTestCase {
    private func ctx(mode: ModeClass = .cw, band: Band = .m20, relation: PointCondition.Relation? = .differentContinent,
                     bothIn: String? = nil, side: String = "all", worked: String = "all",
                     rcvd: [String: String] = [:], kind: String? = nil, call: String = "DL1AA") -> PointCondition.Context {
        .init(modeClass: mode, band: band, relation: relation, sharedContinent: bothIn, side: side, workedSide: worked,
              received: rcvd, workedStationKind: kind, call: call, sets: { _ in nil })
    }

    func testCQWWTableFirstMatchWins() throws {
        let json = """
        [{"when":[{"relation":"sameEntity"}],"points":0},
         {"when":[{"bothInContinent":"NA"}],"points":2},
         {"when":[{"relation":"sameContinent"}],"points":1},
         {"points":3}]
        """
        let rules = try JSONDecoder().decode([PointRule].self, from: Data(json.utf8))
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .sameEntity, bothIn: "NA")), 0)
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .sameContinent, bothIn: "NA")), 2)
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .sameContinent, bothIn: "EU")), 1)
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .differentContinent)), 3)
    }

    func testWPXBandGroups() throws {
        let json = """
        [{"when":[{"relation":"sameEntity"}],"points":1},
         {"when":[{"bothInContinent":"NA","band":["160m","80m","40m"]}],"points":4},
         {"when":[{"bothInContinent":"NA"}],"points":2},
         {"when":[{"relation":"sameContinent","band":["160m","80m","40m"]}],"points":2},
         {"when":[{"relation":"sameContinent"}],"points":1},
         {"when":[{"band":["160m","80m","40m"]}],"points":6},
         {"points":3}]
        """
        let rules = try JSONDecoder().decode([PointRule].self, from: Data(json.utf8))
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m40, relation: .sameContinent, bothIn: "NA")), 4)
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m10, relation: .differentContinent)), 3)
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m80, relation: .differentContinent)), 6)
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m80, relation: .sameEntity)), 1)
    }

    func testModeAndReceivedTokenAndKindAndCall() throws {
        let counties = TokenSet(id: "counties", term: "county", termPlural: "counties", tokens: [.init(abbr: "LIN")])
        let sets: (String) -> TokenSet? = { $0 == "counties" ? counties : nil }
        let rules = [
            PointRule(when: [PointCondition(modeClass: [.cw], receivedTokenIn: .init(element: "location", set: "counties"))], points: 3),
            PointRule(when: [PointCondition(workedStationKind: ["member"])], points: 5),
            PointRule(when: [PointCondition(callsign: ["VE3XYZ"])], points: 10),
            PointRule(when: [PointCondition(modeClass: [.phone])], points: 1),
            PointRule(when: [], points: 2),
        ]
        let c = PointCondition.Context(modeClass: .cw, band: .m20, relation: nil, sharedContinent: nil, side: "inside", workedSide: "inside",
                                       received: ["location": "LIN"], workedStationKind: nil, call: "K5ABC", sets: sets)
        XCTAssertEqual(PointRule.points(rules, c), 3)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .cw, kind: "member")), 5)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .cw, call: "ve3xyz")), 10)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .phone)), 1)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .digital)), 2)
    }
}

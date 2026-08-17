import XCTest
@testable import QSOPartyLogger

final class SideTests: XCTestCase {
    func testDecodesEveryPredicateKind() throws {
        let json = """
        [{"id":"inside","label":"Inside Kansas",
          "predicate":{"kind":"tokenIn","element":"location","set":"counties"},
          "workedPredicate":{"kind":"tokenIn","element":"location","set":"counties"}},
         {"id":"wve","label":"W/VE station",
          "predicate":{"kind":"dxccIn","codes":[291,1]},
          "workedPredicate":{"kind":"dxccIn","codes":[291,1]}},
         {"id":"na","label":"North America",
          "predicate":{"kind":"continentIn","continents":["NA"]},
          "workedPredicate":{"kind":"always"}}]
        """
        let sides = try JSONDecoder().decode([Side].self, from: Data(json.utf8))
        XCTAssertEqual(sides.map(\.id), ["inside", "wve", "na"])
        XCTAssertEqual(sides[0].predicate, SidePredicate(kind: .tokenIn, element: "location", set: "counties"))
        XCTAssertEqual(sides[1].predicate.codes, [291, 1])
        XCTAssertEqual(sides[2].predicate.continents, ["NA"])
        XCTAssertEqual(sides[2].workedPredicate, .always)
    }

    func testTokenInEvaluatesAgainstAnExchange() {
        let counties = TokenSet(id: "counties", term: "county", termPlural: "counties",
                                tokens: [.init(abbr: "LIN"), .init(abbr: "AND")])
        let p = SidePredicate(kind: .tokenIn, element: "location", set: "counties")
        let ctx = SidePredicate.Context(exchange: ["location": ["LIN"]], entityCode: 291, continent: "NA",
                                        sets: { $0 == "counties" ? counties : nil })
        XCTAssertTrue(p.matches(ctx))
        XCTAssertFalse(p.matches(.init(exchange: ["location": ["TX"]], entityCode: 291, continent: "NA",
                                        sets: { $0 == "counties" ? counties : nil })))
    }

    func testDXCCAndContinentEvaluate() {
        let sets: (String) -> TokenSet? = { _ in nil }
        XCTAssertTrue(SidePredicate(kind: .dxccIn, codes: [291, 1])
            .matches(.init(exchange: [:], entityCode: 1, continent: "NA", sets: sets)))
        XCTAssertFalse(SidePredicate(kind: .dxccIn, codes: [291, 1])
            .matches(.init(exchange: [:], entityCode: 110, continent: "OC", sets: sets)))
        XCTAssertTrue(SidePredicate(kind: .continentIn, continents: ["NA"])
            .matches(.init(exchange: [:], entityCode: nil, continent: "NA", sets: sets)))
        XCTAssertTrue(SidePredicate.always.matches(.init(exchange: [:], entityCode: nil, continent: nil, sets: sets)))
    }
}

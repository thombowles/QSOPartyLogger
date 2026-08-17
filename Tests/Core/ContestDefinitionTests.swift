import XCTest
@testable import QSOPartyLogger

final class ContestDefinitionTests: XCTestCase {
    private func fixture() throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try ContestDefinition.decode(try Data(contentsOf: url))
    }

    func testDecodesTheCQWWFixture() throws {
        let c = try fixture()
        XCTAssertEqual(c.id, "cqwwcw")
        XCTAssertEqual(c.family, .dx)
        XCTAssertEqual(c.sides.map(\.id), ["all"])
        XCTAssertEqual(c.exchange.map(\.id), ["rst", "zone"])
        XCTAssertEqual(c.multipliers.map(\.id), ["zone", "country"])
        XCTAssertEqual(c.points.count, 4)
        XCTAssertEqual(c.dupe, DupeRule(scope: .band))
        XCTAssertNil(c.pairing)
        XCTAssertEqual(c.sideRules["all"], nil)
        XCTAssertEqual(c.rules(for: "all"), .none)
        XCTAssertEqual(c.operatingTime?.maxMinutes, 1440)
        XCTAssertEqual(c.cabrillo.contest, "CQ-WW-CW")
        XCTAssertEqual(c.categories.allowedOverlays, ["CLASSIC", "ROOKIE", "YOUTH"])
        XCTAssertTrue(c.bonuses.isEmpty)
        XCTAssertEqual(c.scoreFactors, nil)
        XCTAssertEqual(c.schedule?.first?.start, ISO8601DateFormatter().date(from: "2026-11-28T00:00:00Z"))
    }

    func testTokenSetLookupPrefersTheContestsOwnThenBuiltIns() throws {
        let c = try fixture()
        XCTAssertEqual(c.tokenSet(id: "cqZones")?.tokens.count, 40)
        XCTAssertNil(c.tokenSet(id: "counties"))
        XCTAssertNotNil(c.tokenSet(id: "sections"))
    }

    func testReceivedElementsForASide() throws {
        let c = try fixture()
        XCTAssertEqual(c.receivedElements(for: "all").map(\.id), ["rst", "zone"])
        XCTAssertEqual(c.workableSides(for: "all"), ["all"])
    }

    func testValidateRejectsBrokenReferences() throws {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json")))) as! [String: Any]
        json["points"] = [["when": [["relation": "sameEntity"]], "points": 0]]     // no unconditional rule
        XCTAssertThrowsError(try ContestDefinition.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .pointsWithoutDefault)
        }
        json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json")))) as! [String: Any]
        var mults = json["multipliers"] as! [[String: Any]]
        mults[0]["counting"] = ["nobody": "perBand"]
        json["multipliers"] = mults
        XCTAssertThrowsError(try ContestDefinition.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .unknownSide("nobody"))
        }
    }

    func testValidateRejectsShapeErrors() throws {
        func mutated(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
            var json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(
                Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json")))) as! [String: Any]
            mutate(&json)
            return try JSONSerialization.data(withJSONObject: json)
        }
        // A resolver missing its kind's field.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var mults = json["multipliers"] as! [[String: Any]]
            mults[0]["resolvers"] = [["kind": "cqZone"]]           // no `from`
            json["multipliers"] = mults
        })) { XCTAssertEqual($0 as? ContestValidationError, .badResolver("zone", "cqZone")) }
        // An element nobody sends.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var ex = json["exchange"] as! [[String: Any]]
            ex[1]["sentBy"] = [String: Any]()
            json["exchange"] = ex
        })) { XCTAssertEqual($0 as? ContestValidationError, .elementSentByNobody("zone")) }
        // A derivation that is not a categoryTable.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var ex = json["exchange"] as! [[String: Any]]
            ex[1]["derived"] = ["kind": "lookup", "table": []]
            json["exchange"] = ex
        })) { XCTAssertEqual($0 as? ContestValidationError, .badDerivation("zone")) }
        // A token set with a duplicate abbreviation.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            json["tokenSets"] = [["id": "counties", "term": "county", "termPlural": "counties",
                                  "tokens": [["abbr": "LIN"], ["abbr": "LIN"]]]]
        })) { error in
            guard case .badTokenSet(let id, _)? = error as? ContestValidationError else { return XCTFail("\(error)") }
            XCTAssertEqual(id, "counties")
        }
    }
}

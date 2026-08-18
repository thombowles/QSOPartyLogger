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
        // A zone resolver that names no element — the zone it counts is the
        // received one, so the element it reads is not optional.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var mults = json["multipliers"] as! [[String: Any]]
            mults[0]["resolvers"] = [["kind": "cqZone", "from": "received"]]     // no `element`
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
        // An unsupported schema version.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            json["schemaVersion"] = 1
        })) { XCTAssertEqual($0 as? ContestValidationError, .unsupportedSchemaVersion(1)) }
        // A duplicated side id.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            let side = (json["sides"] as! [[String: Any]])[0]
            json["sides"] = [side, side]
        })) { XCTAssertEqual($0 as? ContestValidationError, .duplicateID("side", "all")) }
        // A multiplier cap naming an unknown side.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var mults = json["multipliers"] as! [[String: Any]]
            mults[0]["caps"] = ["nobody": 3]
            json["multipliers"] = mults
        })) { XCTAssertEqual($0 as? ContestValidationError, .unknownSide("nobody")) }
        // A point rule condition naming an unknown side.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var points = json["points"] as! [[String: Any]]
            points[0]["when"] = [["side": ["nobody"]]]
            json["points"] = points
        })) { XCTAssertEqual($0 as? ContestValidationError, .badPointRule(0, "unknown side")) }
        // A multiplier roster naming a dynamic set.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var mults = json["multipliers"] as! [[String: Any]]
            mults[0]["roster"] = "dxccPrefix"
            json["multipliers"] = mults
        })) { XCTAssertEqual($0 as? ContestValidationError, .badRoster("dxccPrefix")) }
        // An operating-time axis that doesn't exist.
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var operatingTime = json["operatingTime"] as! [String: Any]
            operatingTime["appliesTo"] = ["overlays": "CLASSIC"]
            json["operatingTime"] = operatingTime
        })) { XCTAssertEqual($0 as? ContestValidationError, .badOperatingTimeAxis("overlays")) }
    }

    func testEncodedRoundTripsDates() throws {
        let c = try fixture()
        let back = try ContestDefinition.decode(try c.encoded())
        XCTAssertEqual(back, c)
    }

    func testOwnTokenSetShadowsABuiltIn() throws {
        let f = try fixture()
        let c = ContestDefinition(
            schemaVersion: f.schemaVersion, id: f.id, name: f.name, family: f.family, sponsor: f.sponsor,
            notes: f.notes, caveats: f.caveats, schedule: f.schedule, bands: f.bands, modeClasses: f.modeClasses,
            allowedRawModes: f.allowedRawModes,
            tokenSets: [TokenSet(id: "cqZones", term: "zone", termPlural: "zones", tokens: [.init(abbr: "5")])],
            sides: f.sides, exchange: f.exchange, multipliers: f.multipliers, points: f.points, dupe: f.dupe,
            pairing: f.pairing, sideRules: f.sideRules, bonuses: f.bonuses, scoreFactors: f.scoreFactors,
            operatingTime: f.operatingTime, categories: f.categories, cabrillo: f.cabrillo, sources: f.sources
        )
        XCTAssertEqual(c.tokenSet(id: "cqZones")?.tokens.count, 1)
    }

    func testReceivedElementsHonourPairing() throws {
        let inside = Side(id: "inside", label: "Inside", predicate: .always, workedPredicate: .always)
        let outside = Side(id: "outside", label: "Outside", predicate: .always, workedPredicate: .always)
        let rst = ExchangeElement(id: "rst", kind: .rst, sentBy: ["inside": .init(), "outside": .init()])
        let location = ExchangeElement(id: "location", kind: .token, sentBy: [
            "inside": .init(sets: ["counties"]), "outside": .init(sets: ["usStates"])
        ])
        let call = ExchangeElement(id: "call", kind: .callEcho, sentBy: ["inside": .init(), "outside": .init()])
        let c = ContestDefinition(
            id: "x", name: "X", family: .stateQSOParty, bands: [.m20], modeClasses: [.cw],
            tokenSets: [TokenSet(id: "counties", term: "county", termPlural: "counties", tokens: [.init(abbr: "LIN")])],
            sides: [inside, outside], exchange: [rst, location, call], multipliers: [],
            points: [PointRule(points: 1)], dupe: .partyDefault, pairing: ["outside": ["inside"]],
            cabrillo: CabrilloSpec(contest: "X", location: .state)
        )
        XCTAssertNoThrow(try c.validate())
        XCTAssertEqual(c.workableSides(for: "outside"), ["inside"])
        XCTAssertEqual(c.workableSides(for: "inside"), ["inside", "outside"])
        XCTAssertEqual(c.receivedElements(for: "outside").map(\.id), ["rst", "location"])
        XCTAssertEqual(c.sentElements(for: "inside").map(\.id), ["rst", "location", "call"])
        XCTAssertEqual(c.side(id: "outside")?.label, "Outside")
        XCTAssertNil(c.side(id: "nope"))
    }
}

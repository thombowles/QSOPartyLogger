import XCTest
@testable import QSOPartyLogger

final class ContestDefinitionTests: XCTestCase {
    private func fixture() throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try ContestDefinition.decode(try Data(contentsOf: url))
    }

    /// The same fixture as a JSON dictionary, for tests that mutate one field.
    private func fixtureJSON() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
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

    /// An operating-time rule with no minimum off period (or no maximum)
    /// would credit every empty minute — `OperatingTime.compute` reads both
    /// as ≥ 1, so the file is refused before it can.
    func testOperatingTimeRuleNeedsPositiveMinutes() throws {
        func mutated(_ mutate: (inout [String: Any]) -> Void) throws -> Data {
            var json = try fixtureJSON()
            mutate(&json)
            return try JSONSerialization.data(withJSONObject: json)
        }
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var operatingTime = json["operatingTime"] as! [String: Any]
            operatingTime["minOffMinutes"] = 0
            json["operatingTime"] = operatingTime
        })) { XCTAssertEqual($0 as? ContestValidationError, .badOperatingTime) }
        XCTAssertThrowsError(try ContestDefinition.decode(try mutated { json in
            var operatingTime = json["operatingTime"] as! [String: Any]
            operatingTime["maxMinutes"] = 0
            json["operatingTime"] = operatingTime
        })) { XCTAssertEqual($0 as? ContestValidationError, .badOperatingTime) }
        // The fixture's own rule (1440 / 60) still decodes.
        XCTAssertEqual(try fixture().operatingTime?.minOffMinutes, 60)
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

    /// The workable sides come back in side declaration order — the order
    /// token ownership and the entry hint use — however the pairing row was
    /// written, so an author's `["c", "b"]` cannot reorder which set claims a
    /// token first.
    func testWorkableSidesFollowDeclarationOrderNotThePairingRow() throws {
        let sides = ["a", "b", "c"].map { Side(id: $0, label: $0.uppercased(), predicate: .always, workedPredicate: .always) }
        let rst = ExchangeElement(id: "rst", kind: .rst, sentBy: ["a": .init(), "b": .init(), "c": .init()])
        let c = ContestDefinition(
            id: "abc", name: "ABC", family: .domestic, bands: [.m20], modeClasses: [.cw],
            sides: sides, exchange: [rst], multipliers: [], points: [PointRule(points: 1)],
            dupe: DupeRule(scope: .band), pairing: ["a": ["c", "b"]],
            cabrillo: CabrilloSpec(contest: "ABC", location: .entrantToken)
        )
        XCTAssertNoThrow(try c.validate())
        XCTAssertEqual(c.workableSides(for: "a"), ["b", "c"])
        XCTAssertEqual(c.workableSides(for: "b"), ["a", "b", "c"])
    }

    // MARK: Engine-switch additions

    func testResolvedSideID() throws {
        let c = try fixture()                                   // one side: all
        XCTAssertEqual(c.resolvedSideID("all"), "all")
        XCTAssertEqual(c.resolvedSideID("outside"), "all", "a legacy party side maps to the only side")
        let ks = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "ksqp")))
        XCTAssertEqual(ks.resolvedSideID("inside"), "inside")
        XCTAssertEqual(ks.resolvedSideID("nope"), "outside", "an unknown side on a two-sided contest is the catch-all last side")
    }

    func testCountyRosterAndReceivedElementsWithCallEcho() throws {
        let ks = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "ksqp")))
        XCTAssertEqual(ks.countyRoster()?.id, "counties")
        XCTAssertEqual(ks.countyRoster()?.tokens.count, 105)
        XCTAssertNil(try fixture().countyRoster())
        let f = try fixture()
        let withEcho = ContestDefinition(
            id: "ss", name: "SS", family: .domestic, bands: f.bands, modeClasses: [.cw], sides: f.sides,
            exchange: [ExchangeElement(id: "serial", kind: .serial, sentBy: ["all": .init()]),
                       ExchangeElement(id: "call", kind: .callEcho, sentBy: ["all": .init()]),
                       ExchangeElement(id: "check", kind: .check, sentBy: ["all": .init()])],
            multipliers: [], points: [PointRule(points: 2)], dupe: DupeRule(scope: .contest), cabrillo: CabrilloSpec(contest: "ARRL-SS-CW", location: .section))
        XCTAssertEqual(withEcho.receivedElements(for: "all").map(\.id), ["serial", "check"])
        XCTAssertEqual(withEcho.receivedElements(for: "all", includingCallEcho: true).map(\.id), ["serial", "call", "check"])
    }

    func testCallsignOverridesDecodeAndValidate() throws {
        var json = try fixtureJSON()
        var mults = json["multipliers"] as! [[String: Any]]
        // A dxccEntity resolver reading a received token may name the sets it takes tokens over from.
        json["tokenSets"] = [["id": "states", "term": "state", "termPlural": "states", "tokens": [["abbr": "PA"], ["abbr": "TX"]]]]
        // Keep the fixture's own elements (the zone resolver names `zone`), add a location token element.
        json["exchange"] = (json["exchange"] as! [[String: Any]])
            + [["id": "location", "kind": "token", "sentBy": ["all": ["sets": ["states", "dxccPrefix"]]]]]
        mults[1]["resolvers"] = [["kind": "dxccEntity", "from": "receivedTokenOrCallsign", "element": "location", "list": "arrl",
                                  "callsignOverrides": ["states"]]]
        json["multipliers"] = mults
        let c = try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(c.multipliers[1].resolvers[0].callsignOverrides, ["states"])
        XCTAssertEqual(try ContestDefinition.decode(try c.encoded()), c)
        // Only that resolver shape may carry it, and only for sets the element accepts.
        mults[1]["resolvers"] = [["kind": "dxccEntity", "from": "callsign", "list": "arrl", "callsignOverrides": ["states"]]]
        json["multipliers"] = mults
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .badResolver("country", "dxccEntity"))
        }
        mults[1]["resolvers"] = [["kind": "dxccEntity", "from": "receivedTokenOrCallsign", "element": "location", "list": "arrl",
                                  "callsignOverrides": ["provinces"]]]
        json["multipliers"] = mults
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .unknownTokenSet("provinces"))
        }
    }

    func testReportColumnDecodesWithDefaultFalse() throws {
        XCTAssertFalse(try fixture().cabrillo.reportColumn)
        var json = try fixtureJSON()
        var cab = json["cabrillo"] as! [String: Any]; cab["reportColumn"] = true; json["cabrillo"] = cab
        XCTAssertTrue(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json)).cabrillo.reportColumn)
    }

    func testCountyKeyedBonusesNeedACountyRoster() throws {
        var json = try fixtureJSON()
        json["bonuses"] = [["type": "sweepTiers", "tiers": [["count": 10, "points": 100]]]]
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .bonusNeedsCountyClass)
        }
        // A designated sweep must name tokens of that roster.
        let ks = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "ksqp")))
        let bad = ContestDefinition(id: ks.id, name: ks.name, family: ks.family, bands: ks.bands, modeClasses: ks.modeClasses,
                                    tokenSets: ks.tokenSets, sides: ks.sides, exchange: ks.exchange, multipliers: ks.multipliers,
                                    points: ks.points, dupe: ks.dupe, pairing: ks.pairing, sideRules: ks.sideRules,
                                    bonuses: [.designatedCountySweep(counties: ["MRN", "ZZZ"], need: 1, points: 500)],
                                    cabrillo: ks.cabrillo)
        XCTAssertThrowsError(try bad.validate()) { error in
            XCTAssertEqual(error as? ContestValidationError, .unknownBonusToken("ZZZ"))
        }
    }

    func testScoreFactorIdsMustBeUnique() throws {
        var json = try fixtureJSON()
        json["scoreFactors"] = ["objectives": [["id": "1o", "label": "a", "om": 1], ["id": "1o", "label": "b", "om": 2]]]
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .duplicateID("objective", "1o"))
        }
    }

    /// An activated multiplier is earned by operating from a token of its
    /// class's roster; the class must list one. Tennessee's inside side has
    /// the activated-county rule — the same contest with the county class's
    /// roster dropped is refused for it.
    func testActivatedRuleNeedsAClassWithARoster() throws {
        let tn = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "tnqp")))
        XCTAssertEqual(tn.sideRules["inside"]?.activated?.classID, "county")
        let county = try XCTUnwrap(tn.multipliers.first { $0.id == "county" })
        XCTAssertNotNil(county.roster)
        let rosterless = MultiplierClass(id: county.id, term: county.term, termPlural: county.termPlural,
                                         resolvers: county.resolvers, counting: county.counting, caps: county.caps,
                                         roster: nil, layout: county.layout)
        // Every other field copied — except the bonuses: Tennessee's
        // activated-county bonus is county-keyed, and a missing county roster
        // is reported as that bonus's problem first (`bonusNeedsCountyClass`).
        // The guard under test is the activated rule's own.
        let bad = ContestDefinition(
            schemaVersion: tn.schemaVersion, id: tn.id, name: tn.name, family: tn.family, sponsor: tn.sponsor,
            notes: tn.notes, caveats: tn.caveats, schedule: tn.schedule, bands: tn.bands, modeClasses: tn.modeClasses,
            allowedRawModes: tn.allowedRawModes, tokenSets: tn.tokenSets, sides: tn.sides, exchange: tn.exchange,
            multipliers: tn.multipliers.map { $0.id == "county" ? rosterless : $0 }, points: tn.points, dupe: tn.dupe,
            pairing: tn.pairing, sideRules: tn.sideRules, bonuses: [], scoreFactors: tn.scoreFactors,
            operatingTime: tn.operatingTime, categories: tn.categories, cabrillo: tn.cabrillo, sources: tn.sources
        )
        XCTAssertThrowsError(try bad.validate()) { error in
            XCTAssertEqual(error as? ContestValidationError, .activatedNeedsRoster("county"))
        }
    }
}

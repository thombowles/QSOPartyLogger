import XCTest
@testable import QSOPartyLogger

final class PartyLoweringTests: XCTestCase {
    private func lowered(_ id: String) throws -> ContestDefinition {
        try PartyLowering.lower(try XCTUnwrap(PartyCatalog.party(id: id)))
    }
    private func party(_ id: String) throws -> PartyDefinition { try XCTUnwrap(PartyCatalog.party(id: id)) }

    func testEveryBundledPartyLowersAndValidates() throws {
        let parties = PartyCatalog.loadBundled()
        XCTAssertEqual(parties.count, 50)
        for p in parties {
            let c = try PartyLowering.lower(p)
            XCTAssertNoThrow(try c.validate(), p.id)
            XCTAssertEqual(c.id, p.id)
            XCTAssertEqual(c.name, p.name)
            XCTAssertEqual(c.cabrillo.contest, p.cabrilloContest)
            XCTAssertEqual(c.bands, p.validBands, p.id)
            XCTAssertEqual(c.modeClasses, p.allowedModeClasses, p.id)
            XCTAssertEqual(c.schedule, p.schedule, p.id)
            XCTAssertEqual(c.caveats, p.caveats, p.id)
            XCTAssertEqual(c.dupe, .partyDefault, p.id)
            XCTAssertEqual(c.family, .stateQSOParty, p.id)
            XCTAssertEqual(c.bonuses, p.bonuses, p.id)
            XCTAssertEqual(c.sources.hubSpots, p.hubSpots, p.id)
            XCTAssertEqual(c.sources.callHistory, p.callHistory, p.id)
            XCTAssertEqual(c.sources.combines, p.combines, p.id)
            // The location element is always present and always a token element.
            let loc = try XCTUnwrap(c.exchange.first { $0.id == "location" }, p.id)
            XCTAssertEqual(loc.kind, .token, p.id)
            XCTAssertTrue(loc.fixed, p.id)
            XCTAssertEqual(loc.cabrilloWidth, 6, p.id)
            // Sides.
            XCTAssertEqual(c.sides.map(\.id), p.hasHomeRegion ? ["inside", "outside"] : ["all"], p.id)
            // Class ids are the union of both sides' classes, in MultClass order.
            let expected = MultClass.allCases.filter {
                p.multipliers.inState.classes.contains($0) || p.multipliers.outState.classes.contains($0)
            }.map(\.rawValue)
            XCTAssertEqual(c.multipliers.map(\.id), expected, p.id)
            // The last points rule is unconditional.
            XCTAssertEqual(c.points.last?.when, [], p.id)
        }
    }

    func testKansasShape() throws {
        let c = try lowered("ksqp"), p = try party("ksqp")
        XCTAssertEqual(c.sides[0].label, "Inside KS")
        XCTAssertEqual(c.sides[0].predicate, SidePredicate(kind: .tokenIn, element: "location", set: "counties"))
        XCTAssertEqual(c.sides[1].predicate, .always)
        XCTAssertEqual(c.exchange.map(\.id), ["rst", "location"])
        let loc = c.exchange[1]
        XCTAssertEqual(loc.sentBy["inside"]?.sets, ["counties"])
        XCTAssertEqual(loc.sentBy["inside"]?.multi?.max, min(4, p.maxSimultaneousCounties))
        XCTAssertEqual(loc.sentBy["outside"]?.sets, ["states", "provinces", "dxToken"])
        XCTAssertNil(loc.sentBy["outside"]?.multi)
        XCTAssertEqual(loc.label, "\(p.countyTerm.sentenceCased)/State")
        XCTAssertEqual(c.tokenSet(id: "counties")?.tokens.count, 105)
        XCTAssertEqual(c.tokenSet(id: "counties")?.term, "county")
        XCTAssertFalse(try XCTUnwrap(c.tokenSet(id: "states")).accepts("KS"))   // excludedStateTokens
        XCTAssertTrue(try XCTUnwrap(c.tokenSet(id: "states")).accepts("TX"))
        XCTAssertEqual(c.cabrillo.location, .state)
        // ksqp.json carries `"outStateWorksHomeStationsOnly": true`, so the
        // outside side pairs with the inside one — Kansas is not the exception
        // to that rule; MEQP is the only bundled party that sets it false.
        XCTAssertEqual(c.pairing, ["outside": ["inside"]])
        // KSQP in-state: states+provinces+dx, home state via county.
        let state = try XCTUnwrap(c.multipliers.first { $0.id == "state" })
        XCTAssertEqual(state.counting["inside"], p.multipliers.inState.countScope)
        XCTAssertTrue(state.resolvers.contains { $0.kind == .receivedToken && $0.set == "counties" && $0.mapTo == "group" && $0.sides == ["inside"] })
        XCTAssertEqual(state.resolvers.first?.set, "states")
        XCTAssertEqual(c.tokenSet(id: "counties")?.tokens.first?.group, "KS")
        XCTAssertEqual(c.points, [
            PointRule(when: [PointCondition(modeClass: [.phone])], points: p.points.phone),
            PointRule(when: [PointCondition(modeClass: [.cw])], points: p.points.cw),
            PointRule(when: [PointCondition(modeClass: [.digital])], points: p.points.digital),
            PointRule(points: p.points.phone),
        ])
    }

    func testNAQPHasOneSideAndAName() throws {
        let c = try lowered("naqpcw")
        XCTAssertEqual(c.sides.map(\.id), ["all"])
        XCTAssertEqual(c.exchange.map(\.id), ["name", "location"])
        XCTAssertEqual(c.exchange[1].sentBy["all"]?.sets, ["counties", "states", "provinces", "dxToken"])
        XCTAssertEqual(c.exchange[1].sentBy["all"]?.multi?.max, 1)
        // One side sends the entity list and the states together, so the
        // repeatable list is named: several entities, never several states.
        XCTAssertEqual(c.exchange[1].sentBy["all"]?.multi?.sets, ["counties"])
        XCTAssertEqual(c.tokenSet(id: "counties")?.term, "NA entity")
        XCTAssertEqual(c.cabrillo.location, .entrantToken)
        XCTAssertEqual(c.multipliers.first { $0.id == "county" }?.counting, ["all": .perBand])
    }

    func testPennsylvaniaUsesSectionsInsteadOfStates() throws {
        let c = try lowered("paqp")
        XCTAssertEqual(c.exchange.first { $0.id == "location" }?.sentBy["outside"]?.sets, ["sections", "dxToken"])
        XCTAssertNotNil(c.tokenSet(id: "sections"))
        XCTAssertNil(c.tokenSet(id: "states"))
        XCTAssertEqual(c.multipliers.first { $0.id == "section" }?.resolvers.first?.set, "sections")
        XCTAssertEqual(c.rules(for: "inside").granted.map(\.value).sorted(), ["EPA", "WPA"])
    }

    func testMarylandDCPairsOutsideWithInsideOnly() throws {
        let c = try lowered("mdc")
        XCTAssertEqual(c.pairing, ["outside": ["inside"]])
        XCTAssertEqual(c.exchange.map(\.id), ["location"])          // no RST
    }

    func testCaliforniaSerialAndScoredCap() throws {
        let c = try lowered("cqp")
        let serial = try XCTUnwrap(c.exchange.first { $0.id == "serial" })
        XCTAssertFalse(serial.fixed)
        XCTAssertEqual(serial.kind, .serial)
        XCTAssertEqual(c.rules(for: "inside").maxScoredMultipliers, 58)
    }

    func testFloridaDXAliases() throws {
        let c = try lowered("fqp")
        XCTAssertEqual(c.tokenSet(id: "dxAliases")?.abbrs, ["R1", "R2", "R3"])
        let dx = try XCTUnwrap(c.multipliers.first { $0.id == "dx" })
        XCTAssertEqual(dx.resolvers[0].kind, .receivedToken)
        XCTAssertEqual(dx.resolvers[0].set, "dxAliases")
        XCTAssertEqual(dx.resolvers[1].kind, .dxccEntity)
        XCTAssertEqual(dx.resolvers[1].from, .receivedTokenOrCallsign)
        XCTAssertTrue(try XCTUnwrap(c.exchange.first { $0.id == "location" }?.sentBy["outside"]?.sets).contains("dxccPrefix"))
    }

    func testSkeeterMemberElementAndPoints() throws {
        let c = try lowered("skeeter"), p = try party("skeeter")
        let member = try XCTUnwrap(c.exchange.first { $0.id == "member" })
        XCTAssertEqual(member.kind, .memberOrPower)
        XCTAssertEqual(member.member?.term, p.memberExchange?.term)
        XCTAssertEqual(c.points, [
            PointRule(when: [PointCondition(workedStationKind: ["member"])], points: 3),
            PointRule(when: [PointCondition(workedStationKind: ["qrp"])], points: 2),
            PointRule(points: 1),
        ])
        XCTAssertEqual(c.scoreFactors?.entryClasses.count, 4)
        XCTAssertEqual(c.multipliers.first { $0.id == "dx" }?.resolvers.last?.countEntities, true)
    }

    func testBumblebeesMemberClassAndFloor() throws {
        let c = try lowered("fobb")
        let member = try XCTUnwrap(c.multipliers.first { $0.id == "member" })
        XCTAssertEqual(member.resolvers.first?.kind, .workedStation)
        XCTAssertEqual(member.resolvers.first?.element, "member")
        XCTAssertEqual(member.layout, .workedOnly)
        XCTAssertEqual(c.rules(for: "all").multiplierFloor, 1)
    }

    func testNorthCarolinaScalesDesignatedCounties() throws {
        let c = try lowered("ncqp"), p = try party("ncqp")
        let designated = try XCTUnwrap(c.tokenSet(id: "designatedCounties"))
        XCTAssertEqual(designated.tokens.count, p.countyPointFactor?.counties.count)
        XCTAssertEqual(c.points.count, 7)      // 3 designated + 3 by mode + the unconditional tail
        XCTAssertEqual(c.points[0], PointRule(
            when: [PointCondition(modeClass: [.phone], receivedTokenIn: .init(element: "location", set: "designatedCounties"))],
            points: p.points.phone * (p.countyPointFactor?.factor ?? 0)))
        XCTAssertEqual(c.points[3], PointRule(when: [PointCondition(modeClass: [.phone])], points: p.points.phone))
    }

    func testMaineHomeStationPoints() throws {
        let c = try lowered("meqp"), p = try party("meqp")
        XCTAssertEqual(c.points[0], PointRule(
            when: [PointCondition(modeClass: [.phone], receivedTokenIn: .init(element: "location", set: "counties"))],
            points: p.homeStationPoints?.phone ?? -1))
        XCTAssertEqual(c.points.count, 7)      // 3 home-station + 3 by mode + the unconditional tail
    }

    func testSeventhAreaCountiesCarryTheirState() throws {
        let c = try lowered("sevenqp"), p = try party("sevenqp")
        let counties = try XCTUnwrap(c.tokenSet(id: "counties"))
        // Eight member states, not seven — the 7th call area is what W7 means,
        // and Washington is in it (sevenqp.json's own notes, and
        // `SeventhCallAreaQSOPartyTests` asserting `homeStates.count == 8`).
        XCTAssertEqual(Set(counties.tokens.compactMap(\.group)), Set(p.homeStates))
        XCTAssertEqual(Set(counties.tokens.compactMap(\.group)).count, 8)
        XCTAssertFalse(try XCTUnwrap(c.tokenSet(id: "states")).accepts("ID"))
        XCTAssertEqual(c.sides[0].label, "Inside the 7th call area")
    }

    func testTennesseeActivatedCountyRuleAndSalmonRunCap() throws {
        let tn = try lowered("tnqp"), tnp = try party("tnqp")
        let act = try XCTUnwrap(tn.rules(for: "inside").activated)
        XCTAssertEqual(act.classID, "county")
        XCTAssertEqual(act.minCount, tnp.multipliers.inState.activatedCountyMultiplier?.minCount)
        let wa = try lowered("warun"), wap = try party("warun")
        XCTAssertEqual(wa.multipliers.first { $0.id == "dx" }?.caps?["inside"], wap.multipliers.inState.dxMultCap)
    }

    /// A lowered party is a v2 file: every field it sets survives being written
    /// and read back, and the reader's own `validate()` accepts it.
    func testLoweredContestsRoundTripThroughJSON() throws {
        for id in ["ksqp", "paqp", "skeeter", "sevenqp", "naqpcw"] {
            let c = try lowered(id)
            XCTAssertEqual(try ContestDefinition.decode(try c.encoded()), c, id)
        }
    }

    /// `alqp.json` is the first bundled party alphabetically carrying
    /// `"stateAliases": {"DC": "MD"}` — Alabama credits a DC station as
    /// Maryland, so DC is an accepted spelling but not a token of its own.
    func testStateAliasesCreditTheAliasedState() throws {
        let c = try lowered("alqp")
        let states = try XCTUnwrap(c.tokenSet(id: "states"))
        XCTAssertFalse(states.abbrs.contains("DC"))
        XCTAssertFalse(states.tokens.contains { $0.abbr == "DC" })
        XCTAssertTrue(states.accepts("DC"))
        XCTAssertEqual(states.canonical("DC"), "MD")
        XCTAssertNoThrow(try c.validate())
    }

    /// Ohio lists 11 provinces, not the built-in 13; a contest's own set
    /// shadows the built-in of the same id.
    func testProvinceOverrideShadowsTheBuiltIn() throws {
        let c = try lowered("ohqp")
        XCTAssertEqual(c.tokenSet(id: "provinces")?.tokens.count, 11)
        XCTAssertNotEqual(c.tokenSet(id: "provinces")?.tokens.count, TokenSet.provinces.tokens.count)
    }

    /// azqp.json: the inside side counts states, provinces and DX `perMode`;
    /// the outside side counts counties `perBandMode`. The two sides' classes
    /// are disjoint there, so each class's `counting` carries exactly the side
    /// that counts it, at that side's own scope.
    func testArizonaScopesDifferPerSide() throws {
        let c = try lowered("azqp"), p = try party("azqp")
        XCTAssertNotEqual(p.multipliers.inState.countScope, p.multipliers.outState.countScope)
        let state = try XCTUnwrap(c.multipliers.first { $0.id == "state" })
        XCTAssertEqual(state.counting["inside"], p.multipliers.inState.countScope)
        XCTAssertNil(state.counting["outside"], "Arizona's outside side counts counties, not states")
        let county = try XCTUnwrap(c.multipliers.first { $0.id == "county" })
        XCTAssertEqual(county.counting["outside"], p.multipliers.outState.countScope)
        XCTAssertNil(county.counting["inside"])
        // Hawaii counts the same class on both sides at different scopes —
        // one class, two scopes, which is where a per-contest scope would show.
        let hi = try lowered("hqp"), hip = try party("hqp")
        let hiCounty = try XCTUnwrap(hi.multipliers.first { $0.id == "county" })
        XCTAssertEqual(hiCounty.counting["inside"], hip.multipliers.inState.countScope)
        XCTAssertEqual(hiCounty.counting["outside"], hip.multipliers.outState.countScope)
        XCTAssertNotEqual(hiCounty.counting["inside"], hiCounty.counting["outside"])
    }

    /// MDC excludes both its own tokens: a Maryland or DC station sends a
    /// county, never a state.
    func testMarylandExcludesBothTokens() throws {
        let states = try XCTUnwrap(try lowered("mdc").tokenSet(id: "states"))
        XCTAssertFalse(states.accepts("MD"))
        XCTAssertFalse(states.accepts("DC"))
    }

    /// The assumptions the lowering makes about the whole catalogue. Each would
    /// be a silent scoring change if a party file stopped honouring it.
    func testCatalogueGuards() throws {
        for p in PartyCatalog.loadBundled() {
            for (side, rule) in [("inState", p.multipliers.inState), ("outState", p.multipliers.outState)]
            where rule.homeStateCountsViaCounty {
                // The county→group resolver is added to the state class.
                XCTAssertTrue(rule.classes.contains(.state),
                              "\(p.id) \(side): homeStateCountsViaCounty without the state class")
            }
            // Both would scale the same rows; the lowering writes designated
            // counties first and home stations second, and never both.
            XCTAssertFalse(p.homeStationPoints != nil && p.countyPointFactor != nil,
                           "\(p.id): home-station points and a county point factor would stack")
            if !p.hasHomeRegion {
                // One side, lowered from `outState` — so the unused `inState`
                // rule must say the same thing.
                XCTAssertEqual(p.multipliers.inState, p.multipliers.outState,
                               "\(p.id): a party with no home region has one side; its two rules must agree")
            }
            // A received token belongs to exactly one location class:
            // `ScoreEngine.locationContributions` credits the county and stops,
            // and the lowering gives each class its own set on that assumption.
            // A county abbreviation that is also a state, province or section
            // token would score as whichever the code reached first.
            let countyAbbrs = Set(p.counties.map(\.abbr))
            for (what, other) in [("a state", MultClass.acceptedStateTokens),
                                  ("a province", p.provinces),
                                  ("a section", p.sections)] {
                let clash = countyAbbrs.intersection(other).sorted()
                XCTAssertTrue(clash.isEmpty,
                              "\(p.id): county '\(clash.joined(separator: "', '"))' is also \(what) token")
            }
        }
    }

    func testSkeeterMemberSpecAndEntryClassOrder() throws {
        let c = try lowered("skeeter"), p = try party("skeeter")
        let member = try XCTUnwrap(c.exchange.first { $0.id == "member" })
        XCTAssertEqual(member.member?.qrpMaxWatts, p.memberExchange?.qrpMaxWatts)
        XCTAssertEqual(c.scoreFactors?.entryClasses.map(\.id), p.entryClasses.map(\.id))
        XCTAssertFalse(member.required, "a blank member element is a QRO station, not a missing field")
        // Only the member element is optional. Skeeter sends no name, so the
        // name element's own default is pinned where there is one — NAQP's.
        XCTAssertTrue(try XCTUnwrap(try lowered("naqpcw").exchange.first { $0.id == "name" }).required)
    }

    /// A party with a home region names one `LOCATION:` for everybody inside —
    /// the 7th Call Area's primary state, whichever of its eight the entrant
    /// sits in. A party without one leaves the header to the entrant's token.
    func testMultiStateHomeLocation() throws {
        XCTAssertEqual(try lowered("sevenqp").cabrillo.homeLocation, try party("sevenqp").homeState)
        XCTAssertNil(try lowered("naqpcw").cabrillo.homeLocation)
    }

    /// `SetupSheet` forces `isInState = false` for a party with no home region,
    /// so `ScoreEngine` scores it with `outState` — and so must the single side.
    func testNoHomeRegionUsesTheOutsideRule() throws {
        let c = try lowered("fobb"), p = try party("fobb")
        let member = try XCTUnwrap(c.multipliers.first { $0.id == "member" })
        XCTAssertEqual(member.counting["all"], p.multipliers.outState.countScope)
        // Skeeter and FOBB name no counties. `tokenSet(id:)` falls back to the
        // built-ins, and there is no built-in "counties" — nil is the answer.
        XCTAssertNil(c.tokenSet(id: "counties"))
        XCTAssertNil(try lowered("skeeter").tokenSet(id: "counties"))
        for id in ["fobb", "skeeter"] {
            let sets = try XCTUnwrap(try lowered(id).exchange.first { $0.id == "location" }?.sentBy["all"]?.sets)
            XCTAssertFalse(sets.contains("counties"), id)
        }
    }
}

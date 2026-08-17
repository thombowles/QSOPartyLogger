import Foundation

/// Lowers a QSO-party authoring definition (schema v1) into the general model.
/// Pure and total over the bundled catalogue: `PartyLoweringTests` proves every
/// party lowers and validates. Field-by-field mapping: spec §1.3.
enum PartyLowering {
    static let insideID = "inside", outsideID = "outside", allID = "all"

    /// Validates the result, so a user party file that lowers into an
    /// inconsistent model is rejected here, not at scoring time.
    static func lower(_ p: PartyDefinition) throws -> ContestDefinition {
        let sides = sides(for: p)
        let sideIDs = sides.map(\.id)
        var sets = tokenSets(for: p)
        var points = pointRules(for: p, sets: &sets)
        if points.last?.when.isEmpty != true { points.append(PointRule(points: p.points.phone)) }
        // Exhaustive, so a new v1 dupe scope fails to compile until it maps.
        let dupe: DupeRule = switch p.dupeScope { case .bandMode: .partyDefault }
        let contest = ContestDefinition(
            // TODO(spec §1.3): read PartyDefinition.family once the four non-state parties carry it.
            id: p.id, name: p.name, family: .stateQSOParty, notes: p.notes, caveats: p.caveats,
            schedule: p.schedule, bands: p.validBands, modeClasses: p.allowedModeClasses,
            tokenSets: sets, sides: sides, exchange: exchange(for: p, sideIDs: sideIDs),
            multipliers: multipliers(for: p, sideIDs: sideIDs), points: points, dupe: dupe,
            // No bundled party combines `outStateWorksHomeStationsOnly` with
            // `hasHomeRegion: false`; a single-side contest has no pairing.
            pairing: p.outStateWorksHomeStationsOnly && p.hasHomeRegion ? [outsideID: [insideID]] : nil,
            sideRules: sideRules(for: p, sideIDs: sideIDs), bonuses: p.bonuses,
            scoreFactors: scoreFactors(for: p),
            cabrillo: CabrilloSpec(contest: p.cabrilloContest, location: p.hasHomeRegion ? .state : .entrantToken,
                                   homeLocation: p.hasHomeRegion ? p.homeState : nil),
            sources: ContestSources(hubSpots: p.hubSpots, callHistory: p.callHistory, oneByOne: p.oneByOne, combines: p.combines)
        )
        try contest.validate()
        return contest
    }

    // MARK: Sides

    private static func sides(for p: PartyDefinition) -> [Side] {
        guard p.hasHomeRegion else {
            return [Side(id: allID, label: "Everyone", predicate: .always, workedPredicate: .always)]
        }
        let inCounties = SidePredicate(kind: .tokenIn, element: "location", set: "counties")
        return [
            Side(id: insideID, label: "Inside \(p.inStateLabel)", predicate: inCounties, workedPredicate: inCounties),
            Side(id: outsideID, label: "Outside \(p.inStateLabel)", predicate: .always, workedPredicate: .always),
        ]
    }

    /// The v1 rule that governs a side. Only the `inside` side of a party with
    /// a home region takes `inState`: a party without one has the single `all`
    /// side, and `SetupSheet` forces `isInState = false` for those parties, so
    /// `ScoreEngine` scores their entrants with `party.multipliers.outState`.
    private static func rule(_ p: PartyDefinition, _ side: String) -> PartyDefinition.MultRule {
        side == insideID ? p.multipliers.inState : p.multipliers.outState
    }

    // MARK: Token sets

    private static func tokenSets(for p: PartyDefinition) -> [TokenSet] {
        var out: [TokenSet] = []
        // Skeeter and FOBB name no counties at all — an empty set no side sends
        // and no class counts is noise in the model.
        if !p.counties.isEmpty {
            out.append(TokenSet(id: "counties", term: p.countyTerm, termPlural: p.countyTermPlural,
                                tokens: p.counties.map { TokenSet.Token(abbr: $0.abbr, name: $0.name, group: p.state(forCounty: $0.abbr)) }))
        }
        if p.usesSections {
            out.append(TokenSet(id: "sections", term: "section", termPlural: "sections",
                                tokens: p.sections.sorted().map { TokenSet.Token(abbr: $0) }))
        } else {
            let excluded = Set(p.excludedStateTokens.map { $0.uppercased() })
            let aliasKeys = Set(p.stateAliases.keys.map { $0.uppercased() })
            let states = MultClass.acceptedStateTokens.subtracting(excluded).subtracting(aliasKeys).sorted()
            out.append(TokenSet(id: "states", term: "state", termPlural: "states",
                                tokens: states.map { TokenSet.Token(abbr: $0) }, aliases: p.stateAliases))
            out.append(TokenSet(id: "provinces", term: "province", termPlural: "provinces",
                                tokens: p.provinces.sorted().map { TokenSet.Token(abbr: $0) }))
        }
        if !p.dxTokenAliases.isEmpty {
            out.append(TokenSet(id: "dxAliases", term: "DX", termPlural: "DX",
                                tokens: p.dxTokenAliases.sorted().map { TokenSet.Token(abbr: $0) }))
        }
        return out
    }

    /// What an outside station may send: sections instead of states + provinces
    /// where the party counts sections, then the DX forms it accepts.
    private static func outsideSets(for p: PartyDefinition) -> [String] {
        var sets = p.usesSections ? ["sections"] : ["states", "provinces"]
        if p.acceptsDXToken { sets.append("dxToken") }
        if p.dxStyle == .prefix { sets.append("dxccPrefix") }
        if !p.dxTokenAliases.isEmpty { sets.append("dxAliases") }
        return sets
    }

    // MARK: Exchange

    private static func exchange(for p: PartyDefinition, sideIDs: [String]) -> [ExchangeElement] {
        let all = Dictionary(uniqueKeysWithValues: sideIDs.map { ($0, ExchangeElement.SentSpec()) })
        var out: [ExchangeElement] = []
        if p.exchangeIncludesRST { out.append(ExchangeElement(id: "rst", kind: .rst, sentBy: all, cabrilloWidth: 3)) }
        if p.exchangeIncludesSerial { out.append(ExchangeElement(id: "serial", kind: .serial, label: "QSO #", sentBy: all, cabrilloWidth: 3)) }
        if p.exchangeIncludesName { out.append(ExchangeElement(id: "name", kind: .name, sentBy: all, fixed: true, cabrilloWidth: 3, prefill: [.callHistory, .stationMemory])) }
        let cap = min(ExchangeParser.maxCounties, p.maxSimultaneousCounties)
        let inside = ExchangeElement.SentSpec(sets: ["counties"], multi: .init(max: cap))
        // A party with no counties (Skeeter, FOBB) has no `counties` set to send.
        let single = (p.counties.isEmpty ? [] : ["counties"]) + outsideSets(for: p)
        let sentBy: [String: ExchangeElement.SentSpec] = p.hasHomeRegion
            ? [insideID: inside, outsideID: .init(sets: outsideSets(for: p))]
            : [allID: .init(sets: single, multi: .init(max: cap))]
        out.append(ExchangeElement(
            id: "location", kind: .token,
            label: p.hasHomeRegion ? "\(p.countyTerm.sentenceCased)/State" : "Location",
            sentBy: sentBy, fixed: true, cabrilloWidth: 6, prefill: [.spot, .callHistory, .stationMemory]))
        if let m = p.memberExchange {
            // A blank member element is a valid QRO station, not a missing
            // field: `MemberExchange.workedClass(forReceived: nil)` is `.other`,
            // and `EntryState` logs a row without one.
            out.append(ExchangeElement(
                id: "member", kind: .memberOrPower, label: m.term, shortLabel: m.shortTerm, sentBy: all, fixed: true,
                required: false, cabrilloWidth: 3, prefill: [.callHistory, .stationMemory],
                member: MemberSpec(term: m.term, shortTerm: m.shortTerm, memberPlural: m.memberPlural, qrpMaxWatts: m.qrpMaxWatts)))
        }
        return out
    }

    // MARK: Multipliers

    private static func multipliers(for p: PartyDefinition, sideIDs: [String]) -> [MultiplierClass] {
        let classes = MultClass.allCases.filter { c in sideIDs.contains { rule(p, $0).classes.contains(c) } }
        return classes.map { c in
            var counting: [String: CountScope] = [:]
            for s in sideIDs where rule(p, s).classes.contains(c) { counting[s] = rule(p, s).countScope }
            switch c {
            case .county:
                return MultiplierClass(id: "county", term: p.countyTerm, termPlural: p.countyTermPlural,
                                       resolvers: [Resolver(kind: .receivedToken, element: "location", set: "counties")],
                                       counting: counting, roster: "counties", layout: .groupedTokens)
            case .state:
                var resolvers = [Resolver(kind: .receivedToken, element: "location", set: "states")]
                for s in sideIDs where rule(p, s).homeStateCountsViaCounty {
                    resolvers.append(Resolver(kind: .receivedToken, element: "location", set: "counties", mapTo: "group", sides: [s]))
                }
                return MultiplierClass(id: "state", term: "state", resolvers: resolvers, counting: counting, roster: "states")
            case .province:
                return MultiplierClass(id: "province", term: "province", resolvers: [Resolver(kind: .receivedToken, element: "location", set: "provinces")],
                                       counting: counting, roster: "provinces")
            case .section:
                return MultiplierClass(id: "section", term: "section", resolvers: [Resolver(kind: .receivedToken, element: "location", set: "sections")],
                                       counting: counting, roster: "sections")
            case .dx:
                var resolvers: [Resolver] = []
                if !p.dxTokenAliases.isEmpty { resolvers.append(Resolver(kind: .receivedToken, element: "location", set: "dxAliases")) }
                let entitySides = sideIDs.filter { rule(p, $0).dxCountsEntities }
                let tokenSides = sideIDs.filter { !rule(p, $0).dxCountsEntities }
                if !tokenSides.isEmpty {
                    resolvers.append(Resolver(kind: .dxccEntity, element: "location", from: .receivedTokenOrCallsign, list: .arrl,
                                              countEntities: false, sides: tokenSides.count == sideIDs.count ? nil : tokenSides))
                }
                if !entitySides.isEmpty {
                    resolvers.append(Resolver(kind: .dxccEntity, element: "location", from: .receivedTokenOrCallsign, list: .arrl,
                                              countEntities: true, sides: entitySides.count == sideIDs.count ? nil : entitySides))
                }
                // A cap only means something for a side that counts the class.
                var caps: [String: Int] = [:]
                for s in sideIDs where counting[s] != nil {
                    if let cap = rule(p, s).dxMultCap { caps[s] = cap }
                }
                return MultiplierClass(id: "dx", term: "DX entity", termPlural: "DX entities", resolvers: resolvers,
                                       counting: counting, caps: caps.isEmpty ? nil : caps, layout: .workedOnly)
            case .member:
                return MultiplierClass(id: "member", term: p.memberExchange?.term ?? "member", termPlural: p.memberExchange?.memberPlural,
                                       resolvers: [Resolver(kind: .workedStation, element: "member")],
                                       counting: counting, layout: .workedOnly)
            }
        }
    }

    // MARK: Points

    /// Explicit tables, first match wins: designated counties (scaled),
    /// then home-state stations, then everyone — or the member sprint's three
    /// rates. `sets` gains `designatedCounties` when the party names some.
    private static func pointRules(for p: PartyDefinition, sets: inout [TokenSet]) -> [PointRule] {
        if let m = p.memberExchange {
            return [PointRule(when: [PointCondition(workedStationKind: ["member"])], points: m.memberPoints),
                    PointRule(when: [PointCondition(workedStationKind: ["qrp"])], points: m.qrpPoints),
                    PointRule(points: m.otherPoints)]
        }
        func rows(_ table: PartyDefinition.PointsTable, _ match: PointCondition.TokenMatch?) -> [PointRule] {
            ModeClass.allCases.map { mode in
                PointRule(when: [PointCondition(modeClass: [mode], receivedTokenIn: match)], points: table.points(for: mode))
            }
        }
        var out: [PointRule] = []
        if let f = p.countyPointFactor {
            sets.append(TokenSet(id: "designatedCounties", term: p.countyTerm, termPlural: p.countyTermPlural,
                                 tokens: f.counties.map { TokenSet.Token(abbr: $0) }))
            let base = p.homeStationPoints ?? p.points
            out += rows(base.scaled(by: f.factor), .init(element: "location", set: "designatedCounties"))
        }
        if let home = p.homeStationPoints {
            out += rows(home, .init(element: "location", set: "counties"))
        }
        out += rows(p.points, nil)
        return out
    }

    // MARK: Side rules and factors

    /// Two rules mirror `ScoreEngine` rather than the file: a granted
    /// multiplier of a class this side does not count is ignored
    /// (`for granted in rule.granted where wantedClasses.contains(...)`), and
    /// the activated-county multiplier needs the side to count counties at all
    /// (`rule.classes.contains(.county)`). Dropping both here keeps the lowered
    /// model scoring what the engine scores, and keeps every `classID` a class
    /// this contest actually declares — which `ContestDefinition.validate()`
    /// requires.
    private static func sideRules(for p: PartyDefinition, sideIDs: [String]) -> [String: SideRules] {
        var out: [String: SideRules] = [:]
        for s in sideIDs {
            let r = rule(p, s)
            let counted = Set(r.classes)
            let activated = counted.contains(.county) ? r.activatedCountyMultiplier.map {
                ActivatedRule(classID: "county", minCount: $0.minCount, countUnit: $0.countUnit, countScope: $0.countScope,
                              categories: $0.categories, notOtherwiseWorked: $0.notOtherwiseWorked)
            } : nil
            let rules = SideRules(maxScoredMultipliers: r.maxScoredMultipliers, multiplierFloor: r.multiplierFloor,
                                  granted: r.granted.filter { counted.contains($0.multClass) }
                                      .map { .init(classID: $0.multClass.rawValue, value: $0.value) },
                                  activated: activated)
            if rules != .none { out[s] = rules }
        }
        return out
    }

    private static func scoreFactors(for p: PartyDefinition) -> ScoreFactors? {
        guard p.scoreMultipliers != nil || !p.entryClasses.isEmpty else { return nil }
        return ScoreFactors(power: p.scoreMultipliers?.power, station: p.scoreMultipliers?.stationCategory,
                            entryClasses: p.entryClasses)
    }
}

import Foundation

/// A contest's complete rule set — the one type the engine, entry flow,
/// exporters and UI consume. Decoded from a v2 JSON file, or produced by
/// `PartyLowering.lower(_:)` from a `PartyDefinition`.
struct ContestDefinition: Codable, Identifiable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let family: ContestFamily
    let sponsor: String?
    let notes: String?
    let caveats: [PartyDefinition.Caveat]
    let schedule: [PartyDefinition.ScheduleWindow]?
    let bands: [Band]
    let modeClasses: [ModeClass]
    /// Concrete modes that count when a class is too coarse (a RTTY-only
    /// contest); nil = every raw mode of an allowed class.
    let allowedRawModes: [String]?
    let tokenSets: [TokenSet]
    let sides: [Side]
    let exchange: [ExchangeElement]
    let multipliers: [MultiplierClass]
    let points: [PointRule]
    let dupe: DupeRule
    /// Side id → the worked sides that count; nil = everyone.
    let pairing: [String: [String]]?
    let sideRules: [String: SideRules]
    let bonuses: [BonusRule]
    let scoreFactors: ScoreFactors?
    let operatingTime: OperatingTimeRule?
    let categories: Categories
    let cabrillo: CabrilloSpec
    let sources: ContestSources

    init(schemaVersion: Int = 2, id: String, name: String, family: ContestFamily, sponsor: String? = nil,
         notes: String? = nil, caveats: [PartyDefinition.Caveat] = [], schedule: [PartyDefinition.ScheduleWindow]? = nil,
         bands: [Band], modeClasses: [ModeClass], allowedRawModes: [String]? = nil, tokenSets: [TokenSet] = [],
         sides: [Side], exchange: [ExchangeElement], multipliers: [MultiplierClass], points: [PointRule],
         dupe: DupeRule, pairing: [String: [String]]? = nil, sideRules: [String: SideRules] = [:],
         bonuses: [BonusRule] = [], scoreFactors: ScoreFactors? = nil, operatingTime: OperatingTimeRule? = nil,
         categories: Categories = .all, cabrillo: CabrilloSpec, sources: ContestSources = .none) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.family = family
        self.sponsor = sponsor
        self.notes = notes
        self.caveats = caveats
        self.schedule = schedule
        self.bands = bands
        self.modeClasses = modeClasses
        self.allowedRawModes = allowedRawModes
        self.tokenSets = tokenSets
        self.sides = sides
        self.exchange = exchange
        self.multipliers = multipliers
        self.points = points
        self.dupe = dupe
        self.pairing = pairing
        self.sideRules = sideRules
        self.bonuses = bonuses
        self.scoreFactors = scoreFactors
        self.operatingTime = operatingTime
        self.categories = categories
        self.cabrillo = cabrillo
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, family, sponsor, notes, caveats, schedule, bands, modeClasses, allowedRawModes
        case tokenSets, sides, exchange, multipliers, points, dupe, pairing, sideRules, bonuses, scoreFactors
        case operatingTime, categories, cabrillo, sources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            family: try c.decode(ContestFamily.self, forKey: .family),
            sponsor: try c.decodeIfPresent(String.self, forKey: .sponsor),
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            caveats: try c.decodeIfPresent([PartyDefinition.Caveat].self, forKey: .caveats) ?? [],
            schedule: try c.decodeIfPresent([PartyDefinition.ScheduleWindow].self, forKey: .schedule),
            bands: try c.decode([Band].self, forKey: .bands),
            modeClasses: try c.decodeIfPresent([ModeClass].self, forKey: .modeClasses) ?? ModeClass.allCases,
            allowedRawModes: try c.decodeIfPresent([String].self, forKey: .allowedRawModes),
            tokenSets: try c.decodeIfPresent([TokenSet].self, forKey: .tokenSets) ?? [],
            sides: try c.decode([Side].self, forKey: .sides),
            exchange: try c.decode([ExchangeElement].self, forKey: .exchange),
            multipliers: try c.decodeIfPresent([MultiplierClass].self, forKey: .multipliers) ?? [],
            points: try c.decode([PointRule].self, forKey: .points),
            dupe: try c.decode(DupeRule.self, forKey: .dupe),
            pairing: try c.decodeIfPresent([String: [String]].self, forKey: .pairing),
            sideRules: try c.decodeIfPresent([String: SideRules].self, forKey: .sideRules) ?? [:],
            bonuses: try c.decodeIfPresent([BonusRule].self, forKey: .bonuses) ?? [],
            scoreFactors: try c.decodeIfPresent(ScoreFactors.self, forKey: .scoreFactors),
            operatingTime: try c.decodeIfPresent(OperatingTimeRule.self, forKey: .operatingTime),
            categories: try c.decodeIfPresent(Categories.self, forKey: .categories) ?? .all,
            cabrillo: try c.decode(CabrilloSpec.self, forKey: .cabrillo),
            sources: try c.decodeIfPresent(ContestSources.self, forKey: .sources) ?? .none
        )
    }

    /// Decode a v2 file and validate it — the only entry point the catalog uses.
    static func decode(_ data: Data) throws -> ContestDefinition {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contest = try decoder.decode(ContestDefinition.self, from: data)
        try contest.validate()
        return contest
    }

    // MARK: Lookup

    /// The contest's own set of that id, else a built-in, else the bundled sections.
    func tokenSet(id: String, bundle: Bundle = .main) -> TokenSet? {
        tokenSets.first { $0.id == id } ?? TokenSet.builtIn(id: id) ?? (id == "sections" ? TokenSet.sections(bundle: bundle) : nil)
    }

    func side(id: String) -> Side? { sides.first { $0.id == id } }

    func rules(for side: String) -> SideRules { sideRules[side] ?? .none }

    /// The sides an entrant on `side` may work for credit: its `pairing` row, else every side.
    func workableSides(for side: String) -> [String] { pairing?[side] ?? sides.map(\.id) }

    /// The elements an entrant on `side` receives, in spec order: those sent
    /// by any side it may work, excluding the call echo (which is the call field).
    func receivedElements(for side: String) -> [ExchangeElement] {
        let workable = Set(workableSides(for: side))
        return exchange.filter { $0.kind != .callEcho && !$0.sentBy.keys.filter(workable.contains).isEmpty }
    }

    /// The elements an entrant on `side` sends, in spec order.
    func sentElements(for side: String) -> [ExchangeElement] {
        exchange.filter { $0.sentBy[side] != nil }
    }

    // MARK: Validation

    func validate() throws {
        let sideIDs = Set(sides.map(\.id))
        guard !sides.isEmpty else { throw ContestValidationError.noSides }
        guard !exchange.isEmpty else { throw ContestValidationError.noExchange }
        guard let last = points.last, last.when.isEmpty else { throw ContestValidationError.pointsWithoutDefault }
        guard !cabrillo.contest.isEmpty else { throw ContestValidationError.noCabrilloContest }
        for set in tokenSets {
            do { try set.validate() } catch { throw ContestValidationError.badTokenSet(set.id, error.localizedDescription) }
        }
        for e in exchange {
            guard !e.sentBy.isEmpty else { throw ContestValidationError.elementSentByNobody(e.id) }
            for side in e.sentBy.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            for set in e.sentBy.values.flatMap({ $0.sets ?? [] }) where !isKnownSet(set) {
                throw ContestValidationError.unknownTokenSet(set)
            }
            if let d = e.derived {
                guard d.kind == "categoryTable", !d.table.isEmpty else { throw ContestValidationError.badDerivation(e.id) }
            }
        }
        for m in multipliers {
            for side in m.counting.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            for r in m.resolvers {
                if let set = r.set, !isKnownSet(set) { throw ContestValidationError.unknownTokenSet(set) }
                if let element = r.element, !exchange.contains(where: { $0.id == element }) {
                    throw ContestValidationError.unknownElement(element)
                }
                for side in r.sides ?? [] where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
                // Each kind's required fields — a flat resolver has nothing else to enforce them.
                let bad = ContestValidationError.badResolver(m.id, r.kind.rawValue)
                switch r.kind {
                case .receivedToken: guard r.element != nil, r.set != nil else { throw bad }
                case .grid, .workedStation: guard r.element != nil else { throw bad }
                case .dxccEntity:
                    guard let from = r.from else { throw bad }
                    if from != .callsign { guard r.element != nil else { throw bad } }
                case .cqZone, .ituZone: guard r.from != nil else { throw bad }
                case .wpxPrefix: break
                }
            }
            if let roster = m.roster, !isKnownSet(roster) { throw ContestValidationError.unknownTokenSet(roster) }
        }
        for (side, worked) in pairing ?? [:] {
            guard sideIDs.contains(side) else { throw ContestValidationError.unknownSide(side) }
            for w in worked where !sideIDs.contains(w) { throw ContestValidationError.unknownSide(w) }
        }
        for side in sideRules.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
        for s in sides {
            for p in [s.predicate, s.workedPredicate] {
                switch p.kind {
                case .always: break
                case .tokenIn:
                    guard let set = p.set, isKnownSet(set), let element = p.element,
                          exchange.contains(where: { $0.id == element }) else { throw ContestValidationError.badPredicate(s.id) }
                case .dxccIn: guard !(p.codes ?? []).isEmpty else { throw ContestValidationError.badPredicate(s.id) }
                case .continentIn: guard !(p.continents ?? []).isEmpty else { throw ContestValidationError.badPredicate(s.id) }
                }
            }
        }
    }

    /// The dynamic sets the validator resolves without a `TokenSet` value.
    static let dynamicSetIDs: Set<String> = ["dxccPrefix"]

    private func isKnownSet(_ id: String) -> Bool {
        tokenSets.contains { $0.id == id } || TokenSet.builtIn(id: id) != nil || id == "sections" || Self.dynamicSetIDs.contains(id)
    }
}

enum ContestValidationError: Error, Equatable, LocalizedError {
    case noSides, noExchange, pointsWithoutDefault, noCabrilloContest
    case unknownSide(String), unknownTokenSet(String), unknownElement(String), badPredicate(String)
    case badTokenSet(String, String), elementSentByNobody(String), badDerivation(String), badResolver(String, String)

    var errorDescription: String? {
        switch self {
        case .noSides: "Contest declares no sides."
        case .noExchange: "Contest declares no exchange elements."
        case .pointsWithoutDefault: "The last points rule must have no conditions."
        case .noCabrilloContest: "cabrillo.contest is empty."
        case .unknownSide(let s): "Unknown side '\(s)'."
        case .unknownTokenSet(let s): "Unknown token set '\(s)'."
        case .unknownElement(let e): "Unknown exchange element '\(e)'."
        case .badPredicate(let s): "Side '\(s)' has a predicate missing its fields."
        case .badTokenSet(let id, let why): "Token set '\(id)': \(why)"
        case .elementSentByNobody(let e): "Exchange element '\(e)' is sent by no side."
        case .badDerivation(let e): "Exchange element '\(e)' has a derivation that is not a non-empty categoryTable."
        case .badResolver(let cls, let kind): "Multiplier class '\(cls)': a \(kind) resolver is missing a required field."
        }
    }
}

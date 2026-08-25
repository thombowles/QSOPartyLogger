import Foundation
import os

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
    /// This is a POTA program log: the their-park field is always visible and
    /// in the Space cycle, and the band map's POTA feed defaults on. One
    /// declaration rather than a flag per symptom (spec 2026-08-25 decision
    /// 12); no party sets it.
    let potaProgram: Bool
    /// The word after "CQ" in default messages ("POTA" → "CQ POTA {MYCALL}");
    /// nil is the contest default, "TEST".
    let cqLabel: String?
    /// Whether a callbook lookup's record is stamped into the QSO at logging
    /// (phase 2 of the spec reads this; the field ships now so pota.json is
    /// complete). Default false.
    let enrichFromCallbook: Bool

    init(schemaVersion: Int = 2, id: String, name: String, family: ContestFamily, sponsor: String? = nil,
         notes: String? = nil, caveats: [PartyDefinition.Caveat] = [], schedule: [PartyDefinition.ScheduleWindow]? = nil,
         bands: [Band], modeClasses: [ModeClass], allowedRawModes: [String]? = nil, tokenSets: [TokenSet] = [],
         sides: [Side], exchange: [ExchangeElement], multipliers: [MultiplierClass], points: [PointRule],
         dupe: DupeRule, pairing: [String: [String]]? = nil, sideRules: [String: SideRules] = [:],
         bonuses: [BonusRule] = [], scoreFactors: ScoreFactors? = nil, operatingTime: OperatingTimeRule? = nil,
         categories: Categories = .all, cabrillo: CabrilloSpec, sources: ContestSources = .none,
         potaProgram: Bool = false, cqLabel: String? = nil, enrichFromCallbook: Bool = false) {
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
        self.potaProgram = potaProgram
        self.cqLabel = cqLabel
        self.enrichFromCallbook = enrichFromCallbook
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, family, sponsor, notes, caveats, schedule, bands, modeClasses, allowedRawModes
        case tokenSets, sides, exchange, multipliers, points, dupe, pairing, sideRules, bonuses, scoreFactors
        case operatingTime, categories, cabrillo, sources
        case potaProgram, cqLabel, enrichFromCallbook
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
            sources: try c.decodeIfPresent(ContestSources.self, forKey: .sources) ?? .none,
            potaProgram: try c.decodeIfPresent(Bool.self, forKey: .potaProgram) ?? false,
            cqLabel: try c.decodeIfPresent(String.self, forKey: .cqLabel),
            enrichFromCallbook: try c.decodeIfPresent(Bool.self, forKey: .enrichFromCallbook) ?? false
        )
    }

    /// Decode a v2 file and validate it — the only entry point the catalog uses.
    static func decode(_ data: Data, bundle: Bundle = .main) throws -> ContestDefinition {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contest = try decoder.decode(ContestDefinition.self, from: data)
        try contest.validate(bundle: bundle)
        return contest
    }

    /// The inverse of `decode(_:bundle:)`, mirroring `ContestLog.encoded()`:
    /// plain `JSONEncoder()` would not round-trip the schedule's ISO-8601 dates.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    // MARK: Lookup

    /// The contest's own set of that id, else a built-in, else the bundled sections.
    /// `.main`'s sections are memoized (`mainSections`); any other bundle —
    /// tests, a future plugin bundle — re-reads and re-decodes the file.
    func tokenSet(id: String, bundle: Bundle = .main) -> TokenSet? {
        tokenSets.first { $0.id == id } ?? TokenSet.builtIn(id: id)
            ?? (id == "sections" ? (bundle === Bundle.main ? Self.mainSections : TokenSet.sections(bundle: bundle)) : nil)
    }

    /// `TokenSet.sections(bundle:)` re-parses `arrl_sections.json` on every
    /// call; the `.main` case — every lookup outside tests — is worth caching.
    private static let mainSections = TokenSet.sections(bundle: .main)

    func side(id: String) -> Side? { sides.first { $0.id == id } }

    func rules(for side: String) -> SideRules { sideRules[side] ?? .none }

    /// The sides an entrant on `side` may work for credit: its `pairing` row,
    /// else every side — in side declaration order (the order token ownership
    /// and the entry hint use), however the pairing row was written.
    func workableSides(for side: String) -> [String] {
        pairing?[side].map { row in sides.map(\.id).filter(row.contains) } ?? sides.map(\.id)
    }

    /// The side a log's `sideID` names; for an id this contest does not
    /// declare — a document written before it declared sides, or a lowered
    /// party whose single side is `all` while the log says `outside` — the
    /// contest's only side, else its last-listed side (the catch-all: sides
    /// are evaluated first-match, so the last is the one that takes everyone
    /// else). The fallback is noted in the unified log once per (contest,
    /// side) pair, so a remapped legacy log is visible without a line per
    /// score pass.
    func resolvedSideID(_ id: String) -> String {
        if sides.contains(where: { $0.id == id }) { return id }
        let resolved = sides.last?.id ?? id
        let key = "\(self.id)\u{1F}\(id)"
        if Self.reportedSideFallbacks.withLock({ $0.insert(key).inserted }) {
            Self.log.notice("log names side '\(id, privacy: .public)' which contest '\(self.id, privacy: .public)' does not declare; scoring as '\(resolved, privacy: .public)'")
        }
        return resolved
    }

    private static let log = Logger(subsystem: "org.b5n.QSOPartyLogger", category: "contests")
    private static let reportedSideFallbacks = OSAllocatedUnfairLock<Set<String>>(initialState: [])

    /// The token set the `county` class lists — what the county-keyed bonuses
    /// (`mobileCountyCount`, `activatedCountyCount`, `sweepTiers`,
    /// `designatedCountySweep`) and the ADIF `cnty` fields read. Nil for a
    /// contest with no `county` class. A v2 contest with county-keyed bonuses
    /// but no county multiplier must still declare a `county` class (with
    /// `counting: [:]`) to carry the roster.
    func countyRoster(bundle: Bundle = .main) -> TokenSet? {
        guard let id = multipliers.first(where: { $0.id == MultClass.county.rawValue })?.roster else { return nil }
        return tokenSet(id: id, bundle: bundle)
    }

    /// The elements an entrant on `side` receives, in spec order: those sent
    /// by any side it may work. The call echo is the call field itself and is
    /// excluded unless `includingCallEcho` — the Cabrillo QSO line, which
    /// writes the echoed call inside the received columns, asks for it.
    func receivedElements(for side: String, includingCallEcho: Bool = false) -> [ExchangeElement] {
        let workable = Set(workableSides(for: side))
        return exchange.filter { e in
            (includingCallEcho || e.kind != .callEcho) && e.sentBy.keys.contains(where: workable.contains)
        }
    }

    /// The elements an entrant on `side` sends, in spec order.
    func sentElements(for side: String) -> [ExchangeElement] {
        exchange.filter { $0.sentBy[side] != nil }
    }

    // MARK: Validation

    func validate(bundle: Bundle = .main) throws {
        let sideIDs = Set(sides.map(\.id))
        guard !sides.isEmpty else { throw ContestValidationError.noSides }
        guard !exchange.isEmpty else { throw ContestValidationError.noExchange }
        guard let last = points.last, last.when.isEmpty else { throw ContestValidationError.pointsWithoutDefault }
        guard !cabrillo.contest.isEmpty else { throw ContestValidationError.noCabrilloContest }
        guard schemaVersion == 2 else { throw ContestValidationError.unsupportedSchemaVersion(schemaVersion) }

        var seenSides = Set<String>()
        for s in sides {
            guard seenSides.insert(s.id).inserted else { throw ContestValidationError.duplicateID("side", s.id) }
        }
        var seenElements = Set<String>()
        for e in exchange {
            guard seenElements.insert(e.id).inserted else { throw ContestValidationError.duplicateID("exchange element", e.id) }
        }
        var seenMultipliers = Set<String>()
        for m in multipliers {
            guard seenMultipliers.insert(m.id).inserted else { throw ContestValidationError.duplicateID("multiplier class", m.id) }
        }
        var seenTokenSets = Set<String>()
        for t in tokenSets {
            guard seenTokenSets.insert(t.id).inserted else { throw ContestValidationError.duplicateID("token set", t.id) }
        }

        for set in tokenSets {
            do { try set.validate() } catch { throw ContestValidationError.badTokenSet(set.id, error.localizedDescription) }
        }
        for e in exchange {
            guard !e.sentBy.isEmpty else { throw ContestValidationError.elementSentByNobody(e.id) }
            for side in e.sentBy.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            // A county line's own set list is checked too: an id nothing
            // carries there would silently stop the county line working.
            for set in e.sentBy.values.flatMap({ ($0.sets ?? []) + ($0.multi?.sets ?? []) }) where !isKnownSet(set, bundle: bundle) {
                throw ContestValidationError.unknownTokenSet(set)
            }
            if let d = e.derived {
                guard d.kind == "categoryTable", !d.table.isEmpty else { throw ContestValidationError.badDerivation(e.id) }
            }
            // Fields only that kind reads — a flat element has nothing else to enforce them.
            switch e.kind {
            case .token:
                guard e.sentBy.values.allSatisfy({ !($0.sets ?? []).isEmpty }) else {
                    throw ContestValidationError.badElement(e.id, "a token element's sender must name its sets")
                }
            case .precedence, .classToken:
                guard !(e.letters ?? []).isEmpty else { throw ContestValidationError.badElement(e.id, "needs letters") }
            case .memberOrPower:
                guard e.member != nil else { throw ContestValidationError.badElement(e.id, "needs a member spec") }
            default: break
            }
        }
        for m in multipliers {
            for side in m.counting.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            for side in (m.caps ?? [:]).keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            for r in m.resolvers {
                if let set = r.set, !isKnownSet(set, bundle: bundle) { throw ContestValidationError.unknownTokenSet(set) }
                if let element = r.element, !exchange.contains(where: { $0.id == element }) {
                    throw ContestValidationError.unknownElement(element)
                }
                for side in r.sides ?? [] where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
                // Each kind's required fields — a flat resolver has nothing else to enforce them.
                let bad = ContestValidationError.badResolver(m.id, r.kind.rawValue)
                if let mapTo = r.mapTo, mapTo != "group" { throw bad }
                switch r.kind {
                case .receivedToken: guard r.element != nil, r.set != nil else { throw bad }
                case .grid, .workedStation: guard r.element != nil else { throw bad }
                case .dxccEntity:
                    guard let from = r.from else { throw bad }
                    if from != .callsign { guard r.element != nil else { throw bad } }
                case .cqZone, .ituZone: guard r.from != nil, r.element != nil else { throw bad }
                case .wpxPrefix: break
                }
                if let overrides = r.callsignOverrides {
                    guard r.kind == .dxccEntity, r.from == .receivedTokenOrCallsign, let element = r.element,
                          let el = exchange.first(where: { $0.id == element }) else { throw bad }
                    let accepted = Set(el.sentBy.values.flatMap { $0.sets ?? [] })
                    for set in overrides where !accepted.contains(set) { throw ContestValidationError.unknownTokenSet(set) }
                }
            }
            if let roster = m.roster {
                guard isKnownSet(roster, bundle: bundle) else { throw ContestValidationError.unknownTokenSet(roster) }
                guard !Self.dynamicSetIDs.contains(roster) else { throw ContestValidationError.badRoster(roster) }
            }
        }
        for (i, rule) in points.enumerated() {
            for cond in rule.when {
                for side in (cond.side ?? []) + (cond.workedSide ?? []) where !sideIDs.contains(side) {
                    throw ContestValidationError.badPointRule(i, "unknown side")
                }
                if let rt = cond.receivedTokenIn {
                    guard exchange.contains(where: { $0.id == rt.element }), isKnownSet(rt.set, bundle: bundle) else {
                        throw ContestValidationError.badPointRule(i, "unknown element or set")
                    }
                }
                if let kinds = cond.workedStationKind, !Set(kinds).isSubset(of: ["member", "qrp", "other"]) {
                    throw ContestValidationError.badPointRule(i, "unknown station kind")
                }
            }
        }
        for (side, worked) in pairing ?? [:] {
            guard sideIDs.contains(side) else { throw ContestValidationError.unknownSide(side) }
            guard !worked.isEmpty else { throw ContestValidationError.emptyPairing(side) }
            for w in worked where !sideIDs.contains(w) { throw ContestValidationError.unknownSide(w) }
        }
        let multiplierIDs = Set(multipliers.map(\.id))
        for (side, rules) in sideRules {
            guard sideIDs.contains(side) else { throw ContestValidationError.unknownSide(side) }
            for g in rules.granted where !multiplierIDs.contains(g.classID) {
                throw ContestValidationError.unknownMultiplierClass(g.classID)
            }
            if let activated = rules.activated, !multiplierIDs.contains(activated.classID) {
                throw ContestValidationError.unknownMultiplierClass(activated.classID)
            }
        }
        if let appliesTo = operatingTime?.appliesTo {
            let knownAxes: Set<String> = [
                "operator", "assisted", "power", "band", "mode", "transmitter", "station", "overlay", "time"
            ]
            for key in appliesTo.keys where !knownAxes.contains(key) { throw ContestValidationError.badOperatingTimeAxis(key) }
        }
        // `OperatingTime.compute` reads both as ≥ 1: a zero minimum would
        // credit every empty minute as off time.
        if let rule = operatingTime, rule.maxMinutes < 1 || rule.minOffMinutes < 1 {
            throw ContestValidationError.badOperatingTime
        }
        for s in sides {
            for p in [s.predicate, s.workedPredicate] {
                switch p.kind {
                case .always: break
                case .tokenIn:
                    guard let set = p.set, isKnownSet(set, bundle: bundle), let element = p.element,
                          exchange.contains(where: { $0.id == element }) else { throw ContestValidationError.badPredicate(s.id) }
                case .dxccIn: guard !(p.codes ?? []).isEmpty else { throw ContestValidationError.badPredicate(s.id) }
                case .continentIn: guard !(p.continents ?? []).isEmpty else { throw ContestValidationError.badPredicate(s.id) }
                }
            }
        }
        // County-keyed bonuses read the county class's roster.
        let countyKeyed = bonuses.contains { bonus in
            switch bonus {
            case .mobileCountyCount, .activatedCountyCount, .sweepTiers, .designatedCountySweep: true
            case .workStation, .callAreaSum: false
            }
        }
        if countyKeyed {
            guard let roster = countyRoster(bundle: bundle) else { throw ContestValidationError.bonusNeedsCountyClass }
            for case .designatedCountySweep(let counties, _, _) in bonuses {
                for token in counties where !roster.abbrs.contains(token.uppercased()) {
                    throw ContestValidationError.unknownBonusToken(token)
                }
            }
        }
        // Self-declared ids are keys the log stores; each must be unique.
        if let f = scoreFactors {
            for (what, ids) in [("entry class", f.entryClasses.map(\.id)), ("objective", f.objectives.map(\.id)),
                                ("declared bonus", f.declaredBonuses.map(\.id))] {
                var seen = Set<String>()
                for id in ids where !seen.insert(id).inserted { throw ContestValidationError.duplicateID(what, id) }
            }
        }
        // An activated multiplier is earned by operating from a token of the
        // class's roster; a class with no roster has nothing to operate from.
        for (_, rules) in sideRules {
            if let a = rules.activated, let cls = multipliers.first(where: { $0.id == a.classID }), cls.roster == nil {
                throw ContestValidationError.activatedNeedsRoster(a.classID)
            }
        }
    }

    /// The dynamic sets the validator resolves without a `TokenSet` value.
    static let dynamicSetIDs: Set<String> = ["dxccPrefix"]

    /// Consults `bundle` so a contest referencing `sections` fails validation
    /// under a bundle whose `arrl_sections.json` is missing or corrupt,
    /// exactly as `TokenSet.sections(bundle:)` documents.
    private func isKnownSet(_ id: String, bundle: Bundle) -> Bool {
        tokenSet(id: id, bundle: bundle) != nil || Self.dynamicSetIDs.contains(id)
    }
}

enum ContestValidationError: Error, Equatable, LocalizedError {
    case noSides, noExchange, pointsWithoutDefault, noCabrilloContest
    case unknownSide(String), unknownTokenSet(String), unknownElement(String), badPredicate(String)
    case badTokenSet(String, String), elementSentByNobody(String), badDerivation(String), badResolver(String, String)
    case unsupportedSchemaVersion(Int), duplicateID(String, String), badElement(String, String)
    case badPointRule(Int, String), unknownMultiplierClass(String), emptyPairing(String)
    case badRoster(String), badOperatingTimeAxis(String), badOperatingTime
    case bonusNeedsCountyClass, unknownBonusToken(String), activatedNeedsRoster(String)

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
        case .unsupportedSchemaVersion(let v): "Schema version \(v) is not supported; this build reads schema 2."
        case .duplicateID(let what, let id): "Duplicate \(what) id '\(id)'."
        case .badElement(let id, let why): "Exchange element '\(id)': \(why)."
        case .badPointRule(let i, let why): "Points rule \(i): \(why)."
        case .unknownMultiplierClass(let id): "Unknown multiplier class '\(id)'."
        case .emptyPairing(let side): "Side '\(side)': pairing row is empty."
        case .badRoster(let id): "Roster '\(id)' is a dynamic set and cannot be listed."
        case .badOperatingTimeAxis(let key): "Unknown operating-time axis '\(key)'."
        case .badOperatingTime: "An operating-time rule needs maxMinutes ≥ 1 and minOffMinutes ≥ 1."
        case .bonusNeedsCountyClass: "A county-keyed bonus needs a 'county' multiplier class with a roster."
        case .unknownBonusToken(let t): "Bonus names '\(t)', which is not in the county roster."
        case .activatedNeedsRoster(let id): "Activated multiplier class '\(id)' lists no roster."
        }
    }
}

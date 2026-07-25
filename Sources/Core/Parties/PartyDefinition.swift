import Foundation

/// A QSO party's complete rule set, loaded from JSON (bundled or user-installed).
/// Adding a party requires no code — drop a JSON file in
/// `~/Library/Application Support/QSOPartyLogger/Parties/`.
///
/// All fields beyond the core set are optional with defaults chosen so that
/// schema-v1 files written for earlier builds keep decoding identically.
struct PartyDefinition: Codable, Identifiable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let cabrilloContest: String
    /// Two-letter state whose counties define the party (e.g. "KS").
    let homeState: String
    let countyAbbrLength: Int
    let validBands: [Band]
    let points: PointsTable
    let dupeScope: DupeScope
    let multipliers: MultRules
    let bonuses: [BonusRule]
    let oneByOne: OneByOneConfig?
    /// Operating windows for the current year (UTC), from the official calendar.
    let schedule: [ScheduleWindow]?
    let counties: [County]
    let notes: String?

    // MARK: Optional rule shapes (defaults preserve original behavior)

    /// How DX stations identify themselves in the exchange.
    /// `.token`: the literal word "DX". `.prefix`: their DXCC country prefix
    /// (each unique prefix is its own multiplier where the dx class counts).
    var dxStyle: DXStyle { dxStyleRaw ?? .token }
    private let dxStyleRaw: DXStyle?

    /// Mode classes that are legal contest modes (ALQP/OhQP/COQP/WA/MDC have
    /// no digital). Rows in other modes are invalid — no points, no mults.
    var allowedModeClasses: [ModeClass] { allowedModeClassesRaw ?? ModeClass.allCases }
    private let allowedModeClassesRaw: [ModeClass]?

    /// Max counties one station may claim simultaneously (county lines).
    /// ALQP forbids line sitting (1); TnQP/WA/COQP allow 2; IAQP junctions 4.
    var maxSimultaneousCounties: Int { maxSimultaneousCountiesRaw ?? 4 }
    private let maxSimultaneousCountiesRaw: Int?

    /// State tokens accepted but credited as another state (e.g. DC→MD).
    var stateAliases: [String: String] { stateAliasesRaw ?? [:] }
    private let stateAliasesRaw: [String: String]?

    /// State tokens that are not valid in this party beyond the home state
    /// (MDC: DC arrives as the WDC county entity, so both MD and DC are out).
    var excludedStateTokens: [String] { excludedStateTokensRaw ?? [homeState] }
    private let excludedStateTokensRaw: [String]?

    /// Province token list override (OhQP counts only 11). Default: the 13.
    var provinces: Set<String> {
        provincesRaw.map(Set.init) ?? MultClass.canadianProvinces
    }
    private let provincesRaw: [String]?

    /// Whether the exchange carries RST (MDC exchanges call + location only).
    var exchangeIncludesRST: Bool { exchangeIncludesRSTRaw ?? true }
    private let exchangeIncludesRSTRaw: Bool?

    /// Whether an out-of-state entrant earns credit *only* for contacts with
    /// home-state stations. MDC rule 10b: "Stations not located in the state of
    /// Maryland, or the District of Columbia may only receive credit for
    /// contacts with stations located in Maryland or the District of Columbia."
    /// Rows carrying any other location are not contest QSOs — no points, no
    /// multiplier, excluded from dupe accounting.
    ///
    /// Most state parties word the same restriction somewhere in their rules;
    /// the default is `false` so that definitions written before this field
    /// existed keep scoring identically (constitution Article 4). Turn it on
    /// per party only with the rule text to back it.
    var outStateWorksHomeStationsOnly: Bool { outStateWorksHomeStationsOnlyRaw ?? false }
    private let outStateWorksHomeStationsOnlyRaw: Bool?

    /// Final-score multipliers by entry category (NJQP power; MDC power ×
    /// station category). Keys are the Cabrillo raw values ("QRP", "ROVER"…).
    let scoreMultipliers: ScoreMultipliers?

    /// Points for a contact with a **home-state** station, where the party pays
    /// by *who was worked* rather than by mode. MEQP: "Contacts with stations in
    /// Maine are worth 2 points. Contacts with stations outside Maine are worth
    /// 1 point." — CW and phone pay alike, and the received location decides.
    ///
    /// `nil` (every other bundled party) means `points` applies to every row,
    /// which is how definitions written before this field existed keep scoring
    /// identically (constitution Article 4).
    let homeStationPoints: PointsTable?

    /// The points table governing a contact whose received location is
    /// `theirLoc`. Home-state stations are recognised the only way the exchange
    /// allows — they send a county — so `countyAbbrs` is the party's county set.
    func pointsTable(forTheirLoc theirLoc: String, countyAbbrs: Set<String>) -> PointsTable {
        guard let homeStationPoints,
              countyAbbrs.contains(theirLoc.uppercased())
        else { return points }
        return homeStationPoints
    }

    enum DXStyle: String, Codable, Sendable {
        case token
        case prefix
    }

    struct ScoreMultipliers: Codable, Equatable, Sendable {
        let power: [String: Int]?
        let stationCategory: [String: Int]?

        func factor(power p: StationProfile.CategoryPower, station s: StationProfile.CategoryStation) -> Int {
            (power?[p.rawValue] ?? 1) * (stationCategory?[s.rawValue] ?? 1)
        }
    }

    struct ScheduleWindow: Codable, Equatable, Sendable {
        let start: Date
        let end: Date
    }

    struct PointsTable: Codable, Equatable, Sendable {
        let phone: Int
        let cw: Int
        let digital: Int

        func points(for modeClass: ModeClass) -> Int {
            switch modeClass {
            case .phone: phone
            case .cw: cw
            case .digital: digital
            }
        }
    }

    enum DupeScope: String, Codable, Sendable {
        /// Workable once per band × mode-class (all bundled parties).
        case bandMode
    }

    struct MultRules: Codable, Equatable, Sendable {
        let inState: MultRule
        let outState: MultRule
    }

    struct MultRule: Codable, Equatable, Sendable {
        let classes: [MultClass]
        /// KSQP/ALQP/COQP/IAQP: the first home-state county logged also
        /// satisfies the home state's own state multiplier.
        let homeStateCountsViaCounty: Bool
        let countScope: CountScope
        /// Cap on distinct dx multipliers (WA/NHQP in-state: 10). nil = no cap.
        var dxMultCap: Int? { dxMultCapRaw }
        private let dxMultCapRaw: Int?

        init(
            classes: [MultClass],
            homeStateCountsViaCounty: Bool,
            countScope: CountScope,
            dxMultCap: Int? = nil
        ) {
            self.classes = classes
            self.homeStateCountsViaCounty = homeStateCountsViaCounty
            self.countScope = countScope
            self.dxMultCapRaw = dxMultCap
        }

        private enum CodingKeys: String, CodingKey {
            case classes, homeStateCountsViaCounty, countScope
            case dxMultCapRaw = "dxMultCap"
        }
    }

    enum CountScope: String, Codable, Sendable {
        /// Each multiplier counts once for the whole log (KSQP, TQP, WA…).
        case once
        /// …once per mode class (ALQP, OhQP, COQP).
        case perMode
        /// …once per band (TnQP; NHQP/HQP out-of-state).
        case perBand
        /// …once per band *and* per mode (MEQP: "Each multiplier may be counted
        /// once on each mode on each of the six contest bands").
        case perBandMode
    }

    struct OneByOneConfig: Codable, Equatable, Sendable {
        let words: [String]
        let wildcard: String?
    }

    // MARK: Verification status (constitution Article 3)

    /// Whether this party shipped with rules that could not be fully confirmed
    /// from an official source. Matched on the literal `verified: partial`
    /// marker rather than a loose word search, so provenance prose that merely
    /// mentions "partial" cannot raise a false warning.
    var isPartiallyVerified: Bool {
        notes?.range(of: "verified: partial", options: .caseInsensitive) != nil
    }

    /// The `OPEN QUESTION…` tail of `notes` — the part an operator actually
    /// needs to act on before submitting a log, separated from the provenance
    /// paragraph that precedes it. `nil` when the notes carry no such section.
    var openQuestions: String? {
        guard let notes,
              let marker = notes.range(of: "OPEN QUESTION", options: .caseInsensitive)
        else { return nil }
        let tail = notes[marker.lowerBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return tail.isEmpty ? nil : tail
    }

    // MARK: County abbreviation shape

    /// Distinct abbreviation lengths actually present in the county data,
    /// ascending. Most parties use one length; the Salmon Run mixes 3 and 4
    /// (`CLAL`/`COL`, `KITS`/`KLI`), so a single `countyAbbrLength` cannot
    /// describe it. Derived from the data rather than hand-maintained.
    var countyAbbrLengths: [Int] {
        Set(counties.map(\.abbr.count)).sorted()
    }

    /// Entry-field hint: `"3"` for a uniform party, `"3/4"` where lengths mix.
    var countyAbbrLengthHint: String {
        let lengths = countyAbbrLengths
        return lengths.isEmpty
            ? String(countyAbbrLength)
            : lengths.map(String.init).joined(separator: "/")
    }

    // MARK: Lookup

    var countiesByAbbr: [String: County] {
        Dictionary(uniqueKeysWithValues: counties.map { ($0.abbr, $0) })
    }

    func county(for abbr: String) -> County? {
        countiesByAbbr[abbr.uppercased()]
    }

    /// Valid non-county location tokens: states (less exclusions, plus alias
    /// keys like DC), provinces, and the DX token when the party uses it.
    var validOutStateTokens: Set<String> {
        var tokens = MultClass.acceptedStateTokens
            .subtracting(excludedStateTokens)
            .union(provinces)
        tokens.formUnion(stateAliases.keys)
        if dxStyle == .token {
            tokens.insert(MultClass.dxToken)
        }
        return tokens
    }

    /// Could this token be a DX prefix under `.prefix` style? 1–5 chars,
    /// letters/digits with at least one letter, and not a county or any
    /// state/province/DX token — including excluded ones like the home state,
    /// which must never sneak back in as a "DX prefix".
    /// Known limitation: DXCC prefixes that collide with US state or Canadian
    /// province codes (OH Finland, ON Belgium, PA Netherlands…) are read as
    /// the state/province — same resolution sponsors' log checkers apply.
    func isPlausibleDXPrefix(_ token: String) -> Bool {
        guard dxStyle == .prefix else { return false }
        guard (1...5).contains(token.count) else { return false }
        guard token.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        guard token.contains(where: \.isLetter) else { return false }
        guard countiesByAbbr[token] == nil else { return false }
        guard !MultClass.acceptedStateTokens.contains(token) else { return false }
        guard !MultClass.canadianProvinces.contains(token) else { return false }
        guard !provinces.contains(token) else { return false }
        guard token != MultClass.dxToken else { return false }
        return true
    }

    /// Basic structural validation for user-supplied files.
    func validate() throws {
        var seen = Set<String>()
        for c in counties {
            guard c.abbr == c.abbr.uppercased(), !c.abbr.isEmpty else {
                throw PartyValidationError.badAbbreviation(c.abbr)
            }
            guard seen.insert(c.abbr).inserted else {
                throw PartyValidationError.duplicateAbbreviation(c.abbr)
            }
        }
        guard !counties.isEmpty else { throw PartyValidationError.noCounties }
        guard homeState.count == 2 else { throw PartyValidationError.badHomeState(homeState) }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, cabrilloContest, homeState, countyAbbrLength
        case validBands, points, dupeScope, multipliers, bonuses, oneByOne
        case schedule, counties, notes, scoreMultipliers, homeStationPoints
        case dxStyleRaw = "dxStyle"
        case allowedModeClassesRaw = "allowedModes"
        case maxSimultaneousCountiesRaw = "maxSimultaneousCounties"
        case stateAliasesRaw = "stateAliases"
        case excludedStateTokensRaw = "excludedStateTokens"
        case provincesRaw = "provinces"
        case exchangeIncludesRSTRaw = "exchangeIncludesRST"
        case outStateWorksHomeStationsOnlyRaw = "outStateWorksHomeStationsOnly"
    }
}

enum PartyValidationError: Error, Equatable, LocalizedError {
    case badAbbreviation(String)
    case duplicateAbbreviation(String)
    case noCounties
    case badHomeState(String)

    var errorDescription: String? {
        switch self {
        case .badAbbreviation(let a): "County abbreviation '\(a)' must be non-empty uppercase."
        case .duplicateAbbreviation(let a): "County abbreviation '\(a)' appears more than once."
        case .noCounties: "Party has no counties."
        case .badHomeState(let s): "homeState '\(s)' must be a 2-letter state code."
        }
    }
}

/// Bonus scoring strategies. JSON uses a `type` discriminator so new strategies
/// can be added as cases without breaking existing files.
enum BonusRule: Codable, Equatable, Sendable {
    /// Flat bonus for working a specific station. Scope: how often it pays.
    case workStation(call: String, points: Int, scope: WorkStationScope)
    /// TQP-style: +points for each `per` distinct counties a mobile is worked in.
    case mobileCountyCount(per: Int, points: Int)
    /// TnQP/COQP-style: +points per county I activate (as an in-state
    /// mobile/rover/portable) with at least `minQSOs` valid QSOs made from it.
    case activatedCountyCount(minQSOs: Int, points: Int)
    /// MDC-style tiered sweep of county-class entities: highest reached tier
    /// pays (non-stacking). Tiers must be sorted ascending by count.
    case sweepTiers([SweepTier])

    enum WorkStationScope: String, Codable, Sendable {
        case once       // KSQP KS0KS, MDC W3VPR
        case perMode    // WA W7DX: 500 per mode
        case perQSO     // TnQP K4TCG: 100 per valid QSO
    }

    struct SweepTier: Codable, Equatable, Sendable {
        let count: Int
        let points: Int
    }

    private enum CodingKeys: String, CodingKey {
        case type, call, points, per, scope, minQSOs, tiers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "workStation":
            self = .workStation(
                call: try c.decode(String.self, forKey: .call),
                points: try c.decode(Int.self, forKey: .points),
                scope: try c.decodeIfPresent(WorkStationScope.self, forKey: .scope) ?? .once
            )
        case "mobileCountyCount":
            self = .mobileCountyCount(
                per: try c.decode(Int.self, forKey: .per),
                points: try c.decode(Int.self, forKey: .points)
            )
        case "activatedCountyCount":
            self = .activatedCountyCount(
                minQSOs: try c.decode(Int.self, forKey: .minQSOs),
                points: try c.decode(Int.self, forKey: .points)
            )
        case "sweepTiers":
            self = .sweepTiers(try c.decode([SweepTier].self, forKey: .tiers))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown bonus rule type '\(type)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .workStation(let call, let points, let scope):
            try c.encode("workStation", forKey: .type)
            try c.encode(call, forKey: .call)
            try c.encode(points, forKey: .points)
            try c.encode(scope, forKey: .scope)
        case .mobileCountyCount(let per, let points):
            try c.encode("mobileCountyCount", forKey: .type)
            try c.encode(per, forKey: .per)
            try c.encode(points, forKey: .points)
        case .activatedCountyCount(let minQSOs, let points):
            try c.encode("activatedCountyCount", forKey: .type)
            try c.encode(minQSOs, forKey: .minQSOs)
            try c.encode(points, forKey: .points)
        case .sweepTiers(let tiers):
            try c.encode("sweepTiers", forKey: .type)
            try c.encode(tiers, forKey: .tiers)
        }
    }
}

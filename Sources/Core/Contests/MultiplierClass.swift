import Foundation

/// The counting scope of a multiplier — `PartyDefinition.CountScope`, whose
/// `component(band:modeClass:)` the engine and the sidebar already share.
typealias CountScope = PartyDefinition.CountScope

/// One class of multiplier a contest counts, how its value is found for a row,
/// and how often each side counts it. Well-known ids keep today's `MultClass`
/// raw values (`county state province dx section member`) so persisted
/// snapshots and sidebar preferences read unchanged; new ids are `zone`,
/// `ituZone`, `country`, `prefix`, `grid`.
struct MultiplierClass: Codable, Equatable, Sendable, Identifiable {
    enum Layout: String, Codable, Sendable { case tokens, groupedTokens, zoneGrid, workedOnly }

    let id: String
    let term: String
    let termPlural: String
    /// Tried in order; the first that yields a value wins.
    let resolvers: [Resolver]
    /// Side id → scope. A side absent here does not count the class.
    let counting: [String: CountScope]
    /// Side id → the most distinct values that count (WA in-state: 10 DX).
    let caps: [String: Int]?
    /// The token set the sidebar lists in full (nil = worked-only).
    let roster: String?
    let layout: Layout

    init(id: String, term: String, termPlural: String? = nil, resolvers: [Resolver],
         counting: [String: CountScope], caps: [String: Int]? = nil, roster: String? = nil,
         layout: Layout = .tokens) {
        self.id = id
        self.term = term
        self.termPlural = termPlural ?? term + "s"
        self.resolvers = resolvers
        self.counting = counting
        self.caps = caps
        self.roster = roster
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey { case id, term, termPlural, resolvers, counting, caps, roster, layout }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            term: try c.decode(String.self, forKey: .term),
            termPlural: try c.decodeIfPresent(String.self, forKey: .termPlural),
            resolvers: try c.decode([Resolver].self, forKey: .resolvers),
            counting: try c.decode([String: CountScope].self, forKey: .counting),
            caps: try c.decodeIfPresent([String: Int].self, forKey: .caps),
            roster: try c.decodeIfPresent(String.self, forKey: .roster),
            layout: try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .tokens
        )
    }

    func scope(for side: String) -> CountScope? { counting[side] }
    func cap(for side: String) -> Int? { caps?[side] }
}

/// How a multiplier value is found for one logged row. Flat and data-driven:
/// only the fields the `kind` reads are meaningful.
struct Resolver: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The received `element` holds a token of `set`; value = the token,
        /// or its `mapTo` (`"group"` = the token's group — a county's state).
        case receivedToken
        /// The DXCC entity of the worked station (`from`), against `list`.
        case dxccEntity
        case cqZone, ituZone
        /// `WPXPrefix.of(call)`.
        case wpxPrefix
        /// The received `element` holds a Maidenhead grid; value = its first `precision` characters.
        case grid
        /// The worked call itself, when the received member element parses as a member number.
        case workedStation
    }
    enum From: String, Codable, Sendable { case callsign, receivedToken, receivedTokenOrCallsign, received }
    enum EntityList: String, Codable, Sendable { case arrl, arrlPlusWAE }

    let kind: Kind
    let element: String?
    let set: String?
    let mapTo: String?
    let from: From?
    let list: EntityList?
    let exclude: [Int]
    /// `dxccEntity`: count each entity separately (false = one literal `DX`).
    let countEntities: Bool
    let precision: Int?
    /// Sides this resolver serves; nil = every side.
    let sides: [String]?
    /// Callsign suffixes for which the resolver yields nothing (CQ WW: `/MM`
    /// counts only for a zone).
    let unlessSuffix: [String]?

    init(kind: Kind, element: String? = nil, set: String? = nil, mapTo: String? = nil,
         from: From? = nil, list: EntityList? = nil, exclude: [Int] = [], countEntities: Bool = true,
         precision: Int? = nil, sides: [String]? = nil, unlessSuffix: [String]? = nil) {
        self.kind = kind
        self.element = element
        self.set = set
        self.mapTo = mapTo
        self.from = from
        self.list = list
        self.exclude = exclude
        self.countEntities = countEntities
        self.precision = precision
        self.sides = sides
        self.unlessSuffix = unlessSuffix
    }

    private enum CodingKeys: String, CodingKey {
        case kind, element, set, mapTo, from, list, exclude, countEntities, precision, sides, unlessSuffix
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decode(Kind.self, forKey: .kind),
            element: try c.decodeIfPresent(String.self, forKey: .element),
            set: try c.decodeIfPresent(String.self, forKey: .set),
            mapTo: try c.decodeIfPresent(String.self, forKey: .mapTo),
            from: try c.decodeIfPresent(From.self, forKey: .from),
            list: try c.decodeIfPresent(EntityList.self, forKey: .list),
            exclude: try c.decodeIfPresent([Int].self, forKey: .exclude) ?? [],
            countEntities: try c.decodeIfPresent(Bool.self, forKey: .countEntities) ?? true,
            precision: try c.decodeIfPresent(Int.self, forKey: .precision),
            sides: try c.decodeIfPresent([String].self, forKey: .sides),
            unlessSuffix: try c.decodeIfPresent([String].self, forKey: .unlessSuffix)
        )
    }

    /// Whether this resolver is consulted for a row: the entrant's side is
    /// served, and the worked call carries none of the excluded suffixes.
    func applies(side: String, call: String) -> Bool {
        if let sides, !sides.contains(side) { return false }
        if let unlessSuffix {
            let upper = call.uppercased()
            for suffix in unlessSuffix where upper.hasSuffix("/" + suffix.uppercased()) { return false }
        }
        return true
    }
}

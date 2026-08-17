import Foundation

/// Which side of a contest a station is on — inside/outside a party's state,
/// W/VE versus DX in ARRL DX, "everyone" in CQ WW. `predicate` classifies the
/// entrant (from the sent exchange and the entrant's callsign); `workedPredicate`
/// classifies the worked station (from the received exchange and its callsign).
/// Sides are evaluated in declaration order; the first match wins, so a
/// party's `outside` side is simply `always` after `inside`.
struct Side: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let predicate: SidePredicate
    let workedPredicate: SidePredicate
}

/// A flat, data-driven predicate. Only the fields its `kind` reads are
/// meaningful; `ContestDefinition.validate()` rejects a predicate whose kind
/// lacks its field.
struct SidePredicate: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case always
        /// The exchange's `element` holds a token in `set` (any value, for a
        /// county-line entrant sitting on several).
        case tokenIn
        /// The station's DXCC entity code is one of `codes`.
        case dxccIn
        /// The station's continent is one of `continents`.
        case continentIn
    }

    let kind: Kind
    let element: String?
    let set: String?
    let codes: [Int]?
    let continents: [String]?

    init(kind: Kind, element: String? = nil, set: String? = nil, codes: [Int]? = nil, continents: [String]? = nil) {
        self.kind = kind
        self.element = element
        self.set = set
        self.codes = codes
        self.continents = continents
    }

    static let always = SidePredicate(kind: .always)

    /// What a predicate is evaluated against: an exchange (sent or received,
    /// element id → values), the station's entity and continent from
    /// `CTYTable`, and a way to find token sets by id.
    struct Context {
        let exchange: [String: [String]]
        let entityCode: Int?
        let continent: String?
        let sets: (String) -> TokenSet?
    }

    func matches(_ ctx: Context) -> Bool {
        switch kind {
        case .always:
            return true
        case .tokenIn:
            guard let element, let set, let tokens = ctx.sets(set) else { return false }
            return (ctx.exchange[element] ?? []).contains { tokens.accepts($0) }
        case .dxccIn:
            guard let code = ctx.entityCode else { return false }
            return (codes ?? []).contains(code)
        case .continentIn:
            guard let continent = ctx.continent else { return false }
            return (continents ?? []).contains(continent)
        }
    }
}

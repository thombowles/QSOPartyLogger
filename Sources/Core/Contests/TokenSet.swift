import Foundation

/// An enumerated set of exchange tokens — a party's counties, the 85 ARRL/RAC
/// sections, the US states — with the aliases a sponsor accepts for them.
///
/// Sets are referenced by `id` from `ExchangeElement.sentBy` (what a side
/// sends), `Resolver` (what a class counts) and `MultiplierClass.roster`
/// (what the sidebar lists). A contest's own sets shadow the built-ins by id.
struct TokenSet: Codable, Equatable, Sendable, Identifiable {
    struct Token: Codable, Hashable, Sendable {
        let abbr: String
        let name: String?
        /// The token's grouping for display and for `Resolver.mapTo == "group"`
        /// — a county's state in a multi-state party.
        let group: String?

        init(abbr: String, name: String? = nil, group: String? = nil) {
            self.abbr = abbr.uppercased()
            self.name = name
            self.group = group
        }
    }

    let id: String
    /// Lowercase singular, as `PartyDefinition.countyTerm` is ("county").
    let term: String
    let termPlural: String
    let tokens: [Token]
    /// Accepted spelling → canonical token ("DC" → "MD" where a party credits
    /// DC as Maryland). Keys are accepted on input; values must be tokens.
    let aliases: [String: String]

    init(id: String, term: String, termPlural: String, tokens: [Token], aliases: [String: String] = [:]) {
        self.id = id
        self.term = term
        self.termPlural = termPlural
        self.tokens = tokens
        self.aliases = Dictionary(uniqueKeysWithValues: aliases.map { ($0.key.uppercased(), $0.value.uppercased()) })
    }

    private enum CodingKeys: String, CodingKey { case id, term, termPlural, tokens, aliases }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            term: try c.decode(String.self, forKey: .term),
            termPlural: try c.decode(String.self, forKey: .termPlural),
            tokens: try c.decode([Token].self, forKey: .tokens),
            aliases: try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
        )
    }

    var abbrs: Set<String> { Set(tokens.map(\.abbr)) }

    /// Every spelling the set accepts: its tokens and its alias keys.
    var acceptedTokens: Set<String> { abbrs.union(aliases.keys) }

    func accepts(_ raw: String) -> Bool { canonical(raw) != nil }

    /// The token a spelling credits, or nil. Zone sets fold "05" to "5".
    func canonical(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if abbrs.contains(t) { return t }
        if let aliased = aliases[t] { return aliased }
        if let n = Int(t), abbrs.contains(String(n)) { return String(n) }
        return nil
    }

    func token(for abbr: String) -> Token? {
        guard let canon = canonical(abbr) else { return nil }
        return tokens.first { $0.abbr == canon }
    }

    // MARK: Built-ins

    /// 50 states + DC (`MultClass.acceptedStateTokens`).
    static let usStates = TokenSet(
        id: "usStates", term: "state", termPlural: "states",
        tokens: MultClass.acceptedStateTokens.sorted().map { Token(abbr: $0) })

    /// The 13 provinces and territories (`MultClass.canadianProvinces`).
    static let provinces = TokenSet(
        id: "provinces", term: "province", termPlural: "provinces",
        tokens: MultClass.canadianProvinces.sorted().map { Token(abbr: $0) })

    static let cqZones = TokenSet(
        id: "cqZones", term: "zone", termPlural: "zones",
        tokens: (1...40).map { Token(abbr: String($0)) })

    static let ituZones = TokenSet(
        id: "ituZones", term: "ITU zone", termPlural: "ITU zones",
        tokens: (1...90).map { Token(abbr: String($0)) })

    static let dxToken = TokenSet(
        id: "dxToken", term: "DX", termPlural: "DX",
        tokens: [Token(abbr: MultClass.dxToken, name: "Outside the US and Canada")])

    /// The built-in set for an id, or nil. `sections` is loaded from the
    /// bundle (see `TokenSet.sections(bundle:)`) and is not in this table.
    static func builtIn(id: String) -> TokenSet? {
        switch id {
        case usStates.id: usStates
        case provinces.id: provinces
        case cqZones.id: cqZones
        case ituZones.id: ituZones
        case dxToken.id: dxToken
        default: nil
        }
    }
}

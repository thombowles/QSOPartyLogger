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

        private enum CodingKeys: String, CodingKey { case abbr, name, group }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(
                abbr: try c.decode(String.self, forKey: .abbr),
                name: try c.decodeIfPresent(String.self, forKey: .name),
                group: try c.decodeIfPresent(String.self, forKey: .group)
            )
        }
    }

    let id: String
    /// Lowercase singular, as `PartyDefinition.countyTerm` is ("county").
    let term: String
    let termPlural: String
    let tokens: [Token]
    /// Accepted spelling → canonical token ("DC" → "MD" where a party credits
    /// DC as Maryland). Keys are accepted on input; values must be tokens.
    /// Case-folded; a collision keeps the first. Targets are checked by
    /// `validate()`, not at init.
    let aliases: [String: String]
    /// Every token's `abbr`. Precomputed at init from `tokens`.
    let abbrs: Set<String>

    init(id: String, term: String, termPlural: String, tokens: [Token], aliases: [String: String] = [:]) {
        self.id = id
        self.term = term
        self.termPlural = termPlural
        self.tokens = tokens
        self.abbrs = Set(tokens.map(\.abbr))
        self.aliases = Dictionary(
            aliases.map { ($0.key.uppercased(), $0.value.uppercased()) },
            uniquingKeysWith: { first, _ in first }
        )
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

    /// `abbrs` is derived from `tokens` and is not encoded.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(term, forKey: .term)
        try c.encode(termPlural, forKey: .termPlural)
        try c.encode(tokens, forKey: .tokens)
        try c.encode(aliases, forKey: .aliases)
    }

    /// Every spelling the set accepts: its tokens and its alias keys.
    var acceptedTokens: Set<String> { abbrs.union(aliases.keys) }

    func accepts(_ raw: String) -> Bool { canonical(raw) != nil }

    /// The token a spelling credits, or nil.
    ///
    /// The numeric fold applies to every set: a token spelled with leading
    /// zeros credits its plain number when the set carries that number
    /// (`05` → `5` for zones). Sets never mix zero-padded and plain
    /// spellings of the same number.
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

    /// Duplicate token abbreviations, alias targets that aren't tokens, and
    /// alias keys that shadow a token's `abbr`. Called by
    /// `ContestDefinition.validate()`; the built-ins pass by construction.
    func validate() throws {
        var seen = Set<String>()
        for token in tokens {
            guard seen.insert(token.abbr).inserted else {
                throw TokenSetError.duplicateAbbreviation(token.abbr)
            }
        }
        for (key, target) in aliases {
            guard !abbrs.contains(key) else {
                throw TokenSetError.aliasShadowsToken(key)
            }
            guard abbrs.contains(target) else {
                throw TokenSetError.aliasTargetMissing(key, target)
            }
        }
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

    /// The 85 ARRL/RAC sections, from `Resources/Data/arrl_sections.json`
    /// (generated by `docs/research/gen_sections.py`). Nil when the resource
    /// is missing or does not decode — the app then has no section list, and
    /// `ContestDefinition.validate()` reports the missing set. The file's
    /// `source` key is provenance for readers of the repository, not decoded
    /// (the app never displays it).
    static func sections(bundle: Bundle = .main) -> TokenSet? {
        guard let url = bundle.url(forResource: "arrl_sections", withExtension: "json", subdirectory: "Data"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    /// The built-in set for an id, or nil. `sections` is loaded from the
    /// bundle (see `TokenSet.sections(bundle:)`) and is not in this table.
    static func builtIn(id: String) -> TokenSet? {
        switch id {
        case "usStates": usStates
        case "provinces": provinces
        case "cqZones": cqZones
        case "ituZones": ituZones
        case "dxToken": dxToken
        default: nil
        }
    }
}

enum TokenSetError: Error, Equatable, LocalizedError {
    case duplicateAbbreviation(String)
    case aliasTargetMissing(String, String)
    case aliasShadowsToken(String)

    var errorDescription: String? {
        switch self {
        case .duplicateAbbreviation(let a): "Token abbreviation '\(a)' appears more than once."
        case .aliasTargetMissing(let key, let target): "Alias '\(key)' points to '\(target)', which is not a token."
        case .aliasShadowsToken(let key): "Alias '\(key)' duplicates a token abbreviation."
        }
    }
}

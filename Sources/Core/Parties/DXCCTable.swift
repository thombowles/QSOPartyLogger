import Foundation

/// The ARRL DXCC List as a prefix → entity lookup, so parties whose sponsors
/// count DXCC entities individually can tell one from another.
///
/// Generated from the sponsor-designated source by
/// `docs/research/gen_dxcc.py` — never hand-typed (constitution Article 2).
/// The source is the **ARRL DXCC List, Current Entities, January 2026
/// Edition**, which NAQP rules 3 and 11 designate by name and which
/// `gen_naqp.py` already reads for its North American entity names.
///
/// ## Resolution model
///
/// Entity comes from the **callsign**, never from the received exchange. That
/// split is N1MM Logger+'s, and it is why a Salmon Run contact with `PA0AAA`
/// sending `PA` can be told from `W3XYZ` sending the same token: the exchange
/// field says which *location* was sent, the call says which *entity* sent it.
/// N1MM's manual states the exchange half plainly — "There is a check on
/// provinces and states, no check on countries" — and matches the entity from
/// the call against its country file.
///
/// ## What this table cannot do, by construction
///
/// - **Spratly Is. has no prefix.** Its prefix cell is empty in the ARRL PDF's
///   own text layer, so no callsign resolves to it. Supplying one from memory
///   would be the hand-typed datum Article 2 forbids.
/// - **Fourteen prefix blocks are shared by several entities in the ARRL list
///   itself** — `FO` is Clipperton *and* French Polynesia *and* Austral *and*
///   Marquesas. Each resolves to one designated entity; `mergedPrefixes`
///   names the ones that lose, so the merge can be explained rather than
///   silently applied. N1MM has the same limit and answers it with
///   exact-callsign entries in its country file.
/// - **`TO` and `TX` resolve to nothing.** France shares those pools across
///   five and three entities respectively, so no call beginning `TO`/`TX` can
///   be attributed from this document. Those entities keep their own
///   unambiguous prefixes (`FG`, `FM`, `FR`, `FS`, `FT/T`), which is what
///   stations sign.
/// - **Prefix matching is coarser than DXCC's own rules in places.** Every
///   `KG4` call resolves to Guantanamo Bay, though the entity is really only
///   the two-letter-suffix calls. The ARRL list states no such rule, so
///   encoding one would be inventing a fact.
struct DXCCTable: Sendable {

    struct Entity: Codable, Equatable, Sendable, Identifiable {
        /// ARRL entity code — the list's own stable identifier ("230").
        let code: String
        /// ARRL entity name ("Germany"), and the multiplier value the engine
        /// counts: unique across the list and legible in a log.
        let name: String
        /// ARRL continent column ("EU", "NA", "AS/AF").
        let continent: String
        let prefixes: [String]
        /// What the multiplier list shows — `DL` for Germany, `OZ` for
        /// Denmark. Always one of `prefixes`: cty.dat's primary-prefix field
        /// only *chooses* among the prefixes the ARRL list gives, it never
        /// contributes one. nil only where the ARRL list gives no prefix at
        /// all, which is Spratly Is. alone and unreachable anyway.
        let primaryPrefix: String?

        var id: String { code }
    }

    /// A prefix block the ARRL list gives to more than one entity.
    struct MergedPrefix: Codable, Equatable, Sendable {
        /// The entity a bare match on this prefix is credited to.
        let entity: String
        /// The entities that share the block and are not credited.
        let alsoClaimedBy: [String]
    }

    let source: String
    let fetched: String
    let entities: [Entity]
    /// Prefix → entity code. Longest match wins, so `EA6` beats `EA`.
    let prefixes: [String: String]
    let mergedPrefixes: [String: MergedPrefix]
    /// Entity code → name, for entities the source gives no prefix.
    let withoutPrefix: [String: String]

    private let byCode: [String: Entity]
    private let longestPrefix: Int

    // MARK: Loading

    private enum CodingKeys: String, CodingKey {
        case source, fetched, entities, prefixes, mergedPrefixes, withoutPrefix
    }

    static func load(bundle: Bundle = .main) -> DXCCTable? {
        guard let url = bundle.url(
            forResource: "dxcc_entities", withExtension: "json", subdirectory: "DXCC"
        ), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DXCCTable.self, from: data)
    }

    /// The bundled table. Empty rather than nil when the resource is missing,
    /// so a broken build degrades to today's single-DX-multiplier behaviour
    /// instead of trapping mid-contest.
    static let shared: DXCCTable = load() ?? .empty

    static let empty = DXCCTable(
        source: "", fetched: "", entities: [], prefixes: [:],
        mergedPrefixes: [:], withoutPrefix: [:]
    )

    init(
        source: String,
        fetched: String,
        entities: [Entity],
        prefixes: [String: String],
        mergedPrefixes: [String: MergedPrefix],
        withoutPrefix: [String: String]
    ) {
        self.source = source
        self.fetched = fetched
        self.entities = entities
        self.prefixes = prefixes
        self.mergedPrefixes = mergedPrefixes
        self.withoutPrefix = withoutPrefix
        self.byCode = Dictionary(uniqueKeysWithValues: entities.map { ($0.code, $0) })
        self.longestPrefix = prefixes.keys.map(\.count).max() ?? 0
    }

    // MARK: Lookup

    /// The entity a received prefix token names, or nil if the ARRL list has
    /// no such prefix. Exact — `DL` resolves, `DLX` does not.
    func entity(forPrefix token: String) -> Entity? {
        guard let code = prefixes[token.uppercased()] else { return nil }
        return byCode[code]
    }

    /// The entities a US or Canadian station belongs to, by ARRL entity code.
    ///
    /// These are the ones whose operators send a **state or province** in a
    /// QSO party exchange, so a token from them is never a DX entity however
    /// well it matches a prefix. Without this, Alberta's `AB` reads as the
    /// United States — the ARRL list's US row is `K, W, N, AA-AK`, and `AB`
    /// falls inside it — and a Canadian entrant loses two multipliers.
    ///
    /// Alaska and Hawaii are separate DXCC entities and US states both; the
    /// state reading is the one every sponsor uses, and NMQP says so outright:
    /// "Alaska and Hawaii are states, not DX."
    static let domesticEntityCodes: Set<String> = [
        "291",  // United States of America
        "006",  // Alaska
        "110",  // Hawaii
        "001",  // Canada
    ]

    /// Whether a worked callsign belongs to an entity that sends a state or
    /// province rather than a country.
    func isDomestic(callsign: String) -> Bool {
        guard let entity = entity(forCallsign: callsign) else { return false }
        return Self.domesticEntityCodes.contains(entity.code)
    }

    /// Whether this token is a DXCC prefix the ARRL list actually carries.
    /// Replaces the old shape heuristic, which accepted any 1–5 alphanumerics
    /// and so turned a mistyped county into a valid DX entity.
    func isKnownPrefix(_ token: String) -> Bool {
        prefixes[token.uppercased()] != nil
    }

    /// An entity together with the prefix that actually matched.
    ///
    /// The prefix is what an operator recognises — `DL1ABC` matched on `DL` —
    /// so it is what the multiplier list shows. It is deliberately *not* the
    /// entity's identity: Germany's ARRL row is `DA`–`DR`, so `DL` and `DJ`
    /// are one multiplier and only the entity code can say so. The ARRL list
    /// publishes no primary prefix to use instead; that field belongs to
    /// cty.dat, which is not authority here.
    struct Match: Equatable, Sendable {
        let entity: Entity
        /// The table key that matched — `M` for `M0DD`, `DJ` for `DJ2BB`.
        let prefix: String

        /// What to show for this contact: the entity's primary prefix, so
        /// `DL1AA` and `DJ2BB` both read `DL`. Falls back to the key that
        /// matched if the ARRL list gave the entity no prefixes.
        var label: String { entity.primaryPrefix ?? prefix }
    }

    /// The entity a worked station belongs to, by longest prefix match on its
    /// callsign — N1MM's model, and the only way to tell DX entities apart in
    /// a party whose exchange is the literal token "DX".
    func match(callsign call: String) -> Match? {
        let stem = Self.locationPart(of: call)
        guard !stem.isEmpty else { return nil }
        var length = min(longestPrefix, stem.count)
        while length > 0 {
            let candidate = String(stem.prefix(length))
            if let code = prefixes[candidate], let entity = byCode[code] {
                return Match(entity: entity, prefix: candidate)
            }
            length -= 1
        }
        return nil
    }

    /// The entity a received prefix token names, with the token normalised to
    /// the table's own casing.
    func match(prefix token: String) -> Match? {
        let key = token.uppercased()
        guard let code = prefixes[key], let entity = byCode[code] else { return nil }
        return Match(entity: entity, prefix: key)
    }

    func entity(forCallsign call: String) -> Entity? { match(callsign: call)?.entity }

    // MARK: Callsign shape

    /// Suffixes that say how a station is operating, not where it is.
    private static let operatingSuffixes: Set<String> = [
        "P", "M", "MM", "AM", "A", "B", "QRP", "LH", "BCN", "R", "J",
    ]

    /// The part of a callsign that carries the location.
    ///
    /// A plain call is itself. A slashed call is the shorter remaining part
    /// once operating suffixes and bare call-area digits are dropped, which
    /// reads both conventions the same way: `KH6/DL1ABC` and `DL1ABC/KH6`
    /// both give `KH6`.
    static func locationPart(of call: String) -> String {
        let trimmed = call.uppercased().trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("/") else { return trimmed }
        let parts = trimmed.split(separator: "/").map(String.init).filter {
            !$0.isEmpty && !operatingSuffixes.contains($0) && !$0.allSatisfy(\.isNumber)
        }
        guard let first = parts.first else { return "" }
        return parts.dropFirst().reduce(first) { $1.count < $0.count ? $1 : $0 }
    }
}

extension DXCCTable: Codable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            source: try c.decode(String.self, forKey: .source),
            fetched: try c.decode(String.self, forKey: .fetched),
            entities: try c.decode([Entity].self, forKey: .entities),
            prefixes: try c.decode([String: String].self, forKey: .prefixes),
            mergedPrefixes: try c.decodeIfPresent(
                [String: MergedPrefix].self, forKey: .mergedPrefixes
            ) ?? [:],
            withoutPrefix: try c.decodeIfPresent(
                [String: String].self, forKey: .withoutPrefix
            ) ?? [:]
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source)
        try c.encode(fetched, forKey: .fetched)
        try c.encode(entities, forKey: .entities)
        try c.encode(prefixes, forKey: .prefixes)
        try c.encode(mergedPrefixes, forKey: .mergedPrefixes)
        try c.encode(withoutPrefix, forKey: .withoutPrefix)
    }
}

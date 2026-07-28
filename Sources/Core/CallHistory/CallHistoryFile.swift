import Foundation

/// The N1MM call history text format: what a per-contest community file says
/// each station sends, indexed by call.
///
/// Format per the N1MM documentation (n1mmwp.hamdocs.com/setup/call-history/,
/// fetched 2026-07-28): comma- or semicolon-delimited fields in a declared
/// order; an `!!Order!!` line re-declares the order; `#` begins a comment;
/// field name case is not important. The hand-maintained files drift in every
/// way the tests enumerate — directives after comments, spaces around field
/// names, trailing commas, missing Name columns — so the parser is strict
/// about *structure* and forgiving about *whitespace*.
///
/// **Nothing here is authority for anything** (constitution Article 1). A
/// parsed value becomes a prefill candidate only after the party's own
/// `ExchangeParser` accepts it, and no value ever reaches `ScoreEngine`. The
/// files say it themselves: "This is helping file, LOG what you copy."
enum CallHistoryFile {

    /// One station's row, reduced to what this app can offer.
    struct Entry: Equatable, Sendable {
        let call: String
        /// Operator name, uppercased — offered only in name parties.
        let name: String?
        /// Location candidates in trust order: Exch1, then Sect, then State.
        /// Values pass through verbatim (county-line pairs like
        /// "NSHRM/NSCOL", DX prefixes like "8P") for the party's parser to
        /// judge.
        let locations: [String]
        /// Free text from the file's maintainer ("Etowah (ETOW)", "MOBILE").
        let userText: String?

        var isEmpty: Bool { name == nil && locations.isEmpty && userText == nil }
    }

    /// A parsed file: entries by call plus the file's self-declarations.
    struct Parsed: Equatable, Sendable {
        let entriesByCall: [String: Entry]
        /// Normalized `#` comment lines (uppercased, whitespace removed) —
        /// what `CallHistorySource.isDeclared(inCommentTokens:)` checks.
        let tokens: Set<String>
        /// Rows read, counting duplicates — the honest size of the file.
        let recordCount: Int

        static let empty = Parsed(entriesByCall: [:], tokens: [], recordCount: 0)

        /// Exact match on the normalized call first; failing that, the typed
        /// call stripped of portable decorations (`AA2IL/6` → `AA2IL`) — the
        /// base is the longest slash-separated segment, so `W4/G3ABC` looks
        /// up `G3ABC`. The reverse (file has the suffix, operator typed the
        /// base) is deliberately not guessed at.
        func entry(for call: String) -> Entry? {
            let wanted = call.trimmingCharacters(in: .whitespaces).uppercased()
            guard !wanted.isEmpty else { return nil }
            if let exact = entriesByCall[wanted] { return exact }
            guard wanted.contains("/") else { return nil }
            let base = wanted.components(separatedBy: "/")
                .filter { !$0.isEmpty }
                .max { $0.count < $1.count }
            guard let base, base != wanted else { return nil }
            return entriesByCall[base]
        }
    }

    /// What the file knows about one call, filtered to what `party` can
    /// actually accept from an operator in `role`. `nil` when it knows
    /// nothing usable — never offer an exchange the entry row would reject.
    struct Candidate: Equatable, Sendable {
        let exchange: String?
        let name: String?
        let userText: String?
    }

    static func candidate(
        for call: String,
        in parsed: Parsed,
        party: PartyDefinition,
        role: ExchangeParser.Role
    ) -> Candidate? {
        guard let entry = parsed.entry(for: call) else { return nil }
        let exchange = entry.locations.first {
            if case .success = ExchangeParser.parse($0, party: party, role: role) {
                return true
            }
            return false
        }
        let name = party.exchangeIncludesName ? entry.name : nil
        guard exchange != nil || name != nil else { return nil }
        return Candidate(exchange: exchange, name: name, userText: entry.userText)
    }

    // MARK: Parsing

    /// Fields this app stores. Every other name in an `!!Order!!` line (CK,
    /// BirthDate, Power, grids…) holds its position and is read past.
    private enum Field: String {
        case call, name, exch1, sect, state, usertext
    }

    /// The documented default order, for files with no `!!Order!!` line.
    private static let defaultOrder: [Field?] = [
        .call, .name, nil, nil, .sect, .state, nil, nil, .exch1, nil,
        nil, nil, nil, .usertext,
    ]

    static func parse(data: Data) -> Parsed? {
        // The files are UTF-8 today (Quebec's accents included), but they are
        // hand-maintained Windows exports at heart — decode permissively
        // rather than reject a season's file over one stray byte.
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
            ?? String(data: data, encoding: .isoLatin1)
        return text.map(parse)
    }

    static func parse(_ text: String) -> Parsed {
        var order = defaultOrder
        var entries: [String: Entry] = [:]
        var tokens: Set<String> = []
        var records = 0

        for rawLine in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("#") {
                let comment = CallHistorySource.normalized(
                    String(line.dropFirst()))
                if !comment.isEmpty { tokens.insert(comment) }
                continue
            }

            if line.hasPrefix("!!") {
                if let declared = parseOrderDirective(line), !declared.isEmpty {
                    order = declared
                }
                // Import directives (!!MapStateToSect!! …) are N1MM's own
                // business; they alter nothing this app reads.
                continue
            }

            guard let entry = parseRecord(line, order: order) else { continue }
            records += 1
            // A call can appear in more than one section carrying different
            // halves — the real Alabama file lists WA1FCN once with his
            // county ("WA1FCN,,WLKR,WALKER") and once with his name
            // ("WA1FCN,BOB,"). Later rows overwrite per field, never blank
            // an earlier field, so both halves survive.
            if let existing = entries[entry.call] {
                entries[entry.call] = Entry(
                    call: entry.call,
                    name: entry.name ?? existing.name,
                    locations: entry.locations.isEmpty
                        ? existing.locations : entry.locations,
                    userText: entry.userText ?? existing.userText
                )
            } else {
                entries[entry.call] = entry
            }
        }
        return Parsed(entriesByCall: entries, tokens: tokens, recordCount: records)
    }

    /// `!!Order!!,Call,Name,Exch1,UserText,` — case-insensitive names,
    /// tolerant of spaces and the trailing comma. `nil` if this is some other
    /// `!!…!!` directive.
    private static func parseOrderDirective(_ line: String) -> [Field?]? {
        let parts = split(line)
        guard let first = parts.first,
              first.caseInsensitiveCompare("!!Order!!") == .orderedSame
        else { return nil }
        // Trailing empty tokens are comma artifacts ("…,UserText,"), not
        // fields — dropped so excess delimiters absorb into the last *named*
        // field rather than into a phantom column.
        var names = Array(parts.dropFirst())
        while names.last?.isEmpty == true { names.removeLast() }
        return names.map { Field(rawValue: $0.lowercased()) }
    }

    private static func parseRecord(_ line: String, order: [Field?]) -> Entry? {
        var values = split(line)
        // The last declared field absorbs any extra delimiters, so free text
        // with a comma in it ("Mobile with Melody, KI4HVY") survives whole.
        if values.count > order.count {
            let tail = values[(order.count - 1)...]
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            values = Array(values.prefix(order.count - 1)) + [tail]
        }

        var call: String?
        var name: String?
        var userText: String?
        var byField: [Field: String] = [:]

        for (slot, value) in zip(order, values) where !value.isEmpty {
            switch slot {
            case .call: call = value.uppercased()
            case .name: name = value.uppercased()
            case .usertext: userText = value
            case .exch1, .sect, .state: byField[slot!] = value.uppercased()
            case nil: break
            }
        }

        guard let call, !call.isEmpty else { return nil }
        let locations = [Field.exch1, .sect, .state].compactMap { byField[$0] }
        return Entry(call: call, name: name, locations: locations, userText: userText)
    }

    /// Comma or semicolon delimited (both documented), tokens trimmed.
    private static func split(_ line: String) -> [String] {
        line.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

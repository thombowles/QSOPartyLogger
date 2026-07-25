import Foundation

/// Parses and validates an exchange location field ("MRN", "lin/and", "TX", "DX")
/// against a party's county list and out-of-state tokens.
enum ExchangeParser {

    /// Where the operator is entered from, which decides what can legitimately
    /// arrive in the exchange field.
    ///
    /// An in-state station works all comers, so every token the party can
    /// produce is valid for it. An out-of-state entrant hears a much narrower
    /// set — under most sponsors' rules, only home-state stations count at all
    /// — and validating against the wider set turns typos into valid
    /// exchanges.
    enum Role: Equatable, Sendable {
        case inState
        case outOfState
    }

    struct ParsedExchange: Equatable {
        /// County abbreviations (1–4, county-line) or a single out-of-state token.
        let locations: [String]
        let isInStateCounties: Bool
    }

    enum ExchangeError: Error, Equatable, LocalizedError {
        case empty
        case unknownAbbreviation(String, suggestions: [String])
        case tooManyCounties(Int)
        case mixedTypes

        var errorDescription: String? {
            switch self {
            case .empty:
                "Enter a county abbreviation, state, province, or DX."
            case .unknownAbbreviation(let token, let suggestions):
                suggestions.isEmpty
                    ? "'\(token)' is not a valid county, state, or province."
                    : "'\(token)' is not valid. Did you mean \(suggestions.joined(separator: ", "))?"
            case .tooManyCounties(let n):
                "\(n) counties given — county lines support at most \(ExchangeParser.maxCounties)."
            case .mixedTypes:
                "Mixing counties with states/provinces isn't valid."
            }
        }
    }

    /// Absolute ceiling; parties usually cap lower via `maxSimultaneousCounties`.
    static let maxCounties = 4

    /// County-line entries are separated with "/" or "," only. Space is not a
    /// separator: it advances the entry row's cursor, so it cannot be typed
    /// here at all. Tokens are trimmed so "lin, and" still reads as two.
    static func tokenize(_ raw: String) -> [String] {
        raw.uppercased()
            .components(separatedBy: CharacterSet(charactersIn: "/,"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Whether an out-of-state entrant can receive anything but a home-state
    /// county. False only where the sponsor's own rules restrict them to
    /// home-state contacts — the flag carries that rule text per party.
    static func acceptsOutStateTokens(party: PartyDefinition, role: Role) -> Bool {
        role == .inState || !party.outStateWorksHomeStationsOnly
    }

    /// Whether a token that matches nothing may be guessed at as a DXCC prefix.
    ///
    /// The guess exists so DX entities can be counted as multipliers, and it is
    /// necessarily loose — a prefix really can be almost any short string, and
    /// there is no DXCC table here to check it against. Loose is tolerable only
    /// where it buys something: if DX is not a multiplier class for this
    /// operator, the guess buys nothing and costs everything, silently turning
    /// every mistyped county into a valid exchange.
    static func acceptsDXPrefix(party: PartyDefinition, role: Role) -> Bool {
        let rule = role == .inState ? party.multipliers.inState : party.multipliers.outState
        return rule.classes.contains(.dx)
    }

    static func parse(
        _ raw: String,
        party: PartyDefinition,
        role: Role
    ) -> Result<ParsedExchange, ExchangeError> {
        let tokens = tokenize(raw)
        guard !tokens.isEmpty else { return .failure(.empty) }

        let countyAbbrs = Set(party.counties.map(\.abbr))
        let outTokens = acceptsOutStateTokens(party: party, role: role)
            ? party.validOutStateTokens
            : []

        let counties = tokens.filter { countyAbbrs.contains($0) }
        let outs = tokens.filter { outTokens.contains($0) }

        if counties.count == tokens.count {
            var seen = Set<String>()
            let unique = tokens.filter { seen.insert($0).inserted }
            let cap = min(maxCounties, party.maxSimultaneousCounties)
            guard unique.count <= cap else {
                return .failure(.tooManyCounties(unique.count))
            }
            return .success(ParsedExchange(locations: unique, isInStateCounties: true))
        }

        if outs.count == tokens.count {
            // Out-of-state stations have exactly one location.
            guard tokens.count == 1 else { return .failure(.mixedTypes) }
            return .success(ParsedExchange(locations: [tokens[0]], isInStateCounties: false))
        }

        // DX prefix (ALQP/TQP/TnQP/WA/MDC style): single unknown token that
        // plausibly is a DXCC prefix — but only where DX is a multiplier for
        // this operator, or every typo becomes a valid exchange.
        if tokens.count == 1,
           acceptsDXPrefix(party: party, role: role),
           party.isPlausibleDXPrefix(tokens[0]) {
            return .success(ParsedExchange(locations: [tokens[0]], isInStateCounties: false))
        }

        if !counties.isEmpty && !outs.isEmpty {
            return .failure(.mixedTypes)
        }

        let bad = tokens.first { !countyAbbrs.contains($0) && !outTokens.contains($0) } ?? tokens[0]
        return .failure(
            .unknownAbbreviation(bad, suggestions: suggestions(for: bad, party: party, role: role))
        )
    }

    /// Prefix matches plus edit-distance-1 candidates, capped at 3. Drawn from
    /// what this operator can actually receive, so an out-of-state entrant is
    /// never pointed at a state token it cannot log.
    static func suggestions(for token: String, party: PartyDefinition, role: Role) -> [String] {
        let outTokens = acceptsOutStateTokens(party: party, role: role)
            ? party.validOutStateTokens.sorted()
            : []
        let all = party.counties.map(\.abbr) + outTokens
        var out: [String] = []
        for abbr in all where abbr.hasPrefix(token) && abbr != token {
            out.append(abbr)
        }
        for abbr in all where !out.contains(abbr) && isEditDistanceOne(token, abbr) {
            out.append(abbr)
        }
        return Array(out.prefix(3))
    }

    /// True for one substitution, one insertion/deletion, or one adjacent
    /// transposition (Damerau) — "LNI" suggests "LIN".
    static func isEditDistanceOne(_ a: String, _ b: String) -> Bool {
        let x = Array(a), y = Array(b)
        if abs(x.count - y.count) > 1 { return false }
        if x.count == y.count {
            let diffs = (0..<x.count).filter { x[$0] != y[$0] }
            if diffs.count == 1 { return true }
            return diffs.count == 2
                && diffs[1] == diffs[0] + 1
                && x[diffs[0]] == y[diffs[1]]
                && x[diffs[1]] == y[diffs[0]]
        }
        let (short, long) = x.count < y.count ? (x, y) : (y, x)
        var i = 0, j = 0, edits = 0
        while i < short.count && j < long.count {
            if short[i] == long[j] { i += 1; j += 1 } else {
                edits += 1
                if edits > 1 { return false }
                j += 1
            }
        }
        return true
    }
}

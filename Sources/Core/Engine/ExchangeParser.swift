import Foundation

/// Parses and validates an exchange location field ("MRN", "lin/and", "TX", "DX")
/// against a party's county list and out-of-state tokens.
enum ExchangeParser {

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

    static func parse(_ raw: String, party: PartyDefinition) -> Result<ParsedExchange, ExchangeError> {
        let tokens = tokenize(raw)
        guard !tokens.isEmpty else { return .failure(.empty) }

        let countyAbbrs = Set(party.counties.map(\.abbr))
        let outTokens = party.validOutStateTokens

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
        // plausibly is a DXCC prefix.
        if tokens.count == 1, party.isPlausibleDXPrefix(tokens[0]) {
            return .success(ParsedExchange(locations: [tokens[0]], isInStateCounties: false))
        }

        if !counties.isEmpty && !outs.isEmpty {
            return .failure(.mixedTypes)
        }

        let bad = tokens.first { !countyAbbrs.contains($0) && !outTokens.contains($0) } ?? tokens[0]
        return .failure(.unknownAbbreviation(bad, suggestions: suggestions(for: bad, party: party)))
    }

    /// Prefix matches plus edit-distance-1 candidates, capped at 3.
    static func suggestions(for token: String, party: PartyDefinition) -> [String] {
        let all = party.counties.map(\.abbr) + party.validOutStateTokens.sorted()
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

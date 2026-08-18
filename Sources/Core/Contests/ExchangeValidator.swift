import Foundation

/// Validates one received exchange element for an entrant on `side`, per its
/// kind. Token kinds keep `ExchangeParser`'s tokeniser, suggestions and
/// edit-distance help; the parity test pins them equal on every party.
enum ExchangeValidator {
    /// A rejection in the element's own words.
    ///
    /// `hint` is what this element accepts, spelled with the accepted sets'
    /// own `term`s in the order the element sends them — "county, state,
    /// province, or DX" for a Kansas entrant, "parish, state, province, or
    /// DXCC prefix" where the sponsor says parish. `term` is the plural of the
    /// set a side may send several of at once ("counties"). A fixed-shape kind
    /// carries its whole sentence in `badFormat`.
    enum Failure: Error, Equatable, LocalizedError {
        case empty(hint: String)
        case invalid(String, suggestions: [String], hint: String)
        case tooMany(Int, max: Int, term: String)
        /// Several tokens where only one value is allowed. Several of the
        /// *same* set — a county line — is `tooMany` when it runs past the cap.
        case mixed(hint: String)
        case badFormat(String)

        var errorDescription: String? {
            switch self {
            case .empty(let hint): "Enter a \(hint)."
            case .invalid(let t, let s, let hint):
                s.isEmpty ? "'\(t)' is not a valid \(hint)." : "'\(t)' is not valid. Did you mean \(s.joined(separator: ", "))?"
            case .tooMany(let n, let max, let term): "\(n) \(term) given — at most \(max) allowed."
            case .mixed(let hint): "Only one \(hint) at a time."
            case .badFormat(let what): what
            }
        }
    }

    /// The accepted value(s): one for every kind but a multi-valued token
    /// element (a county line), which returns each county in typed order.
    /// Normalised for the fixed-shape kinds — `007` is QSO number `7`, `5NN`
    /// is `599`, `05` is zone `5` — and returned **as sent** for a token
    /// kind, where an accepted spelling is the sponsor's datum
    /// (`validateToken`).
    static func validate(_ raw: String, element: ExchangeElement, contest: ContestDefinition,
                         side: String, bundle: Bundle = .main) -> Result<[String], Failure> {
        let text = raw.trimmingCharacters(in: .whitespaces).uppercased()
        switch element.kind {
        case .token:
            return validateToken(text, element: element, contest: contest, side: side, bundle: bundle)
        case .rst:
            // Cut numbers folded back the way this app's own sender writes
            // them (`AppSettings.applyCutNumbers`): N is 9, T is 0, A is 1, so
            // a CW operator may type what they copied. Which length a mode
            // class wants — 59 on phone, 599 on CW — is not enforced here:
            // the report is the operator's to give, and sponsors' logs carry
            // both.
            let cut = String(text.map { c -> Character in
                switch c {
                case "N": "9"
                case "T": "0"
                case "A": "1"
                default: c
                }
            })
            return cut.count >= 2 && cut.count <= 3 && cut.allSatisfy(\.isNumber) ? .success([cut]) : .failure(.badFormat("A signal report is 2 or 3 digits."))
        case .serial:
            guard !text.isEmpty, text.count <= 5, text.allSatisfy(\.isNumber), let n = Int(text), n >= 1 else {
                return .failure(.badFormat("A QSO number is 1–5 digits."))
            }
            return .success([String(n)])
        case .name:
            // NAQP names arrive hyphenated ("MARY-ANN") and apostrophed
            // ("O'NEIL"); a digit is still a typo.
            let ok = !text.isEmpty && text.count <= 15 && text.allSatisfy { $0.isLetter || $0 == "-" || $0 == "'" }
            return ok ? .success([text]) : .failure(.badFormat("A name is 1–15 letters."))
        case .cqZone, .ituZone:
            let top = element.kind == .cqZone ? 40 : 90
            // Digits only: `Int("+5")` is 5, and a signed zone is a typo.
            guard text.allSatisfy(\.isNumber), let n = Int(text), (1...top).contains(n) else {
                return .failure(.badFormat("A zone is 1–\(top)."))
            }
            return .success([String(n)])
        case .precedence:
            return (element.letters ?? []).contains(text) ? .success([text]) : .failure(.badFormat("Precedence is one of \((element.letters ?? []).joined(separator: " "))."))
        case .check:
            return text.count == 2 && text.allSatisfy(\.isNumber) ? .success([text]) : .failure(.badFormat("A check is two digits."))
        case .classToken:
            let digits = text.prefix { $0.isNumber }
            let letter = text.dropFirst(digits.count)
            guard let n = Int(digits), n >= (element.minNumber ?? 1), letter.count == 1,
                  (element.letters ?? []).contains(String(letter)) else {
                return .failure(.badFormat("A class is a number and one of \((element.letters ?? []).joined(separator: " "))."))
            }
            return .success([String(n) + letter])
        case .power:
            let ok = text == "K" || text == "KW" || text.range(of: #"^\d+(W|K|KW)?$"#, options: .regularExpression) != nil
            return ok ? .success([text]) : .failure(.badFormat("Power is a number, or K/KW."))
        case .memberOrPower:
            guard let value = MemberExchange.parse(text) else { return .failure(.badFormat("A member number, or a power with its unit (5W).")) }
            switch value {
            case .member(let number): return .success([number])
            case .power: return .success([text.filter { !$0.isWhitespace }])
            }
        case .callEcho:
            guard !text.isEmpty else { return .failure(.badFormat("Enter the callsign as sent back.")) }
            return .success([text])
        case .grid:
            return text.range(of: #"^[A-R]{2}\d{2}([A-X]{2})?$"#, options: .regularExpression) != nil
                ? .success([text]) : .failure(.badFormat("A grid is 4 or 6 characters (EM13 or EM13LE)."))
        case .report:
            return text.range(of: #"^[-+]?\d{1,2}$"#, options: .regularExpression) != nil
                ? .success([text]) : .failure(.badFormat("A report is a signed number of dB."))
        }
    }

    // MARK: Token kinds

    /// The sets an element accepts for an entrant on `side`, resolved once: in
    /// the order the element sends them over the sides the entrant may work
    /// (side declaration order, then each side's `sets` order), with the union
    /// of every enumerated set's accepted spellings — what the dynamic
    /// `dxccPrefix` set must not claim. Built once per element and side by the
    /// validator (per field) and by the engine (per `score`), never per token.
    /// The one value classifies a token, pools what the element accepts,
    /// orders the suggestions, and names the element in the sponsor's own
    /// words — `dxccPrefix` is dynamic and has no `TokenSet` to ask, so its
    /// entry's `set` is nil.
    struct ResolvedSets: Sendable {
        let entries: [(id: String, set: TokenSet?)]
        let accepted: Set<String>
    }

    static func resolvedSets(for element: ExchangeElement, contest: ContestDefinition,
                             side: String, bundle: Bundle = .main) -> ResolvedSets {
        let entries: [(id: String, set: TokenSet?)] = element.setsSent(by: contest.workableSides(for: side)).map {
            ($0, contest.tokenSet(id: $0, bundle: bundle))
        }
        return ResolvedSets(entries: entries, accepted: entries.reduce(into: Set<String>()) { $0.formUnion($1.set?.acceptedTokens ?? []) })
    }

    /// The set a received token belongs to: the first entry that accepts it —
    /// the dynamic `dxccPrefix` accepting a known DXCC prefix that no
    /// enumerated set claims. Nil when nothing accepts it. Validation
    /// (`validateToken`) and scoring (`ScoreEngine`) classify through this one
    /// function, so a token cannot be valid under one reading and counted
    /// under another; the engine layers the callsign override on top
    /// (`Resolver.callsignOverrides`), moving the row's owner to `dxccPrefix`
    /// **before any class's resolvers run**, so a colliding token is never
    /// credited twice.
    static func owningSet(of token: String, in sets: ResolvedSets) -> String? {
        let t = token.trimmingCharacters(in: .whitespaces).uppercased()
        for entry in sets.entries {
            if entry.id == "dxccPrefix" {
                if isDXPrefix(t, excluding: sets.accepted) { return entry.id }
            } else if let set = entry.set, set.accepts(t) {
                return entry.id
            }
        }
        return nil
    }

    /// `owningSet(of:in:)` over freshly resolved sets — for one-off questions; per-row callers resolve once.
    static func owningSet(of token: String, element: ExchangeElement, contest: ContestDefinition,
                          side: String, bundle: Bundle = .main) -> String? {
        owningSet(of: token, in: resolvedSets(for: element, contest: contest, side: side, bundle: bundle))
    }

    private static func validateToken(_ text: String, element: ExchangeElement, contest: ContestDefinition,
                                      side: String, bundle: Bundle) -> Result<[String], Failure> {
        let workable = contest.workableSides(for: side)
        // Every set resolved once for this field (`ResolvedSets`).
        let resolved = resolvedSets(for: element, contest: contest, side: side, bundle: bundle)
        let hint = acceptedHint(for: resolved.entries)
        let tokens = ExchangeParser.tokenize(text)
        guard !tokens.isEmpty else { return .failure(.empty(hint: hint)) }
        // Sets a side may send several of at once (a county line), and how
        // many. A multi spec that names its own sets means those and no others
        // — the side that sends counties *and* states repeats only counties.
        var multiSets = Set<String>()
        for s in workable {
            if let spec = element.sentBy[s], let multi = spec.multi {
                multiSets.formUnion(multi.sets ?? spec.sets ?? [])
            }
        }
        let maxValues = element.maxValues(for: workable)
        let multiTerm = resolved.entries.first { multiSets.contains($0.id) }?.set?.termPlural ?? "values"

        // The value is the token **as sent**, never the set's canonical form:
        // an alias is resolved where it is counted, not where it is received.
        // `ExchangeParser` returns the typed token for every accepted spelling
        // — `DC` stays `DC` in the 14 parties that credit it as Maryland — and
        // `ScoreEngine` maps it at count time (`party.stateAliases[theirLoc]`),
        // which is what keeps the log a record of what the station sent. The
        // lowered model does the same through this set's `aliases`, read by
        // the multiplier's `receivedToken` resolver.
        func classify(_ token: String) -> (set: String, value: String)? {
            owningSet(of: token, in: resolved).map { ($0, token) }
        }

        var classified: [(set: String, value: String)] = []
        for token in tokens {
            guard let hit = classify(token) else {
                return .failure(.invalid(token, suggestions: suggestions(for: token, inSetOrder: resolved.entries), hint: hint))
            }
            classified.append(hit)
        }
        // `ExchangeParser` counts the tokens **as typed**, before it dedupes:
        // `TX/TX` is two out-of-state tokens and so a mix, while `LIN/LIN` is
        // one county typed twice. So the "several values means one multi-set"
        // rule is checked on the raw count; the dedupe follows it, and only
        // the county-line cap sees the deduped list.
        if classified.count > 1 {
            guard classified.allSatisfy({ multiSets.contains($0.set) }) else { return .failure(.mixed(hint: hint)) }
        }
        var seen = Set<String>()
        let unique = classified.filter { seen.insert($0.value).inserted }
        guard unique.count <= maxValues else {
            return .failure(.tooMany(unique.count, max: maxValues, term: multiTerm))
        }
        return .success(unique.map(\.value))
    }

    /// What the element accepts, in its sets' own words and their own order —
    /// "county, state, province, or DX". The dynamic prefix set has no
    /// `TokenSet` to ask, so it names itself; a term repeated by two sets
    /// (a party that takes both `DX` and its own DX aliases) is said once.
    private static func acceptedHint(for sets: [(id: String, set: TokenSet?)]) -> String {
        var seen = Set<String>(), terms: [String] = []
        for entry in sets {
            let term = entry.set?.term ?? (entry.id == "dxccPrefix" ? "DXCC prefix" : entry.id)
            if seen.insert(term).inserted { terms.append(term) }
        }
        switch terms.count {
        case 0: return "value"
        case 1: return terms[0]
        case 2: return "\(terms[0]) or \(terms[1])"
        default: return terms.dropLast().joined(separator: ", ") + ", or " + terms[terms.count - 1]
        }
    }

    /// The party rule: a DXCC prefix the ARRL list carries that is not also
    /// one of this element's own tokens, a state, a province or `DX`.
    static func isDXPrefix(_ token: String, excluding accepted: Set<String>) -> Bool {
        guard !accepted.contains(token), !MultClass.acceptedStateTokens.contains(token),
              !MultClass.canadianProvinces.contains(token), token != MultClass.dxToken else { return false }
        return DXCCTable.shared.isKnownPrefix(token)
    }

    /// Prefix matches then Damerau-1 candidates, capped at 3 — the order
    /// `ExchangeParser.suggestions` had, which is the element's own set order:
    /// a county outranks a state because the element sends counties first.
    /// Within a set the tokens are sorted, so the list is stable.
    static func suggestions(for token: String, inSetOrder sets: [(id: String, set: TokenSet?)]) -> [String] {
        var seen = Set<String>(), all: [String] = []
        for entry in sets {
            for a in (entry.set?.acceptedTokens ?? []).sorted() where seen.insert(a).inserted { all.append(a) }
        }
        var out: [String] = []
        for a in all where a.hasPrefix(token) && a != token { out.append(a) }
        for a in all where !out.contains(a) && ExchangeParser.isEditDistanceOne(token, a) { out.append(a) }
        return Array(out.prefix(3))
    }
}

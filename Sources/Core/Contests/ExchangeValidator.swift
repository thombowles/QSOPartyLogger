import Foundation

/// Validates one received exchange element for an entrant on `side`, per its
/// kind. Token kinds keep `ExchangeParser`'s tokeniser, suggestions and
/// edit-distance help; the parity test pins them equal on every party.
enum ExchangeValidator {
    enum Failure: Error, Equatable, LocalizedError {
        case empty
        case invalid(String, suggestions: [String])
        case tooMany(Int, max: Int)
        case mixed
        case badFormat(String)

        var errorDescription: String? {
            switch self {
            case .empty: "Enter the exchange."
            case .invalid(let t, let s):
                s.isEmpty ? "'\(t)' is not valid." : "'\(t)' is not valid. Did you mean \(s.joined(separator: ", "))?"
            case .tooMany(let n, let max): "\(n) values given — at most \(max) allowed."
            case .mixed: "Mixing counties with states/provinces isn't valid."
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
            let cut = text.replacingOccurrences(of: "N", with: "9")
            return cut.count >= 2 && cut.count <= 3 && cut.allSatisfy(\.isNumber) ? .success([cut]) : .failure(.badFormat("A signal report is 2 or 3 digits."))
        case .serial:
            guard !text.isEmpty, text.count <= 5, text.allSatisfy(\.isNumber), let n = Int(text) else {
                return .failure(.badFormat("A QSO number is 1–5 digits."))
            }
            return .success([String(n)])
        case .name:
            return !text.isEmpty && text.count <= 15 && text.allSatisfy(\.isLetter) ? .success([text]) : .failure(.badFormat("A name is 1–15 letters."))
        case .cqZone, .ituZone:
            let top = element.kind == .cqZone ? 40 : 90
            guard let n = Int(text), (1...top).contains(n) else { return .failure(.badFormat("A zone is 1–\(top).")) }
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

    private static func validateToken(_ text: String, element: ExchangeElement, contest: ContestDefinition,
                                      side: String, bundle: Bundle) -> Result<[String], Failure> {
        let tokens = ExchangeParser.tokenize(text)
        guard !tokens.isEmpty else { return .failure(.empty) }
        let workable = contest.workableSides(for: side)
        let sets = element.setsSent(by: workable)
        // Sets a side may send several of at once (a county line), and how many.
        var multiSets = Set<String>()
        for s in workable {
            if let spec = element.sentBy[s], spec.multi != nil { multiSets.formUnion(spec.sets ?? []) }
        }
        let maxValues = element.maxValues(for: workable)
        // Everything the element accepts, for the dynamic prefix set's exclusions and for suggestions.
        let enumerated = sets.compactMap { contest.tokenSet(id: $0, bundle: bundle) }
        let allAccepted = enumerated.reduce(into: Set<String>()) { $0.formUnion($1.acceptedTokens) }

        // The value is the token **as sent**, never the set's canonical form:
        // an alias is resolved where it is counted, not where it is received.
        // `ExchangeParser` returns the typed token for every accepted spelling
        // — `DC` stays `DC` in the 14 parties that credit it as Maryland — and
        // `ScoreEngine` maps it at count time (`party.stateAliases[theirLoc]`),
        // which is what keeps the log a record of what the station sent. The
        // lowered model does the same through this set's `aliases`, read by
        // the multiplier's `receivedToken` resolver.
        func classify(_ token: String) -> (set: String, value: String)? {
            for id in sets {
                if id == "dxccPrefix" {
                    if isDXPrefix(token, excluding: allAccepted) { return (id, token) }
                } else if let set = contest.tokenSet(id: id, bundle: bundle), set.accepts(token) {
                    return (id, token)
                }
            }
            return nil
        }

        var classified: [(set: String, value: String)] = []
        for token in tokens {
            guard let hit = classify(token) else {
                return .failure(.invalid(token, suggestions: suggestions(for: token, among: allAccepted)))
            }
            classified.append(hit)
        }
        var seen = Set<String>()
        let unique = classified.filter { seen.insert($0.value).inserted }
        if unique.count > 1 {
            guard unique.allSatisfy({ multiSets.contains($0.set) }) else { return .failure(.mixed) }
            guard unique.count <= maxValues else { return .failure(.tooMany(unique.count, max: maxValues)) }
        }
        return .success(unique.map(\.value))
    }

    /// The party rule: a DXCC prefix the ARRL list carries that is not also
    /// one of this element's own tokens, a state, a province or `DX`.
    static func isDXPrefix(_ token: String, excluding accepted: Set<String>) -> Bool {
        guard !accepted.contains(token), !MultClass.acceptedStateTokens.contains(token),
              !MultClass.canadianProvinces.contains(token), token != MultClass.dxToken else { return false }
        return DXCCTable.shared.isKnownPrefix(token)
    }

    /// Prefix matches then Damerau-1 candidates, capped at 3 — `ExchangeParser.suggestions` verbatim.
    static func suggestions(for token: String, among accepted: Set<String>) -> [String] {
        let all = accepted.sorted()
        var out: [String] = []
        for a in all where a.hasPrefix(token) && a != token { out.append(a) }
        for a in all where !out.contains(a) && ExchangeParser.isEditDistanceOne(token, a) { out.append(a) }
        return Array(out.prefix(3))
    }
}

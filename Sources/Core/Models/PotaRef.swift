import Foundation

/// Parks on the Air reference grammar.
///
/// ADIF 3.1.4's POTARef data type (adif.org/314/ADIF_314.htm, fetched
/// 2026-08-05): "a sequence of case-insensitive Characters representing a
/// Parks on the Air park reference in the form xxxx-nnnnn[@yyyyyy]" —
/// program 1–4 characters, park number 4–5 digits, optional ISO 3166-2
/// code of 4–6 characters for a park spanning subdivisions (K-4562@US-CA).
/// Quotes banked in docs/research/pota/SOURCES.md.
///
/// Hand-checked rather than matched against a pattern, like
/// `MemberExchange.parse`: the grammar is three bounded pieces, and each
/// piece's rule reads here as the specification words it.
enum PotaRef {

    struct Failure: Error, Equatable {
        var message: String
    }

    /// One reference: trimmed, uppercased, grammar-checked. `nil` when the
    /// token is not a POTA reference.
    static func normalize(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !token.isEmpty else { return nil }

        // The optional "@" subdivision comes off first, so the park part is
        // whatever precedes it. Empty pieces are kept, so "US-3315@" and
        // "@US-CA" fail on their own length rules rather than vanishing.
        let pieces = token.split(separator: "@", omittingEmptySubsequences: false)
        guard pieces.count <= 2 else { return nil }
        if pieces.count == 2 {
            let subdivision = pieces[1]
            guard (4...6).contains(subdivision.count),
                  subdivision.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
            else { return nil }
        }

        let park = pieces[0].split(separator: "-", omittingEmptySubsequences: false)
        guard park.count == 2 else { return nil }
        let program = park[0], number = park[1]
        guard (1...4).contains(program.count),
              program.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              (4...5).contains(number.count),
              number.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }

        return token
    }

    /// A comma-separated list in the operator's order, exact duplicates
    /// dropped. Empty input is a valid empty list — no parks is a state,
    /// not an error. A bad token names itself, in the same inline voice as
    /// the rest of the app's validation.
    static func parseList(_ raw: String) -> Result<[String], Failure> {
        var refs: [String] = []
        for piece in raw.split(separator: ",") {
            let shown = piece.trimmingCharacters(in: .whitespaces)
            guard !shown.isEmpty else { continue }
            guard let ref = normalize(shown) else {
                return .failure(Failure(
                    message: "'\(shown)' is not a POTA reference — they look "
                        + "like US-3315 or K-4562@US-CA."))
            }
            if !refs.contains(ref) { refs.append(ref) }
        }
        return .success(refs)
    }
}

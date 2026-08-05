import Foundation

/// The QRP-sprint exchange element: a club membership number for members, an
/// output power for everyone else — "RST, S/P/C, Skeeter number" versus
/// "RST, S/P/C, Output power (For example - 559 NY 5W)" in the NJQRP Skeeter
/// Hunt's words. The element decides the QSO's points, which is what makes it
/// an engine shape rather than a note: the Skeeter Hunt pays 3 for a member,
/// 2 for a non-member running QRP, 1 for anyone else, regardless of mode.
///
/// The shape is the standard QRP-club sprint exchange (ARCI, SKCC and NAQCC
/// events all use it), so the type is named for what it carries, not for one
/// sponsor's mascot. Every field is required — one bundled party carries this
/// today, and a default would be that sponsor's rule silently applied to the
/// next (the `ActivatedCountyMultiplier` lesson).
struct MemberExchange: Codable, Equatable, Sendable {
    /// Display-ready name of the member element, verbatim from the party
    /// ("Skeeter number"). Unlike `countyTerm` this is not case-normalized:
    /// the term is usually a proper noun.
    let term: String
    /// Short form for field labels and columns ("Skeeter #").
    let shortTerm: String
    /// Points for a contact whose received element is a member number.
    let memberPoints: Int
    /// Points for a non-member whose received power is QRP for the mode.
    let qrpPoints: Int
    /// Points for everyone else.
    let otherPoints: Int
    /// The QRP ceiling per mode class, in watts, inclusive — the Skeeter
    /// Hunt's own power rule is "5W max CW, 10 Watts max SSB". Watts are
    /// compared, never summed, so `Double` is safe here.
    let qrpMaxWatts: QRPMaxWatts

    struct QRPMaxWatts: Codable, Equatable, Sendable {
        let phone: Double
        let cw: Double
        let digital: Double

        func limit(for modeClass: ModeClass) -> Double {
            switch modeClass {
            case .phone: phone
            case .cw: cw
            case .digital: digital
            }
        }
    }

    /// A parsed received (or sent) element.
    enum Value: Equatable, Sendable {
        /// Digits only — a member number, kept verbatim ("013" stays "013").
        case member(number: String)
        /// A power with its unit ("5W", "500MW", "2.5W", "1KW"), in watts.
        case power(watts: Double)
    }

    /// Digits alone are a member number; a power **requires its unit** (W, MW
    /// or KW, case-insensitive) precisely so the two shapes cannot collide —
    /// "5" is member number 5, "5W" is five watts. Anything else is invalid
    /// and the entry field must not log it.
    static func parse(_ raw: String) -> Value? {
        let token = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !token.isEmpty else { return nil }
        if token.allSatisfy(\.isWholeNumber) {
            return .member(number: token)
        }
        let scales: [(suffix: String, watts: Double)] = [
            ("MW", 0.001), ("KW", 1000), ("W", 1),
        ]
        for (suffix, scale) in scales where token.hasSuffix(suffix) {
            let number = String(token.dropLast(suffix.count))
            guard !number.isEmpty,
                  number.allSatisfy({ $0.isWholeNumber || $0 == "." }),
                  number.filter({ $0 == "." }).count <= 1,
                  let value = Double(number)
            else { return nil }
            return .power(watts: value * scale)
        }
        return nil
    }

    /// The points a valid contact earns from its received element, or `nil`
    /// where the element is missing or unreadable — the caller falls back to
    /// the party's ordinary points table rather than guessing.
    func points(forReceived raw: String?, modeClass: ModeClass) -> Int? {
        guard let raw, let value = Self.parse(raw) else { return nil }
        switch value {
        case .member:
            return memberPoints
        case .power(let watts):
            return watts <= qrpMaxWatts.limit(for: modeClass) ? qrpPoints : otherPoints
        }
    }
}

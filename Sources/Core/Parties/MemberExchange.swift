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
    /// What a *member* is called, plural, for counting them ("Skeeters").
    /// Deliberately not `shortTerm`: the score sidebar counts stations, and
    /// a row labelled "Skeeter #" beside a count reads as somebody's number.
    let memberPlural: String
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
    ///
    /// Whitespace is removed rather than merely trimmed, so "5 W" — which is
    /// how an operator with one hand on a paddle actually types it — reads as
    /// five watts instead of failing.
    static func parse(_ raw: String) -> Value? {
        let token = raw.uppercased().filter { !$0.isWhitespace }
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

    /// One of the sponsor's three station classes, from the received element.
    enum WorkedClass: Equatable, Sendable {
        case member
        case qrp
        case other
    }

    /// Which class a received element puts the worked station in.
    ///
    /// **A blank element is `other`, not a gap to be guessed at.** Plenty of
    /// stations answer a sprint without being in it — a POTA activator who
    /// sends a report and their state and nothing more — and the sponsor's
    /// own third scoring line is "Working any other QRO station - 1 point".
    /// Claiming QRP for a station that never told you its power would
    /// overstate the score, so an absent element takes the lowest rate, which
    /// is also the only rate the rules allow for a station of unknown power.
    func workedClass(forReceived raw: String?, modeClass: ModeClass) -> WorkedClass {
        guard let raw, let value = Self.parse(raw) else { return .other }
        switch value {
        case .member:
            return .member
        case .power(let watts):
            return watts <= qrpMaxWatts.limit(for: modeClass) ? .qrp : .other
        }
    }

    /// The points a valid contact earns from its received element.
    func points(forReceived raw: String?, modeClass: ModeClass) -> Int {
        switch workedClass(forReceived: raw, modeClass: modeClass) {
        case .member: memberPoints
        case .qrp: qrpPoints
        case .other: otherPoints
        }
    }
}

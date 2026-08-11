import Foundation

/// Multiplier classes a party can count.
enum MultClass: String, Codable, CaseIterable, Sendable {
    case county
    case state
    case province
    case dx
    /// ARRL/RAC section, for the parties whose exchange carries one instead of a
    /// state or province. PAQP: "Sequential serial number plus PA county, ARRL
    /// section, Canadian section, or 'DX'" — so `NTX` is a valid token there and
    /// `TX` is not. A party supplies its own accepted list via
    /// `PartyDefinition.sections`, which then supplants the state and province
    /// token sets entirely.
    case section
    /// The worked station itself, in a member-exchange party whose received
    /// member number is the multiplier. FOBB counts each Bumblebee worked,
    /// again on each band: "Working the same Bumblebee on a different band
    /// counts as an additional Contact and as an additional Bumblebee
    /// Worked." The key's value is the raw logged callsign, and the class
    /// only fires where the party lists it, so every party without it is
    /// untouched.
    case member

    /// 50 US states. DC is additionally accepted as a loggable token (see
    /// `acceptedStateTokens`) and counted with `.state` — sponsors' checkers accept it.
    static let usStates: Set<String> = [
        "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA",
        "HI", "ID", "IL", "IN", "IA", "KS", "KY", "LA", "ME", "MD",
        "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ",
        "NM", "NY", "NC", "ND", "OH", "OK", "OR", "PA", "RI", "SC",
        "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY",
    ]

    static let acceptedStateTokens: Set<String> = usStates.union(["DC"])

    /// 13 Canadian provinces/territories per KSQP rules.
    static let canadianProvinces: Set<String> = [
        "AB", "BC", "MB", "NB", "NL", "NT", "NS", "NU", "ON", "PE", "QC", "SK", "YT",
    ]

    static let dxToken = "DX"
}

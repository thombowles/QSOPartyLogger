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

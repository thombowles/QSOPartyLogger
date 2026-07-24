import Foundation

/// A QSO party's complete rule set, loaded from JSON (bundled or user-installed).
/// Adding a party requires no code — drop a JSON file in
/// `~/Library/Application Support/QSOPartyLogger/Parties/`.
struct PartyDefinition: Codable, Identifiable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let cabrilloContest: String
    /// Two-letter state whose counties define the party (e.g. "KS").
    let homeState: String
    let countyAbbrLength: Int
    let validBands: [Band]
    let points: PointsTable
    let dupeScope: DupeScope
    let multipliers: MultRules
    let bonuses: [BonusRule]
    let oneByOne: OneByOneConfig?
    let counties: [County]
    let notes: String?

    struct PointsTable: Codable, Equatable, Sendable {
        let phone: Int
        let cw: Int
        let digital: Int

        func points(for modeClass: ModeClass) -> Int {
            switch modeClass {
            case .phone: phone
            case .cw: cw
            case .digital: digital
            }
        }
    }

    enum DupeScope: String, Codable, Sendable {
        /// Workable once per band × mode-class (KSQP, TQP).
        case bandMode
    }

    struct MultRules: Codable, Equatable, Sendable {
        let inState: MultRule
        let outState: MultRule
    }

    struct MultRule: Codable, Equatable, Sendable {
        let classes: [MultClass]
        /// KSQP: "The first Kansas county logged counts as the Kansas multiplier."
        let homeStateCountsViaCounty: Bool
        let countScope: CountScope
    }

    enum CountScope: String, Codable, Sendable {
        /// Each multiplier counts once for the whole log (KSQP, TQP).
        case once
    }

    struct OneByOneConfig: Codable, Equatable, Sendable {
        let words: [String]
        let wildcard: String?
    }

    // MARK: Lookup

    var countiesByAbbr: [String: County] {
        Dictionary(uniqueKeysWithValues: counties.map { ($0.abbr, $0) })
    }

    func county(for abbr: String) -> County? {
        countiesByAbbr[abbr.uppercased()]
    }

    /// Valid non-county location tokens (received from out-of-state stations, or used
    /// as my own location when operating from outside the party state). The home
    /// state itself is never valid — its stations always send a county.
    var validOutStateTokens: Set<String> {
        MultClass.acceptedStateTokens
            .subtracting([homeState])
            .union(MultClass.canadianProvinces)
            .union([MultClass.dxToken])
    }

    /// Basic structural validation for user-supplied files.
    func validate() throws {
        var seen = Set<String>()
        for c in counties {
            guard c.abbr == c.abbr.uppercased(), !c.abbr.isEmpty else {
                throw PartyValidationError.badAbbreviation(c.abbr)
            }
            guard seen.insert(c.abbr).inserted else {
                throw PartyValidationError.duplicateAbbreviation(c.abbr)
            }
        }
        guard !counties.isEmpty else { throw PartyValidationError.noCounties }
        guard homeState.count == 2 else { throw PartyValidationError.badHomeState(homeState) }
    }
}

enum PartyValidationError: Error, Equatable, LocalizedError {
    case badAbbreviation(String)
    case duplicateAbbreviation(String)
    case noCounties
    case badHomeState(String)

    var errorDescription: String? {
        switch self {
        case .badAbbreviation(let a): "County abbreviation '\(a)' must be non-empty uppercase."
        case .duplicateAbbreviation(let a): "County abbreviation '\(a)' appears more than once."
        case .noCounties: "Party has no counties."
        case .badHomeState(let s): "homeState '\(s)' must be a 2-letter state code."
        }
    }
}

/// Bonus scoring strategies. JSON uses a `type` discriminator so new strategies
/// can be added as cases without breaking existing files.
enum BonusRule: Codable, Equatable, Sendable {
    /// Flat one-time bonus for working a specific station (KSQP: KS0KS +100).
    case workStation(call: String, points: Int)
    /// TQP-style: +points for each `per` distinct counties a mobile is worked in.
    case mobileCountyCount(per: Int, points: Int)

    private enum CodingKeys: String, CodingKey { case type, call, points, per }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "workStation":
            self = .workStation(
                call: try c.decode(String.self, forKey: .call),
                points: try c.decode(Int.self, forKey: .points)
            )
        case "mobileCountyCount":
            self = .mobileCountyCount(
                per: try c.decode(Int.self, forKey: .per),
                points: try c.decode(Int.self, forKey: .points)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c,
                debugDescription: "Unknown bonus rule type '\(type)'"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .workStation(let call, let points):
            try c.encode("workStation", forKey: .type)
            try c.encode(call, forKey: .call)
            try c.encode(points, forKey: .points)
        case .mobileCountyCount(let per, let points):
            try c.encode("mobileCountyCount", forKey: .type)
            try c.encode(per, forKey: .per)
            try c.encode(points, forKey: .points)
        }
    }
}

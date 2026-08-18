import Foundation

/// Cabrillo header data plus category selections.
struct StationProfile: Codable, Equatable, Hashable, Sendable {
    var callsign: String = ""
    var name: String = ""
    var email: String = ""
    var address: String = ""
    var city: String = ""
    var stateProvince: String = ""
    var postalCode: String = ""
    var country: String = "USA"
    var club: String = ""
    /// Space-separated operator calls for multi-op; empty = just `callsign`.
    var operators: String = ""
    var categoryOperator: CategoryOperator = .singleOp
    var categoryAssisted: CategoryAssisted = .nonAssisted
    var categoryPower: CategoryPower = .low
    var categoryStation: CategoryStation = .fixed
    var categoryTransmitter: CategoryTransmitter = .one
    /// Maidenhead grid square (Cabrillo `GRID-LOCATOR:`), e.g. EM13LE. Optional.
    var gridLocator: String = ""
    /// Cabrillo `CATEGORY-BAND:` where a contest admits single-band entries
    /// (`Categories.band`); nil = `ALL`, which is what every party writes.
    var categoryBand: String? = nil
    /// Cabrillo `CATEGORY-OVERLAY:` (CQ WW CLASSIC/ROOKIE/YOUTH, WPX TB-WIRES…);
    /// nil = no overlay line. Nothing bundled sets it yet.
    var categoryOverlay: String? = nil
    /// Cabrillo `CATEGORY-TIME:`; nil = no line. Nothing bundled sets it yet.
    var categoryTime: String? = nil
    /// The entrant's own fixed exchange values remembered across contests —
    /// `section`, `zone`, `check`, `state`, `name`, `power`, `grid`… keyed by
    /// exchange element id (spec §1.5). Setup seeds a contest's sent elements
    /// from here; the Cabrillo `LOCATION:` header falls back to `state` /
    /// `section` when a contest has no location element.
    var exchangeDefaults: [String: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case callsign, name, email, address, city, stateProvince, postalCode
        case country, club, operators
        case categoryOperator, categoryAssisted, categoryPower, categoryStation, categoryTransmitter
        case gridLocator, categoryBand, categoryOverlay, categoryTime, exchangeDefaults
    }

    enum CategoryOperator: String, Codable, CaseIterable, Sendable {
        case singleOp = "SINGLE-OP"
        case multiOp = "MULTI-OP"
        case checklog = "CHECKLOG"
    }

    /// Absent from stored profiles means unassisted — the claim is opt-in,
    /// and sponsors read logs without the header the same way (NAQP rule 5A
    /// vs 5B is exactly this distinction).
    enum CategoryAssisted: String, Codable, CaseIterable, Sendable {
        case nonAssisted = "NON-ASSISTED"
        case assisted = "ASSISTED"
    }

    enum CategoryPower: String, Codable, CaseIterable, Sendable {
        case high = "HIGH"
        case low = "LOW"
        case qrp = "QRP"
    }

    enum CategoryStation: String, Codable, CaseIterable, Sendable {
        case fixed = "FIXED"
        case mobile = "MOBILE"
        case portable = "PORTABLE"
        case rover = "ROVER"
        case expedition = "EXPEDITION"
        case school = "SCHOOL"
    }

    enum CategoryTransmitter: String, Codable, CaseIterable, Sendable {
        case one = "ONE"
        case two = "TWO"
        case limited = "LIMITED"
        case unlimited = "UNLIMITED"
    }
}

extension StationProfile {
    /// Trims every text field and folds all but one to upper case.
    ///
    /// Contest Setup's fields fold as they are typed, so the row shows what
    /// will actually be logged. This is the guarantee behind that display: a
    /// profile loaded from a log written before the fields folded, or pasted in
    /// whole, is normalised on save rather than reaching a Cabrillo header in
    /// whatever case it happened to arrive in.
    ///
    /// **Email is trimmed but never folded.** It is the one header a sponsor
    /// may machine-read back to the entrant, and RFC 5321 leaves the local part
    /// case-sensitive even though most hosts ignore that — rewriting somebody's
    /// address is not a normalisation the app has any business making.
    func normalized() -> StationProfile {
        var copy = self
        copy.callsign = Self.folded(callsign)
        copy.name = Self.folded(name)
        copy.email = email.trimmingCharacters(in: .whitespaces)
        copy.address = Self.folded(address)
        copy.city = Self.folded(city)
        copy.stateProvince = Self.folded(stateProvince)
        copy.postalCode = Self.folded(postalCode)
        copy.country = Self.folded(country)
        copy.club = Self.folded(club)
        copy.operators = Self.folded(operators)
        copy.gridLocator = Self.folded(gridLocator)
        copy.categoryBand = categoryBand.map(Self.folded).flatMap { $0.isEmpty ? nil : $0 }
        copy.categoryOverlay = categoryOverlay.map(Self.folded).flatMap { $0.isEmpty ? nil : $0 }
        copy.categoryTime = categoryTime.map(Self.folded).flatMap { $0.isEmpty ? nil : $0 }
        copy.exchangeDefaults = exchangeDefaults.mapValues(Self.folded).filter { !$0.value.isEmpty }
        return copy
    }

    private static func folded(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// Profiles are persisted in three places written across app versions —
    /// `.qplog` documents, the `lastStationProfile` preference, and the
    /// contest archive — so every field decodes with `decodeIfPresent` plus
    /// its default. A profile saved before a field existed must never fail
    /// the document that carries it. Encoding is custom: every long-standing
    /// key is always written, the four additions only when set — see
    /// `encode(to:)`. This initializer lives in an extension so the
    /// memberwise initializer survives.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        callsign = try c.decodeIfPresent(String.self, forKey: .callsign) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        stateProvince = try c.decodeIfPresent(String.self, forKey: .stateProvince) ?? ""
        postalCode = try c.decodeIfPresent(String.self, forKey: .postalCode) ?? ""
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? "USA"
        club = try c.decodeIfPresent(String.self, forKey: .club) ?? ""
        operators = try c.decodeIfPresent(String.self, forKey: .operators) ?? ""
        categoryOperator = try c.decodeIfPresent(CategoryOperator.self, forKey: .categoryOperator) ?? .singleOp
        categoryAssisted = try c.decodeIfPresent(CategoryAssisted.self, forKey: .categoryAssisted) ?? .nonAssisted
        categoryPower = try c.decodeIfPresent(CategoryPower.self, forKey: .categoryPower) ?? .low
        categoryStation = try c.decodeIfPresent(CategoryStation.self, forKey: .categoryStation) ?? .fixed
        categoryTransmitter = try c.decodeIfPresent(CategoryTransmitter.self, forKey: .categoryTransmitter) ?? .one
        gridLocator = try c.decodeIfPresent(String.self, forKey: .gridLocator) ?? ""
        categoryBand = try c.decodeIfPresent(String.self, forKey: .categoryBand)
        categoryOverlay = try c.decodeIfPresent(String.self, forKey: .categoryOverlay)
        categoryTime = try c.decodeIfPresent(String.self, forKey: .categoryTime)
        exchangeDefaults = try c.decodeIfPresent([String: String].self, forKey: .exchangeDefaults) ?? [:]
    }

    /// Every long-standing key is always written (as the synthesized encoder
    /// did); the four additions only when set, so a profile that never used
    /// them encodes byte-for-byte as before.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(callsign, forKey: .callsign)
        try c.encode(name, forKey: .name)
        try c.encode(email, forKey: .email)
        try c.encode(address, forKey: .address)
        try c.encode(city, forKey: .city)
        try c.encode(stateProvince, forKey: .stateProvince)
        try c.encode(postalCode, forKey: .postalCode)
        try c.encode(country, forKey: .country)
        try c.encode(club, forKey: .club)
        try c.encode(operators, forKey: .operators)
        try c.encode(categoryOperator, forKey: .categoryOperator)
        try c.encode(categoryAssisted, forKey: .categoryAssisted)
        try c.encode(categoryPower, forKey: .categoryPower)
        try c.encode(categoryStation, forKey: .categoryStation)
        try c.encode(categoryTransmitter, forKey: .categoryTransmitter)
        try c.encode(gridLocator, forKey: .gridLocator)
        try c.encodeIfPresent(categoryBand, forKey: .categoryBand)
        try c.encodeIfPresent(categoryOverlay, forKey: .categoryOverlay)
        try c.encodeIfPresent(categoryTime, forKey: .categoryTime)
        if !exchangeDefaults.isEmpty { try c.encode(exchangeDefaults, forKey: .exchangeDefaults) }
    }
}

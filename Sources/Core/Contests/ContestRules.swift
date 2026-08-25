import Foundation

enum ContestFamily: String, Codable, CaseIterable, Sendable {
    case stateQSOParty, dx, domestic, fieldDay, sprint, qrp, vhf
}

/// When a second contact with the same station is a dupe.
struct DupeRule: Codable, Equatable, Sendable {
    enum Scope: String, Codable, Sendable { case contest, band, bandMode }
    let scope: Scope
    /// A station worked from (or in) a different location is a new contact —
    /// a mobile changing county. Every party; no DX contest.
    let locationSensitive: Bool
    /// The UTC day joins the key: a station worked yesterday is new today.
    /// POTA (spec 2026-08-25 decision 9); no party sets it.
    let utcDay: Bool
    /// The own-park set joins the key: a rove to a new park resets dupes,
    /// POTA's per-activation scoring. No party sets it.
    let perMyPark: Bool

    init(scope: Scope, locationSensitive: Bool = false,
         utcDay: Bool = false, perMyPark: Bool = false) {
        self.scope = scope
        self.locationSensitive = locationSensitive
        self.utcDay = utcDay
        self.perMyPark = perMyPark
    }

    private enum CodingKeys: String, CodingKey {
        case scope, locationSensitive, utcDay, perMyPark
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(scope: try c.decode(Scope.self, forKey: .scope),
                  locationSensitive: try c.decodeIfPresent(Bool.self, forKey: .locationSensitive) ?? false,
                  utcDay: try c.decodeIfPresent(Bool.self, forKey: .utcDay) ?? false,
                  perMyPark: try c.decodeIfPresent(Bool.self, forKey: .perMyPark) ?? false)
    }

    /// Today's `DupeChecker` key: band × mode class + both locations.
    static let partyDefault = DupeRule(scope: .bandMode, locationSensitive: true)
}

/// A maximum-operating-time rule (SS 24 of 30 h; WPX single-op 36 of 48 h).
struct OperatingTimeRule: Codable, Equatable, Sendable {
    let maxMinutes: Int
    let minOffMinutes: Int
    /// Category axis → value the rule applies to; nil = every entrant.
    let appliesTo: [String: String]?

    init(maxMinutes: Int, minOffMinutes: Int, appliesTo: [String: String]? = nil) {
        self.maxMinutes = maxMinutes
        self.minOffMinutes = minOffMinutes
        self.appliesTo = appliesTo
    }

    func applies(to category: [String: String]) -> Bool {
        (appliesTo ?? [:]).allSatisfy { category[$0.key] == $0.value }
    }
}

/// The Cabrillo category values a contest admits per axis; nil = the full enum.
struct Categories: Codable, Equatable, Sendable {
    let `operator`: [String]?
    let assisted: [String]?
    let power: [String]?
    let band: [String]?
    let mode: [String]?
    let transmitter: [String]?
    let station: [String]?
    let overlay: [String]?
    let time: [String]?

    init(operator: [String]? = nil, assisted: [String]? = nil, power: [String]? = nil, band: [String]? = nil,
         mode: [String]? = nil, transmitter: [String]? = nil, station: [String]? = nil,
         overlay: [String]? = nil, time: [String]? = nil) {
        self.operator = `operator`
        self.assisted = assisted
        self.power = power
        self.band = band
        self.mode = mode
        self.transmitter = transmitter
        self.station = station
        self.overlay = overlay
        self.time = time
    }

    static let all = Categories()

    var allowedOperators: [String] { `operator` ?? StationProfile.CategoryOperator.allCases.map(\.rawValue) }
    var allowedAssisted: [String] { assisted ?? StationProfile.CategoryAssisted.allCases.map(\.rawValue) }
    var allowedPowers: [String] { power ?? StationProfile.CategoryPower.allCases.map(\.rawValue) }
    var allowedStations: [String] { station ?? StationProfile.CategoryStation.allCases.map(\.rawValue) }
    var allowedTransmitters: [String] { transmitter ?? StationProfile.CategoryTransmitter.allCases.map(\.rawValue) }
    /// Every band the WWROF header spec lists is not useful here; a contest
    /// that admits single-band entries lists them, others get `ALL`.
    var allowedBands: [String] { band ?? ["ALL"] }
    var allowedOverlays: [String] { overlay ?? [] }
    var allowedTimes: [String] { time ?? [] }
}

/// The Cabrillo header and QSO-line shape: the `CONTEST:` name, where the
/// `LOCATION:` token comes from, whether the QSO line carries a transmitter
/// column, how serials run, and a pinned `CATEGORY-MODE:`.
struct CabrilloSpec: Codable, Equatable, Sendable {
    enum Location: String, Codable, Sendable { case state, section, entrantToken }
    enum SerialSequence: String, Codable, Sendable { case contest, perBand }

    let contest: String
    let location: Location
    let transmitterColumn: Bool
    let serialSequence: SerialSequence
    /// Pins `CATEGORY-MODE:` (Field Day: MIXED); nil = derived from the rows.
    let categoryMode: String?
    /// The `LOCATION:` token for an entrant on the first-listed side, where a
    /// contest names one for everybody inside (a party's primary state —
    /// `MyLocation.entrantToken` today). Nil: use the entrant's own sent
    /// location, resolved to its group/state.
    let homeLocation: String?
    /// Write a report column in the QSO line even where the exchange declares
    /// no `rst`, `serial` or `name` element — the generic Cabrillo template's
    /// slot, filled with the row's report or the mode's default (599 / 59).
    /// `PartyLowering` sets it for the four parties whose exchange has none of
    /// the three (MDC, IDQP, NCQP, WIQP), which is what their logs have always
    /// carried; Field Day (class + section) leaves it false. Default false.
    let reportColumn: Bool

    init(contest: String, location: Location, transmitterColumn: Bool = false,
         serialSequence: SerialSequence = .contest, categoryMode: String? = nil,
         homeLocation: String? = nil, reportColumn: Bool = false) {
        self.contest = contest
        self.location = location
        self.transmitterColumn = transmitterColumn
        self.serialSequence = serialSequence
        self.categoryMode = categoryMode
        self.homeLocation = homeLocation
        self.reportColumn = reportColumn
    }

    private enum CodingKeys: String, CodingKey {
        case contest, location, transmitterColumn, serialSequence, categoryMode, homeLocation, reportColumn
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(contest: try c.decode(String.self, forKey: .contest),
                  location: try c.decode(Location.self, forKey: .location),
                  transmitterColumn: try c.decodeIfPresent(Bool.self, forKey: .transmitterColumn) ?? false,
                  serialSequence: try c.decodeIfPresent(SerialSequence.self, forKey: .serialSequence) ?? .contest,
                  categoryMode: try c.decodeIfPresent(String.self, forKey: .categoryMode),
                  homeLocation: try c.decodeIfPresent(String.self, forKey: .homeLocation),
                  reportColumn: try c.decodeIfPresent(Bool.self, forKey: .reportColumn) ?? false)
    }
}

/// Final-score factors and self-declared items: `factor(points × mults) + bonuses`.
struct ScoreFactors: Codable, Equatable, Sendable {
    struct Objective: Codable, Equatable, Sendable {
        let id: String
        let label: String
        /// Winter Field Day: the factor is 1 + the sum of the selected `om`s.
        let om: Int
    }
    struct DeclaredBonus: Codable, Equatable, Sendable {
        struct PerCount: Codable, Equatable, Sendable {
            let label: String
            let max: Int
        }
        let id: String
        let label: String
        let points: Int
        /// Field Day's "100 per transmitter, up to 20": points × count ≤ max.
        let perCount: PerCount?
    }

    let power: [String: ScoreFactor]?
    let station: [String: ScoreFactor]?
    let entryClasses: [PartyDefinition.EntryClass]
    let objectives: [Objective]
    let declaredBonuses: [DeclaredBonus]

    init(power: [String: ScoreFactor]? = nil, station: [String: ScoreFactor]? = nil,
         entryClasses: [PartyDefinition.EntryClass] = [], objectives: [Objective] = [],
         declaredBonuses: [DeclaredBonus] = []) {
        self.power = power
        self.station = station
        self.entryClasses = entryClasses
        self.objectives = objectives
        self.declaredBonuses = declaredBonuses
    }

    private enum CodingKeys: String, CodingKey { case power, station, entryClasses, objectives, declaredBonuses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(power: try c.decodeIfPresent([String: ScoreFactor].self, forKey: .power),
                  station: try c.decodeIfPresent([String: ScoreFactor].self, forKey: .station),
                  entryClasses: try c.decodeIfPresent([PartyDefinition.EntryClass].self, forKey: .entryClasses) ?? [],
                  objectives: try c.decodeIfPresent([Objective].self, forKey: .objectives) ?? [],
                  declaredBonuses: try c.decodeIfPresent([DeclaredBonus].self, forKey: .declaredBonuses) ?? [])
    }
}

/// A multiplier a side earns by operating from a token of `classID`'s roster
/// — today's `ActivatedCountyMultiplier`, generalised to any class.
struct ActivatedRule: Codable, Equatable, Sendable {
    let classID: String
    let minCount: Int
    let countUnit: PartyDefinition.ActivatedCountyMultiplier.CountUnit
    let countScope: CountScope
    let categories: [StationProfile.CategoryStation]
    let notOtherwiseWorked: Bool
}

/// Per-side multiplier arithmetic beyond the classes themselves.
struct SideRules: Codable, Equatable, Sendable {
    struct Granted: Codable, Equatable, Sendable {
        let classID: String
        let value: String
    }
    let maxScoredMultipliers: Int?
    let multiplierFloor: Int
    let granted: [Granted]
    let activated: ActivatedRule?

    init(maxScoredMultipliers: Int? = nil, multiplierFloor: Int = 0, granted: [Granted] = [], activated: ActivatedRule? = nil) {
        self.maxScoredMultipliers = maxScoredMultipliers
        self.multiplierFloor = multiplierFloor
        self.granted = granted
        self.activated = activated
    }

    private enum CodingKeys: String, CodingKey { case maxScoredMultipliers, multiplierFloor, granted, activated }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(maxScoredMultipliers: try c.decodeIfPresent(Int.self, forKey: .maxScoredMultipliers),
                  multiplierFloor: try c.decodeIfPresent(Int.self, forKey: .multiplierFloor) ?? 0,
                  granted: try c.decodeIfPresent([Granted].self, forKey: .granted) ?? [],
                  activated: try c.decodeIfPresent(ActivatedRule.self, forKey: .activated))
    }

    static let none = SideRules()
}

/// Feeds and features that ride with a contest.
struct ContestSources: Codable, Equatable, Sendable {
    let hubSpots: HubSpotSource?
    let callHistory: CallHistorySource?
    let oneByOne: PartyDefinition.OneByOneConfig?
    let combines: [String]

    init(hubSpots: HubSpotSource? = nil, callHistory: CallHistorySource? = nil,
         oneByOne: PartyDefinition.OneByOneConfig? = nil, combines: [String] = []) {
        self.hubSpots = hubSpots
        self.callHistory = callHistory
        self.oneByOne = oneByOne
        self.combines = combines
    }

    private enum CodingKeys: String, CodingKey { case hubSpots, callHistory, oneByOne, combines }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hubSpots: try c.decodeIfPresent(HubSpotSource.self, forKey: .hubSpots),
                  callHistory: try c.decodeIfPresent(CallHistorySource.self, forKey: .callHistory),
                  oneByOne: try c.decodeIfPresent(PartyDefinition.OneByOneConfig.self, forKey: .oneByOne),
                  combines: try c.decodeIfPresent([String].self, forKey: .combines) ?? [])
    }

    static let none = ContestSources()
}

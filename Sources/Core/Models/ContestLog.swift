import Foundation

/// The persisted document payload (`.qplog` = JSON of this).
///
/// **Schema 2** (spec §1.5): the entrant's side (`sideID`) and fixed sent
/// exchange (`sentExchange`) replace the party-shaped `myLocation` /
/// `exchangeName` / `exchangeMember`, which remain as computed views so the
/// party UI and every existing test read unchanged. Documents written by
/// earlier builds decode through `LegacyKeys` and migrate forward; this build
/// writes schema 2 only, so a log saved here needs this build or later
/// (Decision 10). A document from a newer schema than this build knows is
/// refused at decode, never silently rewritten down to fit.
struct ContestLog: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    /// Always `currentSchemaVersion` in memory: an older document is migrated
    /// on decode and written back in today's shape; a newer one — saved by a
    /// later build than this — is refused at decode, not rewritten down to fit.
    var schemaVersion: Int = ContestLog.currentSchemaVersion
    /// The contest id — `PartyDefinition.id` / `ContestDefinition.id`, e.g.
    /// "ksqp". The JSON key and the Swift name are the persisted contract.
    var partyID: String
    var station: StationProfile
    /// The side of the contest this entrant is on: a lowered party's `inside`
    /// or `outside`, a v2 contest's own side ids. A stored id the contest does
    /// not declare — a legacy `outside` on a single-side party — is resolved
    /// at score time by `ContestDefinition.resolvedSideID(_:)`.
    var sideID: String
    /// My fixed sent exchange, element id → values: one value per element,
    /// several for a county-line `location`. Per-row values (`rst`, `serial`)
    /// never live here. Never holds an empty value or an empty list.
    var sentExchange: [String: [String]] { didSet { sentExchange = Self.compact(sentExchange) } }
    var qsos: [QSO]
    /// Per-contest CW macros (Run + S&P sets).
    var messages: MessageSets
    /// Run vs Search & Pounce. Persisted so reopening a log mid-contest
    /// restores the mode the operator was actually in, rather than snapping
    /// back to Run.
    var operatingMode: OperatingMode
    /// Whether the operator has been through Contest Setup for this log —
    /// new documents prompt for setup immediately.
    var setupCompleted: Bool
    /// The self-declared entry class (`ScoreFactors.entryClasses`) this log
    /// claims — the Skeeter Hunt's X1–X4. Stored as the class `id`; an empty
    /// or stale id resolves to the contest's first (lowest-factor) class, so a
    /// log that never chose cannot claim a multiplier the operator did not.
    var entryClassID: String = ""
    /// Winter Field Day objectives claimed (`ScoreFactors.objectives` ids);
    /// the score factor is 1 + the sum of their `om`s. Empty everywhere else.
    var selectedObjectives: [String] = []
    /// Field Day checklist bonuses claimed, id → count (1 for a plain bonus,
    /// the transmitter count for a per-count one). Empty everywhere else.
    var declaredBonuses: [String: Int] = [:]
    /// POTA park reference(s) this contest is being operated from — the
    /// *current* Contest Setup value, normalized park references. Stamped
    /// into each row's `myPotaRefs` at logging, so a mid-contest park change
    /// affects later rows only. Empty for every log that is not an activation.
    var myPotaRefs: [String] = []
    /// Whether spotting-network information — cluster or hub — was ever
    /// delivered into this contest's session. Set once and never cleared:
    /// reception is access (NAQP rule 5A(ii)'s word), access is what the
    /// Cabrillo ASSISTED/NON-ASSISTED split turns on everywhere, and a
    /// restart mid-contest must not launder it.
    var usedSpots: Bool = false
    /// The score as computed when this log was last saved, with the rules
    /// installed then — the frozen "what I claimed" figure the Contest
    /// Dashboard shows for past seasons. Stamped by the save path
    /// (`stampingScoreSnapshot`) and read back from the *file* by the
    /// dashboard; the running document never reads it. Nil for a draft.
    var scoreSnapshot: ScoreSnapshot? = nil

    // MARK: Views over sideID / sentExchange (the party shape)

    /// The party reading of the side and sent location: `inside` with the sent
    /// counties, anything else as out-of-state with the first sent token.
    /// A view: the stored state is `sideID` + `sentExchange`.
    var myLocation: MyLocation {
        get {
            sideID == PartyLowering.insideID
                ? .inState(counties: sentExchange[ExchangeElementID.location] ?? [])
                : .outOfState(location: sentExchange[ExchangeElementID.location]?.first ?? "")
        }
        set {
            sideID = Self.sideID(for: newValue)
            sentExchange[ExchangeElementID.location] = newValue.sentExchanges
        }
    }
    /// The operator name sent in every exchange (NAQP rule 10). Empty where none.
    var exchangeName: String {
        get { sentExchange[ExchangeElementID.name]?.first ?? "" }
        set { sentExchange[ExchangeElementID.name] = [newValue] }
    }
    /// The member-number-or-power element sent in every exchange (Skeeter Hunt).
    var exchangeMember: String {
        get { sentExchange[ExchangeElementID.member]?.first ?? "" }
        set { sentExchange[ExchangeElementID.member] = [newValue] }
    }

    /// The side a party location puts an entrant on. A no-home-region party's
    /// forced out-of-state reads `outside`, which `resolvedSideID` maps to its
    /// single `all` side.
    static func sideID(for location: MyLocation) -> String {
        location.isInState ? PartyLowering.insideID : PartyLowering.outsideID
    }

    /// The assisted-category warning's one predicate: spotting information
    /// reached this log while Contest Setup claims NON-ASSISTED.
    var spotsContradictNonAssistedClaim: Bool {
        usedSpots && station.categoryAssisted == .nonAssisted
    }

    /// The QSO number to send for the next contact, for contests whose
    /// exchange carries one. Derived from the highest number already sent
    /// rather than from the row count, because a county-line contact expands
    /// into several rows that all share one number. Deleting a QSO deliberately
    /// does *not* renumber the rest: those numbers went out on the air.
    var nextSerial: Int {
        (qsos.compactMap(\.serialSent).max() ?? 0) + 1
    }

    /// The category axes as an `OperatingTimeRule.appliesTo` /
    /// `Categories` reads them — Cabrillo raw values, keyed by axis. `mode` is
    /// derived from the rows exactly as the Cabrillo header derives it.
    var categoryValues: [String: String] {
        [
            "operator": station.categoryOperator.rawValue,
            "assisted": station.categoryAssisted.rawValue,
            "power": station.categoryPower.rawValue,
            "station": station.categoryStation.rawValue,
            "transmitter": station.categoryTransmitter.rawValue,
            "band": station.categoryBand ?? "ALL",
            "mode": CabrilloExporter.categoryMode(qsos),
            "overlay": station.categoryOverlay ?? "",
            "time": station.categoryTime ?? "",
        ]
    }

    /// The rule for a log with no stored mode: the first-listed side of a
    /// party — inside, the multiplier everyone is chasing — runs; every other
    /// side searches. Static so both inits can call it before `self` exists.
    private static func deriveOperatingMode(sideID: String) -> OperatingMode {
        sideID == PartyLowering.insideID ? .run : .searchPounce
    }

    /// The mode this log should start in when none is stored.
    var derivedOperatingMode: OperatingMode {
        Self.deriveOperatingMode(sideID: sideID)
    }

    init(
        partyID: String,
        station: StationProfile = StationProfile(),
        myLocation: MyLocation = .outOfState(location: ""),
        qsos: [QSO] = [],
        messages: MessageSets = .standard,
        operatingMode: OperatingMode? = nil,
        setupCompleted: Bool = false,
        exchangeName: String = "",
        exchangeMember: String = "",
        entryClassID: String = "",
        myPotaRefs: [String] = []
    ) {
        self.partyID = partyID
        self.station = station
        self.sideID = Self.sideID(for: myLocation)
        self.sentExchange = Self.compact([
            ExchangeElementID.location: myLocation.sentExchanges,
            ExchangeElementID.name: [exchangeName],
            ExchangeElementID.member: [exchangeMember],
        ])
        self.qsos = qsos
        self.messages = messages
        self.operatingMode = operatingMode ?? Self.deriveOperatingMode(sideID: Self.sideID(for: myLocation))
        self.setupCompleted = setupCompleted
        self.entryClassID = entryClassID
        self.myPotaRefs = myPotaRefs
    }

    /// Drops empty values and then empty lists — the map's one invariant.
    static func compact(_ map: [String: [String]]) -> [String: [String]] {
        map.compactMapValues { values in
            let kept = values.filter { !$0.isEmpty }
            return kept.isEmpty ? nil : kept
        }.filter { !$0.key.isEmpty }
    }

    // MARK: Codable — schema 2 written, schema 1 read

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partyID, station, sideID, sentExchange, qsos, messages, operatingMode, setupCompleted
        case entryClassID, selectedObjectives, declaredBonuses, usedSpots, myPotaRefs, scoreSnapshot
    }

    private enum LegacyKeys: String, CodingKey { case myLocation, exchangeName, exchangeMember }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard version <= Self.currentSchemaVersion else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: [CodingKeys.schemaVersion],
                debugDescription: "This log was saved by a newer build (schema \(version)); this build reads schema \(Self.currentSchemaVersion) or older."))
        }
        schemaVersion = Self.currentSchemaVersion
        partyID = try c.decode(String.self, forKey: .partyID)
        station = try c.decode(StationProfile.self, forKey: .station)
        qsos = try c.decode([QSO].self, forKey: .qsos)
        if c.contains(.sideID) {
            sideID = try c.decode(String.self, forKey: .sideID)
            sentExchange = Self.compact(try c.decodeIfPresent([String: [String]].self, forKey: .sentExchange) ?? [:])
        } else {
            // Schema 1: the party location, name and member element.
            let l = try decoder.container(keyedBy: LegacyKeys.self)
            let location = try l.decode(MyLocation.self, forKey: .myLocation)
            sideID = Self.sideID(for: location)
            sentExchange = Self.compact([
                ExchangeElementID.location: location.sentExchanges,
                ExchangeElementID.name: [try l.decodeIfPresent(String.self, forKey: .exchangeName) ?? ""],
                ExchangeElementID.member: [try l.decodeIfPresent(String.self, forKey: .exchangeMember) ?? ""],
            ])
        }
        // Documents written before per-contest macros existed get the defaults.
        messages = try c.decodeIfPresent(MessageSets.self, forKey: .messages) ?? .standard
        // Logs written before the mode was persisted derive one from the side
        // rather than defaulting an out-of-state operator into Run.
        operatingMode = try c.decodeIfPresent(OperatingMode.self, forKey: .operatingMode)
            ?? Self.deriveOperatingMode(sideID: sideID)
        // Legacy docs in active use (callsign set) count as already set up.
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted)
            ?? !station.callsign.isEmpty
        entryClassID = try c.decodeIfPresent(String.self, forKey: .entryClassID) ?? ""
        selectedObjectives = try c.decodeIfPresent([String].self, forKey: .selectedObjectives) ?? []
        declaredBonuses = try c.decodeIfPresent([String: Int].self, forKey: .declaredBonuses) ?? [:]
        // Documents written before the fact was recorded used no spots.
        usedSpots = try c.decodeIfPresent(Bool.self, forKey: .usedSpots) ?? false
        myPotaRefs = try c.decodeIfPresent([String].self, forKey: .myPotaRefs) ?? []
        scoreSnapshot = try c.decodeIfPresent(ScoreSnapshot.self, forKey: .scoreSnapshot)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(partyID, forKey: .partyID)
        try c.encode(station, forKey: .station)
        try c.encode(sideID, forKey: .sideID)
        try c.encode(sentExchange, forKey: .sentExchange)
        try c.encode(qsos, forKey: .qsos)
        try c.encode(messages, forKey: .messages)
        try c.encode(operatingMode, forKey: .operatingMode)
        try c.encode(setupCompleted, forKey: .setupCompleted)
        try c.encode(entryClassID, forKey: .entryClassID)
        if !selectedObjectives.isEmpty { try c.encode(selectedObjectives, forKey: .selectedObjectives) }
        if !declaredBonuses.isEmpty { try c.encode(declaredBonuses, forKey: .declaredBonuses) }
        try c.encode(usedSpots, forKey: .usedSpots)
        try c.encode(myPotaRefs, forKey: .myPotaRefs)
        try c.encodeIfPresent(scoreSnapshot, forKey: .scoreSnapshot)
    }

    /// The copy the save path writes: `scoreSnapshot` set to this log's
    /// score as of now — the engine's figures when the contest's rules are
    /// installed (`contests`), counts only when they are not — or nil for a
    /// draft (Contest Setup unfinished, or nothing logged yet). Everything
    /// else is untouched.
    func stampingScoreSnapshot(
        contests: (String) -> ContestDefinition? = { ContestCatalog.contest(id: $0) }
    ) -> ContestLog {
        var stamped = self
        stamped.scoreSnapshot = setupCompleted && !qsos.isEmpty
            ? ScoreSnapshot.best(for: self, contests: contests)
            : nil
        return stamped
    }

    /// The same copy, stamped with a snapshot the caller already computed —
    /// the window's cached fold at save time. The draft rule is unchanged:
    /// an unfinished setup or an empty log stamps nil whatever is supplied.
    func stampingScoreSnapshot(using snapshot: ScoreSnapshot) -> ContestLog {
        var stamped = self
        stamped.scoreSnapshot = setupCompleted && !qsos.isEmpty ? snapshot : nil
        return stamped
    }

    static func decode(from data: Data) throws -> ContestLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContestLog.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

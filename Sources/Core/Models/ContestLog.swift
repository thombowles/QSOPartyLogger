import Foundation

/// The persisted document payload (`.qplog` = JSON of this).
struct ContestLog: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    /// PartyDefinition id, e.g. "ksqp".
    var partyID: String
    var station: StationProfile
    var myLocation: MyLocation
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
    /// The operator name sent in every exchange, for parties that carry one
    /// (NAQP rule 10: "a single name throughout the entire contest period").
    /// Set in Contest Setup; stamped into each row's `nameSent` at logging.
    /// Empty for every party that exchanges no name — and for documents
    /// written before the setting existed, which decode to empty.
    var exchangeName: String
    /// The member-number-or-power element sent in every exchange, for parties
    /// that carry one (Skeeter Hunt: your Skeeter number, or your output
    /// power if you have none). Set in Contest Setup; stamped into each row's
    /// `memberSent` at logging. Empty for every party without the element —
    /// and for documents written before the setting existed.
    var exchangeMember: String = ""
    /// The self-declared entry class (`PartyDefinition.entryClasses`) this
    /// log claims — the Skeeter Hunt's X1–X4. Stored as the class `id`; an
    /// empty or stale id resolves to the party's first (lowest-factor) class,
    /// so a log that never chose cannot claim a multiplier the operator did
    /// not. Empty for every party without classes.
    var entryClassID: String = ""
    /// POTA park reference(s) this contest is being operated from — the
    /// *current* Contest Setup value, normalized park references. Stamped
    /// into each row's `myPotaRefs` at logging (the `exchangeName` idiom),
    /// so a mid-contest park change affects later rows only. Empty for
    /// every log that is not an activation — and for documents written
    /// before the setting existed.
    var myPotaRefs: [String] = []
    /// Whether spotting-network information — cluster or hub — was ever
    /// delivered into this contest's session. Set once and never cleared:
    /// reception is access (NAQP rule 5A(ii)'s word), access is what the
    /// Cabrillo ASSISTED/NON-ASSISTED split turns on everywhere, and a
    /// restart mid-contest must not launder it. Recorded even while the
    /// profile claims ASSISTED, so flipping the claim afterwards changes
    /// the warning, not the fact.
    var usedSpots: Bool = false
    /// The score as computed when this log was last saved, with the rules
    /// installed then — the frozen "what I claimed" figure the Contest
    /// Dashboard shows for past seasons, so next year's rule updates never
    /// rewrite this year's history. Stamped by the save path
    /// (`stampingScoreSnapshot`) and read back from the *file* by the
    /// dashboard; the running document never reads it. Nil for a draft, and
    /// for logs written by builds before it existed (the dashboard then
    /// scores the log with today's rules and says so).
    var scoreSnapshot: ScoreSnapshot? = nil

    /// The assisted-category warning's one predicate: spotting information
    /// reached this log while Contest Setup claims NON-ASSISTED. Universal
    /// Cabrillo, no party involved; everything visible hangs off this.
    var spotsContradictNonAssistedClaim: Bool {
        usedSpots && station.categoryAssisted == .nonAssisted
    }

    /// The QSO number to send for the next contact, for parties whose exchange
    /// carries one. Derived from the highest number already sent rather than
    /// from the row count, because a county-line contact expands into several
    /// rows that all share one number. Deleting a QSO deliberately does *not*
    /// renumber the rest: those numbers went out on the air and the other
    /// station logged them, so a gap in the sequence is the honest record.
    var nextSerial: Int {
        (qsos.compactMap(\.serialSent).max() ?? 0) + 1
    }

    /// The rule for a log with no stored mode: the in-state station is the
    /// multiplier everyone is chasing, so it runs; the out-of-state station
    /// is doing the chasing, so it searches. The single copy of that rule —
    /// `derivedOperatingMode`, the memberwise init, and `init(from:)` all
    /// need it, and unlike an instance computed property, a `static func`
    /// takes no `self`, so it is callable from both inits before `self` is
    /// fully initialized.
    private static func deriveOperatingMode(from location: MyLocation) -> OperatingMode {
        location.isInState ? .run : .searchPounce
    }

    /// The mode this log should start in when none is stored.
    var derivedOperatingMode: OperatingMode {
        Self.deriveOperatingMode(from: myLocation)
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
        self.myLocation = myLocation
        self.qsos = qsos
        self.messages = messages
        self.operatingMode = operatingMode ?? Self.deriveOperatingMode(from: myLocation)
        self.setupCompleted = setupCompleted
        self.exchangeName = exchangeName
        self.exchangeMember = exchangeMember
        self.entryClassID = entryClassID
        self.myPotaRefs = myPotaRefs
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partyID, station, myLocation, qsos, messages, operatingMode, setupCompleted
        case exchangeName, exchangeMember, entryClassID, usedSpots, myPotaRefs, scoreSnapshot
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        partyID = try c.decode(String.self, forKey: .partyID)
        station = try c.decode(StationProfile.self, forKey: .station)
        myLocation = try c.decode(MyLocation.self, forKey: .myLocation)
        qsos = try c.decode([QSO].self, forKey: .qsos)
        // Documents written before per-contest macros existed get the defaults.
        messages = try c.decodeIfPresent(MessageSets.self, forKey: .messages) ?? .standard
        // Logs written before the mode was persisted derive one from location
        // rather than defaulting an out-of-state operator into Run.
        operatingMode = try c.decodeIfPresent(OperatingMode.self, forKey: .operatingMode)
            ?? Self.deriveOperatingMode(from: myLocation)
        // Legacy docs in active use (callsign set) count as already set up.
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted)
            ?? !station.callsign.isEmpty
        // Documents written before name exchanges existed carry no name —
        // and likewise for the member element and the entry class.
        exchangeName = try c.decodeIfPresent(String.self, forKey: .exchangeName) ?? ""
        exchangeMember = try c.decodeIfPresent(String.self, forKey: .exchangeMember) ?? ""
        entryClassID = try c.decodeIfPresent(String.self, forKey: .entryClassID) ?? ""
        // Documents written before the fact was recorded used no spots —
        // which is how sponsors read logs that predate the header too.
        usedSpots = try c.decodeIfPresent(Bool.self, forKey: .usedSpots) ?? false
        // Documents written before POTA support carry no parks.
        myPotaRefs = try c.decodeIfPresent([String].self, forKey: .myPotaRefs) ?? []
        // Documents written before the score rode along carry none.
        scoreSnapshot = try c.decodeIfPresent(ScoreSnapshot.self, forKey: .scoreSnapshot)
    }

    /// The copy the save path writes: `scoreSnapshot` set to this log's
    /// score as of now — the engine's figures when the party's rules are
    /// installed (`rules`), counts only when they are not — or nil for a
    /// draft (Contest Setup unfinished, or nothing logged yet). Everything
    /// else is untouched.
    func stampingScoreSnapshot(
        rules: (String) -> PartyDefinition? = { PartyCatalog.party(id: $0) }
    ) -> ContestLog {
        var stamped = self
        stamped.scoreSnapshot = setupCompleted && !qsos.isEmpty
            ? ScoreSnapshot.best(for: self, rules: rules)
            : nil
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

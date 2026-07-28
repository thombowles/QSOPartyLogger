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
        exchangeName: String = ""
    ) {
        self.partyID = partyID
        self.station = station
        self.myLocation = myLocation
        self.qsos = qsos
        self.messages = messages
        self.operatingMode = operatingMode ?? Self.deriveOperatingMode(from: myLocation)
        self.setupCompleted = setupCompleted
        self.exchangeName = exchangeName
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partyID, station, myLocation, qsos, messages, operatingMode, setupCompleted
        case exchangeName
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
        // Documents written before name exchanges existed carry no name.
        exchangeName = try c.decodeIfPresent(String.self, forKey: .exchangeName) ?? ""
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

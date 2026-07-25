import Foundation

/// F1–F8 CW message sets, one per operating style. Stored per document so
/// each contest (window) carries its own macros — running two parties at
/// once means two logs with independent messages.
struct MessageSets: Codable, Equatable, Sendable {
    var run: [String]
    var searchPounce: [String]

    static let defaultRun = [
        "CQ TEST {MYCALL}",
        "{CALL} {RST} {EXCH}",
        "TU {MYCALL}",
        "{MYCALL}",
        "AGN?",
        "?",
        "B4",
        "73 TU {MYCALL}",
    ]

    static let defaultSearchPounce = [
        "{MYCALL}",
        "{RST} {EXCH}",
        "TU",
        "{MYCALL}",
        "AGN?",
        "?",
        "R {RST} {EXCH}",
        "73",
    ]

    static let standard = MessageSets(run: defaultRun, searchPounce: defaultSearchPounce)

    func messages(for mode: OperatingMode) -> [String] {
        switch mode {
        case .run: run
        case .searchPounce: searchPounce
        }
    }
}

/// Run (calling CQ) vs Search & Pounce operating style.
enum OperatingMode: String, Codable, CaseIterable, Sendable {
    case run = "Run"
    case searchPounce = "S&P"
}

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
    /// Whether the operator has been through Contest Setup for this log —
    /// new documents prompt for setup immediately.
    var setupCompleted: Bool

    /// The QSO number to send for the next contact, for parties whose exchange
    /// carries one. Derived from the highest number already sent rather than
    /// from the row count, because a county-line contact expands into several
    /// rows that all share one number. Deleting a QSO deliberately does *not*
    /// renumber the rest: those numbers went out on the air and the other
    /// station logged them, so a gap in the sequence is the honest record.
    var nextSerial: Int {
        (qsos.compactMap(\.serialSent).max() ?? 0) + 1
    }

    init(
        partyID: String,
        station: StationProfile = StationProfile(),
        myLocation: MyLocation = .outOfState(location: ""),
        qsos: [QSO] = [],
        messages: MessageSets = .standard,
        setupCompleted: Bool = false
    ) {
        self.partyID = partyID
        self.station = station
        self.myLocation = myLocation
        self.qsos = qsos
        self.messages = messages
        self.setupCompleted = setupCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partyID, station, myLocation, qsos, messages, setupCompleted
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
        // Legacy docs in active use (callsign set) count as already set up.
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted)
            ?? !station.callsign.isEmpty
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

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

    /// The literal macro set that shipped in every log written before
    /// 2026-07-25 — back when `{RST}` was a fixed default for every party,
    /// regardless of exchange shape. Task 2 compares a log's stored messages
    /// against this constant to tell "the operator never touched the
    /// defaults" from "the operator chose this on purpose," so it must stay
    /// a literal here rather than be re-expressed as `defaults(for: nil)` —
    /// even though the two currently compute the same value, collapsing them
    /// would erase the sentinel a pre-change log is recognised by.
    static let standard = MessageSets(run: defaultRun, searchPounce: defaultSearchPounce)

    /// The default macros for a party's exchange shape. Derived rather than
    /// fixed because three bundled parties send no signal report: CQP and PAQP
    /// send a QSO number instead, and MDC sends call and location only. A fixed
    /// `{RST}` default keys a report those sponsors' exchanges do not contain.
    ///
    /// A nil party — an unrecognised `partyID` — takes the report form. It is
    /// the common shape, and better than handing an operator empty F-keys.
    static func defaults(for party: PartyDefinition?) -> MessageSets {
        let includesRST = party?.exchangeIncludesRST ?? true
        let includesSerial = party?.exchangeIncludesSerial ?? false
        // Report, then number, then location — the order they are sent in.
        let exchange = [
            includesRST ? "{RST}" : nil,
            includesSerial ? "{SERIAL}" : nil,
            "{EXCH}",
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return MessageSets(
            run: [
                "CQ TEST {MYCALL}",
                "{CALL} \(exchange)",
                "TU {MYCALL}",
                "{MYCALL}",
                "AGN?",
                "?",
                "B4",
                "73 TU {MYCALL}",
            ],
            searchPounce: [
                "{MYCALL}",
                exchange,
                "TU",
                "{MYCALL}",
                "AGN?",
                "?",
                "R \(exchange)",
                "73",
            ]
        )
    }

    /// Whether any message in either set references a macro. `macro` is a
    /// braced token such as `{SERIAL}`, matched literally and
    /// case-sensitively as a substring — e.g. `mentions("R")` matches the
    /// bare "R" in "R {RST} {EXCH}", so always pass the full `{TOKEN}`.
    func mentions(_ macro: String) -> Bool {
        (run + searchPounce).contains { $0.contains(macro) }
    }

    /// How a message set can disagree with its party's exchange. Each case is
    /// a distinct on-air failure, not a style preference.
    enum ExchangeMismatch: Equatable, Sendable {
        /// The party sends a QSO number and no message carries `{SERIAL}`, so
        /// the number never goes on the air (CQP, PAQP).
        case missingSerial
        /// The party's exchange carries no signal report, but a message still
        /// sends `{RST}` (CQP, PAQP, MDC).
        case extraneousRST
        /// The party's exchange carries a report and no message sends one —
        /// reachable when an operator types `{SERIAL}` into a report party's
        /// macros, where it expands to nothing because no number is assigned.
        case missingRST
    }

    /// The first way these macros disagree with the party's exchange, or nil
    /// when they agree. Drives the messages editor's warning, which needs the
    /// reason and not merely the fact.
    func exchangeMismatch(with party: PartyDefinition?) -> ExchangeMismatch? {
        guard let party else { return nil }
        if party.exchangeIncludesSerial, !mentions("{SERIAL}") { return .missingSerial }
        if !party.exchangeIncludesRST, mentions("{RST}") { return .extraneousRST }
        if party.exchangeIncludesRST, !mentions("{RST}") { return .missingRST }
        return nil
    }

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

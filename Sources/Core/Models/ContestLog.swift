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

        /// What the messages editor tells the operator. Exhaustive on purpose:
        /// a new case must supply its own sentence rather than inherit one that
        /// describes a different mistake.
        func warning(partyName: String) -> String {
            switch self {
            case .missingSerial:
                "\(partyName) sends a QSO number, but no message uses {SERIAL}."
            case .extraneousRST:
                "\(partyName)'s exchange does not include a signal report, "
                    + "but a message still sends {RST}."
            case .missingRST:
                "\(partyName) sends a signal report, but no message uses {RST}."
            }
        }
    }

    /// The first way these macros disagree with the party's exchange, or nil
    /// when they agree. Drives the messages editor's warning, which needs the
    /// reason and not merely the fact.
    ///
    /// **Each set is judged separately, and within a set each message is judged
    /// on its own.** An operator who fixes Run but not Search & Pounce is still
    /// sending the wrong exchange on every contact they answer rather than call,
    /// and a single OR across both sets would call that agreement. A set with
    /// nothing in it is skipped instead of judged: plenty of operators never
    /// call CQ, and an empty message cannot send a wrong exchange.
    func exchangeMismatch(with party: PartyDefinition?) -> ExchangeMismatch? {
        guard let party else { return nil }
        for messages in [run, searchPounce] {
            if let mismatch = Self.mismatch(in: messages, with: party) { return mismatch }
        }
        return nil
    }

    /// The mismatch within one message set, or nil for a set that agrees — or
    /// that has no messages to disagree with.
    ///
    /// Judged per message rather than per set. CQP's Search & Pounce defaults
    /// carry the exchange twice — the answer and the repeat-back — so asking
    /// only whether the set mentions `{SERIAL}` *somewhere* lets an intact F7
    /// mask an F2 the operator has broken, which is the same defect as ORing
    /// the two sets together.
    private static func mismatch(
        in messages: [String], with party: PartyDefinition
    ) -> ExchangeMismatch? {
        let live = messages.filter { !$0.isEmpty }
        guard !live.isEmpty else { return nil }

        // The messages that send the exchange. A populated set with none of them
        // is judged as though its exchange message existed and were blank, since
        // it cannot send the exchange either. ("Sends no {EXCH}" is a fourth
        // kind of mistake, outside this enum's three.)
        let carriers = live.filter { $0.contains("{EXCH}") }
        let judged = carriers.isEmpty ? [""] : carriers

        // A *missing* token is judged per exchange-bearing message, because
        // CQP's Search & Pounce defaults carry the exchange twice — the answer
        // and the repeat-back — so a set-wide check lets an intact F7 mask an
        // F2 the operator has broken.
        if party.exchangeIncludesSerial, judged.contains(where: { !$0.contains("{SERIAL}") }) {
            return .missingSerial
        }
        // An *extraneous* report is judged across every live message instead:
        // unlike a missing token, it is a should-never-appear check. `{RST}`
        // fat-fingered into F5 ("AGN? {RST}") still keys a literal report every
        // time F5 is pressed, for a party whose exchange has no room for one.
        if !party.exchangeIncludesRST, live.contains(where: { $0.contains("{RST}") }) {
            return .extraneousRST
        }
        if party.exchangeIncludesRST, judged.contains(where: { !$0.contains("{RST}") }) {
            return .missingRST
        }
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
    /// Run vs Search & Pounce. Persisted so reopening a log mid-contest
    /// restores the mode the operator was actually in, rather than snapping
    /// back to Run.
    var operatingMode: OperatingMode
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
        setupCompleted: Bool = false
    ) {
        self.partyID = partyID
        self.station = station
        self.myLocation = myLocation
        self.qsos = qsos
        self.messages = messages
        self.operatingMode = operatingMode ?? Self.deriveOperatingMode(from: myLocation)
        self.setupCompleted = setupCompleted
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partyID, station, myLocation, qsos, messages, operatingMode, setupCompleted
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

import Foundation

private extension String {
    /// Whether this one message references a macro. The `MessageSets` method
    /// of the same name asks it of a whole set; the mismatch checks below ask
    /// it message by message.
    func mentions(_ macro: MacroToken) -> Bool { contains(macro.rawValue) }
}

/// F1–F8 message sets, one per operating style: CW text to key, and on phone
/// which of the radio's recorded voice memories each key plays. Stored per
/// document so each contest (window) carries its own macros — running two
/// parties at once means two logs with independent messages.
struct MessageSets: Codable, Equatable, Sendable {
    var run: [String]
    var searchPounce: [String]

    /// F1–F8 → the radio's voice memory number, or nil for an unassigned key.
    ///
    /// Defaulted in the declaration so the memberwise initialiser keeps its
    /// two-argument form: `MessageSets(run:searchPounce:)` is called from
    /// `defaults(for:)`, `.standard` and `MessagesDraft.edited`.
    var phoneRun: [Int?] = MessageSets.defaultPhoneRun
    var phoneSearchPounce: [Int?] = MessageSets.defaultPhoneSearchPounce

    /// What is recorded in each of the radio's voice memories, M1 first.
    ///
    /// The operator's own note: nothing in the protocol reports a memory's
    /// contents. Indexed by memory rather than by F-key, so eight recordings
    /// have eight names — naming per key would give Run F2 and S&P F2 separate
    /// names for the same audio, free to disagree.
    var voiceMemoryNames: [String] = MessageSets.defaultVoiceMemoryNames

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
    ///
    /// This is also why the two arrays above spell their tokens out instead of
    /// interpolating `MacroToken`, alone in this file: they record what disk
    /// already holds. Renaming a macro must leave them reading `{RST}` and
    /// `{EXCH}`, or every log written before the rename stops being
    /// recognised as untouched.
    static let standard = MessageSets(run: defaultRun, searchPounce: defaultSearchPounce)

    /// Phone defaults stay inside memories 1–4, so the default mapping never
    /// triggers a bank change on a radio whose memories are banked. Memories
    /// 5–8 exist for an operator who wants them, not to be spent by a default.
    static let defaultPhoneRun: [Int?] = [1, 2, 3, nil, 4, nil, nil, nil]

    /// S&P F1 — "send my call" — is deliberately unassigned: a callsign is
    /// faster spoken than recorded, and Return with nothing mapped advances and
    /// logs without transmitting, exactly as an empty CW slot does.
    static let defaultPhoneSearchPounce: [Int?] = [nil, 2, 3, nil, 4, nil, nil, nil]

    static let defaultVoiceMemoryNames = ["CQ", "Exch", "TU", "AGN?", "", "", "", ""]

    /// The number of voice memories the app will ever offer. The *radio's* count
    /// is discovered at connect and is usually smaller; this is only how many
    /// rows the editor draws.
    static let voiceMemorySlots = 8

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
        let includesName = party?.exchangeIncludesName ?? false
        let includesMember = party?.memberExchange != nil
        // Report, then number, then name, then location, then the member
        // element — the order they are sent in ("BILL MOW", "TOM TX": the
        // name leads the location; "559 NJ NR 13": the member trails it).
        let exchange: [MacroToken?] = [
            includesRST ? .rst : nil,
            includesSerial ? .serial : nil,
            includesName ? .name : nil,
            .exchange,
            includesMember ? .member : nil,
        ]
        let sent = exchange.compactMap { $0?.rawValue }.joined(separator: " ")

        return MessageSets(
            run: [
                "CQ TEST \(MacroToken.myCall)",
                "\(MacroToken.call) \(sent)",
                "TU \(MacroToken.myCall)",
                "\(MacroToken.myCall)",
                "AGN?",
                "?",
                "B4",
                "73 TU \(MacroToken.myCall)",
            ],
            searchPounce: [
                "\(MacroToken.myCall)",
                sent,
                "TU",
                "\(MacroToken.myCall)",
                "AGN?",
                "?",
                "R \(sent)",
                "73",
            ]
        )
    }

    /// Whether any message in either set references a macro.
    ///
    /// Takes a `MacroToken` rather than a string so the two ways of getting
    /// this wrong cannot be written: `mentions("R")` used to answer true off
    /// the bare "R" in "R {RST} {EXCH}", and `mentions("{rst}")` false,
    /// because the match is a literal case-sensitive substring.
    func mentions(_ macro: MacroToken) -> Bool {
        (run + searchPounce).contains { $0.mentions(macro) }
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
                "\(partyName) sends a QSO number, but not every message that "
                    + "sends the exchange uses \(MacroToken.serial)."
            case .extraneousRST:
                "\(partyName)'s exchange does not include a signal report, "
                    + "but a message still sends \(MacroToken.rst)."
            case .missingRST:
                "\(partyName) sends a signal report, but not every message that "
                    + "sends the exchange uses \(MacroToken.rst)."
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
        let carriers = live.filter { $0.mentions(.exchange) }
        let judged = carriers.isEmpty ? [""] : carriers

        // A *missing* token is judged per exchange-bearing message, because
        // CQP's Search & Pounce defaults carry the exchange twice — the answer
        // and the repeat-back — so a set-wide check lets an intact F7 mask an
        // F2 the operator has broken.
        if party.exchangeIncludesSerial, judged.contains(where: { !$0.mentions(.serial) }) {
            return .missingSerial
        }
        // An *extraneous* report is judged across every live message instead:
        // unlike a missing token, it is a should-never-appear check. `{RST}`
        // fat-fingered into F5 ("AGN? {RST}") still keys a literal report every
        // time F5 is pressed, for a party whose exchange has no room for one.
        if !party.exchangeIncludesRST, live.contains(where: { $0.mentions(.rst) }) {
            return .extraneousRST
        }
        if party.exchangeIncludesRST, judged.contains(where: { !$0.mentions(.rst) }) {
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

    func voiceMemories(for mode: OperatingMode) -> [Int?] {
        switch mode {
        case .run: phoneRun
        case .searchPounce: phoneSearchPounce
        }
    }

    /// "M4 AGN?", or a bare "M6" when that memory has no name.
    ///
    /// The number always leads. A name can go stale when a recording is
    /// replaced from the front panel, and nothing in the protocol reports what
    /// a memory holds — so the caption degrades to a still-true "M6" rather
    /// than to a claim the app cannot check.
    func voiceMemoryCaption(_ memory: Int) -> String {
        let name = voiceMemoryNames.indices.contains(memory - 1)
            ? voiceMemoryNames[memory - 1].trimmingCharacters(in: .whitespaces)
            : ""
        return name.isEmpty ? "M\(memory)" : "M\(memory) \(name)"
    }
}

/// Run (calling CQ) vs Search & Pounce operating style.
enum OperatingMode: String, Codable, CaseIterable, Sendable {
    case run = "Run"
    case searchPounce = "S&P"
}

/// Additive decoding, Article 4. The phone fields arrived on 2026-08-09; a log
/// written before that carries neither, and must decode with its CW macros
/// untouched and the phone defaults filled in.
///
/// `init(from:)` lives in an extension on purpose: an initialiser declared in
/// the struct body would suppress the memberwise `MessageSets(run:searchPounce:)`
/// that `defaults(for:)` and `.standard` are built from. `encode(to:)` stays
/// synthesised from `CodingKeys`.
extension MessageSets {
    enum CodingKeys: String, CodingKey {
        case run, searchPounce, phoneRun, phoneSearchPounce, voiceMemoryNames
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            run: try c.decode([String].self, forKey: .run),
            searchPounce: try c.decode([String].self, forKey: .searchPounce)
        )
        phoneRun = try c.decodeIfPresent([Int?].self, forKey: .phoneRun)
            ?? Self.defaultPhoneRun
        phoneSearchPounce = try c.decodeIfPresent([Int?].self, forKey: .phoneSearchPounce)
            ?? Self.defaultPhoneSearchPounce
        voiceMemoryNames = try c.decodeIfPresent([String].self, forKey: .voiceMemoryNames)
            ?? Self.defaultVoiceMemoryNames
    }
}


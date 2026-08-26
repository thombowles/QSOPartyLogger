import Foundation

/// The well-known exchange element ids the parties use — the keys of
/// `QSO.sent` / `QSO.rcvd` and of `ContestLog.sentExchange`, and the ids
/// `PartyLowering` gives its elements. A general contest names its own.
enum ExchangeElementID {
    static let rst = "rst"
    static let serial = "serial"
    static let name = "name"
    static let member = "member"
    static let location = "location"
    /// Their state as copied on the air in a POTA log ("59 Missouri") —
    /// carried in `rcvd` like any received token, but declared by no
    /// contest's exchange spec, so the engine and Cabrillo never read it.
    static let state = "state"
}

/// One logged line. County-line contacts produce multiple `QSO` rows sharing a `groupID`
/// (N1MM-style: a separate line per county, per KSQP rule 11).
///
/// The exchange is two maps, element id → value (`sent`, `rcvd`) — the v2 row
/// shape (spec §1.5). The typed accessors below (`rstSent`, `theirLoc`,
/// `serialRcvd`…) are views over the maps, so call sites written for the v1
/// fields read unchanged. The maps never hold an empty value: an absent
/// element has exactly one representation, so equality, encoding and export
/// cannot tell "" from nil. Rows written by earlier builds decode through
/// `LegacyKeys`; this build writes `sent`/`rcvd` only.
struct QSO: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Shared by all rows created from a single on-air contact.
    var groupID: UUID
    var timestampUTC: Date
    var call: String
    var band: Band
    var modeClass: ModeClass
    /// Concrete ADIF mode: CW, SSB, RTTY, FT8…
    var rawMode: String
    /// From CAT when connected; nil when logged manually.
    var freqKHz: Int?
    /// My exchange for this row, element id → value: `rst`, `serial`, `name`,
    /// `member`, `location` for the parties; `zone`, `section`, `check`… for
    /// other contests. A county-line entrant's rows each carry one county.
    var sent: [String: String] { didSet { sent = Self.compact(sent) } }
    /// Their exchange for this row, the same keys.
    var rcvd: [String: String] { didSet { rcvd = Self.compact(rcvd) } }
    /// POTA park references each way, for contests run from a park. Mine are
    /// stamped at logging from Contest Setup's current value
    /// (`ContestLog.myPotaRefs`); theirs is what a park-to-park station
    /// gave. `nil` — never an empty array — when a side has no parks, so
    /// logs written before POTA support decode unchanged and export
    /// byte-identically.
    var myPotaRefs: [String]?
    var theirPotaRefs: [String]?
    /// What a callbook lookup knew about the station at logging time —
    /// stamped only where the contest sets `enrichFromCallbook` (POTA), and
    /// advisory everywhere: never read by `ScoreEngine`, never a received
    /// exchange value, exported as plain ADIF station data. `nil` — the
    /// overwhelmingly common case — writes no key, so every existing log
    /// encodes byte-identically.
    struct CallbookStamp: Codable, Hashable, Sendable {
        var name: String?
        var qth: String?
        var state: String?
        var grid: String?
        /// The service's short label ("QRZ", "HamQTH") — provenance.
        var source: String?
    }
    var callbook: CallbookStamp?
    /// The operator's own note on this contact ("2-fer", "long path") —
    /// POTA logs offer the field; any row may carry one. ADIF `comment`;
    /// nothing scores or exports it anywhere else. `nil` writes no key.
    var notes: String?
    /// Whether this contact was made running or searching, stamped at logging
    /// from the same Run/S&P flag that already picks the message set and
    /// decides what ⇧⌘S means.
    ///
    /// **Nothing scores on it, and no export carries it.** It exists so the
    /// advisor can answer "what has running on 40 m actually paid you tonight"
    /// from the operator's own log rather than from a rule of thumb — see
    /// `Advisor`. `nil` on every row logged before this field existed, and on
    /// rows imported from anywhere else; those simply contribute nothing to
    /// that strand, which is the same evidence-or-silence law the rate column
    /// obeys.
    var posture: OperatingMode?

    // MARK: Typed views over the maps (the v1 fields)

    var rstSent: String {
        get { sent[ExchangeElementID.rst] ?? "" }
        set { sent[ExchangeElementID.rst] = newValue }
    }
    var rstRcvd: String {
        get { rcvd[ExchangeElementID.rst] ?? "" }
        set { rcvd[ExchangeElementID.rst] = newValue }
    }
    /// QSO numbers sent and received, for parties whose exchange carries one
    /// (CQP). A county-line contact is **one** contact and carries **one**
    /// number, shared by every row it expands into (see `CountyLineExpander`).
    var serialSent: Int? {
        get { sent[ExchangeElementID.serial].flatMap { Int($0) } }
        set { sent[ExchangeElementID.serial] = newValue.map(String.init) }
    }
    var serialRcvd: Int? {
        get { rcvd[ExchangeElementID.serial].flatMap { Int($0) } }
        set { rcvd[ExchangeElementID.serial] = newValue.map(String.init) }
    }
    /// Operator names sent and received (NAQP, MNQP). The sent name is the
    /// log's single contest-long name, stamped per row so the record shows
    /// what went out.
    var nameSent: String? {
        get { sent[ExchangeElementID.name] }
        set { sent[ExchangeElementID.name] = newValue }
    }
    var nameRcvd: String? {
        get { rcvd[ExchangeElementID.name] }
        set { rcvd[ExchangeElementID.name] = newValue }
    }
    /// Member-number-or-power elements sent and received (Skeeter Hunt, FOBB)
    /// — a number for members and "5W" for the rest, see `MemberExchange.parse`.
    var memberSent: String? {
        get { sent[ExchangeElementID.member] }
        set { sent[ExchangeElementID.member] = newValue }
    }
    var memberRcvd: String? {
        get { rcvd[ExchangeElementID.member] }
        set { rcvd[ExchangeElementID.member] = newValue }
    }
    /// My sent location for this row: county abbreviation (in-state) or state/province.
    var myLoc: String {
        get { sent[ExchangeElementID.location] ?? "" }
        set { sent[ExchangeElementID.location] = newValue }
    }
    /// Their location for this row: county abbreviation, state, province, or "DX".
    var theirLoc: String {
        get { rcvd[ExchangeElementID.location] ?? "" }
        set { rcvd[ExchangeElementID.location] = newValue }
    }
    /// Their state, for POTA logs — copied on the air, never scored; the
    /// ADIF `state` field where no exchange location supplies one.
    var theirState: String? {
        get { rcvd[ExchangeElementID.state] }
        set { rcvd[ExchangeElementID.state] = newValue }
    }

    // MARK: Inits

    /// The v1 shape: typed fields, mapped into `sent`/`rcvd`.
    init(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        timestampUTC: Date = Date(),
        call: String,
        band: Band,
        modeClass: ModeClass,
        rawMode: String,
        freqKHz: Int? = nil,
        rstSent: String,
        rstRcvd: String,
        serialSent: Int? = nil,
        serialRcvd: Int? = nil,
        nameSent: String? = nil,
        nameRcvd: String? = nil,
        memberSent: String? = nil,
        memberRcvd: String? = nil,
        myPotaRefs: [String]? = nil,
        theirPotaRefs: [String]? = nil,
        myLoc: String,
        theirLoc: String,
        posture: OperatingMode? = nil,
        callbook: CallbookStamp? = nil
    ) {
        self.init(
            id: id, groupID: groupID, timestampUTC: timestampUTC, call: call, band: band,
            modeClass: modeClass, rawMode: rawMode, freqKHz: freqKHz,
            sent: [ExchangeElementID.rst: rstSent, ExchangeElementID.serial: serialSent.map(String.init) ?? "",
                   ExchangeElementID.name: nameSent ?? "", ExchangeElementID.member: memberSent ?? "",
                   ExchangeElementID.location: myLoc],
            rcvd: [ExchangeElementID.rst: rstRcvd, ExchangeElementID.serial: serialRcvd.map(String.init) ?? "",
                   ExchangeElementID.name: nameRcvd ?? "", ExchangeElementID.member: memberRcvd ?? "",
                   ExchangeElementID.location: theirLoc],
            myPotaRefs: myPotaRefs, theirPotaRefs: theirPotaRefs, posture: posture,
            callbook: callbook
        )
    }

    /// The v2 shape: the maps themselves.
    init(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        timestampUTC: Date = Date(),
        call: String,
        band: Band,
        modeClass: ModeClass,
        rawMode: String,
        freqKHz: Int? = nil,
        sent: [String: String],
        rcvd: [String: String],
        myPotaRefs: [String]? = nil,
        theirPotaRefs: [String]? = nil,
        posture: OperatingMode? = nil,
        callbook: CallbookStamp? = nil,
        notes: String? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.timestampUTC = timestampUTC
        self.call = call
        self.band = band
        self.modeClass = modeClass
        self.rawMode = rawMode
        self.freqKHz = freqKHz
        self.sent = Self.compact(sent)
        self.rcvd = Self.compact(rcvd)
        // Empty is stored as absent, so "no parks" has exactly one
        // representation and an ADIF export cannot iterate an empty list.
        self.myPotaRefs = (myPotaRefs?.isEmpty ?? true) ? nil : myPotaRefs
        self.theirPotaRefs = (theirPotaRefs?.isEmpty ?? true) ? nil : theirPotaRefs
        self.posture = posture
        self.callbook = callbook
        self.notes = notes
    }

    /// Drops empty ids and empty values — the maps' one invariant.
    static func compact(_ map: [String: String]) -> [String: String] {
        map.filter { !$0.key.isEmpty && !$0.value.isEmpty }
    }

    // MARK: Codable — v2 written, v1 read

    private enum CodingKeys: String, CodingKey {
        case id, groupID, timestampUTC, call, band, modeClass, rawMode, freqKHz, sent, rcvd, myPotaRefs, theirPotaRefs, posture
        case callbook, notes
    }

    /// The v1 row's own keys. `rstSent`, `rstRcvd`, `myLoc`, `theirLoc` were
    /// required; the rest optional.
    private enum LegacyKeys: String, CodingKey {
        case rstSent, rstRcvd, serialSent, serialRcvd, nameSent, nameRcvd, memberSent, memberRcvd, myLoc, theirLoc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        groupID = try c.decode(UUID.self, forKey: .groupID)
        timestampUTC = try c.decode(Date.self, forKey: .timestampUTC)
        call = try c.decode(String.self, forKey: .call)
        band = try c.decode(Band.self, forKey: .band)
        modeClass = try c.decode(ModeClass.self, forKey: .modeClass)
        rawMode = try c.decode(String.self, forKey: .rawMode)
        freqKHz = try c.decodeIfPresent(Int.self, forKey: .freqKHz)
        myPotaRefs = try c.decodeIfPresent([String].self, forKey: .myPotaRefs).flatMap { $0.isEmpty ? nil : $0 }
        theirPotaRefs = try c.decodeIfPresent([String].self, forKey: .theirPotaRefs).flatMap { $0.isEmpty ? nil : $0 }
        callbook = try c.decodeIfPresent(CallbookStamp.self, forKey: .callbook)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        posture = try c.decodeIfPresent(OperatingMode.self, forKey: .posture)
        if c.contains(.sent) || c.contains(.rcvd) {
            sent = Self.compact(try c.decodeIfPresent([String: String].self, forKey: .sent) ?? [:])
            rcvd = Self.compact(try c.decodeIfPresent([String: String].self, forKey: .rcvd) ?? [:])
        } else {
            let l = try decoder.container(keyedBy: LegacyKeys.self)
            sent = Self.compact([
                ExchangeElementID.rst: try l.decode(String.self, forKey: .rstSent),
                ExchangeElementID.serial: try l.decodeIfPresent(Int.self, forKey: .serialSent).map(String.init) ?? "",
                ExchangeElementID.name: try l.decodeIfPresent(String.self, forKey: .nameSent) ?? "",
                ExchangeElementID.member: try l.decodeIfPresent(String.self, forKey: .memberSent) ?? "",
                ExchangeElementID.location: try l.decode(String.self, forKey: .myLoc),
            ])
            rcvd = Self.compact([
                ExchangeElementID.rst: try l.decode(String.self, forKey: .rstRcvd),
                ExchangeElementID.serial: try l.decodeIfPresent(Int.self, forKey: .serialRcvd).map(String.init) ?? "",
                ExchangeElementID.name: try l.decodeIfPresent(String.self, forKey: .nameRcvd) ?? "",
                ExchangeElementID.member: try l.decodeIfPresent(String.self, forKey: .memberRcvd) ?? "",
                ExchangeElementID.location: try l.decode(String.self, forKey: .theirLoc),
            ])
        }
    }
    // `encode(to:)` stays synthesized over `CodingKeys`: the maps, and every
    // optional only when present — a nil `freqKHz`, parks or `posture` writes
    // no key, exactly as before.
}

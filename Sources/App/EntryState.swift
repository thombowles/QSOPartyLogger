import Foundation
import Observation

/// Live state of the entry row: field values, validation, dupe/mult status.
@Observable
final class EntryState {
    var call = ""

    /// Whether `call` holds text the app put there — a spot click, ⌘↑/⌘↓,
    /// or the call frame — rather than text the operator typed. The same
    /// ownership rule as the exchange, name and member: tuning away may take
    /// back only what the app wrote, and never what was typed.
    private(set) var callIsAutoFilled = false

    /// The call as the operator edits it; the entry field binds here, never
    /// to `call`. Writing through it is what makes the text theirs.
    var callTyped: String {
        get { call }
        set {
            call = newValue
            callIsAutoFilled = false
        }
    }

    func autoFillCall(_ text: String) {
        call = text
        callIsAutoFilled = !text.isEmpty
    }

    /// N1MM's call frame: the spot the VFO is sitting on while searching. Drawn
    /// as a ghost in the empty call field and taken by Space, or by Return
    /// under ESM. It never writes `call` by itself — "When the call-sign
    /// textbox is empty, pressing the space bar will copy the call-sign from
    /// the call-frame to the call-sign textbox" (Entry window, fetched
    /// 2026-08-15).
    var callFrame: Spot?

    /// Whether the row holds anything the operator typed: a call, exchange,
    /// name or member element that is not auto-filled, a received number, a
    /// park, a sent-number override, or a report changed from the default.
    /// The one question the erase rule asks — a row the operator has engaged
    /// with is never cleared by tuning.
    var hasOperatorText: Bool {
        if !call.isEmpty, !callIsAutoFilled { return true }
        if !exchange.isEmpty, !exchangeIsAutoFilled { return true }
        if !nameRcvd.isEmpty, !nameIsAutoFilled { return true }
        if !memberRcvd.isEmpty, !memberIsAutoFilled { return true }
        if !serialRcvd.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if !theirParkTyped.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if hasSerialOverride { return true }
        let defaults = Set(ModeClass.allCases.map(\.defaultRST))
        if !rstSent.isEmpty, !defaults.contains(rstSent) { return true }
        if !rstRcvd.isEmpty, !defaults.contains(rstRcvd) { return true }
        return false
    }

    var rstSent = ""
    var rstRcvd = ""
    var serialRcvd = ""
    /// The name copied from the other station, for parties whose exchange
    /// carries one (NAQP, MNQP). The *sent* name is not entry state at all:
    /// it is the log's contest-long setting, typed once in Contest Setup.
    var nameRcvd = ""

    var exchange = ""

    /// Whether `exchange` holds text the app put there rather than text the
    /// operator typed. Auto-fill only ever writes into a field it already owns,
    /// so it can never destroy a copied exchange — and it takes its own text
    /// back when the call it belonged to leaves the field.
    private(set) var exchangeIsAutoFilled = false

    /// Where auto-filled text came from, because the sources do not deserve
    /// equal faith. Our own log is something the operator copied and logged;
    /// a call history file is a curated community roster of what a station
    /// usually sends; a spot is a stranger's live claim, and the captured hub
    /// corpus shows those go wrong — a busted call, a frequency 29 kHz off,
    /// an unparseable typo. A wrong county is cross-checked against the other
    /// station's log and costs the contact.
    enum ExchangeOrigin: Equatable, Sendable {
        case ownLog
        case callHistory
        case spot
    }

    private(set) var exchangeOrigin: ExchangeOrigin = .ownLog

    /// Auto-filled from a third party rather than from anything we copied.
    /// Drives the stronger of the two provisional treatments in the entry row.
    var exchangeIsUnconfirmed: Bool { exchangeIsAutoFilled && exchangeOrigin == .spot }

    /// The exchange as the operator edits it. Writing through here is what
    /// marks the text as theirs; the view binds to this, never to `exchange`.
    var exchangeTyped: String {
        get { exchange }
        set {
            exchange = newValue
            exchangeIsAutoFilled = false
        }
    }

    func autoFillExchange(_ text: String, origin: ExchangeOrigin = .ownLog) {
        exchange = text
        exchangeIsAutoFilled = true
        exchangeOrigin = origin
    }

    // MARK: Received-name ownership

    /// Whether `nameRcvd` holds text the app put there — the same ownership
    /// rule the exchange has, for the same reason: an offered name must
    /// vanish when its call leaves the field, and must never overwrite what
    /// the operator copied off the air.
    private(set) var nameIsAutoFilled = false

    /// The received name as the operator edits it. Writing through here is
    /// what marks the text as theirs; the view binds to this, never to
    /// `nameRcvd` directly.
    var nameTyped: String {
        get { nameRcvd }
        set {
            nameRcvd = newValue
            nameIsAutoFilled = false
        }
    }

    func autoFillName(_ text: String) {
        nameRcvd = text
        nameIsAutoFilled = true
    }

    /// Take back a name the app offered. Text the operator typed is untouched.
    func clearAutoFilledName() {
        guard nameIsAutoFilled else { return }
        nameRcvd = ""
        nameIsAutoFilled = false
    }

    // MARK: Received member element ownership

    /// The member-number-or-power element copied from the other station, for
    /// parties whose exchange carries one (Skeeter Hunt). The *sent* element
    /// is the log's contest-long setting, typed once in Contest Setup — the
    /// name's arrangement exactly.
    var memberRcvd = ""

    /// Same ownership rule as the exchange and the name, for the same reason.
    private(set) var memberIsAutoFilled = false

    /// Park-to-park: the other station's POTA reference(s) as typed, comma
    /// separated. Empty for the overwhelming majority of contest contacts —
    /// the field only exists at all while this log is an activation.
    var theirParkTyped = ""

    /// The received element as the operator edits it. Writing through here is
    /// what marks the text as theirs; the view binds to this, never to
    /// `memberRcvd` directly.
    var memberTyped: String {
        get { memberRcvd }
        set {
            memberRcvd = newValue
            memberIsAutoFilled = false
        }
    }

    func autoFillMember(_ text: String) {
        memberRcvd = text
        memberIsAutoFilled = true
    }

    /// Take back an element the app offered. Operator text is untouched.
    func clearAutoFilledMember() {
        guard memberIsAutoFilled else { return }
        memberRcvd = ""
        memberIsAutoFilled = false
    }

    /// What the operator copied for a station and never logged. Hunting a
    /// station who can be heard but cannot hear you means copying his exchange
    /// with nothing to show for it; moving to the next spot must not carry that
    /// to the next station, and coming back must not mean copying it twice.
    struct Pending: Equatable {
        var exchange: String
        var serialRcvd: String
        var nameRcvd: String = ""
        var memberRcvd: String = ""

        var isEmpty: Bool {
            exchange.trimmingCharacters(in: .whitespaces).isEmpty
                && serialRcvd.trimmingCharacters(in: .whitespaces).isEmpty
                && nameRcvd.trimmingCharacters(in: .whitespaces).isEmpty
                && memberRcvd.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var pendingExchanges: [String: Pending] = [:]

    /// Put back what was copied for this station, as the operator's own text.
    func restorePending(_ pending: Pending) {
        exchange = pending.exchange
        serialRcvd = pending.serialRcvd
        nameRcvd = pending.nameRcvd
        memberRcvd = pending.memberRcvd
        exchangeIsAutoFilled = false
        nameIsAutoFilled = false
        memberIsAutoFilled = false
    }

    /// Take back text the app put there. Text the operator typed is untouched.
    func clearAutoFilledExchange() {
        guard exchangeIsAutoFilled else { return }
        exchange = ""
        exchangeIsAutoFilled = false
    }

    /// What the operator typed into Ser S, or nil to follow the log.
    ///
    /// An override rather than a seeded value because seeding needs a moment to
    /// happen at, and on 2026-07-25 the moment was missed: a new document is
    /// `ksqp` until Contest Setup runs, so the seed ran against a party that
    /// exchanges no number, and nothing re-ran it when the real party arrived.
    /// The first contact of a CQP log keyed a blank where the number should be.
    /// Derived, there is no moment left to miss.
    private var serialOverride: String?

    /// The log's next QSO number, or nil for the parties that exchange none.
    /// Supplied by `EntryFlow`; nil until then, which reads as "no number".
    @ObservationIgnored var nextSerial: () -> Int? = { nil }

    /// The number this contact will send. Follows the log until the operator
    /// types over it, which is how a mis-sent number gets recorded as it
    /// actually went out.
    var serialSent: String {
        get { serialOverride ?? nextSerial().map(String.init) ?? "" }
        set { serialOverride = newValue }
    }

    /// Whether the operator has typed a number of their own. Distinct from
    /// `serialSent` being non-empty, which is true of the log's own number too.
    var hasSerialOverride: Bool { serialOverride != nil }

    enum ExchangeStatus: Equatable {
        case idle
        case valid([String])
        case invalid(String)
    }

    var exchangeStatus: ExchangeStatus = .idle
    var dupeWarning: String?
    var isNewMult = false

    var callNormalized: String {
        call.trimmingCharacters(in: .whitespaces).uppercased()
    }

    func applyDefaults(modeClass: ModeClass) {
        if rstSent.isEmpty { rstSent = modeClass.defaultRST }
        if rstRcvd.isEmpty { rstRcvd = modeClass.defaultRST }
    }

    /// The typed numbers, or nil where the party exchanges none / nothing was
    /// entered. Non-numeric text yields nil rather than a wrong number.
    func serials(party: PartyDefinition?) -> (sent: Int?, rcvd: Int?) {
        guard party?.exchangeIncludesSerial ?? false else { return (nil, nil) }
        return (Int(serialSent.trimmingCharacters(in: .whitespaces)),
                Int(serialRcvd.trimmingCharacters(in: .whitespaces)))
    }

    /// Whether this party requires a received name the operator has not
    /// copied yet. A name party will not log without one — the sponsors count
    /// only a "complete, correctly copied" exchange, and a nameless row is
    /// the blank ex1 column that blocks submission.
    func missingName(party: PartyDefinition?) -> Bool {
        (party?.exchangeIncludesName ?? false)
            && nameRcvd.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Whether the member element holds something the party cannot read.
    ///
    /// **Blank is not invalid**: a station that sends no number and no power
    /// is a QRO station, which is a real contact worth a point, so an empty
    /// field must log. Text that is neither a number nor a power *is* a
    /// typo, and the element decides the QSO's points — so logging it would
    /// silently score the contact as QRO on a mis-keyed "13".
    func invalidMember(party: PartyDefinition?) -> Bool {
        guard party?.memberExchange != nil else { return false }
        let typed = memberRcvd.trimmingCharacters(in: .whitespaces)
        return !typed.isEmpty && MemberExchange.parse(typed) == nil
    }

    /// An unparseable park-to-park reference blocks logging the way an
    /// unreadable member element does: the reference is what earns the P2P
    /// credit at POTA, so a mis-keyed one must not go into the log in
    /// silence. Empty is always fine — most contacts are not park to park.
    func invalidTheirPark() -> Bool {
        if case .failure = PotaRef.parseList(PotaRef.expandShorthand(theirParkTyped)) { return true }
        return false
    }

    /// Re-validate the exchange and refresh dupe/new-mult hints.
    func revalidate(
        party: PartyDefinition?,
        log: ContestLog,
        band: Band,
        modeClass: ModeClass
    ) {
        guard let party else {
            exchangeStatus = .idle
            return
        }
        let trimmedExchange = exchange.trimmingCharacters(in: .whitespaces)
        guard !trimmedExchange.isEmpty else {
            exchangeStatus = .idle
            dupeWarning = nil
            isNewMult = false
            return
        }

        let role: ExchangeParser.Role = log.myLocation.isInState ? .inState : .outOfState
        switch ExchangeParser.parse(trimmedExchange, party: party, role: role) {
        case .success(let parsed):
            exchangeStatus = .valid(parsed.locations)
            // The call and the member element ride along because a party may
            // count the worked station itself as the multiplier (FOBB counts
            // Bumblebees, again on each band), so the badge cannot be decided
            // by the location alone. Both are inert for every other party.
            let typedMember = memberRcvd.trimmingCharacters(in: .whitespaces)
            isNewMult = ScoreEngine.wouldAddMultiplier(
                theirLocs: parsed.locations, band: band, modeClass: modeClass,
                log: log, party: party,
                call: callNormalized,
                memberRcvd: typedMember.isEmpty ? nil : typedMember
            )
            updateDupeWarning(parsed: parsed, log: log, band: band, modeClass: modeClass)
        case .failure(let error):
            exchangeStatus = .invalid(error.localizedDescription)
            isNewMult = false
            dupeWarning = nil
        }
    }

    /// Revalidation for a v2-only contest (POTA): there is no exchange
    /// element to parse, so the status stays `.idle` and `canLog` is decided
    /// by the layout; the dupe check runs the contest's own rule — the same
    /// key the engine scores with, so the warning can never disagree with
    /// the score (utcDay, perMyPark and all).
    func revalidate(
        contest: ContestDefinition,
        log: ContestLog,
        band: Band,
        modeClass: ModeClass,
        now: Date = Date()
    ) {
        exchangeStatus = .idle
        isNewMult = false
        let callSign = callNormalized
        guard !callSign.isEmpty else {
            dupeWarning = nil
            return
        }
        let probe = QSO(
            timestampUTC: now, call: callSign, band: band,
            modeClass: modeClass, rawMode: "", sent: [:], rcvd: [:],
            myPotaRefs: log.myPotaRefs.isEmpty ? nil : log.myPotaRefs
        )
        let logged = Set(log.qsos.map { DupeChecker.key($0, rule: contest.dupe) })
        if logged.contains(DupeChecker.key(probe, rule: contest.dupe)) {
            let today = contest.dupe.utcDay ? " today" : ""
            dupeWarning = "DUPE: \(callSign) already worked on \(band.rawValue) \(modeClass.displayName)\(today)"
        } else {
            dupeWarning = nil
        }
    }

    private func updateDupeWarning(
        parsed: ExchangeParser.ParsedExchange,
        log: ContestLog,
        band: Band,
        modeClass: ModeClass
    ) {
        let callSign = callNormalized
        guard !callSign.isEmpty else {
            dupeWarning = nil
            return
        }
        let dupes = DupeChecker.existingDupePairs(
            call: callSign,
            band: band,
            modeClass: modeClass,
            myLocs: log.myLocation.sentExchanges,
            theirLocs: parsed.locations,
            log: log.qsos
        )
        dupeWarning = dupes.isEmpty
            ? nil
            : "DUPE: \(callSign) already worked on \(band.rawValue) \(modeClass.displayName) (\(dupes.map(\.theirLoc).joined(separator: ", ")))"
    }

    /// Swap pre-filled default reports when the operating mode changes
    /// (599 ↔ 59); anything the operator actually typed is left alone.
    func syncRSTDefaults(modeClass: ModeClass) {
        let defaults = Set(ModeClass.allCases.map(\.defaultRST))
        if rstSent.isEmpty || defaults.contains(rstSent) { rstSent = modeClass.defaultRST }
        if rstRcvd.isEmpty || defaults.contains(rstRcvd) { rstRcvd = modeClass.defaultRST }
    }

    func clearForNextContact(modeClass: ModeClass) {
        call = ""
        callIsAutoFilled = false
        rstSent = modeClass.defaultRST
        rstRcvd = modeClass.defaultRST
        // Back to following the log, which has just advanced past the contact
        // that was logged. A number the operator typed belonged to that
        // contact, not this one.
        serialOverride = nil
        serialRcvd = ""
        nameRcvd = ""
        nameIsAutoFilled = false
        memberRcvd = ""
        memberIsAutoFilled = false
        theirParkTyped = ""
        exchange = ""
        exchangeIsAutoFilled = false
        exchangeStatus = .idle
        dupeWarning = nil
        isNewMult = false
    }
}

import Foundation
import Observation

/// Live state of the entry row: field values, validation, dupe/mult status.
@Observable
final class EntryState {
    var call = ""
    var rstSent = ""
    var rstRcvd = ""
    var serialRcvd = ""

    var exchange = ""

    /// Whether `exchange` holds text the app put there rather than text the
    /// operator typed. Auto-fill only ever writes into a field it already owns,
    /// so it can never destroy a copied exchange — and it takes its own text
    /// back when the call it belonged to leaves the field.
    private(set) var exchangeIsAutoFilled = false

    /// Where auto-filled text came from, because the two sources do not
    /// deserve equal faith. Our own log is something the operator copied and
    /// logged; a spot is a stranger's claim, and the captured hub corpus shows
    /// those go wrong — a busted call, a frequency 29 kHz off, an unparseable
    /// typo. A wrong county is cross-checked against the other station's log
    /// and costs the contact.
    enum ExchangeOrigin: Equatable, Sendable {
        case ownLog
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

    /// What the operator copied for a station and never logged. Hunting a
    /// station who can be heard but cannot hear you means copying his exchange
    /// with nothing to show for it; moving to the next spot must not carry that
    /// to the next station, and coming back must not mean copying it twice.
    struct Pending: Equatable {
        var exchange: String
        var serialRcvd: String

        var isEmpty: Bool {
            exchange.trimmingCharacters(in: .whitespaces).isEmpty
                && serialRcvd.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var pendingExchanges: [String: Pending] = [:]

    /// Put back what was copied for this station, as the operator's own text.
    func restorePending(_ pending: Pending) {
        exchange = pending.exchange
        serialRcvd = pending.serialRcvd
        exchangeIsAutoFilled = false
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
            isNewMult = ScoreEngine.wouldAddMultiplier(
                theirLocs: parsed.locations, band: band, modeClass: modeClass,
                log: log, party: party
            )
            updateDupeWarning(parsed: parsed, log: log, band: band, modeClass: modeClass)
        case .failure(let error):
            exchangeStatus = .invalid(error.localizedDescription)
            isNewMult = false
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
        rstSent = modeClass.defaultRST
        rstRcvd = modeClass.defaultRST
        // Back to following the log, which has just advanced past the contact
        // that was logged. A number the operator typed belonged to that
        // contact, not this one.
        serialOverride = nil
        serialRcvd = ""
        exchange = ""
        exchangeIsAutoFilled = false
        exchangeStatus = .idle
        dupeWarning = nil
        isNewMult = false
    }
}

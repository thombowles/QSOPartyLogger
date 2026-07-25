import Foundation
import Observation

/// Live state of the entry row: field values, validation, dupe/mult status.
@Observable
final class EntryState {
    var call = ""
    var rstSent = ""
    var rstRcvd = ""
    var serialRcvd = ""

    /// The exchange as it will be logged. Assigning marks it confirmed: the
    /// only way text gets here is the operator putting it here.
    var exchange: String {
        get { exchangeStorage }
        set {
            exchangeStorage = newValue
            exchangeIsUnconfirmed = false
        }
    }
    private var exchangeStorage = ""

    /// The exchange came from a spot and has not been copied yet.
    ///
    /// A hub spot names the county, but that is a third party's claim. The
    /// captured corpus shows those can be wrong — a busted call, a frequency
    /// 29 kHz off, an unparseable typo — and a wrong county is cross-checked
    /// against the other station's log and costs the contact. So the value is
    /// offered, and shown as provisional until the operator stands behind it.
    private(set) var exchangeIsUnconfirmed = false

    /// Offer an exchange taken from a spot rather than copied off the air.
    ///
    /// Never overwrites what the operator typed — stepping through spots with
    /// ⌘←/⌘→ must not replace an exchange already being copied. One offered
    /// value does replace another, so stepping keeps up instead of sticking on
    /// the first county seen.
    func prefillExchange(_ county: String) {
        let county = county.trimmingCharacters(in: .whitespaces).uppercased()
        guard !county.isEmpty else { return }
        guard exchangeStorage.isEmpty || exchangeIsUnconfirmed else { return }
        exchangeStorage = county
        exchangeIsUnconfirmed = true
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
        exchangeStatus = .idle
        dupeWarning = nil
        isNewMult = false
    }
}

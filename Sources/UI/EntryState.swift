import Foundation
import Observation

/// Live state of the entry row: field values, validation, dupe/mult status.
@Observable
final class EntryState {
    var call = ""
    var rstSent = ""
    var rstRcvd = ""
    /// QSO numbers, for parties whose exchange carries one. `serialSent` is
    /// pre-filled with the log's next number and stays editable so a
    /// mis-sent number can be recorded as it actually went out.
    var serialSent = ""
    var serialRcvd = ""
    var exchange = ""

    enum ExchangeStatus: Equatable {
        case idle
        case valid([String])
        case invalid(String)
    }

    var exchangeStatus: ExchangeStatus = .idle
    var dupeWarning: String?
    var isNewMult = false

    /// The station this contact's ESM sequence has already called — set when
    /// the middle message goes out (S&P your call, Run their report), cleared
    /// when the contact is logged or wiped. Holding the callsign rather than a
    /// bare flag means retyping the call restarts the sequence by itself, with
    /// nothing to invalidate.
    var esmSentTo: String?

    var callNormalized: String {
        call.trimmingCharacters(in: .whitespaces).uppercased()
    }

    /// True once this contact's middle message has gone out to the callsign
    /// now in the field. Until it has, Return sends instead of logging — which
    /// is what keeps an exchange prefilled from a spot from logging a QSO that
    /// was never made.
    var esmMiddleSent: Bool {
        guard let esmSentTo, !esmSentTo.isEmpty else { return false }
        return esmSentTo == callNormalized
    }

    func applyDefaults(modeClass: ModeClass) {
        if rstSent.isEmpty { rstSent = modeClass.defaultRST }
        if rstRcvd.isEmpty { rstRcvd = modeClass.defaultRST }
    }

    /// Show the number this contact will send. `nil` for the parties that
    /// exchange no QSO number, which clears the field.
    func syncSerial(next: Int?) {
        serialSent = next.map(String.init) ?? ""
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

        switch ExchangeParser.parse(trimmedExchange, party: party) {
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

    func clearForNextContact(modeClass: ModeClass, nextSerial: Int? = nil) {
        call = ""
        rstSent = modeClass.defaultRST
        rstRcvd = modeClass.defaultRST
        syncSerial(next: nextSerial)
        serialRcvd = ""
        exchange = ""
        exchangeStatus = .idle
        dupeWarning = nil
        isNewMult = false
        esmSentTo = nil
    }
}

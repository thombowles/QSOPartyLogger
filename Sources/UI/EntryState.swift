import Foundation
import Observation

/// Live state of the entry row: field values, validation, dupe/mult status.
@Observable
final class EntryState {
    var call = ""
    var rstSent = ""
    var rstRcvd = ""
    var exchange = ""

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
                theirLocs: parsed.locations, log: log, party: party
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

    func clearForNextContact() {
        call = ""
        rstSent = ""
        rstRcvd = ""
        exchange = ""
        exchangeStatus = .idle
        dupeWarning = nil
        isNewMult = false
    }
}

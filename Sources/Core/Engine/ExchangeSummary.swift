import Foundation

/// What one side of a contact reads as in the log — the exchange the party
/// actually runs, not a fixed signal report plus a location.
///
/// Ten of the bundled parties exchange no report at all: NAQP and MNQP send a
/// name ("TOM TX"), CQP, PAQP and VAQP send a QSO number ("1 SCLA"), and MDC,
/// IdQP, NCQP and WIQP send the location alone. Every row still carries a
/// report, because the entry row fills one from the mode default whether or not
/// the party wants it, so a formatter reading `rstSent` unconditionally shows a
/// report that never went out — and, worse, hides the name or the number that
/// did. `EntryBar` and `EditQSOSheet` already gate their fields on these three
/// flags; this is the same rule for the log.
///
/// The party decides, not the row, because a row cannot tell the difference
/// between a report it sent and a default it was given.
enum ExchangeSummary {

    /// What went out: the elements this party sends, then my location.
    static func sent(_ q: QSO, party: PartyDefinition?) -> String {
        text(rst: q.rstSent, serial: q.serialSent, name: q.nameSent,
             member: q.memberSent, location: q.myLoc, party: party)
    }

    /// What was copied: the elements this party sends, then their location.
    static func received(_ q: QSO, party: PartyDefinition?) -> String {
        text(rst: q.rstRcvd, serial: q.serialRcvd, name: q.nameRcvd,
             member: q.memberRcvd, location: q.theirLoc, party: party)
    }

    private static func text(
        rst: String, serial: Int?, name: String?, member: String?,
        location: String, party: PartyDefinition?
    ) -> String {
        // The member element trails the location — the sponsor's own order
        // ("559 NJ NR 13"), and the entry row's.
        let trailing = party?.memberExchange != nil ? [member ?? ""] : []
        return (elements(rst: rst, serial: serial, name: name, party: party)
                + [location] + trailing)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Everything ahead of the location, in the order the entry row collects
    /// it — report, number, name — so the log reads back the way it was typed.
    /// An element the row never captured drops out rather than leaving a hole:
    /// a name party whose log has no contest name shows the location alone.
    private static func elements(
        rst: String, serial: Int?, name: String?, party: PartyDefinition?
    ) -> [String] {
        guard let party else {
            // No definition to consult — a log whose party id is not in the
            // catalog. The row is then the only evidence of its own shape, so
            // read it the way the Cabrillo ex1 element does: a name, else a
            // number, else the report.
            return [CabrilloExporter.exchangeElement(name: name, serial: serial, rst: rst)]
        }
        var out: [String] = []
        if party.exchangeIncludesRST { out.append(rst) }
        if party.exchangeIncludesSerial, let serial { out.append(String(serial)) }
        if party.exchangeIncludesName, let name { out.append(name) }
        return out
    }
}

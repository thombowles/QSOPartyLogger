import Foundation

/// Expands one on-air contact into logged rows: the cartesian product of my
/// location(s) × their location(s). N1MM-style — a county-line contact becomes
/// one row per county (KSQP rule 11: "a separate QSO must be logged for each
/// county"), and when I straddle a line myself, each of my counties produces
/// rows of its own.
enum CountyLineExpander {

    struct QSOEntry {
        var call: String
        var rstSent: String
        var rstRcvd: String
        /// One contact, one QSO number. A county-line exchange sends its
        /// counties "in a single exchange" (CQP), so every row this expands
        /// into carries the same pair — the operator sent one number on the
        /// air, and the log must not claim several.
        var serialSent: Int? = nil
        var serialRcvd: Int? = nil
        /// One contact, one name each way, for the same reason.
        var nameSent: String? = nil
        var nameRcvd: String? = nil
        /// One contact, one member element each way, for the same reason.
        var memberSent: String? = nil
        var memberRcvd: String? = nil
        var band: Band
        var modeClass: ModeClass
        var rawMode: String
        var freqKHz: Int?
        var timestampUTC: Date
    }

    static func expand(entry: QSOEntry, myLocs: [String], theirLocs: [String]) -> [QSO] {
        let groupID = UUID()
        return myLocs.flatMap { mine in
            theirLocs.map { theirs in
                QSO(
                    groupID: groupID,
                    timestampUTC: entry.timestampUTC,
                    call: entry.call,
                    band: entry.band,
                    modeClass: entry.modeClass,
                    rawMode: entry.rawMode,
                    freqKHz: entry.freqKHz,
                    rstSent: entry.rstSent,
                    rstRcvd: entry.rstRcvd,
                    serialSent: entry.serialSent,
                    serialRcvd: entry.serialRcvd,
                    nameSent: entry.nameSent,
                    nameRcvd: entry.nameRcvd,
                    memberSent: entry.memberSent,
                    memberRcvd: entry.memberRcvd,
                    myLoc: mine,
                    theirLoc: theirs
                )
            }
        }
    }
}

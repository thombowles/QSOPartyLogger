import Foundation

/// One contest as the dashboard sees it: a `.qplog` file in the logs folder,
/// read as a value. Identity is the sponsor's own notion of an entry — one
/// log per callsign per running of a party — so a two-window weekend is
/// naturally one record. Nothing here is persisted; the log file is.
struct ContestRecord: Equatable, Sendable, Identifiable {

    struct Identity: Hashable, Sendable {
        let partyID: String
        let year: Int
        let callsign: String
    }

    /// Where the record's score came from — so the score cell can say
    /// whether it is the frozen figure saved with the log or one computed
    /// now with the rules installed here (a log from an older build, or one
    /// saved on a Mac without this party's rules).
    enum ScoreOrigin: Equatable, Sendable {
        case savedWithLog
        case computedNow
    }

    var partyID: String
    var year: Int
    var callsign: String
    var station: StationProfile
    var myLocation: MyLocation
    var qsos: [QSO]
    var snapshot: ScoreSnapshot
    var scoreOrigin: ScoreOrigin = .computedNow
    /// The log file's modification date.
    var updatedAt: Date
    /// The log's file name in the logs folder — what Open, ⌘E and ⇧⌘E read.
    var sourceFileName: String?

    var id: String { "\(partyID)|\(year)|\(callsign)" }

    var identity: Identity {
        Identity(partyID: partyID, year: year, callsign: callsign)
    }

    var earliestQSO: Date? {
        qsos.map(\.timestampUTC).min()
    }

    /// UTC year of the log's earliest QSO; nil for an empty log.
    static func year(of log: ContestLog) -> Int? {
        log.qsos.map(\.timestampUTC).min()?.utcYear
    }

    /// nil when the log isn't a contest entry yet: no QSOs (nothing to
    /// track) or no callsign (no identity).
    static func make(
        from log: ContestLog,
        snapshot: ScoreSnapshot,
        scoreOrigin: ScoreOrigin = .computedNow,
        updatedAt: Date,
        sourceFileName: String?
    ) -> ContestRecord? {
        let callsign = log.station.callsign
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        guard !callsign.isEmpty, let year = year(of: log) else { return nil }
        return ContestRecord(
            partyID: log.partyID,
            year: year,
            callsign: callsign,
            station: log.station,
            myLocation: log.myLocation,
            qsos: canonicalOrder(log.qsos),
            snapshot: snapshot,
            scoreOrigin: scoreOrigin,
            updatedAt: updatedAt,
            sourceFileName: sourceFileName
        )
    }

    /// Deterministic row order whatever order the log held them.
    static func canonicalOrder(_ qsos: [QSO]) -> [QSO] {
        qsos.sorted {
            if $0.timestampUTC != $1.timestampUTC {
                return $0.timestampUTC < $1.timestampUTC
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

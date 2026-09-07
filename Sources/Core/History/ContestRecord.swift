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
        /// nil for a party — one log per entry, the sponsor's own identity.
        /// For an always-on program (POTA) it is the outing (UTC day +
        /// parks), so a year of activations never folds into one record.
        var outing: String? = nil
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
    /// The outing discriminator for program logs (see `Identity.outing`);
    /// nil for every party record, whose identity is unchanged.
    var outing: String? = nil
    /// The log file's modification date.
    var updatedAt: Date
    /// The log's file name in the logs folder — what Open, ⌘E and ⇧⌘E read.
    var sourceFileName: String?

    var id: String { "\(partyID)|\(year)|\(callsign)" + (outing.map { "|\($0)" } ?? "") }

    var identity: Identity {
        Identity(partyID: partyID, year: year, callsign: callsign, outing: outing)
    }

    var earliestQSO: Date? {
        qsos.map(\.timestampUTC).min()
    }

    /// Whether any contact was made from a park of the operator's own — a
    /// contest worked from a park, which the dashboard's POTA side counts as
    /// an outing too, park contacts only.
    var activatesAPark: Bool {
        qsos.contains { !($0.myPotaRefs ?? []).isEmpty }
    }

    /// UTC year of the log's earliest QSO; nil for an empty log.
    static func year(of log: ContestLog) -> Int? {
        log.qsos.map(\.timestampUTC).min()?.utcYear
    }

    /// nil when the log isn't a contest entry yet: no QSOs (nothing to
    /// track) or no callsign (no identity). `program` marks an always-on
    /// program log (POTA — `ContestFamily.program`): its identity gains an
    /// outing, because "one log per year" is a party's shape, not a program's.
    static func make(
        from log: ContestLog,
        snapshot: ScoreSnapshot,
        scoreOrigin: ScoreOrigin = .computedNow,
        updatedAt: Date,
        sourceFileName: String?,
        program: Bool = false
    ) -> ContestRecord? {
        let callsign = log.station.callsign
            .trimmingCharacters(in: .whitespaces)
            .uppercased()
        guard !callsign.isEmpty, let year = year(of: log) else { return nil }
        let qsos = canonicalOrder(log.qsos)
        return ContestRecord(
            partyID: log.partyID,
            year: year,
            callsign: callsign,
            station: log.station,
            myLocation: log.myLocation,
            qsos: qsos,
            snapshot: snapshot,
            scoreOrigin: scoreOrigin,
            outing: program ? outing(of: qsos) : nil,
            updatedAt: updatedAt,
            sourceFileName: sourceFileName
        )
    }

    /// The outing a program log records: the UTC day of its first QSO plus
    /// the sorted parks worked from, read from the rows themselves (the
    /// log's current-park set can lag a rover). Two files for one outing —
    /// an iCloud "2" copy — still fold; two outings never do. A hunter log
    /// has no park, so its outing is the day alone.
    static func outing(of qsos: [QSO]) -> String? {
        guard let first = qsos.map(\.timestampUTC).min() else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let parts = calendar.dateComponents([.year, .month, .day], from: first)
        let day = String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        let parks = Set(qsos.flatMap { $0.myPotaRefs ?? [] }.map { $0.uppercased() })
        return parks.isEmpty ? day : day + "@" + parks.sorted().joined(separator: "+")
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

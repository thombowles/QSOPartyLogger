import Foundation

/// The contest history as one value — every contest read from the logs
/// folder (`LogFolder.history()`) — for the dashboard, the season stats,
/// the Challenge standing, the upcoming calendar and the station memory.
/// Nothing here is persisted: the `.qplog` files are the history.
struct ContestArchive: Equatable, Sendable {
    var records: [ContestRecord]

    static let empty = ContestArchive(records: [])

    init(records: [ContestRecord] = []) {
        self.records = records
    }

    /// Distinct years present, newest first.
    var years: [Int] {
        Set(records.map(\.year)).sorted(by: >)
    }

    /// Records for a year, earliest contest first.
    func records(year: Int) -> [ContestRecord] {
        records.filter { $0.year == year }
    }

    /// Season order: chronological, then party/callsign.
    static func canonicalOrder(_ records: [ContestRecord]) -> [ContestRecord] {
        records.sorted {
            if $0.year != $1.year { return $0.year < $1.year }
            let first = $0.earliestQSO ?? .distantPast
            let second = $1.earliestQSO ?? .distantPast
            if first != second { return first < second }
            if $0.partyID != $1.partyID { return $0.partyID < $1.partyID }
            return $0.callsign < $1.callsign
        }
    }
}

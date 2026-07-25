import Foundation

/// Pure aggregation over archived records for the dashboard's year view.
struct SeasonStats: Equatable, Sendable {
    let year: Int
    let contests: Int
    let validQSOs: Int
    /// Sum of snapshot totals over records that carry score figures.
    let combinedScore: Int
    let scoredContests: Int
    let operatingMinutes: Int
    let qsosByMode: [String: Int]
    let countiesWorked: Int
    /// The year's records in season order (earliest contest first).
    let rows: [ContestRecord]

    static func compute(records: [ContestRecord], year: Int) -> SeasonStats {
        let rows = ContestArchive.canonicalOrder(records.filter { $0.year == year })
        var qsosByMode: [String: Int] = [:]
        for row in rows {
            for (mode, count) in row.snapshot.qsosByMode {
                qsosByMode[mode, default: 0] += count
            }
        }
        return SeasonStats(
            year: year,
            contests: rows.count,
            validQSOs: rows.reduce(0) { $0 + $1.snapshot.validQSOs },
            combinedScore: rows.compactMap { $0.snapshot.figures?.total }.reduce(0, +),
            scoredContests: rows.filter { $0.snapshot.figures != nil }.count,
            operatingMinutes: rows.reduce(0) { $0 + $1.snapshot.operatingMinutes },
            qsosByMode: qsosByMode,
            countiesWorked: rows.reduce(0) { $0 + $1.snapshot.countiesWorked },
            rows: rows
        )
    }

    /// One party across all years, ascending — the trend chart's data.
    static func partyTrend(
        records: [ContestRecord],
        partyID: String
    ) -> [(year: Int, snapshot: ScoreSnapshot)] {
        records
            .filter { $0.partyID == partyID }
            .sorted { $0.year < $1.year }
            .map { ($0.year, $0.snapshot) }
    }
}

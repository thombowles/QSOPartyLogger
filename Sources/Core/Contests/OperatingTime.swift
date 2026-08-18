import Foundation

/// Operating-time arithmetic for `OperatingTimeRule` (spec §1.2): minute
/// granularity, off time only when the empty minutes between two rows reach
/// the rule's minimum, rows past the maximum marked out of time.
enum OperatingTime {
    /// One credited off period: the empty clock minutes strictly between two
    /// rows, first and last minute inclusive — the SS package's 0115–0144.
    struct OffPeriod: Equatable, Sendable {
        let start: Date
        let end: Date
    }

    struct Result: Equatable, Sendable {
        var operatedMinutes = 0
        var offMinutes = 0
        /// The timestamp of the last row that still counted, once the limit is
        /// reached; nil while the entrant is within the limit.
        var cutoff: Date?
        var outOfTimeRowIDs: Set<UUID> = []
        /// Every credited off period, in clock order — Cabrillo `OFFTIME:` lines.
        var offPeriods: [OffPeriod] = []

        static let zero = Result()
    }

    /// Whole minutes since the epoch, seconds ignored (the sponsors' rule).
    static func minute(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 60)) }

    /// The first second of a whole minute since the epoch.
    static func date(minute: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(minute * 60)) }

    static func compute(rows: [QSO], rule: OperatingTimeRule) -> Result {
        let ordered = rows.sortedChronologically()
        guard let first = ordered.first else { return .zero }
        var result = Result()
        var operated = 0
        var previous = minute(first.timestampUTC)
        var lastCounted = first
        for row in ordered.dropFirst() {
            let now = minute(row.timestampUTC)
            let empty = max(0, now - previous - 1)
            if empty >= rule.minOffMinutes {
                result.offMinutes += empty
                result.offPeriods.append(OffPeriod(start: date(minute: previous + 1), end: date(minute: now - 1)))
            } else {
                operated += now - previous
            }
            previous = now
            if operated > rule.maxMinutes {
                result.outOfTimeRowIDs.insert(row.id)
                if result.cutoff == nil { result.cutoff = lastCounted.timestampUTC }
            } else {
                lastCounted = row
            }
        }
        result.operatedMinutes = min(operated, rule.maxMinutes)
        return result
    }
}

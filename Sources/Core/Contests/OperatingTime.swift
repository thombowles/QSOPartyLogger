import Foundation

/// Operating-time arithmetic for `OperatingTimeRule` (spec §1.2): minute
/// granularity, off time only when the empty minutes between two rows reach
/// the rule's minimum, rows past the maximum marked out of time.
enum OperatingTime {
    struct Result: Equatable, Sendable {
        var operatedMinutes = 0
        var offMinutes = 0
        /// The timestamp of the last row that still counted, once the limit is
        /// reached; nil while the entrant is within the limit.
        var cutoff: Date?
        var outOfTimeRowIDs: Set<UUID> = []

        static let zero = Result()
    }

    /// Whole minutes since the epoch, seconds ignored (the sponsors' rule).
    static func minute(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 60)) }

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

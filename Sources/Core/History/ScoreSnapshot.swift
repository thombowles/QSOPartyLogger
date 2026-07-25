import Foundation

/// A contest's scoring figures as computed when the log was saved — the
/// "what I claimed" record the dashboard shows for past seasons. Snapshots
/// deliberately do not chase later rule-file edits: party JSON is updated
/// every season (schedules are annual), and a 2026 score must not drift when
/// the 2027 rules land. They are recomputed only when the QSO set itself
/// changes (a two-Mac merge).
struct ScoreSnapshot: Codable, Equatable, Sendable {

    /// Engine-derived score figures. Absent when the party definition wasn't
    /// installed on the archiving Mac — counts survive, score shows as
    /// unavailable rather than zero.
    struct Figures: Codable, Equatable, Sendable {
        var qsoPoints: Int
        var multiplierCount: Int
        var multiplierCap: Int?
        var bonusPoints: Int
        var categoryFactor: Int
        var total: Int
        /// Scoped multiplier counts keyed by `MultClass` raw value.
        var multsByClass: [String: Int]
    }

    var validQSOs: Int
    var dupeCount: Int
    var invalidModeCount: Int
    var outOfScopeCount: Int
    /// Valid QSOs keyed by `ModeClass` / `Band` raw value.
    var qsosByMode: [String: Int]
    var qsosByBand: [String: Int]
    var countiesWorked: Int
    var operatingMinutes: Int
    var figures: Figures?

    /// Full snapshot via the scoring engine — the same fold the score
    /// sidebar shows, so the dashboard can never disagree with it.
    static func make(log: ContestLog, party: PartyDefinition) -> ScoreSnapshot {
        let breakdown = ScoreEngine.score(log: log, party: party)
        var byMode: [String: Int] = [:]
        var byBand: [String: Int] = [:]
        for (band, modes) in ScoreEngine.bandModeCounts(log: log, party: party) {
            for (mode, count) in modes {
                byMode[mode.rawValue, default: 0] += count
                byBand[band.rawValue, default: 0] += count
            }
        }
        return ScoreSnapshot(
            validQSOs: breakdown.validQSOs,
            dupeCount: breakdown.dupeCount,
            invalidModeCount: breakdown.invalidModeCount,
            outOfScopeCount: breakdown.outOfScopeCount,
            qsosByMode: byMode,
            qsosByBand: byBand,
            countiesWorked: breakdown.workedValues(.county).count,
            operatingMinutes: operatingMinutes(timestamps: log.qsos.map(\.timestampUTC)),
            figures: Figures(
                qsoPoints: breakdown.qsoPoints,
                multiplierCount: breakdown.multiplierCount,
                multiplierCap: breakdown.multiplierCap,
                bonusPoints: breakdown.bonusPoints,
                categoryFactor: breakdown.categoryFactor,
                total: breakdown.total,
                multsByClass: Dictionary(
                    uniqueKeysWithValues: breakdown.classCounts.map { ($0.key.rawValue, $0.value) }
                )
            )
        )
    }

    /// Counts without rules: every row is tallied as-is (dupes and validity
    /// are unknowable without the party definition), counties as 0.
    static func countsOnly(log: ContestLog) -> ScoreSnapshot {
        var byMode: [String: Int] = [:]
        var byBand: [String: Int] = [:]
        for qso in log.qsos {
            byMode[qso.modeClass.rawValue, default: 0] += 1
            byBand[qso.band.rawValue, default: 0] += 1
        }
        return ScoreSnapshot(
            validQSOs: log.qsos.count,
            dupeCount: 0,
            invalidModeCount: 0,
            outOfScopeCount: 0,
            qsosByMode: byMode,
            qsosByBand: byBand,
            countiesWorked: 0,
            operatingMinutes: operatingMinutes(timestamps: log.qsos.map(\.timestampUTC)),
            figures: nil
        )
    }

    /// On-air time by the contest off-time convention: gaps of
    /// `breakThreshold` (30 min) or more between consecutive QSOs don't
    /// count. Any contact at all is at least a minute.
    static func operatingMinutes(timestamps: [Date], breakThreshold: TimeInterval = 1800) -> Int {
        guard !timestamps.isEmpty else { return 0 }
        let sorted = timestamps.sorted()
        var active: TimeInterval = 0
        for (earlier, later) in zip(sorted, sorted.dropFirst()) {
            let gap = later.timeIntervalSince(earlier)
            if gap < breakThreshold {
                active += gap
            }
        }
        return max(1, Int((active / 60).rounded()))
    }
}

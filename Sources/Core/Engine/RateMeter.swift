import Foundation

/// QSOs per hour, over the four windows that answer different questions during
/// a contest: is this run still alive, how did the last hour go, how is this
/// clock hour shaping up, and what am I averaging.
///
/// Anchored to the N1MM Logger+ manual, *The Info Window*,
/// <https://n1mmwp.hamdocs.com/manual-windows/info-window/>, fetched
/// 2026-08-01, which shows "the rate for the last 10 QSOs, the last 100 QSOs,
/// the last hour, and the interval since the start of the current clock hour."
///
/// Two of its lessons carry over and one figure does not. A **count-based**
/// window always holds data and widens itself when things go quiet; a
/// **time-based** window is the only kind that falls to zero when the operator
/// stops. Each covers the other's blind spot, so both are here. The 100-QSO
/// window is not: at a state party's 30–50/hr it spans two and a half hours,
/// which is not "recently" but "on average" — and `onAir` computes that
/// properly, excluding off-time, which a fixed QSO count cannot.
///
/// Reads no clock. `now` is passed in, so every figure is a pure function of
/// two arguments and the tests can pin exact numbers instead of ranges.
enum RateMeter {

    /// The current UTC clock hour so far — the interval sponsors tabulate by
    /// and operators talk in ("48 in the 18Z hour").
    struct ThisHour: Equatable {
        var count = 0
        var minutesElapsed = 0
        /// Where the hour lands if the current pace holds. `nil` early in the
        /// hour, when there is not yet enough of it to extrapolate from.
        var projected: Int?
    }

    /// One reading of all four windows.
    ///
    /// Counts are non-optional and extrapolations are optional, which is the
    /// whole display rule in the type system: `lastHour` reading 0 is a true
    /// and useful answer — the run died — while a rate derived from a single
    /// contact is not an answer at all, and shows as `—`.
    struct Reading: Equatable {
        /// Instantaneous rate across the last ten QSOs.
        var lastTen: Int?
        /// QSOs in the trailing 60 minutes. A count, so already per hour.
        var lastHour = 0
        var thisHour = ThisHour()
        /// Average across on-air time, ignoring breaks.
        var onAir: Int?
    }

    /// QSOs in the instantaneous window. N1MM's own choice, and about fifteen
    /// minutes at the rates these parties run.
    private static let instantWindow = 10

    /// No window shorter than this extrapolates. Two QSOs three minutes into
    /// an hour project to 40/hr on almost no evidence, and
    /// `ScoreSnapshot.operatingMinutes` floors at one minute, so without it two
    /// contacts ten seconds apart would claim 120/hr.
    private static let extrapolationFloorMinutes = 5

    static func reading(timestamps: [Date], now: Date) -> Reading {
        // Clock skew or a hand-edited log can stamp a row in the future; it
        // must not inflate a window it has not happened in yet.
        let stamps = timestamps.filter { $0 <= now }.sorted()
        return Reading(
            lastTen: instantaneous(stamps, now: now),
            lastHour: stamps.filter { $0 > now.addingTimeInterval(-3600) }.count,
            thisHour: clockHour(stamps, now: now),
            onAir: average(stamps)
        )
    }

    /// Rate across the last ten QSOs, measured to `now`.
    ///
    /// Two details carry the whole figure. **`n − 1`**: ten QSOs bound nine
    /// intervals, so one a minute is 60/hr, not the 66.7/hr that dividing by
    /// ten would report. **The window ends at `now`, not at the last QSO**: it
    /// then decays on its own while the operator sits idle, rather than
    /// reporting a rate from twenty minutes ago as though it were current —
    /// the one failure that makes a rate meter worse than no rate meter. Where
    /// `now` is the last QSO the two forms are identical.
    private static func instantaneous(_ stamps: [Date], now: Date) -> Int? {
        let window = stamps.suffix(instantWindow)
        guard window.count >= 2, let first = window.first else { return nil }
        let elapsed = now.timeIntervalSince(first)
        // A window made entirely of one county-line contact's rows has no span
        // at all, and dividing by it yields infinity — which formats as a
        // number and reads as a fact.
        guard elapsed > 0 else { return nil }
        return Int((Double(window.count - 1) * 3600 / elapsed).rounded())
    }

    private static func clockHour(_ stamps: [Date], now: Date) -> ThisHour {
        // A UTC hour is always 3600 seconds, so this needs no calendar and has
        // no daylight-saving edge to get wrong.
        let top = Date(
            timeIntervalSince1970: (now.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        )
        let count = stamps.filter { $0 >= top }.count
        let minutes = Int(now.timeIntervalSince(top) / 60)
        var hour = ThisHour(count: count, minutesElapsed: minutes)
        // An hour with nothing in it yet projects nothing — "0 → 0" is noise.
        if count > 0, minutes >= extrapolationFloorMinutes {
            hour.projected = Int((Double(count) * 60 / Double(minutes)).rounded())
        }
        return hour
    }

    /// Average across time actually spent on the air. Wall-clock elapsed would
    /// divide a Saturday-and-Sunday party by its overnight break and report
    /// something near zero, so this defers to the contest off-time convention
    /// already implemented for the dashboard.
    private static func average(_ stamps: [Date]) -> Int? {
        guard stamps.count >= 2 else { return nil }
        let minutes = ScoreSnapshot.operatingMinutes(timestamps: stamps)
        guard minutes >= extrapolationFloorMinutes else { return nil }
        return Int((Double(stamps.count) * 60 / Double(minutes)).rounded())
    }
}

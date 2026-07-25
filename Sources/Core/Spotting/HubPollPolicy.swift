import Foundation

/// When to poll the hub, and how hard to try after a failure.
///
/// Kept separate from the client so the decisions are testable without a
/// network: the client owns the socket, this owns the judgement.
enum HubPollPolicy {

    /// Steady-state cadence. The hub's own page carries a 53-second meta
    /// refresh, so a minute is lighter than leaving one tab open on it.
    static let healthyInterval: TimeInterval = 60
    private static let backoff: [TimeInterval] = [120, 300]

    /// Operators set up before the bell and tear down after it, so the window
    /// is opened either side — the band map is already populated at the start,
    /// and a late log edit does not silently stop the feed.
    static let scheduleMargin: TimeInterval = 30 * 60

    /// Whether the party is close enough to its operating window to be worth
    /// asking the site about.
    ///
    /// The site is a small volunteer-run board on shared hosting; polling it
    /// year-round for an event that runs a dozen hours a year is both rude and
    /// pointless. A party with no banked schedule cannot be gated on one, so
    /// it stays pollable rather than silently losing the feature.
    static func shouldPoll(
        now: Date,
        schedule: [PartyDefinition.ScheduleWindow]?,
        margin: TimeInterval = scheduleMargin
    ) -> Bool {
        guard let schedule, !schedule.isEmpty else { return true }
        return schedule.contains { window in
            now >= window.start.addingTimeInterval(-margin)
                && now <= window.end.addingTimeInterval(margin)
        }
    }

    /// Seconds to wait before the next attempt. Backs off rather than
    /// hammering a struggling server, and stops escalating at five minutes so
    /// a recovery is still noticed promptly.
    static func interval(consecutiveFailures: Int) -> TimeInterval {
        guard consecutiveFailures > 0 else { return healthyInterval }
        return backoff[min(consecutiveFailures - 1, backoff.count - 1)]
    }
}

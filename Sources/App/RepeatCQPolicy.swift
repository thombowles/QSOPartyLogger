import Foundation

/// Repeat CQ is a mode, not a run.
///
/// N1MM Logger+ (Entry Window; keyboard shortcuts, fetched 2026-08-15): Alt+R
/// "toggles repeat mode. Hit Esc or begin entering a callsign to stop repeat
/// temporarily" — "the program remains in CQ repeat mode" — and "after you
/// complete manual input, if you press F1, Repeat CQ will resume."
///
/// So the toggle is the *mode*; the loop is what runs inside it. Any key
/// pauses the loop (`KeyMonitorGate.Response.stopsRepeat`) and leaves the mode
/// armed; this decides the other half — what sending a slot does while it is.
/// `MainView` owns the task; this owns the rule, so the rule has tests.
enum RepeatCQPolicy {
    enum OnSend: Equatable {
        /// One transmission, as with the mode off.
        case sendOnce
        /// Cancel whatever loop is running, take the CQ off the air, and start
        /// the loop again from the top — F1 "starts the CQ over", and keeps it
        /// going.
        case restartLoop
    }

    /// What sending F-key slot `index` (0-based) does. Only Run's F1 is the
    /// CQ; S&P's F1 is "my call", and F2–F8 are single messages the operator
    /// sends between repeats — the exchange to the station who answered.
    static func onSend(index: Int, operatingMode: OperatingMode, armed: Bool) -> OnSend {
        armed && operatingMode == .run && index == 0 ? .restartLoop : .sendOnce
    }

    /// Whether the loop may go on in `mode`. Only Run: leaving it — by ⌘R or
    /// by tuning off the CQ frequency — takes the loop down, or its next pass
    /// would re-resolve slot 0 against the S&P set and key "my call" every
    /// few seconds. N1MM: the function "is automatically turned off when no
    /// longer on the CQ-frequency and the mode changed to S&P."
    static func continues(in mode: OperatingMode) -> Bool {
        mode == .run
    }
}

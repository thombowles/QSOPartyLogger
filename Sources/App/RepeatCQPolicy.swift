import Foundation

/// Repeat CQ is a mode, not a run.
///
/// N1MM Logger+ (Entry Window; keyboard shortcuts, fetched 2026-08-15): Alt+R
/// "toggles repeat mode. Hit Esc or begin entering a callsign to stop repeat
/// temporarily" — "the program remains in CQ repeat mode" — and "after you
/// complete manual input, if you press F1, Repeat CQ will resume." And
/// (fetched 2026-08-16): "When you first press F1 after selecting repeat CQs,
/// an icon will appear … As long as the icon is visible, the CQ will repeat" —
/// selecting the mode keys nothing; F1 does.
///
/// So the toggle is the *mode*; the loop is what runs inside it. Any key but a
/// shortcut pauses the loop (`KeyMonitorGate.Response.stopsRepeat`) and leaves
/// the mode armed; this decides the rest — what the toggle does, what sending
/// a slot does while the mode is armed, and what happens to the mode when
/// something else takes the loop down. `MainView` owns the task; this owns the
/// rule, so the rule has tests.
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

    /// What flipping the toggle does.
    enum OnToggle: Equatable {
        /// On: the mode is armed and nothing goes on the air — F1, the CQ
        /// button or ESM's Return start the loop (Article 11: nothing keys the
        /// radio until an F-key asks; and 2026-08-16, "don't start calling CQ
        /// when I click the repeat CQ button"). Until then the toggle keyed a
        /// CQ the moment it was clicked.
        case armOnly
        /// Off: the loop comes down. A CQ already on the air finishes.
        case cancelLoop
    }

    static func onToggle(armed: Bool) -> OnToggle {
        armed ? .armOnly : .cancelLoop
    }

    /// Everything other than the toggle that takes the loop down.
    enum Interruption: CaseIterable {
        /// ⌘R, or the knob tuning off the CQ frequency (`continues(in:)`).
        case leftRun
        /// The radio moved between CW and phone: F1 now means a different
        /// recording or text, and a loop started on one must not run on into
        /// the other unasked.
        case modeClassChanged
        /// The radio went away.
        case disconnected
    }

    /// Whether the mode survives an interruption. It always does: the loop
    /// pauses, the toggle stays on, and back in Run (or reconnected, or back
    /// on CW) F1 resumes — the mode is the operator's setting, and only the
    /// operator changes it (2026-08-16, "make repeat CQ enable setting
    /// persistent when leaving RUN and coming back"). Until then every
    /// interruption disarmed it, and each contact cost a click on the toggle.
    static func staysArmed(through interruption: Interruption) -> Bool {
        switch interruption {
        case .leftRun, .modeClassChanged, .disconnected: true
        }
    }
}

import Foundation

/// What the declared entry category permits, and what the app says about it.
///
/// **An entry that claims `CATEGORY-ASSISTED: NON-ASSISTED` takes no incoming
/// spots at all.** The cluster will not connect, auto-connect does not fire,
/// hub polling does not start, and declaring NON-ASSISTED mid-contest
/// disconnects whatever is running and clears the network spots off the band
/// map. Prevention rather than a warning after the fact: a log that has
/// already taken spots cannot be made un-assisted, so the honest moment to
/// act is before the first one arrives.
///
/// Party-neutral. The ASSISTED/NON-ASSISTED split is universal Cabrillo V3
/// and the rule is keyed on the operator's own claim, never on a sponsor's
/// rules — pinned by `SpottingPolicyTests`, which walks the whole catalog to
/// prove no visible string names a party. (NAQP rule 5A(ii) — "access to
/// spotting information … is prohibited" for Single Operator — is the wording
/// that forced the feature, not a branch condition.)
///
/// Two things deliberately stay outside the block. **Self-spotting** sends
/// rather than receives, and sponsors split on whether it is allowed at all,
/// so a party-neutral rule cannot govern it. **Contacts from your own log**
/// on the band map are not spotting information "obtained from any source
/// other than the station operator", so they survive the sweep.
///
/// Every rule and every string lives here rather than in a view body, so the
/// contract is assertable — the `ContestNotice` / `KeyMonitorGate` pattern.
enum SpottingPolicy {

    // MARK: Prevention

    /// The whole rule: only an assisted entry may take spots.
    static func allowsIncomingSpots(_ claim: StationProfile.CategoryAssisted) -> Bool {
        claim == .assisted
    }

    /// Whether the hub poller should be running. The hub is a spotting
    /// network too — blocking the telnet cluster alone would leave the same
    /// assistance arriving by the other door — and it still answers to the
    /// operator's own setting and to whether the party has a page at all.
    static func hubShouldPoll(
        enabled: Bool, hasSource: Bool, claim: StationProfile.CategoryAssisted
    ) -> Bool {
        enabled && hasSource && allowsIncomingSpots(claim)
    }

    /// Why the connect controls are switched off. A blocked control that does
    /// not say why is a bug report, so this names the claim, the control that
    /// changes it, and where that control lives.
    static let blockedReason = "Spotting is off: this entry is declared "
        + "NON-ASSISTED, and taking spots would invalidate that claim. Change "
        + "Assisted in Contest Setup to use a cluster."

    /// Under the Assisted picker, where the choice is actually made — the
    /// consequence stated before it bites.
    static let setupCaution = "NON-ASSISTED switches spotting off: no cluster, "
        + "no hub spots, and an open connection is dropped."

    // MARK: The record prevention cannot reach

    /// Prevention stops the future, not the past. Spots taken legitimately
    /// under ASSISTED stay on the log's record, so switching the claim to
    /// NON-ASSISTED afterwards still has to be visible — and under prevention
    /// that is the *only* way this badge can appear, which makes it a precise
    /// signal rather than a nag.
    static let badge = "SPOTS ALREADY USED — ENTRY NOW SAYS NON-ASSISTED"

    static let detail = "Spots reached this log while it was declared "
        + "ASSISTED, and that is on the record. Spotting is now switched off, "
        + "but the contacts already made with it remain — restore ASSISTED in "
        + "Contest Setup, or submit knowing the log carries them. Dismiss with "
        + "⌘. (it returns at Cabrillo export)."

    /// The badge shows while the record contradicts the claim and the
    /// operator has not waved it off this sitting.
    static func isVisible(conflict: Bool, dismissed: Bool) -> Bool {
        conflict && !dismissed
    }

    /// The new `dismissed` state after an event that must re-surface a live
    /// warning — exporting Cabrillo, where the claim ships, or the conflict
    /// arising again. A live conflict stands the badge back up; otherwise the
    /// dismissal is the operator's and stays.
    static func rearm(dismissed: Bool, conflict: Bool) -> Bool {
        conflict ? false : dismissed
    }
}

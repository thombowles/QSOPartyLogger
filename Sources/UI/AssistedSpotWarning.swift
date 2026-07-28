import Foundation

/// The decision layer behind the assisted-category warning: spots reached a
/// log whose Contest Setup declares `CATEGORY-ASSISTED: NON-ASSISTED`.
///
/// Every string and every show/hide rule lives here rather than in a view
/// body, so the contract is assertable (`AssistedSpotWarningTests`) — the
/// `PartyNotice` / `KeyMonitorGate` pattern. The views do nothing but read
/// this and flip one session-scoped `dismissed` bit.
///
/// The warning is advice, never a gate: the Cabrillo export proceeds
/// untouched, the file is never rewritten, and no party is consulted — the
/// ASSISTED/NON-ASSISTED split is universal Cabrillo V3. (NAQP rule 5A(ii),
/// which prohibits Single-Op access to "spotting networks, skimmers", is the
/// provenance that forced the feature, not a branch condition.)
enum AssistedSpotWarning {

    /// The strip badge, styled like the COUNTY LINE capsule beside it.
    static let badge = "SPOTS USED — ENTRY SAYS NON-ASSISTED"

    /// The badge's tooltip: what happened, what it costs, and both exits.
    static let detail = "Cluster or hub spots reached this log, but Contest "
        + "Setup declares CATEGORY-ASSISTED: NON-ASSISTED. Sponsors score "
        + "spotting-network use as Assisted — switch the category in Contest "
        + "Setup, or dismiss with ⌘. (the warning returns at Cabrillo export)."

    /// By the control that creates the condition: shown in the cluster
    /// popover while the profile claims NON-ASSISTED, before any spot lands.
    static let connectCaution = "Contest Setup declares NON-ASSISTED — spots "
        + "from this connection will mark this log as assisted."

    /// By the control that fixes it: shown under the Assisted picker when
    /// this log has already used spots and NON-ASSISTED is selected.
    static let setupCaution = "Spots already reached this log — sponsors "
        + "count spotting-network use as Assisted."

    /// The badge shows while the conflict stands and the operator has not
    /// waved it off this sitting.
    static func isVisible(conflict: Bool, dismissed: Bool) -> Bool {
        conflict && !dismissed
    }

    /// The new `dismissed` state after an event that must re-surface a live
    /// warning — exporting Cabrillo (where the claim ships), or the conflict
    /// returning after the profile flips away and back. A live conflict
    /// stands the warning back up; otherwise the dismissal is the
    /// operator's and stays.
    static func rearm(dismissed: Bool, conflict: Bool) -> Bool {
        conflict ? false : dismissed
    }
}

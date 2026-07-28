import XCTest
@testable import QSOPartyLogger

/// The strip's assisted-category warning. A SwiftUI body cannot be asserted
/// on, so every string and every show/hide rule lives in `AssistedSpotWarning`
/// (the `PartyNotice` / `KeyMonitorGate` pattern) and the contract is pinned
/// here.
///
/// The behavior these guard: spots reached a log whose Contest Setup declares
/// CATEGORY-ASSISTED: NON-ASSISTED (NAQP rule 5A(ii) prohibits exactly that
/// access for Single Op — the provenance, not a branch condition). The warning
/// is inline and non-blocking, dismissable from the keyboard, and stands back
/// up where the claim ships: the Cabrillo export.
final class AssistedSpotWarningTests: XCTestCase {

    func testVisibleOnlyWhileTheConflictStandsUndismissed() {
        XCTAssertTrue(AssistedSpotWarning.isVisible(conflict: true, dismissed: false))
        XCTAssertFalse(AssistedSpotWarning.isVisible(conflict: true, dismissed: true),
                       "dismissing must actually dismiss — the warning is advice, not a gate")
        XCTAssertFalse(AssistedSpotWarning.isVisible(conflict: false, dismissed: false),
                       "no conflict, no warning")
        XCTAssertFalse(AssistedSpotWarning.isVisible(conflict: false, dismissed: true))
    }

    /// One rule serves both re-arm events — the Cabrillo export, and a
    /// conflict that returns after the profile flips away and back: a live
    /// conflict stands the warning back up; anything else leaves the
    /// operator's dismissal alone.
    func testRearmClearsTheDismissalOnlyUnderALiveConflict() {
        XCTAssertFalse(AssistedSpotWarning.rearm(dismissed: true, conflict: true),
                       "exporting Cabrillo must re-surface a standing conflict")
        XCTAssertTrue(AssistedSpotWarning.rearm(dismissed: true, conflict: false),
                      "no conflict — nothing to re-surface, the dismissal stands")
        XCTAssertFalse(AssistedSpotWarning.rearm(dismissed: false, conflict: true))
        XCTAssertFalse(AssistedSpotWarning.rearm(dismissed: false, conflict: false))
    }

    func testBadgeNamesTheClaimItContradicts() {
        XCTAssertTrue(AssistedSpotWarning.badge.contains("NON-ASSISTED"),
                      "the badge must say which Cabrillo claim is in trouble")
        XCTAssertTrue(AssistedSpotWarning.badge.localizedCaseInsensitiveContains("spots"),
                      "and what contradicts it")
    }

    /// The tooltip carries the operator's two exits: fix the category where
    /// it lives, or dismiss from the keyboard.
    func testDetailNamesTheFixAndTheKey() {
        XCTAssertTrue(AssistedSpotWarning.detail.contains("Contest Setup"),
                      "the fix lives in Contest Setup")
        XCTAssertTrue(AssistedSpotWarning.detail.contains("⌘."),
                      "the keyboard path is part of the contract (Article 7)")
    }

    func testTheCautionsByTheControlsAreNotEmpty() {
        XCTAssertFalse(AssistedSpotWarning.connectCaution.isEmpty,
                       "the cluster popover warns before the first spot arrives")
        XCTAssertFalse(AssistedSpotWarning.setupCaution.isEmpty,
                       "the Assisted picker warns where the fix happens")
    }

    /// Party-neutral by assertion, not by promise: CATEGORY-ASSISTED is
    /// universal Cabrillo, and no string an operator sees may name a sponsor
    /// or a party — the same discipline Article 10 applies to radio names.
    func testNoOperatorVisibleStringNamesAParty() {
        let strings = [
            AssistedSpotWarning.badge,
            AssistedSpotWarning.detail,
            AssistedSpotWarning.connectCaution,
            AssistedSpotWarning.setupCaution,
        ]
        for party in PartyCatalog.loadBundled() {
            for string in strings {
                XCTAssertFalse(
                    string.localizedCaseInsensitiveContains(party.name),
                    "\"\(string)\" names \(party.name) — the warning must stay party-neutral"
                )
            }
        }
    }
}

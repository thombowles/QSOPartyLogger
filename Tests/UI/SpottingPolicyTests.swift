import XCTest
@testable import QSOPartyLogger

/// What the declared entry category permits, and what the app says about it.
///
/// The rule: an entry that claims `CATEGORY-ASSISTED: NON-ASSISTED` gets no
/// incoming spots at all — the cluster will not connect, auto-connect does
/// not fire, hub polling does not start, and declaring NON-ASSISTED
/// mid-contest disconnects what is running. Prevention rather than a warning
/// after the fact, because a log that has already taken spots cannot be
/// un-assisted.
///
/// Party-neutral: the ASSISTED/NON-ASSISTED split is universal Cabrillo V3,
/// and the rule is keyed on the operator's own claim, never on a sponsor's
/// rules. (NAQP 5A(ii) is the wording that forced the feature, not a branch
/// condition.)
///
/// A SwiftUI body cannot be asserted on, so every rule and every string lives
/// in `SpottingPolicy` — the `PartyNotice` / `KeyMonitorGate` pattern.
final class SpottingPolicyTests: XCTestCase {

    // MARK: Prevention

    func testOnlyAnAssistedEntryMayTakeIncomingSpots() {
        XCTAssertTrue(SpottingPolicy.allowsIncomingSpots(.assisted))
        XCTAssertFalse(SpottingPolicy.allowsIncomingSpots(.nonAssisted),
                       "the whole point: NON-ASSISTED means the feeds never run")
    }

    /// The hub is a spotting network too — blocking the telnet cluster alone
    /// would leave the same assistance arriving by the other door.
    func testHubPollingObeysTheSameClaim() {
        XCTAssertTrue(
            SpottingPolicy.hubShouldPoll(enabled: true, hasSource: true, claim: .assisted)
        )
        XCTAssertFalse(
            SpottingPolicy.hubShouldPoll(enabled: true, hasSource: true, claim: .nonAssisted),
            "hub spots are spotting information whatever the source"
        )
        XCTAssertFalse(
            SpottingPolicy.hubShouldPoll(enabled: false, hasSource: true, claim: .assisted),
            "the operator's own setting still wins"
        )
        XCTAssertFalse(
            SpottingPolicy.hubShouldPoll(enabled: true, hasSource: false, claim: .assisted),
            "a party with no hub page polls nothing"
        )
    }

    /// A blocked control that does not say why is a bug report. This one names
    /// the setting and where it lives.
    func testBlockedReasonNamesTheFixAndWhereItLives() {
        XCTAssertTrue(SpottingPolicy.blockedReason.contains("NON-ASSISTED"),
                      "name the claim that is doing the blocking")
        XCTAssertTrue(SpottingPolicy.blockedReason.contains("Contest Setup"),
                      "and where to change it")
        XCTAssertTrue(SpottingPolicy.blockedReason.contains("Assisted"),
                      "and which control")
    }

    func testTheSetupCautionIsNotEmpty() {
        XCTAssertFalse(SpottingPolicy.setupCaution.isEmpty,
                       "the Assisted picker states the consequence before it bites")
    }

    // MARK: The record prevention cannot reach

    /// Prevention stops the future, not the past: spots taken legitimately
    /// under ASSISTED stay on the log's record, so switching the claim to
    /// NON-ASSISTED afterwards still has to be visible. This is the only way
    /// the badge can appear once prevention is in force — which makes it a
    /// precise signal rather than a nag.
    func testBadgeShowsOnlyWhileTheRecordContradictsTheClaim() {
        XCTAssertTrue(SpottingPolicy.isVisible(conflict: true, dismissed: false))
        XCTAssertFalse(SpottingPolicy.isVisible(conflict: true, dismissed: true),
                       "dismissing must actually dismiss — the badge is advice, not a gate")
        XCTAssertFalse(SpottingPolicy.isVisible(conflict: false, dismissed: false))
        XCTAssertFalse(SpottingPolicy.isVisible(conflict: false, dismissed: true))
    }

    func testRearmClearsTheDismissalOnlyUnderALiveConflict() {
        XCTAssertFalse(SpottingPolicy.rearm(dismissed: true, conflict: true),
                       "exporting Cabrillo must re-surface a standing conflict")
        XCTAssertTrue(SpottingPolicy.rearm(dismissed: true, conflict: false),
                      "no conflict — nothing to re-surface, the dismissal stands")
        XCTAssertFalse(SpottingPolicy.rearm(dismissed: false, conflict: true))
        XCTAssertFalse(SpottingPolicy.rearm(dismissed: false, conflict: false))
    }

    func testBadgeNamesTheClaimItContradicts() {
        XCTAssertTrue(SpottingPolicy.badge.contains("NON-ASSISTED"))
        XCTAssertTrue(SpottingPolicy.badge.localizedCaseInsensitiveContains("spots"))
    }

    func testDetailNamesTheFixAndTheKey() {
        XCTAssertTrue(SpottingPolicy.detail.contains("Contest Setup"))
        XCTAssertTrue(SpottingPolicy.detail.contains("⌘."),
                      "the keyboard path is part of the contract (Article 7)")
    }

    // MARK: Party neutrality, asserted rather than promised

    func testNoOperatorVisibleStringNamesAParty() {
        let strings = [
            SpottingPolicy.badge,
            SpottingPolicy.detail,
            SpottingPolicy.blockedReason,
            SpottingPolicy.setupCaution,
        ]
        for party in PartyCatalog.loadBundled() {
            for string in strings {
                XCTAssertFalse(
                    string.localizedCaseInsensitiveContains(party.name),
                    "\"\(string)\" names \(party.name) — the policy must stay party-neutral"
                )
            }
        }
    }
}

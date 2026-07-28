import XCTest
@testable import QSOPartyLogger

/// The per-party caveat roster, in the spirit of `PartyCatalogTests`' partial
/// roster: a party's warning status changes only on purpose.
final class CaveatRosterTests: XCTestCase {

    private var parties: [PartyDefinition] { PartyCatalog.loadBundled() }

    /// The 22 parties where this app will mis-score or mis-export, as against
    /// the 39 that `verified: partial` used to warn about. A new entry here
    /// means a real scoring gap was found; a departure means one was closed.
    private static let badges: Set<String> = [
        "arqp", "deqp", "fqp", "idqp", "ilqp", "in7qpne", "kyqp", "laqp",
        "moqp", "msqp", "naqpcw", "naqpssb", "ncqp", "ndqp", "neqp",
        "nmqp", "oqp", "qcqp", "scqp", "vaqp", "vtqp", "warun", "wiqp",
    ]

    func testBadgeRosterIsExactlyAsExpected() {
        let actual = Set(parties.filter { !$0.blockingCaveats.isEmpty }.map(\.id))
        XCTAssertEqual(actual, Self.badges)
    }

    /// The whole point of the redesign. If this ever climbs back toward the
    /// catalogue size, the classification has stopped discriminating.
    ///
    /// **Amended 2026-07-27**: the bar was `badging < count / 2`, and the two
    /// NAQP parties tripped it at exactly 23 of 46 — each carries the same
    /// scoreAffecting prefix-shadowing caveat the Salmon Run set the
    /// precedent for, so the classification did not get looser, the
    /// catalogue got two honest entries longer. The guard it exists for is
    /// the old 39-of-46 (84%) failure mode; three in five keeps real
    /// headroom below that while not tripping on catalogue parity.
    func testBadgesStayWellShortOfTheCatalogueSize() {
        let badging = parties.filter { !$0.blockingCaveats.isEmpty }.count
        XCTAssertLessThan(Double(badging), Double(parties.count) * 0.6)
    }

    /// No party's export is blocked any more. Minnesota was the one — the
    /// exchange name had no field and the sponsor's robot expects it in ex1 —
    /// until name exchanges landed 2026-07-27 and closed it. A party joining
    /// this list means a submission-blocking gap shipped; treat it as the
    /// alarm it is.
    func testNoPartyIsExportBlocked() {
        let blocked = parties
            .filter { $0.caveats.contains { $0.kind == .exportBlocking } }
            .map(\.id)
        XCTAssertEqual(blocked, [])
    }

    /// Every party is classified. An unclassified one would silently fall back
    /// to `operatorAlerts`, which is right for a user-installed file and wrong
    /// for a bundled one.
    func testEveryBundledPartyWithMarkedNotesHasCaveats() {
        for party in parties where !party.operatorAlerts.isEmpty {
            XCTAssertFalse(
                party.caveats.isEmpty,
                "\(party.id) has OPEN QUESTION / KNOWN LIMITATION prose but no typed caveats"
            )
        }
    }

    /// `summary` is what reaches the sheet, so it has to be a line rather than
    /// a paragraph, and `detail` must not be an empty string.
    func testSummariesAreShortAndDetailsAreNonEmpty() {
        for party in parties {
            for caveat in party.caveats {
                XCTAssertFalse(caveat.summary.isEmpty, "\(party.id): empty summary")
                XCTAssertLessThan(
                    caveat.summary.count, 160,
                    "\(party.id): summary is a paragraph, not a line — \(caveat.summary)"
                )
                if let detail = caveat.detail {
                    XCTAssertFalse(detail.isEmpty, "\(party.id): empty detail")
                }
            }
        }
    }

    /// A fully verified party can still carry a caveat — the Salmon Run does,
    /// and NAQP's Dominican-Republic shadow is the same prefix-collision
    /// class — so the two statuses must stay independent.
    func testVerifiedPartiesMayStillCarryCaveats() {
        let verifiedWithCaveats = parties
            .filter { !$0.isPartiallyVerified && !$0.caveats.isEmpty }
            .map(\.id)
        XCTAssertEqual(verifiedWithCaveats, ["naqpcw", "naqpssb", "warun"])
    }
}

import XCTest
@testable import QSOPartyLogger

/// What the setup sheet actually shows when a party is `verified: partial`.
///
/// `notes` is a maintainer's provenance record — long, written in shouting
/// capitals so it can be audited in a wall of prose. It is the wrong thing to
/// put in front of an operator mid-contest, and until this change the sheet did
/// exactly that: `openQuestions` ran from the first marker to the **end** of the
/// notes, so picking Nebraska showed the open question *plus* every paragraph
/// that followed it, in caption text.
final class OperatorAlertTests: XCTestCase {

    /// One short line per thing to act on, and nothing else.
    func testAnAlertIsOneHeadlineNotTheWholeParagraph() throws {
        let neqp = try XCTUnwrap(PartyCatalog.party(id: "neqp"))
        let alerts = neqp.operatorAlerts

        XCTAssertEqual(alerts.first, "Open Question: is the start 1400Z or 1300Z?")
        // The paragraph that used to follow it must not be dragged along.
        XCTAssertFalse(alerts[0].contains("WA7BNM"))
        XCTAssertFalse(alerts[0].contains("Article 19"))
        for alert in alerts {
            XCTAssertLessThan(alert.count, 400, "an alert is a line, not an essay: \(alert)")
        }
    }

    /// A question stays a question. Splitting on "." alone ran straight past
    /// "1400Z or 1300Z?" and swept in the next paragraph.
    func testQuestionsKeepTheirQuestionMark() throws {
        let fqp = try XCTUnwrap(PartyCatalog.party(id: "fqp"))
        XCTAssertTrue(fqp.operatorAlerts.contains {
            $0 == "Open Question: is the out-of-state restriction stated or only implied?"
        }, "got: \(fqp.operatorAlerts)")
    }

    /// The maintainer's shouting is lowered, but genuine abbreviations survive.
    func testShoutingIsLoweredAndAbbreviationsSurvive() throws {
        let ndqp = try XCTUnwrap(PartyCatalog.party(id: "ndqp"))
        let joined = ndqp.operatorAlerts.joined(separator: " ")
        XCTAssertFalse(joined.contains("KNOWN LIMITATION"), "the marker itself is title-cased")
        XCTAssertFalse(joined.contains(" THE "), "shouting should be lowered")
        XCTAssertTrue(joined.contains("DX") || joined.contains("QSO") || joined.contains("FT8"),
                      "technical abbreviations must survive: \(joined)")
    }

    /// **Quoted spans are the sponsor's own words** and must not be altered —
    /// lowering their capitals would misquote them.
    func testQuotationsAreNeverAltered() throws {
        let deqp = try XCTUnwrap(PartyCatalog.party(id: "deqp"))
        let joined = deqp.operatorAlerts.joined(separator: " ")
        XCTAssertTrue(joined.contains("'1A DE'"), "an exchange, not shouting: \(joined)")
        XCTAssertFalse(joined.contains("'1A de'"))
    }

    /// A partial party should have something for the operator to act on.
    ///
    /// **Two do not**, and both are already recorded as defects rather than
    /// discovered here: TQP's caveat is written as prose inside its provenance
    /// paragraph instead of under the `OPEN QUESTION` marker Article 3 requires
    /// (see the Deferred-gaps list in `docs/parties/WORKLIST-2026.md`), and
    /// Indiana genuinely has no open question — it is partial only by this
    /// repo's default for a party read from one live page.
    ///
    /// The sheet copes either way: with no alerts it says the rules could not be
    /// fully confirmed and stops, rather than showing a bare warning triangle.
    /// This test pins the exception list so a third party joining it is a
    /// visible change.
    func testEveryPartialPartyHasSomethingToSayExceptTwoKnownCases() {
        let known: Set<String> = ["tqp", "inqp"]
        var silent: Set<String> = []
        for party in PartyCatalog.loadBundled()
        where party.isPartiallyVerified && party.operatorAlerts.isEmpty {
            silent.insert(party.id)
        }
        XCTAssertEqual(silent, known,
                       "a party gained or lost its operator alerts — check deliberately")
    }

    /// **A verified party can still have something to say.** The Salmon Run's
    /// rules are fully confirmed, yet it carries a modelling limitation the
    /// operator should know about — so alerts are not tied to partial
    /// verification, and the sheet shows them either way, with the warning tone
    /// reserved for parties whose rules could not be confirmed.
    func testAVerifiedPartyCanStillCarryALimitation() throws {
        let warun = try XCTUnwrap(PartyCatalog.party(id: "warun"))
        XCTAssertFalse(warun.isPartiallyVerified, "the Salmon Run's rules are confirmed")
        XCTAssertFalse(warun.operatorAlerts.isEmpty,
                       "…and it still has a limitation worth showing")
    }

    /// **The two accessors have different jobs and both are kept.**
    /// `openQuestions` is the raw provenance tail, for auditing; `operatorAlerts`
    /// is what the sheet shows. Confusing them is what put the whole record on
    /// screen in the first place.
    func testTheAuditTrailAndTheOperatorViewAreDifferentThings() throws {
        let gaqp = try XCTUnwrap(PartyCatalog.party(id: "gaqp"))
        XCTAssertEqual(gaqp.operatorAlerts.count, 2, "Georgia has two open questions")

        let raw = try XCTUnwrap(gaqp.openQuestions)
        XCTAssertTrue(raw.contains("OPEN QUESTION 1"), "the record keeps its markers verbatim")
        XCTAssertGreaterThan(raw.count, gaqp.operatorAlerts.joined().count,
                             "the record is the longer of the two")
    }
}

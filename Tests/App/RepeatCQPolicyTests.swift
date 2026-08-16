import XCTest
@testable import QSOPartyLogger

/// Repeat CQ is a mode, not a run — N1MM's Alt+R: "You can stop repeat CQing
/// by beginning to enter a call-sign, or by hitting Escape … the program
/// remains in CQ repeat mode … After you complete manual input, if you press
/// F1, Repeat CQ will resume." (n1mmwp.hamdocs.com, Entry Window, fetched
/// 2026-08-15.) The gate already says a keystroke pauses the loop; this is
/// the other half — what sending F1 does while the mode is armed.
final class RepeatCQPolicyTests: XCTestCase {

    /// The report: "the CQ repeat disengages after I make a QSO. It should
    /// continue repeating CQ once I hit F1 or CQ again."
    func testF1InRunWithTheModeArmedRestartsTheLoop() {
        XCTAssertEqual(
            RepeatCQPolicy.onSend(index: 0, operatingMode: .run, armed: true),
            .restartLoop
        )
    }

    /// The same F1 with the mode off is one CQ, as it always was.
    func testF1WithTheModeOffSendsOnce() {
        XCTAssertEqual(
            RepeatCQPolicy.onSend(index: 0, operatingMode: .run, armed: false),
            .sendOnce
        )
    }

    /// Only F1 is the CQ. F2 during a paused loop is the exchange, once; the
    /// mode stays armed for the next F1.
    func testOtherSlotsSendOnceEvenWhenArmed() {
        for index in 1..<8 {
            XCTAssertEqual(
                RepeatCQPolicy.onSend(index: index, operatingMode: .run, armed: true),
                .sendOnce, "F\(index + 1)"
            )
        }
    }

    /// S&P F1 is "my call", never a CQ — no loop, whatever the toggle says.
    func testSearchAndPounceNeverLoops() {
        XCTAssertEqual(
            RepeatCQPolicy.onSend(index: 0, operatingMode: .searchPounce, armed: true),
            .sendOnce
        )
    }

    /// N1MM: Repeat CQ "is automatically turned off when no longer on the
    /// CQ-frequency and the mode changed to S&P." Leaving Run — by ⌘R or by
    /// tuning off the CQ frequency — takes the loop down; left running, its
    /// next pass would key S&P's F1, which is "my call", not a CQ.
    func testTheLoopContinuesOnlyInRun() {
        XCTAssertTrue(RepeatCQPolicy.continues(in: .run))
        XCTAssertFalse(RepeatCQPolicy.continues(in: .searchPounce))
    }
}

import XCTest
@testable import QSOPartyLogger

/// ⇧⌘← / ⇧⌘→: the VFO moves 100 Hz. The only decision worth pinning is
/// what a nudge is *relative to*: the polled frequency lags the radio by up
/// to a poll interval, so two quick presses computed from it would set the
/// same target twice and move once. A recent target wins over a stale poll.
@MainActor
final class RadioControllerNudgeTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    func testFirstNudgeStartsFromThePolledFrequency() {
        XCTAssertEqual(
            RadioController.nudgeBase(polledHz: 14_322_000, lastTargetHz: nil, lastIssuedAt: nil, now: t0),
            14_322_000
        )
    }

    /// Two presses inside a poll interval: the second builds on the first's
    /// target, not on the frequency the radio reported before either.
    func testAQuickSecondNudgeBuildsOnTheFirst() {
        XCTAssertEqual(
            RadioController.nudgeBase(
                polledHz: 14_322_000, lastTargetHz: 14_322_100,
                lastIssuedAt: t0, now: t0.addingTimeInterval(0.2)),
            14_322_100
        )
    }

    /// After the window the knob may have moved: trust the radio again.
    func testAnOldTargetIsForgotten() {
        XCTAssertEqual(
            RadioController.nudgeBase(
                polledHz: 14_250_000, lastTargetHz: 14_322_100,
                lastIssuedAt: t0, now: t0.addingTimeInterval(5)),
            14_250_000
        )
    }

    /// No frequency from the radio yet: nothing to nudge from.
    func testNoPolledFrequencyAndNoTargetMeansNoBase() {
        XCTAssertNil(RadioController.nudgeBase(polledHz: nil, lastTargetHz: nil, lastIssuedAt: nil, now: t0))
    }

    /// A target survives a poll gap: mid-burst the radio may not have
    /// answered yet, and the burst must still add up.
    func testARecentTargetStandsInForAMissingPoll() {
        XCTAssertEqual(
            RadioController.nudgeBase(
                polledHz: nil, lastTargetHz: 7_040_000,
                lastIssuedAt: t0, now: t0.addingTimeInterval(0.5)),
            7_040_000
        )
    }

    /// The window is short on purpose: long enough for a burst of presses,
    /// shorter than any deliberate turn of the knob between them.
    func testTheWindowIsAboutOneAndAHalfSeconds() {
        XCTAssertEqual(RadioController.nudgeWindow, 1.5, accuracy: 0.001)
    }

    /// Disconnected, the controller does nothing and says so — the view moves
    /// its own cursor instead.
    func testNudgeWithoutARadioReportsNothingMoved() {
        let radio = RadioController()
        XCTAssertNil(radio.nudgeFrequency(byHz: 100))
    }
}

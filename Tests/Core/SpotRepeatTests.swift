import XCTest
@testable import QSOPartyLogger

/// An identical spot repeated inside five minutes is a stuck key, not news —
/// and every network a spot goes to is public.
final class SpotRepeatTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    func testNothingSentBeforeIsNeverARepeat() {
        XCTAssertFalse(SpotRepeat.isRepeat("a", of: nil, lastSentAt: nil, now: t0))
        XCTAssertFalse(SpotRepeat.isRepeat("a", of: "a", lastSentAt: nil, now: t0))
    }

    func testTheSamePayloadInsideTheWindowIsARepeat() {
        XCTAssertTrue(SpotRepeat.isRepeat("a", of: "a", lastSentAt: t0, now: t0.addingTimeInterval(299)))
    }

    func testTheSamePayloadAfterTheWindowIsNotARepeat() {
        XCTAssertFalse(SpotRepeat.isRepeat("a", of: "a", lastSentAt: t0, now: t0.addingTimeInterval(300)))
    }

    /// A changed frequency, county or park is precisely the moment a re-spot
    /// matters.
    func testAChangedPayloadIsNeverARepeat() {
        XCTAssertFalse(SpotRepeat.isRepeat("b", of: "a", lastSentAt: t0, now: t0.addingTimeInterval(1)))
    }

    func testTheHubGuardIsTheSameGuard() {
        XCTAssertEqual(HubSelfSpot.duplicateWindow, SpotRepeat.window)
    }
}

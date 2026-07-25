import XCTest
@testable import QSOPartyLogger

/// When to poll the hub, and how hard to try after a failure.
///
/// The site is a small volunteer-run board on shared hosting. Polling it
/// year-round for an event that runs a dozen hours a year is both rude and
/// pointless, and the party definition already knows the window.
final class HubPollPolicyTests: XCTestCase {

    private static func utc(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// The real 2026 Alabama window, straight out of `alqp.json`.
    private static let alabama = [
        PartyDefinition.ScheduleWindow(
            start: utc("2026-07-25T15:00:00Z"),
            end: utc("2026-07-26T03:00:00Z")
        )
    ]
    private var alabama: [PartyDefinition.ScheduleWindow] { Self.alabama }

    func testPollsInsideThePartysOwnWindow() {
        XCTAssertTrue(HubPollPolicy.shouldPoll(now: Self.utc("2026-07-25T22:34:12Z"),
                                               schedule: alabama))
    }

    func testDoesNotPollLongBeforeTheParty() {
        XCTAssertFalse(HubPollPolicy.shouldPoll(now: Self.utc("2026-07-20T12:00:00Z"),
                                                schedule: alabama))
    }

    func testDoesNotPollAfterThePartyEnds() {
        XCTAssertFalse(HubPollPolicy.shouldPoll(now: Self.utc("2026-07-26T04:00:00Z"),
                                                schedule: alabama))
    }

    /// Operators set up before the bell and tear down after it. A margin
    /// either side means the band map is already populated at the start, and
    /// a late log edit does not silently stop the feed.
    func testAllowsAMarginEitherSide() {
        XCTAssertTrue(HubPollPolicy.shouldPoll(now: Self.utc("2026-07-25T14:45:00Z"),
                                               schedule: alabama))
        XCTAssertTrue(HubPollPolicy.shouldPoll(now: Self.utc("2026-07-26T03:15:00Z"),
                                               schedule: alabama))
    }

    /// A party with no banked schedule cannot be gated on one. Refusing to
    /// poll would silently disable the feature for it.
    func testPartyWithoutAScheduleIsAlwaysPollable() {
        XCTAssertTrue(HubPollPolicy.shouldPoll(now: Self.utc("2026-01-01T00:00:00Z"),
                                               schedule: nil))
        XCTAssertTrue(HubPollPolicy.shouldPoll(now: Self.utc("2026-01-01T00:00:00Z"),
                                               schedule: []))
    }

    /// A healthy feed polls at the site's own cadence — its page carries a
    /// 53-second meta refresh, so a minute is lighter than one open tab.
    func testHealthyIntervalMatchesTheSitesOwnCadence() {
        XCTAssertEqual(HubPollPolicy.interval(consecutiveFailures: 0), 60)
    }

    /// Failures back off rather than hammering a struggling server, and stop
    /// escalating at five minutes so recovery is still noticed promptly.
    func testFailuresBackOffAndThenHold() {
        XCTAssertEqual(HubPollPolicy.interval(consecutiveFailures: 1), 120)
        XCTAssertEqual(HubPollPolicy.interval(consecutiveFailures: 2), 300)
        XCTAssertEqual(HubPollPolicy.interval(consecutiveFailures: 9), 300)
    }
}

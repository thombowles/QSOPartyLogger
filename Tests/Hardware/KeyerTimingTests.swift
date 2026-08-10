import XCTest
@testable import QSOPartyLogger

final class KeyerTimingTests: XCTestCase {

    func testDitDuration() {
        XCTAssertEqual(KeyerTiming.ditMs(wpm: 20), 60, accuracy: 0.001)
        XCTAssertEqual(KeyerTiming.ditMs(wpm: 30), 40, accuracy: 0.001)
        XCTAssertEqual(KeyerTiming.ditMs(wpm: 12), 100, accuracy: 0.001)
    }

    /// Schedules are in dit units and take no speed at all — the property that
    /// lets a message change speed while it is being sent.
    func testLetterEIsOneDit() {
        XCTAssertEqual(KeyerTiming.schedule(text: "E"), [.init(keyDown: true, dits: 1)])
    }

    func testLetterNTiming() {
        // N = dah, gap, dit: 3 dits down, 1 up, 1 down.
        XCTAssertEqual(
            KeyerTiming.schedule(text: "N"),
            [
                .init(keyDown: true, dits: 3),
                .init(keyDown: false, dits: 1),
                .init(keyDown: true, dits: 1),
            ]
        )
    }

    func testInterCharacterGapIsThreeDits() {
        XCTAssertEqual(
            KeyerTiming.schedule(text: "EE"),
            [
                .init(keyDown: true, dits: 1),
                .init(keyDown: false, dits: 3),
                .init(keyDown: true, dits: 1),
            ]
        )
    }

    func testWordGapIsSevenDits() {
        XCTAssertEqual(KeyerTiming.schedule(text: "E E")[1], .init(keyDown: false, dits: 7))
    }

    /// The dit-unit schedule still renders to the millisecond timings the
    /// keyer used to bake in — 20 WPM is 60 ms a dit, so N is 180/60/60.
    func testScheduleRendersToMillisecondsAtASpeed() {
        let n = KeyerTiming.schedule(text: "N")
        XCTAssertEqual(KeyerTiming.durationMs(n, wpm: 20), 300, accuracy: 0.001)
        XCTAssertEqual(n.map { $0.dits * KeyerTiming.ditMs(wpm: 20) }, [180, 60, 60])
    }

    func testParisIsExactlyThreeSecondsAt20WPM() {
        // PARIS = 50 dit units; at 20 WPM (60 ms/dit) one word = 3000 ms
        // including the trailing word gap.
        let sending = KeyerTiming.totalDurationMs(text: "PARIS", wpm: 20)
        XCTAssertEqual(sending + 7 * 60, 3000, accuracy: 0.001)
    }

    /// The same schedule at twice the speed is exactly half as long — there is
    /// no speed baked into it to disagree with.
    func testOneScheduleRendersAtAnySpeed() {
        let events = KeyerTiming.schedule(text: "CQ TEST DE KE5CW K")
        XCTAssertEqual(
            KeyerTiming.durationMs(events, wpm: 40) * 2,
            KeyerTiming.durationMs(events, wpm: 20),
            accuracy: 0.001
        )
    }

    func testAlternatingDownUp() {
        // Schedules must strictly alternate: no two key-downs without an up between.
        let schedule = KeyerTiming.schedule(text: "CQ TEST DE KE5CW K")
        for (a, b) in zip(schedule, schedule.dropFirst()) {
            XCTAssertNotEqual(a.keyDown, b.keyDown, "events must alternate")
        }
        XCTAssertTrue(schedule.first?.keyDown == true)
        XCTAssertTrue(schedule.last?.keyDown == true, "no trailing gap")
    }
}

import XCTest
@testable import QSOPartyLogger

final class KeyerTimingTests: XCTestCase {

    func testDitDuration() {
        XCTAssertEqual(KeyerTiming.ditMs(wpm: 20), 60, accuracy: 0.001)
        XCTAssertEqual(KeyerTiming.ditMs(wpm: 30), 40, accuracy: 0.001)
        XCTAssertEqual(KeyerTiming.ditMs(wpm: 12), 100, accuracy: 0.001)
    }

    func testLetterEIsOneDit() {
        let schedule = KeyerTiming.schedule(text: "E", wpm: 20)
        XCTAssertEqual(schedule, [.init(keyDown: true, durationMs: 60)])
    }

    func testLetterNTiming() {
        // N = dah, gap, dit at 20 WPM: 180 down, 60 up, 60 down.
        XCTAssertEqual(
            KeyerTiming.schedule(text: "N", wpm: 20),
            [
                .init(keyDown: true, durationMs: 180),
                .init(keyDown: false, durationMs: 60),
                .init(keyDown: true, durationMs: 60),
            ]
        )
    }

    func testInterCharacterGapIsThreeDits() {
        let schedule = KeyerTiming.schedule(text: "EE", wpm: 20)
        XCTAssertEqual(
            schedule,
            [
                .init(keyDown: true, durationMs: 60),
                .init(keyDown: false, durationMs: 180),
                .init(keyDown: true, durationMs: 60),
            ]
        )
    }

    func testWordGapIsSevenDits() {
        let schedule = KeyerTiming.schedule(text: "E E", wpm: 20)
        XCTAssertEqual(schedule[1], .init(keyDown: false, durationMs: 420))
    }

    func testParisIsExactlyThreeSecondsAt20WPM() {
        // PARIS = 50 dit units; at 20 WPM (60 ms/dit) one word = 3000 ms
        // including the trailing word gap.
        let sending = KeyerTiming.totalDurationMs(text: "PARIS", wpm: 20)
        XCTAssertEqual(sending + 7 * 60, 3000, accuracy: 0.001)
    }

    func testAlternatingDownUp() {
        // Schedules must strictly alternate: no two key-downs without an up between.
        let schedule = KeyerTiming.schedule(text: "CQ TEST DE KE5CW K", wpm: 28)
        for (a, b) in zip(schedule, schedule.dropFirst()) {
            XCTAssertNotEqual(a.keyDown, b.keyDown, "events must alternate")
        }
        XCTAssertTrue(schedule.first?.keyDown == true)
        XCTAssertTrue(schedule.last?.keyDown == true, "no trailing gap")
    }
}

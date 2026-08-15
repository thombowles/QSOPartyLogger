import XCTest
@testable import QSOPartyLogger

/// The pure half of the recorder: buffers in, one clip out, capped, with the
/// meter's peak. No microphone.
final class RecordingAccumulatorTests: XCTestCase {
    func testAppendsAndReportsLevelAndElapsed() {
        var acc = RecordingAccumulator(sampleRate: 48_000, maxSeconds: 30)
        XCTAssertFalse(acc.append([0.1, -0.5, 0.2]))
        XCTAssertEqual(acc.lastPeak, 0.5)
        XCTAssertEqual(acc.elapsed, 3.0 / 48_000, accuracy: 1e-12)
        XCTAssertEqual(acc.audio.samples, [0.1, -0.5, 0.2])
        XCTAssertEqual(acc.audio.sampleRate, 48_000)
        XCTAssertFalse(acc.isFull)
    }

    func testCutsAtTheMaximumAndSaysSo() {
        var acc = RecordingAccumulator(sampleRate: 10, maxSeconds: 1)
        XCTAssertFalse(acc.append([Float](repeating: 0.1, count: 8)))
        XCTAssertTrue(acc.append([Float](repeating: 0.1, count: 8)), "crossing the cap reports full")
        XCTAssertEqual(acc.audio.samples.count, 10, "and keeps exactly the cap")
        XCTAssertTrue(acc.isFull)
        XCTAssertTrue(acc.append([0.9]), "still full; nothing more is kept")
        XCTAssertEqual(acc.audio.samples.count, 10)
    }

    func testEmptyChunkLeavesPeakAtZero() {
        var acc = RecordingAccumulator(sampleRate: 10, maxSeconds: 1)
        XCTAssertFalse(acc.append([]))
        XCTAssertEqual(acc.lastPeak, 0)
        XCTAssertEqual(acc.elapsed, 0)
    }
}

import XCTest
@testable import QSOPartyLogger

/// The pacing thread: one packet per interval, absolute deadlines, stop
/// between packets, `onFinished` only when every packet went out.
final class FlexDAXStreamerTests: XCTestCase {

    final class Sink: UDPSending, @unchecked Sendable {
        let lock = NSLock()
        private var stored: [(Data, UInt64)] = []
        var localPort: UInt16 { 4991 }
        var packets: [(Data, UInt64)] { lock.withLock { stored } }
        func send(_ data: Data) { lock.withLock { stored.append((data, DispatchTime.now().uptimeNanoseconds)) } }
        func close() {}
    }

    func testSendsEveryPacketAtTheIntervalThenReportsFinished() {
        let sink = Sink()
        let packets = (0..<6).map { Data([UInt8($0)]) }
        let done = expectation(description: "finished")
        let streamer = FlexDAXStreamer(sender: sink, intervalSeconds: 0.005)
        streamer.stream(packets, onFirstPacket: {}, onFinished: { done.fulfill() })
        wait(for: [done], timeout: 2)
        XCTAssertEqual(sink.packets.map { $0.0[0] }, [0, 1, 2, 3, 4, 5])
        let gaps = zip(sink.packets, sink.packets.dropFirst()).map { Double($1.1 - $0.1) / 1e6 }
        XCTAssertTrue(gaps.allSatisfy { $0 > 3 && $0 < 20 }, "≈5 ms apart, got \(gaps)")
    }

    func testFirstPacketIsReportedOnceAndAtOnce() {
        let sink = Sink()
        let first = expectation(description: "first")
        first.assertForOverFulfill = true
        let done = expectation(description: "done")
        let streamer = FlexDAXStreamer(sender: sink, intervalSeconds: 0.002)
        streamer.stream((0..<3).map { Data([UInt8($0)]) }, onFirstPacket: { first.fulfill() }, onFinished: { done.fulfill() })
        wait(for: [first, done], timeout: 2)
    }

    func testStopEndsEarlyAndNeverReportsFinished() {
        let sink = Sink()
        let packets = (0..<400).map { Data([UInt8($0 & 0xFF)]) }
        final class Flag: @unchecked Sendable { var finished = false }
        let flag = Flag()
        let streamer = FlexDAXStreamer(sender: sink, intervalSeconds: 0.005)
        let started = expectation(description: "first")
        streamer.stream(packets, onFirstPacket: { started.fulfill() }, onFinished: { flag.finished = true })
        wait(for: [started], timeout: 1)
        streamer.stop()
        usleep(20_000)
        let sent = sink.packets.count
        usleep(50_000)
        XCTAssertEqual(sink.packets.count, sent, "nothing after stop")
        XCTAssertLessThan(sent, 400)
        XCTAssertFalse(flag.finished)
    }

    func testEmptyPacketListFinishesAtOnce() {
        let done = expectation(description: "done")
        let streamer = FlexDAXStreamer(sender: Sink(), intervalSeconds: 0.005)
        streamer.stream([], onFirstPacket: { XCTFail("no first packet in an empty list") }, onFinished: { done.fulfill() })
        wait(for: [done], timeout: 1)
    }
}

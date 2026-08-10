import XCTest
@testable import QSOPartyLogger

/// Records every control-line transition with the moment it happened, so a
/// test can measure the length of an element the keyer really sent rather
/// than the length it intended to send.
final class TimedLineTransport: SerialTransport, @unchecked Sendable {

    struct Transition {
        let line: SerialLine
        let active: Bool
        let at: DispatchTime
    }

    var isOpen = true
    var onReceive: (@Sendable (Data) -> Void)?

    private let lock = NSLock()
    private var log: [Transition] = []

    func open(baudRate: Int) throws {}
    func close() { isOpen = false }
    func write(_ data: Data) {}

    func set(line: SerialLine, active: Bool) {
        lock.withLock { log.append(Transition(line: line, active: active, at: .now())) }
    }

    var transitions: [Transition] {
        lock.withLock { log }
    }

    /// Length of every key-down period on `line`, in milliseconds. Pairs each
    /// rising edge with the next falling one; a run still keyed down when the
    /// test looks is not reported.
    func keyDownDurationsMs(line: SerialLine) -> [Double] {
        var out: [Double] = []
        var down: DispatchTime?
        for t in transitions where t.line == line {
            if t.active, down == nil {
                down = t.at
            } else if !t.active, let start = down {
                let ns = t.at.uptimeNanoseconds - start.uptimeNanoseconds
                out.append(Double(ns) / 1_000_000)
                down = nil
            }
        }
        return out
    }
}

/// Direct-keying behaviour that needs a running keyer thread rather than a
/// pure schedule. Timing assertions use bands wide enough to absorb scheduler
/// jitter but far too narrow to overlap: a 20 WPM dah is 180 ms and a 40 WPM
/// dah is 90 ms, and the bands checked here are 140-220 and 60-120.
final class CWKeyerTests: XCTestCase {

    /// DTR only — no PTT line to add transitions of its own.
    private var lineConfig: KeyerLineConfig {
        KeyerLineConfig(keyLine: .dtr, pttLine: nil, pttEnabled: false)
    }

    /// The niggle this suite exists for: `⌘=` during a transmission used to do
    /// nothing, because the schedule was baked into milliseconds at the speed
    /// the message started at.
    func testSpeedChangeTakesEffectMidMessage() {
        let transport = TimedLineTransport()
        let keyer = CWKeyer(transport: transport, config: lineConfig, wpm: 20)
        defer { keyer.shutdown() }

        // Six dahs: 180 ms each, 180 ms apart at 20 WPM.
        keyer.send("TTTTTT")
        // Half a second in, the first two dahs are certainly already sent.
        Thread.sleep(forTimeInterval: 0.5)
        keyer.wpm = 40
        Thread.sleep(forTimeInterval: 1.5)

        let downs = transport.keyDownDurationsMs(line: .dtr)
        XCTAssertEqual(downs.count, 6, "expected six dahs, got \(downs)")
        guard downs.count == 6 else { return }

        XCTAssertGreaterThan(downs[0], 140, "first dah should still be a 20 WPM dah")
        XCTAssertLessThan(downs[5], 130, "last dah should be a 40 WPM dah — speed never took effect")
    }

    /// Article 11: a dit or dah in flight finishes at the speed it began, so
    /// no element is ever half one speed and half another. Every dah here must
    /// be *either* a 20 WPM dah or a 40 WPM dah, never something between.
    func testNoElementIsSentAtTwoSpeeds() {
        let transport = TimedLineTransport()
        let keyer = CWKeyer(transport: transport, config: lineConfig, wpm: 20)
        defer { keyer.shutdown() }

        keyer.send("TTTTTT")
        Thread.sleep(forTimeInterval: 0.5)
        keyer.wpm = 40
        Thread.sleep(forTimeInterval: 1.5)

        for (i, ms) in transport.keyDownDurationsMs(line: .dtr).enumerated() {
            let slow = abs(ms - 180) < 40   // 20 WPM dah
            let fast = abs(ms - 90) < 30    // 40 WPM dah
            XCTAssertTrue(
                slow || fast,
                "dah \(i) ran \(String(format: "%.1f", ms)) ms — neither a 20 nor a 40 WPM dah"
            )
        }
    }

    /// Slowing down mid-message has to work as well as speeding up.
    func testSlowingDownMidMessageLengthensLaterElements() {
        let transport = TimedLineTransport()
        let keyer = CWKeyer(transport: transport, config: lineConfig, wpm: 40)
        defer { keyer.shutdown() }

        keyer.send("TTTTTT")
        Thread.sleep(forTimeInterval: 0.25)
        keyer.wpm = 20
        Thread.sleep(forTimeInterval: 1.5)

        let downs = transport.keyDownDurationsMs(line: .dtr)
        XCTAssertEqual(downs.count, 6, "expected six dahs, got \(downs)")
        guard downs.count == 6 else { return }

        XCTAssertLessThan(downs[0], 130, "first dah should still be a 40 WPM dah")
        XCTAssertGreaterThan(downs[5], 140, "last dah should be a 20 WPM dah")
    }

    /// The sending badge and the TX hold key off real completion on the direct
    /// path, so the keyer has to say when it is actually done.
    func testOnFinishedFiresWhenTheQueueDrains() {
        let transport = TimedLineTransport()
        let keyer = CWKeyer(transport: transport, config: lineConfig, wpm: 40)
        defer { keyer.shutdown() }

        let finished = expectation(description: "keyer reports completion")
        let count = Counter()
        keyer.onFinished = {
            count.increment()
            finished.fulfill()
        }

        keyer.send("TT")
        wait(for: [finished], timeout: 3)
        // A single message must report completion once, not once per element.
        XCTAssertEqual(count.value, 1)
    }

    /// Esc mid-message still has to release the badge.
    func testOnFinishedFiresAfterAbort() {
        let transport = TimedLineTransport()
        let keyer = CWKeyer(transport: transport, config: lineConfig, wpm: 8)
        defer { keyer.shutdown() }

        let finished = expectation(description: "keyer reports completion after abort")
        keyer.onFinished = { finished.fulfill() }

        keyer.send("TTTTTTTT")   // ~6 s at 8 WPM; aborted long before it ends
        Thread.sleep(forTimeInterval: 0.3)
        keyer.abort()

        wait(for: [finished], timeout: 2)
    }
}

/// Tiny thread-safe tally — the keyer fires its callbacks from its own thread.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

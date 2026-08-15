import XCTest
@testable import QSOPartyLogger

/// The lead → play → tail → unkey sequence, and abort at every point, driven
/// through a fake output and a hand-cranked scheduler. No audio device.
final class VoicePlayerSequenceTests: XCTestCase {

    final class FakeOutput: AudioOutput, @unchecked Sendable {
        var started: [(audio: VoiceAudio, device: String?, gain: Float)] = []
        var stops = 0
        var failStart = false
        var completion: (@Sendable (Bool) -> Void)?

        func start(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
                   completion: @escaping @Sendable (Bool) -> Void) throws {
            if failStart {
                throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "no device"])
            }
            started.append((audio, deviceUID, gain))
            self.completion = completion
        }

        func stop() { stops += 1 }
    }

    /// Captures scheduled blocks so the test decides when time passes.
    final class ManualScheduler: @unchecked Sendable {
        var pending: [(ms: Int, block: @Sendable () -> Void)] = []
        func schedule(_ ms: Int, _ block: @escaping @Sendable () -> Void) { pending.append((ms, block)) }
        func fireNext() { let p = pending.removeFirst(); p.block() }
    }

    /// Everything the player reports, gathered on one object the closures
    /// can capture (they are `@Sendable`, so no local `var`).
    final class Log: @unchecked Sendable {
        var keys: [Bool] = []
        var events: [TransmitAudioEvent] = []
    }

    private let clip = VoiceAudio(sampleRate: 48_000, samples: [0.1, 0.2])

    private func make() -> (VoicePlayer, FakeOutput, ManualScheduler, Log) {
        let out = FakeOutput()
        let clock = ManualScheduler()
        let player = VoicePlayer(output: out, schedule: clock.schedule)
        return (player, out, clock, Log())
    }

    func testFullSequenceKeysLeadsPlaysTailsUnkeys() {
        let (player, out, clock, log) = make()
        player.play(clip, deviceUID: "dev", gain: 0.6, keyRadio: { log.keys.append($0) },
                    leadMs: 120, tailMs: 100) { log.events.append($0) }

        XCTAssertEqual(log.keys, [true], "keyed at once")
        XCTAssertTrue(out.started.isEmpty, "no audio during the lead")
        XCTAssertEqual(clock.pending.first?.ms, 120)
        clock.fireNext()
        XCTAssertEqual(out.started.count, 1)
        XCTAssertEqual(out.started[0].device, "dev")
        XCTAssertEqual(out.started[0].gain, 0.6)
        XCTAssertEqual(log.events, [.started])
        out.completion?(true)                       // last sample left the device
        XCTAssertEqual(clock.pending.first?.ms, 100)
        XCTAssertEqual(log.keys, [true], "still keyed through the tail")
        clock.fireNext()
        XCTAssertEqual(log.keys, [true, false])
        XCTAssertEqual(log.events, [.started, .finished])
    }

    func testVOXNeverKeysAndHasNoLeadOrTail() {
        let (player, out, clock, log) = make()
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: nil, leadMs: 120, tailMs: 100) { log.events.append($0) }
        XCTAssertEqual(out.started.count, 1, "no lead without a radio to key")
        XCTAssertTrue(clock.pending.isEmpty)
        out.completion?(true)
        XCTAssertEqual(log.events, [.started, .finished], "no tail either")
    }

    func testStopDuringLeadUnkeysAndNeverPlays() {
        let (player, out, clock, log) = make()
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: { log.keys.append($0) },
                    leadMs: 120, tailMs: 100) { log.events.append($0) }
        player.stop()
        XCTAssertEqual(log.keys, [true, false])
        XCTAssertEqual(log.events, [.stopped])
        clock.fireNext()                              // the stale lead timer fires
        XCTAssertTrue(out.started.isEmpty, "a cancelled lead must not start audio")
        XCTAssertEqual(log.events, [.stopped], "and reports nothing more")
    }

    func testStopMidClipUnkeysAtOnceAndSkipsTheTail() {
        let (player, out, clock, log) = make()
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: { log.keys.append($0) },
                    leadMs: 0, tailMs: 100) { log.events.append($0) }
        XCTAssertTrue(clock.pending.isEmpty, "a zero lead starts at once")
        XCTAssertEqual(log.events, [.started])
        player.stop()
        XCTAssertEqual(out.stops, 1)
        XCTAssertEqual(log.keys, [true, false])
        XCTAssertEqual(log.events, [.started, .stopped])
        out.completion?(false)                         // the output reports the interrupted end
        XCTAssertEqual(log.events, [.started, .stopped], "no second terminal event")
    }

    func testStartFailureUnkeysAndReportsTheReason() {
        let (player, out, clock, log) = make()
        out.failStart = true
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: { log.keys.append($0) },
                    leadMs: 10, tailMs: 0) { log.events.append($0) }
        clock.fireNext()
        XCTAssertEqual(log.keys, [true, false])
        XCTAssertEqual(log.events, [.failed("no device")])
    }

    func testSecondPlayReplacesTheFirst() {
        let (player, out, clock, log) = make()
        let second = Log()
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: nil, leadMs: 0, tailMs: 0) { log.events.append($0) }
        XCTAssertEqual(log.events, [.started])
        player.play(clip, deviceUID: nil, gain: 1, keyRadio: nil, leadMs: 0, tailMs: 0) { second.events.append($0) }
        XCTAssertEqual(log.events, [.started, .stopped])
        XCTAssertEqual(out.stops, 1)
        XCTAssertEqual(second.events, [.started])
        XCTAssertTrue(clock.pending.isEmpty)
        out.completion?(true)
        XCTAssertEqual(second.events, [.started, .finished])
        XCTAssertEqual(log.events, [.started, .stopped], "the first play's completion never leaks")
    }

    func testStopWithNothingPlayingIsQuiet() {
        let (player, out, _, _) = make()
        player.stop()
        XCTAssertEqual(out.stops, 0)
    }
}

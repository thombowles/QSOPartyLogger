import XCTest
@testable import QSOPartyLogger

/// `RadioController`'s recordings path over a fake player. The K3 descriptor
/// on `/dev/null` is a serial radio; until its driver conforms to a transport
/// protocol the CAT-keyed path reads `.unsupported`, which one test here pins
/// — the conformance commit flips it. VOX needs no driver help, so the
/// sound-card path is exercised through VOX.
@MainActor
final class RadioControllerRecordingTests: XCTestCase {

    final class FakePlayer: VoicePlaying, @unchecked Sendable {
        struct Play {
            let audio: VoiceAudio
            let deviceUID: String?
            let gain: Float
            let leadMs: Int
            let tailMs: Int
            let keysRadio: Bool
        }
        var plays: [Play] = []
        var stops = 0
        var onEvent: (@Sendable (TransmitAudioEvent) -> Void)?
        var keyRadio: (@Sendable (Bool) -> Void)?

        func play(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
                  keyRadio: (@Sendable (Bool) -> Void)?, leadMs: Int, tailMs: Int,
                  onEvent: @escaping @Sendable (TransmitAudioEvent) -> Void) {
            plays.append(Play(audio: audio, deviceUID: deviceUID, gain: gain,
                              leadMs: leadMs, tailMs: tailMs, keysRadio: keyRadio != nil))
            self.onEvent = onEvent
            self.keyRadio = keyRadio
        }

        func stop() { stops += 1 }
    }

    private func makeSettings() -> AppSettings {
        let s = AppSettings(defaults: Preferences.store)
        s.radioID = "elecraft-k3"
        s.portPath = "/dev/null"
        s.voiceOutputDeviceUID = "codec"
        s.voicePTT = .vox
        s.voiceLevel = 0.5
        s.voicePTTLeadMs = 90
        return s
    }

    private let clip = VoiceAudio(sampleRate: 48_000, samples: [0.5, 0.25])

    /// The player's events hop to the main actor through a Task; give them a
    /// bounded moment to land.
    private func settle(until condition: @escaping @MainActor () -> Bool) async {
        for _ in 0..<50 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    // MARK: The truth table

    func testPathStatusTruthTable() {
        XCTAssertEqual(
            RadioController.voicePath(streams: false, keysOverCAT: false, ptt: .radioCommand, outputName: "USB Audio CODEC"),
            .unsupported)
        XCTAssertEqual(
            RadioController.voicePath(streams: true, keysOverCAT: false, ptt: .radioCommand, outputName: nil),
            .readyOverNetwork)
        XCTAssertEqual(
            RadioController.voicePath(streams: false, keysOverCAT: true, ptt: .radioCommand, outputName: "USB Audio CODEC"),
            .readyOverDevice(name: "USB Audio CODEC"))
        XCTAssertEqual(
            RadioController.voicePath(streams: false, keysOverCAT: false, ptt: .vox, outputName: "USB Audio CODEC"),
            .readyOverDevice(name: "USB Audio CODEC"),
            "VOX needs no CAT keying, so any radio with a sound card works")
        XCTAssertEqual(
            RadioController.voicePath(streams: false, keysOverCAT: true, ptt: .radioCommand, outputName: nil),
            .notReady(reason: RadioController.chooseOutputReason))
        XCTAssertTrue(VoicePathStatus.readyOverNetwork.isReady)
        XCTAssertFalse(VoicePathStatus.unsupported.isReady)
        XCTAssertFalse(VoicePathStatus.notReady(reason: "x").isReady)
    }

    // MARK: Disconnected

    func testDisconnectedControllerIsUnsupportedAndPlaysNothing() {
        let radio = RadioController()
        let player = FakePlayer()
        radio.makeVoicePlayer = { player }
        XCTAssertEqual(radio.voicePathStatus, .unsupported)
        radio.playRecording(clip, caption: "M1 CQ", settings: makeSettings())
        XCTAssertTrue(player.plays.isEmpty)
        XCTAssertNil(radio.nowSending)
    }

    // MARK: The sound-card path through VOX

    func testPlayClaimsTheBadgeAndThePlayerClearsIt() async {
        let radio = RadioController()
        let player = FakePlayer()
        radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { $0 == "codec" ? "USB Audio CODEC" : nil }
        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .readyOverDevice(name: "USB Audio CODEC"), "VOX on a sound card is ready")

        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        XCTAssertEqual(radio.nowSending, "M1 CQ")
        XCTAssertTrue(radio.isVoicePlaying)
        XCTAssertEqual(player.plays.count, 1)
        XCTAssertEqual(player.plays[0].deviceUID, "codec")
        XCTAssertEqual(player.plays[0].gain, 0.5)
        XCTAssertEqual(player.plays[0].leadMs, 90)
        XCTAssertFalse(player.plays[0].keysRadio, "VOX: no keyRadio closure")

        player.onEvent?(.finished)
        await settle { radio.nowSending == nil }
        XCTAssertNil(radio.nowSending)
        XCTAssertFalse(radio.isVoicePlaying)
    }

    func testFailureClearsTheBadgeAndShowsTheReasonInline() async {
        let radio = RadioController()
        let player = FakePlayer()
        radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        player.onEvent?(.failed("no device"))
        await settle { radio.nowSending == nil }
        XCTAssertNil(radio.nowSending)
        XCTAssertFalse(radio.isVoicePlaying)
        XCTAssertEqual(radio.lastError?.summary, "Voice message not sent")
        XCTAssertTrue(radio.lastError?.detail.contains("no device") ?? false)
    }

    func testAbortStopsThePlayerAndClearsTheBadge() {
        let radio = RadioController()
        let player = FakePlayer()
        radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        radio.abortTransmission(settings: settings)
        XCTAssertEqual(player.stops, 1)
        XCTAssertNil(radio.nowSending)
        XCTAssertFalse(radio.isVoicePlaying)
    }

    func testSecondPlayReplacesTheFirst() {
        let radio = RadioController()
        let first = FakePlayer(), second = FakePlayer()
        var players = [first, second]
        radio.makeVoicePlayer = { players.removeFirst() }
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        radio.playRecording(clip, caption: "M2 Exch", settings: settings)
        XCTAssertEqual(first.stops, 1, "the first play is stopped, not queued behind")
        XCTAssertEqual(second.plays.count, 1)
        XCTAssertEqual(radio.nowSending, "M2 Exch")
    }

    /// A terminal event from a play that was already replaced must not clear
    /// the badge the new play owns.
    func testStaleEventFromAReplacedPlayIsIgnored() async {
        let radio = RadioController()
        let first = FakePlayer(), second = FakePlayer()
        var players = [first, second]
        radio.makeVoicePlayer = { players.removeFirst() }
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        radio.playRecording(clip, caption: "M2 Exch", settings: settings)
        first.onEvent?(.stopped)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(radio.nowSending, "M2 Exch")
        XCTAssertTrue(radio.isVoicePlaying)
    }

    func testNotReadyPathRefusesToPlay() {
        let radio = RadioController()
        let player = FakePlayer()
        radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { _ in nil }                // the device is gone
        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .notReady(reason: RadioController.chooseOutputReason))
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        XCTAssertTrue(player.plays.isEmpty)
        XCTAssertNil(radio.nowSending)
    }

    func testRefreshFollowsTheSettingsWhileConnected() {
        let radio = RadioController()
        radio.resolveOutputDevice = { $0 == "codec" ? "USB Audio CODEC" : nil }
        let settings = makeSettings()
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .readyOverDevice(name: "USB Audio CODEC"))
        settings.voiceOutputDeviceUID = nil
        radio.refreshVoicePath(settings: settings)
        XCTAssertEqual(radio.voicePathStatus, .notReady(reason: RadioController.chooseOutputReason))
        radio.disconnect()
        XCTAssertEqual(radio.voicePathStatus, .unsupported, "disconnect resets the path")
    }

    /// A radio that takes the audio over its own link is ready with no device
    /// and no PTT setting at all. 127.0.0.1:1 never leaves the machine and is
    /// never awaited — the path is derived at connect, before any packet.
    func testNetworkPathIsReadyOnAStreamingDriver() {
        let radio = RadioController()
        let settings = AppSettings(defaults: Preferences.store)
        settings.radioID = "flex-6000"
        settings.tcpHost = "127.0.0.1"
        settings.tcpPort = 1
        settings.voiceOutputDeviceUID = nil
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .readyOverNetwork)
    }

    /// The K3 driver keys over CAT, so radio-command PTT is ready on a sound
    /// card — and the player is handed a keying closure.
    func testRadioCommandPTTIsReadyOnADriverThatKeysOverCAT() {
        let radio = RadioController()
        let player = FakePlayer()
        radio.makeVoicePlayer = { player }
        radio.resolveOutputDevice = { _ in "USB Audio CODEC" }
        let settings = makeSettings()
        settings.voicePTT = .radioCommand
        radio.connect(settings: settings)
        defer { radio.disconnect() }
        XCTAssertEqual(radio.voicePathStatus, .readyOverDevice(name: "USB Audio CODEC"))
        radio.playRecording(clip, caption: "M1 CQ", settings: settings)
        XCTAssertEqual(player.plays.count, 1)
        XCTAssertTrue(player.plays[0].keysRadio, "radio command: the player keys through the driver")
    }
}

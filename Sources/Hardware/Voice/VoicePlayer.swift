import Foundation
import AVFAudio
import CoreAudio

/// The audio half of the sound-card player, behind a protocol so the keying
/// sequence is tested with a fake and the engine adapter stays thin.
protocol AudioOutput: AnyObject {
    /// Start playing to `deviceUID` (nil = system default). `completion` is
    /// called once: `true` when the last sample has left the device, `false`
    /// after `stop()`.
    func start(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
               completion: @escaping @Sendable (Bool) -> Void) throws
    func stop()
}

/// Lead → play → tail → unkey, with abort at every point. `keyRadio(false)`
/// always precedes the terminal event, so Esc is never waiting on a callback,
/// and a timer or completion that wakes up after a stop finds its play gone
/// and does nothing.
final class VoicePlayer: VoicePlaying, @unchecked Sendable {
    typealias Schedule = @Sendable (_ delayMs: Int, _ block: @escaping @Sendable () -> Void) -> Void

    private typealias Active = (keyRadio: (@Sendable (Bool) -> Void)?,
                                onEvent: @Sendable (TransmitAudioEvent) -> Void)

    private let output: any AudioOutput
    private let schedule: Schedule
    private let lock = NSLock()
    /// Incremented on every play and every finish; a block that wakes up with
    /// a stale generation belongs to a play that is over.
    private var generation = 0
    private var active: Active?

    init(output: any AudioOutput,
         schedule: @escaping Schedule = { ms, block in
             DispatchQueue.global(qos: .userInteractive)
                 .asyncAfter(deadline: .now() + .milliseconds(ms), execute: block)
         }) {
        self.output = output
        self.schedule = schedule
    }

    func play(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
              keyRadio: (@Sendable (Bool) -> Void)?, leadMs: Int, tailMs: Int,
              onEvent: @escaping @Sendable (TransmitAudioEvent) -> Void) {
        stop()
        let gen: Int = lock.withLock {
            generation += 1
            active = (keyRadio, onEvent)
            return generation
        }
        keyRadio?(true)

        let begin: @Sendable () -> Void = { [weak self] in
            guard let self, self.isCurrent(gen) else { return }
            do {
                try self.output.start(audio, deviceUID: deviceUID, gain: gain) { [weak self] playedToEnd in
                    guard let self, playedToEnd, self.isCurrent(gen) else { return }
                    let end: @Sendable () -> Void = { [weak self] in
                        guard let self, let done = self.finish(gen) else { return }
                        done.keyRadio?(false)
                        done.onEvent(.finished)
                    }
                    if keyRadio != nil, tailMs > 0 { self.schedule(tailMs, end) } else { end() }
                }
                onEvent(.started)
            } catch {
                guard let done = self.finish(gen) else { return }
                done.keyRadio?(false)
                done.onEvent(.failed(error.localizedDescription))
            }
        }
        if keyRadio != nil, leadMs > 0 { schedule(leadMs, begin) } else { begin() }
    }

    func stop() {
        guard let done = finish(nil) else { return }
        output.stop()
        done.keyRadio?(false)
        done.onEvent(.stopped)
    }

    private func isCurrent(_ gen: Int) -> Bool {
        lock.withLock { generation == gen && active != nil }
    }

    /// Takes the active play if `gen` is current (or whatever is active, when
    /// nil), bumping the generation so nothing stale can fire afterwards.
    private func finish(_ gen: Int?) -> Active? {
        lock.withLock {
            guard let current = active, gen == nil || gen == generation else { return nil }
            active = nil
            generation += 1
            return current
        }
    }
}

/// `AVAudioEngine` → the chosen output device. Thin on purpose: everything
/// decidable is decided in `VoicePlayer`, and this only turns a buffer into
/// sound on one device and says when the last sample has gone.
final class EngineAudioOutput: AudioOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?

    enum OutputError: Error, LocalizedError {
        case deviceNotFound(String)
        case format

        var errorDescription: String? {
            switch self {
            case .deviceNotFound(let uid):
                "The audio device for the radio (\(uid)) is not connected."
            case .format:
                "Could not build an audio buffer for the device."
            }
        }
    }

    func start(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
               completion: @escaping @Sendable (Bool) -> Void) throws {
        stop()
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        if let uid = deviceUID {
            guard let deviceID = AudioDevices.deviceID(uid: uid),
                  let unit = engine.outputNode.audioUnit else { throw OutputError.deviceNotFound(uid) }
            var id = deviceID
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw OutputError.deviceNotFound(uid) }
        }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(max(1, audio.samples.count))),
              let channel = buffer.floatChannelData?[0]
        else { throw OutputError.format }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        for (i, s) in audio.samples.enumerated() { channel[i] = max(-1, min(1, s * gain)) }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        lock.withLock { self.engine = engine; self.player = player }
        player.scheduleBuffer(buffer, at: nil, options: [], completionCallbackType: .dataPlayedBack) { type in
            completion(type == .dataPlayedBack)
        }
        player.play()
    }

    func stop() {
        let (e, p): (AVAudioEngine?, AVAudioPlayerNode?) = lock.withLock {
            defer { engine = nil; player = nil }
            return (engine, player)
        }
        p?.stop()
        e?.stop()
    }
}

import Foundation
import AVFAudio
import CoreAudio

/// Collects tapped input buffers into one clip, caps the length, and keeps
/// the last buffer's peak for the meter. Pure, so it is tested without a
/// microphone; the engine adapter below only feeds it.
struct RecordingAccumulator: Sendable {
    let sampleRate: Double
    let maxSamples: Int
    private(set) var samples: [Float] = []
    private(set) var lastPeak: Float = 0

    init(sampleRate: Double, maxSeconds: TimeInterval) {
        self.sampleRate = sampleRate
        self.maxSamples = max(0, Int(maxSeconds * sampleRate))
    }

    var isFull: Bool { samples.count >= maxSamples }
    var elapsed: TimeInterval { Double(samples.count) / sampleRate }
    var audio: VoiceAudio { VoiceAudio(sampleRate: sampleRate, samples: samples) }

    /// Appends up to the cap. Returns true once the cap has been reached, so
    /// the caller can stop the recording by itself.
    mutating func append(_ chunk: [Float]) -> Bool {
        lastPeak = chunk.reduce(0) { max($0, abs($1)) }
        let room = maxSamples - samples.count
        if room > 0 { samples.append(contentsOf: chunk.prefix(room)) }
        return isFull
    }
}

/// The microphone side, behind a protocol for `VoiceStore`'s tests.
protocol VoiceRecording: AnyObject {
    /// Start capturing from `deviceUID` (nil = system default input).
    /// `onLevel` gets the latest peak (0…1) and the elapsed time as buffers
    /// arrive; `onFull` fires once when `maxSeconds` has been captured.
    func start(deviceUID: String?, maxSeconds: TimeInterval,
               onLevel: @escaping @Sendable (Float, TimeInterval) -> Void,
               onFull: @escaping @Sendable () -> Void) throws
    /// Stops and returns what was captured, resampled to the recording rate;
    /// nil when nothing was captured.
    func stop() -> VoiceAudio?
}

/// `AVAudioEngine` input tap → `RecordingAccumulator`. Thin on purpose.
final class EngineVoiceRecorder: VoiceRecording, @unchecked Sendable {
    private let lock = NSLock()
    private var engine: AVAudioEngine?
    private var accumulator: RecordingAccumulator?

    enum RecorderError: Error, LocalizedError {
        case deviceNotFound(String)
        case noInput

        var errorDescription: String? {
            switch self {
            case .deviceNotFound(let uid): "The microphone (\(uid)) is not connected."
            case .noInput: "No microphone is available."
            }
        }
    }

    func start(deviceUID: String?, maxSeconds: TimeInterval,
               onLevel: @escaping @Sendable (Float, TimeInterval) -> Void,
               onFull: @escaping @Sendable () -> Void) throws {
        _ = stop()
        let engine = AVAudioEngine()
        if let uid = deviceUID {
            guard let deviceID = AudioDevices.deviceID(uid: uid),
                  let unit = engine.inputNode.audioUnit else { throw RecorderError.deviceNotFound(uid) }
            var id = deviceID
            let status = AudioUnitSetProperty(
                unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &id, UInt32(MemoryLayout<AudioDeviceID>.size))
            guard status == noErr else { throw RecorderError.deviceNotFound(uid) }
        }
        let format = engine.inputNode.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw RecorderError.noInput }
        lock.withLock {
            accumulator = RecordingAccumulator(sampleRate: format.sampleRate, maxSeconds: maxSeconds)
            self.engine = engine
        }
        engine.inputNode.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            let channels = Int(buffer.format.channelCount)
            var mono = [Float](repeating: 0, count: n)
            for c in 0..<channels {
                for i in 0..<n { mono[i] += data[c][i] }
            }
            if channels > 1 {
                let scale = 1 / Float(channels)
                for i in 0..<n { mono[i] *= scale }
            }
            let (full, peak, elapsed): (Bool, Float, TimeInterval) = self.lock.withLock {
                guard self.accumulator != nil else { return (false, 0, 0) }
                let f = self.accumulator!.append(mono)
                return (f, self.accumulator!.lastPeak, self.accumulator!.elapsed)
            }
            onLevel(peak, elapsed)
            if full { onFull() }
        }
        try engine.start()
    }

    func stop() -> VoiceAudio? {
        let (e, acc): (AVAudioEngine?, RecordingAccumulator?) = lock.withLock {
            defer { engine = nil; accumulator = nil }
            return (engine, accumulator)
        }
        e?.inputNode.removeTap(onBus: 0)
        e?.stop()
        guard let acc, !acc.samples.isEmpty else { return nil }
        return (try? AudioResampler.resample(acc.audio, to: AudioFileIO.recordingSampleRate)) ?? acc.audio
    }
}

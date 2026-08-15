import Foundation
import AVFAudio

/// Reads any file `AVAudioFile` can (folded to mono, at its own rate) and
/// writes the app's own recordings as 48 kHz mono 16-bit PCM WAV — the format
/// every other audio tool opens, should the operator want to edit a message
/// elsewhere.
enum AudioFileIO {
    static let recordingSampleRate = 48_000.0

    enum IOError: Error, LocalizedError {
        case unreadable
        case unwritable

        var errorDescription: String? {
            switch self {
            case .unreadable: "The audio file could not be read."
            case .unwritable: "The recording could not be written."
            }
        }
    }

    static func read(_ url: URL) throws -> VoiceAudio {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let frames = AVAudioFrameCount(file.length)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frames, 1)) else {
            throw IOError.unreadable
        }
        try file.read(into: buffer)
        let n = Int(buffer.frameLength)
        let channels = Int(format.channelCount)
        guard let data = buffer.floatChannelData, channels > 0, n > 0 else {
            return VoiceAudio(sampleRate: format.sampleRate, samples: [])
        }
        var mono = [Float](repeating: 0, count: n)
        for c in 0..<channels {
            for i in 0..<n { mono[i] += data[c][i] }
        }
        if channels > 1 {
            let scale = 1 / Float(channels)
            for i in 0..<n { mono[i] *= scale }
        }
        return VoiceAudio(sampleRate: format.sampleRate, samples: mono)
    }

    static func write(_ audio: VoiceAudio, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: audio.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url, settings: settings)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(max(audio.samples.count, 1))),
              let channel = buffer.floatChannelData?[0]
        else { throw IOError.unwritable }
        buffer.frameLength = AVAudioFrameCount(audio.samples.count)
        for (i, s) in audio.samples.enumerated() { channel[i] = max(-1, min(1, s)) }
        try file.write(from: buffer)
    }

    /// The file's length in seconds, without decoding it.
    static func duration(of url: URL) throws -> TimeInterval {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }
}

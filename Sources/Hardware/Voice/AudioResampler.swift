import Foundation
import AVFAudio

/// `AVAudioConverter` between two mono float rates. Used once per clip when
/// the party's set loads (for a radio whose rate is not the recording's), and
/// on import — never on the F-key press.
enum AudioResampler {
    enum ResampleError: Error, LocalizedError {
        case converter

        var errorDescription: String? {
            "Could not convert the recording to the radio's sample rate."
        }
    }

    static func resample(_ audio: VoiceAudio, to rate: Double) throws -> VoiceAudio {
        guard audio.sampleRate != rate else { return audio }
        guard !audio.samples.isEmpty else { return VoiceAudio(sampleRate: rate, samples: []) }
        guard let inFormat = AVAudioFormat(standardFormatWithSampleRate: audio.sampleRate, channels: 1),
              let outFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let converter = AVAudioConverter(from: inFormat, to: outFormat),
              let input = AVAudioPCMBuffer(pcmFormat: inFormat,
                                           frameCapacity: AVAudioFrameCount(audio.samples.count)),
              let inChannel = input.floatChannelData?[0]
        else { throw ResampleError.converter }
        input.frameLength = AVAudioFrameCount(audio.samples.count)
        for (i, s) in audio.samples.enumerated() { inChannel[i] = s }

        let outFrames = AVAudioFrameCount((Double(audio.samples.count) * rate / audio.sampleRate).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: outFrames) else {
            throw ResampleError.converter
        }
        // The input block is called until it reports the end of the stream;
        // one buffer in, then `.endOfStream`, drains the converter's tail.
        final class Feed: @unchecked Sendable { var fed = false }
        let feed = Feed()
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if feed.fed {
                status.pointee = .endOfStream
                return nil
            }
            feed.fed = true
            status.pointee = .haveData
            return input
        }
        if let error { throw error }
        let n = Int(output.frameLength)
        guard let outChannel = output.floatChannelData?[0] else { throw ResampleError.converter }
        return VoiceAudio(sampleRate: rate, samples: Array(UnsafeBufferPointer(start: outChannel, count: n)))
    }
}

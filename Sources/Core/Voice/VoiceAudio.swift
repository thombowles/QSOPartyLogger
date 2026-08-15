import Foundation

/// A mono clip in memory: the form every voice path works on. Recordings are
/// rendered into one of these (file → trim → gain) once, when the party's set
/// loads, so an F-key never waits on disk.
///
/// Pure Foundation. Nothing here knows about files, devices or radios; the
/// tests drive it with synthetic buffers.
struct VoiceAudio: Equatable, Sendable {
    var sampleRate: Double
    /// Mono, nominally −1…1. Never clipped here — the transports clip at the
    /// wire, so a hot recording turned down by the level control is not
    /// flattened before the level is applied.
    var samples: [Float]

    init(sampleRate: Double, samples: [Float]) {
        self.sampleRate = sampleRate
        self.samples = samples
    }

    var duration: TimeInterval { Double(samples.count) / sampleRate }
    var isEmpty: Bool { samples.isEmpty }

    static func silence(seconds: TimeInterval, sampleRate: Double) -> VoiceAudio {
        VoiceAudio(sampleRate: sampleRate,
                   samples: [Float](repeating: 0, count: max(0, Int((seconds * sampleRate).rounded()))))
    }

    /// The window `start…end` in seconds, clamped to the clip. An inverted or
    /// empty window yields an empty clip rather than trapping.
    func trimmed(from start: TimeInterval, to end: TimeInterval) -> VoiceAudio {
        let lo = max(0, min(samples.count, Int((start * sampleRate).rounded())))
        let hi = max(0, min(samples.count, Int((end * sampleRate).rounded())))
        guard hi > lo else { return VoiceAudio(sampleRate: sampleRate, samples: []) }
        return VoiceAudio(sampleRate: sampleRate, samples: Array(samples[lo..<hi]))
    }

    func scaled(by linear: Float) -> VoiceAudio {
        guard linear != 1 else { return self }
        return VoiceAudio(sampleRate: sampleRate, samples: samples.map { $0 * linear })
    }

    func applyingGain(dB: Float) -> VoiceAudio {
        dB == 0 ? self : scaled(by: Self.linear(dB: dB))
    }

    var peak: Float { samples.reduce(0) { max($0, abs($1)) } }

    var rms: Float {
        guard !samples.isEmpty else { return 0 }
        return sqrtf(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    /// 20·log10, floored at −120 so silence never reads −∞.
    static func decibels(_ linear: Float) -> Float {
        linear <= 0 ? -120 : max(-120, 20 * log10f(linear))
    }

    static func linear(dB: Float) -> Float { powf(10, dB / 20) }

    /// First and last sample louder than `thresholdDB` (relative to full
    /// scale), widened by `pad` seconds each side and clamped to the clip. Nil
    /// when nothing crosses the threshold — a silent recording, which the
    /// recorder keeps as recorded and labels rather than guessing a window.
    func voicedRange(thresholdDB: Float = -40, pad: TimeInterval = 0.12) -> ClosedRange<TimeInterval>? {
        let threshold = Self.linear(dB: thresholdDB)
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
              let last = samples.lastIndex(where: { abs($0) >= threshold }) else { return nil }
        let start = max(0, Double(first) / sampleRate - pad)
        let end = min(duration, Double(last + 1) / sampleRate + pad)
        return start...end
    }

    /// The gain, in dB, that puts the peak at `targetDB`. 0 for a silent clip
    /// — there is nothing to normalize, and infinite gain would be the answer.
    func normalizationGainDB(targetDB: Float = -1) -> Float {
        let p = peak
        guard p > 0 else { return 0 }
        return targetDB - Self.decibels(p)
    }

    /// `bins` peak values across the clip, for drawing. Always exactly `bins`
    /// long; an empty clip draws flat, and more bins than samples repeats
    /// samples rather than leaving holes.
    func waveform(bins: Int) -> [Float] {
        guard bins > 0 else { return [] }
        guard !samples.isEmpty else { return [Float](repeating: 0, count: bins) }
        return (0..<bins).map { bin in
            let lo = min(samples.count - 1, bin * samples.count / bins)
            let hi = max(lo + 1, min(samples.count, (bin + 1) * samples.count / bins))
            return samples[lo..<hi].reduce(0) { max($0, abs($1)) }
        }
    }
}

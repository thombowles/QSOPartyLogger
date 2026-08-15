import XCTest
@testable import QSOPartyLogger

/// The DSP every voice path shares: trim, gain, level, the silence finder the
/// recorder auto-trims with, normalization, and the waveform bins the editor
/// draws. Synthetic buffers only — no file, no device.
final class VoiceAudioTests: XCTestCase {

    /// 1 kHz at 48 kHz, `peak` full-scale.
    private func tone(seconds: Double = 0.5, rate: Double = 48_000, peak: Float = 0.5) -> VoiceAudio {
        let n = Int(seconds * rate)
        return VoiceAudio(sampleRate: rate, samples: (0..<n).map {
            peak * sinf(2 * .pi * 1000 * Float($0) / Float(rate))
        })
    }

    func testDurationAndEmptiness() {
        XCTAssertEqual(tone().duration, 0.5, accuracy: 1e-9)
        XCTAssertFalse(tone().isEmpty)
        XCTAssertTrue(VoiceAudio(sampleRate: 48_000, samples: []).isEmpty)
    }

    func testTrimmedKeepsTheWindowAndClamps() {
        let a = tone(seconds: 1)
        let t = a.trimmed(from: 0.25, to: 0.75)
        XCTAssertEqual(t.samples.count, 24_000)
        XCTAssertEqual(t.samples.first, a.samples[12_000])
        // Out-of-range and inverted windows clamp rather than trap.
        XCTAssertEqual(a.trimmed(from: -1, to: 5).samples.count, a.samples.count)
        XCTAssertTrue(a.trimmed(from: 0.8, to: 0.2).isEmpty)
    }

    func testGainInDecibels() {
        let a = VoiceAudio(sampleRate: 48_000, samples: [0.5, -0.5])
        XCTAssertEqual(a.applyingGain(dB: 6.0206).samples[0], 1.0, accuracy: 1e-4)
        XCTAssertEqual(a.applyingGain(dB: -6.0206).samples[1], -0.25, accuracy: 1e-4)
        XCTAssertEqual(a.applyingGain(dB: 0), a)
        XCTAssertEqual(VoiceAudio.decibels(1), 0, accuracy: 1e-6)
        XCTAssertEqual(VoiceAudio.decibels(0), -120)  // floored, never -inf
        XCTAssertEqual(VoiceAudio.linear(dB: -20), 0.1, accuracy: 1e-6)
    }

    func testPeakAndRMS() {
        let a = VoiceAudio(sampleRate: 48_000, samples: [0.5, -0.8, 0.1])
        XCTAssertEqual(a.peak, 0.8)
        XCTAssertEqual(a.rms, sqrtf((0.25 + 0.64 + 0.01) / 3), accuracy: 1e-6)
        XCTAssertEqual(VoiceAudio(sampleRate: 48_000, samples: []).peak, 0)
        XCTAssertEqual(VoiceAudio(sampleRate: 48_000, samples: []).rms, 0)
    }

    /// Silence, then 0.3 s of tone starting at 0.5 s, then silence: the voiced
    /// range is the tone, padded by 120 ms on each side, clamped to the clip.
    func testVoicedRangeFindsTheSpeechAndPads() {
        let rate = 48_000.0
        var samples = [Float](repeating: 0, count: Int(0.5 * rate))
        samples += tone(seconds: 0.3).samples
        samples += [Float](repeating: 0, count: Int(0.5 * rate))
        let a = VoiceAudio(sampleRate: rate, samples: samples)
        let r = a.voicedRange(thresholdDB: -40, pad: 0.12)!
        XCTAssertEqual(r.lowerBound, 0.5 - 0.12, accuracy: 0.002)
        XCTAssertEqual(r.upperBound, 0.8 + 0.12, accuracy: 0.002)
    }

    func testVoicedRangeClampsPadToTheClipAndIsNilForSilence() {
        let a = tone(seconds: 0.2)                        // voice from the very start
        let r = a.voicedRange(thresholdDB: -40, pad: 0.12)!
        XCTAssertEqual(r.lowerBound, 0)
        XCTAssertEqual(r.upperBound, 0.2, accuracy: 1e-6)
        XCTAssertNil(VoiceAudio(sampleRate: 48_000, samples: [Float](repeating: 0, count: 100))
            .voicedRange(thresholdDB: -40, pad: 0.12))
        XCTAssertNil(VoiceAudio(sampleRate: 48_000, samples: []).voicedRange())
    }

    /// The recorder's trim: room noise and breath before the voice sit well
    /// under the clip's own peak, so the start is where the voice reaches
    /// (peak − 25 dB) over a 10 ms window — not the first sample above a
    /// fixed floor.
    func testVoicedRangeRelativeToPeakIgnoresRoomNoiseAndBreath() {
        let rate = 48_000.0
        // 0.4 s of noise at −45 dBFS, then a breath at −38 dBFS for 0.1 s,
        // then 0.3 s of voice at −6 dBFS, then noise.
        var samples: [Float] = []
        var seed: UInt32 = 12345
        func noise(_ amplitude: Float, _ n: Int) -> [Float] {
            (0..<n).map { _ in
                seed = seed &* 1664525 &+ 1013904223
                return amplitude * (Float(seed >> 8) / Float(1 << 24) * 2 - 1)
            }
        }
        samples += noise(VoiceAudio.linear(dB: -45), Int(0.4 * rate))
        samples += noise(VoiceAudio.linear(dB: -38), Int(0.1 * rate))
        samples += tone(seconds: 0.3, peak: VoiceAudio.linear(dB: -6)).samples
        samples += noise(VoiceAudio.linear(dB: -45), Int(0.4 * rate))
        let a = VoiceAudio(sampleRate: rate, samples: samples)
        let r = a.voicedRange(relativeToPeakDB: 25, floorDB: -45, window: 0.01, pad: 0.12)!
        XCTAssertEqual(r.lowerBound, 0.5 - 0.12, accuracy: 0.015, "starts at the voice, not the breath")
        XCTAssertEqual(r.upperBound, 0.8 + 0.12, accuracy: 0.015)
        // The old fixed −40 dBFS floor would have started at the breath.
        XCTAssertLessThan(a.voicedRange(thresholdDB: -40, pad: 0.12)!.lowerBound, 0.35)
    }

    /// A quiet recording is judged against the floor, not against its own
    /// tiny peak — otherwise a clip of pure noise "finds" a voice in it.
    func testVoicedRangeRelativeToPeakUsesTheFloorForQuietClips() {
        let quiet = VoiceAudio(sampleRate: 48_000, samples: tone(seconds: 0.2, peak: VoiceAudio.linear(dB: -50)).samples)
        XCTAssertNil(quiet.voicedRange(relativeToPeakDB: 25, floorDB: -45, window: 0.01, pad: 0.12))
        XCTAssertNil(VoiceAudio(sampleRate: 48_000, samples: []).voicedRange(relativeToPeakDB: 25, floorDB: -45, window: 0.01, pad: 0.12))
    }

    /// One click does not start a clip: the window's RMS, not a single sample.
    func testVoicedRangeRelativeToPeakIgnoresASingleClick() {
        let rate = 48_000.0
        var samples = [Float](repeating: 0, count: Int(0.5 * rate))
        samples[100] = 0.9                                     // a click at 2 ms
        samples += tone(seconds: 0.3, peak: 0.5).samples
        let a = VoiceAudio(sampleRate: rate, samples: samples)
        let r = a.voicedRange(relativeToPeakDB: 25, floorDB: -45, window: 0.01, pad: 0.12)!
        XCTAssertEqual(r.lowerBound, 0.5 - 0.12, accuracy: 0.015)
    }

    func testNormalizationGainBringsPeakToTarget() {
        let a = tone(peak: 0.25)
        let g = a.normalizationGainDB(targetDB: -1)
        XCTAssertEqual(a.applyingGain(dB: g).peak, VoiceAudio.linear(dB: -1), accuracy: 1e-3)
        XCTAssertEqual(VoiceAudio(sampleRate: 48_000, samples: [0, 0]).normalizationGainDB(targetDB: -1), 0)
    }

    func testWaveformBinsArePeaksAndCountIsExact() {
        let a = VoiceAudio(sampleRate: 4, samples: [0.1, -0.9, 0.2, 0.3, 0.0, 0.5, 0.4, 0.1])
        XCTAssertEqual(a.waveform(bins: 4), [0.9, 0.3, 0.5, 0.4])
        XCTAssertEqual(a.waveform(bins: 3).count, 3)
        XCTAssertEqual(a.waveform(bins: 16).count, 16, "more bins than samples still answers exactly `bins`")
        XCTAssertEqual(VoiceAudio(sampleRate: 4, samples: []).waveform(bins: 3), [0, 0, 0])
        XCTAssertEqual(a.waveform(bins: 0), [])
    }

    func testSilenceAndScaled() {
        let s = VoiceAudio.silence(seconds: 0.1, sampleRate: 24_000)
        XCTAssertEqual(s.samples.count, 2_400)
        XCTAssertTrue(s.samples.allSatisfy { $0 == 0 })
        XCTAssertEqual(VoiceAudio(sampleRate: 1, samples: [0.5]).scaled(by: 0.5).samples, [0.25])
        XCTAssertEqual(VoiceAudio.silence(seconds: -1, sampleRate: 24_000).samples.count, 0)
    }
}

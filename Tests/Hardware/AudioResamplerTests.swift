import XCTest
@testable import QSOPartyLogger

/// `AVAudioConverter` between two rates, checked on a tone: the count halves
/// and the pitch does not move.
final class AudioResamplerTests: XCTestCase {
    private func zeroCrossings(_ s: [Float]) -> Int {
        zip(s, s.dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    func testHalvingTheRateHalvesTheCountAndKeepsTheTone() throws {
        let rate = 48_000.0
        let src = VoiceAudio(sampleRate: rate, samples: (0..<48_000).map {
            0.5 * sinf(2 * .pi * 1000 * Float($0) / Float(rate))
        })
        let out = try AudioResampler.resample(src, to: 24_000)
        XCTAssertEqual(out.sampleRate, 24_000)
        XCTAssertEqual(Double(out.samples.count), 24_000, accuracy: 64)
        // 1 kHz for 1 s ⇒ ~2000 zero crossings at either rate.
        XCTAssertEqual(Double(zeroCrossings(out.samples)), 2000, accuracy: 30)
        XCTAssertEqual(out.peak, 0.5, accuracy: 0.05)
    }

    func testUpsamplingDoublesTheCount() throws {
        let src = VoiceAudio(sampleRate: 24_000, samples: (0..<2400).map { sinf(Float($0) * 0.1) })
        let out = try AudioResampler.resample(src, to: 48_000)
        XCTAssertEqual(Double(out.samples.count), 4800, accuracy: 64)
    }

    func testSameRateIsIdentity() throws {
        let src = VoiceAudio(sampleRate: 24_000, samples: [0.1, 0.2, 0.3])
        XCTAssertEqual(try AudioResampler.resample(src, to: 24_000), src)
    }

    func testEmptyStaysEmpty() throws {
        XCTAssertTrue(try AudioResampler.resample(VoiceAudio(sampleRate: 48_000, samples: []), to: 24_000).isEmpty)
    }
}

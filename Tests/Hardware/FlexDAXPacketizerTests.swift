import XCTest
@testable import QSOPartyLogger

/// The packet FlexLib 3.2.37's DAXTXAudioStream sends, byte for byte — see
/// docs/research/flexlib_3_2_37_dax_tx_excerpts.txt for every constant.
final class FlexDAXPacketizerTests: XCTestCase {
    private func be32(_ d: Data, _ at: Int) -> UInt32 {
        (UInt32(d[at]) << 24) | (UInt32(d[at + 1]) << 16) | (UInt32(d[at + 2]) << 8) | UInt32(d[at + 3])
    }

    func testOnePacketHeaderAndIDs() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0.25, count: 128))
        let packets = FlexDAXPacketizer.packets(for: audio, streamID: 0x8400_0001, startingSequence: 5)
        XCTAssertEqual(packets.count, 1)
        let p = packets[0]
        XCTAssertEqual(p.count, 1052, "263 words")
        XCTAssertEqual(p[0], 0x18, "IF data with stream (1<<4) | class id (1<<3), no trailer")
        XCTAssertEqual(p[1], 0xD5, "TSI other (3<<6) | TSF sample count (1<<4) | count 5")
        XCTAssertEqual(be32(p, 0) & 0xFFFF, 263)
        XCTAssertEqual(be32(p, 4), 0x8400_0001, "stream id")
        XCTAssertEqual(be32(p, 8), 0x001C_2D, "OUI")
        XCTAssertEqual(be32(p, 12), 0x534C_03E3, "information class | packet class")
        XCTAssertEqual(be32(p, 16), 0, "integer timestamp")
        XCTAssertEqual(be32(p, 20), 0, "fractional timestamp, high")
        XCTAssertEqual(be32(p, 24), 0, "fractional timestamp, low")
        // First stereo pair: 0.25 as big-endian float32 = 0x3E800000, in L and R.
        XCTAssertEqual(be32(p, 28), 0x3E80_0000)
        XCTAssertEqual(be32(p, 32), 0x3E80_0000)
    }

    func testSequenceWrapsAt16AndCountsPerPacket() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0, count: 128 * 20))
        let packets = FlexDAXPacketizer.packets(for: audio, streamID: 1, startingSequence: 14)
        XCTAssertEqual(packets.count, 20)
        XCTAssertEqual(packets.map { $0[1] & 0x0F },
                       [14, 15, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 0, 1])
        XCTAssertEqual(FlexDAXPacketizer.nextSequence(after: 14, packetCount: 20), (14 + 20) % 16)
    }

    func testLastPacketIsZeroPaddedAndAShortClipYieldsOnePacket() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [1.0, -1.0, 0.5])
        let packets = FlexDAXPacketizer.packets(for: audio, streamID: 1, startingSequence: 0)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(be32(packets[0], 28), 0x3F80_0000)               // 1.0 L
        XCTAssertEqual(be32(packets[0], 32), 0x3F80_0000)               // 1.0 R
        XCTAssertEqual(be32(packets[0], 36), 0xBF80_0000)               // -1.0
        XCTAssertEqual(be32(packets[0], 44), 0x3F00_0000)               // 0.5
        XCTAssertEqual(be32(packets[0], 28 + 3 * 8), 0, "frame 3 onward is silence")
        XCTAssertEqual(be32(packets[0], 1052 - 4), 0)
    }

    func testAnEmptyClipYieldsOneSilentPacket() {
        let packets = FlexDAXPacketizer.packets(for: VoiceAudio(sampleRate: 24_000, samples: []),
                                                streamID: 1, startingSequence: 3)
        XCTAssertEqual(packets.count, 1)
        XCTAssertEqual(packets[0][1] & 0x0F, 3)
        XCTAssertTrue(packets[0].dropFirst(28).allSatisfy { $0 == 0 })
    }

    func testSamplesAreClippedToFullScale() {
        let audio = VoiceAudio(sampleRate: 24_000, samples: [2.0, -3.0])
        let p = FlexDAXPacketizer.packets(for: audio, streamID: 1, startingSequence: 0)[0]
        XCTAssertEqual(be32(p, 28), 0x3F80_0000)
        XCTAssertEqual(be32(p, 36), 0xBF80_0000)
    }

    func testPacketIntervalIs128FramesAt24k() {
        XCTAssertEqual(FlexDAXPacketizer.framesPerPacket, 128)
        XCTAssertEqual(FlexDAXPacketizer.sampleRate, 24_000)
        XCTAssertEqual(FlexDAXPacketizer.packetInterval, 128.0 / 24_000, accuracy: 1e-12)
        XCTAssertEqual(FlexDAXPacketizer.packetWords, 263)
    }
}

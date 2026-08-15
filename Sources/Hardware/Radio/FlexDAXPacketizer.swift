import Foundation

/// The VITA-49 IF-data packet a DAX transmit client sends the radio, exactly
/// as FlexLib 3.2.37's `DAXTXAudioStream` builds it — see
/// `docs/research/flexlib_3_2_37_dax_tx_excerpts.txt` for every constant:
/// 128 frames of stereo float32, big-endian, information class 0x534C /
/// packet class 0x03E3 under FlexRadio's OUI, sequence count mod 16, class ID
/// present, no trailer, TSI "other" and TSF "sample count" with both
/// timestamps zero. The sample rate is FlexRadio's own answer, 24 ksps
/// (`flex_dax_audio_format_staff_answer.txt`).
///
/// Pure: the driver paces and sends what this returns, and the tests pin the
/// bytes.
enum FlexDAXPacketizer {
    static let sampleRate = 24_000.0
    static let framesPerPacket = 128
    static var packetInterval: TimeInterval { Double(framesPerPacket) / sampleRate }

    static let oui: UInt32 = 0x001C2D
    static let informationClass: UInt16 = 0x534C
    static let packetClass: UInt16 = 0x03E3
    /// 7 header words + 256 payload words: "7*4=28 bytes of Vita overhead".
    static let packetWords: UInt16 = 7 + UInt16(framesPerPacket * 2)

    /// One packet per 128 frames; the last one zero-padded; an empty clip is
    /// one silent packet. `startingSequence` is the 4-bit count of the first
    /// packet, so a stream that spans several clips keeps counting.
    static func packets(for audio: VoiceAudio, streamID: UInt32, startingSequence: Int) -> [Data] {
        let frames = audio.samples
        let count = max(1, Int((Double(frames.count) / Double(framesPerPacket)).rounded(.up)))
        var sequence = startingSequence & 0x0F
        var out: [Data] = []
        out.reserveCapacity(count)
        for p in 0..<count {
            var d = Data(capacity: Int(packetWords) * 4)
            d.append(0x10 | 0x08)                                     // IF data with stream | class id
            d.append(UInt8(0xC0 | 0x10 | UInt8(sequence)))            // TSI other | TSF sample count | count
            appendBE16(&d, packetWords)
            appendBE32(&d, streamID)
            appendBE32(&d, oui)
            appendBE16(&d, informationClass)
            appendBE16(&d, packetClass)
            appendBE32(&d, 0)                                          // integer timestamp
            appendBE32(&d, 0)                                          // fractional timestamp, high
            appendBE32(&d, 0)                                          // fractional timestamp, low
            for i in 0..<framesPerPacket {
                let index = p * framesPerPacket + i
                let sample = index < frames.count ? max(-1, min(1, frames[index])) : 0
                let bits = sample.bitPattern
                appendBE32(&d, bits)                                   // left
                appendBE32(&d, bits)                                   // right
            }
            out.append(d)
            sequence = (sequence + 1) & 0x0F
        }
        return out
    }

    /// The count the packet after `packetCount` packets would carry.
    static func nextSequence(after start: Int, packetCount: Int) -> Int {
        (start + packetCount) & 0x0F
    }

    private static func appendBE16(_ d: inout Data, _ v: UInt16) {
        d.append(UInt8(v >> 8))
        d.append(UInt8(v & 0xFF))
    }

    private static func appendBE32(_ d: inout Data, _ v: UInt32) {
        d.append(UInt8(v >> 24))
        d.append(UInt8((v >> 16) & 0xFF))
        d.append(UInt8((v >> 8) & 0xFF))
        d.append(UInt8(v & 0xFF))
    }
}

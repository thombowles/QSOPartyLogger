import XCTest
import AVFAudio
@testable import QSOPartyLogger

/// WAV out, anything in — through `AVAudioFile`, headless, in a temp folder.
final class AudioFileIOTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioFileIOTests-\(UUID().uuidString).wav")
    }

    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    func testWriteThenReadRoundTripsMonoAt48k() throws {
        let src = VoiceAudio(sampleRate: 48_000, samples: (0..<4800).map { sinf(Float($0) * 0.05) * 0.5 })
        try AudioFileIO.write(src, to: url)
        let back = try AudioFileIO.read(url)
        XCTAssertEqual(back.sampleRate, 48_000)
        XCTAssertEqual(back.samples.count, src.samples.count)
        for i in stride(from: 0, to: 4800, by: 97) {
            XCTAssertEqual(back.samples[i], src.samples[i], accuracy: 1 / 32_000, "16-bit PCM round trip at \(i)")
        }
    }

    func testWriteCreatesTheFolderAndClipsHotSamples() throws {
        let nested = url.deletingLastPathComponent()
            .appendingPathComponent("AudioFileIOTests-nested-\(UUID().uuidString)/deeper/M1.wav")
        defer { try? FileManager.default.removeItem(at: nested.deletingLastPathComponent().deletingLastPathComponent()) }
        try AudioFileIO.write(VoiceAudio(sampleRate: 48_000, samples: [2.0, -2.0, 0.5]), to: nested)
        let back = try AudioFileIO.read(nested)
        XCTAssertEqual(back.samples.count, 3)
        XCTAssertEqual(back.samples[0], 1.0, accuracy: 1e-3)
        XCTAssertEqual(back.samples[1], -1.0, accuracy: 1e-3)
    }

    func testStereoImportFoldsToMonoAndKeepsItsOwnRate() throws {
        // A stereo 44.1 kHz 16-bit file written with AVAudioFile directly: L = 0.4, R = 0.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ]
        do {
            // Scoped: the header is finalised when the file object goes away.
            let file = try AVAudioFile(forWriting: url, settings: settings)
            let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 441)!
            buf.frameLength = 441
            for i in 0..<441 {
                buf.floatChannelData![0][i] = 0.4
                buf.floatChannelData![1][i] = 0
            }
            try file.write(from: buf)
        }

        let back = try AudioFileIO.read(url)
        XCTAssertEqual(back.sampleRate, 44_100)
        XCTAssertEqual(back.samples.count, 441)
        XCTAssertEqual(back.samples[100], 0.2, accuracy: 1e-4, "L and R averaged")
    }

    func testDurationWithoutDecoding() throws {
        try AudioFileIO.write(VoiceAudio(sampleRate: 48_000, samples: [Float](repeating: 0, count: 96_000)), to: url)
        XCTAssertEqual(try AudioFileIO.duration(of: url), 2, accuracy: 1e-6)
    }

    func testMissingFileThrows() {
        XCTAssertThrowsError(try AudioFileIO.read(url))
        XCTAssertThrowsError(try AudioFileIO.duration(of: url))
    }
}

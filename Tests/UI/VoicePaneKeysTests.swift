import XCTest
import SwiftUI
@testable import QSOPartyLogger

/// The Phone tab's pure functions: which key records which memory, and the
/// status sentence for every path and source — worded without a maker, a
/// model, a protocol name or a port (Article 10).
final class VoicePaneKeysTests: XCTestCase {

    func testDigitShortcutsCoverAllEightMemories() {
        for m in 1...MessageSets.voiceMemorySlots {
            XCTAssertEqual(VoiceMessagesPane.recordKey(memory: m), KeyEquivalent(Character("\(m)")))
        }
    }

    private var allPathTexts: [String] {
        [
            VoiceMessagesPane.pathText(.unsupported, source: .recordings, radioHasMemories: false),
            VoiceMessagesPane.pathText(.unsupported, source: .recordings, radioHasMemories: true),
            VoiceMessagesPane.pathText(.notReady(reason: RadioController.chooseOutputReason),
                                       source: .recordings, radioHasMemories: false),
            VoiceMessagesPane.pathText(.readyOverNetwork, source: .recordings, radioHasMemories: false),
            VoiceMessagesPane.pathText(.readyOverDevice(name: "USB Audio CODEC"),
                                       source: .recordings, radioHasMemories: true),
            VoiceMessagesPane.pathText(.readyOverDevice(name: "USB Audio CODEC"),
                                       source: .radioMemories, radioHasMemories: true),
            VoiceMessagesPane.pathText(.unsupported, source: .radioMemories, radioHasMemories: true),
        ]
    }

    func testStatusSentencesNameNoVendorProtocolOrPort() {
        let banned = ["k3", "kx3", "kx2", "flex", "icom", "yaesu", "kenwood", "elecraft", "ci-v",
                      "dax", "4991", "4992", "smartsdr", "vita"]
        for text in allPathTexts {
            for term in banned {
                XCTAssertFalse(text.lowercased().contains(term), "'\(text)' names '\(term)'")
            }
            XCTAssertNil(text.range(of: #"M\d"#, options: .regularExpression),
                         "'\(text)' claims a memory layout")
        }
    }

    func testStatusSentencesSayWhatMatters() {
        let texts = allPathTexts
        XCTAssertTrue(texts[0].contains("No radio"), texts[0])
        XCTAssertTrue(texts[1].contains("own voice memories"), texts[1])
        XCTAssertTrue(texts[2].contains(RadioController.chooseOutputReason), texts[2])
        XCTAssertTrue(texts[3].contains("network"), texts[3])
        XCTAssertTrue(texts[4].contains("USB Audio CODEC"), texts[4])
        XCTAssertTrue(texts[5].contains("Switch the source"), texts[5])
        XCTAssertTrue(texts[6].contains("own voice memories"), texts[6])
    }

    func testDurationCaptions() {
        XCTAssertEqual(VoiceMessagesPane.durationText(2.44), "2.4 s")
        XCTAssertEqual(VoiceMessagesPane.durationText(0), "silent")
        XCTAssertEqual(VoiceMessagesPane.durationText(nil), "no recording")
    }
}

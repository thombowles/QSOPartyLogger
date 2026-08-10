import XCTest
@testable import QSOPartyLogger

/// Article 10's other half, for the voice keyer's displayed status line.
///
/// These lived in `KeyerBackendLabelTests` until the keyer picker was removed
/// (a radio with key lines is now keyed directly and only directly, so there is
/// no backend left to label). They are about displayed *voice* text, not about
/// keyer backends, so they outlive the file they were written in.
final class VoiceStatusTextTests: XCTestCase {

    private var allStatusTexts: [String] {
        [
            MessagesEditor.voiceStatusText(.unsupported, bank: nil),
            MessagesEditor.voiceStatusText(.notInstalled, bank: nil),
            MessagesEditor.voiceStatusText(.available(count: 2), bank: nil),
            MessagesEditor.voiceStatusText(.available(count: 8), bank: 1),
            MessagesEditor.voiceStatusText(.available(count: 8), bank: 2),
        ]
    }

    // MARK: Voice status text

    /// The grep over Sources/UI cannot see whether a *displayed* sentence names
    /// a model, so the strings are asserted here.
    func testVoiceStatusTextNamesNoManufacturer() {
        let banned = ["k3", "kx3", "kx2", "flex", "icom", "yaesu", "kenwood", "elecraft", "ci-v",
                      "kdvr", "dvr"]
        for text in allStatusTexts {
            for term in banned {
                XCTAssertFalse(
                    text.lowercased().contains(term),
                    "voice status '\(text)' names '\(term)' — Article 10 keeps these neutral"
                )
            }
        }
    }

    /// Article 10 forbids model-specific *constants* in displayed text, not
    /// only model names — and the project's grep matches names, so a number
    /// slips straight past it. This is the half that catches a layout claim.
    func testVoiceStatusTextClaimsNoMemoryLayout() {
        for text in allStatusTexts {
            XCTAssertNil(
                text.range(of: #"M\d"#, options: .regularExpression),
                "voice status '\(text)' names a memory label — that is one model's "
                    + "layout in the app layer (Article 10)"
            )
        }
    }

    /// One memory is a memory, not "1 memories".
    func testVoiceStatusTextPluralises() {
        XCTAssertTrue(MessagesEditor.voiceStatusText(.available(count: 1), bank: nil)
            .contains("1 voice memory"))
        XCTAssertTrue(MessagesEditor.voiceStatusText(.available(count: 8), bank: nil)
            .contains("8 voice memories"))
    }
}

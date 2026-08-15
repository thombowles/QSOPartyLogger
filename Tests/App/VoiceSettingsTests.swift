import XCTest
@testable import QSOPartyLogger

/// The voice preferences: defaults, persistence, and what an unreadable token
/// falls back to. A scratch suite per test — never the operator's domain.
@MainActor
final class VoiceSettingsTests: XCTestCase {
    private var suiteName: String!
    private var scratch: UserDefaults!

    override func setUp() {
        suiteName = "VoiceSettingsTests-\(UUID().uuidString)"
        scratch = UserDefaults(suiteName: suiteName)
        scratch.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() { scratch.removePersistentDomain(forName: suiteName) }

    func testDefaults() {
        let s = AppSettings(defaults: scratch)
        XCTAssertEqual(s.phoneMessageSource, .recordings)
        XCTAssertNil(s.voiceInputDeviceUID)
        XCTAssertNil(s.voiceOutputDeviceUID)
        XCTAssertEqual(s.voiceLevel, 0.6, accuracy: 1e-9)
        XCTAssertEqual(s.voicePTT, .radioCommand)
        XCTAssertEqual(s.voicePTTLeadMs, 120)
    }

    func testRoundTripThroughDefaults() {
        let s = AppSettings(defaults: scratch)
        s.phoneMessageSource = .radioMemories
        s.voiceInputDeviceUID = "mic-1"
        s.voiceOutputDeviceUID = "codec-2"
        s.voiceLevel = 0.25
        s.voicePTT = .vox
        s.voicePTTLeadMs = 250
        let again = AppSettings(defaults: scratch)
        XCTAssertEqual(again.phoneMessageSource, .radioMemories)
        XCTAssertEqual(again.voiceInputDeviceUID, "mic-1")
        XCTAssertEqual(again.voiceOutputDeviceUID, "codec-2")
        XCTAssertEqual(again.voiceLevel, 0.25, accuracy: 1e-9)
        XCTAssertEqual(again.voicePTT, .vox)
        XCTAssertEqual(again.voicePTTLeadMs, 250)
    }

    func testClearingADeviceRemovesTheToken() {
        let s = AppSettings(defaults: scratch)
        s.voiceOutputDeviceUID = "codec-2"
        s.voiceOutputDeviceUID = nil
        XCTAssertNil(AppSettings(defaults: scratch).voiceOutputDeviceUID)
    }

    func testUnreadableTokensFallBackToDefaults() {
        scratch.set("garbage", forKey: "phoneMessageSource")
        scratch.set("garbage", forKey: "voicePTT")
        scratch.set(-5, forKey: "voicePTTLeadMs")
        scratch.set(7.0, forKey: "voiceLevel")
        let s = AppSettings(defaults: scratch)
        XCTAssertEqual(s.phoneMessageSource, .recordings)
        XCTAssertEqual(s.voicePTT, .radioCommand)
        XCTAssertEqual(s.voicePTTLeadMs, 0, "clamped into 0…500")
        XCTAssertEqual(s.voiceLevel, 1, "clamped into 0…1")
    }
}

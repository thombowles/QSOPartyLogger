import XCTest
@testable import QSOPartyLogger

final class VoiceKeyerStatusTests: XCTestCase {

    func testMemoryCountIsZeroUnlessAvailable() {
        XCTAssertEqual(VoiceKeyerStatus.unsupported.memoryCount, 0)
        XCTAssertEqual(VoiceKeyerStatus.notInstalled.memoryCount, 0)
        XCTAssertEqual(VoiceKeyerStatus.available(count: 8).memoryCount, 8)
        XCTAssertEqual(VoiceKeyerStatus.available(count: 2).memoryCount, 2)
    }

    /// `isReady` is what gates transmission, so a zero-count "available" must
    /// not read as ready — a radio that answers with no memories is not one to
    /// send an F-key to.
    func testIsReadyRequiresAtLeastOneMemory() {
        XCTAssertFalse(VoiceKeyerStatus.unsupported.isReady)
        XCTAssertFalse(VoiceKeyerStatus.notInstalled.isReady)
        XCTAssertFalse(VoiceKeyerStatus.available(count: 0).isReady)
        XCTAssertTrue(VoiceKeyerStatus.available(count: 2).isReady)
    }
}

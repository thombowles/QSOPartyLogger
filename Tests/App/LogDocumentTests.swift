import XCTest
@testable import QSOPartyLogger

final class LogDocumentTests: XCTestCase {

    /// Regression: `DocumentGroup`'s new-document factory runs on a background
    /// dispatch queue. `LogDocument()` must be constructible off the main
    /// thread — an earlier version wrapped it in `MainActor.assumeIsolated`,
    /// which tripped a dispatch assertion and crashed on launch.
    func testConstructsOffMainThread() {
        let done = expectation(description: "constructed off main")
        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread, "must exercise the background path")
            let document = LogDocument()
            XCTAssertEqual(document.log.partyID, "ksqp")
            XCTAssertEqual(document.log.qsos.count, 0)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    func testSavedStationProfileReadIsThreadSafe() {
        // Reading the persisted profile must not require the main actor.
        let done = expectation(description: "read off main")
        DispatchQueue.global().async {
            _ = LogDocument.savedStationProfile()  // may be nil; must not crash
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }
}

import XCTest
@testable import QSOPartyLogger

/// A running copy that was rebuilt underneath itself keeps running but can no
/// longer prove what it is: the sandbox's save-panel service refuses it, and
/// ⌘E "does nothing" (2026-08-15, live: `openAndSavePanelService` faulted
/// `SecCodeCopyGuestWithAttributes … -67049`, AppKit logged "Unable to display
/// save panel", and the app's own `SecCodeCopySelf` had been failing for
/// hours). The app must say so rather than sit silent.
final class AppIntegrityTests: XCTestCase {

    /// The test host is the app itself, launched from the file it was built
    /// as — intact, so nothing to report.
    func testAnIntactCopyHasNothingToReport() {
        XCTAssertNil(AppIntegrity.check())
    }

    func testSuccessIsNoNotice() {
        XCTAssertNil(AppIntegrity.notice(for: errSecSuccess))
    }

    /// The status the live failure carried, and any other: one line that names
    /// the cause and the remedy.
    func testAFailureNamesTheCauseAndTheRemedy() throws {
        let notice = try XCTUnwrap(AppIntegrity.notice(for: -67049))
        XCTAssertTrue(notice.contains("-67049"), "the status, for the log and the bug report")
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("rebuilt"), "the usual cause")
        XCTAssertTrue(notice.localizedCaseInsensitiveContains("quit"), "the remedy")
        XCTAssertNotNil(AppIntegrity.notice(for: 100001))
    }
}

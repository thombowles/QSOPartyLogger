import AppKit
import XCTest
@testable import QSOPartyLogger

/// Right-click on an F-key opens the Messages editor at once — no menu to
/// choose from first. The catcher is an invisible overlay that claims only
/// the right button (and ⌃-click, the one-button right-click); every other
/// event falls through to the button beneath, so a left click still sends.
final class RightClickCatcherTests: XCTestCase {

    func testTheRightButtonIsClaimed() {
        XCTAssertTrue(RightClickCatcher.claims(type: .rightMouseDown, modifiers: []))
        XCTAssertTrue(RightClickCatcher.claims(type: .rightMouseUp, modifiers: []))
        XCTAssertTrue(RightClickCatcher.claims(type: .rightMouseDragged, modifiers: []))
    }

    func testControlClickIsARightClick() {
        XCTAssertTrue(RightClickCatcher.claims(type: .leftMouseDown, modifiers: [.control]))
        XCTAssertTrue(RightClickCatcher.claims(type: .leftMouseUp, modifiers: [.control]))
    }

    /// A left click is the button's — sending the message — and so is
    /// everything that is not a click at all.
    func testEverythingElseFallsThroughToTheButton() {
        XCTAssertFalse(RightClickCatcher.claims(type: .leftMouseDown, modifiers: []))
        XCTAssertFalse(RightClickCatcher.claims(type: .leftMouseDown, modifiers: [.command]))
        XCTAssertFalse(RightClickCatcher.claims(type: .leftMouseUp, modifiers: []))
        XCTAssertFalse(RightClickCatcher.claims(type: .mouseMoved, modifiers: []))
        XCTAssertFalse(RightClickCatcher.claims(type: .keyDown, modifiers: []))
        XCTAssertFalse(RightClickCatcher.claims(type: nil, modifiers: []))
    }
}

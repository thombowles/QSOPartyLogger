import AppKit
import SwiftUI
import XCTest
@testable import QSOPartyLogger

/// The saved AppKit frame, converted into SwiftUI's placement so a new log
/// window opens where it was rather than opening centred and jumping there.
/// SwiftUI's space is the primary display's flipped one — origin top-left,
/// y down (the menu bar puts its visible rect at y 30) — the position is the
/// window frame's top-left corner and the size is the frame's, chrome
/// included: calibrated on 2026-09-07 by placing at {300, 396, 1200 × 648}
/// and reading the frame back as {300, 252, 1200 × 648} on a 1296-point
/// display.
final class LogWindowPlacementTests: XCTestCase {

    /// A 2304 × 1296 primary display, AppKit's way: origin bottom-left.
    private let primary = CGRect(x: 0, y: 0, width: 2304, height: 1296)
    private var visible: CGRect { CGRect(x: 0, y: 0, width: 2304, height: 1266) }

    func testTheFrameIsFlippedToItsTopLeftCornerAtItsOwnSize() {
        let frame = CGRect(x: 100, y: 200, width: 1000, height: 600)   // top edge at y 800
        let placement = LogWindowPlacement.placement(
            frame: frame, screens: [visible], primaryHeight: primary.height
        )
        XCTAssertEqual(placement, CGRect(x: 100, y: 1296 - 800, width: 1000, height: 600))
    }

    /// The calibration itself: the saved frame of the experiment, and the
    /// rect the unified log showed the closure hand SwiftUI.
    func testTheCalibrationOf2026_09_07() {
        let saved = CGRect(x: 300, y: 200, width: 1200, height: 700)
        XCTAssertEqual(
            LogWindowPlacement.placement(frame: saved, screens: [visible], primaryHeight: 1296),
            CGRect(x: 300, y: 396, width: 1200, height: 700)
        )
    }

    /// The rect becomes SwiftUI's placement field for field; nothing saved
    /// is the empty placement, which leaves the window to the system.
    func testTheRectBecomesTheWindowPlacement() {
        XCTAssertEqual(
            LogWindowPlacement.windowPlacement(CGRect(x: 100, y: 496, width: 1000, height: 548)),
            WindowPlacement(x: 100, y: 496, width: 1000, height: 548)
        )
        XCTAssertEqual(LogWindowPlacement.windowPlacement(nil), WindowPlacement())
    }

    func testNothingSavedIsNoPlacement() {
        XCTAssertNil(LogWindowPlacement.placement(frame: nil, screens: [visible], primaryHeight: primary.height))
    }

    /// Off every screen — the monitor is gone — is the system's placement,
    /// exactly as the memory would refuse to restore it.
    func testAFrameOffEveryScreenIsNoPlacement() {
        let gone = CGRect(x: 3000, y: 200, width: 1000, height: 600)
        XCTAssertNil(LogWindowPlacement.placement(frame: gone, screens: [visible], primaryHeight: primary.height))
    }

    /// A second display to the left of the primary sits at negative x in
    /// AppKit's space and stays there in SwiftUI's; only y flips, about the
    /// primary's top edge.
    func testASecondDisplaysFrameFlipsAboutThePrimarysTop() {
        let left = CGRect(x: -1920, y: 100, width: 1920, height: 1080)
        let frame = CGRect(x: -1500, y: 300, width: 800, height: 500)   // top edge at y 800
        let placement = LogWindowPlacement.placement(
            frame: frame, screens: [visible, left], primaryHeight: primary.height
        )
        XCTAssertEqual(placement, CGRect(x: -1500, y: 496, width: 800, height: 500))
    }
}

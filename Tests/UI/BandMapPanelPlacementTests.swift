import AppKit
import XCTest
@testable import QSOPartyLogger

/// Where a band map opens: at the frame it was last at, or — the first time,
/// or when that frame is off every screen — docked just right of its window.
final class BandMapPanelPlacementTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)
    private let host = NSRect(x: 100, y: 200, width: 1280, height: 800)
    private let size = NSSize(width: 230, height: 560)

    func testTheSavedFrameIsUsed() {
        let saved = NSRect(x: 1500, y: 300, width: 300, height: 600)
        XCTAssertEqual(
            BandMapPanel.initialFrame(saved: saved, host: host, screen: screen, size: size),
            saved
        )
    }

    func testTheFirstOpenDocksRightOfTheWindow() {
        let frame = BandMapPanel.initialFrame(saved: nil, host: host, screen: screen, size: size)
        XCTAssertEqual(frame.minX, host.maxX + 8)
        XCTAssertEqual(frame.maxY, host.maxY)
        XCTAssertEqual(frame.size, size)
    }

    func testASavedFrameOffEveryScreenDocksRightOfTheWindowInstead() {
        let offscreen = NSRect(x: 3000, y: 300, width: 300, height: 600)
        let frame = BandMapPanel.initialFrame(saved: offscreen, host: host, screen: screen, size: size)
        XCTAssertEqual(frame.minX, host.maxX + 8)
        XCTAssertEqual(frame.size, size, "the off-screen frame's size is not kept either")
    }

    func testDockingStaysOnTheScreen() {
        let atEdge = NSRect(x: 2400, y: 200, width: 1280, height: 800)
        let frame = BandMapPanel.initialFrame(saved: nil, host: atEdge, screen: screen, size: size)
        XCTAssertEqual(frame.maxX, screen.maxX - 8)
    }

    func testNoWindowMeansTheSavedFrameOrTheSizeAlone() {
        let saved = NSRect(x: 1500, y: 300, width: 300, height: 600)
        XCTAssertEqual(
            BandMapPanel.initialFrame(saved: saved, host: nil, screen: screen, size: size),
            saved
        )
        XCTAssertEqual(
            BandMapPanel.initialFrame(saved: nil, host: nil, screen: screen, size: size),
            NSRect(origin: .zero, size: size)
        )
    }
}

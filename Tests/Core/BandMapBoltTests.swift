import XCTest
@testable import QSOPartyLogger

/// Where a bolted band map goes, relative to its log window. Both rectangles
/// are window frames in screen coordinates — title bars included — so the two
/// title bars line up.
final class BandMapBoltTests: XCTestCase {

    /// A log window of the app's default size, somewhere on a display.
    private let host = CGRect(x: 100, y: 200, width: 1280, height: 800)

    func testBoltedRightSitsFlushAgainstTheRightEdgeTopAligned() {
        let frame = BandMapBolt.frame(host: host, side: .right, panelWidth: 230, minimumHeight: 300)
        XCTAssertEqual(frame.minX, host.maxX + BandMapBolt.gap)
        XCTAssertEqual(frame.maxY, host.maxY, "the two title bars line up")
        XCTAssertEqual(frame.minY, host.minY, "and so do the bottoms")
        XCTAssertEqual(frame.width, 230, "the width is the operator's")
    }

    func testBoltedLeftSitsFlushAgainstTheLeftEdge() {
        let frame = BandMapBolt.frame(host: host, side: .left, panelWidth: 230, minimumHeight: 300)
        XCTAssertEqual(frame.maxX, host.minX - BandMapBolt.gap)
        XCTAssertEqual(frame.maxY, host.maxY)
        XCTAssertEqual(frame.height, host.height)
        XCTAssertEqual(frame.width, 230)
    }

    func testTheHeightFollowsTheWindow() {
        let tall = CGRect(x: 0, y: 0, width: 1000, height: 1200)
        let frame = BandMapBolt.frame(host: tall, side: .right, panelWidth: 230, minimumHeight: 300)
        XCTAssertEqual(frame.height, 1200)
    }

    /// The map has a minimum height of its own (`PanelMinimumSize`): a window
    /// shorter than that gets a map that hangs below it rather than one that
    /// clips its ruler. Still top-aligned.
    func testAShortWindowGetsTheMapsMinimumHeightHangingBelow() {
        let short = CGRect(x: 0, y: 500, width: 1000, height: 200)
        let frame = BandMapBolt.frame(host: short, side: .right, panelWidth: 230, minimumHeight: 300)
        XCTAssertEqual(frame.height, 300)
        XCTAssertEqual(frame.maxY, short.maxY)
    }

    /// The distance the first-open placement has always used.
    func testTheGapIsEightPoints() {
        XCTAssertEqual(BandMapBolt.gap, 8)
    }

    /// The tokens the preference file holds, and the words the picker shows.
    func testSidesHaveStableTokensAndLabels() {
        XCTAssertEqual(BandMapBolt.Side.allCases, [.left, .right])
        XCTAssertEqual(BandMapBolt.Side.left.rawValue, "left")
        XCTAssertEqual(BandMapBolt.Side.right.rawValue, "right")
        XCTAssertEqual(BandMapBolt.Side.left.label, "Left")
        XCTAssertEqual(BandMapBolt.Side.right.label, "Right")
    }
}

import AppKit
import XCTest
@testable import QSOPartyLogger

/// The band map's relationship to its log window, on real windows.
///
/// The hosted test bundle is never the active application (see
/// `UppercasingFieldCaretTests`), but a child-window relationship, a window
/// level and a frame are bookkeeping that needs no activation — so the AppKit
/// the option rests on is pinned here rather than assumed: that a child moves
/// with its parent, that it can be held at its parent's level, and that a
/// hidden map is not left a child to be brought back with the window.
@MainActor
final class BandMapBoltAttachmentTests: XCTestCase {

    /// A log window, a band map panel, and the attachment between them.
    /// Made by each test on the main actor — XCTest's `setUp` is nonisolated,
    /// and a window cannot be made from there — and closed by a teardown
    /// block on the same actor.
    @MainActor
    private struct Fixture {
        let host: NSWindow
        let panel: NSPanel
        let bolt: BandMapBolt.Attachment

        /// Where the map should be right now, for `side`.
        func expected(_ side: BandMapBolt.Side) -> NSRect {
            BandMapBolt.frame(
                host: host.frame, side: side,
                panelWidth: panel.frame.width, minimumHeight: panel.minSize.height
            )
        }
    }

    private func fixture() -> Fixture {
        let host = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        host.isReleasedWhenClosed = false
        host.orderFront(nil)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 230, height: 560),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.contentMinSize = NSSize(width: 230, height: 280)
        let bolt = BandMapBolt.Attachment(panel: panel, host: host)
        addTeardownBlock { @MainActor in
            bolt.close()
            host.close()
        }
        return Fixture(host: host, panel: panel, bolt: bolt)
    }

    // MARK: Bolting

    func testAFreeMapIsNoChildAndFloats() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: false, side: .right)
        XCTAssertFalse(f.bolt.isAttached)
        XCTAssertNil(f.panel.parent)
        XCTAssertEqual(f.panel.level, .floating)
        XCTAssertTrue(f.panel.isVisible)
    }

    func testBoltingMakesTheMapAChildAtTheWindowsLevelBesideIt() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        XCTAssertTrue(f.bolt.isAttached)
        XCTAssertTrue(f.panel.parent === f.host)
        XCTAssertEqual(f.host.childWindows?.contains(f.panel), true)
        XCTAssertEqual(f.panel.level, f.host.level,
                       "raised and lowered with its window, not floating over the other log")
        XCTAssertEqual(f.panel.frame, f.expected(.right))
        XCTAssertEqual(f.panel.frame.minX, f.host.frame.maxX + BandMapBolt.gap)
    }

    func testBoltingLeftPutsItOnTheLeft() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .left)
        XCTAssertEqual(f.panel.frame, f.expected(.left))
        XCTAssertEqual(f.panel.frame.maxX, f.host.frame.minX - BandMapBolt.gap)
    }

    func testChangingTheSideMovesItAcross() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.bolt.apply(bolted: true, side: .left)
        XCTAssertTrue(f.bolt.isAttached)
        XCTAssertEqual(f.panel.frame, f.expected(.left))
        f.bolt.apply(bolted: true, side: .right)
        XCTAssertEqual(f.panel.frame, f.expected(.right))
    }

    /// Applying the same setting twice changes nothing — the view applies it
    /// on every `onChange`, and on every open.
    func testApplyingTheSameBoltAgainIsANoOp() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.bolt.apply(bolted: true, side: .right)
        XCTAssertEqual(f.host.childWindows?.count, 1)
        XCTAssertEqual(f.panel.frame, f.expected(.right))
    }

    // MARK: Following the window

    func testMovingTheWindowMovesTheMap() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.host.setFrameOrigin(NSPoint(x: 150, y: 150))
        XCTAssertEqual(f.panel.frame, f.expected(.right))
        XCTAssertEqual(f.panel.frame.minX, f.host.frame.maxX + BandMapBolt.gap)
    }

    func testResizingTheWindowRePinsTheHeight() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.host.setFrame(NSRect(x: 100, y: 100, width: 1000, height: 700), display: false)
        XCTAssertEqual(f.panel.frame, f.expected(.right))
        XCTAssertEqual(f.panel.frame.height, f.host.frame.height)
    }

    /// Bolted means bolted: the map cannot be dragged off by its title bar.
    func testDraggingTheMapAwaySnapsItBack() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.panel.setFrameOrigin(NSPoint(x: 10, y: 10))
        XCTAssertEqual(f.panel.frame, f.expected(.right))
    }

    /// The width is the operator's: resized, the map keeps it through every
    /// re-pin.
    func testTheOperatorsWidthSurvivesAPin() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        var wider = f.panel.frame
        wider.size.width = 320
        f.panel.setFrame(wider, display: false)
        f.host.setFrameOrigin(NSPoint(x: 120, y: 120))
        XCTAssertEqual(f.panel.frame.width, 320)
        XCTAssertEqual(f.panel.frame, f.expected(.right))
    }

    // MARK: Setting it free

    func testSettingItFreeLeavesItWhereItIsAndFloating() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        let bolted = f.panel.frame
        f.bolt.apply(bolted: false, side: .right)
        XCTAssertFalse(f.bolt.isAttached)
        XCTAssertNil(f.panel.parent)
        XCTAssertEqual(f.panel.level, .floating)
        XCTAssertEqual(f.panel.frame, bolted, "no remembered position to jump to")
        f.host.setFrameOrigin(NSPoint(x: 200, y: 120))
        XCTAssertEqual(f.panel.frame, bolted, "and the window no longer drags it along")
    }

    // MARK: Hiding and showing — ⌘B

    /// A child window is ordered in with its parent, so a hidden map must not
    /// be left a child: the next click on the log would bring it back.
    func testHidingDetachesSoTheWindowCannotBringItBack() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.bolt.hide()
        XCTAssertFalse(f.panel.isVisible)
        XCTAssertFalse(f.bolt.isAttached)
        XCTAssertNil(f.panel.parent)
        f.host.orderFront(nil)
        XCTAssertFalse(f.panel.isVisible)
    }

    func testShowingABoltedMapReattachesItWhereTheWindowIsNow() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.bolt.hide()
        f.host.setFrameOrigin(NSPoint(x: 50, y: 50))
        f.bolt.show()
        XCTAssertTrue(f.panel.isVisible)
        XCTAssertTrue(f.bolt.isAttached)
        XCTAssertEqual(f.panel.frame, f.expected(.right))
    }

    /// The setting can be flipped with the map closed or hidden; the bolt
    /// takes hold when the map next shows. Opening it is the view's job.
    func testBoltingAHiddenMapWaitsUntilItIsShown() {
        let f = fixture()
        f.bolt.apply(bolted: true, side: .right)
        XCTAssertFalse(f.bolt.isAttached)
        XCTAssertNil(f.panel.parent)
        XCTAssertFalse(f.panel.isVisible)
        f.bolt.show()
        XCTAssertTrue(f.bolt.isAttached)
        XCTAssertEqual(f.panel.frame, f.expected(.right))
    }

    func testClosingDetachesStopsFollowingAndClosesThePanel() {
        let f = fixture()
        f.bolt.show()
        f.bolt.apply(bolted: true, side: .right)
        f.bolt.close()
        XCTAssertFalse(f.panel.isVisible)
        XCTAssertNil(f.panel.parent)
        let before = f.panel.frame
        f.host.setFrameOrigin(NSPoint(x: 250, y: 100))
        XCTAssertEqual(f.panel.frame, before, "nothing is left observing the window")
    }
}

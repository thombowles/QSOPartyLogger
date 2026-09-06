import AppKit
import XCTest
@testable import QSOPartyLogger

/// Every contest is a tab of one log window. The AppKit these rest on is
/// pinned on real windows: a tab group is bookkeeping and needs no activation.
@MainActor
final class LogWindowTabsTests: XCTestCase {

    private func window(visible: Bool = true) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        if visible { window.orderFront(nil) }
        addTeardownBlock { @MainActor in window.close() }
        return window
    }

    func testConfiguringAsksForTabsUnderTheLogIdentifier() {
        let w = window()
        LogWindowTabs.configure(w)
        XCTAssertEqual(w.tabbingMode, .preferred)
        XCTAssertEqual(w.tabbingIdentifier, LogWindowTabs.identifier)
    }

    /// SwiftUI shows the window before the accessor can mark it, so a window
    /// that arrives alone is added to the front log window's group by hand,
    /// and becomes the tab in front.
    func testASecondLogWindowJoinsTheFirstsGroupAndIsSelected() {
        let first = window()
        let second = window()
        LogWindowTabs.configure(first)
        LogWindowTabs.configure(second)
        XCTAssertTrue(LogWindowTabs.join(second, among: [first, second]))
        XCTAssertEqual(first.tabbedWindows?.count, 2)
        XCTAssertTrue(first.tabbedWindows?.contains(second) ?? false)
        XCTAssertTrue(second.tabGroup?.selectedWindow === second)
    }

    func testTheFirstLogWindowIsLeftAlone() {
        let first = window()
        LogWindowTabs.configure(first)
        XCTAssertFalse(LogWindowTabs.join(first, among: [first]))
        XCTAssertNil(first.tabbedWindows)
    }

    /// A window already in a group — AppKit tabbed it before we got there —
    /// is not moved again.
    func testAWindowAlreadyTabbedIsNotMoved() {
        let first = window()
        let second = window()
        LogWindowTabs.configure(first)
        LogWindowTabs.configure(second)
        first.addTabbedWindow(second, ordered: .above)
        XCTAssertFalse(LogWindowTabs.join(second, among: [first, second]))
        XCTAssertEqual(first.tabbedWindows?.count, 2)
    }

    /// The dashboard, a panel, a window that is not on screen: none is a
    /// group to join.
    func testOnlyVisibleLogWindowsAreCandidates() {
        let dashboard = window()
        dashboard.tabbingMode = .disallowed
        let hidden = window(visible: false)
        LogWindowTabs.configure(hidden)
        let newcomer = window()
        LogWindowTabs.configure(newcomer)
        XCTAssertFalse(LogWindowTabs.join(newcomer, among: [dashboard, hidden, newcomer]))
        XCTAssertNil(newcomer.tabbedWindows)
    }
}

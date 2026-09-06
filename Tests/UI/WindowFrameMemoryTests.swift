import AppKit
import XCTest
@testable import QSOPartyLogger

/// A log window comes back where it was: the saved frame is restored to a
/// window that opens alone, and every move and resize is saved.
@MainActor
final class WindowFrameMemoryTests: XCTestCase {

    private let screen = NSRect(x: 0, y: 0, width: 2560, height: 1440)

    private func window() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        addTeardownBlock { @MainActor in window.close() }
        return window
    }

    // MARK: Placement

    func testASavedFrameOnAScreenIsThePlacement() {
        let saved = CGRect(x: 200, y: 300, width: 1300, height: 820)
        XCTAssertEqual(WindowFrameMemory.placement(saved: saved, screens: [screen]), saved)
    }

    func testNothingSavedPlacesNothing() {
        XCTAssertNil(WindowFrameMemory.placement(saved: nil, screens: [screen]))
    }

    /// The monitor it was on is gone: the system places the window, rather
    /// than the app restoring it off every screen.
    func testAFrameOffEveryScreenIsIgnored() {
        let offscreen = CGRect(x: 3000, y: 300, width: 1300, height: 820)
        XCTAssertNil(WindowFrameMemory.placement(saved: offscreen, screens: [screen]))
    }

    /// Partly on a screen is enough — the title bar can be dragged from there.
    func testAFramePartlyOnAScreenIsKept() {
        let edge = CGRect(x: 2400, y: 300, width: 1300, height: 820)
        XCTAssertEqual(WindowFrameMemory.placement(saved: edge, screens: [screen]), edge)
    }

    // MARK: Restoring

    func testALoneWindowIsRestoredToTheSavedFrame() {
        let w = window()
        let saved = CGRect(x: 200, y: 300, width: 1300, height: 820)
        let memory = WindowFrameMemory(window: w, saved: saved, screens: [screen], save: { _ in })
        XCTAssertEqual(w.frame, saved)
        withExtendedLifetime(memory) {}
    }

    /// A window opening into a tab group takes the group's frame; restoring
    /// the saved one would move every tab.
    func testAWindowInATabGroupKeepsTheGroupsFrame() {
        let first = window()
        let second = window()
        first.tabbingMode = .preferred
        second.tabbingMode = .preferred
        first.addTabbedWindow(second, ordered: .above)
        let before = second.frame
        let memory = WindowFrameMemory(
            window: second, saved: CGRect(x: 200, y: 300, width: 1300, height: 820),
            screens: [screen], save: { _ in }
        )
        XCTAssertEqual(second.frame, before)
        withExtendedLifetime(memory) {}
    }

    // MARK: Saving

    func testMovesAndResizesAreSaved() {
        let w = window()
        var saved: [CGRect] = []
        let memory = WindowFrameMemory(window: w, saved: nil, screens: [screen], save: { saved.append($0) })
        w.setFrameOrigin(NSPoint(x: 150, y: 150))
        w.setFrame(NSRect(x: 150, y: 150, width: 1000, height: 700), display: false)
        XCTAssertEqual(saved.last, NSRect(x: 150, y: 150, width: 1000, height: 700))
        XCTAssertEqual(saved.count, 2)
        withExtendedLifetime(memory) {}
    }

    func testRestoringDoesNotSave() {
        let w = window()
        var saved: [CGRect] = []
        let memory = WindowFrameMemory(
            window: w, saved: CGRect(x: 200, y: 300, width: 1300, height: 820),
            screens: [screen], save: { saved.append($0) }
        )
        XCTAssertTrue(saved.isEmpty, "the frame that was just read back is not written again")
        withExtendedLifetime(memory) {}
    }
}

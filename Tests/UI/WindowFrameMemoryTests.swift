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
        let before = w.frame
        let memory = WindowFrameMemory(window: w, saved: saved, screens: [screen], save: { _ in })
        XCTAssertEqual(w.frame, saved)
        XCTAssertTrue(memory.corrected, "the window was moved there")
        XCTAssertEqual(memory.placedAt, before, "and remembers where it found it")
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
        XCTAssertFalse(memory.corrected)
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

    /// A window SwiftUI already placed at the saved frame — `LogWindowPlacement`
    /// — is left alone, to the few points AppKit may have nudged it by to
    /// keep it on the screen (a frame saved at x −2 is placed at x 0; seen
    /// in the unified log, 2026-09-07).
    func testAWindowAlreadyAtTheSavedFrameIsNotCorrected() {
        let w = window()
        let before = w.frame
        let saved = CGRect(x: before.minX - 2, y: before.minY + 1, width: before.width, height: before.height + 0.3)
        let memory = WindowFrameMemory(window: w, saved: saved, screens: [screen], save: { _ in })
        XCTAssertFalse(memory.corrected)
        XCTAssertEqual(w.frame, before)
    }

    /// Past the tolerance it is a different place, and the window goes there.
    func testAWindowFartherOffThanTheToleranceIsCorrected() {
        let w = window()
        let before = w.frame
        let saved = before.offsetBy(dx: WindowFrameMemory.tolerance + 1, dy: 0)
        let memory = WindowFrameMemory(window: w, saved: saved, screens: [screen], save: { _ in })
        XCTAssertTrue(memory.corrected)
        XCTAssertEqual(w.frame, saved)
    }
}

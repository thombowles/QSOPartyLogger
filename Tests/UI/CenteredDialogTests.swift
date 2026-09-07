import AppKit
import SwiftUI
import XCTest
@testable import QSOPartyLogger

/// Contest Setup in the middle of the screen, not hung from the log window —
/// a window against the bottom of the display used to cut the sheet off.
/// The modal session itself cannot run inside a test; the window it runs
/// on can be made and measured.
@MainActor
final class CenteredDialogTests: XCTestCase {

    private let screen = CGRect(x: 0, y: 30, width: 2304, height: 1266)

    private struct Fixed: View {
        var body: some View { Color.clear.frame(width: 560, height: 700) }
    }

    func testTheFrameIsTheMiddleOfTheScreen() {
        let frame = CenteredDialog<Fixed>.frame(size: CGSize(width: 560, height: 700), in: screen)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.midY, screen.midY)
        XCTAssertEqual(frame.size, CGSize(width: 560, height: 700))
    }

    /// The window's position does not enter into it: a log window at the
    /// bottom of the display gets the same dialog as one at the top.
    func testTheDialogIsSizedToItsContentAndCentred() {
        let window = CenteredDialog<Fixed>.Presenter.makeWindow(content: Fixed(), title: "Contest Setup", on: screen)
        addTeardownBlock { @MainActor in window.close() }
        XCTAssertEqual(window.contentView?.frame.size, CGSize(width: 560, height: 700))
        XCTAssertEqual(window.frame.midX, screen.midX, accuracy: 1)
        XCTAssertEqual(window.frame.midY, screen.midY, accuracy: 1)
    }

    /// Sheet-like: no buttons, no visible title, not resizable, draggable by
    /// its background — and a titled window, so it can become key.
    func testTheDialogLooksLikeASheet() {
        let window = CenteredDialog<Fixed>.Presenter.makeWindow(content: Fixed(), title: "Contest Setup", on: screen)
        addTeardownBlock { @MainActor in window.close() }
        XCTAssertTrue(window.styleMask.contains(.titled))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.styleMask.contains(.closable))
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.isMovableByWindowBackground)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.title, "Contest Setup")
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            XCTAssertEqual(window.standardWindowButton(button)?.isHidden ?? true, true)
        }
    }
}

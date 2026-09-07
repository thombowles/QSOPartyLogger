import AppKit
import SwiftUI
import XCTest
@testable import QSOPartyLogger

/// The band map's header — band, VFO, contest, span, filters — on one line
/// where the panel is wide enough, and on two where it is not. Measured the
/// way `WindowSizeTests` measures rows: `sizeThatFits(in:)` at a width is what
/// the header does when the panel is that wide, and at `.zero` its minimum.
@MainActor
final class BandMapHeaderTests: XCTestCase {

    private func header(contest: String = "KSQP") -> some View {
        BandMapHeader(
            band: "20m", vfoText: "14025.0", contestLabel: contest,
            spanKHz: .constant(50), spanChoices: [("25", 25), ("50", 50), ("100", 100), ("All", 10_000)]
        ) {
            Button("Filters") {}
        }
    }

    private func size<V: View>(of view: V, atWidth width: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    /// The narrowest panel (230, less its padding) fits the header without
    /// clipping — nothing is smashed against a side.
    func testTheHeaderFitsTheNarrowestPanel() {
        let floor = NSHostingController(rootView: header()).sizeThatFits(in: .zero)
        XCTAssertLessThanOrEqual(floor.width, 210, "minimum width \(floor.width)")
    }

    func testTheHeaderIsOneLineWhenThePanelIsWide() {
        let oneLine = size(of: header(), atWidth: 420)
        XCTAssertLessThanOrEqual(oneLine.height, 30, "height \(oneLine.height)")
    }

    func testTheHeaderFoldsToTwoLinesWhenThePanelIsNarrow() {
        let oneLine = size(of: header(), atWidth: 420)
        let folded = size(of: header(), atWidth: 210)
        XCTAssertGreaterThan(folded.height, oneLine.height + 12, "folded \(folded.height) vs \(oneLine.height)")
    }

    /// No contest yet (setup not done): the header simply has no label.
    func testNoContestIsNoLabel() {
        let with = size(of: header(contest: "KSQP"), atWidth: 420)
        let without = size(of: header(contest: ""), atWidth: 420)
        XCTAssertEqual(with.height, without.height)
    }
}

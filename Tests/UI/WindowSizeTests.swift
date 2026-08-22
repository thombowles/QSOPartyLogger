import AppKit
import SwiftUI
import XCTest
@testable import QSOPartyLogger

/// How small the log window can go, and which rows fold to let it.
///
/// `NSHostingController.sizeThatFits(in: .zero)` is the size SwiftUI hands a
/// window as its minimum content size; `sizeThatFits(in:)` at a width is what
/// a row does when the window is that wide. Measured on 2026-08-22 before
/// this change: the window 1040 × 640, the messages row 908 wide with no way
/// to fold, the entry row 708 for Skeeter Hunt with a P2P field — so two logs
/// would not fit beside a panadapter. These bounds are the claim that they do.
@MainActor
final class WindowSizeTests: XCTestCase {

    private struct EntryHost: View {
        let party: PartyDefinition?
        let showsP2P: Bool
        @State private var entry = EntryState()
        @FocusState private var focus: EntryBar.Field?
        var body: some View {
            EntryBar(entry: entry, party: party, showsP2P: showsP2P, callFrameColor: .secondary,
                     onTakeCallFrame: {}, onLog: {}, focus: $focus)
        }
    }

    private func minimum<V: View>(of view: V) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: .zero)
    }

    private func size<V: View>(of view: V, atWidth width: CGFloat) -> CGSize {
        NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 10_000))
    }

    private func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.allParties().first { $0.id == id }, "no bundled party \(id)")
    }

    private var messagesRow: MessagesRow {
        let keys = (1...8).map { MessagesRow.MessageKey(caption: "CQ TEST KE5CW \($0)", isActive: true) }
        return MessagesRow(
            operatingMode: .constant(.run), keys: keys, onSend: { _ in }, onEdit: { _ in },
            enabled: true, pendingIndex: 1, repeatEnabled: .constant(false), repeatPaused: false,
            repeatInterval: .constant(3), esmEnabled: .constant(true),
            cqFrequencyLabel: "14025.4", onJumpToCQ: {}
        )
    }

    // MARK: The window

    /// Two of these side by side on a 1920-point display, with a panadapter
    /// above them: each at most 840 wide with its sidebar (the pane's 560 and
    /// the sidebar's 250, with the divider), and 400 tall.
    func testTheLogWindowsMinimumFitsHalfADisplay() {
        let floor = minimum(of: MainView(document: LogDocument()))
        XCTAssertLessThanOrEqual(floor.width, 840, "minimum width \(floor.width)")
        XCTAssertLessThanOrEqual(floor.height, 400, "minimum height \(floor.height)")
    }

    /// The score card's two columns do not shrink; the sidebar hides instead.
    func testTheScoreSidebarKeepsItsFloor() {
        let document = LogDocument()
        let floor = minimum(of: ScoreSidebar(log: document.log, party: nil, score: .init()))
        XCTAssertEqual(floor.width, 250)
    }

    // MARK: The messages row

    /// At every width it fits today the row is the single line it has always
    /// been; one point narrower it folds rather than pushing the interval
    /// stepper off the edge.
    func testTheMessagesRowIsOneLineAtItsDeclaredWidthAndFoldsBelowIt() {
        let oneLine = size(of: messagesRow, atWidth: 10_000).height
        let padding: CGFloat = 24  // 12 a side, outside the fold
        XCTAssertEqual(size(of: messagesRow, atWidth: MessagesRow.singleRowWidth + padding).height, oneLine)
        XCTAssertGreaterThan(size(of: messagesRow, atWidth: MessagesRow.singleRowWidth + padding - 1).height, oneLine)
    }

    /// Folded, the row needs no more than its widest item.
    func testTheMessagesRowFoldsDownToItsWidestItem() {
        XCTAssertLessThan(minimum(of: messagesRow).width, 200)
    }

    // MARK: The entry row

    /// The widest row any party builds: Skeeter Hunt's member number plus a
    /// P2P field. One line where it fits, folded where it does not.
    func testTheEntryRowFoldsForTheWidestParty() throws {
        let widest = EntryHost(party: try party("skeeter"), showsP2P: true)
        let oneLine = size(of: widest, atWidth: 10_000).height
        XCTAssertEqual(size(of: widest, atWidth: 800).height, oneLine, "745 ideal fits in 800")
        XCTAssertGreaterThan(size(of: widest, atWidth: 600).height, oneLine, "and folds at 600")
        XCTAssertLessThan(minimum(of: widest).width, 320)
    }

    /// The everyday row — call, two reports, the exchange — still fits the
    /// pane's floor on one line.
    func testTheEverydayEntryRowFitsThePaneFloorOnOneLine() {
        let everyday = EntryHost(party: nil, showsP2P: false)
        let oneLine = size(of: everyday, atWidth: 10_000).height
        XCTAssertEqual(size(of: everyday, atWidth: 560 - 24).height, oneLine)
    }
}

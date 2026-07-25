import XCTest
@testable import QSOPartyLogger

/// The table takes its space from the log table, not from the window. These
/// assert the arithmetic that makes that true — a measured height would let
/// macOS grow the window the first time a match appeared, which is the one
/// thing this table must never do.
final class WorkedBeforeTableTests: XCTestCase {

    func testNothingToShowIsNoHeight() {
        XCTAssertEqual(
            WorkedBeforeTable.height(contacts: 0, hasArchiveLine: false), 0
        )
    }

    /// The archive alone is worth showing: it is where a pre-filled exchange
    /// came from when this log has never worked the station.
    func testArchiveLineAloneEarnsATable() {
        XCTAssertGreaterThan(
            WorkedBeforeTable.height(contacts: 0, hasArchiveLine: true), 0
        )
    }

    func testEachContactAddsExactlyOneRow() {
        let one = WorkedBeforeTable.height(contacts: 1, hasArchiveLine: false)
        let two = WorkedBeforeTable.height(contacts: 2, hasArchiveLine: false)
        XCTAssertEqual(two - one, WorkedBeforeTable.rowHeight)
    }

    func testGrowthStopsAtTheRowCap() {
        let cap = WorkedBeforeTable.visibleRowCap
        XCTAssertEqual(
            WorkedBeforeTable.height(contacts: cap, hasArchiveLine: false),
            WorkedBeforeTable.height(contacts: cap + 40, hasArchiveLine: false),
            "past the cap the table scrolls rather than growing"
        )
    }

    /// The invariant the window depends on: whatever the table takes, the log
    /// table gives back, so the left pane's minimum content height never moves.
    func testTablePlusLogMinimumIsInvariant() {
        for contacts in 0...12 {
            for archive in [false, true] {
                let table = WorkedBeforeTable.height(
                    contacts: contacts, hasArchiveLine: archive
                )
                XCTAssertEqual(
                    table + WorkedBeforeTable.logTableMin(tableHeight: table),
                    WorkedBeforeTable.logTableMinAlone,
                    accuracy: 0.001,
                    "\(contacts) contacts, archive line \(archive)"
                )
            }
        }
    }
}

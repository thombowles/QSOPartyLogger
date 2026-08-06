import XCTest
@testable import QSOPartyLogger

/// The park picker's keyboard and disclosure rules. A SwiftUI body cannot be
/// asserted on, so the decisions live in `PotaPickerBehavior` and the
/// contract is pinned here — the same split `PartyNotice` uses.
///
/// These are KE5CW's four complaints from the first build, each turned into
/// a rule: the list must not stay open once the search is cleared, arrows
/// must move through results, Return must take the highlighted one, and
/// Escape must empty the field without reaching for the mouse.
final class PotaPickerBehaviorTests: XCTestCase {

    // MARK: Disclosure — the section collapses when there is nothing to show

    func testResultsShowWhileSearching() {
        XCTAssertTrue(PotaPickerBehavior.showsResults(query: "cedar", focused: true))
        // Still shown when focus moves to the list itself.
        XCTAssertTrue(PotaPickerBehavior.showsResults(query: "cedar", focused: false))
    }

    /// An empty field with the cursor in it offers the nearest parks — that
    /// is the discovery affordance, and it is why the list exists at all
    /// before anything is typed.
    func testAnEmptyFocusedFieldOffersTheNearestParks() {
        XCTAssertTrue(PotaPickerBehavior.showsResults(query: "", focused: true))
        XCTAssertTrue(PotaPickerBehavior.showsResults(query: "   ", focused: true))
    }

    /// The complaint: clearing the search left the results on screen and the
    /// section at full height. Cleared and unfocused means collapsed.
    func testAnEmptyUnfocusedFieldCollapses() {
        XCTAssertFalse(PotaPickerBehavior.showsResults(query: "", focused: false))
        XCTAssertFalse(PotaPickerBehavior.showsResults(query: "  ", focused: false))
    }

    // MARK: Escape — clearing without the mouse

    /// One press empties the field *and* closes the list, which is what
    /// "clear the search" means to someone looking at a sheet that has grown
    /// too tall.
    func testEscapeWithTextClearsAndCollapses() {
        XCTAssertEqual(PotaPickerBehavior.escape(query: "cedar"), .clearAndCollapse)
    }

    func testEscapeOnAnEmptyFieldJustCollapses() {
        XCTAssertEqual(PotaPickerBehavior.escape(query: ""), .collapse)
        XCTAssertEqual(PotaPickerBehavior.escape(query: "  "), .collapse)
    }

    // MARK: Arrow keys

    func testArrowsMoveAndClampInsideTheList() {
        XCTAssertEqual(PotaPickerBehavior.move(highlighted: 0, by: 1, count: 3), 1)
        XCTAssertEqual(PotaPickerBehavior.move(highlighted: 2, by: 1, count: 3), 2,
                       "the bottom does not wrap past the last row")
        XCTAssertEqual(PotaPickerBehavior.move(highlighted: 0, by: -1, count: 3), 0,
                       "and the top does not wrap either")
        XCTAssertEqual(PotaPickerBehavior.move(highlighted: 2, by: -1, count: 3), 1)
    }

    func testAnEmptyListHasNothingToHighlight() {
        XCTAssertEqual(PotaPickerBehavior.move(highlighted: 0, by: 1, count: 0), 0)
    }

    /// Typing narrows the list under the cursor, so the highlight has to come
    /// back to the top rather than point at a row that is no longer there.
    func testAStaleHighlightIsPulledBackIntoRange() {
        XCTAssertEqual(PotaPickerBehavior.move(highlighted: 9, by: 0, count: 3), 2)
        XCTAssertEqual(PotaPickerBehavior.move(highlighted: -4, by: 0, count: 3), 0)
    }

    // MARK: Return

    func testReturnTakesTheHighlightedPark() {
        XCTAssertEqual(
            PotaPickerBehavior.submit(query: "cedar", highlighted: 1, offeredCount: 4),
            .addHighlighted(1))
    }

    /// With no list — no download yet, or a park the directory does not
    /// carry — a full reference typed by hand is still added.
    func testReturnAddsATypedReferenceWhenThereIsNoList() {
        XCTAssertEqual(
            PotaPickerBehavior.submit(query: "us-3315", highlighted: 0, offeredCount: 0),
            .addTyped("US-3315"))
    }

    func testReturnOnNonsenseDoesNothing() {
        XCTAssertEqual(
            PotaPickerBehavior.submit(query: "not a park", highlighted: 0, offeredCount: 0),
            .nothing)
        XCTAssertEqual(
            PotaPickerBehavior.submit(query: "", highlighted: 0, offeredCount: 0),
            .nothing)
    }
}

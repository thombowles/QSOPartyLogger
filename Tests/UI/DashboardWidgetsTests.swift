import XCTest
@testable import QSOPartyLogger

/// Which dashboard widgets are shown: everything by default, each one
/// toggleable (⌘1–⌘6, or the toolbar Widgets menu), the hidden set
/// persisted as a raw string that tolerates names it doesn't know — an
/// older build's prefs and a newer one's coexist.
final class DashboardWidgetsTests: XCTestCase {

    func testEverythingShowsByDefault() {
        let visibility = DashboardWidgetVisibility()
        for widget in DashboardWidget.allCases {
            XCTAssertTrue(visibility.shows(widget), "\(widget) hidden by default")
        }
        XCTAssertFalse(visibility.allHidden)
        XCTAssertEqual(visibility.rawValue, "")
    }

    func testToggleHidesAndShowsAgain() {
        var visibility = DashboardWidgetVisibility()
        visibility.toggle(.challenge)
        XCTAssertFalse(visibility.shows(.challenge))
        XCTAssertTrue(visibility.shows(.contests))
        visibility.toggle(.challenge)
        XCTAssertTrue(visibility.shows(.challenge))
    }

    func testRawValueRoundTripsInAStableOrder() {
        var visibility = DashboardWidgetVisibility()
        visibility.toggle(.upcoming)
        visibility.toggle(.seasonCards)
        XCTAssertEqual(visibility.rawValue, "seasonCards,upcoming")
        XCTAssertEqual(DashboardWidgetVisibility(rawValue: "seasonCards,upcoming"), visibility)
    }

    /// A pref written by a build with widgets this one doesn't have (or a
    /// typo) never poisons the rest of the set.
    func testUnknownNamesAreIgnored() {
        let visibility = DashboardWidgetVisibility(rawValue: "potaCards, bogus ,,challenge")
        XCTAssertFalse(visibility.shows(.potaCards))
        XCTAssertFalse(visibility.shows(.challenge))
        XCTAssertTrue(visibility.shows(.contests))
    }

    func testAllHiddenIsKnowable() {
        var visibility = DashboardWidgetVisibility()
        for widget in DashboardWidget.allCases { visibility.toggle(widget) }
        XCTAssertTrue(visibility.allHidden)
    }

    /// ⌘1 … ⌘6 in display order — the keyboard path the menu advertises.
    func testShortcutKeysAreTheDigitsInOrder() {
        XCTAssertEqual(DashboardWidget.allCases.map(\.shortcutKey), ["1", "2", "3", "4", "5", "6"])
        XCTAssertEqual(DashboardWidget.allCases.count, 6)
    }
}

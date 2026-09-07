import XCTest
@testable import QSOPartyLogger

/// The band map's settings in three short pages instead of one tall popover
/// that had to be dragged to be read: which spots, how the knob is followed,
/// and where the window is. The page is remembered.
final class BandMapSettingsTabTests: XCTestCase {

    func testThreePagesInThisOrder() {
        XCTAssertEqual(BandMapSettingsTab.allCases.map(\.label), ["Spots", "Tuning", "Window"])
    }

    /// The raw values are what `@AppStorage` keeps, so they must not drift.
    func testTheStoredTokensAreStable() {
        XCTAssertEqual(BandMapSettingsTab.allCases.map(\.rawValue), ["spots", "tuning", "window"])
        XCTAssertNil(BandMapSettingsTab(rawValue: "filters"))
    }

    /// Every filter that can make the funnel light up lives on the Spots page.
    func testTheSpotsPageIsTheDefault() {
        XCTAssertEqual(BandMapSettingsTab.defaultTab, .spots)
    }
}

import XCTest
@testable import QSOPartyLogger

/// The POTA history row's Activation cell, one glance per outing: hunting,
/// a single park-day against POTA's ten, or how many of a rove's park-days
/// made it.
final class DashboardPotaRowTests: XCTestCase {

    private func label(valid: Int, total: Int, unique: Int? = nil) -> String {
        DashboardPotaSection.activationLabel(valid: valid, total: total, unique: unique)
    }

    func testHunterOutingSaysHunting() {
        XCTAssertEqual(label(valid: 0, total: 0), "hunting")
    }

    func testSingleParkDayShowsItsUniqueCount() {
        XCTAssertEqual(label(valid: 1, total: 1, unique: 12), "✓ 12 unique")
        XCTAssertEqual(label(valid: 0, total: 1, unique: 7), "7/10 unique")
    }

    func testRoveShowsValidOverTotal() {
        XCTAssertEqual(label(valid: 1, total: 2), "1/2 valid")
        XCTAssertEqual(label(valid: 2, total: 2), "✓ 2/2 valid")
    }
}

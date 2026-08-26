import XCTest
@testable import QSOPartyLogger

/// The info line by the call field: name · state · grid · distance/bearing,
/// from the record and the station grid. Pure, so the line's shape is
/// testable without a view.
final class CallbookCaptionTests: XCTestCase {

    private func record(name: String? = "Bob", state: String? = "MO",
                        grid: String? = "EM48ss") -> CallbookRecord {
        CallbookRecord(call: "W0ABC", name: name, qth: "Rolla", state: state,
                       county: nil, grid: grid, country: "United States",
                       dxccID: 291, source: .hamqth,
                       fetchedAt: Date(timeIntervalSince1970: 0))
    }

    func testFullLine() throws {
        let line = try XCTUnwrap(
            CallbookCaption.line(for: record(), stationGrid: "EM13qc"))
        XCTAssertTrue(line.hasPrefix("Bob · MO · EM48ss · "), line)
        XCTAssertTrue(line.contains("mi"), "distance in miles, the README's unit")
    }

    func testDegradesFieldByField() {
        XCTAssertEqual(CallbookCaption.line(for: record(grid: nil), stationGrid: "EM13qc"),
                       "Bob · MO")
        XCTAssertNil(CallbookCaption.line(for: record(name: nil, state: nil, grid: nil),
                                          stationGrid: ""),
                     "nothing to say, no line")
        // No station grid: the record's grid still shows, without a distance.
        XCTAssertEqual(CallbookCaption.line(for: record(), stationGrid: ""),
                       "Bob · MO · EM48ss")
    }

    func testBearingArrowPointsRoughlyNortheastFromTexasToMissouri() throws {
        let line = try XCTUnwrap(
            CallbookCaption.line(for: record(), stationGrid: "EM13qc"))
        XCTAssertTrue(line.contains("↗") || line.contains("↑"),
                      "Dallas to Rolla is up and to the right: \(line)")
    }

    func testBearingMathAtTheCardinalPoints() {
        // Due north and due east from the equator/prime meridian.
        XCTAssertEqual(CallbookCaption.bearingDegrees(fromLat: 0, lon: 0,
                                                      toLat: 10, lon: 0),
                       0, accuracy: 0.1)
        XCTAssertEqual(CallbookCaption.bearingDegrees(fromLat: 0, lon: 0,
                                                      toLat: 0, lon: 10),
                       90, accuracy: 0.1)
        XCTAssertEqual(CallbookCaption.arrow(0), "↑")
        XCTAssertEqual(CallbookCaption.arrow(90), "→")
        XCTAssertEqual(CallbookCaption.arrow(45), "↗")
        XCTAssertEqual(CallbookCaption.arrow(350), "↑")
        XCTAssertEqual(CallbookCaption.arrow(200), "↓")
    }
}

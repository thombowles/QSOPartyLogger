import XCTest
@testable import QSOPartyLogger

final class MaidenheadTests: XCTestCase {

    func testKnownAnchors() {
        // W1AW, Newington CT — the canonical FN31PR.
        XCTAssertEqual(Maidenhead.locator(latitude: 41.714775, longitude: -72.727260),
                       "FN31PR")
        // Ray Roberts Lake State Park — POTA's own payload says EM13li.
        XCTAssertEqual(Maidenhead.locator(latitude: 33.3688, longitude: -97.0094),
                       "EM13LI")
        // Southern hemisphere, east longitude: Sydney Opera House.
        XCTAssertEqual(Maidenhead.locator(latitude: -33.8568, longitude: 151.2153),
                       "QF56OD")
        XCTAssertEqual(Maidenhead.locator(latitude: 0, longitude: 0), "JJ00AA")
    }

    func testFarEdgesClampIntoTheLastCell() {
        XCTAssertEqual(Maidenhead.locator(latitude: 90, longitude: 180), "RR99XX")
        XCTAssertEqual(Maidenhead.locator(latitude: -90, longitude: -180), "AA00AA")
    }

    func testOutOfRangeCoordinatesAreRejected() {
        XCTAssertNil(Maidenhead.locator(latitude: 91, longitude: 0))
        XCTAssertNil(Maidenhead.locator(latitude: 0, longitude: 181))
    }

    func testCenterOfSixCharacterGrid() throws {
        let c = try XCTUnwrap(Maidenhead.center(of: "FN31PR"))
        XCTAssertEqual(c.latitude, 41.72917, accuracy: 0.001)
        XCTAssertEqual(c.longitude, -72.70833, accuracy: 0.001)
    }

    func testCenterOfFourCharacterGrid() throws {
        // EM13's center: north Texas.
        let c = try XCTUnwrap(Maidenhead.center(of: "em13"))
        XCTAssertEqual(c.latitude, 33.5, accuracy: 0.0001)
        XCTAssertEqual(c.longitude, -97.0, accuracy: 0.0001)
    }

    func testCenterRejectsNonLocators() {
        for bad in ["", "EM1", "EM13L", "XX99XX", "12AB", "EM1A", "EMAB"] {
            XCTAssertNil(Maidenhead.center(of: bad), "should reject \(bad)")
        }
    }

    func testRoundTripStaysInsideTheSubsquare() throws {
        let grid = try XCTUnwrap(Maidenhead.locator(latitude: 41.714775,
                                                    longitude: -72.727260))
        let c = try XCTUnwrap(Maidenhead.center(of: grid))
        // A subsquare is 2.5' of latitude and 5' of longitude; the center is
        // within half of each.
        XCTAssertEqual(c.latitude, 41.714775, accuracy: 2.5 / 60)
        XCTAssertEqual(c.longitude, -72.727260, accuracy: 5.0 / 60)
    }
}

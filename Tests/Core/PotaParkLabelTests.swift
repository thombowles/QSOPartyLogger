import XCTest
@testable import QSOPartyLogger

/// A park as the dashboard's POTA list names it: name and state, from the
/// downloaded park list's location tag.
final class PotaParkLabelTests: XCTestCase {

    private func park(_ name: String, location: String?) -> PotaPark {
        PotaPark(reference: "US-0001", name: name, latitude: nil, longitude: nil, grid: nil, locationDesc: location)
    }

    func testNameAndState() {
        XCTAssertEqual(park("Cedar Hill State Park", location: "US-TX").nameAndState, "Cedar Hill State Park · TX")
    }

    /// A park spanning states names them all — every one is an activation
    /// location the sponsor's rules may care about.
    func testAParkSpanningStatesNamesThemAll() {
        XCTAssertEqual(
            park("Great Smoky Mountains National Park", location: "US-TN,US-NC").nameAndState,
            "Great Smoky Mountains National Park · TN/NC"
        )
    }

    func testNoLocationTagIsTheNameAlone() {
        XCTAssertEqual(park("Somewhere", location: nil).nameAndState, "Somewhere")
        XCTAssertEqual(park("Somewhere", location: "").nameAndState, "Somewhere")
    }
}

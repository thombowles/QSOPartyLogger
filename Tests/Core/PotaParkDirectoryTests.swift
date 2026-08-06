import XCTest
@testable import QSOPartyLogger

/// The park list the picker searches. The fixture is six entries copied
/// verbatim from api.pota.app's US program payload (2026-08-05), so these
/// exercise the real field shape rather than an invented one.
final class PotaParkDirectoryTests: XCTestCase {

    func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_parks_sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testParsesTheProgramPayloadShape() throws {
        let directory = try XCTUnwrap(PotaParkDirectory.parse(data: fixtureData()))
        XCTAssertEqual(directory.parks.count, 6)
        let acadia = try XCTUnwrap(directory.parks.first { $0.reference == "US-0001" })
        XCTAssertEqual(acadia.name, "Acadia National Park")
        XCTAssertEqual(acadia.locationDesc, "US-ME")
        XCTAssertEqual(acadia.grid, "FN54vh")
        XCTAssertNil(PotaParkDirectory.parse(data: Data("not json".utf8)))
        XCTAssertNil(PotaParkDirectory.parse(data: Data("[]".utf8)),
                     "an empty list would silently disable search — refuse it")
    }

    func testSearchByNameNumberAndState() throws {
        let d = try XCTUnwrap(PotaParkDirectory.parse(data: fixtureData()))
        XCTAssertEqual(d.search("cedar").map(\.reference), ["US-2996"])
        XCTAssertEqual(d.search("3051").map(\.reference), ["US-3051"])
        // Every term must match: two Texas lakes, and never Acadia.
        XCTAssertEqual(Set(d.search("lake tx").map(\.reference)),
                       Set(["US-3051", "US-3031"]))
        XCTAssertEqual(d.search("tawakoni").count, 2)
        XCTAssertEqual(d.search("").count, 0)
        XCTAssertEqual(d.search("zzzz").count, 0)
        XCTAssertEqual(d.search("us-", limit: 3).count, 3, "limit respected")
    }

    func testNearestSortsByGreatCircle() throws {
        let d = try XCTUnwrap(PotaParkDirectory.parse(data: fixtureData()))
        // From Ray Roberts itself: Ray Roberts (~0 km), Spring Creek
        // (~56 km), Cedar Hill (~83 km) — margins wide enough that the
        // order cannot flap.
        let ranked = d.nearest(latitude: 33.3688, longitude: -97.0094, limit: 3)
        XCTAssertEqual(ranked.map(\.park.reference), ["US-3051", "US-4423", "US-2996"])
        XCTAssertEqual(ranked[0].km, 0, accuracy: 0.5)
    }

    func testHaversineSanity() {
        // Dallas to Austin is about 290 km great-circle.
        let km = PotaParkDirectory.distanceKm(from: (32.78, -96.80),
                                              to: (30.27, -97.74))
        XCTAssertEqual(km, 290, accuracy: 15)
    }
}

import XCTest
@testable import QSOPartyLogger

/// Board rows → band-map spots (spec 2026-08-25 decision 3). The fixture is
/// five rows copied verbatim from the live board
/// (docs/research/pota/SOURCES.md § "POTA spot API").
final class PotaBoardSpotTests: XCTestCase {

    private func fixtureRows() throws -> [PotaSpot.BoardSpot] {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_spots_sample", withExtension: "json"))
        return try XCTUnwrap(PotaSpot.board(from: try Data(contentsOf: url)))
    }

    func testFixtureDecodesWithFrequenciesAndParks() throws {
        let rows = try fixtureRows()
        XCTAssertEqual(rows.count, 5)
        XCTAssertTrue(rows.allSatisfy { !$0.reference.isEmpty })
    }

    func testMapToSpots() throws {
        let spots = PotaSpot.mapToSpots(try fixtureRows(),
                                        now: Date(timeIntervalSince1970: 0))
        XCTAssertFalse(spots.isEmpty)
        for spot in spots {
            XCTAssertEqual(spot.source, .pota)
            XCTAssertNotNil(spot.park, "the park is the point")
            XCTAssertGreaterThan(spot.freqKHz, 1000, "kHz, per the board's own rule")
            XCTAssertNil(spot.county, "a park is not a county")
        }
        // The mode rides the comment so the map's mode inference and colour
        // rules see it without a new field.
        XCTAssertTrue(spots.contains { !$0.comment.isEmpty })
    }

    func testUnparseableFrequencyRowsAreDropped() {
        let rows = [PotaSpot.BoardSpot(activator: "W1AW", reference: "US-0001",
                                       spotter: "W1AW", frequency: "QRG?",
                                       mode: "CW", spotTime: nil, source: nil)]
        XCTAssertTrue(PotaSpot.mapToSpots(rows, now: Date(timeIntervalSince1970: 0)).isEmpty)
    }

    @MainActor
    func testStoreReplaceIsWholesalePerSource() {
        let store = SpotStore()
        store.add(Spot(call: "K1AA", freqKHz: 14040, spotter: "N1XX",
                       comment: "", receivedAt: Date(timeIntervalSince1970: 0),
                       county: nil, source: .cluster))
        let first = Spot(call: "W1AW", freqKHz: 14285, spotter: "W1AW",
                         comment: "SSB", receivedAt: Date(timeIntervalSince1970: 1),
                         county: nil, source: .pota, park: "US-0001")
        store.replace(source: .pota, with: [first])
        XCTAssertEqual(store.all.filter { $0.source == .pota }.count, 1)
        XCTAssertEqual(store.all.filter { $0.source == .pota }.first?.park, "US-0001")
        // Next poll: the board no longer lists W1AW (QRT). He is gone; the
        // cluster spot is untouched.
        store.replace(source: .pota, with: [])
        XCTAssertTrue(store.all.filter { $0.source == .pota }.isEmpty)
        XCTAssertEqual(store.all.filter { $0.source == .cluster }.count, 1)
    }
}

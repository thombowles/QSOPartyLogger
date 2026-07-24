import XCTest
@testable import QSOPartyLogger

final class SpottingTests: XCTestCase {

    private func spot(
        call: String = "K5ABC",
        freqKHz: Double = 14026.1,
        at: Date = Date(timeIntervalSince1970: 1_785_078_000),
        spotter: String = "W3LPL"
    ) -> Spot {
        Spot(call: call, freqKHz: freqKHz, spotter: spotter, comment: "", receivedAt: at)
    }

    // MARK: Cluster line parsing

    func testParseClusterSpotLine() {
        let line = "DX de W3LPL:     14026.1  K5ABC        loud in VA                    1523Z"
        let spot = SpotParser.parse(line, receivedAt: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(spot?.spotter, "W3LPL")
        XCTAssertEqual(spot?.freqKHz ?? 0, 14026.1, accuracy: 0.001)
        XCTAssertEqual(spot?.call, "K5ABC")
        XCTAssertEqual(spot?.band, .m20)
        XCTAssertEqual(spot?.comment, "loud in VA")
    }

    func testParseSpotWithEmptyComment() {
        let spot = SpotParser.parse("DX de N0AX:      7040.0  W0BH           0001Z", receivedAt: Date())
        XCTAssertEqual(spot?.call, "W0BH")
        XCTAssertEqual(spot?.freqKHz ?? 0, 7040.0, accuracy: 0.001)
        XCTAssertEqual(spot?.band, .m40)
        XCTAssertEqual(spot?.comment, "")
    }

    func testParseRejectsNonSpotLines() {
        XCTAssertNil(SpotParser.parse("WWV de W0MU <18>:   SFI=140, A=5, K=2, No Storms", receivedAt: Date()))
        XCTAssertNil(SpotParser.parse("To ALL de N0AX: anyone on 6m?", receivedAt: Date()))
        XCTAssertNil(SpotParser.parse("login: ", receivedAt: Date()))
        XCTAssertNil(SpotParser.parse("", receivedAt: Date()))
    }

    func testParseRejectsOutOfBandFrequency() {
        XCTAssertNil(
            SpotParser.parse("DX de W3LPL:     599.0  K5ABC        comment   1523Z", receivedAt: Date()),
            "frequency outside every amateur band is garbage"
        )
    }

    // MARK: sh/dx replies (different layout from broadcast spots)

    /// `sh/dx` output is columnar with a trailing `<spotter>`, not `DX de …`.
    func testParseShowDXLine() {
        let line = "  14025.0  K5ABC        24-Jul-2026 1523Z  loud in VA                     <W3LPL>"
        let spot = SpotParser.parse(line, receivedAt: Date())
        XCTAssertEqual(spot?.call, "K5ABC")
        XCTAssertEqual(spot?.freqKHz ?? 0, 14025.0, accuracy: 0.001)
        XCTAssertEqual(spot?.spotter, "W3LPL")
        XCTAssertEqual(spot?.comment, "loud in VA")
        XCTAssertEqual(spot?.band, .m20)
    }

    func testShowDXUsesTheSpotsOwnTimestamp() throws {
        let received = Date(timeIntervalSince1970: 1_785_078_000)
        let line = "  14025.0  K5ABC        24-Jul-2026 1523Z  loud                           <W3LPL>"
        let spot = try XCTUnwrap(SpotParser.parse(line, receivedAt: received))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let parts = utc.dateComponents([.year, .month, .day, .hour, .minute], from: spot.receivedAt)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 7)
        XCTAssertEqual(parts.day, 24)
        XCTAssertEqual(parts.hour, 15)
        XCTAssertEqual(parts.minute, 23)
    }

    func testParseShowDXSingleDigitDayAndNoComment() {
        let line = " 14195.0  VK9CZ         7-Jan-2020 0234Z                                  <W1ABC>"
        let spot = SpotParser.parse(line, receivedAt: Date())
        XCTAssertEqual(spot?.call, "VK9CZ")
        XCTAssertEqual(spot?.spotter, "W1ABC")
        XCTAssertEqual(spot?.comment, "")
    }

    func testShowDXHeaderAndChatterRejected() {
        XCTAssertNil(SpotParser.parse("Callsign   Frequency   Date      Time", receivedAt: Date()))
        XCTAssertNil(SpotParser.parse("  599.0  K5ABC   24-Jul-2026 1523Z  x   <W3LPL>", receivedAt: Date()))
        XCTAssertNil(SpotParser.parse("dxc.example.com >", receivedAt: Date()))
    }

    // MARK: Store: upsert, purge, band filter

    @MainActor
    func testStoreUpsertsSameCallAndBand() {
        let t0 = Date(timeIntervalSince1970: 1_785_078_000)
        let store = SpotStore()
        store.add(spot(freqKHz: 14026.1, at: t0))
        store.add(spot(freqKHz: 14026.4, at: t0.addingTimeInterval(60)))
        XCTAssertEqual(store.spots(band: .m20).count, 1, "re-spot of the same call+band replaces")
        XCTAssertEqual(store.spots(band: .m20).first?.freqKHz ?? 0, 14026.4, accuracy: 0.001)

        store.add(spot(freqKHz: 7026.0, at: t0.addingTimeInterval(90)))
        XCTAssertEqual(store.spots(band: .m40).count, 1, "same call on another band is a separate spot")
    }

    @MainActor
    func testStorePurgesOldSpots() {
        let now = Date(timeIntervalSince1970: 1_785_078_000)
        let store = SpotStore()
        store.add(spot(call: "OLD1", freqKHz: 14001.0, at: now.addingTimeInterval(-16 * 60)))
        store.add(spot(call: "NEW1", freqKHz: 14002.0, at: now.addingTimeInterval(-60)))
        store.purge(now: now)
        XCTAssertEqual(store.spots(band: .m20).map(\.call), ["NEW1"])
    }

    @MainActor
    func testStoreDropsStaleSpotsFromABulkShowDXReply() {
        // sh/dx returns a batch spanning a wide time range; anything older
        // than the window relative to the newest spot is already stale.
        let now = Date(timeIntervalSince1970: 1_785_078_000)
        let store = SpotStore()
        store.add(spot(call: "OLD1", freqKHz: 14001.0, at: now.addingTimeInterval(-40 * 60)))
        store.add(spot(call: "NEW1", freqKHz: 14002.0, at: now))
        XCTAssertEqual(store.spots(band: .m20).map(\.call), ["NEW1"])
    }

    @MainActor
    func testStoreSortsByFrequency() {
        let store = SpotStore()
        store.add(spot(call: "A1AA", freqKHz: 14040.0))
        store.add(spot(call: "B1BB", freqKHz: 14005.0))
        store.add(spot(call: "C1CC", freqKHz: 14026.0))
        XCTAssertEqual(store.spots(band: .m20).map(\.call), ["B1BB", "C1CC", "A1AA"])
    }

    // MARK: Next/previous spot navigation

    func testNextSpotUpDownWithWrap() {
        let spots = [
            spot(call: "A1AA", freqKHz: 14005.0),
            spot(call: "B1BB", freqKHz: 14026.1),
            spot(call: "C1CC", freqKHz: 14040.0),
        ]
        XCTAssertEqual(SpotStore.next(in: spots, afterKHz: 14026.1, direction: .up)?.call, "C1CC")
        XCTAssertEqual(SpotStore.next(in: spots, afterKHz: 14040.0, direction: .up)?.call, "A1AA", "wraps")
        XCTAssertEqual(SpotStore.next(in: spots, afterKHz: 14026.1, direction: .down)?.call, "A1AA")
        XCTAssertEqual(SpotStore.next(in: spots, afterKHz: 14005.0, direction: .down)?.call, "C1CC", "wraps")
        XCTAssertEqual(
            SpotStore.next(in: spots, afterKHz: 14010.0, direction: .up)?.call, "B1BB",
            "between spots: nearest in that direction"
        )
        XCTAssertNil(SpotStore.next(in: [], afterKHz: 14026.1, direction: .up))
    }

    func testNextSpotSingleSpotAlwaysReturnsIt() {
        let only = [spot(call: "A1AA", freqKHz: 14005.0)]
        XCTAssertEqual(SpotStore.next(in: only, afterKHz: 14005.0, direction: .up)?.call, "A1AA")
        XCTAssertEqual(SpotStore.next(in: only, afterKHz: 14005.0, direction: .down)?.call, "A1AA")
    }
}

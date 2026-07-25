import XCTest
@testable import QSOPartyLogger

/// Spot lifetime, per source.
///
/// The two feeds differ in kind. Cluster spots stream continuously from
/// skimmers, so a 15-minute window is generous. Hub spots are hand-posted and
/// sparse, and the hub itself keeps them a full 60 minutes — because a mobile
/// parked in a county stays workable far longer than a skimmer decode stays
/// fresh. Applying the cluster's window to both empties the hub feed entirely.
final class HubSpotLifetimeTests: XCTestCase {

    /// UTC instants from the live ALQP capture of 2026-07-25, and the poll
    /// that read them. Ages run 18.8 to 36.7 minutes.
    private static func utc(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: iso)!
    }

    private static let pollTime = utc("2026-07-25 22:34:12")

    private static let liveALQPSpots: [Spot] = [
        Spot(call: "W4NBS", freqKHz: 7041.4, spotter: "N4EMP", comment: "",
             receivedAt: utc("2026-07-25 22:15:25"), county: "LAWR", source: .hub),
        Spot(call: "N4NM", freqKHz: 7043.4, spotter: "N4EMP", comment: "",
             receivedAt: utc("2026-07-25 22:08:43"), county: "MDSN", source: .hub),
        Spot(call: "KC4TEO", freqKHz: 7047.0, spotter: "N4EMP", comment: "RIGHT CALL",
             receivedAt: utc("2026-07-25 22:01:10"), county: "MDSN", source: .hub),
        Spot(call: "KC4TE", freqKHz: 7047.0, spotter: "N4EMP", comment: "",
             receivedAt: utc("2026-07-25 21:57:30"), county: "MDSN", source: .hub),
    ]

    /// The defect this exists to prevent, stated as it would have reached the
    /// operator: every hub spot purged on arrival, an empty band map, and
    /// nothing to distinguish that from a broken parser.
    @MainActor
    func testLiveHubSpotsSurviveTheClusterTunedWindow() {
        let store = SpotStore()
        store.maxAgeMinutes = 15
        for spot in Self.liveALQPSpots { store.add(spot) }
        store.purge(now: Self.pollTime)

        XCTAssertEqual(
            Set(store.all.map(\.call)),
            ["W4NBS", "N4NM", "KC4TEO", "KC4TE"],
            "all four live spots are inside the hub's own 60-minute retention"
        )
    }

    /// The cluster window is genuinely unchanged — this is not a blanket
    /// loosening that would leave stale skimmer spots on the map.
    @MainActor
    func testClusterSpotsStillAgeOutAtFifteenMinutes() {
        let store = SpotStore()
        store.maxAgeMinutes = 15
        store.add(Spot(call: "K5OLD", freqKHz: 14002.0, spotter: "W3LPL", comment: "",
                       receivedAt: Self.pollTime.addingTimeInterval(-16 * 60)))
        store.add(Spot(call: "K5NEW", freqKHz: 14003.0, spotter: "W3LPL", comment: "",
                       receivedAt: Self.pollTime.addingTimeInterval(-60)))
        store.purge(now: Self.pollTime)

        XCTAssertEqual(store.all.map(\.call), ["K5NEW"])
    }

    /// Both feeds in one store, each aged by its own rule.
    @MainActor
    func testEachSourceIsAgedByItsOwnWindow() {
        let store = SpotStore()
        store.maxAgeMinutes = 15
        store.hubMaxAgeMinutes = 60

        store.add(Spot(call: "K5CLUS", freqKHz: 14002.0, spotter: "W3LPL", comment: "",
                       receivedAt: Self.pollTime.addingTimeInterval(-30 * 60)))
        store.add(Spot(call: "K5HUB", freqKHz: 14003.0, spotter: "N4EMP", comment: "",
                       receivedAt: Self.pollTime.addingTimeInterval(-30 * 60),
                       county: "MDSN", source: .hub))
        store.purge(now: Self.pollTime)

        XCTAssertEqual(store.all.map(\.call), ["K5HUB"],
                       "same age, different source, different verdict")
    }

    /// A hub spot older than the hub's own retention is still dropped.
    @MainActor
    func testHubSpotsDoNotLiveForever() {
        let store = SpotStore()
        store.hubMaxAgeMinutes = 60
        store.add(Spot(call: "K5STALE", freqKHz: 14002.0, spotter: "N4EMP", comment: "",
                       receivedAt: Self.pollTime.addingTimeInterval(-61 * 60),
                       county: "MDSN", source: .hub))
        store.purge(now: Self.pollTime)

        XCTAssertTrue(store.all.isEmpty)
    }

    /// A spot built without the new fields is a cluster spot with no county,
    /// so every existing call site keeps its exact behaviour.
    func testDefaultsPreserveClusterBehaviour() {
        let spot = Spot(call: "K5ABC", freqKHz: 14026.1, spotter: "W3LPL",
                        comment: "", receivedAt: Date())
        XCTAssertEqual(spot.source, .cluster)
        XCTAssertNil(spot.county)
    }

    /// A later cluster spot must not strip the county off a hub spot. The
    /// county is what un-hides a rover that has moved — losing it silently
    /// re-hides the best remaining multiplier on the band.
    @MainActor
    func testClusterRespotDoesNotEraseTheCounty() throws {
        let store = SpotStore()
        let t0 = Self.pollTime.addingTimeInterval(-120)

        store.add(Spot(call: "K0ABC", freqKHz: 14045.0, spotter: "K0ABC", comment: "",
                       receivedAt: t0, county: "MINN", source: .hub))
        store.add(Spot(call: "K0ABC", freqKHz: 14045.2, spotter: "W3LPL", comment: "loud",
                       receivedAt: t0.addingTimeInterval(60)))

        XCTAssertEqual(store.all.count, 1, "same call+band is still one entry")
        let merged = try XCTUnwrap(store.all.first)
        XCTAssertEqual(merged.county, "MINN", "the county survives the newer cluster spot")
        XCTAssertEqual(merged.freqKHz, 14045.2, accuracy: 0.001,
                       "but the newer report still wins on frequency")
    }
}

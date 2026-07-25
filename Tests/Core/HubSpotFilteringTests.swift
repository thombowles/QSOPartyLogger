import XCTest
@testable import QSOPartyLogger

/// How hub spots behave on the band map once they are in the store.
///
/// The county is worth more for *un-hiding* stations than for labelling them.
/// `DupeChecker.DupeKey` already includes `theirLoc`, so the scoring engine
/// knows a mobile in a new county is a new contact — but the band map has
/// always keyed worked-tracking on the callsign alone. Left that way, a rover
/// you have worked stays greyed, skipped by ⌘←/⌘→ and hidden under "hide
/// worked" for the rest of the contest, however many needed counties it drives
/// through. Rovers are the largest multiplier source in a state QSO party.
final class HubSpotFilteringTests: XCTestCase {

    private func spot(
        call: String = "K0ABC",
        freqKHz: Double = 14045.0,
        county: String? = nil,
        source: SpotSource = .hub,
        superseded: Bool = false
    ) -> Spot {
        Spot(call: call, freqKHz: freqKHz, spotter: "N4EMP", comment: "",
             receivedAt: Date(), county: county, source: source,
             isSuperseded: superseded)
    }

    // MARK: Rover un-hiding

    /// The whole point: worked in Lincoln, now reporting from Minnehaha, so
    /// there is a fresh multiplier on offer and the spot must be visible.
    func testRoverInANewCountyIsNotTreatedAsWorked() {
        var options = SpotFilter.Options()
        options.hideWorked = true
        options.workedCalls = ["K0ABC"]
        options.workedCallCounties = ["K0ABC|LINC"]

        XCTAssertTrue(SpotFilter.matches(spot(county: "MINN"), options: options))
    }

    /// The same station in the same county really is worked.
    func testSameStationSameCountyStaysHidden() {
        var options = SpotFilter.Options()
        options.hideWorked = true
        options.workedCalls = ["K0ABC"]
        options.workedCallCounties = ["K0ABC|LINC"]

        XCTAssertFalse(SpotFilter.matches(spot(county: "LINC"), options: options))
    }

    /// A cluster spot carries no county, so it can only be judged on the call
    /// — exactly as before.
    func testClusterSpotsStillMatchOnCallAlone() {
        var options = SpotFilter.Options()
        options.hideWorked = true
        options.workedCalls = ["K0ABC"]
        options.workedCallCounties = ["K0ABC|LINC"]

        XCTAssertFalse(
            SpotFilter.matches(spot(county: nil, source: .cluster), options: options)
        )
    }

    /// ⌘←/⌘→ works from the same judgement, so the keys cannot disagree with
    /// what the map is showing.
    func testSpotKeysStopOnARoverThatHasMoved() {
        let spots = [
            spot(call: "K0ABC", freqKHz: 14045.0, county: "MINN"),
            spot(call: "W0XYZ", freqKHz: 14060.0, county: "LINC"),
        ]
        let next = SpotStore.next(
            in: spots, afterKHz: 14000, direction: .up,
            workedCalls: ["K0ABC", "W0XYZ"],
            workedCallCounties: ["K0ABC|LINC", "W0XYZ|LINC"]
        )
        XCTAssertEqual(next?.call, "K0ABC",
                       "worked in Lincoln, spotted from Minnehaha — still workable")
    }

    /// With no county information at all the keys behave exactly as they did.
    func testSpotKeysUnchangedWithoutCountyData() {
        let spots = [
            spot(call: "K0ABC", freqKHz: 14045.0, county: nil, source: .cluster),
            spot(call: "W0XYZ", freqKHz: 14060.0, county: nil, source: .cluster),
        ]
        let next = SpotStore.next(in: spots, afterKHz: 14000, direction: .up,
                                  workedCalls: ["K0ABC"])
        XCTAssertEqual(next?.call, "W0XYZ")
    }

    // MARK: Superseded

    /// A call the board has already corrected is not somewhere to send the
    /// radio.
    func testSpotKeysStepOverASupersededCall() {
        let spots = [
            spot(call: "KC4TE", freqKHz: 7047.0, county: "MDSN", superseded: true),
            spot(call: "KC4TEO", freqKHz: 7047.5, county: "MDSN"),
        ]
        let next = SpotStore.next(in: spots, afterKHz: 7000, direction: .up)
        XCTAssertEqual(next?.call, "KC4TEO")
    }

    // MARK: Source filter

    /// Hundreds of cluster spots against a handful from the hub. When the
    /// operator is hunting counties, the county-bearing feed has to be
    /// isolatable or it is simply buried.
    func testHubOnlyFilterHidesClusterSpots() {
        var options = SpotFilter.Options()
        options.sources = [.hub]

        XCTAssertTrue(SpotFilter.matches(spot(county: "MDSN"), options: options))
        XCTAssertFalse(
            SpotFilter.matches(spot(county: nil, source: .cluster), options: options)
        )
    }

    /// Empty means no restriction, so nothing changes by default.
    func testEmptySourceSetShowsEverything() {
        let options = SpotFilter.Options()
        XCTAssertTrue(SpotFilter.matches(spot(county: "MDSN"), options: options))
        XCTAssertTrue(
            SpotFilter.matches(spot(county: nil, source: .cluster), options: options)
        )
    }

    /// A source filter counts as narrowing the view, so the funnel has to show
    /// as active — otherwise spots vanish with no visible cause.
    func testSourceFilterCountsAsAnActiveFilter() {
        var options = SpotFilter.Options()
        options.sources = [.hub]
        XCTAssertTrue(options.isActive)
    }
}

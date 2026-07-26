import XCTest
@testable import QSOPartyLogger

/// Stations from your own log, on the band map.
///
/// A station nobody spotted left no mark there at all: work him, tune past his
/// frequency ten minutes later, and nothing on screen says it is occupied by
/// someone already in the log. N1MM's bandmap has always carried locally-added
/// calls beside network ones — *"Bold – This is a self-spotted call. In this
/// context 'self spotted' means that the user typed in the call, not that the
/// spot came from the spotting network"* — greyed once worked (`"Gray: Dupe"`),
/// on the one timeout the whole map shares.
final class WorkedStationSpotTests: XCTestCase {

    private static let logged = Date(timeIntervalSince1970: 1_760_000_000)

    private func qso(
        call: String = "K0ABC",
        band: Band = .m40,
        freqKHz: Int? = 7047,
        theirLoc: String = "MDSN",
        groupID: UUID = UUID(),
        myLoc: String = "TX"
    ) -> QSO {
        QSO(groupID: groupID, timestampUTC: Self.logged, call: call, band: band,
            modeClass: .cw, rawMode: "CW", freqKHz: freqKHz,
            rstSent: "599", rstRcvd: "599", myLoc: myLoc, theirLoc: theirLoc)
    }

    // MARK: A contact becomes a spot

    func testALoggedContactBecomesASpotAtItsOwnFrequency() throws {
        let spot = try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "KE5CW"))

        XCTAssertEqual(spot.call, "K0ABC")
        XCTAssertEqual(spot.freqKHz, 7047)
        XCTAssertEqual(spot.receivedAt, Self.logged)
    }

    /// It came from your log, not from a feed — and the spotter is you.
    func testTheSpotIsMarkedAsComingFromYourOwnLog() throws {
        let spot = try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "ke5cw"))

        XCTAssertEqual(spot.source, .local)
        XCTAssertEqual(spot.spotter, "KE5CW")
    }

    /// `workedCallCounties` is built as `CALL|THEIRLOC`, so carrying `theirLoc`
    /// through is what makes the spot draw struck-through the instant it lands
    /// rather than looking like a fresh station to call.
    func testTheContactsLocationRidesAlongSoTheSpotGreysOutAtOnce() throws {
        let spot = try XCTUnwrap(WorkedSpot.spot(for: qso(theirLoc: "mdsn"), myCall: "KE5CW"))

        XCTAssertEqual(spot.county, "MDSN")
        XCTAssertTrue(
            SpotFilter.isWorked(spot, workedCalls: [], workedCallCounties: ["K0ABC|MDSN"])
        )
    }

    /// No radio, no frequency, nowhere to draw it. Inventing one would put a
    /// station on a frequency he was never on.
    func testAContactLoggedWithoutARadioMakesNoSpot() {
        XCTAssertNil(WorkedSpot.spot(for: qso(freqKHz: nil), myCall: "KE5CW"))
    }

    /// A county-line contact expands to one row per county but is one contact,
    /// on one frequency, with one station on it.
    func testACountyLineContactMakesOneSpot() {
        let group = UUID()
        let rows = [
            qso(groupID: group, myLoc: "MDSN"),
            qso(groupID: group, myLoc: "LIME"),
        ]

        XCTAssertEqual(WorkedSpot.spots(for: rows, myCall: "KE5CW").count, 1)
    }

    // MARK: Only when the band is clear

    @MainActor
    func testAWorkedStationIsAddedWhenNothingElseHasSpottedHim() throws {
        let store = SpotStore()
        let spot = try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "KE5CW"))

        store.addIfAbsent(spot)

        XCTAssertEqual(store.all.map(\.call), ["K0ABC"])
    }

    /// The operator asked for the station to be added when it is *not* spotted.
    /// A spot already on the map keeps its own reported frequency and simply
    /// greys out — being worked is not a reason to move someone else's spot.
    @MainActor
    func testAnExistingSpotForThatStationKeepsItsPlace() throws {
        let store = SpotStore()
        store.add(Spot(call: "K0ABC", freqKHz: 7042.5, spotter: "N4EMP", comment: "",
                       receivedAt: Self.logged, county: "MDSN", source: .hub))

        store.addIfAbsent(try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "KE5CW")))

        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all.first?.freqKHz, 7042.5)
        XCTAssertEqual(store.all.first?.source, .hub)
    }

    /// Same call, other band: a different spot entirely, and one worth having.
    @MainActor
    func testTheSameStationOnAnotherBandIsStillAdded() throws {
        let store = SpotStore()
        store.add(Spot(call: "K0ABC", freqKHz: 14042.5, spotter: "N4EMP", comment: "",
                       receivedAt: Self.logged, county: "MDSN", source: .hub))

        store.addIfAbsent(try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "KE5CW")))

        XCTAssertEqual(store.all.count, 2)
    }

    // MARK: Lifetime

    /// One timeout for the map, the operator's own "Age out after" setting —
    /// a station you worked twenty minutes ago has very likely moved. The hub's
    /// longer life is for hand-posted spots and stays as it was.
    @MainActor
    func testAWorkedStationAgesOutOnTheClusterTimeout() throws {
        let store = SpotStore()
        store.maxAgeMinutes = 15
        store.hubMaxAgeMinutes = 60
        store.addIfAbsent(try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "KE5CW")))
        store.add(Spot(call: "W1XYZ", freqKHz: 7052, spotter: "N4EMP", comment: "",
                       receivedAt: Self.logged, county: "LIME", source: .hub))

        store.purge(now: Self.logged.addingTimeInterval(20 * 60))

        XCTAssertEqual(store.all.map(\.call), ["W1XYZ"])
    }

    // MARK: Filters

    /// "QSO Party Hub spots only" chooses between feeds. Your own log is not
    /// one of them, so it is never what that toggle is hiding.
    func testYourOwnStationsSurviveTheHubOnlyFilter() throws {
        var options = SpotFilter.Options()
        options.sources = [.hub]

        let spot = try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "KE5CW"))

        XCTAssertTrue(SpotFilter.matches(spot, options: options))
    }

    /// "Hide stations already worked" is the control that clears them, and it
    /// clears all of them: every station in your log is worked by definition.
    func testHideWorkedClearsThem() throws {
        var options = SpotFilter.Options()
        options.hideWorked = true
        options.workedCallCounties = ["K0ABC|MDSN"]

        let spot = try XCTUnwrap(WorkedSpot.spot(for: qso(), myCall: "KE5CW"))

        XCTAssertFalse(SpotFilter.matches(spot, options: options))
    }
}

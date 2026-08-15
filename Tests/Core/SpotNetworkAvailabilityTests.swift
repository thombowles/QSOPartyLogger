import XCTest
@testable import QSOPartyLogger

/// Which networks the spot sheet offers, and the reason given when one is
/// not — the thing to change, named, so a greyed checkbox is never a mystery.
final class SpotNetworkAvailabilityTests: XCTestCase {

    private func context(
        clusterConnected: Bool = true,
        clusterHost: String = "dxc.wa9pie.net",
        clusterBlockedReason: String? = nil,
        hubHost: String? = "qsopartyhub.com",
        target: SpotNetworkAvailability.Target = .myself,
        myParks: [String] = ["US-0817"],
        draftPark: String = ""
    ) -> SpotNetworkAvailability.Context {
        .init(
            clusterConnected: clusterConnected, clusterHost: clusterHost,
            clusterBlockedReason: clusterBlockedReason, hubHost: hubHost,
            target: target, myParks: myParks, draftPark: draftPark
        )
    }

    // MARK: Cluster

    func testAConnectedClusterIsOfferedByHost() {
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .cluster, in: context()),
            .available("dxc.wa9pie.net")
        )
    }

    func testADisconnectedClusterSaysHowToConnect() {
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .cluster, in: context(clusterConnected: false)),
            .unavailable(SpotNetworkAvailability.clusterNotConnected)
        )
    }

    /// NON-ASSISTED cannot connect at all; the reason shown is the policy's
    /// own, passed in, so this file owes nothing to the layer that owns it.
    func testABlockedClusterCarriesThePolicyReason() {
        XCTAssertEqual(
            SpotNetworkAvailability.availability(
                of: .cluster, in: context(clusterConnected: true, clusterBlockedReason: "blocked")
            ),
            .unavailable("blocked")
        )
    }

    // MARK: Hub

    func testTheHubIsOfferedOnlyWhenThePartyHasAPage() {
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .hub, in: context()),
            .available("qsopartyhub.com")
        )
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .hub, in: context(hubHost: nil)),
            .unavailable(SpotNetworkAvailability.noHubPage)
        )
    }

    // MARK: POTA

    func testSpottingYourselfOnPotaNeedsAnActivation() {
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .pota, in: context()),
            .available("pota.app · US-0817")
        )
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .pota, in: context(myParks: [])),
            .unavailable(SpotNetworkAvailability.noOwnPark)
        )
    }

    /// For another station the park is whatever the draft holds — typing one
    /// is what enables the row.
    func testSpottingAnotherStationOnPotaNeedsTheirPark() {
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .pota, in: context(target: .station, draftPark: "")),
            .unavailable(SpotNetworkAvailability.noTheirPark)
        )
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .pota, in: context(target: .station, draftPark: "us-3051")),
            .available("pota.app")
        )
        XCTAssertEqual(
            SpotNetworkAvailability.availability(of: .pota, in: context(target: .station, draftPark: "USA-3051")),
            .unavailable(SpotNetworkAvailability.noTheirPark)
        )
    }

    // MARK: The set, and the door

    func testAvailableIsTheSetOfOfferedNetworks() {
        XCTAssertEqual(SpotNetworkAvailability.available(in: context(clusterConnected: false)), [.hub, .pota])
        XCTAssertEqual(SpotNetworkAvailability.available(in: context()), [.cluster, .hub, .pota])
    }

    /// The sheet can open for another station with nothing on offer yet: its
    /// POTA row carries the park field, so typing one is the way in. For
    /// yourself there is nothing to type, so nothing on offer means no sheet.
    func testTheSheetOpensForAStationEvenWithNothingOffered() {
        let bare = context(clusterConnected: false, hubHost: nil, target: .station, myParks: [])
        XCTAssertTrue(SpotNetworkAvailability.canOpenSheet(in: bare))
        let bareSelf = context(clusterConnected: false, hubHost: nil, target: .myself, myParks: [])
        XCTAssertFalse(SpotNetworkAvailability.canOpenSheet(in: bareSelf))
        XCTAssertTrue(SpotNetworkAvailability.canOpenSheet(in: context(clusterConnected: false, hubHost: nil)))
    }

    func testAvailabilityTextIsTheHostOrTheReason() {
        XCTAssertEqual(SpotNetworkAvailability.Availability.available("x").text, "x")
        XCTAssertEqual(SpotNetworkAvailability.Availability.unavailable("y").text, "y")
        XCTAssertTrue(SpotNetworkAvailability.Availability.available("x").isAvailable)
        XCTAssertFalse(SpotNetworkAvailability.Availability.unavailable("y").isAvailable)
    }
}

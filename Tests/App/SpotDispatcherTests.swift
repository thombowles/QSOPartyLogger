import XCTest
@testable import QSOPartyLogger

/// One draft, every ticked network, one receipt — through scripted
/// transports; nothing here touches TCP or HTTP.
@MainActor
final class SpotDispatcherTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private var alqp: PartyDefinition { PartyCatalog.party(id: "alqp")! }

    final class Recorder {
        var clusterCommands: [String] = []
        var clusterConnected = true
        var hubPosts: [(HubSelfSpot.Fields, PartyDefinition)] = []
        var potaPosts: [PotaSpot.Fields] = []
    }

    private func dispatcher(_ r: Recorder) -> SpotDispatcher {
        SpotDispatcher(transports: .init(
            sendClusterCommand: { r.clusterCommands.append($0); return r.clusterConnected },
            postToHub: { fields, party in r.hubPosts.append((fields, party)) },
            postToPota: { r.potaPosts.append($0) }
        ))
    }

    private func draft(_ networks: Set<SpotNetwork>) -> SpotDraft {
        SpotDraft(station: "KE5CW", frequencyKHz: 7047, county: "MDSN", comment: "",
                  poster: "KE5CW", park: "US-0817", mode: "CW", networks: networks)
    }

    private func spot(call: String, spotter: String = "KE5CW", kHz: Double = 7047.0) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: spotter, comment: "", receivedAt: t0)
    }

    // MARK: Fan-out

    func testOnlyTickedNetworksAreSentTo() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.cluster, .pota]), party: alqp, now: t0)
        XCTAssertEqual(r.clusterCommands, ["DX 7047 KE5CW AL-QSO-PARTY MDSN"])
        XCTAssertTrue(r.hubPosts.isEmpty)
        XCTAssertEqual(r.potaPosts.count, 1)
        XCTAssertEqual(r.potaPosts.first?.reference, "US-0817")
        XCTAssertEqual(d.receipt?.networks, [.cluster, .pota])
        XCTAssertEqual(d.receipt?.states[.cluster], .sent(t0))
        XCTAssertEqual(d.receipt?.states[.pota], .sending)
        XCTAssertEqual(d.receipt?.title, "KE5CW 7047")
    }

    func testTheHubGetsItsFieldsAndTheParty() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.hub]), party: alqp, now: t0)
        XCTAssertEqual(r.hubPosts.count, 1)
        XCTAssertEqual(r.hubPosts.first?.0.county, "MDSN")
        XCTAssertEqual(r.hubPosts.first?.1.id, "alqp")
        XCTAssertEqual(d.receipt?.states[.hub], .sending)
    }

    func testAClusterWithNoSessionFails() {
        let r = Recorder()
        r.clusterConnected = false
        let d = dispatcher(r)
        d.send(draft([.cluster]), party: alqp, now: t0)
        XCTAssertEqual(d.receipt?.states[.cluster], .failed("Cluster not connected."))
    }

    // MARK: Echo

    func testTheNodesEchoConfirmsTheClusterSpot() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.cluster]), party: alqp, now: t0)
        d.noteIncomingSpot(spot(call: "N4RT"), now: t0)
        XCTAssertEqual(d.receipt?.states[.cluster], .sent(t0), "somebody else's spot is not our echo")
        d.noteIncomingSpot(spot(call: "KE5CW"), now: t0.addingTimeInterval(2))
        XCTAssertEqual(d.receipt?.states[.cluster], .confirmed)
        XCTAssertEqual(d.receipt?.changedAt, t0.addingTimeInterval(2))
    }

    /// An echo for a spot that was never sent to the cluster — or arriving
    /// after a new send replaced the receipt — changes nothing.
    func testAStrayEchoIsIgnored() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.hub]), party: alqp, now: t0)
        d.noteIncomingSpot(spot(call: "KE5CW"), now: t0)
        XCTAssertNil(d.receipt?.states[.cluster])
        d.send(draft([.cluster]), party: alqp, now: t0.addingTimeInterval(400))
        d.send(draft([.pota]), party: alqp, now: t0.addingTimeInterval(800))
        d.noteIncomingSpot(spot(call: "KE5CW"), now: t0.addingTimeInterval(801))
        XCTAssertNil(d.receipt?.states[.cluster])
    }

    // MARK: Client reports

    func testClientStatesFlowIntoTheReceipt() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.hub, .pota]), party: alqp, now: t0)
        d.update(.hub, state: .sent(t0), now: t0)
        d.update(.pota, state: .confirmed, now: t0)
        XCTAssertEqual(d.receipt?.states[.hub], .sent(t0))
        XCTAssertEqual(d.receipt?.states[.pota], .confirmed)
        // A network this send did not go to is ignored.
        d.update(.cluster, state: .confirmed, now: t0)
        XCTAssertNil(d.receipt?.states[.cluster])
    }

    // MARK: Guards

    func testAnIdenticalClusterSpotInsideFiveMinutesIsRefused() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.cluster]), party: alqp, now: t0)
        d.send(draft([.cluster]), party: alqp, now: t0.addingTimeInterval(30))
        XCTAssertEqual(r.clusterCommands.count, 1)
        XCTAssertEqual(
            d.receipt?.states[.cluster],
            .failed("That spot just went out to the node — nothing has changed since.")
        )
    }

    func testAChangedClusterSpotGoesOutAgain() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.cluster]), party: alqp, now: t0)
        var moved = draft([.cluster])
        moved.frequencyKHz = 7050
        d.send(moved, party: alqp, now: t0.addingTimeInterval(30))
        XCTAssertEqual(r.clusterCommands.count, 2)
        XCTAssertEqual(d.receipt?.states[.cluster], .sent(t0.addingTimeInterval(30)))
    }

    /// The hub and POTA clients keep their own repeat guards; the dispatcher
    /// never second-guesses them.
    func testHubAndPotaRepeatsAreTheClientsToJudge() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.hub, .pota]), party: alqp, now: t0)
        d.send(draft([.hub, .pota]), party: alqp, now: t0.addingTimeInterval(30))
        XCTAssertEqual(r.hubPosts.count, 2)
        XCTAssertEqual(r.potaPosts.count, 2)
    }

    // MARK: Receipt lifecycle

    func testDismissHidesTheReceipt() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.hub]), party: alqp, now: t0)
        d.dismiss(now: t0.addingTimeInterval(1))
        XCTAssertEqual(d.receipt?.isVisible(now: t0.addingTimeInterval(2)), false)
    }

    func testANewSendReplacesTheReceipt() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([.hub]), party: alqp, now: t0)
        d.send(draft([.pota]), party: alqp, now: t0.addingTimeInterval(400))
        XCTAssertEqual(d.receipt?.networks, [.pota])
        XCTAssertNil(d.receipt?.dismissedAt)
    }

    func testNothingTickedSendsNothingAndLeavesNoReceipt() {
        let r = Recorder()
        let d = dispatcher(r)
        d.send(draft([]), party: alqp, now: t0)
        XCTAssertTrue(r.clusterCommands.isEmpty && r.hubPosts.isEmpty && r.potaPosts.isEmpty)
        XCTAssertNil(d.receipt)
    }
}

/// The remembered choice of networks.
final class SpotNetworkPreferenceTests: XCTestCase {

    func testDefaultsToEveryNetworkAndRoundTrips() {
        let suite = UserDefaults(suiteName: "SpotNetworkPreferenceTests-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: suite)
        XCTAssertEqual(settings.spotNetworks, Set(SpotNetwork.allCases))
        settings.spotNetworks = [.hub]
        XCTAssertEqual(AppSettings(defaults: suite).spotNetworks, [.hub])
        settings.spotNetworks = []
        XCTAssertEqual(AppSettings(defaults: suite).spotNetworks, [])
    }

    func testAnUnknownStoredNetworkIsDropped() {
        let suite = UserDefaults(suiteName: "SpotNetworkPreferenceTests-\(UUID().uuidString)")!
        suite.set(["hub", "telegraph"], forKey: "spotNetworks")
        XCTAssertEqual(AppSettings(defaults: suite).spotNetworks, [.hub])
    }
}

import XCTest
@testable import QSOPartyLogger

/// The sheet's one model, and what each network gets from it.
final class SpotDraftTests: XCTestCase {

    private var alqp: PartyDefinition { PartyCatalog.party(id: "alqp")! }

    private func draft(networks: Set<SpotNetwork> = [.cluster, .hub, .pota]) -> SpotDraft {
        SpotDraft(station: "KE5CW", frequencyKHz: 7047, county: "MDSN", comment: "mobile",
                  poster: "KE5CW", park: "US-0817", mode: "CW", networks: networks)
    }

    func testEachNetworkGetsItsOwnPayload() {
        let d = draft()
        XCTAssertEqual(
            d.hubFields,
            HubSelfSpot.Fields(station: "KE5CW", frequencyKHz: 7047, county: "MDSN",
                               comment: "mobile", poster: "KE5CW")
        )
        XCTAssertEqual(
            d.clusterFields(party: alqp),
            ClusterSpot.Fields(call: "KE5CW", frequencyKHz: 7047, remarks: "AL-QSO-PARTY MDSN mobile")
        )
        XCTAssertEqual(
            d.potaFields,
            PotaSpot.Fields(activator: "KE5CW", spotter: "KE5CW", frequencyKHz: 7047,
                            reference: "US-0817", mode: "CW", comments: "mobile")
        )
    }

    /// A hub-only objection blocks the hub, not the cluster; a POTA-only
    /// objection blocks POTA. Each is shown under its own row.
    func testProblemsAreKeyedToTheNetworkTheyBelongTo() {
        var d = draft()
        d.county = "ZZZZ"      // not a county of this party — the hub's rule
        d.park = "USA-0817"    // not a reference the form takes — POTA's rule
        let problems = d.problems(party: alqp)
        XCTAssertEqual(Set(problems.keys), [.hub, .pota])
        XCTAssertEqual(problems[.hub], "ZZZZ isn't a county in this party.")
        XCTAssertEqual(problems[.pota], "USA-0817 isn't a reference pota.app accepts — they look like US-0817.")
        XCTAssertNil(d.problem(for: .cluster, party: alqp))
    }

    func testOnlyTickedNetworksAreJudged() {
        var d = draft(networks: [.cluster])
        d.park = "bad"
        XCTAssertTrue(d.problems(party: alqp).isEmpty)
        XCTAssertTrue(d.canPost(party: alqp))
        // …but the objection is still there to be shown if the row is ticked.
        XCTAssertNotNil(d.problem(for: .pota, party: alqp))
    }

    func testPostNeedsSomethingTickedAndNothingTickedBroken() {
        XCTAssertFalse(draft(networks: []).canPost(party: alqp))
        var d = draft(networks: [.pota])
        d.park = ""
        XCTAssertFalse(d.canPost(party: alqp))
        XCTAssertTrue(draft().canPost(party: alqp))
    }

    /// The whole point of a confirming sheet: nothing that goes out is a
    /// surprise.
    func testPreviewsShowExactlyWhatGoesOut() {
        let d = draft()
        XCTAssertEqual(d.preview(for: .cluster, party: alqp), "DX 7047 KE5CW AL-QSO-PARTY MDSN mobile")
        XCTAssertEqual(d.preview(for: .hub, party: alqp), "KE5CW 7047 MDSN mobile")
        XCTAssertEqual(d.preview(for: .pota, party: alqp), "US-0817 · CW · mobile")
        var bare = d
        bare.county = nil; bare.comment = ""; bare.mode = ""
        XCTAssertEqual(bare.preview(for: .hub, party: alqp), "KE5CW 7047")
        XCTAssertEqual(bare.preview(for: .pota, party: alqp), "US-0817")
    }

    /// A network that stopped being on offer while the sheet was open — the
    /// node dropped — is not sent to.
    func testSendingKeepsOnlyOfferedNetworks() {
        XCTAssertEqual(draft().sending(available: [.hub]).networks, [.hub])
        XCTAssertEqual(draft().sending(available: []).networks, [])
    }

    func testTheEmptyDraftIsBlank() {
        XCTAssertEqual(SpotDraft.empty.station, "")
        XCTAssertEqual(SpotDraft.empty.frequencyKHz, 0)
        XCTAssertNil(SpotDraft.empty.county)
        XCTAssertTrue(SpotDraft.empty.networks.isEmpty)
    }
}

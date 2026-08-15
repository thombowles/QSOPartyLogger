import XCTest
@testable import QSOPartyLogger

/// What the operator is told after Post, and for how long.
final class SpotReceiptTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func receipt(_ states: [SpotNetwork: SpotSendState]) -> SpotReceipt {
        SpotReceipt(station: "KE5CW", frequencyKHz: 7047, states: states, changedAt: t0)
    }

    // MARK: Wording

    func testLinesNameTheNetworkAndItsState() {
        let r = receipt([
            .cluster: .confirmed, .hub: .sent(t0),
            .pota: .failed("pota.app refused the spot (HTTP 500)."),
        ])
        XCTAssertEqual(r.line(for: .cluster), "Cluster — echoed by the node")
        XCTAssertEqual(r.line(for: .hub), "Hub — sent, watching the board")
        XCTAssertEqual(r.line(for: .pota), "POTA — pota.app refused the spot (HTTP 500).")
        XCTAssertEqual(receipt([.hub: .confirmed]).line(for: .hub), "Hub — on the board")
        XCTAssertEqual(receipt([.pota: .confirmed]).line(for: .pota), "POTA — on pota.app")
        XCTAssertEqual(receipt([.pota: .sent(t0)]).line(for: .pota), "POTA — sent, watching pota.app")
        XCTAssertEqual(receipt([.cluster: .sent(t0)]).line(for: .cluster), "Cluster — sent to the node")
        XCTAssertEqual(receipt([.cluster: .sending]).line(for: .cluster), "Cluster — sending…")
    }

    func testTheSummaryListsNetworksInOrder() {
        XCTAssertEqual(
            receipt([.pota: .confirmed, .cluster: .confirmed]).summary,
            "Cluster — echoed by the node · POTA — on pota.app"
        )
        XCTAssertEqual(receipt([:]).title, "KE5CW 7047")
        XCTAssertEqual(receipt([.hub: .sending, .cluster: .sending]).networks, [.cluster, .hub])
    }

    // MARK: Tint

    func testTintIsBadOnAnyFailureGoodWhenAllConfirmedElsePending() {
        XCTAssertEqual(receipt([.hub: .confirmed, .pota: .failed("x")]).tint, .bad)
        XCTAssertEqual(receipt([.hub: .confirmed, .pota: .confirmed]).tint, .good)
        // "Sent" is provisional and stays neutral.
        XCTAssertEqual(receipt([.hub: .confirmed, .pota: .sent(t0)]).tint, .pending)
        XCTAssertEqual(receipt([.hub: .sending]).tint, .pending)
        XCTAssertEqual(receipt([:]).tint, .pending)
    }

    // MARK: Visibility

    func testVisibleForTwelveSecondsAfterAChangeWhenNothingFailed() {
        let r = receipt([.hub: .confirmed])
        XCTAssertTrue(r.isVisible(now: t0))
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(11.9)))
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(12)))
    }

    func testVisibleForAMinuteWhenSomethingFailed() {
        let r = receipt([.hub: .failed("x"), .pota: .confirmed])
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(59)))
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(60)))
    }

    /// The hub's poll saying the spot never appeared lands two minutes after
    /// Post — long after the capsule has gone. It comes back to say so.
    func testALateChangeReShowsIt() {
        var r = receipt([.hub: .sent(t0)])
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(100)))
        r.set(.confirmed, for: .hub, at: t0.addingTimeInterval(100))
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(101)))
        XCTAssertEqual(r.changedAt, t0.addingTimeInterval(100))
    }

    func testDismissHidesUntilTheNextChange() {
        var r = receipt([.hub: .sent(t0)])
        r.dismiss(at: t0.addingTimeInterval(1))
        XCTAssertFalse(r.isVisible(now: t0.addingTimeInterval(2)))
        r.set(.failed("gone"), for: .hub, at: t0.addingTimeInterval(3))
        XCTAssertTrue(r.isVisible(now: t0.addingTimeInterval(4)))
    }

    func testOnlyNetworksInTheReceiptTakeUpdatesAndUnchangedStatesDoNotRearm() {
        var r = receipt([.hub: .sent(t0)])
        r.set(.confirmed, for: .pota, at: t0.addingTimeInterval(5))
        XCTAssertNil(r.states[.pota])
        XCTAssertEqual(r.changedAt, t0)
        r.set(.sent(t0), for: .hub, at: t0.addingTimeInterval(5))
        XCTAssertEqual(r.changedAt, t0)
    }

    func testFailedNetworksAndSettlement() {
        let r = receipt([.cluster: .sent(t0), .hub: .failed("x"), .pota: .sending])
        XCTAssertEqual(r.failedNetworks, [.hub])
        XCTAssertFalse(r.isSettled)
        XCTAssertTrue(receipt([.cluster: .sent(t0)]).isSettled)
        XCTAssertTrue(receipt([.cluster: .failed("x")]).isSettled)
    }
}

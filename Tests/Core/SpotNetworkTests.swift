import XCTest
@testable import QSOPartyLogger

/// The three places a spot can go, and how the sheet remembers which ones
/// the operator wants.
final class SpotNetworkTests: XCTestCase {

    func testTheSheetOpensWithTheOfferedNetworksTheOperatorKeptLastTime() {
        XCTAssertEqual(
            SpotNetwork.initialSelection(available: [.cluster, .hub], preferred: [.hub, .pota]),
            [.hub]
        )
    }

    /// POTA was not on offer — a home weekend — so it keeps its bit for the
    /// next park rather than being un-ticked by a post it took no part in.
    func testAPostMovesOnlyTheNetworksTheSheetOffered() {
        XCTAssertEqual(
            SpotNetwork.updatedPreference(
                preferred: [.cluster, .hub, .pota], available: [.cluster, .hub], selected: [.hub]
            ),
            [.hub, .pota]
        )
    }

    func testTickingAnOfferedNetworkRemembersIt() {
        XCTAssertEqual(
            SpotNetwork.updatedPreference(
                preferred: [.hub], available: [.cluster, .hub], selected: [.cluster, .hub]
            ),
            [.cluster, .hub]
        )
    }

    /// A network ticked but no longer on offer at Post cannot become a
    /// preference through the back door.
    func testAnUnofferedSelectionDoesNotLeakIntoThePreference() {
        XCTAssertEqual(
            SpotNetwork.updatedPreference(preferred: [], available: [.hub], selected: [.hub, .pota]),
            [.hub]
        )
    }

    func testShortcutDigitsAreOneTwoThreeInListOrder() {
        XCTAssertEqual(SpotNetwork.allCases.map(\.shortcutDigit), ["1", "2", "3"])
    }

    func testRawValuesRoundTrip() {
        for network in SpotNetwork.allCases {
            XCTAssertEqual(SpotNetwork(rawValue: network.rawValue), network)
        }
    }

    func testNamesAreShortEnoughToShareALine() {
        XCTAssertEqual(SpotNetwork.allCases.map(\.shortName), ["Cluster", "Hub", "POTA"])
        XCTAssertEqual(SpotNetwork.allCases.map(\.displayName), ["DX cluster", "QSO Party Hub", "POTA"])
    }
}

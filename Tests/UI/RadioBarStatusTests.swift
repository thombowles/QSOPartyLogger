import XCTest
@testable import QSOPartyLogger

/// What the radio bar says in each connection phase: a button that only
/// claims "Disconnect" for a link the radio has actually answered on, and the
/// inline status line (with tooltip detail) that replaced the modal alert.
@MainActor
final class RadioBarStatusTests: XCTestCase {

    // MARK: Button label

    func testButtonOffersConnectOnlyWhenIdle() {
        XCTAssertEqual(RadioBar.connectButtonTitle(for: .disconnected), "Connect")
    }

    func testButtonOffersCancelWhileTheLinkIsUnproven() {
        // Transport up, radio silent — "Disconnect" here is the lie the
        // button used to tell.
        XCTAssertEqual(RadioBar.connectButtonTitle(for: .waitingForRadio), "Cancel")
        XCTAssertEqual(RadioBar.connectButtonTitle(for: .unresponsive), "Cancel")
    }

    func testButtonOffersDisconnectOnlyOnceTheRadioAnswered() {
        XCTAssertEqual(RadioBar.connectButtonTitle(for: .connected), "Disconnect")
    }

    // MARK: Inline status

    func testStatusIsQuietWhenDisconnectedWithNothingToTell() {
        XCTAssertEqual(RadioBar.status(phase: .disconnected, error: nil), .idle)
    }

    func testStatusCarriesTheFailureAndItsTooltipAfterAFailedConnect() {
        let error = RadioController.ConnectionError(
            summary: "Couldn't open port",
            detail: "Could not open /dev/cu.usbserial-A1: No such file or directory"
        )
        XCTAssertEqual(
            RadioBar.status(phase: .disconnected, error: error),
            .trouble(
                summary: "Couldn't open port",
                detail: "Could not open /dev/cu.usbserial-A1: No such file or directory"
            )
        )
    }

    func testStatusShowsProgressWhileWaitingForTheRadio() {
        XCTAssertEqual(RadioBar.status(phase: .waitingForRadio, error: nil), .waiting)
    }

    func testStatusWarnsWithDetailWhenTheRadioStaysSilent() {
        let error = RadioController.ConnectionError(
            summary: "Radio not answering",
            detail: "Connected to 192.168.20.40:4992, but the radio isn't answering."
        )
        XCTAssertEqual(
            RadioBar.status(phase: .unresponsive, error: error),
            .trouble(
                summary: "Radio not answering",
                detail: "Connected to 192.168.20.40:4992, but the radio isn't answering."
            )
        )
    }

    func testUnresponsiveWithoutAStoredErrorStillWarns() {
        XCTAssertEqual(
            RadioBar.status(phase: .unresponsive, error: nil),
            .trouble(summary: "Radio not answering", detail: "")
        )
    }

    func testALiveRadioShowsTheFrequencyNotAStaleWarning() {
        let stale = RadioController.ConnectionError(
            summary: "Radio not answering", detail: "old news"
        )
        XCTAssertEqual(RadioBar.status(phase: .connected, error: stale), .live)
    }
}

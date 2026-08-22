import XCTest
@testable import QSOPartyLogger

/// The connection is the app's, not any one window's. Every log window holds
/// `RadioController.shared`, so a second window opening onto a connected
/// radio must leave it alone, and one window closing while another is still
/// logging must not take the radio away from it. A serial port is one stream
/// of bytes: two controllers each polling it split every CAT response between
/// two parsers, which is what `lsof` showed on the operator's Mac on
/// 2026-08-22 — two descriptors on one `/dev/cu.usbserial-*`, both mid-read.
///
/// Over `/dev/null` as the silent serial port, like
/// `RadioControllerConnectionTests`. The port list is injected, because
/// `autoConnect` acts only on a port IOKit lists, and the guard that matters
/// most here was otherwise unprovable without an adapter on the desk.
@MainActor
final class RadioControllerSharedConnectionTests: XCTestCase {

    private func makeSilentSerialSettings() -> AppSettings {
        let settings = AppSettings(defaults: Preferences.store)
        settings.radioID = "elecraft-k3"
        settings.portPath = "/dev/null"
        return settings
    }

    /// A controller that believes `/dev/null` is a serial adapter on offer.
    private func makeController() -> RadioController {
        let radio = RadioController()
        radio.enumeratePorts = { [SerialPortInfo(path: "/dev/null")] }
        return radio
    }

    /// Polls a MainActor condition without blocking the actor. On timeout it
    /// simply returns — the caller's own assertion names what never happened.
    private func waitUntil(
        timeout: TimeInterval = 3, _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    // MARK: Auto-connect on document open

    /// The positive case — the README's "opening a contest file reconnects the
    /// last radio you used" — provable for the first time without hardware.
    func testAutoConnectConnectsWhenTheConfiguredPortIsPresent() {
        let radio = makeController()
        defer { radio.disconnect() }

        radio.autoConnect(settings: makeSilentSerialSettings())

        XCTAssertTrue(radio.isConnected)
        XCTAssertEqual(radio.connectionPhase, .waitingForRadio)
        XCTAssertEqual(radio.availablePorts.map(\.path), ["/dev/null"],
                       "auto-connect rescans before it decides")
    }

    /// A second window opening onto a live link is a no-op. `connect` tears
    /// down and rebuilds, which would wipe the validation verdict and close
    /// the port out from under the window already using it.
    func testAutoConnectLeavesAnAlreadyConnectedRadioAlone() async throws {
        let radio = makeController()
        radio.validationWindow = 0.25
        defer { radio.disconnect() }
        let settings = makeSilentSerialSettings()

        radio.connect(settings: settings)
        try await waitUntil { radio.connectionPhase == .unresponsive }
        XCTAssertEqual(radio.connectionPhase, .unresponsive,
                       "precondition: a verdict a reconnect would erase")

        radio.autoConnect(settings: settings)
        XCTAssertEqual(radio.connectionPhase, .unresponsive, "the second window did not reconnect")
        XCTAssertEqual(radio.lastError?.summary, "Radio not answering", "…and its verdict survived")

        // The control: the bar's Connect button *does* rebuild, so the
        // assertions above are ones that can fail.
        radio.connect(settings: settings)
        XCTAssertEqual(radio.connectionPhase, .waitingForRadio)
        XCTAssertNil(radio.lastError)
    }

    // MARK: Window lifetime

    func testClosingOneWindowKeepsTheConnectionForTheOthers() {
        let radio = makeController()
        defer { radio.disconnect() }
        let settings = makeSilentSerialSettings()

        // Two windows open, in the order `MainView.onAppear` does it.
        radio.windowDidOpen()
        radio.autoConnect(settings: settings)
        radio.windowDidOpen()
        radio.autoConnect(settings: settings)
        XCTAssertEqual(radio.attachedWindows, 2)
        XCTAssertTrue(radio.isConnected)

        radio.windowDidClose()
        XCTAssertEqual(radio.attachedWindows, 1)
        XCTAssertTrue(radio.isConnected, "one window closing must not take the radio from the other")

        radio.windowDidClose()
        XCTAssertEqual(radio.attachedWindows, 0)
        XCTAssertEqual(radio.connectionPhase, .disconnected, "the last window closing releases the port")
        XCTAssertNil(radio.lastError, "…as a clean slate, like the Disconnect button")
    }

    /// An unpaired close floors at zero. A count driven negative would make
    /// the next real close leave the port held with no window showing it.
    func testAStrayCloseNeverDrivesTheCountNegative() {
        let radio = makeController()
        defer { radio.disconnect() }

        radio.windowDidClose()
        XCTAssertEqual(radio.attachedWindows, 0)

        radio.windowDidOpen()
        radio.autoConnect(settings: makeSilentSerialSettings())
        XCTAssertTrue(radio.isConnected)

        radio.windowDidClose()
        XCTAssertEqual(radio.connectionPhase, .disconnected)
    }
}

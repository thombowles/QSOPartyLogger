import XCTest
@testable import QSOPartyLogger

/// Connection lifecycle as the radio bar shows it: the phase behind the
/// Connect/Cancel/Disconnect button, and the structured error that feeds the
/// inline status line and its tooltip. These used to surface as a modal
/// alert; now the state itself has to be right.
///
/// The silent-radio tests run over `/dev/null` as a serial port: it opens
/// cleanly and never says a word — exactly a cabled radio that is switched
/// off, and the same "transport up, CAT dead" shape as the screenshot's
/// silent FlexRadio. No hardware, no network.
@MainActor
final class RadioControllerConnectionTests: XCTestCase {

    private func makeSettings(radioID: String) -> AppSettings {
        let settings = AppSettings(defaults: Preferences.store)
        settings.radioID = radioID
        return settings
    }

    /// A transport that is up while the "radio" never answers.
    private func makeSilentSerialSettings() -> AppSettings {
        let settings = makeSettings(radioID: "elecraft-k3")
        settings.portPath = "/dev/null"
        return settings
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

    // MARK: Phase derivation (pure)

    func testPhaseIsDisconnectedWheneverTheTransportIsDown() {
        for answered in [false, true] {
            for expired in [false, true] {
                XCTAssertEqual(
                    RadioController.phase(
                        transportUp: false, radioAnswered: answered, validationExpired: expired
                    ),
                    .disconnected
                )
            }
        }
    }

    func testPhaseIsConnectedOnceTheRadioHasAnswered() {
        // Even when the validation clock ran out first — a late answer wins.
        for expired in [false, true] {
            XCTAssertEqual(
                RadioController.phase(
                    transportUp: true, radioAnswered: true, validationExpired: expired
                ),
                .connected
            )
        }
    }

    func testPhaseWaitsThenGoesUnresponsiveWhileTheRadioIsSilent() {
        XCTAssertEqual(
            RadioController.phase(transportUp: true, radioAnswered: false, validationExpired: false),
            .waitingForRadio
        )
        XCTAssertEqual(
            RadioController.phase(transportUp: true, radioAnswered: false, validationExpired: true),
            .unresponsive
        )
    }

    // MARK: The unresponsive-radio story (pure builder)

    func testUnresponsiveErrorNamesTheTargetAndCarriesTheNetworkHint() {
        let error = RadioController.unresponsiveError(target: "192.168.20.40:4992", isNetwork: true)
        XCTAssertEqual(error.summary, "Radio not answering")
        XCTAssertTrue(error.detail.contains("192.168.20.40:4992"), "detail names the target")
        XCTAssertTrue(
            error.detail.contains("Local Network"),
            "network radios carry the macOS permission hint"
        )
    }

    func testUnresponsiveErrorForSerialSkipsTheLocalNetworkHint() {
        let error = RadioController.unresponsiveError(target: "cu.usbserial-A1", isNetwork: false)
        XCTAssertEqual(error.summary, "Radio not answering")
        XCTAssertTrue(error.detail.contains("cu.usbserial-A1"))
        XCTAssertFalse(
            error.detail.contains("Local Network"),
            "the macOS Local Network hint is a network-radio thing"
        )
    }

    // MARK: Config errors — loud, structured, and no transport left behind

    func testUnknownRadioReportsErrorAndStaysDisconnected() {
        let radio = RadioController()
        radio.connect(settings: makeSettings(radioID: "no-such-radio"))

        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertFalse(radio.isConnected)
        XCTAssertEqual(radio.lastError?.summary, "Unknown radio")
        XCTAssertEqual(radio.lastError?.detail.contains("no-such-radio"), true)
    }

    func testSerialWithoutAPortReportsError() {
        let settings = makeSettings(radioID: "elecraft-k3")
        settings.portPath = ""
        let radio = RadioController()
        radio.connect(settings: settings)

        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertEqual(radio.lastError?.summary, "No serial port selected")
        XCTAssertEqual(radio.lastError?.detail.isEmpty, false)
    }

    func testNetworkWithoutAHostReportsError() {
        let settings = makeSettings(radioID: "flex-6000")
        settings.tcpHost = "   "
        let radio = RadioController()
        radio.connect(settings: settings)

        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertEqual(radio.lastError?.summary, "No radio address")
        XCTAssertEqual(radio.lastError?.detail.isEmpty, false)
    }

    func testSerialWithAMissingDeviceReportsError() {
        let settings = makeSettings(radioID: "elecraft-k3")
        settings.portPath = "/dev/cu.qplog-test-missing"
        let radio = RadioController()
        radio.connect(settings: settings)

        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertEqual(radio.lastError?.summary, "Couldn't open port")
        XCTAssertEqual(radio.lastError?.detail.contains("/dev/cu.qplog-test-missing"), true)
    }

    // MARK: Auto-connect (document open) stays quiet when unconfigured

    func testAutoConnectWithoutAHostDoesNothingQuietly() {
        let settings = makeSettings(radioID: "flex-6000")
        settings.tcpHost = ""
        let radio = RadioController()
        radio.autoConnect(settings: settings)

        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertNil(radio.lastError)
    }

    func testAutoConnectWithAnAbsentSerialPortDoesNothingQuietly() {
        let settings = makeSettings(radioID: "elecraft-k3")
        settings.portPath = "/dev/cu.qplog-test-missing"
        let radio = RadioController()
        radio.autoConnect(settings: settings)

        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertNil(radio.lastError)
    }

    // MARK: Transport up, radio silent — the screenshot scenario

    func testConnectWaitsThenTurnsUnresponsiveAndCancelClears() async throws {
        let radio = RadioController()
        radio.validationWindow = 0.25

        radio.connect(settings: makeSilentSerialSettings())
        XCTAssertEqual(
            radio.connectionPhase, .waitingForRadio,
            "transport is up but nothing has been heard yet"
        )
        XCTAssertNil(radio.lastError)

        try await waitUntil { radio.connectionPhase == .unresponsive }
        XCTAssertEqual(radio.connectionPhase, .unresponsive)
        XCTAssertTrue(radio.isConnected, "the link stays up — the radio may still wake")
        let error = try XCTUnwrap(radio.lastError)
        XCTAssertEqual(error.summary, "Radio not answering")
        XCTAssertTrue(error.detail.contains("null"), "detail names the target port")

        radio.disconnect()  // the Cancel button
        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertNil(radio.lastError, "a deliberate disconnect is a clean slate")
    }

    func testNetworkConnectIsWaitingImmediatelyAndCancelClears() {
        // `TCPTransport.open` succeeds locally before any packet moves, so
        // the manual-connect experience is the same whether or not anything
        // answers: the bar waits, and Cancel is always available. 127.0.0.1
        // never leaves the machine; the test never waits for the socket.
        let settings = makeSettings(radioID: "flex-6000")
        settings.tcpHost = "127.0.0.1"
        settings.tcpPort = 1
        let radio = RadioController()

        radio.connect(settings: settings)
        XCTAssertEqual(radio.connectionPhase, .waitingForRadio)
        XCTAssertTrue(radio.isConnected)
        XCTAssertNil(radio.lastError)

        radio.disconnect()
        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertNil(radio.lastError)
    }

    func testTransportLossKeepsItsErrorThroughTheDisconnect() {
        let radio = RadioController()
        radio.connect(settings: makeSilentSerialSettings())
        XCTAssertEqual(radio.connectionPhase, .waitingForRadio)

        radio.transportDidDisconnect(reason: "Connection reset by peer")

        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertFalse(radio.isConnected)
        let error = radio.lastError
        XCTAssertEqual(error?.summary, "Connection lost", "an involuntary drop must explain itself")
        XCTAssertEqual(error?.detail.contains("Connection reset by peer"), true)
    }

    func testLateTransportLossAfterManualDisconnectIsIgnored() {
        let radio = RadioController()
        radio.connect(settings: makeSilentSerialSettings())
        radio.disconnect()

        radio.transportDidDisconnect(reason: "Socket closed")

        XCTAssertNil(radio.lastError, "a drop we caused ourselves is not news")
        XCTAssertEqual(radio.connectionPhase, .disconnected)
    }

    func testLateStateArrivalAfterDisconnectIsIgnored() {
        // A driver update already in flight when the user disconnects must
        // not resurrect the frequency display — or wipe a Connection lost
        // error that arrived with the teardown.
        let radio = RadioController()
        radio.connect(settings: makeSilentSerialSettings())
        radio.transportDidDisconnect(reason: "Connection reset by peer")

        radio.driverDidReportState(
            RadioState(frequencyHz: 14_042_000, rawMode: "CW", isTransmitting: false)
        )

        XCTAssertNil(radio.radioState, "no live state on a dead link")
        XCTAssertEqual(radio.connectionPhase, .disconnected)
        XCTAssertEqual(radio.lastError?.summary, "Connection lost")
    }

    func testStateArrivalClearsAStaleSilenceError() async throws {
        let radio = RadioController()
        radio.validationWindow = 0.25

        radio.connect(settings: makeSilentSerialSettings())
        try await waitUntil { radio.connectionPhase == .unresponsive }
        XCTAssertNotNil(radio.lastError)

        // The radio finally speaks — the promised "light up" must also
        // retire the warning.
        radio.driverDidReportState(
            RadioState(frequencyHz: 14_042_000, rawMode: "CW", isTransmitting: false)
        )

        XCTAssertEqual(radio.connectionPhase, .connected)
        XCTAssertNil(radio.lastError)
        XCTAssertEqual(radio.radioState?.frequencyHz, 14_042_000)
        radio.disconnect()
    }
}

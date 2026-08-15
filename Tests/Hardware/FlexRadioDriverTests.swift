import XCTest
@testable import QSOPartyLogger

/// FlexRadio 6000-series SmartSDR TCP API: status parsing, command builders,
/// and the driver loop over a mock transport.
final class FlexRadioDriverTests: XCTestCase {

    // MARK: Status parsing (pure)

    func testParseSliceStatus() {
        let s = FlexRadioDriver.parseSlice("slice 0 in_use=1 RF_frequency=14.042000 mode=CW active=1")
        XCTAssertEqual(s?.index, 0)
        XCTAssertEqual(s?.frequencyHz, 14_042_000)
        XCTAssertEqual(s?.rawMode, "CW")
        XCTAssertEqual(s?.active, true)
    }

    func testParseSlicePartialUpdate() {
        // Flex sends deltas; absent keys must stay nil so the driver merges.
        let s = FlexRadioDriver.parseSlice("slice 0 RF_frequency=7.040000")
        XCTAssertEqual(s?.index, 0)
        XCTAssertEqual(s?.frequencyHz, 7_040_000)
        XCTAssertNil(s?.rawMode)
        XCTAssertNil(s?.active)
    }

    func testParseSliceRejectsOtherStatus() {
        XCTAssertNil(FlexRadioDriver.parseSlice("interlock state=READY"))
        XCTAssertNil(FlexRadioDriver.parseSlice(""))
    }

    func testParseInterlockState() {
        XCTAssertEqual(
            FlexRadioDriver.parseInterlockTransmitting("interlock state=TRANSMITTING reason= source="),
            true
        )
        XCTAssertEqual(FlexRadioDriver.parseInterlockTransmitting("interlock state=RECEIVE"), false)
        XCTAssertEqual(FlexRadioDriver.parseInterlockTransmitting("interlock state=READY tx_allowed=1"), false)
        XCTAssertNil(FlexRadioDriver.parseInterlockTransmitting("slice 0 mode=CW"))
    }

    func testParseCWXSpeed() {
        XCTAssertEqual(FlexRadioDriver.parseCWXSpeed("cwx delay=0 wpm=28 qsk_enabled=1"), 28)
        XCTAssertNil(FlexRadioDriver.parseCWXSpeed("cwx erase=1"))
        XCTAssertNil(FlexRadioDriver.parseCWXSpeed("slice 0 wpm=28"))
    }

    // MARK: Mode mapping

    func testFlexToAppModeMapping() {
        XCTAssertEqual(FlexRadioDriver.appRawMode(flexMode: "CW"), "CW")
        XCTAssertEqual(FlexRadioDriver.appRawMode(flexMode: "USB"), "USB")
        XCTAssertEqual(FlexRadioDriver.appRawMode(flexMode: "LSB"), "LSB")
        XCTAssertEqual(FlexRadioDriver.appRawMode(flexMode: "DIGU"), "RTTY")
        XCTAssertEqual(FlexRadioDriver.appRawMode(flexMode: "DIGL"), "RTTY")
        XCTAssertEqual(FlexRadioDriver.appRawMode(flexMode: "AM"), "AM")
    }

    func testAppToFlexModeMapping() {
        // SSB resolves by frequency: USB at/above 10 MHz, LSB below.
        XCTAssertEqual(FlexRadioDriver.flexMode(forAppMode: "SSB", frequencyHz: 14_200_000), "USB")
        XCTAssertEqual(FlexRadioDriver.flexMode(forAppMode: "SSB", frequencyHz: 7_200_000), "LSB")
        XCTAssertEqual(FlexRadioDriver.flexMode(forAppMode: "CW", frequencyHz: 14_040_000), "CW")
        XCTAssertEqual(FlexRadioDriver.flexMode(forAppMode: "RTTY", frequencyHz: 14_080_000), "DIGU")
        XCTAssertEqual(FlexRadioDriver.flexMode(forAppMode: "USB", frequencyHz: 7_200_000), "USB")
        XCTAssertNil(FlexRadioDriver.flexMode(forAppMode: "???", frequencyHz: 14_000_000))
    }

    // MARK: Command builders

    func testCommandBuilders() {
        XCTAssertEqual(FlexRadioDriver.cmdTune(sliceIndex: 0, hz: 14_042_000), "slice tune 0 14.042000")
        XCTAssertEqual(FlexRadioDriver.cmdTune(sliceIndex: 1, hz: 7_040_500), "slice tune 1 7.040500")
        XCTAssertEqual(FlexRadioDriver.cmdSetMode(sliceIndex: 0, flexMode: "CW"), "slice set 0 mode=CW")
        // `cw wpm`, not `cwx wpm` — the API's own example is "C19|cw wpm 25",
        // printed identically on the cw and cwx pages. The x is the trap: it
        // is on every other CWX verb and not on this one.
        XCTAssertEqual(FlexRadioDriver.cmdKeyerSpeed(wpm: 28), "cw wpm 28")
        XCTAssertEqual(FlexRadioDriver.cmdKeyerSpeed(wpm: 99), "cw wpm 50", "clamped")
        XCTAssertEqual(FlexRadioDriver.cmdKeyerSpeed(wpm: 1), "cw wpm 8", "clamped")
        XCTAssertFalse(
            FlexRadioDriver.cmdKeyerSpeed(wpm: 28).hasPrefix("cwx"),
            "cwx wpm is not a command any Flex answers"
        )
        XCTAssertEqual(FlexRadioDriver.cmdSendCW("TU 73"), "cwx send \"TU 73\"")
        XCTAssertEqual(
            FlexRadioDriver.cmdSendCW("SAY \"HI\""), "cwx send \"SAY HI\"",
            "embedded quotes are stripped, not escaped"
        )
    }

    // MARK: Driver over a mock transport

    func testDriverSubscribesOnStart() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        driver.start(transport: mock)
        XCTAssertTrue(mock.allWritten.contains("sub slice all"))
        XCTAssertTrue(mock.allWritten.contains("sub tx all"))
        XCTAssertTrue(mock.allWritten.contains("sub cwx all"))
        driver.stop()
    }

    func testDriverPublishesStateFromStatusMessages() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        let got = expectation(description: "state delivered")
        nonisolated(unsafe) var received: RadioState?
        driver.onStateChange = { state in
            received = state
            if state.rawMode == "CW" { got.fulfill() }
        }
        driver.start(transport: mock)
        mock.inject("V1.4.0.0\n")
        mock.inject("H2C87D3E2\n")
        mock.inject("S2C87D3E2|slice 0 in_use=1 RF_frequency=14.042000 mode=CW active=1\n")
        wait(for: [got], timeout: 2)
        XCTAssertEqual(received?.frequencyKHz, 14042)
        XCTAssertEqual(received?.rawMode, "CW")
        XCTAssertEqual(received?.isTransmitting, false)
        driver.stop()
    }

    func testDriverHandlesFragmentedLines() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        let got = expectation(description: "state from fragments")
        driver.onStateChange = { _ in got.fulfill() }
        driver.start(transport: mock)
        mock.inject("S2C87D3E2|slice 0 in_use=1 RF_freq")
        mock.inject("uency=7.040000 mode=CW active=1\n")
        wait(for: [got], timeout: 2)
        driver.stop()
    }

    func testDriverTracksTransmitViaInterlock() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        nonisolated(unsafe) var states: [RadioState] = []
        let tx = expectation(description: "tx seen")
        driver.onStateChange = { state in
            states.append(state)
            if state.isTransmitting { tx.fulfill() }
        }
        driver.start(transport: mock)
        mock.inject("S1|slice 0 in_use=1 RF_frequency=14.042000 mode=CW active=1\n")
        mock.inject("S1|interlock state=TRANSMITTING reason=\n")
        wait(for: [tx], timeout: 2)
        XCTAssertEqual(states.last?.isTransmitting, true)
        XCTAssertEqual(states.last?.frequencyKHz, 14042, "TX flag merges into existing slice state")
        driver.stop()
    }

    /// A Flex has no key lines, so its own keyer is the only path (Article 11)
    /// — which makes `cw wpm` the *whole* mechanism for changing speed here.
    /// Asserted on the wire, since the builder being right does not prove the
    /// driver calls it.
    func testDriverEmitsTheKeyerSpeedCommandOnTheWire() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        driver.start(transport: mock)
        driver.setKeyerSpeed(wpm: 28)
        XCTAssertTrue(mock.allWritten.contains("cw wpm 28"), "wrote: \(mock.allWritten)")
        XCTAssertFalse(mock.allWritten.contains("cwx wpm"))
        driver.stop()
    }

    /// Speed has to reach a message already sending, so the setter forwards
    /// straight to the radio rather than waiting for the next `send`.
    func testInternalKeyerForwardsSpeedImmediately() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        driver.start(transport: mock)

        let keyer = RadioInternalKeyer(driver: driver, wpm: 24)
        keyer.send("CQ TEST DE KE5CW K")
        let beforeSpeedChange = mock.allWritten
        keyer.wpm = 30

        XCTAssertTrue(mock.allWritten.contains("cw wpm 30"))
        XCTAssertFalse(
            beforeSpeedChange.contains("cw wpm 30"),
            "the speed went out on the change, not queued behind the message"
        )
        keyer.abort()
        XCTAssertTrue(mock.allWritten.contains("cwx clear"))
        driver.stop()
    }

    func testDriverReportsKeyerSpeedChanges() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        nonisolated(unsafe) var wpms: [Int] = []
        let got = expectation(description: "wpm")
        driver.onKeyerSpeedChange = { wpm in
            wpms.append(wpm)
            got.fulfill()
        }
        driver.start(transport: mock)
        mock.inject("S1|cwx delay=0 wpm=25 qsk_enabled=1\n")
        wait(for: [got], timeout: 2)
        XCTAssertEqual(wpms, [25])
        driver.stop()
    }

    func testSetFrequencyPublishesOptimistically() {
        // SmartSDR does not echo status back to the client that commanded the
        // change — the driver must update its own state when it sends a tune.
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        nonisolated(unsafe) var received: [RadioState] = []
        let tuned = expectation(description: "optimistic state")
        driver.onStateChange = { state in
            received.append(state)
            if state.frequencyKHz == 14050 { tuned.fulfill() }
        }
        driver.start(transport: mock)
        mock.inject("S1|slice 0 in_use=1 RF_frequency=14.042000 mode=CW active=1\n")
        driver.setFrequency(hz: 14_050_000)   // no status echo injected
        wait(for: [tuned], timeout: 2)
        XCTAssertTrue(mock.allWritten.contains("slice tune 0 14.050000"))
        XCTAssertEqual(received.last?.frequencyKHz, 14050)
        XCTAssertEqual(received.last?.rawMode, "CW", "mode carried over")
        driver.stop()
    }

    func testSetModePublishesOptimistically() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        nonisolated(unsafe) var received: RadioState?
        let switched = expectation(description: "optimistic mode")
        driver.onStateChange = { state in
            received = state
            if state.rawMode == "USB" { switched.fulfill() }
        }
        driver.start(transport: mock)
        mock.inject("S1|slice 0 in_use=1 RF_frequency=14.242000 mode=CW active=1\n")
        driver.setMode(rawMode: "SSB")   // 14.2 MHz → USB; no echo injected
        wait(for: [switched], timeout: 2)
        XCTAssertTrue(mock.allWritten.contains("slice set 0 mode=USB"))
        XCTAssertEqual(received?.rawMode, "USB")
        XCTAssertEqual(received?.frequencyKHz, 14242, "frequency carried over")
        driver.stop()
    }

    func testDriverIgnoresInactiveSliceForState() {
        let mock = MockSerialTransport()
        let driver = FlexRadioDriver()
        nonisolated(unsafe) var received: RadioState?
        let got = expectation(description: "active slice state")
        driver.onStateChange = { state in
            received = state
            if state.frequencyKHz == 14042 { got.fulfill() }
        }
        driver.start(transport: mock)
        // Slice 1 is inactive — its updates must not become the app state.
        mock.inject("S1|slice 1 in_use=1 RF_frequency=21.030000 mode=USB active=0\n")
        mock.inject("S1|slice 0 in_use=1 RF_frequency=14.042000 mode=CW active=1\n")
        wait(for: [got], timeout: 2)
        XCTAssertEqual(received?.frequencyKHz, 14042)
        driver.stop()
    }

    // MARK: Transmit audio over DAX (docs/research/voice_transports.md)

    /// A TCP-shaped mock: records every `C<seq>|<body>` write, answers on
    /// request, and names a host so the driver can open its UDP channel.
    final class MockNetworkTransport: NetworkTransport, @unchecked Sendable {
        var isOpen = true
        var onReceive: (@Sendable (Data) -> Void)?
        let hostName = "10.0.0.5"
        private let lock = NSLock()
        private var lines: [String] = []

        func open(baudRate: Int) throws {}
        func close() { isOpen = false }
        func set(line: SerialLine, active: Bool) {}
        func write(_ data: Data) {
            lock.withLock { lines.append(String(data: data, encoding: .utf8) ?? "") }
        }

        /// The command bodies, in order — "C12|xmit 1\n" → "xmit 1".
        var commands: [String] {
            lock.withLock {
                lines.compactMap { line in
                    guard line.hasPrefix("C"), let bar = line.firstIndex(of: "|") else { return nil }
                    return String(line[line.index(after: bar)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        /// The sequence number of the first write whose body is `command`.
        func seq(of command: String) -> Int? {
            lock.withLock {
                for line in lines {
                    guard line.hasPrefix("C"), let bar = line.firstIndex(of: "|") else { continue }
                    let body = String(line[line.index(after: bar)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if body == command { return Int(line[line.index(after: line.startIndex)..<bar]) }
                }
                return nil
            }
        }

        func clearWritten() { lock.withLock { lines.removeAll() } }
        func feed(_ line: String) { onReceive?(Data(line.utf8)) }
        /// The radio's reply to `command`: `R<seq>|<code>|<message>`.
        func reply(to command: String, code: String, message: String) {
            guard let seq = seq(of: command) else { return XCTFail("\(command) was never sent") }
            feed("R\(seq)|\(code)|\(message)\n")
        }
    }

    final class FakeUDP: UDPSending, @unchecked Sendable {
        let localPort: UInt16 = 51234
        private let lock = NSLock()
        private var stored: [Data] = []
        private(set) var closed = 0
        var sent: [Data] { lock.withLock { stored } }
        func send(_ data: Data) { lock.withLock { stored.append(data) } }
        func close() { lock.withLock { closed += 1 } }
    }

    final class Events: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [TransmitAudioEvent] = []
        var all: [TransmitAudioEvent] { lock.withLock { stored } }
        func append(_ e: TransmitAudioEvent) { lock.withLock { stored.append(e) } }
    }

    /// A driver started against the mock, with the prologue, an active TX
    /// slice on DAX channel 0 and DAX off — the state a Flex on SSB is in.
    private func connectedDriver(makeUDP: FakeUDP = FakeUDP()) -> (FlexRadioDriver, MockNetworkTransport, FakeUDP) {
        let transport = MockNetworkTransport()
        let driver = FlexRadioDriver()
        driver.makeUDPSender = { host, port in
            XCTAssertEqual(host, "10.0.0.5")
            XCTAssertEqual(port, 4991)
            return makeUDP
        }
        driver.start(transport: transport)
        transport.feed("V1.4.0.0\n")
        transport.feed("H1A2B3C4\n")
        transport.feed("S0|slice 0 in_use=1 RF_frequency=14.250000 mode=USB active=1 tx=1 dax=0\n")
        transport.feed("S0|transmit dax=0 rfpower=50\n")
        transport.clearWritten()
        return (driver, transport, makeUDP)
    }

    /// 256 frames at 24 kHz — two packets of clip between the lead and tail.
    private let clip = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0.1, count: 256))

    /// Feed the reply to the create and the `tx=1` status for our stream.
    private func confirmStream(_ transport: MockNetworkTransport, id: String = "0x84000001") {
        transport.reply(to: FlexRadioDriver.cmdStreamCreateDAXTX, code: "0", message: id)
        transport.feed("S1A2B3C4|stream \(id) type=dax_tx client_handle=0x1A2B3C4 tx=1\n")
    }

    /// Wait until the streamer has finished (or failed) — bounded.
    private func waitForTerminal(_ events: Events, timeout: TimeInterval = 5) {
        let e = expectation(description: "terminal event")
        DispatchQueue.global().async {
            let deadline = Date().addingTimeInterval(timeout)
            while Date() < deadline {
                if events.all.contains(where: { $0 == .finished || $0 == .stopped || { if case .failed = $0 { return true }; return false }($0) }) {
                    e.fulfill(); return
                }
                usleep(10_000)
            }
        }
        wait(for: [e], timeout: timeout + 1)
    }

    func testStartSubscribesToDAX() {
        let transport = MockNetworkTransport()
        let driver = FlexRadioDriver()
        driver.start(transport: transport)
        XCTAssertTrue(transport.commands.contains("sub dax all"))
        driver.stop()
    }

    func testNoSocketUntilTheFirstPlay() {
        let transport = MockNetworkTransport()
        let driver = FlexRadioDriver()
        nonisolated(unsafe) var made = 0
        driver.makeUDPSender = { _, _ in made += 1; return FakeUDP() }
        driver.start(transport: transport)
        transport.feed("H1A2B3C4\n")
        XCTAssertEqual(made, 0)
        XCTAssertFalse(transport.commands.contains { $0.hasPrefix("client udpport") })
        XCTAssertFalse(transport.commands.contains { $0.hasPrefix("stream create") })
        driver.stop()
    }

    func testFirstPlaySetsUpTheStreamThenKeysStreamsAndUnkeys() {
        let (driver, transport, udp) = connectedDriver()
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        XCTAssertEqual(transport.commands,
                       ["client udpport 51234", "dax audio set 1 slice=0 tx=1", "stream create type=dax_tx"])
        XCTAssertTrue(events.all.isEmpty, "nothing keyed before the radio confirms")

        confirmStream(transport)
        waitForTerminal(events)
        XCTAssertEqual(Array(transport.commands.suffix(4)),
                       ["transmit set dax=1", "xmit 1", "xmit 0", "transmit set dax=0"])
        XCTAssertEqual(events.all, [.started, .finished])
        // 120 ms lead ≈ 23 packets, 2 clip packets, 100 ms tail ≈ 19 packets.
        XCTAssertGreaterThan(udp.sent.count, 40)
        XCTAssertLessThan(udp.sent.count, 50)
        XCTAssertTrue(udp.sent.allSatisfy { $0.count == 1052 })
        driver.stop()
    }

    func testSecondPlaySkipsTheSetup() {
        let (driver, transport, _) = connectedDriver()
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        confirmStream(transport)
        waitForTerminal(events)

        transport.clearWritten()
        let second = Events()
        driver.onTransmitAudioEvent = { second.append($0) }
        driver.transmitAudio(clip)
        waitForTerminal(second)
        XCTAssertEqual(transport.commands, ["transmit set dax=1", "xmit 1", "xmit 0", "transmit set dax=0"])
        XCTAssertEqual(second.all, [.started, .finished])
        driver.stop()
    }

    func testDAXAlreadyOnIsLeftOn() {
        let (driver, transport, _) = connectedDriver()
        transport.feed("S0|transmit dax=1\n")
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        confirmStream(transport)
        waitForTerminal(events)
        XCTAssertFalse(transport.commands.contains("transmit set dax=1"))
        XCTAssertFalse(transport.commands.contains("transmit set dax=0"))
        XCTAssertEqual(Array(transport.commands.suffix(2)), ["xmit 1", "xmit 0"])
        driver.stop()
    }

    func testTXSliceWithADAXChannelUsesItWithoutReassigning() {
        let (driver, transport, _) = connectedDriver()
        transport.feed("S0|slice 0 dax=3\n")
        driver.transmitAudio(clip)
        XCTAssertTrue(transport.commands.contains("dax audio set 3 tx=1"))
        XCTAssertFalse(transport.commands.contains { $0.contains("slice=") })
        driver.stop()
    }

    func testRefusedStreamNeverKeysAndReportsTheCode() {
        let (driver, transport, _) = connectedDriver()
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        transport.reply(to: FlexRadioDriver.cmdStreamCreateDAXTX, code: "50000064", message: "")
        XCTAssertEqual(events.all, [.failed("The radio refused the transmit audio stream (0x50000064 — no UDP port registered).")])
        XCTAssertFalse(transport.commands.contains("xmit 1"))
        driver.stop()
    }

    func testNoTXConfirmationWithinTheWindowFailsWithoutKeying() {
        let (driver, transport, _) = connectedDriver()
        driver.streamConfirmTimeout = 0.2
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        transport.reply(to: FlexRadioDriver.cmdStreamCreateDAXTX, code: "0", message: "0x84000001")
        // No `tx=1` status ever arrives.
        waitForTerminal(events, timeout: 2)
        guard case .failed(let reason)? = events.all.first else { return XCTFail("expected .failed, got \(events.all)") }
        XCTAssertTrue(reason.contains("did not confirm"), reason)
        XCTAssertFalse(transport.commands.contains("xmit 1"))
        driver.stop()
    }

    func testStopMidClipUnkeysAndReportsStopped() {
        let (driver, transport, _) = connectedDriver()
        let longClip = VoiceAudio(sampleRate: 24_000, samples: [Float](repeating: 0.1, count: 24_000 * 3))
        let events = Events()
        let started = expectation(description: "started")
        driver.onTransmitAudioEvent = { events.append($0); if $0 == .started { started.fulfill() } }
        driver.transmitAudio(longClip)
        confirmStream(transport)
        wait(for: [started], timeout: 3)
        driver.stopTransmitAudio()
        XCTAssertEqual(Array(transport.commands.suffix(2)), ["xmit 0", "transmit set dax=0"])
        XCTAssertEqual(events.all, [.started, .stopped])
        usleep(50_000)
        XCTAssertEqual(events.all, [.started, .stopped], "no .finished after a stop")
        driver.stop()
    }

    func testStopDuringSetupReportsStoppedAndNeverKeys() {
        let (driver, transport, _) = connectedDriver()
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        driver.stopTransmitAudio()
        XCTAssertEqual(events.all, [.stopped])
        confirmStream(transport)                       // arrives late
        usleep(50_000)
        XCTAssertFalse(transport.commands.contains("xmit 1"), "a play stopped during setup never keys")
        driver.stop()
    }

    func testStopRemovesTheStreamAndClosesTheSocket() {
        let (driver, transport, udp) = connectedDriver()
        driver.transmitAudio(clip)
        transport.reply(to: FlexRadioDriver.cmdStreamCreateDAXTX, code: "0", message: "0x84000001")
        driver.stop()
        XCTAssertTrue(transport.commands.contains("stream remove 0x84000001"))
        XCTAssertEqual(udp.closed, 1)
    }

    func testStreamRemovedByTheRadioIsRecreatedOnTheNextPlay() {
        let (driver, transport, _) = connectedDriver()
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.transmitAudio(clip)
        confirmStream(transport)
        waitForTerminal(events)
        transport.feed("S1A2B3C4|stream 0x84000001 removed\n")
        transport.clearWritten()
        driver.transmitAudio(clip)
        XCTAssertEqual(transport.commands, ["stream create type=dax_tx"], "no second udpport or claim, one new create")
        driver.stop()
    }

    func testAnotherClientsStreamIsNotOurs() {
        let (driver, transport, _) = connectedDriver()
        let events = Events()
        driver.onTransmitAudioEvent = { events.append($0) }
        driver.streamConfirmTimeout = 0.3
        driver.transmitAudio(clip)
        transport.feed("S1A2B3C5|stream 0x84000009 type=dax_tx client_handle=0x1A2B3C5 tx=1\n")
        usleep(50_000)
        XCTAssertFalse(transport.commands.contains("xmit 1"), "someone else's stream must not key us")
        waitForTerminal(events, timeout: 2)
        driver.stop()
    }

    func testPureParsersForTheTransmitAudioPath() {
        XCTAssertEqual(FlexRadioDriver.parseHandle("H1A2B3C4"), 0x1A2B3C4)
        XCTAssertNil(FlexRadioDriver.parseHandle("V1.4.0.0"))
        XCTAssertNil(FlexRadioDriver.parseHandle("H"))
        let r = FlexRadioDriver.parseReply("R12|50000064|")
        XCTAssertEqual(r?.seq, 12)
        XCTAssertEqual(r?.code, 0x50000064)
        XCTAssertEqual(r?.message, "")
        XCTAssertEqual(FlexRadioDriver.parseReply("R3|0|0x84000001|OK")?.message, "0x84000001")
        XCTAssertNil(FlexRadioDriver.parseReply("S0|slice 0"))
        let s = FlexRadioDriver.parseStreamStatus("stream 0x84000001 type=dax_tx client_handle=0x1A2B3C4 tx=1")
        XCTAssertEqual(s?.id, 0x84000001)
        XCTAssertEqual(s?.type, "dax_tx")
        XCTAssertEqual(s?.clientHandle, 0x1A2B3C4)
        XCTAssertEqual(s?.tx, true)
        XCTAssertEqual(s?.removed, false)
        XCTAssertEqual(FlexRadioDriver.parseStreamStatus("stream 0x84000001 removed")?.removed, true)
        XCTAssertNil(FlexRadioDriver.parseStreamStatus("slice 0 dax=1"))
        XCTAssertEqual(FlexRadioDriver.parseTransmitDAX("transmit dax=1 rfpower=50"), true)
        XCTAssertEqual(FlexRadioDriver.parseTransmitDAX("transmit dax=0"), false)
        XCTAssertNil(FlexRadioDriver.parseTransmitDAX("transmit rfpower=50"))
        XCTAssertNil(FlexRadioDriver.parseTransmitDAX("slice 0 dax=1"))
        let u = FlexRadioDriver.parseSlice("slice 0 tx=1 dax=2")
        XCTAssertEqual(u?.tx, true)
        XCTAssertEqual(u?.daxChannel, 2)
        XCTAssertNil(FlexRadioDriver.parseSlice("slice 0 mode=USB")?.tx)
        XCTAssertEqual(FlexRadioDriver.replyMeaning(0x50000064), "no UDP port registered")
        XCTAssertNil(FlexRadioDriver.replyMeaning(0x12345678))
        XCTAssertEqual(FlexRadioDriver.streamRefusedText(code: 0x12345678),
                       "The radio refused the transmit audio stream (0x12345678).")
    }

    func testTransmitAudioCommandBuilders() {
        XCTAssertEqual(FlexRadioDriver.cmdClientUDPPort(4993), "client udpport 4993")
        XCTAssertEqual(FlexRadioDriver.cmdDAXAudioSetTX(channel: 2, slice: nil), "dax audio set 2 tx=1")
        XCTAssertEqual(FlexRadioDriver.cmdDAXAudioSetTX(channel: 1, slice: 0), "dax audio set 1 slice=0 tx=1")
        XCTAssertEqual(FlexRadioDriver.cmdStreamRemove(0x84000001), "stream remove 0x84000001")
        XCTAssertEqual(FlexRadioDriver.cmdTransmitDAX(true), "transmit set dax=1")
        XCTAssertEqual(FlexRadioDriver.cmdXmit(false), "xmit 0")
        XCTAssertEqual(FlexRadioDriver().transmitSampleRate, 24_000)
        XCTAssertNotNil(FlexRadioDriver() as? any AudioStreamTransmitCapable)
        XCTAssertNil(FlexRadioDriver() as? any TransmitControlCapable, "exactly one path")
    }
}

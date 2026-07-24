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
        XCTAssertEqual(FlexRadioDriver.cmdKeyerSpeed(wpm: 28), "cwx wpm 28")
        XCTAssertEqual(FlexRadioDriver.cmdKeyerSpeed(wpm: 99), "cwx wpm 50", "clamped")
        XCTAssertEqual(FlexRadioDriver.cmdKeyerSpeed(wpm: 1), "cwx wpm 8", "clamped")
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
}

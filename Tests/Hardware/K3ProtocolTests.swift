import XCTest
@testable import QSOPartyLogger

/// In-memory transport for driver tests — records writes, replays canned data.
final class MockSerialTransport: SerialTransport, @unchecked Sendable {
    var isOpen = true
    var onReceive: (@Sendable (Data) -> Void)?
    private(set) var written: [String] = []
    private(set) var lineStates: [(SerialLine, Bool)] = []
    private let lock = NSLock()

    func open(baudRate: Int) throws {}
    func close() { isOpen = false }

    func write(_ data: Data) {
        lock.withLock { written.append(String(data: data, encoding: .utf8) ?? "") }
    }

    func set(line: SerialLine, active: Bool) {
        lock.withLock { lineStates.append((line, active)) }
    }

    func inject(_ text: String) {
        onReceive?(Data(text.utf8))
    }

    var allWritten: String {
        lock.withLock { written.joined() }
    }
}

final class K3ProtocolTests: XCTestCase {

    /// Build a spec-exact IF response: `IF[f]*****+yyyyrx*00tmvspbd1*;`
    func ifResponse(freqHz: Int, tx: Bool = false, modeDigit: Character = "3") -> String {
        String(format: "IF%011d", freqHz)   // [0-12]
            + "     "                        // [13-17] 5 blanks
            + "+0000"                        // [18-22] RIT sign+offset
            + "0"                            // [23] RIT off
            + "0"                            // [24] XIT off
            + " 00"                          // [25-27]
            + (tx ? "1" : "0")               // [28] TX flag
            + String(modeDigit)              // [29] mode
            + "0"                            // [30] VFO A
            + "0"                            // [31] scan
            + "0"                            // [32] split
            + "0"                            // [33] b
            + "0"                            // [34] data sub-mode
            + "1"                            // [35]
            + " ;"                           // [36-37]
    }

    func testIFResponseLength() {
        XCTAssertEqual(ifResponse(freqHz: 14_042_000).count, 38, "spec-exact IF is 38 chars")
    }

    func testParseIF() throws {
        let state = try XCTUnwrap(ElecraftK3Driver.parseIF(ifResponse(freqHz: 14_042_000)))
        XCTAssertEqual(state.frequencyHz, 14_042_000)
        XCTAssertEqual(state.frequencyKHz, 14042)
        XCTAssertEqual(state.rawMode, "CW")
        XCTAssertEqual(state.band, .m20)
        XCTAssertFalse(state.isTransmitting)
    }

    func testParseIFTransmitAndModes() throws {
        let tx = try XCTUnwrap(ElecraftK3Driver.parseIF(ifResponse(freqHz: 7_040_000, tx: true)))
        XCTAssertTrue(tx.isTransmitting)
        XCTAssertEqual(tx.band, .m40)

        let usb = try XCTUnwrap(ElecraftK3Driver.parseIF(ifResponse(freqHz: 14_240_000, modeDigit: "2")))
        XCTAssertEqual(usb.rawMode, "USB")
        XCTAssertEqual(usb.modeClass, .phone)

        let data = try XCTUnwrap(ElecraftK3Driver.parseIF(ifResponse(freqHz: 14_080_000, modeDigit: "6")))
        XCTAssertEqual(data.modeClass, .digital)

        let cwr = try XCTUnwrap(ElecraftK3Driver.parseIF(ifResponse(freqHz: 14_042_000, modeDigit: "7")))
        XCTAssertEqual(cwr.rawMode, "CW")
    }

    func testParseIFRejectsGarbage() {
        XCTAssertNil(ElecraftK3Driver.parseIF("FA00014042000;"))
        XCTAssertNil(ElecraftK3Driver.parseIF("IF123"))
        XCTAssertNil(ElecraftK3Driver.parseIF(""))
        XCTAssertNil(ElecraftK3Driver.parseIF("?;"))
    }

    func testParseSimpleResponses() {
        XCTAssertEqual(ElecraftK3Driver.parseFA("FA00014042000;"), 14_042_000)
        XCTAssertEqual(ElecraftK3Driver.parseMD("MD3;"), .cw)
        XCTAssertEqual(ElecraftK3Driver.parseMD("MD9;"), .dataReverse)
        XCTAssertEqual(ElecraftK3Driver.parseKS("KS028;"), 28)
        XCTAssertNil(ElecraftK3Driver.parseFA("FA;"))
    }

    func testCommandBuilders() {
        XCTAssertEqual(ElecraftK3Driver.cmdSetFrequency(hz: 14_042_000), "FA00014042000;")
        XCTAssertEqual(ElecraftK3Driver.cmdSetKeyerSpeed(wpm: 28), "KS028;")
        XCTAssertEqual(ElecraftK3Driver.cmdSetKeyerSpeed(wpm: 99), "KS050;", "clamped to 50")
        XCTAssertEqual(ElecraftK3Driver.cmdSetKeyerSpeed(wpm: 1), "KS008;", "clamped to 8")
    }

    func testCmdSetMode() {
        XCTAssertEqual(ElecraftK3Driver.cmdSetMode(rawMode: "CW", frequencyHz: 14_040_000), "MD3;")
        XCTAssertEqual(
            ElecraftK3Driver.cmdSetMode(rawMode: "SSB", frequencyHz: 14_200_000), "MD2;",
            "SSB above 10 MHz is USB"
        )
        XCTAssertEqual(
            ElecraftK3Driver.cmdSetMode(rawMode: "SSB", frequencyHz: 7_200_000), "MD1;",
            "SSB below 10 MHz is LSB"
        )
        XCTAssertEqual(ElecraftK3Driver.cmdSetMode(rawMode: "USB", frequencyHz: 7_200_000), "MD2;")
        XCTAssertEqual(ElecraftK3Driver.cmdSetMode(rawMode: "LSB", frequencyHz: 14_200_000), "MD1;")
        XCTAssertEqual(ElecraftK3Driver.cmdSetMode(rawMode: "RTTY", frequencyHz: 14_080_000), "MD6;")
        XCTAssertEqual(ElecraftK3Driver.cmdSetMode(rawMode: "AM", frequencyHz: 14_200_000), "MD5;")
        XCTAssertEqual(ElecraftK3Driver.cmdSetMode(rawMode: "FM", frequencyHz: 29_600_000), "MD4;")
        XCTAssertNil(ElecraftK3Driver.cmdSetMode(rawMode: "???", frequencyHz: 14_000_000))
    }

    /// A K3 has key lines, so it is keyed directly and only directly
    /// (Article 11) and this driver has no internal-keyer path. Asserted on
    /// the wire: nothing it does in a full session may put a `KY` on the port.
    ///
    /// This matters more on a K3 than elsewhere. Programmer's Reference rev G5
    /// documents `KYW` as delaying "any following host commands … until the
    /// current message has been sent … e.g., KS (keyer speed)" — exactly the
    /// deferred speed change the constitution forbids. Not sending `KY` at all
    /// is what puts that trap out of reach.
    func testDriverNeverSendsKY() {
        let mock = MockSerialTransport()
        let driver = ElecraftK3Driver()
        driver.start(transport: mock)
        driver.setFrequency(hz: 14_042_000)
        driver.setMode(rawMode: "CW")
        driver.setKeyerSpeed(wpm: 28)
        // Two poll cycles, so the poll loop gets its chance to ask as well.
        Thread.sleep(forTimeInterval: 1.2)
        driver.stop()

        XCTAssertFalse(mock.allWritten.contains("KY"), "wrote: \(mock.allWritten)")
    }

    func testDriverIsNotAnInternalKeyerDriver() {
        XCTAssertFalse(
            ElecraftK3Driver() is any InternalKeyerDriver,
            "a K3 is keyed from its key line — it must not offer an internal-keyer path"
        )
    }

    func testDriverStartSendsSetupAndPolls() {
        let mock = MockSerialTransport()
        let driver = ElecraftK3Driver()
        driver.start(transport: mock)
        XCTAssertTrue(mock.allWritten.contains("AI0;"))
        XCTAssertTrue(mock.allWritten.contains("K31;"))

        let expectation = expectation(description: "poll happens")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            if mock.allWritten.contains("IF;") { expectation.fulfill() }
        }
        wait(for: [expectation], timeout: 2.0)
        driver.stop()
    }

    func testDriverParsesFragmentedResponses() {
        let mock = MockSerialTransport()
        let driver = ElecraftK3Driver()

        let got = expectation(description: "state delivered")
        nonisolated(unsafe) var received: RadioState?
        driver.onStateChange = { state in
            received = state
            got.fulfill()
        }
        driver.start(transport: mock)

        // Response arrives split across two reads.
        let full = ifResponse(freqHz: 14_042_000)
        let mid = full.index(full.startIndex, offsetBy: 9)
        mock.inject(String(full[..<mid]))
        mock.inject(String(full[mid...]))

        wait(for: [got], timeout: 2.0)
        XCTAssertEqual(received?.frequencyKHz, 14042)
        XCTAssertEqual(received?.rawMode, "CW")
        driver.stop()
    }

    func testDriverDeduplicatesUnchangedState() {
        let mock = MockSerialTransport()
        let driver = ElecraftK3Driver()
        nonisolated(unsafe) var count = 0
        let first = expectation(description: "first state")
        driver.onStateChange = { _ in
            count += 1
            if count == 1 { first.fulfill() }
        }
        driver.start(transport: mock)
        mock.inject(ifResponse(freqHz: 14_042_000))
        mock.inject(ifResponse(freqHz: 14_042_000))  // identical — no second callback
        mock.inject(ifResponse(freqHz: 14_042_000))
        wait(for: [first], timeout: 2.0)
        // Give the identical injections a moment to (not) fire.
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(count, 1)
        driver.stop()
    }

    func testCWKeyerTogglesConfiguredLine() {
        let mock = MockSerialTransport()
        let keyer = CWKeyer(
            transport: mock,
            config: KeyerLineConfig(keyLine: .dtr, pttLine: nil, pttEnabled: false),
            wpm: 40
        )
        keyer.send("E")
        // E at 40 WPM = 30 ms down; allow generous time.
        let deadline = Date().addingTimeInterval(2)
        while keyer.isIdle == false && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        Thread.sleep(forTimeInterval: 0.1)
        let dtrEvents = mock.lineStates.filter { $0.0 == .dtr }
        XCTAssertTrue(dtrEvents.contains { $0.1 == true }, "key down happened")
        XCTAssertEqual(dtrEvents.last?.1, false, "ends key-up")
        keyer.shutdown()
    }

    func testCWKeyerAbortForcesKeyUp() {
        let mock = MockSerialTransport()
        let keyer = CWKeyer(
            transport: mock,
            config: KeyerLineConfig(keyLine: .dtr, pttLine: .rts, pttEnabled: true, pttLeadMs: 10, pttTailMs: 10),
            wpm: 8
        )
        keyer.send("CQ CQ CQ TEST CQ CQ CQ TEST")
        Thread.sleep(forTimeInterval: 0.15)
        keyer.abort()
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(mock.lineStates.last(where: { $0.0 == .dtr })?.1, false)
        XCTAssertEqual(mock.lineStates.last(where: { $0.0 == .rts })?.1, false)
        keyer.shutdown()
    }

    func testRegistryHasK3() {
        XCTAssertNotNil(RadioRegistry.descriptor(id: "elecraft-k3"))
        XCTAssertEqual(RadioRegistry.descriptor(id: "elecraft-k3")?.defaultBaud, 38400)
        XCTAssertEqual(RadioRegistry.descriptor(id: "elecraft-k3")?.baudRates, [4800, 9600, 19200, 38400])
    }
}

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

    /// Inject raw bytes. `inject` encodes UTF-8, which mangles the high-bit
    /// bytes an `IC` response is made of — the driver decodes ISO Latin-1,
    /// where every byte is exactly one character.
    func injectBytes(_ bytes: [UInt8]) {
        onReceive?(Data(bytes))
    }

    func clearWritten() {
        lock.withLock { written.removeAll() }
    }

    var allWritten: String {
        lock.withLock { written.joined() }
    }

    /// Every poll string any driver here writes on its timer.
    static let pollStrings = [ElecraftProtocol.pollCommands, ElecraftKXDriver.pollCommands]

    /// Writes with the periodic poll filtered out.
    ///
    /// `start` schedules a repeating poll on its own queue, so a test that
    /// asserts *exactly* what a command emitted would race it. Filtering the
    /// poll makes those assertions deterministic instead of merely usually
    /// true, which is the difference between a test and a flake.
    var writtenExcludingPolls: String {
        lock.withLock {
            written.filter { !Self.pollStrings.contains($0) }.joined()
        }
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
        let state = try XCTUnwrap(ElecraftProtocol.parseIF(ifResponse(freqHz: 14_042_000)))
        XCTAssertEqual(state.frequencyHz, 14_042_000)
        XCTAssertEqual(state.frequencyKHz, 14042)
        XCTAssertEqual(state.rawMode, "CW")
        XCTAssertEqual(state.band, .m20)
        XCTAssertFalse(state.isTransmitting)
    }

    func testParseIFTransmitAndModes() throws {
        let tx = try XCTUnwrap(ElecraftProtocol.parseIF(ifResponse(freqHz: 7_040_000, tx: true)))
        XCTAssertTrue(tx.isTransmitting)
        XCTAssertEqual(tx.band, .m40)

        let usb = try XCTUnwrap(ElecraftProtocol.parseIF(ifResponse(freqHz: 14_240_000, modeDigit: "2")))
        XCTAssertEqual(usb.rawMode, "USB")
        XCTAssertEqual(usb.modeClass, .phone)

        let data = try XCTUnwrap(ElecraftProtocol.parseIF(ifResponse(freqHz: 14_080_000, modeDigit: "6")))
        XCTAssertEqual(data.modeClass, .digital)

        let cwr = try XCTUnwrap(ElecraftProtocol.parseIF(ifResponse(freqHz: 14_042_000, modeDigit: "7")))
        XCTAssertEqual(cwr.rawMode, "CW")
    }

    func testParseIFRejectsGarbage() {
        XCTAssertNil(ElecraftProtocol.parseIF("FA00014042000;"))
        XCTAssertNil(ElecraftProtocol.parseIF("IF123"))
        XCTAssertNil(ElecraftProtocol.parseIF(""))
        XCTAssertNil(ElecraftProtocol.parseIF("?;"))
    }

    func testParseSimpleResponses() {
        XCTAssertEqual(ElecraftProtocol.parseFA("FA00014042000;"), 14_042_000)
        XCTAssertEqual(ElecraftProtocol.parseMD("MD3;"), .cw)
        XCTAssertEqual(ElecraftProtocol.parseMD("MD9;"), .dataReverse)
        XCTAssertEqual(ElecraftProtocol.parseKS("KS028;"), 28)
        XCTAssertNil(ElecraftProtocol.parseFA("FA;"))
    }

    /// `KS` "nnn is 008-050 (8-50 WPM)" (Pgmrs Ref G5) — a reading outside
    /// that range is not the radio speaking, it is line noise, and RF on the
    /// serial line during a transmission is the classic source. Believing one
    /// is what sent the speed sync to its 8/50 clamp rails mid-message
    /// (2026-08-29): a single flipped bit turns "KS015;" into "KS815;", the
    /// app adopts 815, and the write-back clamps it to 50 on the radio's
    /// front panel while the message on the air jumps with it.
    func testParseKSRejectsSpeedsTheRadioCannotReport() {
        XCTAssertEqual(ElecraftProtocol.parseKS("KS008;"), 8)
        XCTAssertEqual(ElecraftProtocol.parseKS("KS050;"), 50)
        XCTAssertNil(ElecraftProtocol.parseKS("KS815;"))
        XCTAssertNil(ElecraftProtocol.parseKS("KS005;"))
        XCTAssertNil(ElecraftProtocol.parseKS("KS000;"))
        XCTAssertNil(ElecraftProtocol.parseKS("KS999;"))
    }

    func testCommandBuilders() {
        XCTAssertEqual(ElecraftProtocol.cmdSetFrequency(hz: 14_042_000), "FA00014042000;")
        XCTAssertEqual(ElecraftProtocol.cmdSetKeyerSpeed(wpm: 28), "KS028;")
        XCTAssertEqual(ElecraftProtocol.cmdSetKeyerSpeed(wpm: 99), "KS050;", "clamped to 50")
        XCTAssertEqual(ElecraftProtocol.cmdSetKeyerSpeed(wpm: 1), "KS008;", "clamped to 8")
    }

    func testCmdSetMode() {
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "CW", frequencyHz: 14_040_000), "MD3;")
        XCTAssertEqual(
            ElecraftProtocol.cmdSetMode(rawMode: "SSB", frequencyHz: 14_200_000), "MD2;",
            "SSB above 10 MHz is USB"
        )
        XCTAssertEqual(
            ElecraftProtocol.cmdSetMode(rawMode: "SSB", frequencyHz: 7_200_000), "MD1;",
            "SSB below 10 MHz is LSB"
        )
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "USB", frequencyHz: 7_200_000), "MD2;")
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "LSB", frequencyHz: 14_200_000), "MD1;")
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "RTTY", frequencyHz: 14_080_000), "MD6;")
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "AM", frequencyHz: 14_200_000), "MD5;")
        XCTAssertEqual(ElecraftProtocol.cmdSetMode(rawMode: "FM", frequencyHz: 29_600_000), "MD4;")
        XCTAssertNil(ElecraftProtocol.cmdSetMode(rawMode: "???", frequencyHz: 14_000_000))
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

    // MARK: OM — model and voice memory count

    /// Programmer's Reference G5, OM entry: "OM APXSDFfLVR--;" with a missing
    /// module's letter replaced by a dash. D at index 4 is the KDVR3.
    func testParseOMK3WithRecorderHasEightMemories() throws {
        let result = try XCTUnwrap(ElecraftProtocol.parseOM("OM APXSDFfLVR--;"))
        XCTAssertEqual(result.model, .k3)
        XCTAssertEqual(result.voice, .available(count: 8))
    }

    func testParseOMK3WithoutRecorderIsNotInstalled() throws {
        let result = try XCTUnwrap(ElecraftProtocol.parseOM("OM -P-S--------;"))
        XCTAssertEqual(result.model, .k3)
        XCTAssertEqual(result.voice, .notInstalled)
    }

    /// The reference prints the K3 example with a space after OM. Tolerate both.
    func testParseOMWithoutTheSpace() throws {
        let result = try XCTUnwrap(ElecraftProtocol.parseOM("OMAPXSDFfLVR--;"))
        XCTAssertEqual(result.voice, .available(count: 8))
    }

    /// KX3 and KX2 have the recorder built in — two memories, nothing to detect.
    /// The trailing 0n is the product identifier: 1 = KX2, 2 = KX3.
    func testParseOMKX2() throws {
        let result = try XCTUnwrap(ElecraftProtocol.parseOM("OM A-F-------01;"))
        XCTAssertEqual(result.model, .kx2)
        XCTAssertEqual(result.voice, .available(count: 2))
    }

    func testParseOMKX3() throws {
        let result = try XCTUnwrap(ElecraftProtocol.parseOM("OM A-F-------02;"))
        XCTAssertEqual(result.model, .kx3)
        XCTAssertEqual(result.voice, .available(count: 2))
    }

    /// Radios do send partial lines. A driver that traps on one takes the app
    /// down mid-contest (Article 13).
    func testParseOMRejectsTruncatedAndForeignResponses() {
        XCTAssertNil(ElecraftProtocol.parseOM("OM APX;"))
        XCTAssertNil(ElecraftProtocol.parseOM("OM;"))
        XCTAssertNil(ElecraftProtocol.parseOM(""))
        XCTAssertNil(ElecraftProtocol.parseOM("IF00014042000;"))
    }

    /// The reference reserves the K3's trailing dashes "for future module
    /// letters and product ID", so a later K3 could report an identifier where
    /// only a KX reports one today. A K3 read as a KX would be sent memory
    /// commands from the wrong table, so a fitted recorder — a `D` at index 4,
    /// which no KX can carry — settles the family regardless of 10–11.
    func testARecorderEquippedK3IsNeverMistakenForAKX() throws {
        let asIfProductIDed = try XCTUnwrap(ElecraftProtocol.parseOM("OM APXSDFfLVR02;"))
        XCTAssertEqual(asIfProductIDed.model, .k3)
        XCTAssertEqual(asIfProductIDed.voice, .available(count: 8))
    }

    /// ...and the guard must not cost a real KX its identity: index 4 is a
    /// reserved dash on both KX models, so neither is affected.
    func testTheGuardStillIdentifiesBothKXModels() throws {
        XCTAssertEqual(try XCTUnwrap(ElecraftProtocol.parseOM("OM A-F-------01;")).model, .kx2)
        XCTAssertEqual(try XCTUnwrap(ElecraftProtocol.parseOM("OM A-F-------02;")).model, .kx3)
        XCTAssertEqual(try XCTUnwrap(ElecraftProtocol.parseOM("OM APF---TBXI02;")).model, .kx3)
    }

    // MARK: IC — playback and bank

    /// `ICabcde;` — five 8-bit characters. B7 of every byte is always 1, so no
    /// control character is sent; B2 of byte a is "MSG is playing" and B3 is
    /// the message bank. Programmer's Reference G5, Table 4.
    func icResponse(playing: Bool, bank: Int) -> String {
        var a: UInt8 = 0x80
        if playing { a |= 0x04 }
        if bank == 2 { a |= 0x08 }
        let rest = String(repeating: "\u{80}", count: 4)
        return "IC" + String(UnicodeScalar(a)) + rest + ";"
    }

    func testParseICReadsPlaybackState() throws {
        let playing = try XCTUnwrap(ElecraftProtocol.parseIC(icResponse(playing: true, bank: 1)))
        XCTAssertTrue(playing.playing)
        let idle = try XCTUnwrap(ElecraftProtocol.parseIC(icResponse(playing: false, bank: 1)))
        XCTAssertFalse(idle.playing)
    }

    func testParseICReadsBank() throws {
        let one = try XCTUnwrap(ElecraftProtocol.parseIC(icResponse(playing: false, bank: 1)))
        XCTAssertEqual(one.bank, 1)
        let two = try XCTUnwrap(ElecraftProtocol.parseIC(icResponse(playing: false, bank: 2)))
        XCTAssertEqual(two.bank, 2)
    }

    /// The always-set B7 must not leak into either answer, and the two bits
    /// must not be read as one.
    func testParseICSeparatesTheTwoBits() throws {
        let both = try XCTUnwrap(ElecraftProtocol.parseIC(icResponse(playing: true, bank: 2)))
        XCTAssertTrue(both.playing)
        XCTAssertEqual(both.bank, 2)
    }

    func testParseICRejectsShortAndForeignResponses() {
        XCTAssertNil(ElecraftProtocol.parseIC("IC;"))
        XCTAssertNil(ElecraftProtocol.parseIC("IC\u{80}\u{80};"))
        XCTAssertNil(ElecraftProtocol.parseIC("KS020;"))
    }

    /// The raw bytes of an `IC` response, for `injectBytes`.
    func icBytes(playing: Bool, bank: Int) -> [UInt8] {
        var a: UInt8 = 0x80
        if playing { a |= 0x04 }
        if bank == 2 { a |= 0x08 }
        return Array("IC".utf8) + [a, 0x80, 0x80, 0x80, 0x80] + Array(";".utf8)
    }

    // MARK: Voice memory commands

    /// Table 7 — M1-M4 TAP. In a voice mode these play the recorder's
    /// messages; in CW the same switches play CW text memories.
    func testK3MemoryTapCommands() {
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[1], "SWT21;")
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[2], "SWT31;")
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[3], "SWT35;")
        XCTAssertEqual(ElecraftK3Driver.cmdPlayK3Memory[4], "SWT39;")
    }

    /// "Terminates transmit in all modes, including message play and repeating
    /// messages" — Programmer's Reference G5, RX entry.
    func testStopVoiceMessageCommand() {
        XCTAssertEqual(ElecraftK3Driver.cmdStopVoiceMessage, "RX;")
    }

    func testBankSelectCommand() {
        XCTAssertEqual(ElecraftK3Driver.cmdSelectBank, "SWH37;")
    }

    // MARK: Playing, end to end over the transport

    /// Bring a driver up as the given model, clear the start-up writes, and
    /// stop it when the test ends so its poll timer does not outlive the case.
    func startedRadio(om: String, bank: Int = 1) -> (ElecraftK3Driver, MockSerialTransport) {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        addTeardownBlock { driver.stop() }
        transport.inject(om)
        transport.injectBytes(icBytes(playing: false, bank: bank))
        transport.clearWritten()
        return (driver, transport)
    }

    /// A K3 with the KDVR3 fitted, with `bank` already confirmed.
    func startedK3(bank: Int = 1) -> (ElecraftK3Driver, MockSerialTransport) {
        startedRadio(om: "OM APXSDFfLVR--;", bank: bank)
    }

    func testPlayingABankOneMemoryTapsImmediately() {
        let (driver, transport) = startedK3()
        driver.playVoiceMessage(memory: 3)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT35;")
    }

    func testStopSendsRX() {
        let (driver, transport) = startedK3()
        driver.stopVoiceMessage()
        XCTAssertEqual(transport.writtenExcludingPolls, "RX;")
    }

    // MARK: Transmit control for recordings made on the Mac (Pgmrs Ref G5: TX, RX)

    /// `TX;` — "Same as activating PTT or using the XMIT switch"; `RX;` —
    /// "Terminates transmit in all modes". The sound-card player calls these
    /// around a clip, lead before and tail after.
    func testSetTransmitOnWritesTXAndOffWritesRX() {
        let (driver, transport) = startedK3()
        driver.setTransmit(true)
        XCTAssertEqual(transport.writtenExcludingPolls, "TX;")
        driver.setTransmit(false)
        XCTAssertEqual(transport.writtenExcludingPolls, "TX;RX;")
    }

    /// The Elecraft family keys over CAT for a sound-card recording, and never
    /// takes the samples over its own link (Article 11: exactly one path).
    func testDriverKeysOverCATAndDoesNotStream() {
        let driver: any RadioDriver = ElecraftK3Driver()
        XCTAssertNotNil(driver as? any TransmitControlCapable)
        XCTAssertNil(driver as? any AudioStreamTransmitCapable)
    }

    /// Nothing about the recorder's own path is disturbed by keying: a play
    /// after `TX;`/`RX;` still taps the memory directly.
    func testKeyingLeavesTheVoiceMemoryPathAlone() {
        let (driver, transport) = startedK3()
        driver.setTransmit(true)
        driver.setTransmit(false)
        transport.clearWritten()
        driver.playVoiceMessage(memory: 2)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT31;")
    }

    /// A memory this radio does not have is ignored, never clamped onto a
    /// neighbouring recording.
    func testOutOfRangeMemoriesTransmitNothing() {
        let (driver, transport) = startedK3()
        driver.playVoiceMessage(memory: 0)
        driver.playVoiceMessage(memory: 9)
        driver.playVoiceMessage(memory: -1)
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }

    /// A portable answering on this descriptor is not claimed. Its memories
    /// are reached by a different switch sequence, so offering them here could
    /// only tap the wrong switches — the mirror of
    /// `KXProtocolTests.testAK3AnsweringHereIsNotClaimed`.
    func testAKXAnsweringHereIsNotClaimedAndTapsNothing() {
        nonisolated(unsafe) var reported: [VoiceKeyerStatus] = []
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.onVoiceKeyerStatusChange = { reported.append($0) }
        driver.start(transport: transport)
        addTeardownBlock { driver.stop() }

        transport.inject("OM A-F-------01;")
        transport.clearWritten()
        driver.playVoiceMessage(memory: 1)

        XCTAssertEqual(reported, [], "no memory count may be claimed for a radio this driver cannot play")
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }

    /// A K3 with no recorder fitted must not emit a tap at all.
    func testNoRecorderMeansNoTap() {
        let (driver, transport) = startedRadio(om: "OM -P-S--------;")
        driver.playVoiceMessage(memory: 1)
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }

    // MARK: Bank sequencing

    /// Asking for a bank-2 memory requests the bank change and sends no tap.
    func testBankTwoMemoryRequestsTheBankAndDoesNotTapYet() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWH37;IC;")
        XCTAssertFalse(transport.allWritten.contains("SWT31;"), "tapped before the bank confirmed")
    }

    /// The tap follows only once an IC confirms the radio really is in bank 2 —
    /// and it is bank 2's M2, i.e. memory 6.
    func testTapFollowsTheBankConfirmation() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 2))
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT31;")
    }

    /// **The safety property.** If the bank never confirms, nothing is
    /// transmitted at all — and the driver says so rather than failing silent.
    func testAnUnconfirmedBankTransmitsNothingAndReports() {
        let (driver, transport) = startedK3(bank: 1)
        let dropped = expectation(description: "play dropped")
        driver.onVoiceMessageDropped = { memory, reason in
            XCTAssertEqual(memory, 6)
            XCTAssertEqual(reason, .unconfirmed, "a bank that never confirmed is a real failure")
            dropped.fulfill()
        }

        driver.playVoiceMessage(memory: 6)
        transport.clearWritten()

        // Two IC responses that still say bank 1 — the switch did not take.
        transport.injectBytes(icBytes(playing: false, bank: 1))
        transport.injectBytes(icBytes(playing: false, bank: 1))

        wait(for: [dropped], timeout: 1)
        XCTAssertEqual(transport.writtenExcludingPolls, "", "no tap may be sent on an unconfirmed bank")
    }

    /// Never toggle twice: a second SWH37; would land back in bank 1. The
    /// two-response window absorbs a poll that was already in flight, it does
    /// not license a retry.
    func testTheBankIsNeverToggledTwiceForOneRequest() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 5)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 1))
        transport.injectBytes(icBytes(playing: false, bank: 1))

        XCTAssertFalse(transport.allWritten.contains("SWH37;"))
    }

    /// A stale poll arriving first must not spend the whole window: the real
    /// confirmation still lands the tap.
    func testAStalePollBeforeTheConfirmationStillPlays() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 8)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 1))   // stale, in flight
        XCTAssertEqual(transport.writtenExcludingPolls, "", "tapped on the stale response")
        transport.injectBytes(icBytes(playing: false, bank: 2))   // the confirmation
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT39;", "bank 2 M4 is memory 8")
    }

    // MARK: A second press inside the confirmation window

    /// A press landing while a bank change this driver requested is still
    /// unconfirmed must not tap: writes are FIFO, so the tap would arrive after
    /// the toggle and play the other bank's recording.
    func testAPressDuringAnUnconfirmedToggleIsRefusedRatherThanMisdirected() {
        let (driver, transport) = startedK3(bank: 1)
        nonisolated(unsafe) var dropped: [Int] = []
        nonisolated(unsafe) var reasons: [VoiceMessageDropReason] = []
        driver.onVoiceMessageDropped = { dropped.append($0); reasons.append($1) }

        driver.playVoiceMessage(memory: 6)      // arms the toggle
        transport.clearWritten()
        driver.playVoiceMessage(memory: 2)      // bank 1 — would tap under the old fast path

        XCTAssertEqual(transport.writtenExcludingPolls, "",
                       "SWT31; here lands in bank 2 and plays memory 6, not memory 2")
        XCTAssertEqual(dropped, [2])
        XCTAssertEqual(reasons, [.busy], "a press while busy is not a fault")
    }

    /// A second bank-2 press must not toggle again — a double toggle lands back
    /// in bank 1 — and must not silently discard the first request.
    func testASecondPressInTheWindowNeitherTogglesAgainNorVanishes() {
        let (driver, transport) = startedK3(bank: 1)
        nonisolated(unsafe) var dropped: [Int] = []
        nonisolated(unsafe) var reasons: [VoiceMessageDropReason] = []
        driver.onVoiceMessageDropped = { dropped.append($0); reasons.append($1) }

        driver.playVoiceMessage(memory: 6)
        transport.clearWritten()
        driver.playVoiceMessage(memory: 7)

        XCTAssertFalse(transport.writtenExcludingPolls.contains("SWH37;"), "toggled twice")
        XCTAssertEqual(dropped, [7], "the refused press must say so")
        XCTAssertEqual(reasons, [.busy])
    }

    /// The refusal is not sticky: once the pending play resolves, the next press
    /// is served normally.
    func testAPlayIsServedAgainOnceThePendingOneResolves() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        transport.injectBytes(icBytes(playing: false, bank: 2))   // resolves, taps SWT31;
        transport.clearWritten()

        driver.playVoiceMessage(memory: 7)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT35;", "bank 2 M3 is memory 7")
    }

    /// Once bank 2 is confirmed, a second bank-2 memory taps straight away.
    func testASecondBankTwoMemoryNeedsNoFurtherSwitch() {
        let (driver, transport) = startedK3(bank: 2)
        driver.playVoiceMessage(memory: 7)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT35;")
    }

    // MARK: A bank that has never been observed

    /// A K3 whose bank has never been observed — `OM` has answered, no `IC` yet.
    func startedK3BeforeAnyIC() -> (ElecraftK3Driver, MockSerialTransport) {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        addTeardownBlock { driver.stop() }
        transport.inject("OM APXSDFfLVR--;")
        transport.clearWritten()
        return (driver, transport)
    }

    /// An unobserved bank is asked about, never toggled: toggling would flip the
    /// operator's bank on the strength of a guess.
    func testAnUnobservedBankIsAskedAboutRatherThanToggled() {
        let (driver, transport) = startedK3BeforeAnyIC()
        driver.playVoiceMessage(memory: 2)
        XCTAssertEqual(transport.writtenExcludingPolls, "IC;")
        XCTAssertFalse(transport.allWritten.contains("SWH37;"), "toggled a bank it had never seen")
    }

    /// ...and when the answer turns out to be the bank we wanted, it just taps.
    func testAnUnobservedBankThatIsAlreadyRightJustTaps() {
        let (driver, transport) = startedK3BeforeAnyIC()
        driver.playVoiceMessage(memory: 2)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 1))
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT31;")
    }

    /// ...and when it turns out wrong, *then* it toggles, and taps on the
    /// confirmation after that.
    func testAnUnobservedBankThatIsWrongTogglesThenTaps() {
        let (driver, transport) = startedK3BeforeAnyIC()
        driver.playVoiceMessage(memory: 6)
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 1))
        XCTAssertEqual(transport.writtenExcludingPolls, "SWH37;IC;")

        transport.clearWritten()
        transport.injectBytes(icBytes(playing: false, bank: 2))
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT31;", "bank 2 M2 is memory 6")
    }

    /// Aborting clears a pending play: a later IC must not resurrect it.
    func testStopClearsAPendingPlay() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        driver.stopVoiceMessage()
        transport.clearWritten()

        transport.injectBytes(icBytes(playing: false, bank: 2))
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }

    /// Aborting inside the confirmation window invalidates the observed bank.
    /// The toggle may well have taken effect — `RX;` stops the audio, it does
    /// not undo a bank change — so the last `IC` reading is no longer evidence
    /// and the next press must ask rather than tap on it.
    func testAbortingAnUnconfirmedToggleForgetsTheObservedBank() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)      // toggle requested, unconfirmed
        driver.stopVoiceMessage()
        transport.clearWritten()

        driver.playVoiceMessage(memory: 2)
        XCTAssertEqual(transport.writtenExcludingPolls, "IC;",
                       "SWT31; here plays memory 6 if the toggle did take effect")
    }

    /// A dropped play leaves the same doubt an abort does: a toggle was asked
    /// for and never confirmed. The next press asks rather than assuming the
    /// toggle failed to take.
    func testAPressAfterADroppedPlayAsksForTheBank() {
        let (driver, transport) = startedK3(bank: 1)
        driver.playVoiceMessage(memory: 6)
        transport.injectBytes(icBytes(playing: false, bank: 1))
        transport.injectBytes(icBytes(playing: false, bank: 1))   // window closes, dropped
        transport.clearWritten()

        driver.playVoiceMessage(memory: 2)
        XCTAssertEqual(transport.writtenExcludingPolls, "IC;",
                       "SWT31; here assumes a toggle we never saw land")
    }

    /// ...but an abort with no toggle outstanding must not throw away a good
    /// reading, or every Esc would cost the next press an extra round trip.
    func testAbortingWithNoToggleOutstandingKeepsTheObservedBank() {
        let (driver, transport) = startedK3(bank: 1)
        driver.stopVoiceMessage()
        transport.clearWritten()

        driver.playVoiceMessage(memory: 2)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT31;")
    }

    // MARK: Discovery

    func testStartAsksForOptionsAndPollsIcons() {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        XCTAssertTrue(transport.allWritten.contains("OM;"), "options never requested")
    }

    /// A radio powered on after the app connected would miss a one-shot query
    /// and read as having no recorder for the rest of the session. The first IF
    /// is the moment it proves it is listening, so ask again there — once.
    func testOptionsAreAskedAgainOnTheFirstIF() {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        transport.clearWritten()

        transport.inject(ifResponse(freqHz: 14_042_000))
        XCTAssertTrue(transport.allWritten.contains("OM;"))

        transport.clearWritten()
        transport.inject(ifResponse(freqHz: 14_043_000))
        XCTAssertFalse(transport.allWritten.contains("OM;"), "asked more than once")
    }

    func testPollIncludesIcons() {
        XCTAssertTrue(ElecraftProtocol.pollCommands.contains("IC;"))
        XCTAssertTrue(ElecraftProtocol.pollCommands.contains("IF;"))
        XCTAssertTrue(ElecraftProtocol.pollCommands.contains("KS;"))
    }

    func testStatusChangeIsReportedOnce() {
        let driver = ElecraftK3Driver()
        let transport = MockSerialTransport()
        nonisolated(unsafe) var reported: [VoiceKeyerStatus] = []
        driver.onVoiceKeyerStatusChange = { reported.append($0) }
        driver.start(transport: transport)

        transport.inject("OM APXSDFfLVR--;")
        transport.inject("OM APXSDFfLVR--;")
        XCTAssertEqual(reported, [.available(count: 8)])
    }

    func testPlaybackChangeIsReportedOnlyOnChange() {
        let (driver, transport) = startedK3()
        nonisolated(unsafe) var reported: [Bool] = []
        driver.onVoicePlaybackChange = { reported.append($0) }

        transport.injectBytes(icBytes(playing: true, bank: 1))
        transport.injectBytes(icBytes(playing: true, bank: 1))
        transport.injectBytes(icBytes(playing: false, bank: 1))
        XCTAssertEqual(reported, [true, false])

        // The very first `IC` of a *session* is a boundary `startedK3()`
        // cannot reach — it already seeds one `IC` (`playing: false`) before
        // returning. A fresh driver's `lastVoicePlaying` starts nil (nothing
        // observed yet, not "was playing"), so the first-ever observation of
        // "not playing" must not itself read as a change, while a first
        // observation of "playing" still does — that really is new
        // information the app never asked for.
        let (idleDriver, idleTransport) = startedK3BeforeAnyIC()
        nonisolated(unsafe) var idleReported: [Bool] = []
        idleDriver.onVoicePlaybackChange = { idleReported.append($0) }
        idleTransport.injectBytes(icBytes(playing: false, bank: 1))
        XCTAssertEqual(idleReported, [], "nil→false is not a transition")

        let (playingDriver, playingTransport) = startedK3BeforeAnyIC()
        nonisolated(unsafe) var playingReported: [Bool] = []
        playingDriver.onVoicePlaybackChange = { playingReported.append($0) }
        playingTransport.injectBytes(icBytes(playing: true, bank: 1))
        XCTAssertEqual(playingReported, [true], "nil→true is still new information")
    }
}

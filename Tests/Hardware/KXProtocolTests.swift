import XCTest
@testable import QSOPartyLogger

/// The KX3/KX2 driver, on the wire, over a mock transport.
///
/// This radio is keyed through its **own** keyer, which is the opposite of
/// every other serial radio the app supports — and it is not a preference.
/// A KX's CAT jack (ACC) is tip = RX data, ring 1 = TX data, ring 2 = key
/// *out* for amplifiers: no key line reaches the app, so Article 11's
/// `InternalKeyerDriver` arm is the only one available. `CW KEY1 = HAND` makes
/// the KEY jack accept a computer, but that is a second wire this app cannot
/// assume. See `docs/research/kx_cw_keying.md`.
///
/// Every byte asserted here is quoted from the **Programmer's Reference G5**
/// (Article 12): `KY *[text];` with 0–24 characters and a blank rather than
/// `W`; `KYn;` where n is 0 (buffer not full) or 1 (full); `RX;` terminating
/// transmit in all modes; `SWT`/`SWH` Table 8A for the KX2 and Table 8 for the
/// KX3.
final class KXProtocolTests: XCTestCase {

    // MARK: Harness

    /// Bring a driver up as the given model and clear the start-up writes.
    /// Stopped at teardown so its poll timer cannot outlive the case.
    private func startedRadio(om: String) -> (ElecraftKXDriver, MockSerialTransport) {
        let driver = ElecraftKXDriver()
        let transport = MockSerialTransport()
        driver.start(transport: transport)
        addTeardownBlock { driver.stop() }
        transport.inject(om)
        transport.clearWritten()
        return (driver, transport)
    }

    /// A KX2 — `OM` product identifier `01`.
    private func startedKX2() -> (ElecraftKXDriver, MockSerialTransport) {
        startedRadio(om: "OM A-F-------01;")
    }

    /// A KX3 — product identifier `02`.
    private func startedKX3() -> (ElecraftKXDriver, MockSerialTransport) {
        startedRadio(om: "OM A-F-------02;")
    }

    // MARK: Article 11 — this radio has exactly one way to send CW

    func testDriverKeysThroughTheRadiosOwnKeyer() {
        XCTAssertTrue(
            ElecraftKXDriver() is any InternalKeyerDriver,
            "a KX's CAT jack carries no key line, so its driver must offer the internal-keyer path"
        )
    }

    func testRegistryOffersTheKXAndDoesNotClaimDirectKeying() throws {
        let descriptor = try XCTUnwrap(RadioRegistry.descriptor(id: "elecraft-kx"))
        XCTAssertFalse(
            descriptor.supportsDirectKeying,
            "a KX cannot be keyed from the CAT port's control lines"
        )
        XCTAssertEqual(descriptor.connection, .serial)
        XCTAssertEqual(descriptor.baudRates, ElecraftProtocol.baudRates)
    }

    /// The K3 keeps direct keying, and keeps its own id so a saved setting
    /// still resolves.
    func testTheK3KeepsItsIdAndItsDirectKeying() throws {
        let k3 = try XCTUnwrap(RadioRegistry.descriptor(id: "elecraft-k3"))
        XCTAssertTrue(k3.supportsDirectKeying)
        XCTAssertEqual(RadioRegistry.defaultRadioID, "elecraft-k3")
    }

    // MARK: OM — which model answered

    func testOMIdentifiesBothKXModelsWithTwoMemories() throws {
        nonisolated(unsafe) var reported: [VoiceKeyerStatus] = []
        let driver = ElecraftKXDriver()
        let transport = MockSerialTransport()
        driver.onVoiceKeyerStatusChange = { reported.append($0) }
        driver.start(transport: transport)
        addTeardownBlock { driver.stop() }

        transport.inject("OM A-F-------01;")
        XCTAssertEqual(reported, [.available(count: 2)], "a KX2 has two voice memories")
    }

    /// A K3 answering on this descriptor is not claimed: this driver cannot
    /// play a K3's banked memories, and saying it could is how the wrong
    /// recording reaches the air.
    func testAK3AnsweringHereIsNotClaimed() {
        let (driver, transport) = startedRadio(om: "OM APXSDFfLVR--;")
        driver.playVoiceMessage(memory: 1)
        XCTAssertEqual(transport.writtenExcludingPolls, "",
                       "a K3's memories are the K3 driver's business")
    }

    // MARK: KY — text to the radio's own keyer

    /// `KY *[text];` — "`*` is normally a BLANK and `[text]` is 0 to 24
    /// characters" (Pgmrs Ref G5). A message that fits goes in one packet, and
    /// no buffer query follows it because there is nothing waiting behind it.
    func testAShortMessageGoesOutInOnePacket() {
        let (driver, transport) = startedKX2()
        driver.sendInternalKeyerText("CQ TEST")
        XCTAssertEqual(transport.writtenExcludingPolls, "KY CQ TEST;")
    }

    /// Longer than 24 characters, so it is split — and the second chunk must
    /// **not** be written until the radio says its buffer has room.
    func testALongMessageIsSplitAndTheSecondChunkWaitsForTheBuffer() {
        let (driver, transport) = startedKX2()
        driver.sendInternalKeyerText("CQ TEST DE KE5CW KE5CW TEST")

        XCTAssertEqual(
            transport.writtenExcludingPolls, "KY CQ TEST DE KE5CW KE5CW ;KY;",
            "the split falls on the last space inside 24 characters, so the word gap survives, "
                + "and KY; asks whether there is room for the rest"
        )

        transport.clearWritten()
        transport.inject("KY1;")           // buffer full
        XCTAssertEqual(transport.writtenExcludingPolls, "",
                       "nothing may be pushed into a buffer the radio says is full")

        transport.inject("KY0;")           // room now
        XCTAssertEqual(transport.writtenExcludingPolls, "KY TEST;",
                       "and the tail follows, with no further query behind it")
    }

    /// The splitter is a pure function and gets its own assertions: never over
    /// 24 characters, never losing a character, and preferring a word gap.
    func testChunkingNeverExceedsTwentyFourCharactersAndLosesNothing() {
        for text in ["CQ TEST", "CQ TEST DE KE5CW KE5CW TEST",
                     String(repeating: "X", count: 60), "A B C D E F G H I J K L M N O P"] {
            let chunks = ElecraftKXDriver.chunks(for: text)
            XCTAssertEqual(chunks.joined(), text.uppercased(), "text lost splitting '\(text)'")
            for chunk in chunks {
                XCTAssertLessThanOrEqual(chunk.count, 24, "chunk too long in '\(text)': '\(chunk)'")
                XCTAssertFalse(chunk.isEmpty, "empty chunk from '\(text)'")
            }
        }
    }

    /// A word longer than the packet has to be cut somewhere; it is cut at 24
    /// rather than dropped.
    func testAWordLongerThanOnePacketIsHardSplit() {
        XCTAssertEqual(
            ElecraftKXDriver.chunks(for: String(repeating: "X", count: 30)),
            [String(repeating: "X", count: 24), String(repeating: "X", count: 6)]
        )
    }

    // MARK: Abort

    /// `RX;` — "Terminates transmit in all modes, including message play and
    /// repeating messages" (Pgmrs Ref G5). Everything still queued here is
    /// dropped too, so nothing follows the abort onto the air.
    func testStopWritesRXAndDropsWhatWasQueued() {
        let (driver, transport) = startedKX2()
        driver.sendInternalKeyerText("CQ TEST DE KE5CW KE5CW TEST")
        transport.clearWritten()

        driver.stopInternalKeyer()
        XCTAssertEqual(transport.writtenExcludingPolls, "RX;")

        transport.clearWritten()
        transport.inject("KY0;")
        XCTAssertEqual(transport.writtenExcludingPolls, "",
                       "an aborted message must not resume when the buffer drains")
    }

    // MARK: Speed — Article 13 requires this proved per path

    /// The blank `KY` form is chosen precisely so a following `KS` is *not*
    /// deferred: G5 says the `W` form delays "any following host commands …
    /// e.g., KS (keyer speed)". So the speed change goes out immediately, in
    /// the middle of a message, and reaches it.
    func testSpeedGoesOutImmediatelyMidMessage() {
        let (driver, transport) = startedKX2()
        driver.sendInternalKeyerText("CQ TEST DE KE5CW KE5CW TEST")
        transport.clearWritten()

        driver.setKeyerSpeed(wpm: 32)
        XCTAssertEqual(transport.writtenExcludingPolls, "KS032;")
    }

    /// The other half of the same rule: `KYW` must never appear on the wire,
    /// because it is the deferred-side-effect form Article 11 forbids.
    func testDriverNeverSendsTheDeferringKYWForm() {
        let (driver, transport) = startedKX2()
        driver.sendInternalKeyerText("CQ TEST DE KE5CW KE5CW TEST")
        driver.setKeyerSpeed(wpm: 32)
        transport.inject("KY0;")
        driver.sendInternalKeyerText("TU")
        driver.stopInternalKeyer()
        Thread.sleep(forTimeInterval: 1.2)   // two poll cycles

        XCTAssertFalse(transport.allWritten.contains("KYW"), "wrote: \(transport.allWritten)")
    }

    // MARK: Voice memories — Tables 8 and 8A

    /// "tap MSG, then tap the digit". Codes 19 and 27 are digits 1 and 2 on
    /// both models, which is what lets one driver serve them.
    func testVoiceMemoriesTapMSGThenTheDigit() {
        let (kx2, kx2Transport) = startedKX2()
        kx2.playVoiceMessage(memory: 1)
        XCTAssertEqual(kx2Transport.writtenExcludingPolls, "SWT11;SWT19;")

        let (kx3, kx3Transport) = startedKX3()
        kx3.playVoiceMessage(memory: 2)
        XCTAssertEqual(kx3Transport.writtenExcludingPolls, "SWT11;SWT27;")
    }

    /// A KX has two memories. A third is ignored, never clamped onto a
    /// neighbour — wrong audio on the air is worse than silence.
    func testAThirdMemoryTransmitsNothing() {
        let (driver, transport) = startedKX2()
        for memory in [0, 3, 9, -1] {
            driver.playVoiceMessage(memory: memory)
        }
        XCTAssertEqual(transport.writtenExcludingPolls, "")
    }

    /// A KX has no message banks, so the bank-select command must never be
    /// emitted at one.
    func testTheBankCommandIsNeverSentToAKX() {
        let (driver, transport) = startedKX2()
        driver.playVoiceMessage(memory: 1)
        driver.playVoiceMessage(memory: 2)
        driver.stopVoiceMessage()
        XCTAssertFalse(transport.allWritten.contains("SWH37;"))
    }

    func testStopVoiceMessageSendsRX() {
        let (driver, transport) = startedKX2()
        driver.stopVoiceMessage()
        XCTAssertEqual(transport.writtenExcludingPolls, "RX;")
    }

    // MARK: Transmit control for recordings played through a sound card

    func testSetTransmitWritesTXAndRX() {
        let (driver, transport) = startedKX2()
        driver.setTransmit(true)
        driver.setTransmit(false)
        XCTAssertEqual(transport.writtenExcludingPolls, "TX;RX;")
    }

    func testDriverKeysOverCATAndDoesNotStream() {
        XCTAssertNotNil(ElecraftKXDriver() as? any TransmitControlCapable)
        XCTAssertNil(ElecraftKXDriver() as? any AudioStreamTransmitCapable)
    }

    // MARK: State, speed sync, and malformed input

    /// Spec-exact `IF[f]*****+yyyyrx*00tmvspbd1*;`, built field by field rather
    /// than written out, because the two fields that matter sit at offsets 28
    /// and 29 and a hand-counted literal gets them wrong.
    private func ifResponse(freqHz: Int, modeDigit: Character = "3") -> String {
        String(format: "IF%011d", freqHz) + "     " + "+0000" + "0" + "0" + " 00"
            + "0" + String(modeDigit) + "00000" + "1" + " ;"
    }

    func testFrequencyModeAndSpeedAreReported() {
        let (driver, transport) = startedKX2()
        nonisolated(unsafe) var states: [RadioState] = []
        nonisolated(unsafe) var speeds: [Int] = []
        driver.onStateChange = { states.append($0) }
        driver.onKeyerSpeedChange = { speeds.append($0) }

        XCTAssertEqual(ifResponse(freqHz: 14_042_000).count, 38, "spec-exact IF is 38 chars")
        transport.inject(ifResponse(freqHz: 14_042_000))
        transport.inject("KS028;")

        XCTAssertEqual(states.first?.frequencyHz, 14_042_000)
        XCTAssertEqual(states.first?.rawMode, "CW")
        XCTAssertEqual(speeds, [28])
    }

    /// G5's `MD` entry: "FM mode does not apply to the KX2." So a KX2 is never
    /// sent `MD4`, while a KX3 still is.
    func testAKX2IsNeverSentFM() {
        let (kx2, kx2Transport) = startedKX2()
        kx2.setMode(rawMode: "FM")
        XCTAssertEqual(kx2Transport.writtenExcludingPolls, "")

        let (kx3, kx3Transport) = startedKX3()
        kx3.setMode(rawMode: "FM")
        XCTAssertEqual(kx3Transport.writtenExcludingPolls, "MD4;")
    }

    /// Radios do send partial lines; a driver that traps on one takes the app
    /// down mid-contest (Article 13).
    func testMalformedResponsesAreSurvived() {
        let (driver, transport) = startedKX2()
        for junk in ["OM APX;", "IF123", "?;", "KY;", "KS;", ";", "IC\u{80};", ""] {
            transport.inject(junk)
        }
        driver.playVoiceMessage(memory: 1)
        XCTAssertEqual(transport.writtenExcludingPolls, "SWT11;SWT19;",
                       "the driver still works after being fed rubbish")
    }

    func testPollAsksForTheBufferStateSoAStalledMessageRecovers() {
        XCTAssertTrue(ElecraftKXDriver.pollCommands.contains("KY;"))
        XCTAssertTrue(ElecraftKXDriver.pollCommands.contains("IF;"))
        XCTAssertTrue(ElecraftKXDriver.pollCommands.contains("KS;"))
    }
}

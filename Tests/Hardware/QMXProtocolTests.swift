import XCTest
@testable import QSOPartyLogger

/// QRP Labs QMX+ / QMX CAT protocol. Byte strings quoted from the **QMX CAT
/// programming manual, firmware 1_04_004** (23-Jul-2026) unless a test says
/// otherwise; the `KY` buffer arithmetic and the DTR keying story come from the
/// **QMX operating manual, firmware 1_04_004** (Article 12).
///
/// `MockSerialTransport` is shared with `K3ProtocolTests`.
final class QMXProtocolTests: XCTestCase {

    /// Build a spec-exact IF response from the CAT manual's field list:
    /// 11-digit frequency, five spaces, ±4-digit RIT, RIT, XIT, memory bank,
    /// 2-digit memory channel, TX, mode, receive VFO, scan, split, tone, tone
    /// number, one trailing space.
    func ifResponse(freqHz: Int, tx: Bool = false, modeDigit: Character = "3") -> String {
        String(format: "IF%011d", freqHz)   // [0-12]
            + "     "                        // [13-17] 5 spaces
            + "+0000"                        // [18-22] RIT sign+offset
            + "0"                            // [23] RIT off
            + "0"                            // [24] XIT — always 0 on a QMX
            + "0"                            // [25] memory bank — always 0
            + "00"                           // [26-27] memory channel — always 00
            + (tx ? "1" : "0")               // [28] transceiver status
            + String(modeDigit)              // [29] operating mode
            + "0"                            // [30] receive VFO A
            + "0"                            // [31] scan — always 0
            + "0"                            // [32] split
            + "0"                            // [33] tone — always 0
            + "0"                            // [34] tone number — always 0
            + " ;"                           // [35-36]
    }

    func testIFResponseLength() {
        XCTAssertEqual(
            ifResponse(freqHz: 14_042_000).count, 37,
            "the manual's IF field list totals 37 characters including the terminator"
        )
    }

    // MARK: IF

    func testParseIF() throws {
        let state = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 14_042_000)))
        XCTAssertEqual(state.frequencyHz, 14_042_000)
        XCTAssertEqual(state.frequencyKHz, 14042)
        XCTAssertEqual(state.rawMode, "CW")
        XCTAssertEqual(state.band, .m20)
        XCTAssertFalse(state.isTransmitting)
    }

    func testParseIFTransmitAndModes() throws {
        let tx = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 7_040_000, tx: true)))
        XCTAssertTrue(tx.isTransmitting)
        XCTAssertEqual(tx.band, .m40)

        let lsb = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 3_860_000, modeDigit: "1")))
        XCTAssertEqual(lsb.rawMode, "LSB")
        XCTAssertEqual(lsb.modeClass, .phone)

        let usb = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 14_240_000, modeDigit: "2")))
        XCTAssertEqual(usb.rawMode, "USB")
        XCTAssertEqual(usb.modeClass, .phone)

        let fsk = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 14_080_000, modeDigit: "6")))
        XCTAssertEqual(fsk.modeClass, .digital)

        let cwr = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 14_042_000, modeDigit: "7")))
        XCTAssertEqual(cwr.rawMode, "CW", "CW-Reverse is still a CW QSO")

        let fskr = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 14_080_000, modeDigit: "9")))
        XCTAssertEqual(fskr.rawMode, "RTTY")

        let am = try XCTUnwrap(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 3_885_000, modeDigit: "5")))
        XCTAssertEqual(am.rawMode, "AM")
    }

    /// MD8 "activates SWR Tune mode" — a transmission, not a mode. Letting it
    /// through would classify as digital (`ModeClass.classify` defaults there)
    /// and stamp "SWR" on whatever QSO was open while the operator tuned up.
    func testParseIFRejectsSWRTuneAsAMode() {
        XCTAssertNil(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 14_042_000, modeDigit: "8")))
        XCTAssertNil(QMXMode.swrTune.rawMode)
        XCTAssertNil(QMXMode.swrTune.modeClass)
    }

    /// A QMX has no FM, so MD4 does not exist. An unknown digit is dropped
    /// rather than guessed.
    func testParseIFRejectsUndefinedModeDigits() {
        XCTAssertNil(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 29_600_000, modeDigit: "4")))
        XCTAssertNil(QRPLabsQMXDriver.parseIF(ifResponse(freqHz: 14_042_000, modeDigit: "0")))
    }

    /// Radios send partial lines. Every one of these must return nil, not trap.
    func testParseIFRejectsGarbageAndTruncation() {
        XCTAssertNil(QRPLabsQMXDriver.parseIF("FA00014042000;"))
        XCTAssertNil(QRPLabsQMXDriver.parseIF("IF123"))
        XCTAssertNil(QRPLabsQMXDriver.parseIF(""))
        XCTAssertNil(QRPLabsQMXDriver.parseIF("?;"))
        // Cut one character short of the mode digit.
        let full = ifResponse(freqHz: 14_042_000)
        XCTAssertNil(QRPLabsQMXDriver.parseIF(String(full.prefix(29))))
        // Frequency field full of spaces (a QMX still booting its display).
        XCTAssertNil(QRPLabsQMXDriver.parseIF("IF           " + String(full.dropFirst(13))))
    }

    /// Everything the app logs sits at or before index 29, so a line clipped
    /// after the mode digit is still usable.
    func testParseIFAcceptsALineClippedAfterTheModeDigit() throws {
        let clipped = String(ifResponse(freqHz: 14_042_000).prefix(30))
        let state = try XCTUnwrap(QRPLabsQMXDriver.parseIF(clipped))
        XCTAssertEqual(state.frequencyHz, 14_042_000)
        XCTAssertEqual(state.rawMode, "CW")
    }

    // MARK: Simple responses

    func testParseSimpleResponses() {
        XCTAssertEqual(QRPLabsQMXDriver.parseFA("FA00007030000;"), 7_030_000)
        XCTAssertNil(QRPLabsQMXDriver.parseFA("FA;"))
        XCTAssertEqual(QRPLabsQMXDriver.parseMD("MD3;"), .cw)
        XCTAssertEqual(QRPLabsQMXDriver.parseMD("MD8;"), .swrTune)
        XCTAssertNil(QRPLabsQMXDriver.parseMD("MD4;"), "no FM on a QMX")
    }

    /// The CAT manual documents KS's value but never its width, so both the
    /// TS-480 three-digit form it subsets and a bare one answer parse.
    func testParseKSAcceptsAnyDocumentedWidth() {
        XCTAssertEqual(QRPLabsQMXDriver.parseKS("KS028;"), 28)
        XCTAssertEqual(QRPLabsQMXDriver.parseKS("KS28;"), 28)
        XCTAssertEqual(QRPLabsQMXDriver.parseKS("KS8;"), 8)
        XCTAssertNil(QRPLabsQMXDriver.parseKS("KS;"))
        XCTAssertNil(QRPLabsQMXDriver.parseKS("KY0;"), "KY is not a speed report")
    }

    func testParseKY() {
        XCTAssertEqual(QRPLabsQMXDriver.parseKY("KY0;"), .sending)
        XCTAssertEqual(QRPLabsQMXDriver.parseKY("KY1;"), .sendingNearlyFull)
        XCTAssertEqual(QRPLabsQMXDriver.parseKY("KY2;"), .idle)
        XCTAssertNil(QRPLabsQMXDriver.parseKY("KY;"))
        XCTAssertNil(QRPLabsQMXDriver.parseKY("?;"), "the overflow error is not a buffer state")
    }

    // MARK: Command builders

    func testCommandBuilders() {
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetFrequency(hz: 7_030_000), "FA00007030000;")
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetFrequency(hz: 14_042_000), "FA00014042000;")
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetKeyerSpeed(wpm: 28), "KS028;")
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetKeyerSpeed(wpm: 99), "KS050;", "clamped to 50")
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetKeyerSpeed(wpm: 1), "KS008;", "clamped to 8")
    }

    func testCmdSetMode() {
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetMode(rawMode: "CW", frequencyHz: 7_040_000), "MD3;")
        XCTAssertEqual(
            QRPLabsQMXDriver.cmdSetMode(rawMode: "SSB", frequencyHz: 14_200_000), "MD2;",
            "SSB above 10 MHz is USB"
        )
        XCTAssertEqual(
            QRPLabsQMXDriver.cmdSetMode(rawMode: "SSB", frequencyHz: 3_860_000), "MD1;",
            "SSB below 10 MHz is LSB"
        )
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetMode(rawMode: "USB", frequencyHz: 7_200_000), "MD2;")
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetMode(rawMode: "LSB", frequencyHz: 14_200_000), "MD1;")
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetMode(rawMode: "RTTY", frequencyHz: 14_080_000), "MD6;")
        XCTAssertEqual(QRPLabsQMXDriver.cmdSetMode(rawMode: "AM", frequencyHz: 3_885_000), "MD5;")
        XCTAssertNil(QRPLabsQMXDriver.cmdSetMode(rawMode: "FM", frequencyHz: 29_600_000), "no FM digit")
        XCTAssertNil(QRPLabsQMXDriver.cmdSetMode(rawMode: "???", frequencyHz: 14_000_000))
    }

    /// The one command that must never be built. MD8 is SWR Tune: it keys the
    /// transmitter, and nothing an operator can type into the mode field is
    /// allowed to reach it.
    func testNoAppModeEverResolvesToSWRTune() {
        let modes = ["CW", "SSB", "USB", "LSB", "RTTY", "DIGI", "AM", "FM", "PSK", "SWR", "8", "", "???"]
        let frequencies = [1_800_000, 3_860_000, 7_040_000, 14_042_000, 28_060_000, 50_313_000]
        for mode in modes {
            for hz in frequencies {
                XCTAssertNotEqual(
                    QRPLabsQMXDriver.cmdSetMode(rawMode: mode, frequencyHz: hz), "MD8;",
                    "'\(mode)' at \(hz) Hz resolved to SWR Tune"
                )
            }
        }
    }

    // MARK: KY chunking

    func testKYChunkingRespectsTheBufferLimit() {
        let text = "CQ CQ CQ TEST DE KE5CW KE5CW KE5CW PSE K"
        let cmds = QRPLabsQMXDriver.cmdKeyerText(text)
        XCTAssertGreaterThan(cmds.count, 1, "40 characters does not fit one 20-character chunk")
        for cmd in cmds {
            XCTAssertTrue(cmd.hasPrefix("KY "))
            XCTAssertTrue(cmd.hasSuffix(";"))
            XCTAssertLessThanOrEqual(cmd.dropFirst(3).dropLast(1).count, QRPLabsQMXDriver.keyerChunkLimit)
        }
    }

    /// KY appends characters to one circular buffer rather than queueing whole
    /// messages, so the chunks must concatenate back to the original text with
    /// nothing added and nothing — least of all a word space — dropped.
    func testKYChunksConcatenateBackToTheOriginalText() {
        for text in [
            "CQ CQ CQ TEST DE KE5CW KE5CW KE5CW PSE K",
            "TU 73",
            "KE5CW 599 TX TRAVIS TRAVIS",
            "W1AW/4 DE KE5CW BK",
        ] {
            let payloads = QRPLabsQMXDriver.cmdKeyerText(text).map { String($0.dropFirst(3).dropLast(1)) }
            XCTAssertEqual(payloads.joined(), text, "round trip failed for '\(text)'")
        }
    }

    func testKYSplitsAWordTooLongToFit() {
        let text = "KE5CW/PORTABLE/MOBILE/ROVER"  // 27 characters, no space to cut on
        let payloads = QRPLabsQMXDriver.cmdKeyerText(text).map { String($0.dropFirst(3).dropLast(1)) }
        XCTAssertEqual(payloads.joined(), text)
        XCTAssertEqual(payloads.first?.count, QRPLabsQMXDriver.keyerChunkLimit)
    }

    func testShortKYSingleChunk() {
        XCTAssertEqual(QRPLabsQMXDriver.cmdKeyerText("TU 73"), ["KY TU 73;"])
    }

    // MARK: Driver behaviour over a mock transport

    func testDriverStartSendsSetupAndPolls() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)
        XCTAssertTrue(mock.allWritten.contains("AI0;"), "auto-info off, so every IF is one we asked for")

        let expectation = expectation(description: "poll happens")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.4) {
            if mock.allWritten.contains("IF;") && mock.allWritten.contains("KS;") {
                expectation.fulfill()
            }
        }
        wait(for: [expectation], timeout: 2.0)
        driver.stop()
    }

    /// A carriage return switches the QMX's serial port into terminal mode and
    /// it stops answering CAT — so nothing this driver can emit may contain one.
    func testNoCommandContainsACarriageReturn() {
        var emitted = [
            QRPLabsQMXDriver.cmdPollIF,
            QRPLabsQMXDriver.cmdPollKS,
            QRPLabsQMXDriver.cmdPollKY,
            QRPLabsQMXDriver.cmdAutoInfoOff,
            QRPLabsQMXDriver.cmdAbortSending,
            QRPLabsQMXDriver.cmdSetFrequency(hz: 14_042_000),
            QRPLabsQMXDriver.cmdSetKeyerSpeed(wpm: 28),
            QRPLabsQMXDriver.cmdSetMode(rawMode: "CW", frequencyHz: 14_042_000) ?? "",
        ]
        emitted += QRPLabsQMXDriver.cmdKeyerText("CQ TEST DE KE5CW KE5CW K")

        for command in emitted {
            XCTAssertFalse(command.contains("\r"), "carriage return in '\(command)'")
            XCTAssertFalse(command.contains("\n"), "newline in '\(command)'")
            XCTAssertTrue(command.hasSuffix(";"), "'\(command)' is not ';'-terminated")
        }
    }

    /// Everything the driver actually puts on the wire during a normal session,
    /// checked the same way — the builders above are only half the story.
    func testNothingWrittenToTheTransportContainsACarriageReturn() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)
        driver.setFrequency(hz: 7_030_000)
        driver.setMode(rawMode: "CW")
        driver.setKeyerSpeed(wpm: 28)
        driver.sendInternalKeyerText("CQ TEST DE KE5CW KE5CW K")
        driver.stopInternalKeyer()
        mock.inject("KY0;")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(mock.allWritten.contains("\r"))
        XCTAssertFalse(mock.allWritten.contains("\n"))
        driver.stop()
    }

    func testDriverEmitsExactBytesForQSYModeAndSpeed() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)

        driver.setFrequency(hz: 7_030_000)
        XCTAssertTrue(mock.allWritten.contains("FA00007030000;"))

        // No IF seen yet, so setMode falls back to 14 MHz — USB territory.
        driver.setMode(rawMode: "SSB")
        XCTAssertTrue(mock.allWritten.contains("MD2;"))

        driver.setKeyerSpeed(wpm: 32)
        XCTAssertTrue(mock.allWritten.contains("KS032;"))
        driver.stop()
    }

    /// `setMode("SSB")` resolves against the frequency the radio last reported,
    /// not the one the app last asked for — the driver owns the band plan.
    func testSetModeResolvesSSBAgainstTheReportedFrequency() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        let got = expectation(description: "state delivered")
        driver.onStateChange = { _ in got.fulfill() }
        driver.start(transport: mock)
        mock.inject(ifResponse(freqHz: 3_860_000, modeDigit: "1"))
        wait(for: [got], timeout: 2.0)

        driver.setMode(rawMode: "SSB")
        XCTAssertTrue(mock.allWritten.contains("MD1;"), "80 m SSB is LSB")
        driver.stop()
    }

    func testDriverParsesFragmentedResponses() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()

        let got = expectation(description: "state delivered")
        nonisolated(unsafe) var received: RadioState?
        driver.onStateChange = { state in
            received = state
            got.fulfill()
        }
        driver.start(transport: mock)

        let full = ifResponse(freqHz: 7_030_000)
        let mid = full.index(full.startIndex, offsetBy: 9)
        mock.inject(String(full[..<mid]))
        mock.inject(String(full[mid...]))

        wait(for: [got], timeout: 2.0)
        XCTAssertEqual(received?.frequencyKHz, 7030)
        XCTAssertEqual(received?.rawMode, "CW")
        driver.stop()
    }

    func testDriverDeduplicatesUnchangedState() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        nonisolated(unsafe) var count = 0
        let first = expectation(description: "first state")
        driver.onStateChange = { _ in
            count += 1
            if count == 1 { first.fulfill() }
        }
        driver.start(transport: mock)
        mock.inject(ifResponse(freqHz: 7_030_000))
        mock.inject(ifResponse(freqHz: 7_030_000))
        mock.inject(ifResponse(freqHz: 7_030_000))
        wait(for: [first], timeout: 2.0)
        Thread.sleep(forTimeInterval: 0.1)
        XCTAssertEqual(count, 1)
        driver.stop()
    }

    /// Front-panel speed changes reach the app, and only on a change.
    func testKeyerSpeedChangesAreReportedOnce() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        nonisolated(unsafe) var reported: [Int] = []
        let got = expectation(description: "speed reported")
        got.expectedFulfillmentCount = 2
        driver.onKeyerSpeedChange = { wpm in
            reported.append(wpm)
            got.fulfill()
        }
        driver.start(transport: mock)
        mock.inject("KS022;")
        mock.inject("KS022;")
        mock.inject("KS025;")
        wait(for: [got], timeout: 2.0)
        XCTAssertEqual(reported, [22, 25])
        driver.stop()
    }

    // MARK: KY flow control

    /// The buffer is 80 characters and an overflowing message "will simply be
    /// ignored" — silently. So only the first chunk goes out unprompted; the
    /// rest wait for the radio to answer `KY;` with room to spare.
    func testKeyerTextSendsOneChunkThenWaitsForTheRadio() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)

        let text = "CQ CQ CQ TEST DE KE5CW KE5CW KE5CW PSE K"
        let chunks = QRPLabsQMXDriver.cmdKeyerText(text)
        XCTAssertGreaterThanOrEqual(chunks.count, 3, "the fixture needs at least three chunks")

        driver.sendInternalKeyerText(text)
        XCTAssertTrue(mock.allWritten.contains(chunks[0]))
        XCTAssertFalse(mock.allWritten.contains(chunks[1]), "chunk 2 must wait for a KY answer")

        // "not more than 75% full" — room for another 20 characters.
        mock.inject("KY0;")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(mock.allWritten.contains(chunks[1]))
        XCTAssertFalse(mock.allWritten.contains(chunks[2]))

        // "more than 75% full" — hold, even though more is queued.
        mock.inject("KY1;")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(mock.allWritten.contains(chunks[2]), "KY1 means the buffer is too full")

        mock.inject("KY0;")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertTrue(mock.allWritten.contains(chunks[2]))
        driver.stop()
    }

    /// KY; only earns its place on the wire while a message is still going out.
    func testKYIsPolledOnlyWhileAMessageIsQueued() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(mock.allWritten.contains("IF;"))
        XCTAssertFalse(mock.allWritten.contains("KY;"), "nothing queued — no reason to ask")

        driver.sendInternalKeyerText("CQ CQ CQ TEST DE KE5CW KE5CW KE5CW PSE K")
        let asked = expectation(description: "KY polled")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
            if mock.allWritten.contains("KY;") { asked.fulfill() }
        }
        wait(for: [asked], timeout: 2.0)
        driver.stop()
    }

    /// Abort is immediate and takes the queue with it: RX; goes out now, and no
    /// later KY answer can resurrect the rest of the message.
    func testStopInternalKeyerDropsTheQueueAndReceives() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)

        let text = "CQ CQ CQ TEST DE KE5CW KE5CW KE5CW PSE K"
        let chunks = QRPLabsQMXDriver.cmdKeyerText(text)
        driver.sendInternalKeyerText(text)
        driver.stopInternalKeyer()
        XCTAssertTrue(mock.allWritten.contains("RX;"))

        mock.inject("KY0;")
        mock.inject("KY2;")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(mock.allWritten.contains(chunks[1]), "aborted text must not resume")
        driver.stop()
    }

    /// A queue left over from one contest file must not drain into the next
    /// connection.
    func testStopClearsAPendingKeyerQueue() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)
        let chunks = QRPLabsQMXDriver.cmdKeyerText("CQ CQ CQ TEST DE KE5CW KE5CW KE5CW PSE K")
        driver.sendInternalKeyerText("CQ CQ CQ TEST DE KE5CW KE5CW KE5CW PSE K")
        driver.stop()

        let second = MockSerialTransport()
        driver.start(transport: second)
        second.inject("KY0;")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(second.allWritten.contains(chunks[1]))
        driver.stop()
    }

    /// The internal keyer is the fallback path; it still has to work, and it
    /// reaches the radio only through the two protocol members (Article 11).
    func testRadioInternalKeyerDrivesTheQMX() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)

        let keyer = RadioInternalKeyer(driver: driver, wpm: 24)
        keyer.wpm = 30
        XCTAssertTrue(mock.allWritten.contains("KS030;"))
        keyer.send("TU 73")
        XCTAssertTrue(mock.allWritten.contains("KY TU 73;"))
        keyer.abort()
        XCTAssertTrue(mock.allWritten.contains("RX;"))
        driver.stop()
    }

    /// Commands issued after `stop()` go nowhere rather than to a dead port.
    func testCommandsAfterStopAreDropped() {
        let mock = MockSerialTransport()
        let driver = QRPLabsQMXDriver()
        driver.start(transport: mock)
        driver.stop()
        let before = mock.allWritten
        driver.setFrequency(hz: 7_030_000)
        driver.setMode(rawMode: "CW")
        driver.sendInternalKeyerText("TU")
        driver.stopInternalKeyer()
        XCTAssertEqual(mock.allWritten, before)
    }

    // MARK: Registry

    func testRegistryHasTheQMX() {
        let descriptor = RadioRegistry.descriptor(id: "qrplabs-qmx")
        XCTAssertNotNil(descriptor)
        XCTAssertEqual(descriptor?.connection, .serial)
        XCTAssertEqual(descriptor?.defaultBaud, 9600)
        XCTAssertEqual(descriptor?.baudRates, [4800, 9600, 19200, 38400, 115200])
    }

    /// A QMX keys from the DTR line of its own USB port ("Key from USB DTR" in
    /// the CW menu), so direct keying is offered and is the default path.
    func testQMXOffersDirectKeying() {
        XCTAssertEqual(RadioRegistry.descriptor(id: "qrplabs-qmx")?.supportsDirectKeying, true)
    }

    /// Article 11: the keyer picker's label names the command, never the maker.
    func testKeyerLabelIsRadioNeutral() {
        let label = try? XCTUnwrap(RadioRegistry.descriptor(id: "qrplabs-qmx")?.keyerLabel)
        XCTAssertEqual(label, "Radio keyer (KY)")
    }
}

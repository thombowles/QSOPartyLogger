import XCTest
@testable import QSOPartyLogger

final class OperatingFeatureTests: XCTestCase {

    // MARK: ESM state machine

    func testESMRunMode() {
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: true, exchangeValid: false),
            .sendMessage(index: 0), "empty call → CQ"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: false, exchangeValid: false),
            .sendMessage(index: 1), "call typed → send exchange"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: false, exchangeValid: true),
            .logAndSend(index: 2), "exchange copied → log + TU"
        )
    }

    func testESMSearchPounceMode() {
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: true, exchangeValid: false),
            .sendMessage(index: 0), "answer CQ with my call"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: false, exchangeValid: false),
            .sendMessage(index: 0)
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: false, exchangeValid: true),
            .logAndSend(index: 1), "they answered → my report + log"
        )
    }

    // MARK: Per-document message sets

    func testMessageSetsPerMode() {
        let sets = MessageSets(run: ["CQ A"], searchPounce: ["B"])
        XCTAssertEqual(sets.messages(for: .run), ["CQ A"])
        XCTAssertEqual(sets.messages(for: .searchPounce), ["B"])
    }

    func testLegacyDocumentDecodesWithDefaultMessages() throws {
        // A pre-messages .qplog must load and receive the standard sets.
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        let data = try log.encoded()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "messages")
        let legacy = try JSONSerialization.data(withJSONObject: json)
        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertEqual(decoded.messages, .standard)
        XCTAssertEqual(decoded.station.callsign, "KE5CW")
    }

    func testMessagesRoundTrip() throws {
        var log = ContestLog(partyID: "alqp")
        log.messages = MessageSets(run: ["CQ AL {MYCALL}"], searchPounce: ["{MYCALL}"])
        let decoded = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(decoded.messages.run, ["CQ AL {MYCALL}"])
        XCTAssertEqual(decoded.messages.searchPounce, ["{MYCALL}"])
    }

    // MARK: Radio keyer-speed sync

    func testDriverReportsKeyerSpeedChanges() {
        let mock = MockSerialTransport()
        let driver = ElecraftK3Driver()
        nonisolated(unsafe) var reported: [Int] = []
        let first = expectation(description: "wpm reported")
        driver.onKeyerSpeedChange = { wpm in
            reported.append(wpm)
            if reported.count == 1 { first.fulfill() }
        }
        driver.start(transport: mock)
        mock.inject("KS025;")
        wait(for: [first], timeout: 2)
        mock.inject("KS025;")  // unchanged — no duplicate callback
        mock.inject("KS030;")  // knob turned
        let deadline = Date().addingTimeInterval(1)
        while reported.count < 2 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        XCTAssertEqual(reported, [25, 30])
        driver.stop()
    }

    func testPollIncludesKS() {
        XCTAssertEqual(ElecraftK3Driver.cmdPollKS, "KS;")
    }

    // MARK: Setup-completed flag

    func testNewLogNeedsSetup() {
        XCTAssertFalse(ContestLog(partyID: "ksqp").setupCompleted)
    }

    func testLegacyDocSetupInference() throws {
        // Legacy files (no setupCompleted key): configured iff callsign present.
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: log.encoded()) as? [String: Any]
        )
        json.removeValue(forKey: "setupCompleted")
        let withCall = try ContestLog.decode(from: JSONSerialization.data(withJSONObject: json))
        XCTAssertTrue(withCall.setupCompleted)

        var blank = try XCTUnwrap(
            JSONSerialization.jsonObject(with: ContestLog(partyID: "ksqp").encoded()) as? [String: Any]
        )
        blank.removeValue(forKey: "setupCompleted")
        let noCall = try ContestLog.decode(from: JSONSerialization.data(withJSONObject: blank))
        XCTAssertFalse(noCall.setupCompleted)
    }

    // MARK: iCloud mirror naming

    func testMirrorFileNameUsesFirstQSODate() {
        var log = ContestLog(partyID: "alqp")
        log.station.callsign = "KE5CW"
        log.qsos = [
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_785_078_000),  // Jul 26 2026
                call: "K4A", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "JEFF"
            ),
            QSO(
                timestampUTC: Date(timeIntervalSince1970: 1_784_991_600),  // Jul 25 2026 (earlier)
                call: "K4B", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MOBI"
            ),
        ]
        XCTAssertEqual(LogDocument.mirrorFileName(for: log), "2026-07-25 ALQP KE5CW")
    }

    // MARK: Default document naming

    func testDefaultDisplayName() {
        let date = Date(timeIntervalSince1970: 1_784_991_600)  // 2026-07-25 UTC
        XCTAssertEqual(
            LogDocument.defaultDisplayName(partyID: "ksqp", callsign: "KE5CW", date: date),
            "2026-07-25 KSQP KE5CW"
        )
        XCTAssertEqual(
            LogDocument.defaultDisplayName(partyID: "alqp", callsign: "", date: date),
            "2026-07-25 ALQP", "no trailing space without a callsign"
        )
    }
}

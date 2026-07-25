import XCTest
@testable import QSOPartyLogger

final class OperatingFeatureTests: XCTestCase {

    // MARK: ESM state machine

    func testESMRunMode() {
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: true, exchange: .empty, cursor: .call),
            .sendMessage(index: 0), "empty call → CQ"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: false, exchange: .empty, cursor: .call),
            .sendMessage(index: 1), "call typed → send his call and report"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: false, exchange: .valid, cursor: .exchange),
            .logAndSend(index: 2), "exchange copied, cursor moved on → log + TU"
        )
    }

    func testESMSearchPounceMode() {
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: true, exchange: .empty, cursor: .call),
            .sendMessage(index: 0), "answer CQ with my call"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: false, exchange: .empty, cursor: .call),
            .sendMessage(index: 0)
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: false, exchange: .valid, cursor: .exchange),
            .logAndSend(index: 1), "they answered, cursor on the exchange → my report + log"
        )
    }

    /// Hunting N4RT, whose county was copied off his QSO with someone else and
    /// typed in before ever calling him. He then works three other stations.
    /// Every Return with the cursor in the call field has to keep calling —
    /// the row holds a call and a valid exchange the whole time, and looks
    /// exactly like a completed QSO.
    func testESMKeepsCallingWhileTheCursorIsInTheCallField() {
        for _ in 1...3 {
            XCTAssertEqual(
                ESM.nextAction(
                    mode: .searchPounce, callEmpty: false, exchange: .valid, cursor: .call
                ),
                .sendMessage(index: 0),
                "S&P: prefilled exchange, cursor in the call field → send my call, never log"
            )
        }
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: false, exchange: .valid, cursor: .call),
            .sendMessage(index: 1),
            "Run: same rule — the call field sends his call and report, never logs"
        )
    }

    /// Moving to the exchange is the operator saying the contact happened.
    /// Only then does the same row log.
    func testESMLogsOnlyOnceTheCursorHasLeftTheCallField() {
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: false, exchange: .valid, cursor: .exchange),
            .logAndSend(index: 1)
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: false, exchange: .empty, cursor: .exchange),
            .sendMessage(index: 0),
            "off the call field but nothing copied yet → still calling"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: false, exchange: .empty, cursor: .exchange),
            .sendMessage(index: 1)
        )
    }

    /// Run's CQ outranks the cursor rule: an empty call field cannot log, and
    /// cannot send a report to nobody.
    func testESMCQOutranksEverything() {
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: true, exchange: .valid, cursor: .exchange),
            .sendMessage(index: 0)
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: true, exchange: .valid, cursor: .exchange),
            .sendMessage(index: 0)
        )
    }

    /// Copying his county and getting something that matches nothing: he is
    /// already talking to you, so Return asks him to repeat rather than
    /// calling him again.
    func testESMAsksAgainForAnUnmatchedExchange() {
        for mode in OperatingMode.allCases {
            XCTAssertEqual(
                ESM.nextAction(mode: mode, callEmpty: false, exchange: .unmatched, cursor: .exchange),
                .sendMessage(index: ESM.againIndex),
                "\(mode): garbled copy in the exchange field → AGN?"
            )
        }
    }

    /// AGN? is the exchange field's answer only. Elsewhere an unmatched
    /// exchange is just an incomplete contact, and Return goes on calling.
    func testESMAsksAgainOnlyFromTheExchangeField() {
        for mode in OperatingMode.allCases {
            for cursor in [ESM.Cursor.call, .other] {
                XCTAssertNotEqual(
                    ESM.nextAction(mode: mode, callEmpty: false, exchange: .unmatched, cursor: cursor),
                    .sendMessage(index: ESM.againIndex),
                    "\(mode) from \(cursor): not the exchange field, so not AGN?"
                )
            }
        }
    }

    /// An empty exchange is not a bad copy — nothing has been heard yet, so
    /// there is nothing to ask him to repeat.
    func testESMEmptyExchangeDoesNotAskAgain() {
        XCTAssertEqual(
            ESM.nextAction(mode: .searchPounce, callEmpty: false, exchange: .empty, cursor: .exchange),
            .sendMessage(index: 0), "S&P: still calling"
        )
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: false, exchange: .empty, cursor: .exchange),
            .sendMessage(index: 1), "Run: still sending his report"
        )
    }

    /// No callsign means no contact — there is nobody to ask.
    func testESMDoesNotAskAgainWithoutACallsign() {
        XCTAssertEqual(
            ESM.nextAction(mode: .run, callEmpty: true, exchange: .unmatched, cursor: .exchange),
            .sendMessage(index: 0)
        )
    }

    /// The messages row highlights whatever Return would key, so the two are
    /// read from the same action rather than computed twice.
    func testESMActionReportsItsMessageIndex() {
        XCTAssertEqual(ESM.Action.sendMessage(index: 0).messageIndex, 0)
        XCTAssertEqual(ESM.Action.logAndSend(index: 2).messageIndex, 2)
        XCTAssertNil(ESM.Action.none.messageIndex)
    }

    /// Nothing in the row's contents separates "about to call him" from "just
    /// worked him" when the exchange was prefilled — only the cursor does. So
    /// for every state of the row, the call field sends and the exchange logs.
    func testESMCursorAloneDecidesWhetherTheSameRowLogs() {
        for exchange in [ESM.ExchangeState.valid, .empty, .unmatched] {
            for mode in OperatingMode.allCases {
                let inCall = ESM.nextAction(
                    mode: mode, callEmpty: false, exchange: exchange, cursor: .call
                )
                if case .logAndSend = inCall {
                    XCTFail("\(mode) with the cursor in the call field must never log")
                }
            }
        }
    }

    /// ESM.againIndex has to be the slot the default sets actually put AGN? in,
    /// or Return asks him to repeat by keying something else entirely.
    func testAgainIndexIsTheAgainMessageInBothDefaultSets() {
        XCTAssertEqual(MessageSets.defaultRun[ESM.againIndex], "AGN?")
        XCTAssertEqual(MessageSets.defaultSearchPounce[ESM.againIndex], "AGN?")
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

    // MARK: RST pre-fill

    func testClearForNextContactPrefillsDefaultRST() {
        let entry = EntryState()
        entry.call = "W1AW"
        entry.rstSent = "579"
        entry.rstRcvd = "449"
        entry.exchange = "DAL"
        entry.clearForNextContact(modeClass: .cw)
        XCTAssertEqual(entry.call, "")
        XCTAssertEqual(entry.exchange, "")
        XCTAssertEqual(entry.rstSent, "599")
        XCTAssertEqual(entry.rstRcvd, "599")

        entry.clearForNextContact(modeClass: .phone)
        XCTAssertEqual(entry.rstSent, "59")
        XCTAssertEqual(entry.rstRcvd, "59")
    }

    func testSyncRSTDefaultsFollowsModeChange() {
        let entry = EntryState()
        entry.clearForNextContact(modeClass: .cw)
        entry.syncRSTDefaults(modeClass: .phone)
        XCTAssertEqual(entry.rstSent, "59")
        XCTAssertEqual(entry.rstRcvd, "59")
        entry.syncRSTDefaults(modeClass: .cw)
        XCTAssertEqual(entry.rstSent, "599")
        XCTAssertEqual(entry.rstRcvd, "599")
    }

    func testSyncRSTDefaultsPreservesUserTypedReports() {
        let entry = EntryState()
        entry.rstSent = "579"
        entry.rstRcvd = "339"
        entry.syncRSTDefaults(modeClass: .phone)
        XCTAssertEqual(entry.rstSent, "579")
        XCTAssertEqual(entry.rstRcvd, "339")
    }

    // MARK: Cut numbers for CW macros

    func testCutNumbersAppliesToRSTOnly() {
        let out = AppSettings.expandMacros(
            "{CALL} {RST} {EXCH} DE {MYCALL}",
            myCall: "KE5CW", call: "N9TF", rst: "599", exchange: "DAL",
            cutNumbers: true
        )
        XCTAssertEqual(out, "N9TF 5NN DAL DE KE5CW", "digits in callsigns must never be cut")
    }

    func testCutNumbersMapsNineAndZero() {
        XCTAssertEqual(AppSettings.applyCutNumbers("590"), "5NT")
        XCTAssertEqual(AppSettings.applyCutNumbers("579"), "57N")
    }

    func testCutNumbersOffByDefault() {
        let out = AppSettings.expandMacros(
            "{RST}", myCall: "KE5CW", call: "W1AW", rst: "599", exchange: ""
        )
        XCTAssertEqual(out, "599")
    }

    // MARK: RadioBar flow-layout row packing

    func testFlowLayoutPacksRowsByWidth() {
        let widths: [CGFloat] = [100, 100, 100]
        XCTAssertEqual(
            FlowLayout.packRows(itemWidths: widths, containerWidth: .infinity, spacing: 8),
            [[0, 1, 2]]
        )
        // 100 + 8 + 100 fits in 250; the third item would overflow → next row.
        XCTAssertEqual(
            FlowLayout.packRows(itemWidths: widths, containerWidth: 250, spacing: 8),
            [[0, 1], [2]]
        )
        // Exact fit: 100+8+100+8+100 = 316.
        XCTAssertEqual(
            FlowLayout.packRows(itemWidths: widths, containerWidth: 316, spacing: 8),
            [[0, 1, 2]]
        )
        // An oversized item still occupies its own row.
        XCTAssertEqual(
            FlowLayout.packRows(itemWidths: [300], containerWidth: 250, spacing: 8),
            [[0]]
        )
    }

    // MARK: Band/mode QSO breakdown

    func testBandModeCounts() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        var log = ContestLog(partyID: "ksqp")
        log.myLocation = .outOfState(location: "TX")
        let t = Date(timeIntervalSince1970: 1_785_078_000)
        func qso(_ call: String, _ band: Band, _ mode: ModeClass, offset: TimeInterval) -> QSO {
            QSO(
                timestampUTC: t.addingTimeInterval(offset),
                call: call, band: band, modeClass: mode,
                rawMode: mode == .cw ? "CW" : "SSB",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "RIL"
            )
        }
        log.qsos = [
            qso("K0A", .m40, .cw, offset: 0),
            qso("K0B", .m40, .cw, offset: 60),
            qso("K0B", .m40, .cw, offset: 120),  // exact dupe — not counted
            qso("K0C", .m20, .phone, offset: 180),
        ]
        let counts = ScoreEngine.bandModeCounts(log: log, party: party)
        XCTAssertEqual(counts[.m40]?[.cw], 2)
        XCTAssertEqual(counts[.m20]?[.phone], 1)
        XCTAssertNil(counts[.m80])
        XCTAssertNil(counts[.m40]?[.phone])
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

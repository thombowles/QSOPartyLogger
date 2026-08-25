import XCTest
@testable import QSOPartyLogger

/// What the radio actually keys, driven through the real sequences.
///
/// This suite exists because on 2026-07-25 two bugs in exactly this code
/// shipped through eight review rounds: ESM in Search & Pounce keyed the *next*
/// contact's QSO number, and the first contact of a new CQP log keyed no number
/// at all. Both were unreachable by any test, because the code lived inside a
/// SwiftUI `View`. Deleting the QSO number from the air entirely
/// (`serial: entry.serialSent` → `serial: ""`) left all 643 tests of the time
/// green.
///
/// The two acceptance tests are marked. Each has been confirmed to fail against
/// the pre-`7651adc` behaviour it guards; see
/// `docs/superpowers/specs/2026-07-25-keying-path-seam-design.md`.
///
/// CQP is the party to drive these with: its exchange carries a QSO number and
/// *no* signal report, so the number is the whole message and a wrong one is
/// unmissable. Out-of-state TX makes `{EXCH}` a single stable token.
@MainActor
final class EntryFlowTests: XCTestCase {

    // MARK: Fixtures

    /// A CQP log, out-of-state TX, set up and ready to work someone — the state
    /// the app is in after Contest Setup.
    func cqpDocument(mode: OperatingMode = .searchPounce) -> LogDocument {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "cqp",
            undoManager: nil
        )
        doc.log.operatingMode = mode
        return doc
    }

    /// CW, radio connected, ESM on — the conditions ESM runs under.
    func context(
        cursor: ESM.Cursor = .exchange,
        esm: Bool = true,
        connected: Bool = true,
        modeClass: ModeClass = .cw,
        cutNumbers: Bool = false,
        cutOne: Bool = false
    ) -> EntryFlow.Context {
        EntryFlow.Context(
            band: .m20,
            modeClass: modeClass,
            rawMode: modeClass == .cw ? "CW" : "SSB",
            freqKHz: 14_042,
            radioConnected: connected,
            cursor: cursor,
            keying: KeyingSettings(esmEnabled: esm, cutNumbers: cutNumbers, cutOne: cutOne)
        )
    }

    /// A contact copied and ready for the Return that logs it.
    func readyToLog(_ flow: EntryFlow, call: String = "W6ABC", their: String = "SCLA") {
        flow.entry.call = call
        flow.entry.exchange = their
        flow.revalidate(context())
    }

    // MARK: Acceptance — bug 1 (2026-07-25)

    /// **The number on the air is the number in the log.**
    ///
    /// Pre-`7651adc`, `returnPressed` logged before it expanded. Logging
    /// advances the entry to the next number, so the log recorded n while the
    /// radio sent n+1 — every contact, CQP and PAQP, silently. Both stations
    /// would be removed from each other's logs.
    func testSearchPounceReturnKeysTheNumberItJustLogged() throws {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow)
        XCTAssertEqual(flow.entry.serialSent, "1", "precondition: first contact")

        let outcome = flow.returnPressed(context(), undoManager: nil)

        guard case .logged(let rows, .cw(let keyed)) = outcome else {
            return XCTFail("expected the contact to be logged with CW, got \(outcome)")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].serialSent, 1, "the number written to the log")
        XCTAssertEqual(keyed, "1 TX", "the number put on the air — pre-fix: \"2 TX\"")

        // Stated as the invariant rather than two literals, because the
        // literals are what a future edit would update in lockstep while
        // breaking the thing that matters.
        let logged = try XCTUnwrap(rows[0].serialSent)
        XCTAssertTrue(
            keyed.split(separator: " ").contains(Substring(String(logged))),
            "the QSO number keyed (\(keyed)) must be the one logged (\(logged))"
        )
    }

    /// The same guarantee on the next contact, where the log is no longer
    /// empty — n+1 and n are both plausible-looking numbers by then.
    func testTheGuaranteeHoldsOnLaterContacts() throws {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow, call: "W6ABC", their: "SCLA")
        _ = flow.returnPressed(context(), undoManager: nil)

        readyToLog(flow, call: "K6XYZ", their: "ALAM")
        let outcome = flow.returnPressed(context(), undoManager: nil)

        guard case .logged(let rows, .cw(let keyed)) = outcome else {
            return XCTFail("expected the contact to be logged with CW, got \(outcome)")
        }
        XCTAssertEqual(rows[0].serialSent, 2)
        XCTAssertEqual(keyed, "2 TX", "pre-fix: \"3 TX\"")
    }

    // MARK: Acceptance — bug 2 (2026-07-25)

    /// **The first contact of a new CQP log sends number 1.**
    ///
    /// A new document is `ksqp` — which exchanges no QSO number — until Contest
    /// Setup runs. Pre-`7651adc` the entry was seeded once, while the document
    /// was still the placeholder, and nothing re-seeded it when the real party
    /// arrived: the first contact keyed a blank where the number should be,
    /// while the logged row (which falls back to `nextSerial`) looked correct.
    ///
    /// No re-seed call appears in this test on purpose. The number follows the
    /// log, so there is no lifecycle moment left for a caller to miss.
    func testFirstContactOfANewCQPLogKeysNumberOne() {
        let doc = LogDocument()
        XCTAssertEqual(doc.log.partyID, "ksqp", "precondition: the placeholder party")

        let flow = EntryFlow(document: doc)
        flow.onAppear(context())
        XCTAssertEqual(flow.entry.serialSent, "", "ksqp exchanges no number")

        // Contest Setup picks the real party.
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "cqp",
            undoManager: nil
        )
        doc.log.operatingMode = .searchPounce
        flow.entry.call = "W6ABC"

        XCTAssertEqual(flow.entry.serialSent, "1")
        XCTAssertEqual(
            flow.expandedMessage(at: 1, context: context()),
            "1 TX",
            "pre-fix: \"TX\" — the number never went out"
        )
    }

    /// The converse: a party that exchanges no number must not grow one.
    func testAPartyWithoutANumberKeysNone() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        doc.log.operatingMode = .searchPounce
        let flow = EntryFlow(document: doc)
        flow.entry.call = "W6ABC"

        XCTAssertEqual(flow.entry.serialSent, "")
        XCTAssertEqual(flow.expandedMessage(at: 1, context: context()), "599 TX")
    }

    // MARK: The mutants that survived the 2026-07-25 suite

    /// `serial: entry.serialSent` → `serial: ""` deletes the feature the
    /// branch existed for. It left all 643 tests green.
    func testTheQSONumberReachesTheAir() {
        let flow = EntryFlow(document: cqpDocument(mode: .run))
        flow.entry.call = "W6ABC"
        XCTAssertEqual(flow.expandedMessage(at: 1, context: context()), "W6ABC 1 TX")
    }

    /// `cutOne: settings.cwCutNumberOne` → `cutOne: settings.cwCutNumbers`
    /// also left all 643 green. Cutting 1 → A is the less universal habit and
    /// is a separate switch: with cut numbers on and cut-one off, 1 stays 1.
    func testCutOneIsASeparateSwitchFromCutNumbers() {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        flow.entry.call = "W6ABC"

        XCTAssertEqual(
            flow.expandedMessage(at: 1, context: context(cutNumbers: true, cutOne: false)),
            "1 TX",
            "cut numbers alone must not turn 1 into A"
        )
        XCTAssertEqual(
            flow.expandedMessage(at: 1, context: context(cutNumbers: true, cutOne: true)),
            "A TX"
        )
        XCTAssertEqual(
            flow.expandedMessage(at: 1, context: context(cutNumbers: false, cutOne: true)),
            "1 TX",
            "cut-one is meaningless with cut numbers off"
        )
    }

    /// Cut numbers are a CW habit. On phone the macro expands plainly.
    func testCutNumbersDoNotApplyOnPhone() {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        flow.entry.call = "W6ABC"
        for _ in 0..<9 { appendFiller(flow) }

        XCTAssertEqual(flow.entry.serialSent, "10", "precondition")
        XCTAssertEqual(
            flow.expandedMessage(
                at: 1,
                context: context(modeClass: .phone, cutNumbers: true, cutOne: true)
            ),
            "10 TX"
        )
    }

    // MARK: A number the operator typed

    /// The field stays editable so a mis-sent number is recorded as it actually
    /// went out. What was typed must reach both the log and the air.
    func testATypedNumberGoesToBothTheLogAndTheAir() throws {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow)
        flow.entry.serialSent = "17"

        let outcome = flow.returnPressed(context(), undoManager: nil)
        guard case .logged(let rows, .cw(let keyed)) = outcome else {
            return XCTFail("expected the contact to be logged with CW, got \(outcome)")
        }
        XCTAssertEqual(rows[0].serialSent, 17)
        XCTAssertEqual(keyed, "17 TX")
    }

    /// …and it belongs to that contact alone. The next one is back on the log's
    /// own numbering, which the typed number has moved.
    func testTheNextContactIsBackOnTheLogsNumbering() {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow)
        flow.entry.serialSent = "17"
        _ = flow.returnPressed(context(), undoManager: nil)

        XCTAssertFalse(flow.entry.hasSerialOverride)
        XCTAssertEqual(flow.entry.serialSent, "18")
    }

    // MARK: When ESM does and does not drive Return

    /// ESM only drives Return on CW with the radio connected. Otherwise Return
    /// is a plain log key and nothing goes on the air.
    func testReturnOnlyKeysUnderESMOnCWWithAConnectedRadio() {
        for ctx in [
            context(esm: false),
            context(connected: false),
            context(modeClass: .phone),
        ] {
            let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
            readyToLog(flow)
            let outcome = flow.returnPressed(ctx, undoManager: nil)

            guard case .logged(let rows, let transmission) = outcome else {
                return XCTFail("expected a plain log, got \(outcome)")
            }
            XCTAssertEqual(rows.count, 1, "the contact is still logged")
            XCTAssertEqual(transmission, .silent, "but nothing is keyed")
        }
    }

    /// The call field never logs, however complete the row looks — it calls.
    /// In S&P that is F1, my own call.
    func testTheCallFieldCallsInsteadOfLogging() {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow)

        let outcome = flow.returnPressed(context(cursor: .call), undoManager: nil)
        XCTAssertEqual(outcome, .send(index: 0, transmission: .cw("KE5CW")))
        XCTAssertTrue(flow.document.log.qsos.isEmpty, "nothing was logged")
    }

    /// An exchange that matches no county asks him to repeat rather than
    /// logging a guess.
    func testAnUnmatchedExchangeAsksForARepeat() {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow, their: "ZZZZ")

        let outcome = flow.returnPressed(context(cursor: .exchange), undoManager: nil)
        XCTAssertEqual(outcome, .send(index: ESM.againIndex, transmission: .cw("AGN?")))
        XCTAssertTrue(flow.document.log.qsos.isEmpty)
    }

    // MARK: Return's other jobs

    /// "14025", "40M", "CW" in the call field is a QSY, not a contact.
    func testAQSYCommandInTheCallFieldTunesInsteadOfLogging() {
        let flow = EntryFlow(document: cqpDocument())
        flow.entry.call = "14025"

        let outcome = flow.returnPressed(context(), undoManager: nil)
        XCTAssertEqual(outcome, .qsy(.frequency(kHz: 14025)))
        XCTAssertEqual(flow.entry.call, "", "the command is consumed, not logged")
        XCTAssertTrue(flow.document.log.qsos.isEmpty)
    }

    /// A log whose station has no location cannot produce a submittable row.
    /// Return asks for Contest Setup rather than logging a blank exchange.
    func testAContactWithNoLocationAsksForSetup() {
        let doc = LogDocument()
        doc.log.partyID = "cqp"
        doc.log.myLocation = .outOfState(location: "")
        doc.log.station = StationProfile(callsign: "KE5CW")
        doc.log.messages = MessageSets.defaults(for: PartyCatalog.party(id: "cqp"))
        doc.log.operatingMode = .searchPounce

        let flow = EntryFlow(document: doc)
        readyToLog(flow)
        XCTAssertEqual(flow.returnPressed(context(), undoManager: nil), .needsSetup)
        XCTAssertTrue(doc.log.qsos.isEmpty)
    }

    /// An empty F-key slot keys nothing rather than an empty transmission.
    func testAnEmptySlotKeysNothing() {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.messages.searchPounce[0] = ""
        let flow = EntryFlow(document: doc)

        XCTAssertEqual(flow.expandedMessage(at: 0, context: context()), "")
        XCTAssertEqual(flow.returnPressed(context(cursor: .call), undoManager: nil), .nothing)
    }

    /// The messages row highlights what Return will send next, and reads the
    /// same decision Return does — the two can never disagree.
    func testThePendingHighlightMatchesWhatReturnWouldSend() {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow)

        XCTAssertEqual(flow.pendingMessageIndex(context(cursor: .call)), 0)
        XCTAssertEqual(flow.pendingMessageIndex(context(cursor: .exchange)), 1)
        XCTAssertNil(flow.pendingMessageIndex(context(esm: false)),
                     "no highlight when ESM is not driving Return")
    }

    // MARK: County lines

    /// A county-line contact expands into several rows that share one number,
    /// and the message goes out once carrying that number.
    func testACountyLineContactKeysOneNumberForAllItsRows() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "W6ABC"),
            location: .inState(counties: ["SCLA", "ALAM"]),
            partyID: "cqp",
            undoManager: nil
        )
        doc.log.operatingMode = .run
        let flow = EntryFlow(document: doc)
        flow.entry.call = "K5XYZ"
        flow.entry.exchange = "TX"
        flow.revalidate(context())

        let outcome = flow.returnPressed(context(), undoManager: nil)
        guard case .logged(let rows, .cw(let keyed)) = outcome else {
            return XCTFail("expected the contact to be logged with CW, got \(outcome)")
        }
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.compactMap(\.serialSent)), [1],
                       "one contact, one QSO number")
        XCTAssertEqual(keyed, "TU W6ABC")
        XCTAssertEqual(flow.entry.serialSent, "2",
                       "the next number, not one per row")
    }

    // MARK: The party the flow reads

    /// The party lookup is cached to keep `PartyCatalog` off the keystroke
    /// path, so a party change has to invalidate it.
    func testThePartyFollowsTheDocument() {
        let doc = LogDocument()
        let flow = EntryFlow(document: doc)
        XCTAssertEqual(flow.party?.id, "ksqp")
        XCTAssertNil(flow.nextSerialIfUsed)

        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "cqp",
            undoManager: nil
        )
        XCTAssertEqual(flow.party?.id, "cqp")
        XCTAssertEqual(flow.nextSerialIfUsed, 1)
    }

    // MARK: Helpers

    /// Log a throwaway contact to advance the log's numbering.
    private func appendFiller(_ flow: EntryFlow) {
        let n = flow.document.log.nextSerial
        flow.document.append(
            qsos: [
                QSO(
                    timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + Double(n) * 60),
                    call: "N0FILL\(n)", band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "", rstRcvd: "", serialSent: n, serialRcvd: n,
                    myLoc: "TX", theirLoc: "SCLA"
                )
            ],
            undoManager: nil
        )
    }

    // MARK: Exchange prefill

    /// A KSQP log, out-of-state TX — the seat that receives Kansas counties.
    func ksqpDocument() -> LogDocument {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        return doc
    }

    /// The same, with one contact already in the log.
    func ksqpDocumentWorking(_ call: String, as loc: String) -> LogDocument {
        let doc = ksqpDocument()
        doc.append(
            qsos: [
                QSO(
                    call: call, band: .m40, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: loc
                )
            ],
            undoManager: nil
        )
        return doc
    }

    func testTypingAKnownCallFillsTheExchange() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JOH"))
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "JOH")
        XCTAssertTrue(flow.entry.exchangeIsAutoFilled)
    }

    func testAutoFillNeverOverwritesTypedText() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JOH"))
        flow.entry.exchangeTyped = "MIA"
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "MIA", "what the operator typed stands")
        XCTAssertFalse(flow.entry.exchangeIsAutoFilled)
    }

    /// Auto-filled text is the app's, so the app takes it back the moment the
    /// call it belonged to is no longer in the field.
    func testAutoFillWithdrawsWhenTheCallStopsMatching() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JOH"))
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "JOH")

        flow.entry.call = "K5NAX"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "", "the fill belonged to K5NA")
    }

    func testUnknownCallFillsNothing() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JOH"))
        flow.entry.call = "W1ABC"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "")
    }

    // MARK: Pending exchanges across spot moves

    /// The niggle itself: a county copied for a station who never came back
    /// must not follow you to the next spot and get logged against him.
    func testMovingToAnotherStationClearsWhatWasCopied() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JOH"
        flow.entry.serialRcvd = "42"

        flow.stationChanged(to: "W0BH", context())

        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertEqual(flow.entry.exchange, "")
        XCTAssertEqual(flow.entry.serialRcvd, "")
    }

    func testComingBackRestoresWhatWasCopied() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JOH"
        flow.entry.serialRcvd = "42"

        flow.stationChanged(to: "W0BH", context())
        flow.stationChanged(to: "K5NA", context())

        XCTAssertEqual(flow.entry.exchange, "JOH")
        XCTAssertEqual(flow.entry.serialRcvd, "42")
        XCTAssertFalse(
            flow.entry.exchangeIsAutoFilled,
            "restored text is the operator's, not the app's"
        )
    }

    /// The restore hangs off the call, not off the navigation.
    func testTypingTheCallBackRestoresWhatWasCopied() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JOH"
        flow.stationChanged(to: "W0BH", context())

        flow.entry.call = "K5NA"
        flow.callChanged(context())

        XCTAssertEqual(flow.entry.exchange, "JOH")
    }

    /// Auto-filled text regenerates from the log, so stashing it would only
    /// make a typed-looking copy of something the app already knows.
    func testAutoFilledTextIsNeverStashed() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JOH"))
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertTrue(flow.entry.exchangeIsAutoFilled)

        flow.stationChanged(to: "W0BH", context())
        XCTAssertNil(flow.entry.pendingExchanges["K5NA"])
    }

    func testLoggingAContactDropsItsPendingExchange() {
        let doc = ksqpDocument()
        let flow = EntryFlow(document: doc)
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JOH"
        flow.stationChanged(to: "W0BH", context())
        XCTAssertNotNil(flow.entry.pendingExchanges["K5NA"])

        flow.stationChanged(to: "K5NA", context())
        _ = flow.logContact(context(), undoManager: nil)

        XCTAssertEqual(doc.log.qsos.count, 1)
        XCTAssertNil(
            flow.entry.pendingExchanges["K5NA"],
            "he is in the log now — there is nothing pending about him"
        )
    }

    func testAnEmptyExchangeIsNotStashed() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.stationChanged(to: "W0BH", context())
        XCTAssertTrue(flow.entry.pendingExchanges.isEmpty)
    }

    // MARK: POTA

    func testActivationStampsMyParksOnEveryLoggedRow() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315", "US-4571"]
        let flow = EntryFlow(document: doc)
        readyToLog(flow)
        let outcome = flow.returnPressed(context(), undoManager: nil)
        guard case .logged(let rows, _) = outcome else {
            return XCTFail("expected the contact to be logged, got \(outcome)")
        }
        XCTAssertEqual(rows.map(\.myPotaRefs), [["US-3315", "US-4571"]])
        XCTAssertNil(rows[0].theirPotaRefs)
    }

    func testNoActivationStampsNil() throws {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        readyToLog(flow)
        let outcome = flow.returnPressed(context(), undoManager: nil)
        guard case .logged(let rows, _) = outcome else {
            return XCTFail("expected the contact to be logged, got \(outcome)")
        }
        XCTAssertNil(rows[0].myPotaRefs)
    }

    func testTheirParkIsParsedNormalizedAndCleared() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315"]
        let flow = EntryFlow(document: doc)
        readyToLog(flow)
        flow.entry.theirParkTyped = "us-0088, us-0119"
        let outcome = flow.returnPressed(context(), undoManager: nil)
        guard case .logged(let rows, _) = outcome else {
            return XCTFail("expected the contact to be logged, got \(outcome)")
        }
        XCTAssertEqual(rows[0].theirPotaRefs, ["US-0088", "US-0119"])
        XCTAssertEqual(flow.entry.theirParkTyped, "", "cleared for the next contact")
    }

    /// An unparseable park refuses to log, exactly as an unreadable member
    /// element does — the reference decides P2P credit, and a mis-keyed one
    /// must not be logged in silence. Nothing is keyed either: ESM's
    /// `logAndSend` passes a non-`logged` outcome straight through, so no
    /// report goes out for a contact that did not happen.
    func testMalformedTheirParkRefusesToLog() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315"]
        let flow = EntryFlow(document: doc)
        readyToLog(flow)
        flow.entry.theirParkTyped = "USA-331"
        let outcome = flow.returnPressed(context(), undoManager: nil)
        guard case .nothing = outcome else {
            return XCTFail("must not log a garbled park reference, got \(outcome)")
        }
        XCTAssertTrue(doc.log.qsos.isEmpty)
        XCTAssertTrue(flow.entry.invalidTheirPark())
    }

    /// Working the same activator again on another band: the park he gave
    /// an hour ago comes back offered, so it is not re-typed every time.
    func testSecondBandP2PContactPrefillsTheirPark() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315"]
        let flow = EntryFlow(document: doc)
        readyToLog(flow)
        flow.entry.theirParkTyped = "US-0088"
        guard case .logged = flow.returnPressed(context(), undoManager: nil) else {
            return XCTFail("should log")
        }
        XCTAssertEqual(flow.entry.theirParkTyped, "", "precondition: cleared after logging")

        flow.entry.call = "W6ABC"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.theirParkTyped, "US-0088")
    }

    /// A park is a same-day fact about where someone is sitting, so it is
    /// only ever offered from this log — never from the archive of past
    /// contests the exchange prefill draws on.
    func testAParkIsNeverOfferedForAStationThisLogHasNotWorked() {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315"]
        let flow = EntryFlow(document: doc)
        flow.entry.call = "K6XYZ"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.theirParkTyped, "")
    }

    // MARK: Voice

    private func phoneContext(memories: Int, cursor: ESM.Cursor = .call) -> EntryFlow.Context {
        var keying = KeyingSettings()
        keying.esmEnabled = true
        return EntryFlow.Context(
            modeClass: .phone,
            rawMode: "SSB",
            radioConnected: true,
            cursor: cursor,
            keying: keying,
            voiceMemoryCount: memories
        )
    }

    /// A radio with no memories leaves Return a plain log key, exactly as a
    /// disconnected radio does.
    func testESMDoesNotDriveReturnOnPhoneWithoutMemories() {
        let flow = EntryFlow(document: LogDocument())
        XCTAssertFalse(flow.esmDrivesReturn(phoneContext(memories: 0)))
    }

    func testESMDrivesReturnOnPhoneWithMemories() {
        let flow = EntryFlow(document: LogDocument())
        XCTAssertTrue(flow.esmDrivesReturn(phoneContext(memories: 8)))
    }

    /// Digital never drives ESM in either mode class.
    func testESMNeverDrivesReturnOnDigital() {
        var keying = KeyingSettings()
        keying.esmEnabled = true
        let context = EntryFlow.Context(
            modeClass: .digital, rawMode: "RTTY", radioConnected: true,
            cursor: .call, keying: keying, voiceMemoryCount: 8
        )
        XCTAssertFalse(EntryFlow(document: LogDocument()).esmDrivesReturn(context))
    }

    /// The same F-key indexes as CW — ESM.swift is untouched by this feature.
    ///
    /// A fresh `LogDocument()` derives Search & Pounce (its default location is
    /// out-of-state), so Run is set explicitly — the mapping under test here is
    /// `phoneRun`, not `phoneSearchPounce`.
    func testPhoneTransmissionUsesTheMappedMemoryAndItsCaption() {
        let document = LogDocument()
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        // Run default: F1 → M1, named "CQ".
        XCTAssertEqual(
            flow.transmission(at: 0, context: phoneContext(memories: 8)),
            .voice(memory: 1, caption: "M1 CQ")
        )
    }

    func testUnassignedPhoneKeyIsSilent() {
        let document = LogDocument()
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        // Run default: F4 is unassigned.
        XCTAssertEqual(flow.transmission(at: 3, context: phoneContext(memories: 8)), .silent)
    }

    /// The behaviour the S&P phone default relies on: Return on an unassigned
    /// key does nothing — it does not log, and it does not transmit. The call
    /// field never logs, so there is nothing else for it to do while the
    /// operator says their own callsign.
    func testReturnOnAnUnassignedPhoneKeyDoesNothing() {
        let document = LogDocument()          // derives S&P for an out-of-state log
        let flow = EntryFlow(document: document)
        flow.entry.call = "W6ABC"

        let outcome = flow.returnPressed(phoneContext(memories: 8), undoManager: nil)

        XCTAssertEqual(outcome, .nothing)
        XCTAssertTrue(document.log.qsos.isEmpty, "the call field must never log")
    }

    /// A mapping built for an 8-memory radio must not fire memory 5 at a radio
    /// that has two. Silence, not a clamp onto a neighbouring recording.
    func testPhoneKeyBeyondTheRadiosMemoryCountIsSilent() {
        let document = LogDocument()
        document.log.operatingMode = .run
        var sets = document.log.messages
        sets.phoneRun = [5, nil, nil, nil, nil, nil, nil, nil]
        document.updateMessages(sets, undoManager: nil)

        let flow = EntryFlow(document: document)
        XCTAssertEqual(flow.transmission(at: 0, context: phoneContext(memories: 2)), .silent)
        XCTAssertEqual(
            flow.transmission(at: 0, context: phoneContext(memories: 8)),
            .voice(memory: 5, caption: "M5")
        )
    }

    func testCWTransmissionStillCarriesExpandedText() {
        let document = LogDocument()
        // Run, explicitly: a fresh out-of-state log opens in S&P, where F1 is
        // the bare `{MYCALL}` — empty until some *other* test has saved a
        // profile into the store, which is how this passed by order for a
        // while. Run's F1 carries text of its own.
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.entry.call = "W6ABC"
        var keying = KeyingSettings()
        keying.esmEnabled = true
        let context = EntryFlow.Context(
            modeClass: .cw, rawMode: "CW", radioConnected: true,
            cursor: .call, keying: keying
        )
        guard case .cw(let text) = flow.transmission(at: 0, context: context) else {
            return XCTFail("expected CW")
        }
        XCTAssertFalse(text.isEmpty)
    }

    // MARK: Recordings on this Mac

    /// Phone, ESM on, the recordings source — ready unless a test says otherwise.
    private func recordingsContext(ready: Bool = true) -> EntryFlow.Context {
        var keying = KeyingSettings()
        keying.esmEnabled = true
        return EntryFlow.Context(
            modeClass: .phone, rawMode: "USB", radioConnected: true,
            cursor: .call, keying: keying, voiceMemoryCount: 0,
            phoneSource: .recordings(ready: ready)
        )
    }

    private let clip = VoiceAudio(sampleRate: 48_000, samples: [0.1, 0.2, 0.3])

    func testRecordingsSourcePlaysTheMappedRecording() {
        let document = LogDocument()
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [1: clip]
        // Run default: F1 → M1, named "CQ".
        XCTAssertEqual(
            flow.transmission(at: 0, context: recordingsContext()),
            .recording(memory: 1, audio: clip, caption: "M1 CQ")
        )
    }

    func testUnrecordedMemoryIsSilentUnderRecordings() {
        let document = LogDocument()
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [2: clip]                 // F1 → M1 has nothing
        XCTAssertEqual(flow.transmission(at: 0, context: recordingsContext()), .silent)
        XCTAssertEqual(
            flow.transmission(at: 1, context: recordingsContext()),
            .recording(memory: 2, audio: clip, caption: "M2 Exch")
        )
    }

    /// The operator chose recordings; the path is not set up. The key stays
    /// silent — it must not quietly play the radio's own memory 1 instead,
    /// which would be a different recording than the one they expect.
    func testUnreadyRecordingsSourceIsSilentAndNeverFallsBackToTheRadio() {
        let document = LogDocument()
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [1: clip]
        var context = recordingsContext(ready: false)
        context.voiceMemoryCount = 8                       // the radio has memories, too
        XCTAssertEqual(flow.transmission(at: 0, context: context), .silent)
        XCTAssertFalse(flow.esmDrivesReturn(context))
    }

    func testESMDrivesReturnUnderRecordingsOnlyWhenReadyAndSomethingIsRecorded() {
        let flow = EntryFlow(document: LogDocument())
        XCTAssertFalse(flow.esmDrivesReturn(recordingsContext()), "nothing recorded")
        flow.voiceRecordings = [3: clip]
        XCTAssertTrue(flow.esmDrivesReturn(recordingsContext()))
        XCTAssertFalse(flow.esmDrivesReturn(recordingsContext(ready: false)))
    }

    /// The default `phoneSource` is the radio's memories, so every context
    /// built before this feature — and every test above — means what it did.
    func testRadioMemoriesSourceIgnoresRecordings() {
        let document = LogDocument()
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [1: clip]
        XCTAssertEqual(
            flow.transmission(at: 0, context: phoneContext(memories: 8)),
            .voice(memory: 1, caption: "M1 CQ")
        )
        XCTAssertEqual(EntryFlow.Context().phoneSource, .radioMemories)
    }

    /// Return under ESM with a recording mapped: the same `.send`/`.logged`
    /// outcomes CW gets, carrying the recording.
    func testReturnSendsARecordingUnderESM() {
        let document = LogDocument()
        document.log.operatingMode = .run
        let flow = EntryFlow(document: document)
        flow.voiceRecordings = [1: clip]
        // Empty call field in Run: F1 (CQ) is what Return sends.
        let outcome = flow.returnPressed(recordingsContext(), undoManager: nil)
        XCTAssertEqual(outcome, .send(index: 0, transmission: .recording(memory: 1, audio: clip, caption: "M1 CQ")))
    }

    // MARK: Posture

    /// Every logged row is stamped from the log's own Run/S&P flag — the same
    /// one that picks the message set and decides what ⇧⌘S means. Without
    /// this the advisor's own-rate strands would have nothing to read, and
    /// their silence would look exactly like a quiet band.
    func testLoggedRowsAreStampedWithTheOperatingPosture() {
        for posture in OperatingMode.allCases {
            let flow = EntryFlow(document: cqpDocument(mode: posture))
            readyToLog(flow)
            guard case .logged(let rows, _) = flow.returnPressed(context(), undoManager: nil)
            else { return XCTFail("expected the contact to be logged") }
            XCTAssertEqual(rows.map(\.posture), [posture])
        }
    }

    /// Toggling mid-contest stamps the contacts on either side of it
    /// differently — which is the whole point of recording it per row rather
    /// than once per log.
    func testTogglingPostureMidContestSplitsTheLog() {
        let doc = cqpDocument(mode: .run)
        let flow = EntryFlow(document: doc)
        readyToLog(flow, call: "W6ABC", their: "SCLA")
        _ = flow.returnPressed(context(), undoManager: nil)

        doc.log.operatingMode = .searchPounce
        readyToLog(flow, call: "K6XYZ", their: "ALAM")
        _ = flow.returnPressed(context(), undoManager: nil)

        XCTAssertEqual(doc.log.qsos.map(\.posture), [.run, .searchPounce])
    }

    // MARK: POTA — the nil-party path (spec 2026-08-25 §entry row)

    /// A POTA activation log at one park — the dedicated-mode state after
    /// Contest Setup. No `PartyDefinition` resolves; the contest comes from
    /// the catalog.
    func potaDocument(parks: [String] = ["US-1111"]) -> LogDocument {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: ""),
            partyID: "pota",
            undoManager: nil
        )
        doc.log.myPotaRefs = parks
        return doc
    }

    func potaFlow(parks: [String] = ["US-1111"]) throws -> (EntryFlow, LogDocument) {
        let doc = potaDocument(parks: parks)
        let flow = EntryFlow(document: doc)
        XCTAssertNil(flow.party, "pota must resolve to no PartyDefinition")
        XCTAssertNotNil(flow.standaloneContest)
        return (flow, doc)
    }

    func testPotaLogsOneRowWithParksBothWays() throws {
        let (flow, doc) = try potaFlow()
        flow.entry.callTyped = "W1AW"
        flow.entry.theirParkTyped = "US-2222,US-3333"
        let outcome = flow.logContact(context(esm: false, connected: false),
                                      undoManager: nil)
        guard case .logged(let rows, _) = outcome else {
            return XCTFail("expected .logged, got \(outcome)")
        }
        XCTAssertEqual(rows.count, 1, "no county line in POTA — one row per contact")
        let q = try XCTUnwrap(doc.log.qsos.first)
        XCTAssertEqual(q.call, "W1AW")
        XCTAssertEqual(q.myPotaRefs, ["US-1111"])
        XCTAssertEqual(q.theirPotaRefs, ["US-2222", "US-3333"])
        XCTAssertEqual(q.rstSent, "599")
        XCTAssertEqual(q.myLoc, "", "no location element, no location")
        XCTAssertTrue(flow.entry.call.isEmpty, "row cleared for the next contact")
    }

    func testPotaHunterLogsWithNoOwnPark() throws {
        let (flow, doc) = try potaFlow(parks: [])
        flow.entry.callTyped = "K5ABC"
        flow.entry.theirParkTyped = "US-4444"
        guard case .logged = flow.logContact(context(esm: false, connected: false),
                                             undoManager: nil) else {
            return XCTFail("a hunter log must log without an own park — decision 1")
        }
        XCTAssertNil(doc.log.qsos.first?.myPotaRefs)
        XCTAssertEqual(doc.log.qsos.first?.theirPotaRefs, ["US-4444"])
    }

    func testPotaRefusesAGarbledPark() throws {
        let (flow, doc) = try potaFlow()
        flow.entry.callTyped = "W1AW"
        flow.entry.theirParkTyped = "USA-33"
        guard case .nothing = flow.logContact(context(esm: false, connected: false),
                                              undoManager: nil) else {
            return XCTFail("an unparseable park must refuse to log")
        }
        XCTAssertTrue(doc.log.qsos.isEmpty)
    }

    func testPotaDupeWarningIsPerDayAndPark() throws {
        let (flow, doc) = try potaFlow()
        let ctx = context(esm: false, connected: false)
        flow.entry.callTyped = "W1AW"
        guard case .logged = flow.logContact(ctx, undoManager: nil) else {
            return XCTFail("first contact must log")
        }
        // Same call, band, mode, same UTC day, same park: warned.
        flow.entry.callTyped = "W1AW"
        flow.revalidate(ctx)
        XCTAssertNotNil(flow.entry.dupeWarning)
        // Rove to a new park: the same station is new again.
        doc.log.myPotaRefs = ["US-9999"]
        flow.revalidate(ctx)
        XCTAssertNil(flow.entry.dupeWarning)
    }

    func testPotaTheirParkComesBackOnTheNextBand() throws {
        let (flow, _) = try potaFlow()
        let ctx = context(esm: false, connected: false)
        flow.entry.callTyped = "W1AW"
        flow.entry.theirParkTyped = "US-2222"
        guard case .logged = flow.logContact(ctx, undoManager: nil) else {
            return XCTFail("first contact must log")
        }
        flow.entry.callTyped = "W1AW"
        flow.callChanged(ctx)
        XCTAssertEqual(flow.entry.theirParkTyped, "US-2222",
                       "the park prefill must not be party-gated")
    }
}

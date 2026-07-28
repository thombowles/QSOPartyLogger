import XCTest
@testable import QSOPartyLogger

/// Call history in the prefill chain: below everything the operator copied
/// (this log, the archive, a pending stash), above a spot's claim — and the
/// received-name half, which auto-fills with the same ownership rules the
/// exchange has always had.
@MainActor
final class CallHistoryPrefillTests: XCTestCase {

    // MARK: Fixtures

    /// A KSQP log for an out-of-state operator, ready to work Kansans.
    private func ksqpFlow() -> EntryFlow {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        return EntryFlow(document: doc)
    }

    /// An NAQP CW log — the name-party case.
    private func naqpFlow() -> EntryFlow {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "naqpcw",
            undoManager: nil
        )
        doc.log.exchangeName = "TOM"
        return doc.flowForTest()
    }

    private func context() -> EntryFlow.Context {
        EntryFlow.Context(
            band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14_042,
            radioConnected: false, cursor: .call,
            keying: KeyingSettings()
        )
    }

    private func ksqpIndex() -> (partyID: String, parsed: CallHistoryFile.Parsed) {
        ("ksqp", CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY KS
        K0VBU,Bill,JOH,Johnson
        W0BH,Bob,BAR/RIC
        N0MOB,,,MOBILE
        """))
    }

    private func naqpIndex() -> (partyID: String, parsed: CallHistoryFile.Parsed) {
        ("naqpcw", CallHistoryFile.parse("""
        !!Order!!,Call,Name,State,UserText,
        # NAQPCW
        K5ZD,RANDY,OH,
        7L3PXO,MASA,,
        """))
    }

    // MARK: Exchange chain

    func testCallHistoryFillsWhenNothingElseIsKnown() {
        let flow = ksqpFlow()
        flow.callHistoryIndex = ksqpIndex()
        flow.entry.call = "K0VBU"
        flow.callChanged(context())

        XCTAssertEqual(flow.entry.exchange, "JOH")
        XCTAssertTrue(flow.entry.exchangeIsAutoFilled)
        XCTAssertEqual(flow.entry.exchangeOrigin, .callHistory)
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed,
                       "curated history is not a stranger's spot — no orange")
    }

    func testCountyLinePairFillsIntact() {
        let flow = ksqpFlow()
        flow.callHistoryIndex = ksqpIndex()
        flow.entry.call = "W0BH"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "BAR/RIC",
                       "the pair rides whole for the expander to fan out")
    }

    func testThisLogOutranksTheFile() {
        let flow = ksqpFlow()
        flow.callHistoryIndex = ksqpIndex()
        // Worked him an hour ago in a different county — he is mobile.
        flow.document.append(qsos: [QSO(
            call: "K0VBU", band: .m40, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "SED"
        )], undoManager: nil)

        flow.entry.call = "K0VBU"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "SED",
                       "what we copied ourselves beats last season's roster")
        XCTAssertEqual(flow.entry.exchangeOrigin, .ownLog)
    }

    func testFileOutranksASpotsClaim() {
        let flow = ksqpFlow()
        flow.callHistoryIndex = ksqpIndex()
        flow.stationChanged(to: "K0VBU", context(), spotCounty: "ELL")

        XCTAssertEqual(flow.entry.exchange, "JOH",
                       "the curated file beats the spot's county")
        XCTAssertEqual(flow.entry.exchangeOrigin, .callHistory)
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed)
    }

    func testSpotStillFillsWhenTheFileKnowsNothing() {
        let flow = ksqpFlow()
        flow.callHistoryIndex = ksqpIndex()
        flow.stationChanged(to: "N0MOB", context(), spotCounty: "ELL")

        XCTAssertEqual(flow.entry.exchange, "ELL",
                       "a MOBILE entry with no county falls through to the spot")
        XCTAssertEqual(flow.entry.exchangeOrigin, .spot)
        XCTAssertTrue(flow.entry.exchangeIsUnconfirmed)
    }

    func testIndexForAnotherPartyIsIgnored() {
        let flow = ksqpFlow()
        var index = ksqpIndex()
        index.partyID = "tnqp"
        flow.callHistoryIndex = index
        flow.entry.call = "K0VBU"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "",
                       "a stale download for the last party must not leak in")
    }

    func testClearingTheCallTakesTheOfferBack() {
        let flow = ksqpFlow()
        flow.callHistoryIndex = ksqpIndex()
        flow.entry.call = "K0VBU"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "JOH")

        flow.entry.call = ""
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "")
        XCTAssertFalse(flow.entry.exchangeIsAutoFilled)
    }

    /// KSQP rejects "KS" from an in-state operator's counterpart; a file
    /// offering it must be filtered by the same parser the entry field uses.
    func testUnparseableFileValueIsWithheld() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "K0AAA"),
            location: .inState(counties: ["JOH"]),
            partyID: "ksqp",
            undoManager: nil
        )
        let flow = EntryFlow(document: doc)
        flow.callHistoryIndex = ("ksqp", CallHistoryFile.parse("""
        !!Order!!,Call,Exch1
        W0KS,KS
        """))
        flow.entry.call = "W0KS"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "",
                       "the home-state token is invalid here and never offered")
    }

    // MARK: The name half

    func testNameAndStateFillTogetherForANameParty() {
        let flow = naqpFlow()
        flow.callHistoryIndex = naqpIndex()
        flow.entry.call = "K5ZD"
        flow.callChanged(context())

        XCTAssertEqual(flow.entry.exchange, "OH")
        XCTAssertEqual(flow.entry.nameRcvd, "RANDY")
        XCTAssertTrue(flow.entry.nameIsAutoFilled)
        XCTAssertFalse(flow.entry.missingName(party: flow.party),
                       "an offered name satisfies the log gate; logging is "
                       + "how the operator accepts it")
    }

    func testNameOnlyEntryStillOffersTheName() {
        let flow = naqpFlow()
        flow.callHistoryIndex = naqpIndex()
        flow.entry.call = "7L3PXO"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.nameRcvd, "MASA")
        XCTAssertEqual(flow.entry.exchange, "",
                       "no location known — the exchange stays honest")
    }

    func testTypedNameIsNeverOverwritten() {
        let flow = naqpFlow()
        flow.callHistoryIndex = naqpIndex()
        flow.entry.call = "K5ZD"
        flow.entry.nameTyped = "RANDALL"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.nameRcvd, "RANDALL",
                       "what was copied off the air is the operator's")
        XCTAssertFalse(flow.entry.nameIsAutoFilled)
    }

    func testAutoFilledNameClearsWhenTheStationChanges() {
        let flow = naqpFlow()
        flow.callHistoryIndex = naqpIndex()
        flow.stationChanged(to: "K5ZD", context())
        XCTAssertEqual(flow.entry.nameRcvd, "RANDY")

        flow.stationChanged(to: "N0SUCH", context())
        XCTAssertEqual(flow.entry.nameRcvd, "",
                       "RANDY must not ride along to a stranger's row")
        XCTAssertFalse(flow.entry.nameIsAutoFilled)
    }

    func testThisLogsNameOutranksTheFile() {
        let flow = naqpFlow()
        flow.callHistoryIndex = naqpIndex()
        flow.document.append(qsos: [QSO(
            call: "K5ZD", band: .m40, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599", nameRcvd: "RANDIE",
            myLoc: "TX", theirLoc: "MA"
        )], undoManager: nil)

        flow.entry.call = "K5ZD"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.nameRcvd, "RANDIE",
                       "the name he actually sent us this contest wins")
        XCTAssertEqual(flow.entry.exchange, "MA",
                       "and so does the location we logged")
    }

    /// A non-name party must never grow a name from the file — ALQP's file
    /// carries names, and its exchange has nowhere to put one.
    func testNamePartyGateHolds() {
        let flow = ksqpFlow()
        flow.callHistoryIndex = ("ksqp", CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1
        K0VBU,Bill,JOH
        """))
        flow.entry.call = "K0VBU"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "JOH")
        XCTAssertEqual(flow.entry.nameRcvd, "")
    }

    // MARK: Pending interplay

    /// Copying a serial for a station, moving on, and coming back must
    /// restore the copied serial *and* still offer the file's exchange for
    /// the empty half.
    func testPendingSerialRestoresAndHintsStillFill() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "cqp",
            undoManager: nil
        )
        let flow = EntryFlow(document: doc)
        flow.callHistoryIndex = ("cqp", CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY CA
        AA6AH,,SACR,SACRAMENTO,
        """))

        flow.stationChanged(to: "AA6AH", context())
        XCTAssertEqual(flow.entry.exchange, "SACR")
        flow.entry.serialRcvd = "42"

        flow.stationChanged(to: "W6XYZ", context())
        XCTAssertEqual(flow.entry.serialRcvd, "")

        flow.stationChanged(to: "AA6AH", context())
        XCTAssertEqual(flow.entry.serialRcvd, "42",
                       "the copied serial came back with its station")
        XCTAssertEqual(flow.entry.exchange, "SACR",
                       "and the empty exchange still gets the file's hint")
        XCTAssertTrue(flow.entry.exchangeIsAutoFilled)
    }
}

private extension LogDocument {
    /// `EntryFlow` for a document, for tests that build both.
    func flowForTest() -> EntryFlow { EntryFlow(document: self) }
}

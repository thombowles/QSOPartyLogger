import XCTest
@testable import QSOPartyLogger

/// N1MM's call frame, in the entry row: the spot under the VFO while
/// searching, taken by Space or by Return under ESM ("Hitting the space bar
/// (or Enter, in ESM) will pull the call-sign from the call-frame into the
/// Call-sign textbox" — Entry window, fetched 2026-08-15), and erased again
/// when the VFO tunes away ("any call-sign captured into the Entry window's
/// call-frame or brought into the Entry window's call-sign textbox will be
/// erased" — Bandmap window). Typed text is never touched by tuning.
@MainActor
final class CallFrameTests: XCTestCase {

    // MARK: Fixtures

    /// A KSQP log, out-of-state TX, searching — the state the frame lives in.
    private func ksqpFlow() -> EntryFlow {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        doc.log.operatingMode = .searchPounce
        return EntryFlow(document: doc)
    }

    /// CW, radio connected, ESM on unless said otherwise, cursor in the call
    /// field unless said otherwise.
    private func context(
        cursor: ESM.Cursor = .call, esm: Bool = true, offersSpotCounty: Bool = true
    ) -> EntryFlow.Context {
        EntryFlow.Context(
            band: .m40, modeClass: .cw, rawMode: "CW", freqKHz: 7040,
            radioConnected: true, cursor: cursor,
            keying: KeyingSettings(esmEnabled: esm),
            offersSpotCounty: offersSpotCounty
        )
    }

    private func hubSpot(_ call: String = "W0BH", county: String? = "MRN", kHz: Double = 7040.0) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: "N0AX", comment: "",
             receivedAt: Date(), county: county, source: .hub)
    }

    // MARK: Taking the frame

    func testSpaceTakesTheFrameIntoAnEmptyCallField() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        XCTAssertTrue(flow.takeCallFrame(context()))

        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertTrue(flow.entry.callIsAutoFilled, "the app put it there")
        XCTAssertEqual(flow.entry.exchange, "MRN", "the spot's county comes with it")
        XCTAssertTrue(flow.entry.exchangeIsUnconfirmed, "as a stranger's claim, marked so")
    }

    func testTheCountyIsNotOfferedWhenTheOptionIsOff() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        XCTAssertTrue(flow.takeCallFrame(context(offersSpotCounty: false)))
        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertEqual(flow.entry.exchange, "")
    }

    /// N1MM: "When the call-sign textbox is empty, pressing the space bar will
    /// copy the call-sign" — and only then.
    func testAFieldWithTextInItIsNeverOverwritten() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        flow.entry.callTyped = "K5"
        XCTAssertFalse(flow.takeCallFrame(context()))
        XCTAssertEqual(flow.entry.call, "K5")
    }

    func testNoFrameNothingToTake() {
        let flow = ksqpFlow()
        XCTAssertFalse(flow.takeCallFrame(context()))
        XCTAssertEqual(flow.entry.call, "")
    }

    /// The frame never writes the field by itself.
    func testTheFrameByItselfLeavesTheFieldEmpty() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        XCTAssertEqual(flow.entry.callFrame?.call, "W0BH")
        XCTAssertEqual(flow.entry.call, "")
        flow.updateCallFrame(nil)
        XCTAssertNil(flow.entry.callFrame)
    }

    // MARK: Return under ESM

    /// One Return fills the row and calls him: S&P with the cursor in the
    /// call field is F1, my call — the same message Return sends on an empty
    /// row, now with the call in the field.
    func testReturnUnderESMInTheEmptyCallFieldTakesTheFrameAndCalls() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        let outcome = flow.returnPressed(context(cursor: .call), undoManager: nil)

        XCTAssertEqual(outcome, .send(index: 0, transmission: .cw("KE5CW")))
        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertEqual(flow.entry.exchange, "MRN")
    }

    /// From any other field the frame stays put: with the county pre-filled
    /// the row could be loggable, and the cursor in the exchange field is what
    /// ESM reads as "I have him". The call field never logs, which is why it
    /// alone may take the frame.
    func testReturnFromTheExchangeFieldLeavesTheFrameAlone() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        let outcome = flow.returnPressed(context(cursor: .exchange), undoManager: nil)

        XCTAssertEqual(outcome, .send(index: 0, transmission: .cw("KE5CW")), "the empty-row F1, as before")
        XCTAssertEqual(flow.entry.call, "", "not taken")
        XCTAssertEqual(flow.entry.callFrame?.call, "W0BH", "still on offer")
    }

    /// Outside ESM, Return logs — so it must not first fill a row that would
    /// then be loggable. N1MM: "(or Enter, in ESM)".
    func testReturnWithoutESMLeavesTheFrameAlone() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        let outcome = flow.returnPressed(context(cursor: .call, esm: false), undoManager: nil)

        XCTAssertEqual(outcome, .nothing)
        XCTAssertEqual(flow.entry.call, "")
    }

    // MARK: Ownership of the call

    func testStationChangedMarksTheCallAppFilledAndTypingTakesItBack() {
        let flow = ksqpFlow()
        flow.stationChanged(to: "W0BH", context(), spotCounty: nil, atKHz: 7040.0)
        XCTAssertTrue(flow.entry.callIsAutoFilled)

        flow.entry.callTyped = "W0BHX"
        XCTAssertFalse(flow.entry.callIsAutoFilled, "the first keystroke makes it the operator's")
    }

    func testClearingForTheNextContactResetsTheMark() {
        let flow = ksqpFlow()
        flow.stationChanged(to: "W0BH", context(), spotCounty: nil, atKHz: 7040.0)
        flow.entry.clearForNextContact(modeClass: .cw)
        XCTAssertFalse(flow.entry.callIsAutoFilled)
        XCTAssertEqual(flow.entry.call, "")
    }

    // MARK: hasOperatorText

    func testAFreshRowHasNoOperatorText() {
        let flow = ksqpFlow()
        flow.entry.applyDefaults(modeClass: .cw)
        XCTAssertFalse(flow.entry.hasOperatorText)
    }

    func testAnAppFilledRowHasNoOperatorText() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        _ = flow.takeCallFrame(context())
        XCTAssertEqual(flow.entry.exchange, "MRN", "precondition: county auto-filled")
        XCTAssertFalse(flow.entry.hasOperatorText, "call and county are both the app's")
    }

    func testEachTypedFieldCountsAsOperatorText() {
        let fresh = { () -> EntryState in
            let entry = EntryState()
            entry.applyDefaults(modeClass: .cw)
            return entry
        }
        var entry = fresh(); entry.callTyped = "K"
        XCTAssertTrue(entry.hasOperatorText, "typed call")
        entry = fresh(); entry.exchangeTyped = "M"
        XCTAssertTrue(entry.hasOperatorText, "typed exchange")
        entry = fresh(); entry.nameTyped = "T"
        XCTAssertTrue(entry.hasOperatorText, "typed name")
        entry = fresh(); entry.memberTyped = "1"
        XCTAssertTrue(entry.hasOperatorText, "typed member element")
        entry = fresh(); entry.serialRcvd = "1"
        XCTAssertTrue(entry.hasOperatorText, "received number")
        entry = fresh(); entry.theirParkTyped = "US-1"
        XCTAssertTrue(entry.hasOperatorText, "park")
        entry = fresh(); entry.serialSent = "7"
        XCTAssertTrue(entry.hasOperatorText, "sent number override")
        entry = fresh(); entry.rstRcvd = "579"
        XCTAssertTrue(entry.hasOperatorText, "a report changed from the default")
        entry = fresh(); entry.autoFillExchange("MRN", origin: .spot); entry.autoFillName("BOB")
        XCTAssertFalse(entry.hasOperatorText, "auto-filled text is the app's")
    }

    // MARK: Erasing what was taken

    func testTuningAwayErasesAnAppFilledRow() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot(kHz: 7040.0))
        _ = flow.takeCallFrame(context())
        XCTAssertEqual(flow.entry.call, "W0BH", "precondition")

        flow.tunedAway(toKHz: 7040.2, toleranceKHz: 0.3, context())
        XCTAssertEqual(flow.entry.call, "W0BH", "still within tolerance — zero-beating him")

        flow.tunedAway(toKHz: 7040.4, toleranceKHz: 0.3, context())
        XCTAssertEqual(flow.entry.call, "", "erased")
        XCTAssertEqual(flow.entry.exchange, "", "and the county the app offered with it")
        XCTAssertFalse(flow.entry.callIsAutoFilled)
    }

    /// The same for a spot click or ⌘↑/⌘↓ — every app-filled call.
    func testTuningAwayErasesACallFromASpotClick() {
        let flow = ksqpFlow()
        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN", atKHz: 7040.0)
        flow.tunedAway(toKHz: 7041.0, toleranceKHz: 0.3, context())
        XCTAssertEqual(flow.entry.call, "")
    }

    func testTypedTextIsNeverErasedByTuning() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot(kHz: 7040.0))
        _ = flow.takeCallFrame(context())
        flow.entry.exchangeTyped = "MRN"   // he copied it himself

        flow.tunedAway(toKHz: 7041.0, toleranceKHz: 0.3, context())

        XCTAssertEqual(flow.entry.call, "W0BH", "he has engaged with this station")
        XCTAssertEqual(flow.entry.exchange, "MRN")

        let typed = ksqpFlow()
        typed.entry.callTyped = "K5ABC"
        typed.tunedAway(toKHz: 7041.0, toleranceKHz: 0.3, context())
        XCTAssertEqual(typed.entry.call, "K5ABC", "a typed call is not the app's to erase")
    }
}

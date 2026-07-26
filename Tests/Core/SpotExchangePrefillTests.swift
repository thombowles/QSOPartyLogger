import XCTest
@testable import QSOPartyLogger

/// A spot's county as the last-resort exchange candidate.
///
/// Three things can fill this field, and they do not deserve equal faith:
///
/// 1. What the operator copied for this station and never logged.
/// 2. What the operator worked before, here or in a past contest.
/// 3. What a stranger posted to a spotting board thirty seconds ago.
///
/// Only the third is someone else's claim, and the captured hub corpus shows
/// those go wrong — a busted call, a frequency 29 kHz off, an unparseable
/// typo. A wrong county is cross-checked against the other station's log and
/// costs the contact. So a spot county fills only when nothing better exists,
/// and says plainly that it was not copied.
@MainActor
final class SpotExchangePrefillTests: XCTestCase {

    private func ksqpDocument() -> LogDocument {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        return doc
    }

    private func ksqpDocumentWorking(_ call: String, as loc: String) -> LogDocument {
        let doc = ksqpDocument()
        doc.append(
            qsos: [
                QSO(call: call, band: .m40, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: loc)
            ],
            undoManager: nil
        )
        return doc
    }

    private func context() -> EntryFlow.Context {
        EntryFlow.Context(
            band: .m40, modeClass: .cw, rawMode: "CW", freqKHz: nil,
            radioConnected: false, cursor: .exchange,
            keying: KeyingSettings(esmEnabled: true, cutNumbers: false, cutOne: false)
        )
    }

    // MARK: The spot fills when nothing better is known

    func testSpotCountyFillsAnUnknownStation() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN")

        XCTAssertEqual(flow.entry.exchange, "MRN")
        XCTAssertTrue(flow.entry.exchangeIsUnconfirmed,
                      "nobody copied this — it is a spotter's claim")
    }

    /// A spot with no county at all — every cluster spot — fills nothing.
    func testSpotWithoutACountyFillsNothing() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.stationChanged(to: "W0BH", context(), spotCounty: nil)

        XCTAssertEqual(flow.entry.exchange, "")
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed)
    }

    // MARK: Anything of our own outranks it

    /// Worked before means the operator already copied this county once, off
    /// the air. That beats a stranger's claim, and carries no warning.
    func testOwnLogOutranksTheSpotsClaim() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JOH"))
        flow.stationChanged(to: "K5NA", context(), spotCounty: "MRN")

        XCTAssertEqual(flow.entry.exchange, "JOH", "what we worked beats what a spotter says")
        XCTAssertTrue(flow.entry.exchangeIsAutoFilled)
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed,
                       "our own log is not an unconfirmed claim")
    }

    /// What the operator copied but never logged outranks everything.
    func testCopiedExchangeOutranksTheSpotsClaim() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JOH"

        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN")
        flow.stationChanged(to: "K5NA", context(), spotCounty: "SED")

        XCTAssertEqual(flow.entry.exchange, "JOH", "the operator's own copy stands")
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed)
    }

    // MARK: Ownership

    /// Typing is the operator taking responsibility for the value.
    func testTypingOverTheSpotCountyConfirmsIt() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN")
        XCTAssertTrue(flow.entry.exchangeIsUnconfirmed)

        flow.entry.exchangeTyped = "MRN"
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed,
                       "the operator has put their own name to it now")
    }

    /// The claim belongs to the call it arrived with. Correcting a busted spot
    /// by typing must not leave the old station's county behind.
    func testSpotCountyDoesNotFollowATypedCorrection() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN")
        XCTAssertEqual(flow.entry.exchange, "MRN")

        flow.entry.call = "W0BHX"
        flow.callChanged(context())

        XCTAssertEqual(flow.entry.exchange, "",
                       "the county was W0BH's, not this station's")
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed)
    }

    /// Moving on takes the app's own text back rather than carrying it to the
    /// next station, exactly as it does for a fill from the log.
    func testMovingToAnotherStationDropsTheSpotCounty() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN")
        flow.stationChanged(to: "K5NA", context(), spotCounty: nil)

        XCTAssertEqual(flow.entry.exchange, "")
        XCTAssertFalse(flow.entry.exchangeIsUnconfirmed)
    }

    // MARK: Downstream

    /// The mark is presentation only. A spot-filled exchange validates and
    /// scores exactly as a typed one does — checking it is the operator's job,
    /// not the app's to discount it.
    func testASpotFilledExchangeStillValidatesNormally() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN")

        XCTAssertEqual(flow.entry.exchangeStatus, .valid(["MRN"]))
        XCTAssertTrue(flow.entry.exchangeIsUnconfirmed, "validating is not confirming")
    }
}

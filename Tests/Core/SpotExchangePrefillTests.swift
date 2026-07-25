import XCTest
@testable import QSOPartyLogger

/// Pre-filling the exchange from a spot's county.
///
/// A hub spot names the county, which is the exchange in a state QSO party —
/// but it is a *third party's* claim, not something the operator copied. The
/// captured corpus is proof that claim can be wrong: `N4RT` appeared at both
/// 7045.5 and 7074.5 within 33 seconds, `KC4TE` was a busted call, `1042.3`
/// was a typo. A wrong county reaching the log is cross-checked against the
/// other station's and costs the contact.
///
/// So the value goes in, but stays marked unconfirmed until the operator has
/// actually touched it. What was copied is always distinguishable from what
/// was claimed.
final class SpotExchangePrefillTests: XCTestCase {

    func testPrefilledExchangeIsMarkedUnconfirmed() {
        let entry = EntryState()
        entry.prefillExchange("MDSN")

        XCTAssertEqual(entry.exchange, "MDSN")
        XCTAssertTrue(entry.exchangeIsUnconfirmed)
    }

    /// Typing is the operator taking responsibility for the value.
    func testTypingIntoTheFieldConfirmsIt() {
        let entry = EntryState()
        entry.prefillExchange("MDSN")
        entry.exchange = "MDSN"

        XCTAssertFalse(entry.exchangeIsUnconfirmed,
                       "the operator has now put their own name to it")
    }

    /// Never overwrite what the operator typed. Stepping through spots with
    /// ⌘←/⌘→ must not quietly replace an exchange already being copied.
    func testPrefillNeverClobbersTypedText() {
        let entry = EntryState()
        entry.exchange = "LAWR"
        entry.prefillExchange("MDSN")

        XCTAssertEqual(entry.exchange, "LAWR")
        XCTAssertFalse(entry.exchangeIsUnconfirmed)
    }

    /// But one unconfirmed value may replace another, so stepping between
    /// spots keeps up rather than sticking on the first county seen.
    func testPrefillReplacesAnEarlierUnconfirmedValue() {
        let entry = EntryState()
        entry.prefillExchange("MDSN")
        entry.prefillExchange("LAWR")

        XCTAssertEqual(entry.exchange, "LAWR")
        XCTAssertTrue(entry.exchangeIsUnconfirmed)
    }

    /// Clearing for the next contact drops the mark with the value, or the
    /// next contact would inherit a warning about an exchange that is gone.
    func testClearingForTheNextContactResetsTheMark() {
        let entry = EntryState()
        entry.prefillExchange("MDSN")
        entry.clearForNextContact(modeClass: .cw)

        XCTAssertEqual(entry.exchange, "")
        XCTAssertFalse(entry.exchangeIsUnconfirmed)
    }

    /// An empty county is not a value to pre-fill — most cluster spots have
    /// none at all.
    func testEmptyCountyIsNotPrefilled() {
        let entry = EntryState()
        entry.prefillExchange("")

        XCTAssertEqual(entry.exchange, "")
        XCTAssertFalse(entry.exchangeIsUnconfirmed)
    }

    /// The mark is presentation only. A pre-filled exchange still validates
    /// and scores exactly as a typed one does — it is the operator's job to
    /// check it, not the app's to discount it.
    func testAnUnconfirmedExchangeStillValidatesNormally() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        var log = ContestLog(partyID: "alqp")
        log.myLocation = .outOfState(location: "TX")

        let entry = EntryState()
        entry.call = "K4EES"
        entry.prefillExchange("BALD")
        entry.revalidate(party: alqp, log: log, band: .m40, modeClass: .cw)

        XCTAssertEqual(entry.exchangeStatus, .valid(["BALD"]))
        XCTAssertTrue(entry.exchangeIsUnconfirmed, "validating is not confirming")
    }
}

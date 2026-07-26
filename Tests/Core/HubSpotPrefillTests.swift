import XCTest
@testable import QSOPartyLogger

/// Filling the spot sheet for a station that is not you.
///
/// The hub is not self-spot-only — `docs/research/qsopartyhub.md` §6.4: every
/// spot in the live ALQP capture was posted by `N4EMP` for somebody else. So
/// the form needs no new contract, only a prefill that can start from a band
/// map spot, a log row, or the entry field.
///
/// The one judgement here is the county. `theirLoc` is a county for an
/// in-state station and a state or `DX` for everyone else, the entry field
/// holds whatever the operator has typed so far, and the form's county is a
/// token from the hub's own `<select>`. Anything that is not a county of this
/// party is dropped rather than posted to a public board as one.
final class HubSpotPrefillTests: XCTestCase {

    private func party() throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.party(id: "alqp"))
    }

    private func fields(
        station: String = "K0ABC",
        frequencyKHz: Double? = 7047,
        location: String? = "MDSN",
        poster: String = "KE5CW"
    ) throws -> HubSelfSpot.Fields {
        HubSpotPrefill.fields(
            station: station, frequencyKHz: frequencyKHz, location: location,
            poster: poster, party: try party()
        )
    }

    // MARK: The county

    func testACountyFromTheLogIsOfferedToTheForm() throws {
        XCTAssertEqual(try fields(location: "MDSN").county, "MDSN")
    }

    /// An out-of-state entrant's exchange is a state. It is a multiplier, and
    /// it is not a county token — the form would reject it, and the board
    /// would carry a county that does not exist.
    func testAnOutOfStateLocationIsNotOfferedAsACounty() throws {
        XCTAssertNil(try fields(location: "TX").county)
    }

    func testADXLocationIsNotOfferedAsACounty() throws {
        XCTAssertNil(try fields(location: "DX").county)
    }

    /// Straight from the entry field mid-QSO, signal report and all.
    func testTheCountyIsFoundInsideACopiedExchange() throws {
        XCTAssertEqual(try fields(location: "599 mdsn").county, "MDSN")
    }

    /// A county-line station gives two; the sheet's picker can change it, so
    /// the first is the one to offer.
    func testACountyLineExchangeOffersItsFirstCounty() throws {
        XCTAssertEqual(try fields(location: "MDSN/LIME").county, "MDSN")
    }

    func testAnExchangeWithNoCountyInItOffersNone() throws {
        XCTAssertNil(try fields(location: "59 59").county)
    }

    func testNoLocationAtAllOffersNoCounty() throws {
        XCTAssertNil(try fields(location: nil).county)
    }

    // MARK: The rest of the form

    func testTheStationSpottedIsTheOneAskedFor() throws {
        let fields = try fields(station: " k0abc ")

        XCTAssertEqual(fields.station, "K0ABC")
        XCTAssertEqual(fields.poster, "KE5CW")
    }

    /// A QSO logged with no radio has no frequency. The field opens empty and
    /// the sheet's own validation holds the send until one is typed — a guessed
    /// frequency on a public board is worse than a blank field.
    func testAContactWithNoLoggedFrequencyLeavesTheFrequencyEmpty() throws {
        XCTAssertEqual(try fields(frequencyKHz: nil).frequencyKHz, 0)
    }

    /// End to end: what the prefill produces is something the form accepts.
    func testAPrefilledSpotPassesTheFormsOwnValidation() throws {
        XCTAssertNil(HubSelfSpot.validate(try fields(), party: try party()))
    }

    /// And an unfilled frequency does not: this is the state the sheet has to
    /// stop, and the operator is told which field to fix.
    func testAnEmptyFrequencyIsRefusedByValidation() throws {
        XCTAssertEqual(
            HubSelfSpot.validate(try fields(frequencyKHz: nil), party: try party()),
            .frequencyNotOnAPartyBand
        )
    }
}

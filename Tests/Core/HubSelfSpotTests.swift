import XCTest
@testable import QSOPartyLogger

/// Building a self-spot for qsopartyhub.com.
///
/// The form has no CSRF token, no authentication and no session: anything
/// posted reaches a public board immediately, and a repeated submit posts
/// twice. The contract below is derived from the page's own markup — no test
/// post was ever made to the live board — so the shape is pinned here and the
/// first real send is verified against the following poll rather than assumed.
final class HubSelfSpotTests: XCTestCase {

    private func party(_ id: String) throws -> PartyDefinition {
        try XCTUnwrap(PartyCatalog.party(id: id))
    }

    private func fields(
        station: String = "KE5CW",
        frequencyKHz: Double = 7047,
        county: String? = "MDSN",
        comment: String = "",
        poster: String = "KE5CW"
    ) -> HubSelfSpot.Fields {
        HubSelfSpot.Fields(station: station, frequencyKHz: frequencyKHz,
                           county: county, comment: comment, poster: poster)
    }

    // MARK: Wire format

    /// Byte-for-byte, because a hand-rolled multipart body that a browser
    /// would not have sent is the kind of thing that fails only in the field.
    func testMultipartBodyMatchesTheBrowsersShape() throws {
        let body = HubSelfSpot.multipartBody(
            fields: fields(comment: "MOBILE"),
            party: try party("alqp"),
            boundary: "----QSOPartyLoggerBoundary"
        )
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertEqual(text, """
        ------QSOPartyLoggerBoundary\r
        Content-Disposition: form-data; name="station"\r
        \r
        KE5CW\r
        ------QSOPartyLoggerBoundary\r
        Content-Disposition: form-data; name="frequency"\r
        \r
        7047\r
        ------QSOPartyLoggerBoundary\r
        Content-Disposition: form-data; name="county"\r
        \r
        MDSN\r
        ------QSOPartyLoggerBoundary\r
        Content-Disposition: form-data; name="comment"\r
        \r
        MOBILE\r
        ------QSOPartyLoggerBoundary\r
        Content-Disposition: form-data; name="poster"\r
        \r
        KE5CW\r
        ------QSOPartyLoggerBoundary--\r\n
        """)
    }

    /// The form's own placeholder is `14150`, so a whole kilohertz goes out
    /// without a decimal point. Posting clean kHz is also the one thing this
    /// app can do to reduce the very ambiguity its parser exists to resolve.
    func testFrequencyIsSentAsKilohertz() throws {
        let alqp = try party("alqp")
        XCTAssertEqual(try value(of: "frequency", in: fields(frequencyKHz: 14150), party: alqp),
                       "14150")
        XCTAssertEqual(try value(of: "frequency", in: fields(frequencyKHz: 7041.4), party: alqp),
                       "7041.4")
        XCTAssertEqual(try value(of: "frequency", in: fields(frequencyKHz: 14045.25), party: alqp),
                       "14045.25")
    }

    /// Illinois again, in reverse. Our official `PULA` has to go out as the
    /// hub's `PULS`, because that is the only token its own form accepts.
    func testCountyIsTranslatedBackToTheHubsToken() throws {
        XCTAssertEqual(
            try value(of: "county", in: fields(county: "PULA"), party: try party("ilqp")),
            "PULS"
        )
    }

    /// An optional county is simply blank, matching the form's "-Optional-".
    func testMissingCountyIsSentEmpty() throws {
        XCTAssertEqual(
            try value(of: "county", in: fields(county: nil), party: try party("alqp")),
            ""
        )
    }

    /// A county line goes out whole. This is off the documented contract —
    /// `docs/research/qsopartyhub.md` §5 records the county input as a
    /// `<select>` of single tokens, and §6 lists a county-line spot as
    /// unverified. Taken anyway: a spot naming only `MDSN` tells a chaser
    /// hunting `LIME` to skip a station that would have given them the
    /// multiplier. Correct information off-contract beats misleading
    /// information on it.
    func testACountyLineIsSentWhole() throws {
        XCTAssertEqual(
            try value(of: "county", in: fields(county: "MDSN/LIME"), party: try party("alqp")),
            "MDSN/LIME"
        )
    }

    /// Illinois inside a pair: the alias is per token, not per field, so the
    /// county that needs translating still gets it and its partner is left
    /// alone.
    func testEachCountyOfALineIsTranslatedSeparately() throws {
        XCTAssertEqual(
            try value(of: "county", in: fields(county: "PULA/JACK"), party: try party("ilqp")),
            "PULS/JACK"
        )
    }

    // MARK: Validation

    /// The form's own maxlengths. Exceeding them is the caller's bug, but the
    /// board is public, so it is caught here rather than posted.
    func testFieldsAreHeldToTheFormsOwnLimits() throws {
        let alqp = try party("alqp")
        XCTAssertNil(HubSelfSpot.validate(fields(), party: alqp))
        XCTAssertNotNil(HubSelfSpot.validate(fields(station: ""), party: alqp))
        XCTAssertNotNil(HubSelfSpot.validate(fields(poster: ""), party: alqp))
        XCTAssertNotNil(
            HubSelfSpot.validate(fields(station: String(repeating: "A", count: 16)), party: alqp)
        )
        XCTAssertNotNil(
            HubSelfSpot.validate(fields(comment: String(repeating: "A", count: 51)), party: alqp)
        )
    }

    /// A frequency the app itself would refuse to read back is not one to
    /// broadcast to everyone else.
    func testFrequencyOutsideThePartysBandsIsRefused() throws {
        XCTAssertNotNil(
            HubSelfSpot.validate(fields(frequencyKHz: 144200), party: try party("alqp"))
        )
    }

    /// A county this party does not have would be a multiplier nobody can
    /// claim.
    func testUnknownCountyIsRefused() throws {
        XCTAssertNotNil(
            HubSelfSpot.validate(fields(county: "ZZZZ"), party: try party("alqp"))
        )
    }

    /// The field is typed by hand, so it is read the way a county line is
    /// written — however the operator happens to separate them.
    func testACountyLineIsAcceptedHoweverItIsSeparated() throws {
        let alqp = try party("alqp")
        XCTAssertNil(HubSelfSpot.validate(fields(county: "MDSN/LIME"), party: alqp))
        XCTAssertNil(HubSelfSpot.validate(fields(county: "MDSN, LIME"), party: alqp))
        XCTAssertNil(HubSelfSpot.validate(fields(county: "mdsn lime"), party: alqp))
    }

    /// One bad county in a pair fails the whole spot, and names the one at
    /// fault rather than making the operator guess which half is wrong.
    func testABadCountyInsideALineIsNamed() throws {
        XCTAssertEqual(
            HubSelfSpot.validate(fields(county: "MDSN/ZZZZ"), party: try party("alqp")),
            .unknownCounty("ZZZZ")
        )
    }

    /// Splitting typed text, before anything judges whether the tokens are
    /// real counties — that is validation's job, and it needs the bad ones.
    func testTypedCountyTextSplitsIntoTokens() {
        XCTAssertEqual(HubSelfSpot.counties(in: "MDSN/LIME"), ["MDSN", "LIME"])
        XCTAssertEqual(HubSelfSpot.counties(in: " mdsn ,  lime "), ["MDSN", "LIME"])
        XCTAssertEqual(HubSelfSpot.counties(in: "MDSN//"), ["MDSN"])
        XCTAssertEqual(HubSelfSpot.counties(in: "MDSN/MDSN"), ["MDSN"])
        XCTAssertEqual(HubSelfSpot.counties(in: "MDSN/ZZZZ"), ["MDSN", "ZZZZ"])
        XCTAssertEqual(HubSelfSpot.counties(in: "   "), [])
    }

    // MARK: Throttle

    /// The board is public and the form has no protection of its own, so a
    /// stuck key must not be able to spam it.
    func testIdenticalSpotIsRefusedWithinTheWindow() {
        let sent = fields()
        let now = Date()
        XCTAssertTrue(HubSelfSpot.isDuplicate(sent, of: sent, lastSentAt: now,
                                              now: now.addingTimeInterval(30)))
        XCTAssertFalse(HubSelfSpot.isDuplicate(sent, of: sent, lastSentAt: now,
                                               now: now.addingTimeInterval(10 * 60)))
    }

    /// Moving frequency is exactly when a re-spot matters, so it is never a
    /// duplicate.
    func testChangingFrequencyIsNotADuplicate() {
        let now = Date()
        XCTAssertFalse(HubSelfSpot.isDuplicate(fields(frequencyKHz: 7050),
                                               of: fields(frequencyKHz: 7047),
                                               lastSentAt: now,
                                               now: now.addingTimeInterval(30)))
    }

    /// And so is changing county — the thing a rover most often forgets.
    func testChangingCountyIsNotADuplicate() {
        let now = Date()
        XCTAssertFalse(HubSelfSpot.isDuplicate(fields(county: "LAWR"),
                                               of: fields(county: "MDSN"),
                                               lastSentAt: now,
                                               now: now.addingTimeInterval(30)))
    }

    // MARK: Helpers

    private func value(
        of name: String, in fields: HubSelfSpot.Fields, party: PartyDefinition
    ) throws -> String {
        let body = HubSelfSpot.multipartBody(fields: fields, party: party, boundary: "B")
        let text = try XCTUnwrap(String(data: body, encoding: .utf8))
        let marker = "Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n"
        let after = try XCTUnwrap(text.range(of: marker))
        let rest = text[after.upperBound...]
        let end = try XCTUnwrap(rest.range(of: "\r\n--B"))
        return String(rest[..<end.lowerBound])
    }
}

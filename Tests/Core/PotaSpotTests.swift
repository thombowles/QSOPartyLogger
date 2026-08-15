import XCTest
@testable import QSOPartyLogger

/// The spot pota.app's own "Add Spot" form posts, rule for rule — the
/// form's code is the contract, quoted in `docs/research/pota/SOURCES.md`.
final class PotaSpotTests: XCTestCase {

    private func fields(
        activator: String = "KE5CW", spotter: String = "KE5CW", kHz: Double = 7047,
        reference: String = "US-0817", mode: String = "CW", comments: String = ""
    ) -> PotaSpot.Fields {
        .init(activator: activator, spotter: spotter, frequencyKHz: kHz,
              reference: reference, mode: mode, comments: comments)
    }

    // MARK: The form's own rules

    /// `validCallsignRegex`, verbatim.
    func testCallsignsTheFormAccepts() {
        for call in ["KE5CW", "ke5cw", "W1AW/M", "VE3/KE5CW", "K5D", "4U1UN", "9A1A", "W1AW/P"] {
            XCTAssertTrue(PotaSpot.isValidCallsign(call), call)
        }
        for call in ["", "KE5CW/", "/KE5CW", "K E5CW", "KECW", "KE5CW/MOBILE", "KE5CW-#", "ABCDE1"] {
            XCTAssertFalse(PotaSpot.isValidCallsign(call), call)
        }
    }

    /// `validReferenceRegex` or the literal `K-TEST`, after the ADIF grammar.
    func testReferencesTheFormAccepts() {
        XCTAssertEqual(PotaSpot.reference(from: " us-0817 "), "US-0817")
        XCTAssertEqual(PotaSpot.reference(from: "K-10000"), "K-10000")
        XCTAssertEqual(PotaSpot.reference(from: "K-TEST"), "K-TEST")
        XCTAssertEqual(PotaSpot.reference(from: "k-test"), "K-TEST")
        // The spot page's regex has no room for a subdivision — it comes off.
        XCTAssertEqual(PotaSpot.reference(from: "K-4562@US-CA"), "K-4562")
        for bad in ["", "US0817", "US-817", "US-123456", "USA-0817", "US-08I7", "US 0817"] {
            XCTAssertNil(PotaSpot.reference(from: bad), bad)
        }
    }

    func testValidationSpeaksInTheFormsTerms() {
        XCTAssertNil(PotaSpot.validate(fields()))
        XCTAssertEqual(PotaSpot.validate(fields(activator: "")), .missingActivator)
        XCTAssertEqual(PotaSpot.validate(fields(spotter: " ")), .missingSpotter)
        XCTAssertEqual(PotaSpot.validate(fields(activator: "KE5CW/MOBILE")), .badCallsign("KE5CW/MOBILE"))
        XCTAssertEqual(PotaSpot.validate(fields(spotter: "ke5cw/")), .badCallsign("KE5CW/"))
        XCTAssertEqual(PotaSpot.validate(fields(reference: "")), .missingReference)
        XCTAssertEqual(PotaSpot.validate(fields(reference: "USA-0817")), .badReference("USA-0817"))
        XCTAssertEqual(PotaSpot.validate(fields(kHz: 999)), .frequencyNotKHz)
        XCTAssertEqual(PotaSpot.validate(fields(kHz: 1000.5)), nil)
        XCTAssertEqual(
            PotaSpot.Problem.badReference("X").errorDescription,
            "X isn't a reference pota.app accepts — they look like US-0817."
        )
        XCTAssertEqual(
            PotaSpot.Problem.frequencyNotKHz.errorDescription,
            "pota.app takes the frequency in kilohertz, above 1000."
        )
    }

    // MARK: Wire

    /// Byte for byte: sorted keys, kHz as text, our own name as the source.
    func testTheJSONBodyIsTheFormsShape() throws {
        let data = try PotaSpot.jsonBody(fields(kHz: 14045.25, mode: "SSB", comments: "QSO party"))
        XCTAssertEqual(
            String(decoding: data, as: UTF8.self),
            #"{"activator":"KE5CW","comments":"QSO party","frequency":"14045.25","mode":"SSB","reference":"US-0817","source":"QSOPartyLogger","spotter":"KE5CW"}"#
        )
    }

    func testTheBodyNormalizesCallsTheReferenceAndTheMode() throws {
        let data = try PotaSpot.jsonBody(
            fields(activator: " ke5cw", spotter: "ke5cw ", reference: "k-4562@us-ca", mode: "cw ")
        )
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains(#""activator":"KE5CW""#), text)
        XCTAssertTrue(text.contains(#""spotter":"KE5CW""#), text)
        XCTAssertTrue(text.contains(#""reference":"K-4562""#), text)
        XCTAssertTrue(text.contains(#""mode":"CW""#), text)
    }

    /// A slash in a portable call must not be escaped into `\/`.
    func testSlashesInCallsAreNotEscaped() throws {
        let data = try PotaSpot.jsonBody(fields(activator: "W1AW/M"))
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains(#""activator":"W1AW/M""#))
    }

    // MARK: The board's answer

    private func board() throws -> [PotaSpot.BoardSpot] {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "pota_spots_sample", withExtension: "json")
        )
        return try XCTUnwrap(PotaSpot.board(from: try Data(contentsOf: url)))
    }

    /// The fixture is five rows copied verbatim from the live board.
    func testTheBoardParsesFromTheLivePayloadShape() throws {
        let rows = try board()
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.first?.activator, "W8EKM")
        XCTAssertEqual(rows.first?.reference, "US-6653")
        XCTAssertEqual(rows.first?.source, "Web")
        XCTAssertEqual(rows.first?.frequency, "21320")
        XCTAssertEqual(rows.map(\.source).last, "RBN")
    }

    func testOurSpotIsFoundByActivatorAndReference() throws {
        let rows = try board()
        XCTAssertTrue(PotaSpot.contains(fields(activator: "n4gbn", reference: "us-13340"), in: rows))
        XCTAssertFalse(PotaSpot.contains(fields(activator: "N4GBN", reference: "US-0001"), in: rows))
        XCTAssertFalse(PotaSpot.contains(fields(activator: "KE5CW", reference: "US-13340"), in: rows))
    }

    func testANonArrayBodyIsNotABoard() {
        XCTAssertNil(PotaSpot.board(from: Data("Invalid spot".utf8)))
        XCTAssertNil(PotaSpot.board(from: Data("{\"a\":1}".utf8)))
        XCTAssertEqual(PotaSpot.board(from: Data("[]".utf8)), [])
    }

    /// The form shows `e.response.data` as-is; so does the receipt, when it
    /// is a readable line.
    func testFailureTextIsTheServersOwnLineOrTheStatus() {
        XCTAssertEqual(
            PotaSpot.failureText(status: 400, body: Data("Invalid callsign\n".utf8)),
            "pota.app refused the spot: Invalid callsign"
        )
        XCTAssertEqual(
            PotaSpot.failureText(status: 502, body: Data("<html><body>Bad gateway".utf8)),
            "pota.app refused the spot (HTTP 502)."
        )
        XCTAssertEqual(PotaSpot.failureText(status: 500, body: Data()), "pota.app refused the spot (HTTP 500).")
    }
}

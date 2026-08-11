import XCTest
@testable import QSOPartyLogger

/// The ARS Bumblebee roster pipeline, over the real report page captured
/// 2026-08-10 (234 numbers — the July 2026 event's roster, still served
/// between events). Provenance: docs/research/fobb_rules.md §13.
final class FOBBRosterParserTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: ext),
            "\(name).\(ext) missing from Tests/Fixtures/CallHistory")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testConvertsTheBankedPage() throws {
        let html = try fixture("fobb-roster-page-2026-07", "html")
        let text = try XCTUnwrap(
            FOBBRosterParser.n1mmText(fromHTML: html, token: "FOBB ROSTER"))
        let lines = text.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines[0], "# FOBB ROSTER")
        XCTAssertTrue(lines.contains("!!Order!!,Call,Name,State,Exch1"))
        // Every bee twice: the bare call and the /BB form they sign with.
        XCTAssertTrue(lines.contains("K2SQS,FRANK,NJ,1"), "\(lines.prefix(8))")
        XCTAssertTrue(lines.contains("K2SQS/BB,FRANK,NJ,1"))
        XCTAssertTrue(lines.contains("W4KAC,KEN,NC,7"))
        XCTAssertTrue(lines.contains("K4KBL,JERRY,GA,234"))
        // A multi-word name keeps its internal spaces — only the emitted
        // format's own delimiters are stripped.
        XCTAssertTrue(lines.contains("AC6J,RYAN DORKOSKI,VA,4"))
        // One call under two numbers survives as two rows in each form.
        XCTAssertEqual(lines.filter { $0.hasPrefix("NN5DE,") }.count, 2)
        XCTAssertEqual(lines.filter { $0.hasPrefix("NN5DE/BB,") }.count, 2)
        // 234 numbers are issued, but #50 is an issued-and-unclaimed row —
        // number present, callsign, name and SPC all blank — so 233 bees
        // are offerable, each under two forms.
        let records = lines.filter { !$0.hasPrefix("#") && !$0.hasPrefix("!!") }
        XCTAssertEqual(records.count, 466)
    }

    /// A numbered row with no callsign is dropped rather than emitted as an
    /// empty entry. The sponsor's table carries exactly one (#50), and a
    /// record keyed on nothing would sit in the index matching nothing —
    /// or, worse, match a blank call field.
    func testANumberedRowWithNoCallsignIsDropped() throws {
        let html = try fixture("fobb-roster-page-2026-07", "html")
        let text = try XCTUnwrap(
            FOBBRosterParser.n1mmText(fromHTML: html, token: "FOBB ROSTER"))
        XCTAssertFalse(text.contains("\n,"), "no record may begin with an empty call")
        XCTAssertFalse(text.contains(",,,50\n"), "#50 is unclaimed in the banked table")
        XCTAssertTrue(text.contains(",49\n"), "its neighbours are unaffected")
        XCTAssertTrue(text.contains(",51\n"))
    }

    /// The store's declaration gate must accept the converted text, and the
    /// entries must be reachable under both spellings of a bee's call.
    func testConvertedTextPassesTheTokenGateAndIndexesBothForms() throws {
        let html = try fixture("fobb-roster-page-2026-07", "html")
        let text = try XCTUnwrap(
            FOBBRosterParser.n1mmText(fromHTML: html, token: "FOBB ROSTER"))
        let parsed = try XCTUnwrap(CallHistoryFile.parse(data: Data(text.utf8)))
        XCTAssertGreaterThan(parsed.recordCount, 0)

        // The gate reads the token alone, so the kind is immaterial here;
        // the party's real source shape is asserted in the party's own tests.
        let source = CallHistorySource(filePrefix: "FOBB", token: "FOBB ROSTER")
        XCTAssertTrue(source.isDeclared(inCommentTokens: parsed.tokens))

        XCTAssertNotNil(parsed.entry(for: "W4KAC"), "the bare call")
        XCTAssertNotNil(parsed.entry(for: "W4KAC/BB"), "the form bees sign with")
    }

    /// Drift fails loudly: no header row is nil, a renamed header is nil,
    /// and a header with no rows under it is nil.
    func testUnrecognizedMarkupIsNil() {
        XCTAssertNil(FOBBRosterParser.n1mmText(
            fromHTML: "<html><body><p>maintenance</p></body></html>",
            token: "FOBB ROSTER"))

        let renamed = """
        <table><tr><th>Number</th><th>Call</th><th>Name</th><th>SPC</th>\
        <th>Where</th></tr><tr><td>1</td><td>K2SQS</td><td>Frank</td>\
        <td>NJ</td><td>park</td></tr></table>
        """
        XCTAssertNil(FOBBRosterParser.n1mmText(fromHTML: renamed, token: "T"))

        let headerOnly = """
        <table><tr><th>BB</th><th>Callsign</th><th>Name</th><th>SPC</th>\
        <th>Expected Location</th></tr></table>
        """
        XCTAssertNil(FOBBRosterParser.n1mmText(fromHTML: headerOnly, token: "T"))
    }

    /// A heading table above the roster does not hide it — the header row is
    /// found rather than assumed to be first.
    func testAPrecedingTableDoesNotHideTheRoster() throws {
        let html = """
        <table><tr><td>Home</td><td>Rules</td></tr></table>
        <table><tr><td><font face="Arial">BB</font></td>\
        <td><font face="Arial">Callsign</font></td>\
        <td><font face="Arial">Name</font></td>\
        <td><font face="Arial">SPC</font></td>\
        <td><font face="Arial">Expected Location</font></td></tr>
        <tr><td>1</td><td>K2SQS</td><td>Frank</td><td>NJ</td><td>Local park</td></tr>
        </table>
        """
        let text = try XCTUnwrap(FOBBRosterParser.n1mmText(fromHTML: html, token: "T"))
        XCTAssertTrue(text.contains("K2SQS,FRANK,NJ,1"), text)
    }
}

import XCTest
@testable import QSOPartyLogger

/// The Skeeter Hunt roster pipeline, over the real artifacts captured
/// 2026-08-04: W2LJ's page (the roster link discovery) and the roster
/// sheet's CSV (the conversion to call-history text). Provenance:
/// docs/research/skeeter_rules.md §13.
final class SkeeterRosterParserTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: ext),
            "\(name).\(ext) missing from Tests/Fixtures/CallHistory")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Finding the roster link

    /// The page links a dozen years of *scoreboard* spreadsheets; the roster
    /// is the one whose surrounding text names it. The 2026 document id is
    /// the assertion — a scoreboard id coming back here is the failure this
    /// parser exists to prevent.
    func testFindsTheRosterSheetAmongTheScoreboards() throws {
        let html = try fixture("w2lj-skeeter-page-2026-08-04", "html")
        XCTAssertEqual(
            SkeeterRosterParser.rosterSheetURL(inPageHTML: html),
            "https://docs.google.com/spreadsheets/d/"
                + "17QjNLUKwkfC2T8_NQEG1Ny7Y4a-BBqtv/export?format=csv"
        )
    }

    /// A page with spreadsheet links but no roster phrasing is an explicit
    /// nothing — never "the first sheet will do".
    func testAPageWithoutARosterLinkIsNil() {
        let scoreboardOnly = """
        <p>2025 Scoreboard - click
        <a href="https://docs.google.com/spreadsheets/d/1_aNsVnye/edit">here</a></p>
        """
        XCTAssertNil(SkeeterRosterParser.rosterSheetURL(inPageHTML: scoreboardOnly))
        XCTAssertNil(SkeeterRosterParser.rosterSheetURL(inPageHTML: "<html></html>"))
    }

    // MARK: Converting the CSV

    /// The whole live sheet as captured: 187 assigned numbers convert; the
    /// 43 pre-numbered blank rows and the trailing scoreboard emptiness do
    /// not. The count is exact because the fixture is frozen (Article 2's
    /// hard-count idiom).
    func testRealRosterConvertsWhole() throws {
        let csv = try fixture("skeeter-roster-2026-08-04", "csv")
        let text = try XCTUnwrap(
            SkeeterRosterParser.n1mmText(fromCSV: csv, token: "SKEETER ROSTER"))
        let parsed = CallHistoryFile.parse(text)
        XCTAssertEqual(parsed.recordCount, 187)

        // The comment token is what CallHistorySource.isDeclared verifies.
        let source = CallHistorySource(
            filePrefix: "SKEETER", token: "SKEETER ROSTER",
            kind: .w2ljRosterPage, pageURL: "https://example.test/")
        XCTAssertTrue(source.isDeclared(inCommentTokens: parsed.tokens))

        // Spot checks from the sponsor's own sheet: the manager's
        // traditional number, and this app's own operator.
        XCTAssertEqual(parsed.entry(for: "W2LJ")?.locations, ["13", "NJ"],
                       "number in Exch1, S/P/C in State — and ' W2LJ ' trimmed")
        XCTAssertEqual(parsed.entry(for: "W2LJ")?.name, "LARRY")
        XCTAssertEqual(parsed.entry(for: "KE5CW")?.locations, ["20", "TX"])
        XCTAssertEqual(parsed.entry(for: "KE5CW")?.name, "TOM")
    }

    /// Sheet quirks observed live: one call under two numbers (K3UT, #25 and
    /// #183 — later wins, the parser's ordinary overwrite), and a stray
    /// comma in an S/P/C cell (",SC"), which must not shift columns in the
    /// emitted text.
    func testSheetQuirksSurviveConversion() throws {
        let csv = try fixture("skeeter-roster-2026-08-04", "csv")
        let text = try XCTUnwrap(
            SkeeterRosterParser.n1mmText(fromCSV: csv, token: "SKEETER ROSTER"))
        let parsed = CallHistoryFile.parse(text)
        XCTAssertEqual(parsed.entry(for: "K3UT")?.locations.first, "183")
        XCTAssertFalse(
            text.contains(",,SC"),
            "a delimiter inside a cell must be stripped, not emitted")
    }

    /// A sheet that is not the observed shape converts to nothing — loudly,
    /// not as an empty install.
    func testForeignShapesConvertToNil() {
        XCTAssertNil(SkeeterRosterParser.n1mmText(
            fromCSV: "Call,Number\nW2LJ,13", token: "T"),
            "missing the header row observed on the live sheet")
        XCTAssertNil(SkeeterRosterParser.n1mmText(
            fromCSV: "Skeeter #,Call,Name,S/P/C\n , , , ", token: "T"),
            "no assigned numbers, nothing to install")
        XCTAssertNil(SkeeterRosterParser.n1mmText(fromCSV: "", token: "T"))
    }

    // MARK: The CSV reader

    /// The sheet's scoreboard columns use quoted cells with commas in them
    /// ("5th Place - High Score IA, High Score SSB") — a naive comma split
    /// misreads real rows.
    func testQuotedFieldsHoldCommasAndDoubledQuotes() {
        let rows = SkeeterRosterParser.parseCSV(
            "a,\"b, c\",\"say \"\"hi\"\"\"\r\nd,e,f\n")
        XCTAssertEqual(rows, [["a", "b, c", "say \"hi\""], ["d", "e", "f"]])
    }

    func testBlankRowsAreDropped() {
        let rows = SkeeterRosterParser.parseCSV("a,b\n , \n\nc,d\n")
        XCTAssertEqual(rows, [["a", "b"], ["c", "d"]])
    }
}

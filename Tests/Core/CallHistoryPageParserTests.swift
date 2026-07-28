import XCTest
@testable import QSOPartyLogger

/// The n1mmwp.hamdocs.com pages, tested against captures from 2026-07-28
/// (`Tests/Fixtures/CallHistory/*.html`). Positional reads of somebody
/// else's markup: a reshaped page must come back `nil`, never as a silent
/// zero that reads as "no file this year".
final class CallHistoryPageParserTests: XCTestCase {

    private func fixture(_ name: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "html"),
                                "missing fixture \(name).html")
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: Listing

    /// The real Alabama search: three revisions, newest first.
    func testParsesTheAlabamaSearchListing() throws {
        let listings = try XCTUnwrap(CallHistoryPageParser.parseListing(
            html: fixture("listing-qsop_al-2026-07-28")))
        XCTAssertEqual(listings.count, 3)
        XCTAssertEqual(listings[0].filename, "QSOP_AL-2026-002.txt")
        XCTAssertEqual(listings[0].pageURL,
                       "https://n1mmwp.hamdocs.com/mmfiles/qsop_al-2026-002-txt/")
        XCTAssertEqual(listings[0].listedDate, "2026-07-15")
        XCTAssertEqual(listings[1].filename, "QSOP_AL-2026-001.txt")
        XCTAssertEqual(listings[2].filename, "QSOP_AL-2025.txt",
                       "sort=newest puts last season at the bottom")
    }

    /// A search with no matches is a recognized page with zero rows — the
    /// difference between "no file exists" and "the site changed".
    func testEmptySearchIsEmptyNotNil() throws {
        let listings = CallHistoryPageParser.parseListing(
            html: try fixture("listing-empty-2026-07-28"))
        XCTAssertEqual(listings, [])
    }

    func testUnrecognizedPageIsNil() {
        XCTAssertNil(CallHistoryPageParser.parseListing(
            html: "<html><body>Maintenance</body></html>"))
    }

    /// The newest *claimed* file is the first row the source claims — rows
    /// for other parties (or a redesign's stray titles) are passed over.
    func testFirstClaimedRowWins() throws {
        let listings = try XCTUnwrap(CallHistoryPageParser.parseListing(
            html: fixture("listing-qsop_al-2026-07-28")))
        let source = CallHistorySource(filePrefix: "QSOP_AL", token: "QSOPARTY AL")
        let newest = listings.first { source.claims(fileNamed: $0.filename) }
        XCTAssertEqual(newest?.filename, "QSOP_AL-2026-002.txt")
        let wrongParty = CallHistorySource(filePrefix: "QSOP_TX", token: nil)
        XCTAssertNil(listings.first { wrongParty.claims(fileNamed: $0.filename) })
    }

    // MARK: File page

    /// The real Alabama file page: the CMDM form, its nonce and its id. The
    /// nonce is per-capture — the values pinned here are the fixture's own.
    func testParsesTheDownloadForm() throws {
        let form = try XCTUnwrap(CallHistoryPageParser.parseFilePage(
            html: fixture("filepage-qsop_al-2026-002-2026-07-28")))
        XCTAssertEqual(form.action,
                       "https://n1mmwp.hamdocs.com/mmfile/get/file/QSOP_AL-2026-002.txt")
        XCTAssertEqual(form.nonce, "bceeca58da")
        XCTAssertEqual(form.id, "240858")
    }

    func testFilePageWithoutTheFormIsNil() throws {
        XCTAssertNil(CallHistoryPageParser.parseFilePage(
            html: try fixture("listing-empty-2026-07-28")),
            "a listing page is not a file page")
        XCTAssertNil(CallHistoryPageParser.parseFilePage(html: "<html></html>"))
    }
}

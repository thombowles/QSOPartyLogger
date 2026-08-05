import XCTest
@testable import QSOPartyLogger

/// What the log's Sent and Rcvd columns read for each exchange shape.
///
/// The columns used to be `"\(rstSent) \(myLoc)"` unconditionally, which put a
/// signal report on the ten bundled parties that do not exchange one — an NAQP
/// row logged as "TOM TX" displayed as "599 TX", and the operator's name, the
/// half of the exchange the sponsor actually scores, was nowhere in the log.
final class ExchangeSummaryTests: XCTestCase {

    var seq: TimeInterval = 0
    func qso(
        my: String = "ALL",
        their: String = "TX",
        rstSent: String = "599",
        rstRcvd: String = "599",
        serialSent: Int? = nil,
        serialRcvd: Int? = nil,
        nameSent: String? = nil,
        nameRcvd: String? = nil
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + seq),
            call: "N2CU", band: .m40, modeClass: .cw, rawMode: "CW",
            rstSent: rstSent, rstRcvd: rstRcvd,
            serialSent: serialSent, serialRcvd: serialRcvd,
            nameSent: nameSent, nameRcvd: nameRcvd,
            myLoc: my, theirLoc: their
        )
    }

    /// A minimal party carrying whichever exchange flags the case needs.
    func party(_ extra: String = "") throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"n","name":"N","cabrilloContest":"N","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[{"abbr":"ALL","name":"Allen"}]\(extra)}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    // MARK: The 38 parties that do exchange a report

    func testReportPartyReadsReportThenLocation() throws {
        let p = try party()
        let q = qso(my: "ALL", their: "TX", rstSent: "599", rstRcvd: "579")
        XCTAssertEqual(ExchangeSummary.sent(q, party: p), "599 ALL")
        XCTAssertEqual(ExchangeSummary.received(q, party: p), "579 TX")
    }

    // MARK: Name exchanges — NAQP, MNQP

    func testNamePartyReadsNameThenLocationAndNoReport() throws {
        let p = try party(",\"exchangeIncludesName\":true,\"exchangeIncludesRST\":false")
        let q = qso(my: "TX", their: "NY", nameSent: "TOM", nameRcvd: "BILL")
        XCTAssertEqual(ExchangeSummary.sent(q, party: p), "TOM TX")
        XCTAssertEqual(ExchangeSummary.received(q, party: p), "BILL NY")
    }

    /// The report is still on the row — every row carries a mode default — and
    /// must not leak into a column for a party that never sent one.
    func testNamePartyNeverShowsTheRowsUnusedReport() throws {
        let p = try party(",\"exchangeIncludesName\":true,\"exchangeIncludesRST\":false")
        let q = qso(rstSent: "599", rstRcvd: "599", nameSent: "TOM", nameRcvd: "BILL")
        XCTAssertFalse(ExchangeSummary.sent(q, party: p).contains("599"))
        XCTAssertFalse(ExchangeSummary.received(q, party: p).contains("599"))
    }

    /// A log opened before a contest name was set has no sent name. The column
    /// shows what the row holds — the location alone, with no orphan spacing.
    func testMissingNameLeavesTheLocationAlone() throws {
        let p = try party(",\"exchangeIncludesName\":true,\"exchangeIncludesRST\":false")
        let q = qso(my: "TX", their: "NY", nameSent: nil, nameRcvd: nil)
        XCTAssertEqual(ExchangeSummary.sent(q, party: p), "TX")
        XCTAssertEqual(ExchangeSummary.received(q, party: p), "NY")
    }

    // MARK: Serial exchanges — CQP, PAQP, VAQP

    func testSerialPartyReadsNumberThenLocation() throws {
        let p = try party(",\"exchangeIncludesSerial\":true,\"exchangeIncludesRST\":false")
        let q = qso(my: "ALL", their: "TX", serialSent: 1, serialRcvd: 47)
        XCTAssertEqual(ExchangeSummary.sent(q, party: p), "1 ALL")
        XCTAssertEqual(ExchangeSummary.received(q, party: p), "47 TX")
    }

    // MARK: Location-only exchanges — MDC, IdQP, NCQP, WIQP

    func testLocationOnlyPartyReadsTheLocationAlone() throws {
        let p = try party(",\"exchangeIncludesRST\":false")
        let q = qso(my: "ALL", their: "TX")
        XCTAssertEqual(ExchangeSummary.sent(q, party: p), "ALL")
        XCTAssertEqual(ExchangeSummary.received(q, party: p), "TX")
    }

    // MARK: Combinations the schema allows

    /// No bundled party sends all three, but the flags are independent and a
    /// future sponsor may. Order follows the entry row: report, number, name,
    /// location — so the log reads back the way the operator typed it.
    func testEveryElementReadsInEntryOrder() throws {
        let p = try party(",\"exchangeIncludesSerial\":true,\"exchangeIncludesName\":true")
        let q = qso(my: "ALL", their: "TX", serialSent: 3, serialRcvd: 9,
                    nameSent: "TOM", nameRcvd: "BILL")
        XCTAssertEqual(ExchangeSummary.sent(q, party: p), "599 3 TOM ALL")
        XCTAssertEqual(ExchangeSummary.received(q, party: p), "599 9 BILL TX")
    }

    // MARK: No definition to read

    /// A log whose party id is not in the catalog has no flags to consult, so
    /// the row is the only evidence of its own shape — same precedence the
    /// Cabrillo ex1 element uses: a name, else a number, else the report.
    func testUnknownPartyFallsBackToTheRowsOwnShape() {
        let named = qso(my: "TX", their: "NY", nameSent: "TOM", nameRcvd: "BILL")
        XCTAssertEqual(ExchangeSummary.sent(named, party: nil), "TOM TX")
        XCTAssertEqual(ExchangeSummary.received(named, party: nil), "BILL NY")

        let numbered = qso(serialSent: 1, serialRcvd: 47)
        XCTAssertEqual(ExchangeSummary.sent(numbered, party: nil), "1 ALL")
        XCTAssertEqual(ExchangeSummary.received(numbered, party: nil), "47 TX")

        let reported = qso(rstSent: "599", rstRcvd: "579")
        XCTAssertEqual(ExchangeSummary.sent(reported, party: nil), "599 ALL")
        XCTAssertEqual(ExchangeSummary.received(reported, party: nil), "579 TX")
    }

    // MARK: The bundled parties themselves

    /// Read through the real definitions, so a flag flip in a party file shows
    /// up here rather than only on the air.
    func testBundledPartiesRenderTheirOwnExchange() throws {
        let catalog = PartyCatalog.loadBundled()
        func party(_ id: String) throws -> PartyDefinition {
            try XCTUnwrap(catalog.first { $0.id == id }, "\(id) is not bundled")
        }

        let naqp = qso(my: "TX", their: "NY", nameSent: "TOM", nameRcvd: "BILL")
        XCTAssertEqual(ExchangeSummary.sent(naqp, party: try party("naqpcw")), "TOM TX")
        XCTAssertEqual(ExchangeSummary.received(naqp, party: try party("naqpcw")), "BILL NY")

        let cqp = qso(my: "SCLA", their: "TX", serialSent: 1, serialRcvd: 47)
        XCTAssertEqual(ExchangeSummary.sent(cqp, party: try party("cqp")), "1 SCLA")
        XCTAssertEqual(ExchangeSummary.received(cqp, party: try party("cqp")), "47 TX")

        let mdc = qso(my: "WDC", their: "TX")
        XCTAssertEqual(ExchangeSummary.sent(mdc, party: try party("mdc")), "WDC")
        XCTAssertEqual(ExchangeSummary.received(mdc, party: try party("mdc")), "TX")

        let tqp = qso(my: "HRRS", their: "OK")
        XCTAssertEqual(ExchangeSummary.sent(tqp, party: try party("tqp")), "599 HRRS")
        XCTAssertEqual(ExchangeSummary.received(tqp, party: try party("tqp")), "599 OK")
    }

    /// The parties whose columns this changed, named so a party cannot lose its
    /// report incidentally — each flag flip is its own commit.
    func testWhichPartiesExchangeNoReport() {
        let silent = PartyCatalog.loadBundled()
            .filter { !$0.exchangeIncludesRST }
            .map(\.id)
        XCTAssertEqual(
            silent,
            ["cqp", "idqp", "mdc", "mnqp", "naqpcw", "naqpssb", "ncqp", "paqp", "vaqp", "wiqp"]
        )
    }
}

import XCTest
@testable import QSOPartyLogger

final class CountyLineExpanderTests: XCTestCase {

    func entry(call: String = "W0BH") -> CountyLineExpander.QSOEntry {
        CountyLineExpander.QSOEntry(
            call: call,
            rstSent: "599",
            rstRcvd: "599",
            band: .m20,
            modeClass: .cw,
            rawMode: "CW",
            freqKHz: 14042,
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000)
        )
    }

    func testSimpleContactOneRow() {
        let rows = CountyLineExpander.expand(entry: entry(), myLocs: ["TX"], theirLocs: ["MRN"])
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].myLoc, "TX")
        XCTAssertEqual(rows[0].theirLoc, "MRN")
    }

    func testTheirCountyLineTwoRows() {
        let rows = CountyLineExpander.expand(entry: entry(), myLocs: ["TX"], theirLocs: ["LIN", "AND"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.theirLoc), ["LIN", "AND"])
        XCTAssertEqual(Set(rows.map(\.groupID)).count, 1, "rows share one groupID")
        XCTAssertEqual(Set(rows.map(\.id)).count, 2, "rows have distinct ids")
    }

    func testMyCountyLineTwoRows() {
        let rows = CountyLineExpander.expand(entry: entry(), myLocs: ["MRN", "CHS"], theirLocs: ["TX"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.map(\.myLoc), ["MRN", "CHS"])
        XCTAssertEqual(Set(rows.map(\.theirLoc)), ["TX"])
    }

    func testBothOnCountyLinesFourRows() {
        let rows = CountyLineExpander.expand(
            entry: entry(),
            myLocs: ["MRN", "CHS"],
            theirLocs: ["LIN", "AND"]
        )
        XCTAssertEqual(rows.count, 4)
        let pairs = rows.map { "\($0.myLoc)-\($0.theirLoc)" }
        XCTAssertEqual(pairs, ["MRN-LIN", "MRN-AND", "CHS-LIN", "CHS-AND"])
        XCTAssertEqual(Set(rows.map(\.groupID)).count, 1)
    }

    func testSeparateContactsGetSeparateGroupIDs() {
        let a = CountyLineExpander.expand(entry: entry(), myLocs: ["TX"], theirLocs: ["LIN"])
        let b = CountyLineExpander.expand(entry: entry(), myLocs: ["TX"], theirLocs: ["LIN"])
        XCTAssertNotEqual(a[0].groupID, b[0].groupID)
    }

    func testEntryFieldsCopiedToEveryRow() {
        let rows = CountyLineExpander.expand(entry: entry(call: "KS0KS"), myLocs: ["MRN", "CHS"], theirLocs: ["MO"])
        for row in rows {
            XCTAssertEqual(row.call, "KS0KS")
            XCTAssertEqual(row.band, .m20)
            XCTAssertEqual(row.modeClass, .cw)
            XCTAssertEqual(row.freqKHz, 14042)
            XCTAssertEqual(row.rstSent, "599")
        }
    }
}

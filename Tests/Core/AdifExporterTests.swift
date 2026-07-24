import XCTest
@testable import QSOPartyLogger

final class AdifExporterTests: XCTestCase {

    var ksqp: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
    }

    let t = Date(timeIntervalSince1970: 1_788_013_920)  // 2026-08-29 14:32:00Z

    func makeLog() -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        log.qsos = [
            QSO(
                timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: 14042, rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"
            )
        ]
        return log
    }

    func testHeader() {
        let text = AdifExporter.export(log: makeLog(), party: ksqp)
        XCTAssertTrue(text.contains("<adif_ver:5>3.1.4"))
        XCTAssertTrue(text.contains("<programid:14>QSOPartyLogger"))
        XCTAssertTrue(text.contains("<eoh>"))
    }

    func testRecordFields() {
        let text = AdifExporter.export(log: makeLog(), party: ksqp)
        XCTAssertTrue(text.contains("<qso_date:8>20260829"))
        XCTAssertTrue(text.contains("<time_on:6>143200"))
        XCTAssertTrue(text.contains("<call:4>W0BH"))
        XCTAssertTrue(text.contains("<band:3>20m"))
        XCTAssertTrue(text.contains("<freq:9>14.042000"))
        XCTAssertTrue(text.contains("<mode:2>CW"))
        XCTAssertTrue(text.contains("<rst_sent:3>599"))
        XCTAssertTrue(text.contains("<stx_string:2>TX"))
        XCTAssertTrue(text.contains("<srx_string:3>MRN"))
        XCTAssertTrue(text.contains("<contest_id:12>KS-QSO-PARTY"))
        XCTAssertTrue(text.contains("<cnty:9>KS,Marion"))
        XCTAssertTrue(text.contains("<state:2>KS"))
        XCTAssertTrue(text.contains("<my_state:2>TX"))
        XCTAssertTrue(text.contains("<station_callsign:5>KE5CW"))
        XCTAssertTrue(text.contains("<eor>"))
    }

    func testOutOfStateTheirLocEmitsStateNoCounty() {
        var log = makeLog()
        log.myLocation = .inState(counties: ["MRN"])
        log.qsos = [
            QSO(
                timestampUTC: t, call: "K5XYZ", band: .m20, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, rstSent: "599", rstRcvd: "599", myLoc: "MRN", theirLoc: "TX"
            )
        ]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertTrue(text.contains("<state:2>TX"))
        XCTAssertFalse(text.contains("<cnty:"))
        XCTAssertTrue(text.contains("<my_cnty:9>KS,Marion"))
        XCTAssertTrue(text.contains("<my_state:2>KS"))
        XCTAssertFalse(text.contains("<freq:"), "no freq field when unknown")
    }

    func testRecordCountMatchesRows() {
        var log = makeLog()
        log.qsos = CountyLineExpander.expand(
            entry: .init(
                call: "W0BH", rstSent: "599", rstRcvd: "599", band: .m20,
                modeClass: .cw, rawMode: "CW", freqKHz: 14042, timestampUTC: t
            ),
            myLocs: ["TX"], theirLocs: ["LIN", "AND"]
        )
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 2)
        XCTAssertEqual(
            text.components(separatedBy: "app_qsopartylogger_groupid").count - 1, 2,
            "group id present on both rows"
        )
    }

    func testFieldLengthUsesUTF8Bytes() {
        XCTAssertEqual(AdifExporter.field("name", "café"), "<name:5>café ")
        XCTAssertEqual(AdifExporter.field("x", ""), "")
    }

    func testSSBNormalization() {
        XCTAssertEqual(AdifExporter.adifMode("USB"), "SSB")
        XCTAssertEqual(AdifExporter.adifMode("LSB"), "SSB")
        XCTAssertEqual(AdifExporter.adifMode("RTTY"), "RTTY")
    }
}

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

    // MARK: POTA

    /// The whole existing suite is the byte-identity guarantee for non-POTA
    /// logs; this pins the absence of the six new fields. "<sig" would also
    /// match nothing else: "station_callsign" contains "sig" but not "<sig".
    func testNoParksEmitsNoPotaFieldsAndOneRecord() {
        let text = AdifExporter.export(log: makeLog(), party: ksqp)
        XCTAssertFalse(text.contains("<my_sig"))
        XCTAssertFalse(text.contains("<sig"))
        XCTAssertFalse(text.contains("pota_ref"))
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 1)
    }

    func testActivationStampsTheMySigTripletOnTheRecord() {
        var log = makeLog()
        log.qsos[0].myPotaRefs = ["US-3315"]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertTrue(text.contains("<my_sig:4>POTA"))
        XCTAssertTrue(text.contains("<my_sig_info:7>US-3315"))
        XCTAssertTrue(text.contains("<my_pota_ref:7>US-3315"))
        XCTAssertFalse(text.contains("<sig:"), "no P2P side on this row")
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 1)
    }

    /// POTA's park-to-park reference: "list the same QSO three times in the
    /// ADIF log file, each with one of the three park references in
    /// SIG_INFO, with the rest unchanged."
    func testWorkingAThreeFerDuplicatesTheRecordPerPark() {
        var log = makeLog()
        log.qsos[0].myPotaRefs = ["US-3315"]
        log.qsos[0].theirPotaRefs = ["US-0088", "US-0119", "US-0705"]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: "<sig:4>POTA").count - 1, 3)
        for park in ["US-0088", "US-0119", "US-0705"] {
            XCTAssertTrue(text.contains("<sig_info:7>\(park)"))
            XCTAssertTrue(text.contains("<pota_ref:7>\(park)"))
        }
        // "with the rest unchanged" — every copy repeats the QSO's facts.
        XCTAssertEqual(text.components(separatedBy: "<call:4>W0BH").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: "<time_on:6>143200").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: "<my_sig_info:7>US-3315").count - 1, 3)
    }

    /// My two-fer working their two-fer: the cross product, each record
    /// naming exactly one (mine, theirs) pair — no record contradicts
    /// itself. `field()` writes a trailing space, so adjacency is testable.
    func testTwoFerWorkingATwoFerEmitsTheCrossProduct() {
        var log = makeLog()
        log.qsos[0].myPotaRefs = ["US-3315", "US-4571"]
        log.qsos[0].theirPotaRefs = ["US-0088", "US-0119"]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 4)
        for (mine, theirs) in [("US-3315", "US-0088"), ("US-3315", "US-0119"),
                               ("US-4571", "US-0088"), ("US-4571", "US-0119")] {
            XCTAssertTrue(text.contains(
                "<my_sig:4>POTA <my_sig_info:7>\(mine) <my_pota_ref:7>\(mine) "
                + "<sig:4>POTA <sig_info:7>\(theirs) <pota_ref:7>\(theirs) "),
                "missing pair \(mine) × \(theirs)")
        }
    }

    /// County-line rows each carry the parks (the expander stamps every row
    /// of the contact), and each emits its own park-stamped record.
    func testCountyLineRowsEachCarryThePark() {
        var log = makeLog()
        let counties = ksqp.counties.prefix(2).map(\.abbr)
        log.myLocation = .inState(counties: Array(counties))
        log.qsos = CountyLineExpander.expand(
            entry: .init(call: "W0BH", rstSent: "599", rstRcvd: "599",
                         myPotaRefs: ["US-3315"],
                         band: .m20, modeClass: .cw, rawMode: "CW",
                         freqKHz: nil, timestampUTC: t),
            myLocs: Array(counties), theirLocs: ["TX"])
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 2)
        XCTAssertEqual(text.components(separatedBy: "<my_sig_info:7>US-3315").count - 1, 2)
    }
}

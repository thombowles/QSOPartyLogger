import XCTest
@testable import QSOPartyLogger

/// The POTA row's State and Notes (operator reports 1 of 4, 2026-08-25):
/// their state rides the rcvd map under the well-known `state` id, notes are
/// an additive stored field — both invisible to ScoreEngine, both plain ADIF.
final class PotaFieldsTests: XCTestCase {

    private func qso(state: String? = "MO", notes: String? = "2-fer, rain") -> QSO {
        var q = QSO(call: "W0ABC", band: .m20, modeClass: .cw, rawMode: "CW",
                    sent: [ExchangeElementID.rst: "599"],
                    rcvd: [ExchangeElementID.rst: "599"],
                    myPotaRefs: ["US-1111"])
        q.theirState = state
        q.notes = notes
        return q
    }

    func testAccessorsRoundTripAndAbsentWritesNoKey() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601

        let reread = try decoder.decode(QSO.self, from: encoder.encode(qso()))
        XCTAssertEqual(reread.theirState, "MO")
        XCTAssertEqual(reread.notes, "2-fer, rain")

        var plain = qso(state: nil, notes: nil)
        plain.theirState = nil
        let text = String(decoding: try encoder.encode(plain), as: UTF8.self)
        XCTAssertFalse(text.contains("notes"), "absent notes write no key")
        XCTAssertFalse(text.contains("state"), "absent state writes no key")
    }

    func testAdifCarriesStateAndComment() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        log.qsos = [qso()]
        let text = AdifExporter.export(log: log, contest: contest)
        XCTAssertTrue(text.contains("<state:2>MO"))
        XCTAssertTrue(text.contains("<comment:11>2-fer, rain"))
    }

    func testTypedStateOutranksTheCallbookStamp() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        var q = qso(state: "MO", notes: nil)
        q.callbook = QSO.CallbookStamp(name: "Bob", qth: nil, state: "VT",
                                       grid: nil, source: "QRZ")
        log.qsos = [q]
        let text = AdifExporter.export(log: log, contest: contest)
        XCTAssertTrue(text.contains("<state:2>MO"), "what he copied wins")
        XCTAssertFalse(text.contains("<state:2>VT"))
        XCTAssertEqual(text.components(separatedBy: "<state:").count - 1, 1,
                       "state is written exactly once")
    }

    func testCallbookStateStillFillsWhereNothingWasTyped() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        var q = qso(state: nil, notes: nil)
        q.callbook = QSO.CallbookStamp(name: nil, qth: nil, state: "VT",
                                       grid: nil, source: "QRZ")
        log.qsos = [q]
        XCTAssertTrue(AdifExporter.export(log: log, contest: contest)
            .contains("<state:2>VT"))
    }

    func testPartyExportsAreUntouchedByAStrayState() throws {
        // A party row's state comes from its exchange location, never from
        // this field — the location machinery stays the only author there.
        let ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        var q = QSO(timestampUTC: Date(timeIntervalSince1970: 0), call: "W0BH",
                    band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN")
        q.notes = "great signal"
        log.qsos = [q]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertTrue(text.contains("<state:2>KS"), "the county's state, as always")
        XCTAssertTrue(text.contains("<comment:12>great signal"),
                      "notes export from any log that has them")
    }
}

import XCTest
@testable import QSOPartyLogger

/// The lookup enrichment sidecar (spec 2026-08-25 decision 5): additive on
/// QSO, structurally invisible to ScoreEngine, emitted as plain ADIF fields
/// — and on-air data always outranks it.
final class CallbookStampTests: XCTestCase {

    private func stamped() -> QSO {
        var q = QSO(call: "W1AW", band: .m20, modeClass: .cw, rawMode: "CW",
                    sent: [ExchangeElementID.rst: "599"],
                    rcvd: [ExchangeElementID.rst: "599"],
                    myPotaRefs: ["US-1111"])
        q.callbook = QSO.CallbookStamp(name: "Bob", qth: "Newington",
                                       state: "CT", grid: "FN31pr",
                                       source: "QRZ")
        return q
    }

    func testSidecarRoundTripsAndOldRowsDecodeNil() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reread = try decoder.decode(QSO.self, from: encoder.encode(stamped()))
        XCTAssertEqual(reread.callbook?.name, "Bob")

        var plain = stamped(); plain.callbook = nil
        let rereadPlain = try decoder.decode(QSO.self, from: encoder.encode(plain))
        XCTAssertNil(rereadPlain.callbook)
        XCTAssertFalse(String(decoding: try encoder.encode(plain), as: UTF8.self)
            .contains("callbook"), "absent writes no key — old builds unaffected")
    }

    func testAdifEmitsTheStampInAPotaLog() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        log.qsos = [stamped()]
        let text = AdifExporter.export(log: log, contest: contest)
        XCTAssertTrue(text.contains("<name:3>BOB"))
        XCTAssertTrue(text.contains("<qth:9>Newington"))
        XCTAssertTrue(text.contains("<state:2>CT"))
        XCTAssertTrue(text.contains("<gridsquare:6>FN31pr"))
    }

    func testStampNeverOverridesOnAirData() throws {
        // A name party's copied name outranks the callbook's, and the
        // exchange's state outranks the callbook's state.
        let naqp = try XCTUnwrap(PartyCatalog.party(id: "naqpcw"))
        var log = ContestLog(partyID: "naqpcw")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        var q = QSO(timestampUTC: Date(timeIntervalSince1970: 0), call: "W1AW",
                    band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "599",
                    nameRcvd: "MARK", myLoc: "TX", theirLoc: "CT")
        q.callbook = QSO.CallbookStamp(name: "Bob", qth: nil, state: "VT",
                                       grid: nil, source: "QRZ")
        log.qsos = [q]
        let text = AdifExporter.export(log: log, party: naqp)
        XCTAssertTrue(text.contains("<name:4>MARK"), "copied on the air, wins")
        XCTAssertFalse(text.contains("BOB"))
        XCTAssertTrue(text.contains("<state:2>CT"), "the exchange's state wins")
        XCTAssertFalse(text.contains("<state:2>VT"))
    }
}

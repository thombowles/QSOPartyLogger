import XCTest
@testable import QSOPartyLogger

/// The dashboard's year of POTA, computed pure from program records: each
/// outing's park-days (unique-ten validity, the same strict reading as
/// `PotaStats`), P2P, states and DX, and the season rollup that unions —
/// never double-counts — across outings.
final class PotaSeasonTests: XCTestCase {

    private let t0 = Date(timeIntervalSince1970: 1_770_000_000)  // 2026-02-02 02:40Z

    private func qso(
        _ call: String,
        park: String? = nil,
        theirPark: String? = nil,
        state: String? = nil,
        callbookState: String? = nil,
        band: Band = .m20,
        mode: ModeClass = .cw,
        group: UUID = UUID(),
        offset: TimeInterval = 0
    ) -> QSO {
        var q = QSO(
            groupID: group,
            timestampUTC: t0.addingTimeInterval(offset),
            call: call,
            band: band,
            modeClass: mode,
            rawMode: mode == .cw ? "CW" : "SSB",
            rstSent: "599",
            rstRcvd: "599",
            myPotaRefs: park.map { [$0] },
            theirPotaRefs: theirPark.map { [$0] },
            myLoc: "",
            theirLoc: ""
        )
        q.theirState = state
        if let callbookState {
            q.callbook = QSO.CallbookStamp(state: callbookState, source: "QRZ")
        }
        return q
    }

    private func record(qsos: [QSO], call: String = "KE5CW") -> ContestRecord {
        var log = ContestLog(partyID: "pota")
        log.station.callsign = call
        log.myLocation = .outOfState(location: "MO")
        log.qsos = qsos
        log.setupCompleted = true
        return ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.best(for: log),
            updatedAt: t0,
            sourceFileName: "x.qplog",
            program: true
        )!
    }

    /// A contest log worked from a park: a party record, not a program one —
    /// no outing in its identity — whose park contacts the POTA side counts.
    private func contestRecord(qsos: [QSO], partyID: String = "ksqp") -> ContestRecord {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = "KE5CW"
        log.myLocation = .inState(counties: ["JOH"])
        log.qsos = qsos
        log.setupCompleted = true
        return ContestRecord.make(
            from: log,
            snapshot: ScoreSnapshot.best(for: log),
            updatedAt: t0,
            sourceFileName: "ksqp.qplog",
            program: false
        )!
    }

    /// US calls resolve to the operator's own entity; DL and G are DX.
    private let entities: (String) -> Int? = {
        ["KE5CW": 291, "W0AAA": 291, "K5BBB": 291, "DL1ABC": 230, "G4XYZ": 223][$0]
    }

    private func season(_ records: [ContestRecord], year: Int = 2026) -> PotaSeason {
        PotaSeason.compute(records: records, year: year, entityCode: entities)
    }

    // MARK: Park-days

    /// A park × UTC day is POTA's unit of activation: a two-day rove at two
    /// parks is four candidate activations, each counting its own unique
    /// (call, band, mode) contacts — a second row of the same triple is the
    /// dupe the checker ignores, a band change is a new contact.
    func testParkDaysGroupByParkAndUTCDay() {
        let outing = record(qsos: [
            qso("W0AAA", park: "US-1234"),
            qso("W0AAA", park: "US-1234", offset: 60),            // same triple — not unique
            qso("W0AAA", park: "US-1234", band: .m40, offset: 120),
            qso("K5BBB", park: "US-5678", offset: 180),
            qso("W0AAA", park: "US-1234", offset: 86_400),        // next UTC day
        ])
        let se = season([outing])
        XCTAssertEqual(se.outings.count, 1)
        let days = se.outings[0].parkDays
        XCTAssertEqual(
            days.map { "\($0.park)|\($0.unique)" },
            ["US-1234|2", "US-5678|1", "US-1234|1"]               // day, then park
        )
        XCTAssertEqual(se.outings[0].parks, ["US-1234", "US-5678"])
        XCTAssertEqual(se.activations, 3)
    }

    func testActivationIsValidAtTenUnique() {
        let nine = record(qsos: (1...9).map { qso("W\($0)AA", park: "US-1234") })
        let ten = record(qsos: (1...10).map { qso("W\($0)AA", park: "US-5678", offset: 86_400 * 3) })
        let se = season([nine, ten])
        XCTAssertEqual(se.outings.flatMap(\.parkDays).map(\.valid), [false, true])
        XCTAssertEqual(se.outings.map(\.validParkDays), [0, 1])
        XCTAssertEqual(se.activations, 2)
        XCTAssertEqual(se.validActivations, 1)
    }

    // MARK: A contest worked from a park

    /// A party record's contacts are POTA contacts only where the park is on
    /// the row — the hour before the park was set is the contest's alone —
    /// while a program record's every contact counts, park or hunting.
    func testAContestRecordCountsOnlyItsParkContacts() {
        let ksqp = contestRecord(qsos: [
            qso("N0X", offset: -3600),                      // before the park
            qso("W0AAA", park: "US-1234"),
            qso("K5BBB", park: "US-1234", mode: .phone, offset: 60),
        ])
        let hunting = record(qsos: [qso("W0AAA", offset: 86_400)])
        let se = season([ksqp, hunting])
        XCTAssertEqual(se.outings.map(\.qsos), [2, 1])
        XCTAssertEqual(se.outings[0].parks, ["US-1234"])
        XCTAssertEqual(se.outings[0].record.partyID, "ksqp")
        XCTAssertNil(se.outings[0].record.outing, "a party record keeps a party's identity")
        XCTAssertEqual(se.qsos, 3)
        XCTAssertEqual(se.qsosByMode, ["cw": 2, "phone": 1])
        XCTAssertEqual(se.parksActivated, 1)
    }

    // MARK: P2P, states, DX

    /// P2P counts contacts, not rows — a county-line style multi-park row
    /// group is one contact — and every park they were in counts hunted.
    func testP2PCountsContactsAndDistinctParks() {
        let pair = UUID()
        let se = season([record(qsos: [
            qso("W0AAA", park: "US-1234", theirPark: "US-0001", group: pair),
            qso("W0AAA", park: "US-1234", theirPark: "US-0002", group: pair, offset: 1),
            qso("K5BBB", park: "US-1234", theirPark: "US-0001", offset: 60),
            qso("DL1ABC", park: "US-1234", offset: 120),
        ])])
        XCTAssertEqual(se.outings[0].p2pContacts, 2)
        XCTAssertEqual(se.p2pContacts, 2)
        XCTAssertEqual(se.parksHunted, 2)
    }

    /// The typed state wins over the callbook's (a portable's QRZ state is
    /// wrong); DX is any entity that is not the record's own callsign's.
    func testStatesAndDX() {
        let se = season([record(qsos: [
            qso("W0AAA", park: "US-1234", state: "MO", callbookState: "TX"),
            qso("K5BBB", park: "US-1234", callbookState: "AR", offset: 60),
            qso("DL1ABC", park: "US-1234", offset: 120),
            qso("G4XYZ", park: "US-1234", offset: 180),
        ])])
        XCTAssertEqual(se.outings[0].states, 2)                   // MO, AR — not TX
        XCTAssertEqual(se.outings[0].dxEntities, 2)               // DL, G — not the W/K calls
        XCTAssertEqual(se.states, 2)
        XCTAssertEqual(se.dxEntities, 2)
    }

    // MARK: Hunter outings

    func testHunterOutingHasNoParkDays() {
        let se = season([record(qsos: [
            qso("W0AAA", theirPark: "US-0001"),
            qso("K5BBB", theirPark: "US-0002", offset: 60),
        ])])
        XCTAssertEqual(se.outings[0].parks, [])
        XCTAssertEqual(se.outings[0].parkDays, [])
        XCTAssertEqual(se.activations, 0)
        XCTAssertEqual(se.qsos, 2)
        XCTAssertEqual(se.parksHunted, 2)
    }

    // MARK: Season rollup

    /// Distinct things union across outings — a state worked on two outings
    /// is one state, the same park twice is one park — while activations,
    /// QSOs and minutes sum. Other years' outings and other years entirely
    /// stay out.
    func testSeasonUnionsAcrossOutingsAndFiltersByYear() {
        let a = record(qsos: (1...10).map {
            qso("W\($0)AA", park: "US-1234", state: $0 == 1 ? "MO" : nil)
        })
        let b = record(qsos: [
            qso("W0AAA", park: "US-1234", state: "MO", offset: 86_400 * 7),
            qso("DL1ABC", park: "US-9999", theirPark: "US-0001", offset: 86_400 * 7 + 60),
        ])
        let lastYear = record(qsos: [qso("W0AAA", park: "US-8888", offset: -86_400 * 40)])

        let se = season([a, b, lastYear])
        XCTAssertEqual(se.year, 2026)
        XCTAssertEqual(se.outings.count, 2)
        XCTAssertEqual(se.outings.map(\.date), se.outings.map(\.date).sorted())
        XCTAssertEqual(se.parksActivated, 2)                      // 1234, 9999 — not 8888
        XCTAssertEqual(se.activations, 3)
        XCTAssertEqual(se.validActivations, 1)
        XCTAssertEqual(se.qsos, 12)
        XCTAssertEqual(se.states, 1)
        XCTAssertEqual(se.dxEntities, 1)
        XCTAssertEqual(se.p2pContacts, 1)
        XCTAssertEqual(se.parksHunted, 1)
        XCTAssertGreaterThan(se.minutes, 0)
        XCTAssertEqual(se.qsosByMode["cw"], 12)

        XCTAssertEqual(season([], year: 2026).outings, [])
    }
}

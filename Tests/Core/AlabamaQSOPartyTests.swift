import XCTest
@testable import QSOPartyLogger

final class AlabamaQSOPartyTests: XCTestCase {

    var alqp: PartyDefinition!

    override func setUpWithError() throws {
        alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"), "bundled ALQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K4ZGB",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "JEFF"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_784_991_600 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "alqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    // MARK: County data (official page spot checks)

    func testCountyData() {
        XCTAssertEqual(alqp.counties.count, 67)
        XCTAssertEqual(Set(alqp.counties.map(\.abbr)).count, 67)
        XCTAssertEqual(alqp.county(for: "CHOU")?.name, "Calhoun")
        XCTAssertEqual(alqp.county(for: "CKEE")?.name, "Cherokee")
        XCTAssertEqual(alqp.county(for: "TDEG")?.name, "Talladega")
        XCTAssertEqual(alqp.county(for: "TPOO")?.name, "Tallapoosa")
        XCTAssertEqual(alqp.county(for: "SCLR")?.name, "St. Clair")
        XCTAssertEqual(alqp.county(for: "MGMY")?.name, "Montgomery")
        XCTAssertEqual(alqp.county(for: "DLLS")?.name, "Dallas")
        XCTAssertEqual(alqp.county(for: "LEE")?.name, "Lee")
        XCTAssertEqual(alqp.cabrilloContest, "AL-QSO-PARTY")
        XCTAssertEqual(alqp.maxSimultaneousCounties, 1, "county-line sitting not permitted")
        XCTAssertEqual(alqp.allowedModeClasses, [.phone, .cw])
        XCTAssertEqual(alqp.dxStyle, .prefix)
    }

    // MARK: Per-mode multipliers (rules: "Multipliers can be counted once per mode")

    func testMultsCountPerMode() {
        let log = outLog([
            qso(call: "K4A", band: .m40, mode: .cw, their: "JEFF"),
            qso(call: "K4A", band: .m40, mode: .phone, their: "JEFF"),  // same county, other mode: 2nd mult
            qso(call: "K4B", band: .m20, mode: .cw, their: "JEFF"),    // same county+mode, other band: no new mult
        ])
        let s = ScoreEngine.score(log: log, party: alqp)
        XCTAssertEqual(s.multiplierCount, 2, "JEFF on CW + JEFF on phone")
        XCTAssertEqual(s.workedValues(.county), ["JEFF"])
        XCTAssertEqual(s.qsoPoints, 6, "2 points per QSO regardless of mode, 3 valid QSOs")
        XCTAssertEqual(s.total, 6 * 2)
    }

    // MARK: Both modes are 2 points; digital is invalid, not zero

    func testDigitalRowsAreInvalid() {
        let log = outLog([
            qso(call: "K4A", mode: .cw, their: "MOBI"),
            qso(call: "K4B", mode: .digital, their: "MOBI"),
        ])
        let s = ScoreEngine.score(log: log, party: alqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 1, "invalid row contributes no mult")
    }

    // MARK: In-state: counties + states(via county incl AL) + provinces + DX prefixes

    func testInStateMultClasses() {
        var log = ContestLog(partyID: "alqp")
        log.myLocation = .inState(counties: ["JEFF"])
        log.qsos = [
            qso(call: "W4AA", my: "JEFF", their: "SHEL"),   // AL county → county mult + AL state via county
            qso(call: "W5BB", my: "JEFF", their: "TX"),     // state
            qso(call: "VE3CC", my: "JEFF", their: "ON"),    // province
            qso(call: "DL1DD", my: "JEFF", their: "DL"),    // DX prefix
            qso(call: "G4EE", my: "JEFF", their: "G"),      // second DX prefix = second dx mult
            qso(call: "K4DC", my: "JEFF", their: "DC"),     // DC → MD alias
        ]
        let s = ScoreEngine.score(log: log, party: alqp)
        XCTAssertEqual(s.workedValues(.county), ["SHEL"])
        XCTAssertEqual(s.workedValues(.state), ["AL", "TX", "MD"], "AL via county; DC credited as MD")
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["DL", "G"], "each DXCC prefix is its own mult")
        XCTAssertEqual(s.multiplierCount, 7)
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("chou", party: alqp).get().locations, ["CHOU"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: alqp).get().locations, ["DL"], "DX prefix accepted")
        XCTAssertEqual(try ExchangeParser.parse("DC", party: alqp).get().locations, ["DC"], "DC loggable (counts as MD)")
        // County-line sitting is not permitted: two counties must be rejected.
        XCTAssertEqual(
            ExchangeParser.parse("AUTA/BALD", party: alqp),
            .failure(.tooManyCounties(2))
        )
        // AL is never a valid exchange (AL stations send their county).
        guard case .failure = ExchangeParser.parse("AL", party: alqp) else {
            return XCTFail("AL token must be rejected")
        }
    }

    // MARK: Dupes per band+mode; mobile county change = new station

    func testDupeAndMobileRework() {
        let a = qso(call: "K4M", band: .m40, mode: .cw, their: "AUTA")
        var b = a
        b.id = UUID()
        b.timestampUTC = a.timestampUTC.addingTimeInterval(300)
        let moved = qso(call: "K4M", band: .m40, mode: .cw, their: "ELMO")
        let s = ScoreEngine.score(log: outLog([a, b, moved]), party: alqp)
        XCTAssertEqual(s.validQSOs, 2, "repeat is dupe; county change is new")
        XCTAssertEqual(s.dupeCount, 1)
    }

    // MARK: Schedule (this weekend)

    func testSchedule() throws {
        let window = try XCTUnwrap(alqp.schedule?.first)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(window.start, f.date(from: "2026-07-25T15:00:00Z"))
        XCTAssertEqual(window.end, f.date(from: "2026-07-26T03:00:00Z"))
    }
}

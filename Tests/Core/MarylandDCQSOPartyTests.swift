import XCTest
@testable import QSOPartyLogger

/// Maryland-DC QSO Party — rules "The Fun Contest Maryland-DC QSO Party Rules",
/// Revised 06 AUG 2024 v.5. Section references below are to that document.
final class MarylandDCQSOPartyTests: XCTestCase {

    var mdc: PartyDefinition!

    override func setUpWithError() throws {
        mdc = try XCTUnwrap(PartyCatalog.party(id: "mdc"), "bundled MDC should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W3ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "ANA"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_786_312_800 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            myLoc: my, theirLoc: their
        )
    }

    /// Out-of-state (non-MDC) entrant.
    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "mdc")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    /// MDC entrant operating from a given entity.
    func inLog(_ qsos: [QSO], from entity: String = "ANA") -> ContestLog {
        var log = ContestLog(partyID: "mdc")
        log.myLocation = .inState(counties: [entity])
        log.qsos = qsos
        return log
    }

    // MARK: Entity data (rules Table 1)

    func testEntityData() {
        XCTAssertEqual(mdc.counties.count, 25, "23 MD counties + Baltimore City + DC")
        XCTAssertEqual(Set(mdc.counties.map(\.abbr)).count, 25)
        // Baltimore City and Baltimore County are separate entities — the trap.
        XCTAssertEqual(mdc.county(for: "BAL")?.name, "Baltimore City")
        XCTAssertEqual(mdc.county(for: "BCT")?.name, "Baltimore County")
        // DC is an entity, not a state.
        XCTAssertEqual(mdc.county(for: "WDC")?.name, "Washington DC")
        // Abbreviations that are not simple truncations.
        XCTAssertEqual(mdc.county(for: "PGE")?.name, "Prince George's")
        XCTAssertEqual(mdc.county(for: "QAN")?.name, "Queen Anne's")
        XCTAssertEqual(mdc.county(for: "STM")?.name, "St. Mary's")
        XCTAssertEqual(mdc.county(for: "DRC")?.name, "Dorchester")
        XCTAssertEqual(mdc.county(for: "CLN")?.name, "Caroline")
        XCTAssertEqual(mdc.county(for: "CLV")?.name, "Calvert")
        XCTAssertEqual(mdc.county(for: "WRC")?.name, "Worcester")
        XCTAssertEqual(mdc.county(for: "WAS")?.name, "Washington", "MD's Washington County")
    }

    func testPartyShape() {
        XCTAssertEqual(mdc.cabrilloContest, "MDC-QSO-PARTY")
        XCTAssertEqual(mdc.homeState, "MD")
        XCTAssertEqual(mdc.countyAbbrLength, 3)
        XCTAssertEqual(mdc.allowedModeClasses, [.phone, .cw], "§6: no digital modes exist")
        XCTAssertEqual(mdc.dxStyle, .prefix, "§7a: DX stations send their country")
        XCTAssertEqual(mdc.maxSimultaneousCounties, 1, "no county-line provision")
        XCTAssertFalse(mdc.exchangeIncludesRST, "§7: call + location only")
        XCTAssertTrue(mdc.outStateWorksHomeStationsOnly, "§10b")
        XCTAssertEqual(mdc.validBands, [.m160, .m80, .m40, .m20, .m15, .m10],
                       "§13: no WARC, no 60 m, no VHF/UHF")
    }

    // MARK: Points — §14a: CW 3, phone 1

    func testPointsByMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", mode: .cw, their: "ANA"),
            qso(call: "W3B", mode: .phone, their: "BAL"),
        ]), party: mdc)
        XCTAssertEqual(s.qsoPoints, 4, "3 CW + 1 phone")
        XCTAssertEqual(s.validQSOs, 2)
    }

    func testDigitalRowsAreInvalidNotZeroScored() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", mode: .cw, their: "ANA"),
            qso(call: "W3B", mode: .digital, their: "BAL"),
        ]), party: mdc)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.qsoPoints, 3)
        XCTAssertEqual(s.multiplierCount, 1, "the digital row contributes no mult")
    }

    // MARK: §10b — non-MDC entrants only get credit for MD/DC stations

    func testOutOfStateEarnsNothingForNonMDCContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", mode: .cw, their: "ANA"),   // MDC entity: counts
            qso(call: "K5B", mode: .cw, their: "OK"),    // another out-of-state: no credit
            qso(call: "VE3C", mode: .cw, their: "ON"),   // province: no credit
            qso(call: "DL1D", mode: .cw, their: "DL"),   // DX: no credit
        ]), party: mdc)
        XCTAssertEqual(s.validQSOs, 1, "only the MDC contact is a contest QSO")
        XCTAssertEqual(s.outOfScopeCount, 3)
        XCTAssertEqual(s.qsoPoints, 3, "no points for the three non-MDC contacts")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// An MDC entrant may work anyone (§10b second sentence) — the same three
    /// contacts that earn an out-of-state entrant nothing are all mults here.
    func testInStateWorksAnyoneAndSumsAllClasses() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "ANA", their: "BAL"),   // entity
            qso(call: "K5B", my: "ANA", their: "OK"),    // state
            qso(call: "VE3C", my: "ANA", their: "ON"),   // province
            qso(call: "DL1D", my: "ANA", their: "DL"),   // DXCC country
            qso(call: "G4E", my: "ANA", their: "G"),     // second DXCC country
        ]), party: mdc)
        XCTAssertEqual(s.outOfScopeCount, 0)
        XCTAssertEqual(s.workedValues(.county), ["BAL"])
        XCTAssertEqual(s.workedValues(.state), ["OK"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["DL", "G"], "§16d: each DXCC country")
        XCTAssertEqual(s.multiplierCount, 5, "§16e: all classes summed")
    }

    /// §10i: "Participating stations may not count Maryland as a state they have
    /// worked." Nor is DC a state — it arrives as entity WDC.
    func testMarylandAndDCAreNeverStateMultipliers() {
        XCTAssertEqual(mdc.excludedStateTokens.sorted(), ["DC", "MD"])
        XCTAssertFalse(mdc.validOutStateTokens.contains("MD"))
        XCTAssertFalse(mdc.validOutStateTokens.contains("DC"))
        // WDC is reachable as an entity, and scores as a county-class mult.
        let s = ScoreEngine.score(log: outLog([qso(their: "WDC")]), party: mdc)
        XCTAssertEqual(s.workedValues(.county), ["WDC"])
        XCTAssertEqual(s.workedValues(.state), [], "DC is not credited as a state")
    }

    /// §10h/§16d: Alaska and Hawaii count as states only, never DXCC entities.
    func testAlaskaAndHawaiiAreStatesNotDXCC() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "KL7A", my: "ANA", their: "AK"),
            qso(call: "KH6B", my: "ANA", their: "HI"),
        ]), party: mdc)
        XCTAssertEqual(s.workedValues(.state), ["AK", "HI"])
        XCTAssertEqual(s.workedValues(.dx), [])
    }

    // MARK: Multiplier scope — §16: once per contest, never per band or mode

    func testMultsCountOnceForTheContest() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", band: .m40, mode: .cw, their: "ANA"),
            qso(call: "W3A", band: .m40, mode: .phone, their: "ANA"),  // other mode
            qso(call: "W3B", band: .m20, mode: .cw, their: "ANA"),     // other band
        ]), party: mdc)
        XCTAssertEqual(s.multiplierCount, 1, "ANA counts once, not per band or per mode")
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 3 + 1 + 3)
    }

    // MARK: Dupes — §10f once per band per mode; §10g relocation is a new station

    func testDupesAndRelocation() {
        let a = qso(call: "W3M", band: .m40, mode: .cw, their: "ANA")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(300)
        let otherMode = qso(call: "W3M", band: .m40, mode: .phone, their: "ANA")
        let moved = qso(call: "W3M", band: .m40, mode: .cw, their: "BAL")
        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, moved]), party: mdc)
        XCTAssertEqual(s.dupeCount, 1, "only the verbatim repeat is a dupe")
        XCTAssertEqual(s.validQSOs, 3, "other mode is workable; relocation is a new station")
        XCTAssertEqual(s.multiplierCount, 2, "ANA + BAL")
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("ana", party: mdc, role: .inState).get().locations, ["ANA"])
        XCTAssertEqual(try ExchangeParser.parse("WDC", party: mdc, role: .inState).get().locations, ["WDC"])
        XCTAssertEqual(try ExchangeParser.parse("OK", party: mdc, role: .inState).get().locations, ["OK"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: mdc, role: .inState).get().locations, ["DL"],
                       "§7a: DX sends its country")
        // MD stations always send an entity, so the bare state token is invalid.
        guard case .failure = ExchangeParser.parse("MD", party: mdc, role: .inState) else {
            return XCTFail("MD token must be rejected")
        }
        // DC likewise — it is entity WDC, never the state token DC.
        guard case .failure = ExchangeParser.parse("DC", party: mdc, role: .inState) else {
            return XCTFail("DC token must be rejected — DC is entity WDC")
        }
        // No county-line provision: two entities at once is invalid.
        XCTAssertEqual(
            ExchangeParser.parse("ANA/BAL", party: mdc, role: .inState),
            .failure(.tooManyCounties(2))
        )
    }

    // MARK: Bonuses — §18a W3VPR 50 once; §18b tiered sweep 250 @ 13 / 500 @ 25

    func testW3VPRBonusIsOneTimeAcrossModesAndBands() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3VPR", band: .m40, mode: .cw, their: "ANA"),
            qso(call: "W3VPR", band: .m40, mode: .phone, their: "ANA"),
            qso(call: "W3VPR", band: .m20, mode: .cw, their: "ANA"),
        ]), party: mdc)
        XCTAssertEqual(s.bonusPoints, 50, "§20f(i): a one-time 50 points, any mode")
    }

    func testSweepTiersAreNonStacking() {
        let entities = mdc.counties.map(\.abbr)

        func bonus(workingFirst n: Int) -> Int {
            let rows = entities.prefix(n).enumerated().map { i, abbr in
                qso(call: "W3\(i)", their: abbr)
            }
            return ScoreEngine.score(log: outLog(rows), party: mdc).bonusPoints
        }

        XCTAssertEqual(bonus(workingFirst: 12), 0, "below the first tier")
        XCTAssertEqual(bonus(workingFirst: 13), 250, "§18b(i): 13 jurisdictions")
        XCTAssertEqual(bonus(workingFirst: 24), 250, "still the 13 tier, not stacked")
        XCTAssertEqual(bonus(workingFirst: 25), 500,
                       "§18b: all 25 pays 500, and does not stack with 250")
    }

    // MARK: Final-score multipliers — §15a/§15b, applied before bonuses

    func testPowerAndStationCategoryMultiplyTheBasicScore() throws {
        let mults = try XCTUnwrap(mdc.scoreMultipliers)
        XCTAssertEqual(mults.factor(power: .qrp, station: .rover), 12, "QRP 3 × Rover 4")
        XCTAssertEqual(mults.factor(power: .low, station: .portable), 6, "Low 2 × Portable 3")
        XCTAssertEqual(mults.factor(power: .high, station: .mobile), 2, "High 1 × Mobile 2")
        XCTAssertEqual(mults.factor(power: .high, station: .fixed), 1)
    }

    /// §20e/§20g: (points × power × category × mults) + bonuses — the bonus is
    /// added after multiplication, not multiplied by it.
    func testScoreFormulaOrder() {
        var log = outLog([
            qso(call: "W3VPR", mode: .cw, their: "ANA"),
            qso(call: "W3B", mode: .cw, their: "BAL"),
        ])
        log.station.categoryPower = .qrp      // ×3
        log.station.categoryStation = .mobile // ×2
        let s = ScoreEngine.score(log: log, party: mdc)
        XCTAssertEqual(s.qsoPoints, 6, "two CW QSOs")
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertEqual(s.categoryFactor, 6)
        XCTAssertEqual(s.bonusPoints, 50)
        XCTAssertEqual(s.total, 6 * 2 * 6 + 50, "bonus added after multiplying")
    }

    // MARK: Schedule — §2, second Saturday in August 2026 = Aug 8

    func testSchedule() throws {
        let windows = try XCTUnwrap(mdc.schedule)
        XCTAssertEqual(windows.count, 1, "§2: a single 14-hour period")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-08-08T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-08-09T04:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 14 * 3600)
    }
}

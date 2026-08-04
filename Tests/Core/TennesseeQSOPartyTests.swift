import XCTest
@testable import QSOPartyLogger

/// Tennessee QSO Party — Tennessee Contest Group rules as posted at tnqp.org
/// (read 2026-07-23, re-checked 2026-07-24). See docs/research/tnqp_rules.md.
final class TennesseeQSOPartyTests: XCTestCase {

    var tnqp: PartyDefinition!

    override func setUpWithError() throws {
        tnqp = try XCTUnwrap(PartyCatalog.party(id: "tnqp"), "bundled TnQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K4ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "DAVI"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_788_800_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "tnqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(
        _ qsos: [QSO],
        from county: String = "DAVI",
        station: StationProfile.CategoryStation = .fixed
    ) -> ContestLog {
        var log = ContestLog(partyID: "tnqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: County data — 95 counties, official 4-letter list

    func testCountyData() {
        XCTAssertEqual(tnqp.counties.count, 95, "Tennessee has 95 counties")
        XCTAssertEqual(Set(tnqp.counties.map(\.abbr)).count, 95)
        XCTAssertTrue(tnqp.counties.allSatisfy { $0.abbr.count == 4 })
        // The lookalike pair that makes this party's list worth generating.
        XCTAssertEqual(tnqp.county(for: "HARD")?.name, "Hardeman")
        XCTAssertEqual(tnqp.county(for: "HARN")?.name, "Hardin")
        // Abbreviations that are not simple truncations.
        XCTAssertEqual(tnqp.county(for: "VANB")?.name, "Van Buren")
        XCTAssertEqual(tnqp.county(for: "MCMI")?.name, "McMinn")
        XCTAssertEqual(tnqp.county(for: "MCNA")?.name, "McNairy")
        XCTAssertEqual(tnqp.county(for: "OBIO")?.name, "Obion")
        XCTAssertEqual(tnqp.county(for: "SEQU")?.name, "Sequatchie")
        XCTAssertEqual(tnqp.county(for: "TROU")?.name, "Trousdale")
        XCTAssertEqual(tnqp.county(for: "UNIC")?.name, "Unicoi")
        // The sponsor's own spelling is preserved rather than "corrected".
        XCTAssertEqual(tnqp.county(for: "DEKA")?.name, "Dekalb",
                       "official list prints 'Dekalb'")
        XCTAssertEqual(tnqp.county(for: "davi")?.name, "Davidson", "case-insensitive")
    }

    func testPartyShape() {
        XCTAssertEqual(tnqp.cabrilloContest, "TN-QSO-PARTY")
        XCTAssertEqual(tnqp.homeState, "TN")
        XCTAssertEqual(tnqp.countyAbbrLength, 4)
        XCTAssertEqual(tnqp.allowedModeClasses, ModeClass.allCases,
                       "CW, phone and digital are all valid")
        XCTAssertEqual(tnqp.dxStyle, .prefix, "the exchange carries a DXCC entity")
        XCTAssertTrue(tnqp.exchangeIncludesRST)
        XCTAssertTrue(tnqp.outStateWorksHomeStationsOnly,
                      "outside-Tennessee stations work only Tennessee stations")
        XCTAssertEqual(tnqp.maxSimultaneousCounties, 2,
                       "county lines allowed, but not three- or four-county lines")
        XCTAssertNil(tnqp.scoreMultipliers, "no power or category multiplier")
        // "All amateur bands ... except 60, 30, 17 and 12 meters."
        XCTAssertFalse(tnqp.validBands.contains(.m60))
        XCTAssertFalse(tnqp.validBands.contains(.m30))
        XCTAssertFalse(tnqp.validBands.contains(.m17))
        XCTAssertFalse(tnqp.validBands.contains(.m12))
        XCTAssertTrue(tnqp.validBands.contains(.m160))
        XCTAssertTrue(tnqp.validBands.contains(.m6), "VHF/UHF are in play")
        XCTAssertTrue(tnqp.validBands.contains(.cm70))
        XCTAssertTrue(tnqp.validBands.contains(.cm125),
                      "1.25 m is valid — the suggested-frequency list gives 223.50")
    }

    // MARK: Points — flat 3 regardless of mode

    func testThreePointsInEveryMode() {
        for mode in ModeClass.allCases {
            XCTAssertEqual(tnqp.points.points(for: mode), 3, "3 points per QSO in \(mode)")
        }
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4A", mode: .cw, their: "DAVI"),
            qso(call: "K4B", mode: .phone, their: "KNOX"),
            qso(call: "K4C", mode: .digital, their: "SHEL"),
        ]), party: tnqp)
        XCTAssertEqual(s.qsoPoints, 9)
        XCTAssertEqual(s.invalidModeCount, 0)
    }

    // MARK: Multipliers accumulate PER BAND, not per mode

    func testMultsCountPerBandNotPerMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4A", band: .m40, mode: .cw, their: "DAVI"),
            qso(call: "K4A", band: .m40, mode: .phone, their: "DAVI"), // other mode: no new mult
            qso(call: "K4B", band: .m20, mode: .cw, their: "DAVI"),    // other band: new mult
        ]), party: tnqp)
        XCTAssertEqual(s.multiplierCount, 2, "DAVI on 40 m and on 20 m; mode is irrelevant")
        XCTAssertEqual(s.validQSOs, 3)
    }

    /// The rules' own worked example: "if you work all 95 Tennessee counties on
    /// 40M and again on 20M you earn 190 multipliers."
    func testAll95CountiesOnTwoBandsIs190() {
        var rows: [QSO] = []
        var n = 0
        for band in [Band.m40, .m20] {
            for abbr in tnqp.counties.map(\.abbr) {
                n += 1
                rows.append(qso(call: "K4\(n)", band: band, mode: .cw, their: abbr))
            }
        }
        let s = ScoreEngine.score(log: outLog(rows), party: tnqp)
        XCTAssertEqual(s.multiplierCount, 190, "95 counties x 2 bands, per the rules' example")
        XCTAssertEqual(s.workedValues(.county).count, 95)
    }

    // MARK: In-state classes; Tennessee itself is never a state multiplier

    func testInStateCountsCountiesStatesProvincesAndDXCC() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K4A", my: "DAVI", their: "KNOX"),   // TN county
            qso(call: "K5B", my: "DAVI", their: "TX"),     // state
            qso(call: "VE3C", my: "DAVI", their: "ON"),    // province
            qso(call: "DL1D", my: "DAVI", their: "DL"),    // DXCC entity
            qso(call: "G4E", my: "DAVI", their: "G"),      // second DXCC entity
        ]), party: tnqp)
        XCTAssertEqual(s.workedValues(.county), ["KNOX"])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["Germany", "England"])
        XCTAssertEqual(s.multiplierCount, 5)
    }

    func testTennesseeIsNeverAStateMultiplier() {
        XCTAssertFalse(tnqp.multipliers.inState.homeStateCountsViaCounty,
                       "'do not count Tennessee as a state'")
        XCTAssertEqual(tnqp.excludedStateTokens, ["TN"])
        XCTAssertFalse(tnqp.validOutStateTokens.contains("TN"))
        let s = ScoreEngine.score(log: inLog([qso(my: "DAVI", their: "KNOX")]), party: tnqp)
        XCTAssertEqual(s.workedValues(.state), [], "a TN county yields no TN state mult")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// "District of Columbia counts as Maryland."
    func testDCCountsAsMaryland() {
        XCTAssertEqual(tnqp.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K3A", my: "DAVI", their: "DC"),
            qso(call: "K3B", my: "DAVI", their: "MD"),
        ]), party: tnqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "DC and MD are one multiplier")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// "Alaska & Hawaii count as states only" — never DXCC entities.
    func testAlaskaAndHawaiiAreStatesNotDXCC() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "KL7A", my: "DAVI", their: "AK"),
            qso(call: "KH6B", my: "DAVI", their: "HI"),
        ]), party: tnqp)
        XCTAssertEqual(s.workedValues(.state), ["AK", "HI"])
        XCTAssertEqual(s.workedValues(.dx), [])
    }

    // MARK: "Outside Tennessee stations work only Tennessee stations"

    func testOutOfStateEarnsNothingForNonTennesseeContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4A", their: "DAVI"),
            qso(call: "K5B", their: "TX"),
            qso(call: "VE3C", their: "ON"),
            qso(call: "DL1D", their: "DL"),
        ]), party: tnqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 3)
        XCTAssertEqual(s.qsoPoints, 3)
    }

    // MARK: Dupes — per band/mode, mobiles re-workable on a county change

    func testDupesAndMobileCountyChange() {
        let a = qso(call: "K4M", band: .m80, mode: .cw, their: "MONT")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "K4M", band: .m80, mode: .digital, their: "MONT")
        let moved = qso(call: "K4M", band: .m80, mode: .cw, their: "WILS")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, moved]), party: tnqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3, "other mode counts; mobile county change counts")
        XCTAssertEqual(s.multiplierCount, 2, "MONT + WILS, both on 80 m")
    }

    // MARK: Bonuses — K4TCG is PER QSO, not once

    func testK4TCGBonusIsPerQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4TCG", band: .m40, mode: .cw, their: "DAVI"),
            qso(call: "K4TCG", band: .m40, mode: .phone, their: "DAVI"),
            qso(call: "K4TCG", band: .m20, mode: .cw, their: "DAVI"),
        ]), party: tnqp)
        XCTAssertEqual(s.bonusPoints, 300, "100 points for EACH QSO with K4TCG")
    }

    /// "Tennessee mobile & rover operators may claim 500 bonus points for each
    /// Tennessee county from which they complete at least 10 QSOs."
    func testMobileActivationBonusNeedsTenQSOsPerCounty() {
        func rows(_ county: String, _ count: Int) -> [QSO] {
            (0..<count).map { i in
                qso(call: "W\(county)\(i)", mode: .cw, my: county, their: "KNOX")
            }
        }
        // DAVI qualifies with 10, MONT falls one short with 9.
        let log = inLog(rows("DAVI", 10) + rows("MONT", 9), station: .mobile)
        let s = ScoreEngine.score(log: log, party: tnqp)
        XCTAssertEqual(s.bonusPoints, 500, "only the county with 10+ QSOs pays")

        // A fixed station earns no activation bonus at all.
        var fixed = log
        fixed.station.categoryStation = .fixed
        XCTAssertEqual(ScoreEngine.score(log: fixed, party: tnqp).bonusPoints, 0)
    }

    /// Bonuses are added after the multiplier, never multiplied by it.
    func testBonusesAddedAfterMultipliers() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4TCG", band: .m40, mode: .cw, their: "DAVI"),
            qso(call: "K4B", band: .m20, mode: .cw, their: "KNOX"),
        ]), party: tnqp)
        XCTAssertEqual(s.qsoPoints, 6)
        XCTAssertEqual(s.multiplierCount, 2, "DAVI on 40 m, KNOX on 20 m")
        XCTAssertEqual(s.bonusPoints, 100)
        XCTAssertEqual(s.total, 6 * 2 + 100)
    }

    // MARK: County lines — two allowed, three rejected

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("davi", party: tnqp, role: .inState).get().locations, ["DAVI"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: tnqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: tnqp, role: .inState).get().locations, ["DL"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: tnqp, role: .inState).get().locations, ["DC"],
                       "loggable, credited as MD")
        // Two-county line is legal here.
        XCTAssertEqual(
            try ExchangeParser.parse("MONT/WILS", party: tnqp, role: .inState).get().locations,
            ["MONT", "WILS"]
        )
        // Three is not.
        XCTAssertEqual(
            ExchangeParser.parse("MONT/WILS/DAVI", party: tnqp, role: .inState),
            .failure(.tooManyCounties(3))
        )
        guard case .failure = ExchangeParser.parse("TN", party: tnqp, role: .inState) else {
            return XCTFail("TN token must be rejected")
        }
    }

    // MARK: Schedule — first Sunday of September, 10 hours

    func testSchedule() throws {
        let windows = try XCTUnwrap(tnqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-09-06T17:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-09-07T03:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 10 * 3600)
    }

    func testNotesRecordThePartialVerification() {
        let notes = tnqp.notes ?? ""
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("late August 2026"),
                      "notes must say when to re-check for a 2026 revision")
    }
}

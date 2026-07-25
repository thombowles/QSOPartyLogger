import XCTest
@testable import QSOPartyLogger

/// New Jersey QSO Party — Burlington County Radio Club rules, version
/// 2026rev0.5, read live 2026-07-24. See docs/research/njqp_rules.md.
final class NewJerseyQSOPartyTests: XCTestCase {

    var njqp: PartyDefinition!

    override func setUpWithError() throws {
        njqp = try XCTUnwrap(PartyCatalog.party(id: "njqp"), "bundled NJQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K2ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "BURL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_300_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO], power: StationProfile.CategoryPower = .low) -> ContestLog {
        var log = ContestLog(partyID: "njqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], power: StationProfile.CategoryPower = .low) -> ContestLog {
        var log = ContestLog(partyID: "njqp")
        log.myLocation = .inState(counties: ["BURL"])
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    // MARK: County data — 21 counties, and the truncation traps

    func testCountyData() {
        XCTAssertEqual(njqp.counties.count, 21, "New Jersey has 21 counties")
        XCTAssertEqual(Set(njqp.counties.map(\.abbr)).count, 21)
        XCTAssertTrue(njqp.counties.allSatisfy { $0.abbr.count == 4 })
        // Not first-four-letter truncations — the two that bite.
        XCTAssertEqual(njqp.county(for: "CMDN")?.name, "Camden")
        XCTAssertEqual(njqp.county(for: "WRRN")?.name, "Warren")
        XCTAssertNil(njqp.county(for: "CAMD"), "the naive truncation is not valid")
        XCTAssertNil(njqp.county(for: "WARR"), "the naive truncation is not valid")
        // Lookalike pairs.
        XCTAssertEqual(njqp.county(for: "MONM")?.name, "Monmouth")
        XCTAssertEqual(njqp.county(for: "MORR")?.name, "Morris")
        XCTAssertEqual(njqp.county(for: "HUDS")?.name, "Hudson")
        XCTAssertEqual(njqp.county(for: "HUNT")?.name, "Hunterdon")
        XCTAssertEqual(njqp.county(for: "CAPE")?.name, "Cape May")
        XCTAssertEqual(njqp.county(for: "burl")?.name, "Burlington", "case-insensitive")
    }

    func testPartyShape() {
        XCTAssertEqual(njqp.cabrilloContest, "NJQP")
        XCTAssertEqual(njqp.homeState, "NJ")
        XCTAssertEqual(njqp.countyAbbrLength, 4)
        XCTAssertEqual(njqp.validBands, [.m80, .m40, .m20, .m15, .m10],
                       "80/40/20/15/10 ONLY — no 160 m, no VHF")
        XCTAssertEqual(njqp.allowedModeClasses, ModeClass.allCases,
                       "digital is a first-class NJQP mode")
        XCTAssertEqual(njqp.dxStyle, .token)
        XCTAssertTrue(njqp.exchangeIncludesRST)
        XCTAssertEqual(njqp.maxSimultaneousCounties, 1,
                       "no simultaneous operation in more than one county")
        XCTAssertTrue(njqp.bonuses.isEmpty, "no bonus station, no bonus points")
        XCTAssertTrue(njqp.isPartiallyVerified, "DC and the works-only-NJ rule are open")
    }

    // MARK: Points — phone 1, CW 2, digital 2

    func testPointsByMode() {
        XCTAssertEqual(njqp.points.points(for: .phone), 1)
        XCTAssertEqual(njqp.points.points(for: .cw), 2)
        XCTAssertEqual(njqp.points.points(for: .digital), 2)
    }

    // MARK: Multipliers count ONCE — not per band, not per mode

    func testMultipliersCountOnceForTheContest() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K2A", band: .m40, mode: .cw, their: "BURL"),
            qso(call: "K2B", band: .m20, mode: .cw, their: "BURL"),    // other band
            qso(call: "K2C", band: .m40, mode: .phone, their: "BURL"), // other mode
            qso(call: "K2D", band: .m80, mode: .digital, their: "BURL"),
        ]), party: njqp)
        XCTAssertEqual(s.multiplierCount, 1,
                       "BURL counts once — neither per band nor per mode, unlike COQP "
                           + "which shares this date")
        XCTAssertEqual(s.validQSOs, 4)
    }

    /// Rules: non-NJ stations reach "a maximum of 21x multiplier".
    func testOutOfStateCeilingIs21() {
        let rows = njqp.counties.map(\.abbr).enumerated().map { i, abbr in
            qso(call: "K2\(i)", their: abbr)
        }
        let s = ScoreEngine.score(log: outLog(rows), party: njqp)
        XCTAssertEqual(s.multiplierCount, 21)
    }

    /// Rules: NJ stations reach "a maximum of 84x contact multiplier" —
    /// 21 counties + 49 states (not NJ, and no DC) + 13 provinces + 1 DX.
    func testInStateCeilingIs84() {
        var rows: [QSO] = []
        var n = 0
        func add(_ loc: String) {
            n += 1
            rows.append(qso(call: "W\(n)", my: "BURL", their: loc))
        }
        njqp.counties.map(\.abbr).forEach(add)
        MultClass.usStates.subtracting(["NJ"]).sorted().forEach(add)
        njqp.provinces.sorted().forEach(add)
        add("DX")

        let s = ScoreEngine.score(log: inLog(rows), party: njqp)
        XCTAssertEqual(s.workedValues(.county).count, 21)
        XCTAssertEqual(s.workedValues(.state).count, 49, "50 states less NJ; DC is not counted")
        XCTAssertEqual(s.workedValues(.province).count, 13)
        XCTAssertEqual(s.workedValues(.dx).count, 1)
        XCTAssertEqual(s.multiplierCount, 84, "the rules' own stated maximum")
    }

    // MARK: Provinces — all 13, but Newfoundland is NF, not NL

    func testNewfoundlandIsNFNotNL() {
        XCTAssertEqual(njqp.provinces.count, 13, "all 13 count, unlike OhQP's 11")
        XCTAssertTrue(njqp.provinces.contains("NF"),
                      "the official table spells it NF, the legacy abbreviation")
        XCTAssertFalse(njqp.provinces.contains("NL"), "the modern NL is not NJQP's token")
        // Unlike OhQP, Yukon and Nunavut stay separate from NT.
        XCTAssertTrue(njqp.provinces.contains("YT"))
        XCTAssertTrue(njqp.provinces.contains("NU"))
        XCTAssertTrue(njqp.provinces.contains("NT"))

        let s = ScoreEngine.score(log: inLog([qso(my: "BURL", their: "NF")]), party: njqp)
        XCTAssertEqual(s.workedValues(.province), ["NF"])

        XCTAssertTrue(njqp.validOutStateTokens.contains("NF"))
        XCTAssertFalse(njqp.validOutStateTokens.contains("NL"))
        guard case .failure = ExchangeParser.parse("NL", party: njqp) else {
            return XCTFail("NL must be rejected — NJQP's official token is NF")
        }
    }

    /// The sponsor's states table has no DC row and counts only 49 states, so DC
    /// is excluded outright rather than aliased to Maryland (a rule NJQP, unlike
    /// ALQP/TnQP/COQP, never states).
    func testDCIsNotALoggableToken() {
        XCTAssertEqual(njqp.excludedStateTokens.sorted(), ["DC", "NJ"])
        XCTAssertFalse(njqp.validOutStateTokens.contains("DC"))
        XCTAssertTrue(njqp.stateAliases.isEmpty, "no DC-counts-as-Maryland rule exists here")
        guard case .failure = ExchangeParser.parse("DC", party: njqp) else {
            return XCTFail("DC must be rejected — it is absent from the official table")
        }
    }

    // MARK: Power is a final-score multiplier

    func testPowerMultiplier() throws {
        let mults = try XCTUnwrap(njqp.scoreMultipliers)
        XCTAssertEqual(mults.factor(power: .high, station: .fixed), 1)
        XCTAssertEqual(mults.factor(power: .low, station: .fixed), 2)
        XCTAssertEqual(mults.factor(power: .qrp, station: .fixed), 4)
        // No station-category factor here, unlike MDC.
        XCTAssertEqual(mults.factor(power: .qrp, station: .mobile), 4,
                       "station type must not change the factor")
    }

    // MARK: The sponsor's own worked examples, reproduced end to end

    /// S1: "Non-NJ Station completed QSO with 9 NJ Counties. Low Power … 13
    /// Phone, 10 CW and 3 Digital contacts. … QSO Score: (13 x 1) + (10 x 2) +
    /// (3 x 2) = 39 … Final Score: 39 x 9 x 2 = 702"
    func testSponsorExampleNonNJStationScores702() {
        let nineCounties = Array(njqp.counties.map(\.abbr).prefix(9))
        var rows: [QSO] = []
        var n = 0
        func add(_ mode: ModeClass, _ count: Int) {
            for _ in 0..<count {
                rows.append(qso(call: "K2X\(n)", mode: mode, their: nineCounties[n % 9]))
                n += 1
            }
        }
        add(.phone, 13)
        add(.cw, 10)
        add(.digital, 3)

        let s = ScoreEngine.score(log: outLog(rows, power: .low), party: njqp)
        XCTAssertEqual(s.validQSOs, 26)
        XCTAssertEqual(s.qsoPoints, 39, "(13 x 1) + (10 x 2) + (3 x 2)")
        XCTAssertEqual(s.multiplierCount, 9, "9 NJ counties, counted once")
        XCTAssertEqual(s.categoryFactor, 2, "low power")
        XCTAssertEqual(s.total, 702, "the sponsor's own arithmetic: 39 x 9 x 2")
    }

    /// S1: "NJ Station completed QSO with 6 NJ Counties and 5 USA states, 2 in
    /// Canada and 1 DX. QRP … 5 Phone, 5 CW and 4 Digital contacts. … QSO Score:
    /// … = 23 … Final Score: 23 x 14 x 4 = 1288"
    func testSponsorExampleNJStationScores1288() {
        let locations =
            Array(njqp.counties.map(\.abbr).prefix(6))       // 6 NJ counties
            + ["NY", "PA", "DE", "MD", "CA"]                  // 5 US states
            + ["ON", "QC"]                                    // 2 Canadian
            + ["DX"]                                          // 1 DX
        XCTAssertEqual(locations.count, 14)

        let modes: [ModeClass] =
            Array(repeating: .phone, count: 5)
            + Array(repeating: .cw, count: 5)
            + Array(repeating: .digital, count: 4)

        let rows = zip(locations, modes).enumerated().map { i, pair in
            qso(call: "W2Y\(i)", mode: pair.1, my: "BURL", their: pair.0)
        }

        let s = ScoreEngine.score(log: inLog(rows, power: .qrp), party: njqp)
        XCTAssertEqual(s.validQSOs, 14)
        XCTAssertEqual(s.qsoPoints, 23, "(5 x 1) + (5 x 2) + (4 x 2)")
        XCTAssertEqual(s.workedValues(.county).count, 6)
        XCTAssertEqual(s.workedValues(.state).count, 5)
        XCTAssertEqual(s.workedValues(.province).count, 2)
        XCTAssertEqual(s.workedValues(.dx).count, 1)
        XCTAssertEqual(s.multiplierCount, 14)
        XCTAssertEqual(s.categoryFactor, 4, "QRP")
        XCTAssertEqual(s.total, 1288, "the sponsor's own arithmetic: 23 x 14 x 4")
    }

    // MARK: Dupes and mobile relocation

    func testDupesAndRelocation() {
        let a = qso(call: "K2M", band: .m40, mode: .cw, their: "OCEA")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "K2M", band: .m40, mode: .digital, their: "OCEA")
        let moved = qso(call: "K2M", band: .m40, mode: .cw, their: "MONM")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, moved]), party: njqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3, "other mode counts; a county change is a new station")
        XCTAssertEqual(s.multiplierCount, 2, "OCEA + MONM")
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("burl", party: njqp).get().locations, ["BURL"])
        XCTAssertEqual(try ExchangeParser.parse("CMDN", party: njqp).get().locations, ["CMDN"])
        XCTAssertEqual(try ExchangeParser.parse("PA", party: njqp).get().locations, ["PA"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: njqp).get().locations, ["DX"])
        guard case .failure = ExchangeParser.parse("NJ", party: njqp) else {
            return XCTFail("NJ must be rejected — 'NJ : use counties'")
        }
        XCTAssertEqual(
            ExchangeParser.parse("OCEA/MONM", party: njqp),
            .failure(.tooManyCounties(2)),
            "no simultaneous operation in more than one county"
        )
    }

    // MARK: Schedule — the date that contradicts the Challenge calendar

    func testScheduleUsesTheSponsorsSeptember12NotTheCalendarsSeptember19() throws {
        let windows = try XCTUnwrap(njqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-09-12T14:00:00Z"),
                       "sponsor says Saturday September 12, 10:00 AM EDT")
        XCTAssertEqual(windows[0].end, f.date(from: "2026-09-13T02:00:00Z"),
                       "10:00 PM EDT Saturday is 0200Z Sunday")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600)
    }

    func testNotesRecordTheOpenQuestions() throws {
        let notes = njqp.notes ?? ""
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("NewJerseyQSOParty@gmail.com"),
                      "notes must say who to ask")
        let questions = try XCTUnwrap(njqp.openQuestions)
        XCTAssertTrue(questions.contains("District of Columbia"))
    }
}

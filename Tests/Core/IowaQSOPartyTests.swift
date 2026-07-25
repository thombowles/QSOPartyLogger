import XCTest
@testable import QSOPartyLogger

/// Iowa QSO Party — Story County ARC rules as posted at w0yl.com/IAQP
/// (captured 2026-07-23, re-checked 2026-07-24). See docs/research/iaqp_rules.md.
final class IowaQSOPartyTests: XCTestCase {

    var iaqp: PartyDefinition!

    override func setUpWithError() throws {
        iaqp = try XCTUnwrap(PartyCatalog.party(id: "iaqp"), "bundled IAQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W0ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "STR"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_900_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "iaqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "STR") -> ContestLog {
        var log = ContestLog(partyID: "iaqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 99 counties, badly clustered abbreviations

    func testCountyData() {
        XCTAssertEqual(iaqp.counties.count, 99, "Iowa has 99 counties")
        XCTAssertEqual(Set(iaqp.counties.map(\.abbr)).count, 99)
        XCTAssertTrue(iaqp.counties.allSatisfy { $0.abbr.count == 3 })
    }

    func testClusteredAbbreviations() {
        // Four counties starting CL.
        XCTAssertEqual(iaqp.county(for: "CLR")?.name, "Clarke")
        XCTAssertEqual(iaqp.county(for: "CLA")?.name, "Clay")
        XCTAssertEqual(iaqp.county(for: "CLT")?.name, "Clayton")
        XCTAssertEqual(iaqp.county(for: "CLN")?.name, "Clinton")
        // The M cluster.
        XCTAssertEqual(iaqp.county(for: "MNA")?.name, "Monona")
        XCTAssertEqual(iaqp.county(for: "MOE")?.name, "Monroe")
        XCTAssertEqual(iaqp.county(for: "MTG")?.name, "Montgomery")
        XCTAssertEqual(iaqp.county(for: "MRN")?.name, "Marion")
        XCTAssertEqual(iaqp.county(for: "MSL")?.name, "Marshall")
        // Not truncations at all.
        XCTAssertEqual(iaqp.county(for: "BTL")?.name, "Butler")
        XCTAssertNil(iaqp.county(for: "BUT"), "Butler is BTL, not BUT")
        XCTAssertEqual(iaqp.county(for: "HDN")?.name, "Hardin")
        XCTAssertEqual(iaqp.county(for: "BKH")?.name, "Black Hawk")
        XCTAssertEqual(iaqp.county(for: "BNV")?.name, "Buena Vista")
        XCTAssertEqual(iaqp.county(for: "DSM")?.name, "Des Moines")
        XCTAssertEqual(iaqp.county(for: "PLA")?.name, "Palo Alto")
        XCTAssertEqual(iaqp.county(for: "CEG")?.name, "Cerro Gordo")
        XCTAssertEqual(iaqp.county(for: "WNB")?.name, "Winnebago")
        XCTAssertEqual(iaqp.county(for: "WNS")?.name, "Winneshiek")
        // The only bundled county name with an apostrophe.
        XCTAssertEqual(iaqp.county(for: "OBR")?.name, "O'Brien")
        XCTAssertEqual(iaqp.county(for: "obr")?.name, "O'Brien", "case-insensitive")
    }

    func testPartyShape() {
        XCTAssertEqual(iaqp.cabrilloContest, "IAQP")
        XCTAssertEqual(iaqp.homeState, "IA")
        XCTAssertEqual(iaqp.countyAbbrLength, 3)
        XCTAssertEqual(iaqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(iaqp.dxStyle, .token)
        XCTAssertTrue(iaqp.exchangeIncludesRST)
        XCTAssertEqual(iaqp.maxSimultaneousCounties, 4,
                       "Iowa junctions reach four counties — the widest of any party")
        XCTAssertTrue(iaqp.bonuses.isEmpty, "no bonus points, no bonus stations")
        XCTAssertNil(iaqp.scoreMultipliers, "power splits awards only")
        XCTAssertTrue(iaqp.isPartiallyVerified)
        // "any amateur band EXCEPT the 60m, 30m, 17m, and 12m bands"
        for excluded in [Band.m60, .m30, .m17, .m12] {
            XCTAssertFalse(iaqp.validBands.contains(excluded), "\(excluded) is excluded")
        }
        // 1.25 m included — the rules tabulate 222.150 / 223.450 for it.
        for included in [Band.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70] {
            XCTAssertTrue(iaqp.validBands.contains(included), "\(included) is valid")
        }
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(iaqp.points.points(for: .phone), 1)
        XCTAssertEqual(iaqp.points.points(for: .cw), 2)
        XCTAssertEqual(iaqp.points.points(for: .digital), 2)
    }

    // MARK: "Multipliers are applied one time only, NOT per Band, NOT per Mode"

    func testMultipliersCountOnceOnly() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", band: .m40, mode: .cw, their: "STR"),
            qso(call: "W0B", band: .m20, mode: .cw, their: "STR"),      // other band
            qso(call: "W0C", band: .m40, mode: .phone, their: "STR"),   // other mode
            qso(call: "W0D", band: .m80, mode: .digital, their: "STR"),
        ]), party: iaqp)
        XCTAssertEqual(s.multiplierCount, 1, "the sponsor states this outright")
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.qsoPoints, 2 + 2 + 1 + 2)
    }

    // MARK: Iowa stations — Iowa itself counts, DX never does

    /// "one multiplier for each state (including Iowa)" — and Iowa stations send
    /// a county, so Iowa can only be earned through one.
    func testIowaItselfCountsViaCounty() {
        XCTAssertTrue(iaqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "STR", their: "POL")]), party: iaqp)
        XCTAssertEqual(s.workedValues(.county), ["POL"])
        XCTAssertEqual(s.workedValues(.state), ["IA"], "Iowa earned via an Iowa county")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "No multiplier for working DX stations. DX stations still count as QSOs,
    /// so definitely DO work them!" — the first bundled party where DX scores
    /// points but can never be a multiplier.
    func testDXScoresPointsButNeverAMultiplier() {
        XCTAssertFalse(iaqp.multipliers.inState.classes.contains(.dx),
                       "dx is not a multiplier class for Iowa stations")
        XCTAssertFalse(iaqp.multipliers.outState.classes.contains(.dx))

        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "STR", their: "DX"),
            qso(call: "JA1B", my: "STR", their: "DX"),
        ]), party: iaqp)
        XCTAssertEqual(s.validQSOs, 2, "DX contacts are valid QSOs")
        XCTAssertEqual(s.qsoPoints, 4, "and they score points")
        XCTAssertEqual(s.workedValues(.dx), [], "but never a multiplier")
        XCTAssertEqual(s.multiplierCount, 0)
    }

    func testInStateCountsCountiesStatesAndProvinces() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W0A", my: "STR", their: "POL"),   // county (+ IA state)
            qso(call: "K5B", my: "STR", their: "TX"),    // state
            qso(call: "VE3C", my: "STR", their: "ON"),   // province
            qso(call: "DL1D", my: "STR", their: "DX"),   // no mult
        ]), party: iaqp)
        XCTAssertEqual(s.workedValues(.county), ["POL"])
        XCTAssertEqual(s.workedValues(.state), ["IA", "TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.multiplierCount, 4, "POL + IA + TX + ON; DX adds nothing")
    }

    /// The sponsor's own state list prints "MD  Maryland and DC".
    func testDCCountsAsMaryland() {
        XCTAssertEqual(iaqp.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K3A", my: "STR", their: "DC"),
            qso(call: "K3B", my: "STR", their: "MD"),
        ]), party: iaqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "one multiplier, not two")
    }

    /// Unlike NJQP, Iowa's official list uses the modern NL spelling.
    func testProvincesUseStandardThirteenWithNL() {
        XCTAssertEqual(iaqp.provinces, MultClass.canadianProvinces, "the standard 13")
        XCTAssertTrue(iaqp.validOutStateTokens.contains("NL"))
        XCTAssertFalse(iaqp.validOutStateTokens.contains("NF"),
                       "NF is NJQP's spelling, not Iowa's")
    }

    // MARK: Out-of-state entrants count Iowa counties only

    func testOutOfStateGetsCountiesOnly() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", their: "STR"),
            qso(call: "W0B", their: "POL"),
        ]), party: iaqp)
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertEqual(s.workedValues(.state), [], "no state class, so no IA either")
    }

    func testOutOfStateEarnsNothingForNonIowaContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", their: "STR"),
            qso(call: "K5B", their: "TX"),
        ]), party: iaqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1,
                       "shipped restrictive; see iaqp_rules.md §14.7 — this is an "
                           + "open question with the sponsor")
    }

    // MARK: Four-county junctions, in a single exchange

    /// The rules' own example: "you are 59 in Story STR, Marshall MSL, and
    /// Hardin HDN counties".
    func testThreeCountyJunctionFromTheRulesExample() throws {
        XCTAssertEqual(
            try ExchangeParser.parse("STR/MSL/HDN", party: iaqp, role: .inState).get().locations,
            ["STR", "MSL", "HDN"]
        )
    }

    func testFourCountyJunctionIsTheLimit() throws {
        XCTAssertEqual(
            try ExchangeParser.parse("STR/MSL/HDN/BOO", party: iaqp, role: .inState).get().locations,
            ["STR", "MSL", "HDN", "BOO"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("STR/MSL/HDN/BOO/POL", party: iaqp, role: .inState),
            .failure(.tooManyCounties(5))
        )
    }

    /// Each county at a junction is its own multiplier.
    func testEveryCountyAtAJunctionScores() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0YL", their: "STR"),
            qso(call: "W0YL", their: "MSL"),
            qso(call: "W0YL", their: "HDN"),
        ]), party: iaqp)
        XCTAssertEqual(s.validQSOs, 3, "one row per county, none a dupe")
        XCTAssertEqual(s.multiplierCount, 3)
    }

    // MARK: Dupes

    func testDupesAndMobileCountyChange() {
        let a = qso(call: "W0M", band: .m40, mode: .cw, their: "POL")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "W0M", band: .m40, mode: .phone, their: "POL")
        let moved = qso(call: "W0M", band: .m40, mode: .cw, their: "STR")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, moved]), party: iaqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3,
                       "'Iowa Mobile/Rover stations may work all stations AGAIN for "
                           + "each county that they operate from'")
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("str", party: iaqp, role: .inState).get().locations, ["STR"])
        XCTAssertEqual(try ExchangeParser.parse("OBR", party: iaqp, role: .inState).get().locations, ["OBR"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: iaqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: iaqp, role: .inState).get().locations, ["DX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: iaqp, role: .inState).get().locations, ["DC"],
                       "loggable, credited as Maryland")
        guard case .failure = ExchangeParser.parse("IA", party: iaqp, role: .inState) else {
            return XCTFail("IA must be rejected — Iowa stations send a county")
        }
    }

    // MARK: Schedule — third Saturday of September, 12 hours

    func testSchedule() throws {
        let windows = try XCTUnwrap(iaqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-09-19T14:00:00Z"),
                       "9AM US Central on the third Saturday of September")
        XCTAssertEqual(windows[0].end, f.date(from: "2026-09-20T02:00:00Z"), "9PM Central")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600)
    }

    func testNotesRecordTheOpenQuestions() throws {
        let notes = iaqp.notes ?? ""
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("iowaqsoparty@hotmail.com"))
        let questions = try XCTUnwrap(iaqp.openQuestions)
        XCTAssertTrue(questions.contains("2025"), "the posted rules are still the 2025 edition")
    }
}

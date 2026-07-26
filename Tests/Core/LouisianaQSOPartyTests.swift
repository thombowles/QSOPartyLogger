import XCTest
@testable import QSOPartyLogger

/// Louisiana QSO Party — Louisiana Contest Club (`N5LCC`). Built from the
/// sponsor's rules page and its official parish abbreviation list, read verbatim
/// 2026-07-26. See docs/research/laqp_rules.md.
///
/// **The first bundled party whose home entities are parishes**, and the second
/// after ILQP to group CW with digital as one mode — but the first where that
/// grouping moves the *score*, because LAQP counts multipliers per band and mode.
final class LouisianaQSOPartyTests: XCTestCase {

    var laqp: PartyDefinition!

    override func setUpWithError() throws {
        laqp = try XCTUnwrap(PartyCatalog.party(id: "laqp"), "bundled LAQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W5ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "ORLE"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_775_311_200 + seq),  // 2026-04-04 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "laqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from parish: String = "ORLE",
               station: StationProfile.CategoryStation = .fixed) -> ContestLog {
        var log = ContestLog(partyID: "laqp")
        log.myLocation = .inState(counties: [parish])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: Parishes — 64, mixed 3/4, and nine "St." names

    func testParishData() {
        XCTAssertEqual(laqp.counties.count, 64, "Louisiana has 64 parishes, not counties")
        XCTAssertEqual(Set(laqp.counties.map(\.abbr)).count, 64)
        XCTAssertEqual(Set(laqp.counties.map(\.name)).count, 64)
        XCTAssertEqual(laqp.countyAbbrLengths, [3, 4])
        XCTAssertEqual(laqp.countyAbbrLengthHint, "3/4")
    }

    /// Exactly five codes are three characters, all contractions of long names.
    func testTheFiveThreeCharacterCodes() {
        let three = Set(laqp.counties.filter { $0.abbr.count == 3 }.map(\.abbr))
        XCTAssertEqual(three, ["EBR", "WBR", "PCP", "SJB", "SMT"])
        XCTAssertEqual(laqp.county(for: "EBR")?.name, "East Baton Rouge")
        XCTAssertEqual(laqp.county(for: "WBR")?.name, "West Baton Rouge")
        XCTAssertEqual(laqp.county(for: "PCP")?.name, "Pointe Coupee")
    }

    /// **Nine `St.` parishes and no two follow the same pattern.** The worst pair
    /// is `SMT` St. Martin against `SMAR` St. Mary — three characters against
    /// four, for two names three letters apart.
    func testTheNineStParishes() {
        XCTAssertEqual(laqp.counties.filter { $0.name.hasPrefix("St. ") }.count, 9)
        XCTAssertEqual(laqp.county(for: "SMT")?.name, "St. Martin")
        XCTAssertEqual(laqp.county(for: "SMAR")?.name, "St. Mary")
        XCTAssertEqual(laqp.county(for: "SBND")?.name, "St. Bernard")
        XCTAssertEqual(laqp.county(for: "SCHL")?.name, "St. Charles")
        XCTAssertEqual(laqp.county(for: "SJB")?.name, "St. John Baptist",
                       "the sponsor drops the 'the' of St. John the Baptist Parish")
        XCTAssertEqual(laqp.county(for: "STAM")?.name, "St. Tammany")
    }

    /// East/West triples, of which only the Baton Rouges contract; and the two
    /// Jeffersons.
    func testTheEastWestPairsAndTheTwoJeffersons() {
        XCTAssertEqual(laqp.county(for: "ECAR")?.name, "East Carroll")
        XCTAssertEqual(laqp.county(for: "WCAR")?.name, "West Carroll")
        XCTAssertEqual(laqp.county(for: "EFEL")?.name, "East Feliciana")
        XCTAssertEqual(laqp.county(for: "WFEL")?.name, "West Feliciana")
        XCTAssertEqual(laqp.county(for: "JEFF")?.name, "Jefferson")
        XCTAssertEqual(laqp.county(for: "JFDV")?.name, "Jefferson Davis")
        XCTAssertEqual(laqp.county(for: "orle")?.name, "Orleans", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(laqp.cabrilloContest, "LA-QSO-PARTY", "WA7BNM; the rules print none")
        XCTAssertEqual(laqp.homeState, "LA")
        XCTAssertEqual(laqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(laqp.dxStyle, .prefix, "'state/province/country', and DXCC is a multiplier")
        XCTAssertTrue(laqp.exchangeIncludesRST)
        XCTAssertFalse(laqp.exchangeIncludesSerial)
        XCTAssertNil(laqp.scoreMultipliers, "power selects the award only")
        XCTAssertTrue(laqp.isPartiallyVerified)
    }

    func testEightBandsNoWARC() {
        XCTAssertEqual(laqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for excluded in [Band.m60, .m30, .m17, .m12, .cm125, .cm70] {
            XCTAssertFalse(laqp.validBands.contains(excluded))
        }
    }

    // MARK: Points

    /// "two (2) points for each complete PHONE QSO … four (4) points for each
    /// complete CW/Digital QSO" — CW at 4 ties BCQP for the highest here.
    func testPointsByMode() {
        XCTAssertEqual(laqp.points.points(for: .phone), 2)
        XCTAssertEqual(laqp.points.points(for: .cw), 4)
        XCTAssertEqual(laqp.points.points(for: .digital), 4)
    }

    // MARK: Multipliers — per band AND mode

    /// "64 possible per band/mode" is what fixes the scope. Neither a second band
    /// nor a second mode may be free.
    func testMultipliersCountPerBandAndMode() {
        XCTAssertEqual(laqp.multipliers.inState.countScope, .perBandMode)
        XCTAssertEqual(laqp.multipliers.outState.countScope, .perBandMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", band: .m20, mode: .cw, their: "ORLE"),
            qso(call: "W5A", band: .m20, mode: .phone, their: "ORLE"),
            qso(call: "W5A", band: .m40, mode: .cw, their: "ORLE"),
        ]), party: laqp)
        XCTAssertEqual(s.multiplierCount, 3, "one parish, three band/mode slots")
    }

    func testOutOfStateCountsParishesOnly() {
        XCTAssertEqual(Set(laqp.multipliers.outState.classes), [.county])
        let rows = laqp.counties.enumerated().map { i, c in qso(call: "W5\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: laqp).multiplierCount, 64)
    }

    /// "States (**other than Louisiana**)" — stated outright, in the negative.
    func testLouisianaIsNotAStateMultiplier() {
        XCTAssertFalse(laqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "ORLE", their: "CADD")]), party: laqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(laqp.validOutStateTokens.contains("LA"))
    }

    /// The 13 standard provinces — and the sponsor explains why it dropped the
    /// Maritime sub-regions it once counted.
    func testTheStandardThirteenProvinces() {
        XCTAssertEqual(laqp.provinces, MultClass.canadianProvinces)
        XCTAssertTrue(laqp.validOutStateTokens.contains("NL"))
    }

    func testInStateCountsParishesStatesProvincesAndDXCC() {
        XCTAssertEqual(Set(laqp.multipliers.inState.classes), [.county, .state, .province, .dx])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W5A", my: "ORLE", their: "CADD"),
            qso(call: "K5B", my: "ORLE", their: "TX"),
            qso(call: "VE3C", my: "ORLE", their: "ON"),
            qso(call: "DL1D", my: "ORLE", their: "DL"),
        ]), party: laqp)
        XCTAssertEqual(s.multiplierCount, 4)
    }

    // MARK: The mode-grouping gap — and here it moves the score

    /// **KNOWN LIMITATION, pinned.** The sponsor's split is two-way: "once on
    /// CW/Digital and once on Phone PER BAND", and "CW/Digital and Phone contacts
    /// count as separate multipliers". This app keys on three mode classes.
    ///
    /// ILQP has the identical rule, but there it touched only dupe accounting,
    /// because ILQP counts multipliers **once overall**. LAQP counts them **per
    /// band and mode**, so the over-count reaches the final score — which is what
    /// this test shows.
    func testKnownGapCWAndDigitalAreOneModeForTheSponsorAndTwoHere() throws {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5M", band: .m20, mode: .cw, their: "ORLE"),
            qso(call: "W5M", band: .m20, mode: .digital, their: "ORLE"),
        ]), party: laqp)
        XCTAssertEqual(s.dupeCount, 0, "current behaviour — three mode classes, so no dupe")
        XCTAssertEqual(s.validQSOs, 2, "the sponsor counts one")
        XCTAssertEqual(s.multiplierCount, 2,
                       "AND two multipliers, where the sponsor counts one — this is the "
                           + "difference from ILQP, whose multipliers count once overall")

        // The contrast, made explicit: ILQP's identical rule costs no multiplier.
        let ilqp = try XCTUnwrap(PartyCatalog.party(id: "ilqp"))
        XCTAssertEqual(ilqp.multipliers.outState.countScope, .once)
        XCTAssertEqual(laqp.multipliers.outState.countScope, .perBandMode)

        XCTAssertTrue(try XCTUnwrap(laqp.notes).contains("KNOWN LIMITATION"))
    }

    // MARK: Bonuses

    /// "Any station working N5LCC … may claim a **one-time** 100 POINT BONUS."
    func testN5LCCPaysOneHundredOnce() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "N5LCC", band: .m20, mode: .cw, their: "ORLE"),
            qso(call: "N5LCC", band: .m40, mode: .cw, their: "ORLE"),
            qso(call: "N5LCC", band: .m20, mode: .phone, their: "ORLE"),
        ]), party: laqp)
        XCTAssertEqual(s.bonusPoints, 100, "'one-time' — not per band, not per mode")
    }

    /// "PLUS **50 points per Parish activated**" — no QSO threshold is stated.
    func testFiftyPointsPerParishActivated() {
        XCTAssertEqual(laqp.bonuses, [
            .workStation(call: "N5LCC", points: 100, scope: .once),
            .activatedCountyCount(minQSOs: 1, points: 50),
        ])
        var log = inLog([
            qso(call: "W5A", my: "ORLE", their: "TX"),
            qso(call: "W5B", my: "CADD", their: "MD"),
        ], station: .rover)
        log.myLocation = .inState(counties: ["ORLE"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: laqp).bonusPoints, 100,
                       "50 for each of two parishes, one QSO each")
    }

    // MARK: Parish lines — two, logged separately

    /// "Rovers who are PRECISELY on a parish line may give contacts for both
    /// parishes, however, a separate and complete QSO and log entry must be made
    /// for each contact."
    func testParishLineIsTwoAndLogsAsTwoRows() throws {
        XCTAssertEqual(laqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            ExchangeParser.parse("ORLE/JEFF/SBND", party: laqp, role: .inState),
            .failure(.tooManyCounties(3))
        )
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W5ROV", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_775_311_200)
            ),
            myLocs: ["TX"],
            theirLocs: ["ORLE", "JEFF"]
        )
        XCTAssertEqual(rows.count, 2)
        let s = ScoreEngine.score(log: outLog(rows), party: laqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 8, "CW 4 points each")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange and credit

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("orle", party: laqp, role: .inState).get().locations,
                       ["ORLE"])
        XCTAssertEqual(try ExchangeParser.parse("EBR", party: laqp, role: .inState).get().locations,
                       ["EBR"], "a 3-character code alongside the 4s")
        XCTAssertEqual(try ExchangeParser.parse("TX", party: laqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: laqp, role: .inState).get().locations,
                       ["DL"])
        guard case .failure = ExchangeParser.parse("LA", party: laqp, role: .inState) else {
            return XCTFail("LA must be rejected — Louisiana stations send a parish")
        }
    }

    /// Rule 1.2: "Non-Louisiana stations work Louisiana stations only."
    func testOutOfStateEntrantsGetNoCreditForNonLouisianaContacts() {
        XCTAssertTrue(laqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", their: "ORLE"),
            qso(call: "K5B", their: "TX"),
        ]), party: laqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — derived, and the derivation is the open question

    /// **The sponsor publishes no 2026 date.** Rule 2 still prints the 2025
    /// running. This window rests on the stable 1400Z–0200Z shape, on "first
    /// Saturday in April" fitting both 2025 and the sponsor's archived "2020 LAQP
    /// is April 4th", and on the Challenge calendar agreeing — but **no formula
    /// is stated**, which is why the party ships partial.
    func testScheduleIsDerivedForTheFirstSaturdayInApril() throws {
        let windows = try XCTUnwrap(laqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-04T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-05T02:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.month, from: windows[0].start), 4)
        XCTAssertLessThanOrEqual(utc.component(.day, from: windows[0].start), 7,
                                 "the first Saturday in April")

        XCTAssertTrue(try XCTUnwrap(laqp.openQuestions).contains("questions@laqp.org"))
    }

    func testNotesRecordTheDerivedDateAndTheModeGap() throws {
        let notes = try XCTUnwrap(laqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("THE 2026 DATE IS DERIVED, NOT PUBLISHED"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION"))
        XCTAssertTrue(notes.contains("THE FIRST BUNDLED PARTY WHOSE HOME ENTITIES ARE PARISHES"))
    }
}

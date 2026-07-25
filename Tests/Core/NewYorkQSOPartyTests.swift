import XCTest
@testable import QSOPartyLogger

/// New York QSO Party — Rochester (NY) DX Association rules PDF, `v1.2 FINAL
/// 2025-10-01`, with county codes cross-checked against the sponsor's official
/// CSV. Both read verbatim 2026-07-24. See docs/research/nyqp_rules.md.
///
/// The first party where digital outscores CW, the first to state its own
/// Cabrillo `CONTEST:` value, and the first to put a numeric maximum on
/// county-line credit.
final class NewYorkQSOPartyTests: XCTestCase {

    var nyqp: PartyDefinition!

    override func setUpWithError() throws {
        nyqp = try XCTUnwrap(PartyCatalog.party(id: "nyqp"), "bundled NYQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W2ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "MON"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_792_200_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "nyqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "MON") -> ContestLog {
        var log = ContestLog(partyID: "nyqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 62, from two sponsor sources that agree

    func testCountyData() {
        XCTAssertEqual(nyqp.counties.count, 62, "'New York Counties (62)'")
        XCTAssertEqual(Set(nyqp.counties.map(\.abbr)).count, 62)
        XCTAssertEqual(Set(nyqp.counties.map(\.name)).count, 62)
        XCTAssertTrue(nyqp.counties.allSatisfy { $0.abbr.count == 3 })
        XCTAssertEqual(nyqp.countyAbbrLengths, [3])
    }

    /// The near-collision clusters. `ALB`→Albany would prove nothing; these are
    /// the ones a transcription error lands on.
    func testNearCollisionClusters() {
        // Chautauqua / Chemung / Chenango — and CGO breaks the pattern outright.
        XCTAssertEqual(nyqp.county(for: "CHA")?.name, "Chautauqua")
        XCTAssertEqual(nyqp.county(for: "CHE")?.name, "Chemung")
        XCTAssertEqual(nyqp.county(for: "CGO")?.name, "Chenango", "not CHE — CGO, uniquely")
        // Three Sch- counties.
        XCTAssertEqual(nyqp.county(for: "SCH")?.name, "Schenectady")
        XCTAssertEqual(nyqp.county(for: "SCO")?.name, "Schoharie")
        XCTAssertEqual(nyqp.county(for: "SCU")?.name, "Schuyler")
        // Steuben vs St. Lawrence, the only county with a period in its name.
        XCTAssertEqual(nyqp.county(for: "STE")?.name, "Steuben")
        XCTAssertEqual(nyqp.county(for: "STL")?.name, "St. Lawrence")
        // On- and Or- clusters.
        XCTAssertEqual(nyqp.county(for: "ONE")?.name, "Oneida")
        XCTAssertEqual(nyqp.county(for: "ONO")?.name, "Onondaga")
        XCTAssertEqual(nyqp.county(for: "ONT")?.name, "Ontario")
        XCTAssertEqual(nyqp.county(for: "ORA")?.name, "Orange")
        XCTAssertEqual(nyqp.county(for: "ORL")?.name, "Orleans")
        XCTAssertEqual(nyqp.county(for: "MTG")?.name, "Montgomery")
        XCTAssertEqual(nyqp.county(for: "mon")?.name, "Monroe", "case-insensitive")
    }

    /// The five New York City boroughs are counties, and none of their codes is
    /// obvious — `BRM` (Broome, upstate) is one letter from `BRX` (Bronx).
    func testNewYorkCityBoroughs() {
        XCTAssertEqual(nyqp.county(for: "BRX")?.name, "Bronx")
        XCTAssertEqual(nyqp.county(for: "KIN")?.name, "Kings", "Brooklyn")
        XCTAssertEqual(nyqp.county(for: "NEW")?.name, "New York", "Manhattan")
        XCTAssertEqual(nyqp.county(for: "QUE")?.name, "Queens")
        XCTAssertEqual(nyqp.county(for: "RIC")?.name, "Richmond", "Staten Island")
        XCTAssertEqual(nyqp.county(for: "BRM")?.name, "Broome", "not the Bronx")
    }

    func testPartyShape() {
        XCTAssertEqual(nyqp.cabrilloContest, "NY-QSO-PARTY",
                       "published by the sponsor in its own sample Cabrillo header")
        XCTAssertEqual(nyqp.homeState, "NY")
        XCTAssertEqual(nyqp.dxStyle, .token, "'send signal report and \"DX.\"'")
        XCTAssertTrue(nyqp.exchangeIncludesRST)
        XCTAssertFalse(nyqp.exchangeIncludesSerial)
        XCTAssertEqual(nyqp.dupeScope, .bandMode)
        XCTAssertTrue(nyqp.bonuses.isEmpty, "no bonus station anywhere in 17 pages")
        XCTAssertNil(nyqp.scoreMultipliers, "power decides the award, not the score")
        XCTAssertTrue(nyqp.outStateWorksHomeStationsOnly)
        XCTAssertTrue(nyqp.isPartiallyVerified, "the rules are the 2025 edition")
    }

    // MARK: Points — digital outscores CW here, uniquely

    func testDigitalIsLegalAndPaysMost() {
        XCTAssertEqual(nyqp.points.points(for: .phone), 1)
        XCTAssertEqual(nyqp.points.points(for: .cw), 2)
        XCTAssertEqual(nyqp.points.points(for: .digital), 3,
                       "the first bundled party where digital beats CW")
        XCTAssertEqual(nyqp.allowedModeClasses, ModeClass.allCases)

        let s = ScoreEngine.score(log: outLog([
            qso(call: "W2A", band: .m40, mode: .phone, their: "MON"),
            qso(call: "W2A", band: .m40, mode: .cw, their: "MON"),
            qso(call: "W2A", band: .m40, mode: .digital, their: "MON"),
        ]), party: nyqp)
        XCTAssertEqual(s.validQSOs, 3, "'a maximum of three contacts per station' per band")
        XCTAssertEqual(s.qsoPoints, 6, "1 + 2 + 3")
        XCTAssertEqual(s.multiplierCount, 1, "one county, counted once")
    }

    /// A fourth contact on the same band and mode is the dupe.
    func testFourthContactOnABandIsADupe() {
        var rows = [
            qso(call: "W2A", band: .m40, mode: .phone, their: "MON"),
            qso(call: "W2A", band: .m40, mode: .cw, their: "MON"),
            qso(call: "W2A", band: .m40, mode: .digital, their: "MON"),
        ]
        rows.append(qso(call: "W2A", band: .m40, mode: .cw, their: "MON"))
        let s = ScoreEngine.score(log: outLog(rows), party: nyqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.dupeCount, 1)
    }

    // MARK: Multipliers — the sponsor's 125 closes exactly

    /// "Count US states (50), New York Counties (62) and Canadian provinces (13)
    /// … Maximum of 125 multipliers."
    func testInStateCeilingIs125() {
        var rows: [QSO] = []
        var n = 0
        for county in nyqp.counties.map(\.abbr) {
            n += 1
            rows.append(qso(call: "W2\(n)", my: "MON", their: county))
        }
        for state in MultClass.usStates.subtracting(["NY"]).sorted() {
            n += 1
            rows.append(qso(call: "K\(n)AA", my: "MON", their: state))
        }
        for province in MultClass.canadianProvinces.sorted() {
            n += 1
            rows.append(qso(call: "VE\(n)AA", my: "MON", their: province))
        }
        let s = ScoreEngine.score(log: inLog(rows), party: nyqp)
        XCTAssertEqual(s.workedValues(.county).count, 62)
        XCTAssertEqual(s.workedValues(.state).count, 50, "49 worked + NY via a county")
        XCTAssertEqual(s.workedValues(.province).count, 13)
        XCTAssertEqual(s.multiplierCount, 125, "the rules' own stated maximum")
    }

    func testOutOfStateCeilingIs62() {
        let rows = nyqp.counties.enumerated().map { i, c in qso(call: "W2\(i)", their: c.abbr) }
        let s = ScoreEngine.score(log: outLog(rows), party: nyqp)
        XCTAssertEqual(s.multiplierCount, 62)
    }

    /// "The first valid New York county logged will count as the multiplier for
    /// New York" — stated outright, and required for 125 to close.
    func testNewYorkIsEarnedViaACounty() {
        XCTAssertTrue(nyqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W2A", my: "MON", their: "ULS"),
            qso(call: "W2B", my: "MON", their: "SUF"),
        ]), party: nyqp)
        XCTAssertEqual(s.workedValues(.state), ["NY"], "both counties yield the one NY mult")
        XCTAssertEqual(s.workedValues(.county), ["ULS", "SUF"])
        XCTAssertEqual(s.multiplierCount, 3, "two counties plus NY")
        XCTAssertFalse(nyqp.validOutStateTokens.contains("NY"), "NY is never sent as a token")
    }

    func testOutOfStateGetsNoNewYorkStateMultiplier() {
        XCTAssertFalse(nyqp.multipliers.outState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: outLog([qso(their: "MON")]), party: nyqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testMultipliersCountOnceNotPerBandOrMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W2A", band: .m40, mode: .cw, their: "MON"),
            qso(call: "W2A", band: .m20, mode: .cw, their: "MON"),
            qso(call: "W2A", band: .m40, mode: .phone, their: "MON"),
        ]), party: nyqp)
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.validQSOs, 3)
    }

    /// "DX counts as QSO points but not multipliers" — for either side.
    func testDXScoresPointsButIsNeverAMultiplier() {
        XCTAssertFalse(nyqp.multipliers.inState.classes.contains(.dx))
        XCTAssertFalse(nyqp.multipliers.outState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", mode: .cw, my: "MON", their: "DX"),
            qso(call: "JA1B", band: .m20, mode: .digital, my: "MON", their: "DX"),
        ]), party: nyqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 5, "CW 2 + digital 3")
        XCTAssertEqual(s.multiplierCount, 0)
    }

    // MARK: Bands — eleven, including 60 m

    func testElevenBandsIncluding60m() {
        XCTAssertEqual(
            nyqp.validBands,
            [.m160, .m80, .m60, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70],
            "'All FCC allocated amateur frequencies (excluding the 30, 17, and 12 meter bands)'"
        )
        for warc in [Band.m30, .m17, .m12] {
            XCTAssertFalse(nyqp.validBands.contains(warc), "\(warc.rawValue) is excluded")
        }
        XCTAssertTrue(nyqp.validBands.contains(.m60),
                      "only three bands are excluded, so 60 m is in on a literal reading")
    }

    /// The sponsor's own sample log has 902 MHz, 1.2 GHz and 10 GHz QSOs, which
    /// this app cannot express — recorded in notes rather than silently dropped.
    func testMicrowaveLimitationIsRecorded() throws {
        XCTAssertTrue(try XCTUnwrap(nyqp.notes).contains("KNOWN LIMITATION"))
        XCTAssertTrue(try XCTUnwrap(nyqp.notes).contains("10 GHz"))
    }

    // MARK: County lines — a stated maximum of two

    /// "If the portable or mobile station is operating from the intersection of
    /// three or more NY counties, only two counties at a time may be counted for
    /// the same contact."
    func testCountyLineLimitIsTwo() throws {
        XCTAssertEqual(nyqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            try ExchangeParser.parse("DUT/PUT", party: nyqp, role: .inState).get().locations,
            ["DUT", "PUT"],
            "the sponsor's own CW example, 'KX2NY 599 DUT/PUT'"
        )
        XCTAssertEqual(
            ExchangeParser.parse("DUT/PUT/ORA", party: nyqp, role: .inState),
            .failure(.tooManyCounties(3)),
            "three or more counties still credit only two at a time"
        )
    }

    /// "County line exchanges should be logged as two separate QSOs."
    func testCountyLineExpandsToTwoQSOs() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "KX2NY", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_792_200_000)
            ),
            myLocs: ["TX"],
            theirLocs: ["DUT", "PUT"]
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.groupID)).count, 1)
        let s = ScoreEngine.score(log: outLog(rows), party: nyqp)
        XCTAssertEqual(s.validQSOs, 2, "both stations get credit for both counties")
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertEqual(s.qsoPoints, 4, "CW 2 points each")
    }

    /// "New York stations that change counties are considered to be a new station
    /// and may be contacted again for points and multiplier credit."
    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W2MOB", band: .m40, mode: .cw, their: "ONE"),
            qso(call: "W2MOB", band: .m40, mode: .cw, their: "ONO"),
        ]), party: nyqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Scope of credit and exchange parsing

    func testOutOfStateEntrantsGetNoCreditForNonNewYorkContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W2A", their: "MON"),
            qso(call: "K5B", their: "TX"),
        ]), party: nyqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("mon", party: nyqp, role: .inState).get().locations, ["MON"])
        XCTAssertEqual(try ExchangeParser.parse("STL", party: nyqp, role: .inState).get().locations, ["STL"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: nyqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("ON", party: nyqp, role: .inState).get().locations, ["ON"],
                       "the standard 13 provinces")
        XCTAssertEqual(try ExchangeParser.parse("DX", party: nyqp, role: .inState).get().locations, ["DX"])
        guard case .failure = ExchangeParser.parse("NY", party: nyqp, role: .inState) else {
            return XCTFail("NY must be rejected — New York stations send a county")
        }
    }

    // MARK: Schedule — the third Saturday, 12 hours

    func testScheduleIsOneTwelveHourWindow() throws {
        let windows = try XCTUnwrap(nyqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-10-17T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-10-18T02:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600,
                       "the rules' own '12 Hours'")

        // "Third Saturday in October": 17 October 2026.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 17)

        // "1400 UTC (10 AM Eastern)" — still EDT, since DST ends 1 November 2026.
        let eastern = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(eastern.secondsFromGMT(for: windows[0].start), -4 * 3600)
        var edt = Calendar(identifier: .gregorian)
        edt.timeZone = eastern
        XCTAssertEqual(edt.component(.hour, from: windows[0].start), 10, "10 AM Eastern")
        XCTAssertEqual(edt.component(.hour, from: windows[0].end), 22,
                       "the rules' 01:59:59 UTC end, stored as the exclusive 02:00 instant")
    }

    func testNotesRecordBothOpenQuestionsAndThe60mReading() throws {
        let notes = try XCTUnwrap(nyqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("60 M IS INCLUDED"),
                      "no other bundled party permits 60 m — the reading must be visible")
        let questions = try XCTUnwrap(nyqp.openQuestions)
        XCTAssertTrue(questions.contains("2025 edition"))
        XCTAssertTrue(questions.contains("only New York stations"))
    }
}

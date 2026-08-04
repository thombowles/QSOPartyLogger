import XCTest
@testable import QSOPartyLogger

/// Illinois QSO Party — Western Illinois ARC rules, "Announcing the 2025 Illinois
/// QSO Party", with the club's official county abbreviation list. Both read
/// verbatim 2026-07-24. See docs/research/ilqp_rules.md.
///
/// The last party of the 2026 season: the shortest window (8 hours), the only
/// Sunday-only party, and the only one whose rules name their own worst
/// abbreviation traps.
final class IllinoisQSOPartyTests: XCTestCase {

    var ilqp: PartyDefinition!

    override func setUpWithError() throws {
        ilqp = try XCTUnwrap(PartyCatalog.party(id: "ilqp"), "bundled ILQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W9ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "COOK"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_792_300_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "ilqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "COOK") -> ContestLog {
        var log = ContestLog(partyID: "ilqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 102, and LEE is the odd one out

    func testCountyData() {
        XCTAssertEqual(ilqp.counties.count, 102, "Illinois has 102 counties")
        XCTAssertEqual(Set(ilqp.counties.map(\.abbr)).count, 102)
        XCTAssertEqual(Set(ilqp.counties.map(\.name)).count, 102)
    }

    /// "Each Illinois county has an established 4 letter abbreviation (Lee County
    /// excepted)" — the third party after the Salmon Run and SDQP to mix lengths.
    func testLeeIsTheOnlyThreeLetterCode() {
        XCTAssertEqual(ilqp.countyAbbrLengths, [3, 4])
        XCTAssertEqual(ilqp.countyAbbrLengthHint, "3/4")
        XCTAssertEqual(ilqp.counties.filter { $0.abbr.count == 3 }.map(\.abbr), ["LEE"])
        XCTAssertEqual(ilqp.county(for: "LEE")?.name, "Lee")
        XCTAssertEqual(ilqp.counties.filter { $0.abbr.count == 4 }.count, 101)
    }

    /// The rules name their own worst traps, which makes them the best possible
    /// spot checks: "This often involves White (WHIT) and Whiteside (WTSD)
    /// counties as well as Mason (MASN) and Macon (MACN) counties."
    func testTheTrapsTheRulesThemselvesName() {
        XCTAssertEqual(ilqp.county(for: "WHIT")?.name, "White")
        XCTAssertEqual(ilqp.county(for: "WTSD")?.name, "Whiteside")
        XCTAssertEqual(ilqp.county(for: "MASN")?.name, "Mason")
        XCTAssertEqual(ilqp.county(for: "MACN")?.name, "Macon")
    }

    /// The website FAQ says Macon "should be MCON", while the county list and the
    /// rules both say MACN. Two sponsor documents to one, and this pins the
    /// winner so the FAQ's spelling is not mistaken for a correction later.
    func testMaconIsMACNNotMCON() {
        XCTAssertEqual(ilqp.county(for: "MACN")?.name, "Macon")
        XCTAssertNil(ilqp.county(for: "MCON"),
                     "the FAQ's MCON contradicts both the county list and the rules")
    }

    func testOtherIrregularAbbreviations() {
        XCTAssertEqual(ilqp.county(for: "BURO")?.name, "Bureau")
        XCTAssertEqual(ilqp.county(for: "CHRS")?.name, "Christian")
        XCTAssertEqual(ilqp.county(for: "CLRK")?.name, "Clark")
        XCTAssertEqual(ilqp.county(for: "CLAY")?.name, "Clay")
        XCTAssertEqual(ilqp.county(for: "CLNT")?.name, "Clinton")
        XCTAssertEqual(ilqp.county(for: "JODA")?.name, "JoDaviess")
        XCTAssertEqual(ilqp.county(for: "LASA")?.name, "LaSalle")
        XCTAssertEqual(ilqp.county(for: "MCPN")?.name, "Macoupin")
        XCTAssertEqual(ilqp.county(for: "MCDN")?.name, "McDonough")
        XCTAssertEqual(ilqp.county(for: "ROCK")?.name, "Rock Island")
        XCTAssertEqual(ilqp.county(for: "TAZW")?.name, "Tazewell")
        XCTAssertEqual(ilqp.county(for: "SCLA")?.name, "St. Clair",
                       "the same code CQP uses for Santa Clara, in a different party")
        XCTAssertEqual(ilqp.county(for: "cook")?.name, "Cook", "case-insensitive")
    }

    func testPartyShape() {
        XCTAssertEqual(ilqp.cabrilloContest, "IL-QSO-PARTY", "WA7BNM; sponsor prints none")
        XCTAssertEqual(ilqp.homeState, "IL")
        XCTAssertEqual(ilqp.allowedModeClasses, ModeClass.allCases,
                       "phone and CW/digital are all legal")
        XCTAssertEqual(ilqp.dxStyle, .prefix, "'others give RS/T and state, province or country'")
        XCTAssertTrue(ilqp.exchangeIncludesRST)
        XCTAssertFalse(ilqp.exchangeIncludesSerial)
        XCTAssertNil(ilqp.scoreMultipliers, "power decides the award, not the score")
        XCTAssertTrue(ilqp.isPartiallyVerified)
    }

    /// "160 through 2 meters, excluding WARC bands (60, 30, 17 and 12 meters)" —
    /// the sponsor counts 60 m among the WARC bands, which is loose but
    /// unambiguous, and the exact opposite of NYQP.
    func testEightBandsWith60mExcluded() {
        XCTAssertEqual(ilqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for excluded in [Band.m60, .m30, .m17, .m12] {
            XCTAssertFalse(ilqp.validBands.contains(excluded), "\(excluded.rawValue) is excluded")
        }
        for above2m in [Band.cm125, .cm70] {
            XCTAssertFalse(ilqp.validBands.contains(above2m), "'160 through 2 meters' caps the list")
        }
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(ilqp.points.points(for: .phone), 1)
        XCTAssertEqual(ilqp.points.points(for: .cw), 2)
        XCTAssertEqual(ilqp.points.points(for: .digital), 2, "'CW/digital QSO 2 points'")
    }

    // MARK: Multipliers — once each, with a five-entity DX cap

    func testMultipliersCountOnce() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9A", band: .m40, mode: .cw, their: "COOK"),
            qso(call: "W9A", band: .m20, mode: .cw, their: "COOK"),
            qso(call: "W9A", band: .m40, mode: .phone, their: "COOK"),
        ]), party: ilqp)
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 5, "CW 2 + CW 2 + phone 1")
    }

    func testOutOfStateCeilingIs102() {
        let rows = ilqp.counties.enumerated().map { i, c in qso(call: "W9\(i)", their: c.abbr) }
        let s = ScoreEngine.score(log: outLog(rows), party: ilqp)
        XCTAssertEqual(s.multiplierCount, 102)
    }

    func testInStateCountsEverything() {
        XCTAssertEqual(Set(ilqp.multipliers.inState.classes), [.county, .state, .province, .dx])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W9A", my: "COOK", their: "LEE"),
            qso(call: "K5B", my: "COOK", their: "TX"),
            qso(call: "VE3C", my: "COOK", their: "ON"),
            qso(call: "DL1D", my: "COOK", their: "DL"),
        ]), party: ilqp)
        XCTAssertEqual(s.workedValues(.county), ["LEE"])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["Germany"])
        XCTAssertEqual(s.multiplierCount, 4)
    }

    /// "DXCC countries (maximum 5) … Additional DX contacts count for points but
    /// not multipliers." The lowest cap after PAQP's 1, and one this app can
    /// honour because ILQP's DX exchange is a prefix.
    func testDXCapIsFiveAndBinds() {
        XCTAssertEqual(ilqp.multipliers.inState.dxMultCap, 5)
        let prefixes = ["DL", "JA", "G", "F", "I", "EA", "PY"]
        let rows = prefixes.enumerated().map { i, p in
            qso(call: "\(p)1AA\(i)", my: "COOK", their: p)
        }
        let s = ScoreEngine.score(log: inLog(rows), party: ilqp)
        XCTAssertEqual(s.validQSOs, 7, "all seven count for points")
        XCTAssertEqual(s.qsoPoints, 14)
        XCTAssertEqual(s.multiplierCount, 5, "but only five DX entities multiply")
    }

    func testOutOfStateCountsCountiesOnly() {
        XCTAssertEqual(Set(ilqp.multipliers.outState.classes), [.county])
        XCTAssertNil(ilqp.multipliers.outState.dxMultCap)
    }

    /// Illinois is never received as a token and no rule says a county yields it.
    func testIllinoisIsNotAStateMultiplier() {
        XCTAssertFalse(ilqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "COOK", their: "LEE")]), party: ilqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(ilqp.validOutStateTokens.contains("IL"))
    }

    // MARK: Two bonus stations, 100 each, 200 maximum

    /// "any entrant contacting these stations will have a 100 point bonus added
    /// to the final score. Total of 200 points possible."
    func testBothClubCallsPay100Once() {
        XCTAssertEqual(ilqp.bonuses, [
            .workStation(call: "W9AWE", points: 100, scope: .once),
            .workStation(call: "W9OAB", points: 100, scope: .once),
        ])

        let one = ScoreEngine.score(log: outLog([qso(call: "W9AWE", their: "ADAM")]), party: ilqp)
        XCTAssertEqual(one.bonusPoints, 100)

        let both = ScoreEngine.score(log: outLog([
            qso(call: "W9AWE", band: .m40, mode: .cw, their: "ADAM"),
            qso(call: "W9OAB", band: .m40, mode: .phone, their: "ADAM"),
        ]), party: ilqp)
        XCTAssertEqual(both.bonusPoints, 200, "'Total of 200 points possible'")

        // Working either again pays nothing extra.
        let repeated = ScoreEngine.score(log: outLog([
            qso(call: "W9AWE", band: .m40, mode: .cw, their: "ADAM"),
            qso(call: "W9AWE", band: .m20, mode: .cw, their: "ADAM"),
            qso(call: "W9OAB", band: .m40, mode: .phone, their: "ADAM"),
            qso(call: "W9OAB", band: .m20, mode: .phone, their: "ADAM"),
        ]), party: ilqp)
        XCTAssertEqual(repeated.bonusPoints, 200, "once each, not per band")
        XCTAssertEqual(repeated.total, repeated.qsoPoints * repeated.multiplierCount + 200)
    }

    // MARK: County corners — 2, 3 or 4 counties

    /// "Contacts with/by stations at the border of 2/3/4 counties count as 2/3/4
    /// counties and 2/3/4 QSOs."
    func testUpToFourCountyCorners() throws {
        XCTAssertEqual(ilqp.maxSimultaneousCounties, 4)
        XCTAssertEqual(
            try ExchangeParser.parse("ADAM/BOND/BOON", party: ilqp, role: .inState).get().locations,
            ["ADAM", "BOND", "BOON"],
            "a three-county corner"
        )
        XCTAssertEqual(
            try ExchangeParser.parse("ADAM/BOND/BOON/BROW", party: ilqp, role: .inState).get().locations.count, 4
        )
        XCTAssertEqual(
            ExchangeParser.parse("ADAM/BOND/BOON/BROW/BURO", party: ilqp, role: .inState),
            .failure(.tooManyCounties(5)),
            "the rules stop at four"
        )
    }

    func testFourCountyCornerScoresFourQSOs() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W9COR", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_792_300_000)
            ),
            myLocs: ["TX"],
            theirLocs: ["ADAM", "BOND", "BOON", "BROW"]
        )
        XCTAssertEqual(rows.count, 4)
        let s = ScoreEngine.score(log: outLog(rows), party: ilqp)
        XCTAssertEqual(s.validQSOs, 4, "'count as 2/3/4 counties and 2/3/4 QSOs'")
        XCTAssertEqual(s.qsoPoints, 8, "CW 2 points each")
        XCTAssertEqual(s.multiplierCount, 4)
    }

    // MARK: Dupes — and the one gap this party leaves

    func testDupesWithinAModeClass() {
        let a = qso(call: "W9M", band: .m40, mode: .cw, their: "PEOR")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let s = ScoreEngine.score(log: outLog([a, repeated]), party: ilqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 1)
    }

    /// ILQP's mode split is TWO-WAY — "once per band and mode (phone and
    /// CW/digital)" — while this app keys dupes on three mode classes. So a CW +
    /// RTTY pair on one band is *not* flagged, and the sponsor counts the second
    /// as a duplicate. Pinned so the gap stays deliberate and visible; recorded
    /// in notes and in the worklist's deferred engine gaps.
    func testKnownGapCWAndDigitalAreNotDupesHereButAreForTheSponsor() throws {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9M", band: .m40, mode: .cw, their: "PEOR"),
            qso(call: "W9M", band: .m40, mode: .digital, their: "PEOR"),
        ]), party: ilqp)
        XCTAssertEqual(s.dupeCount, 0, "current behaviour — three mode classes, so no dupe")
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 1, "multipliers are unaffected: they count once")
        XCTAssertTrue(try XCTUnwrap(ilqp.notes).contains("DUPES ACROSS CW AND DIGITAL"),
                      "the limitation must be stated where an operator will see it")
    }

    /// "once per band/mode/county for IL Mobile and Rover stations"
    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9MOB", band: .m40, mode: .cw, their: "MASN"),
            qso(call: "W9MOB", band: .m40, mode: .cw, their: "MACN"),
        ]), party: ilqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange parsing and scope of credit

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("cook", party: ilqp, role: .inState).get().locations, ["COOK"])
        XCTAssertEqual(try ExchangeParser.parse("LEE", party: ilqp, role: .inState).get().locations, ["LEE"],
                       "the 3-letter code parses alongside the 4-letter ones")
        XCTAssertEqual(try ExchangeParser.parse("WTSD", party: ilqp, role: .inState).get().locations, ["WTSD"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: ilqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: ilqp, role: .inState).get().locations, ["DC"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: ilqp, role: .inState).get().locations, ["DL"])
        guard case .failure = ExchangeParser.parse("IL", party: ilqp, role: .inState) else {
            return XCTFail("IL must be rejected — Illinois stations send a county")
        }
    }

    func testOutOfStateEntrantsGetNoCreditForNonIllinoisContacts() {
        XCTAssertTrue(ilqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9A", their: "COOK"),
            qso(call: "K5B", their: "TX"),
        ]), party: ilqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — 8 hours, Sunday only

    func testScheduleIsOneEightHourSundayWindow() throws {
        let windows = try XCTUnwrap(ilqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-10-18T17:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-10-19T01:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 8 * 3600,
                       "the shortest window of any bundled party")

        // "Sunday the third full weekend of October": 18 October 2026.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 1, "Sunday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 18)
        XCTAssertEqual(utc.component(.month, from: windows[0].start), 10)
    }

    func testNotesRecordBothLimitationsAndTheStaleSecondarySource() throws {
        let notes = try XCTUnwrap(ilqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("NO SUCH RULE IS IN THE SPONSOR'S RULES"),
                      "the invented per-eight-QSOs multiplier must stay recorded")
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 2"), "FT4/FT8 earn no credit")
        let questions = try XCTUnwrap(ilqp.openQuestions)
        XCTAssertTrue(questions.contains("2025 edition"))
        XCTAssertTrue(questions.contains("NEW FOR 2025"), "the bonus stations have run once")
    }
}

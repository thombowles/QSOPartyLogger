import XCTest
@testable import QSOPartyLogger

/// South Dakota QSO Party — Prairie Dog Amateur Radio Club rules, read verbatim
/// 2026-07-24 from the sponsor's current page (headed "October 10 & 11, 2026").
/// See docs/research/sdqp_rules.md.
///
/// The first party in five iterations to need no engine change at all — and the
/// second after the Salmon Run to mix 3- and 4-character county abbreviations.
final class SouthDakotaQSOPartyTests: XCTestCase {

    var sdqp: PartyDefinition!

    override func setUpWithError() throws {
        sdqp = try XCTUnwrap(PartyCatalog.party(id: "sdqp"), "bundled SDQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W0ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "MINN"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_600_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "sdqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "MINN") -> ContestLog {
        var log = ContestLog(partyID: "sdqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 66, and mixed abbreviation lengths

    func testCountyData() {
        XCTAssertEqual(sdqp.counties.count, 66, "South Dakota has 66 counties")
        XCTAssertEqual(Set(sdqp.counties.map(\.abbr)).count, 66)
        XCTAssertEqual(Set(sdqp.counties.map(\.name)).count, 66)
    }

    /// Only the Salmon Run has mixed lengths before this, so a single
    /// `countyAbbrLength` cannot describe SDQP.
    func testMixedAbbreviationLengths() {
        XCTAssertEqual(sdqp.countyAbbrLengths, [3, 4])
        XCTAssertEqual(sdqp.countyAbbrLengthHint, "3/4")
        let threeLetter = sdqp.counties.filter { $0.abbr.count == 3 }.map(\.abbr)
        XCTAssertEqual(threeLetter, ["DAY"], "DAY is the lone 3-letter code")
        XCTAssertEqual(sdqp.counties.filter { $0.abbr.count == 4 }.count, 65)
    }

    /// The vowel-dropped codes and the two-word names — `CLAY`→Clay would prove
    /// nothing (Article 18).
    func testIrregularAbbreviations() {
        XCTAssertEqual(sdqp.county(for: "BRWN")?.name, "Brown", "not BROW — BROO is Brookings")
        XCTAssertEqual(sdqp.county(for: "BROO")?.name, "Brookings")
        XCTAssertEqual(sdqp.county(for: "CLRK")?.name, "Clark", "not CLAR")
        XCTAssertEqual(sdqp.county(for: "DEWY")?.name, "Dewey")
        XCTAssertEqual(sdqp.county(for: "DGLS")?.name, "Douglas")
        XCTAssertEqual(sdqp.county(for: "HNSN")?.name, "Hanson", "HAND is Hand")
        XCTAssertEqual(sdqp.county(for: "HAND")?.name, "Hand")
        XCTAssertEqual(sdqp.county(for: "HRDG")?.name, "Harding")
        XCTAssertEqual(sdqp.county(for: "JKSN")?.name, "Jackson")
        XCTAssertEqual(sdqp.county(for: "MRSH")?.name, "Marshall")
        XCTAssertEqual(sdqp.county(for: "MCOO")?.name, "McCook", "internal capital")
        XCTAssertEqual(sdqp.county(for: "MCPH")?.name, "McPherson")
        XCTAssertEqual(sdqp.county(for: "BONH")?.name, "Bon Homme", "two words")
        XCTAssertEqual(sdqp.county(for: "CHAR")?.name, "Charles Mix")
        XCTAssertEqual(sdqp.county(for: "FALL")?.name, "Fall River")
        XCTAssertEqual(sdqp.county(for: "minn")?.name, "Minnehaha", "case-insensitive")

        for wrong in ["BROW", "CLAR", "DOUG", "HANS", "HARD", "JACK", "MARS"] {
            XCTAssertNil(sdqp.county(for: wrong), "'\(wrong)' is not an SDQP code")
        }
    }

    /// Shannon County was renamed Oglala Lakota County in 2015. The sponsor
    /// prints "Oglala Lakota (Former Shannon county)"; the county's name is the
    /// former, and this test exists so nobody restores the parenthetical.
    func testOglalaLakotaNaming() {
        XCTAssertEqual(sdqp.county(for: "OGLA")?.name, "Oglala Lakota")
        XCTAssertNil(sdqp.counties.first { $0.name.contains("Shannon") },
                     "the sponsor's operator aid is not part of the county name")
    }

    func testPartyShape() {
        XCTAssertEqual(sdqp.cabrilloContest, "SDQSOP",
                       "the short form per WA7BNM, like TQP's TXQP — not a typo")
        XCTAssertEqual(sdqp.homeState, "SD")
        XCTAssertEqual(sdqp.allowedModeClasses, [.phone, .cw],
                       "'The South Dakota QSO Party does not include digital modes'")
        XCTAssertEqual(sdqp.dxStyle, .prefix, "'state, province or DXCC country'")
        XCTAssertTrue(sdqp.exchangeIncludesRST, "'send signal report and county'")
        XCTAssertFalse(sdqp.exchangeIncludesSerial, "no QSO number in SDQP")
        XCTAssertEqual(sdqp.dupeScope, .bandMode)
        XCTAssertEqual(sdqp.maxSimultaneousCounties, 1,
                       "county line contacts 'must be logged separately'")
        XCTAssertNil(sdqp.scoreMultipliers, "power decides the award, not the score")
        XCTAssertTrue(sdqp.isPartiallyVerified)
    }

    /// Ten bands — 160 m through 70 cm less WARC, tying PAQP for the widest here.
    func testValidBands() {
        XCTAssertEqual(
            sdqp.validBands,
            [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70]
        )
        for warc in [Band.m12, .m17, .m30, .m60] {
            XCTAssertFalse(sdqp.validBands.contains(warc), "no WARC bands")
        }
        XCTAssertTrue(sdqp.validBands.contains(.cm125),
                      "1.25 m is in the sponsor's own frequency table")
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(sdqp.points.points(for: .phone), 1)
        XCTAssertEqual(sdqp.points.points(for: .cw), 2)
        XCTAssertNil(sdqp.homeStationPoints)
    }

    func testDigitalRowsAreInvalidNotZeroScored() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", mode: .cw, their: "MINN"),
            qso(call: "W0B", mode: .digital, their: "PENN"),
        ]), party: sdqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Multipliers — once each, stated outright

    /// "South Dakota counties may only be used ONCE as a multiplier."
    func testCountiesCountOnceNotPerBandOrMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", band: .m40, mode: .cw, their: "MINN"),
            qso(call: "W0A", band: .m20, mode: .cw, their: "MINN"),    // other band
            qso(call: "W0A", band: .m40, mode: .phone, their: "MINN"), // other mode
        ]), party: sdqp)
        XCTAssertEqual(s.multiplierCount, 1,
                       "would be 3 under perBandMode, 2 under perBand or perMode")
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 5, "CW 2 + CW 2 + phone 1")
    }

    func testOutOfStateCeilingIs66() {
        let rows = sdqp.counties.enumerated().map { i, c in qso(call: "W0\(i)", their: c.abbr) }
        let s = ScoreEngine.score(log: outLog(rows), party: sdqp)
        XCTAssertEqual(s.multiplierCount, 66)
        XCTAssertEqual(s.workedValues(.county).count, 66)
    }

    /// In-state counts counties, states, provinces and DXCC countries.
    func testInStateCountsEverything() {
        XCTAssertEqual(Set(sdqp.multipliers.inState.classes), [.county, .state, .province, .dx])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W0A", my: "MINN", their: "PENN"),
            qso(call: "K5B", my: "MINN", their: "TX"),
            qso(call: "VE3C", my: "MINN", their: "ON"),
            qso(call: "DL1D", my: "MINN", their: "DL"),
        ]), party: sdqp)
        XCTAssertEqual(s.workedValues(.county), ["PENN"])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["DL"])
        XCTAssertEqual(s.multiplierCount, 4)
    }

    /// DXCC countries are separate multipliers, which is why the exchange must
    /// carry a prefix rather than the literal word "DX".
    func testDXCCCountriesCountSeparately() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "MINN", their: "DL"),
            qso(call: "JA1B", my: "MINN", their: "JA"),
            qso(call: "G4C", my: "MINN", their: "G"),
        ]), party: sdqp)
        XCTAssertEqual(s.workedValues(.dx), ["DL", "JA", "G"])
        XCTAssertNil(sdqp.multipliers.inState.dxMultCap, "no DX cap is stated")
    }

    /// South Dakota is never received as a token, and no rule says a county
    /// yields it — the party's first open question.
    func testSouthDakotaIsNotAStateMultiplier() {
        XCTAssertFalse(sdqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "MINN", their: "PENN")]), party: sdqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertFalse(sdqp.validOutStateTokens.contains("SD"))
    }

    // MARK: The W0OJY bonus — once for the contest, twice stated

    func testW0OJYBonusIsOnceForTheContest() {
        XCTAssertEqual(sdqp.bonuses, [.workStation(call: "W0OJY", points: 100, scope: .once)])

        let one = ScoreEngine.score(log: outLog([
            qso(call: "W0OJY", band: .m40, mode: .cw, their: "YANK"),
        ]), party: sdqp)
        XCTAssertEqual(one.bonusPoints, 100)

        let many = ScoreEngine.score(log: outLog([
            qso(call: "W0OJY", band: .m40, mode: .cw, their: "YANK"),
            qso(call: "W0OJY", band: .m20, mode: .phone, their: "YANK"),
            qso(call: "W0OJY", band: .m160, mode: .cw, their: "YANK"),
        ]), party: sdqp)
        XCTAssertEqual(many.bonusPoints, 100,
                       "'may only be worked once regardless of mode' — the extra "
                           + "contacts still score as ordinary QSOs")
        XCTAssertEqual(many.validQSOs, 3)
        XCTAssertEqual(many.qsoPoints, 5, "CW 2 + phone 1 + CW 2")
    }

    func testNoBonusWithoutW0OJY() {
        let s = ScoreEngine.score(log: outLog([qso(call: "W0XYZ", their: "YANK")]), party: sdqp)
        XCTAssertEqual(s.bonusPoints, 0)
    }

    // MARK: The sponsor's own worked example, end to end

    /// "QSO Points x Multipliers = Total + Bonus = Grand Total (Example 50
    /// contacts SSB x 20 counties = 1,000 points + 100 bonus = 1,100 points
    /// grand total)."
    func testSponsorsWorkedExample() {
        // 50 phone QSOs spread over the first 20 counties, plus W0OJY for the
        // bonus. The example's 50 contacts are the 50 that carry the points.
        let twenty = sdqp.counties.prefix(20).map(\.abbr)
        var rows: [QSO] = []
        for i in 0..<50 {
            rows.append(qso(
                call: "W0N\(i)",
                band: sdqp.validBands[i % sdqp.validBands.count],
                mode: .phone,
                their: twenty[i % twenty.count]
            ))
        }
        let s = ScoreEngine.score(log: outLog(rows), party: sdqp)
        XCTAssertEqual(s.validQSOs, 50)
        XCTAssertEqual(s.qsoPoints, 50, "50 phone contacts at 1 point")
        XCTAssertEqual(s.multiplierCount, 20, "20 counties, counted once each")
        XCTAssertEqual(s.total, 1_000, "50 x 20 = 1,000 points")

        // …and the bonus lands after the multiply, not before it.
        var withBonus = outLog(rows + [qso(call: "W0OJY", mode: .phone, their: twenty[0])])
        withBonus.myLocation = .outOfState(location: "TX")
        let b = ScoreEngine.score(log: withBonus, party: sdqp)
        XCTAssertEqual(b.qsoPoints, 51)
        XCTAssertEqual(b.total, 51 * 20 + 100, "Total + Bonus = Grand Total")
    }

    // MARK: Scope of credit, dupes, mobiles, county lines

    func testOutOfStateEntrantsGetNoCreditForNonSouthDakotaContacts() {
        XCTAssertTrue(sdqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", their: "MINN"),
            qso(call: "K5B", their: "TX"),
        ]), party: sdqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    func testDupesAndModeSplit() {
        let a = qso(call: "W0M", band: .m40, mode: .cw, their: "LAWR")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "W0M", band: .m40, mode: .phone, their: "LAWR")
        let otherBand = qso(call: "W0M", band: .cm70, mode: .cw, their: "LAWR")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, otherBand]), party: sdqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1, "LAWR once, however many band/mode slots")
    }

    /// "South Dakota Mobile (Rover/Portable) stations are considered a new
    /// contact each time they change counties."
    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "HAND"),
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "HNSN"),
        ]), party: sdqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("minn", party: sdqp).get().locations, ["MINN"])
        XCTAssertEqual(try ExchangeParser.parse("DAY", party: sdqp).get().locations, ["DAY"],
                       "the 3-letter code parses alongside the 4-letter ones")
        XCTAssertEqual(try ExchangeParser.parse("OGLA", party: sdqp).get().locations, ["OGLA"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: sdqp).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: sdqp).get().locations, ["DC"],
                       "no DC rule is stated, so DC is its own token")
        XCTAssertEqual(try ExchangeParser.parse("NL", party: sdqp).get().locations, ["NL"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: sdqp).get().locations, ["DL"],
                       "a DXCC prefix, this party's DX form")
        guard case .failure = ExchangeParser.parse("SD", party: sdqp) else {
            return XCTFail("SD must be rejected — South Dakota stations send a county")
        }
    }

    /// "County line contacts will count as multiple contacts for both, but must
    /// be logged separately."
    func testCountyLineEntriesAreRejected() {
        XCTAssertEqual(
            ExchangeParser.parse("AURO/BEAD", party: sdqp),
            .failure(.tooManyCounties(2)),
            "two counties are two contacts in SDQP"
        )
    }

    // MARK: Schedule — one 24-hour window, 1 PM CDT to 1 PM CDT

    func testScheduleIsOneTwentyFourHourWindow() throws {
        let windows = try XCTUnwrap(sdqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-10-10T18:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-10-11T18:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 24 * 3600)

        // "2nd full weekend of October": Oct 10 2026 is a Saturday.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 10)

        // "1 PM Central Daylight Time … GMT is 1800z" — still CDT in October,
        // since US DST ends 1 November 2026.
        let central = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(central.secondsFromGMT(for: windows[0].start), -5 * 3600)
        var cdt = Calendar(identifier: .gregorian)
        cdt.timeZone = central
        XCTAssertEqual(cdt.component(.hour, from: windows[0].start), 13, "1 PM CDT")
        XCTAssertEqual(cdt.component(.hour, from: windows[0].end), 13, "to 1 PM CDT")
    }

    func testNotesRecordTheStaleSubSiteAndBothOpenQuestions() throws {
        let notes = try XCTUnwrap(sdqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("PROVENANCE HAZARD"),
                      "two rule pages live on the domain and only one is current")
        let questions = try XCTUnwrap(sdqp.openQuestions)
        XCTAssertTrue(questions.contains("state multiplier"))
        XCTAssertTrue(questions.contains("only SD stations"))
    }
}

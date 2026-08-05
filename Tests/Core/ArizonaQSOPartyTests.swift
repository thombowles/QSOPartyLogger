import XCTest
@testable import QSOPartyLogger

/// Arizona QSO Party — rules from azqp.org, read verbatim 2026-07-24. The rules
/// text is still the 2025 revision ("Rev: 2501 6/23/2025") under a 2026 banner,
/// which is why AZQP ships `verified: partial`. See docs/research/azqp_rules.md.
///
/// AZQP is the first party whose two sides use *different multiplier scopes*:
/// per mode in-state, per band **and** mode out-of-state.
final class ArizonaQSOPartyTests: XCTestCase {

    var azqp: PartyDefinition!

    override func setUpWithError() throws {
        azqp = try XCTUnwrap(PartyCatalog.party(id: "azqp"), "bundled AZQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K7ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "MCP"
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
        var log = ContestLog(partyID: "azqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "MCP") -> ContestLog {
        var log = ContestLog(partyID: "azqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 15, and every one of them irregular

    func testCountyData() {
        XCTAssertEqual(azqp.counties.count, 15, "Arizona has 15 counties")
        XCTAssertEqual(Set(azqp.counties.map(\.abbr)).count, 15)
        XCTAssertEqual(Set(azqp.counties.map(\.name)).count, 15)
        XCTAssertTrue(azqp.counties.allSatisfy { $0.abbr.count == 3 })
        XCTAssertEqual(azqp.countyAbbrLengths, [3])
    }

    /// Not one AZQP abbreviation is the first three letters of its county — the
    /// scheme exists to keep `Cochise`/`Coconino`, `Graham`/`Greenlee`,
    /// `Pima`/`Pinal` and `Yavapai`/`Yuma` apart.
    func testEveryAbbreviationIsIrregular() {
        XCTAssertEqual(azqp.county(for: "CHS")?.name, "Cochise", "not COC")
        XCTAssertEqual(azqp.county(for: "CNO")?.name, "Coconino", "also not COC")
        XCTAssertEqual(azqp.county(for: "GHM")?.name, "Graham", "not GRA")
        XCTAssertEqual(azqp.county(for: "GLE")?.name, "Greenlee", "not GRE")
        XCTAssertEqual(azqp.county(for: "PMA")?.name, "Pima", "not PIM")
        XCTAssertEqual(azqp.county(for: "PNL")?.name, "Pinal", "not PIN")
        XCTAssertEqual(azqp.county(for: "LPZ")?.name, "La Paz", "space dropped")
        XCTAssertEqual(azqp.county(for: "SCZ")?.name, "Santa Cruz")
        XCTAssertEqual(azqp.county(for: "YVP")?.name, "Yavapai")
        XCTAssertEqual(azqp.county(for: "YMA")?.name, "Yuma", "not YUM")
        XCTAssertEqual(azqp.county(for: "mcp")?.name, "Maricopa", "case-insensitive")

        for firstThree in ["APA", "COC", "GRA", "GRE", "PIM", "PIN", "YUM", "NAV", "MOH"] {
            XCTAssertNil(azqp.county(for: firstThree),
                         "'\(firstThree)' is not an AZQP abbreviation")
        }
    }

    func testPartyShape() {
        XCTAssertEqual(azqp.cabrilloContest, "AZ-QSO-PARTY", "WA7BNM registry; sponsor prints none")
        XCTAssertEqual(azqp.homeState, "AZ")
        XCTAssertEqual(azqp.countyAbbrLength, 3)
        XCTAssertEqual(azqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10],
                       "160, 80, 40, 20, 15, 10 — six bands")
        XCTAssertEqual(azqp.allowedModeClasses, [.phone, .cw], "MODES: CW, Phone")
        XCTAssertEqual(azqp.dxStyle, .prefix, "DX stations send their DXCC prefix, not 'DX'")
        XCTAssertTrue(azqp.exchangeIncludesRST)
        XCTAssertEqual(azqp.dupeScope, .bandMode)
        XCTAssertEqual(azqp.maxSimultaneousCounties, 1,
                       "county lines are logged as multiple contacts")
        XCTAssertTrue(azqp.outStateWorksHomeStationsOnly)
        XCTAssertNil(azqp.scoreMultipliers, "score is (points × mults) + bonus, nothing else")
        XCTAssertTrue(azqp.isPartiallyVerified, "rules are still the 2025 revision")
    }

    /// AZQP states no DC rule at all, so DC is its own token here — unlike the
    /// six bundled parties that fold it into Maryland.
    func testNoDCAlias() throws {
        XCTAssertTrue(azqp.stateAliases.isEmpty)
        XCTAssertEqual(try ExchangeParser.parse("DC", party: azqp, role: .inState).get().locations, ["DC"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "MCP", their: "MD"),
            qso(call: "W3B", my: "MCP", their: "DC"),
        ]), party: azqp)
        XCTAssertEqual(s.workedValues(.state), ["MD", "DC"], "two multipliers, not one")
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(azqp.points.points(for: .phone), 1)
        XCTAssertEqual(azqp.points.points(for: .cw), 2)
        XCTAssertNil(azqp.homeStationPoints, "AZQP pays by mode, not by who was worked")
    }

    func testDigitalRowsAreInvalidNotZeroScored() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K7A1", mode: .cw, their: "MCP"),
            qso(call: "K7B1", mode: .digital, their: "PMA"),
        ]), party: azqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 1, "the digital row contributes no multiplier")
    }

    // MARK: The asymmetry — in-state PER MODE, out-of-state PER BAND AND MODE

    /// "Multipliers are the 15 Arizona counties. Multipliers count again for
    /// each band and mode."
    func testOutOfStateCountsCountiesPerBandAndMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K7A", band: .m40, mode: .cw, their: "MCP"),
            qso(call: "K7A", band: .m20, mode: .cw, their: "MCP"),    // new band
            qso(call: "K7A", band: .m40, mode: .phone, their: "MCP"), // new mode
            qso(call: "K7A", band: .m20, mode: .phone, their: "MCP"), // both
        ]), party: azqp)
        XCTAssertEqual(s.multiplierCount, 4, "2 under perBand or perMode, 1 under once")
        XCTAssertEqual(s.workedValues(.county), ["MCP"])
    }

    /// The sponsor's own out-of-state ceiling: "15 x 6 x 2 = 180".
    func testOutOfStateCeilingIs180() {
        var rows: [QSO] = []
        var n = 0
        for band in azqp.validBands {
            for mode in [ModeClass.cw, .phone] {
                for county in azqp.counties.map(\.abbr) {
                    n += 1
                    rows.append(qso(call: "K7\(n)", band: band, mode: mode, their: county))
                }
            }
        }
        let s = ScoreEngine.score(log: outLog(rows), party: azqp)
        XCTAssertEqual(s.multiplierCount, 180, "the rules' own stated maximum")
        XCTAssertEqual(s.workedValues(.county).count, 15)
    }

    /// In-state is the *other* scope: "Multipliers count again for each mode" —
    /// per mode only, so a second band adds nothing.
    func testInStateCountsPerModeNotPerBand() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", band: .m40, mode: .cw, my: "MCP", their: "TX"),
            qso(call: "K5A", band: .m20, mode: .cw, my: "MCP", their: "TX"),    // new band
            qso(call: "K5A", band: .m40, mode: .phone, my: "MCP", their: "TX"), // new mode
        ]), party: azqp)
        XCTAssertEqual(s.multiplierCount, 2,
                       "TX on CW and on phone; the extra band adds nothing")
    }

    /// The two sides genuinely differ — the same log scores differently from
    /// inside and outside Arizona.
    func testTheTwoScopesReallyDiffer() {
        let rows = [
            qso(call: "X1", band: .m40, mode: .cw, their: "MCP"),
            qso(call: "X1", band: .m20, mode: .cw, their: "MCP"),
        ]
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: azqp).multiplierCount, 2,
                       "out-of-state: a second band is a second multiplier")
        XCTAssertEqual(azqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(azqp.multipliers.outState.countScope, .perBandMode)
    }

    func testInStateCountsStatesProvincesAndDX() {
        XCTAssertEqual(Set(azqp.multipliers.inState.classes), [.state, .province, .dx])
        XCTAssertFalse(azqp.multipliers.inState.classes.contains(.county),
                       "counties are not an in-state multiplier class")

        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", my: "MCP", their: "TX"),
            qso(call: "VE3B", my: "MCP", their: "ON"),
            qso(call: "DL1C", my: "MCP", their: "DL"),
        ]), party: azqp)
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["DL"])
        XCTAssertEqual(s.multiplierCount, 3)
    }

    /// Arizona is reachable only through a county, and the sponsor's stated
    /// in-state total of "(50 + 13 + DXCC) x 2" requires it to be reachable.
    func testArizonaIsEarnedViaACounty() {
        XCTAssertTrue(azqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K7A", mode: .cw, my: "MCP", their: "PMA"),
            qso(call: "K7B", mode: .cw, my: "MCP", their: "CHS"),  // a second AZ county
        ]), party: azqp)
        XCTAssertEqual(s.workedValues(.state), ["AZ"], "both AZ QSOs yield the one AZ mult")
        XCTAssertEqual(s.workedValues(.county), [], "counties are not an in-state class")
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertFalse(azqp.validOutStateTokens.contains("AZ"), "AZ is never sent as a token")
    }

    /// …and per mode, like every other in-state multiplier.
    func testArizonaViaCountyCountsOncePerMode() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K7A", mode: .cw, my: "MCP", their: "PMA"),
            qso(call: "K7A", mode: .phone, my: "MCP", their: "PMA"),
        ]), party: azqp)
        XCTAssertEqual(s.multiplierCount, 2, "AZ on CW and AZ on phone")
    }

    func testOutOfStateGetsNoArizonaStateMultiplier() {
        XCTAssertFalse(azqp.multipliers.outState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: outLog([qso(their: "MCP")]), party: azqp)
        XCTAssertEqual(s.workedValues(.county), ["MCP"])
        XCTAssertEqual(s.workedValues(.state), [])
    }

    // MARK: DX — prefixes, so entities are distinguishable here

    func testDXPrefixesAreSeparateMultipliers() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "MCP", their: "DL"),
            qso(call: "JA1B", my: "MCP", their: "JA"),
            qso(call: "G4C", my: "MCP", their: "G"),
        ]), party: azqp)
        XCTAssertEqual(s.workedValues(.dx), ["DL", "JA", "G"],
                       "prefix style, so unlike NHQP/MEQP each entity counts")
        XCTAssertEqual(s.multiplierCount, 3)
    }

    /// A DXCC prefix that equals a US state or Canadian province code used to
    /// be read as that state or province. The worked callsign decides now, and
    /// only when it names the very same entity the token would — so these two
    /// are DX, while `W3XYZ` sending `PA` is still Pennsylvania.
    func testTheCallsignDecidesAPrefixThatEqualsAStateCode() {
        let dx = ScoreEngine.score(log: inLog([
            qso(call: "PA0ABC", my: "MCP", their: "PA"),   // Netherlands
            qso(call: "ON4XYZ", my: "MCP", their: "ON"),   // Belgium
        ]), party: azqp)
        XCTAssertEqual(dx.workedValues(.state), [])
        XCTAssertEqual(dx.workedValues(.province), [])
        XCTAssertEqual(Set(dx.workedValues(.dx)), ["PA", "ON"])

        let home = ScoreEngine.score(log: inLog([
            qso(call: "W3XYZ", my: "MCP", their: "PA"),
            qso(call: "VE3ABC", my: "MCP", their: "ON"),
        ]), party: azqp)
        XCTAssertEqual(home.workedValues(.state), ["PA"], "read as Pennsylvania")
        XCTAssertEqual(home.workedValues(.province), ["ON"], "read as Ontario")
        XCTAssertEqual(home.workedValues(.dx), [])
    }

    // MARK: The K7A bonus

    func testK7ABonusIsOneTimeOnAnyBandOrMode() {
        let one = ScoreEngine.score(log: outLog([
            qso(call: "K7A", band: .m40, mode: .cw, their: "PMA"),
        ]), party: azqp)
        XCTAssertEqual(one.bonusPoints, 100, "one-time bonus of 100 points for a QSO with K7A")

        let many = ScoreEngine.score(log: outLog([
            qso(call: "K7A", band: .m40, mode: .cw, their: "PMA"),
            qso(call: "K7A", band: .m20, mode: .phone, their: "PMA"),
            qso(call: "K7A", band: .m160, mode: .cw, their: "PMA"),
        ]), party: azqp)
        XCTAssertEqual(many.bonusPoints, 100, "one-time — not per band and not per mode")
        XCTAssertEqual(many.total, many.qsoPoints * many.multiplierCount + 100,
                       "Total Score = (QSO POINTS x MULTIPLIERS) + BONUS POINTS")
    }

    func testNoBonusWithoutK7A() {
        let s = ScoreEngine.score(log: outLog([qso(call: "K7XYZ", their: "PMA")]), party: azqp)
        XCTAssertEqual(s.bonusPoints, 0)
    }

    // MARK: Scope of credit, dupes, mobiles

    func testOutOfStateEntrantsGetNoCreditForNonArizonaContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K7A", their: "MCP"),
            qso(call: "K5B", their: "TX"),
        ]), party: azqp)
        XCTAssertEqual(s.validQSOs, 1, "a valid contact always has an Arizona station in it")
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    func testDupesAndModeSplit() {
        let a = qso(call: "K7M", band: .m40, mode: .cw, their: "SCZ")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "K7M", band: .m40, mode: .phone, their: "SCZ")
        let otherBand = qso(call: "K7M", band: .m160, mode: .cw, their: "SCZ")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, otherBand]), party: azqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 5, "CW 2 + phone 1 + CW 2")
        XCTAssertEqual(s.multiplierCount, 3, "SCZ on 40/CW, 40/phone and 160/CW")
    }

    /// "Mobiles that change counties are considered new stations and can be
    /// worked again for both multiplier and QSO point credit."
    func testMobileChangingCountyIsANewQSONotADupe() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K7MOB", band: .m40, mode: .cw, their: "GHM"),
            qso(call: "K7MOB", band: .m40, mode: .cw, their: "GLE"),
        ]), party: azqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 4)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("mcp", party: azqp, role: .inState).get().locations, ["MCP"])
        XCTAssertEqual(try ExchangeParser.parse("CNO", party: azqp, role: .inState).get().locations, ["CNO"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: azqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("NL", party: azqp, role: .inState).get().locations, ["NL"],
                       "the standard 13 provinces")
        XCTAssertEqual(try ExchangeParser.parse("DL", party: azqp, role: .inState).get().locations, ["DL"],
                       "a DXCC prefix, this party's DX form")
        guard case .failure = ExchangeParser.parse("AZ", party: azqp, role: .inState) else {
            return XCTFail("AZ must be rejected — Arizona stations send a county")
        }
        guard case .failure = ExchangeParser.parse("DX", party: azqp, role: .inState) else {
            return XCTFail("the literal token DX is not AZQP's DX form")
        }
    }

    /// "Expeditions (or mobiles) spanning multiple county lines should be logged
    /// as multiple contacts" — so a county-line entry is refused.
    func testCountyLineEntriesAreRejected() {
        XCTAssertEqual(
            ExchangeParser.parse("APH/CHS", party: azqp, role: .inState),
            .failure(.tooManyCounties(2)),
            "two counties are two contacts in AZQP"
        )
    }

    // MARK: Schedule — one 14-hour window, 8 AM to 10 PM Arizona time

    func testScheduleIsOneFourteenHourWindow() throws {
        let windows = try XCTUnwrap(azqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-10-10T15:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-10-11T05:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 14 * 3600,
                       "8 AM to 10 PM Arizona time, which keeps MST (UTC−7) all year")

        // "2nd October Saturday": 10 October 2026 is the second Saturday.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 10)

        // Arizona has no DST, so the local anchors hold in October.
        let phoenix = try XCTUnwrap(TimeZone(identifier: "America/Phoenix"))
        XCTAssertEqual(phoenix.secondsFromGMT(for: windows[0].start), -7 * 3600)
        var az = Calendar(identifier: .gregorian)
        az.timeZone = phoenix
        XCTAssertEqual(az.component(.hour, from: windows[0].start), 8, "8 AM AZ")
        XCTAssertEqual(az.component(.hour, from: windows[0].end), 22, "10 PM AZ")
    }

    func testNotesRecordBothOpenQuestions() throws {
        let notes = try XCTUnwrap(azqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        let questions = try XCTUnwrap(azqp.openQuestions)
        XCTAssertTrue(questions.contains("2025 revision"), "the stale rules document")
        XCTAssertTrue(questions.contains("state multiplier"), "the Arizona-via-county inference")
    }
}

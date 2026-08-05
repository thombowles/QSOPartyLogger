import XCTest
@testable import QSOPartyLogger

/// Maine QSO Party — Wireless Society of Southern Maine (WS1SM), official rules
/// PDF titled "2026 Official Rules" plus the rules page, both read verbatim
/// 2026-07-24. See docs/research/meqp_rules.md.
///
/// MEQP is the repo's first party to pay QSO points by *who was worked* rather
/// than by mode, and the first to count multipliers per band AND per mode.
final class MaineQSOPartyTests: XCTestCase {

    var meqp: PartyDefinition!

    override func setUpWithError() throws {
        meqp = try XCTUnwrap(PartyCatalog.party(id: "meqp"), "bundled MEQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W1ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "CBL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_790_400_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "meqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "CBL") -> ContestLog {
        var log = ContestLog(partyID: "meqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data

    func testCountyData() {
        XCTAssertEqual(meqp.counties.count, 16, "Maine has 16 counties; the rules say 'Sixteen in total'")
        XCTAssertEqual(Set(meqp.counties.map(\.abbr)).count, 16)
        XCTAssertEqual(Set(meqp.counties.map(\.name)).count, 16)
        XCTAssertTrue(meqp.counties.allSatisfy { $0.abbr.count == 3 })
        XCTAssertEqual(meqp.countyAbbrLengths, [3])
    }

    /// The six abbreviations that are *not* simply the first three letters —
    /// the ones a transcription error would land on. `KEN`→Kennebec proves
    /// nothing (Article 18).
    func testIrregularAbbreviations() {
        XCTAssertEqual(meqp.county(for: "CBL")?.name, "Cumberland", "not CUM")
        XCTAssertEqual(meqp.county(for: "PSQ")?.name, "Piscataquis", "not PIS")
        XCTAssertEqual(meqp.county(for: "SAG")?.name, "Sagadahoc")
        XCTAssertEqual(meqp.county(for: "ARO")?.name, "Aroostook")
        XCTAssertEqual(meqp.county(for: "KNO")?.name, "Knox")
        XCTAssertEqual(meqp.county(for: "WAS")?.name, "Washington", "the county, not the state WA")
        XCTAssertNil(meqp.county(for: "CUM"), "Cumberland is CBL in MEQP")
        XCTAssertEqual(meqp.county(for: "cbl")?.name, "Cumberland", "case-insensitive")
    }

    func testPartyShape() {
        XCTAssertEqual(meqp.cabrilloContest, "ME-QSO-PARTY", "WA7BNM registry; sponsor prints none")
        XCTAssertEqual(meqp.homeState, "ME")
        XCTAssertEqual(meqp.countyAbbrLength, 3)
        XCTAssertEqual(meqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10],
                       "'160, 80, 40, 20, 15, and 10' — six bands, 160 m included, no WARC, no VHF")
        XCTAssertEqual(meqp.allowedModeClasses, [.phone, .cw],
                       "'CW and phone (SSB, FM, AM)' — there is no digital category")
        XCTAssertEqual(meqp.dxStyle, .token, "DX stations send the literal word DX")
        XCTAssertTrue(meqp.exchangeIncludesRST, "'send signal report and county'")
        XCTAssertEqual(meqp.dupeScope, .bandMode)
        XCTAssertTrue(meqp.bonuses.isEmpty, "no bonus station, no bonus points")
        XCTAssertNil(meqp.scoreMultipliers, "power categories affect awards, not score")
        XCTAssertTrue(meqp.isPartiallyVerified)
    }

    // MARK: Points — by WHO was worked, not by mode

    func testMaineStationsAreWorthTwoPointsAndEveryoneElseOne() throws {
        // "Contacts with stations in Maine are worth 2 points. Contacts with
        // stations outside Maine are worth 1 point."
        XCTAssertEqual(meqp.points.points(for: .phone), 1)
        XCTAssertEqual(meqp.points.points(for: .cw), 1, "CW pays the same as phone in MEQP")
        let home = try XCTUnwrap(meqp.homeStationPoints)
        XCTAssertEqual(home.points(for: .phone), 2)
        XCTAssertEqual(home.points(for: .cw), 2)

        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1A", mode: .cw, their: "CBL"),      // Maine  → 2
            qso(call: "W1B", mode: .phone, their: "PEN"),   // Maine  → 2
            qso(call: "K5C", mode: .cw, their: "TX"),       // not ME → 1
            qso(call: "VE3D", mode: .phone, their: "ON"),   // not ME → 1
        ]), party: meqp)
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.qsoPoints, 6, "2 + 2 + 1 + 1 — mode makes no difference")
    }

    /// The same rule seen from inside Maine, which is how the sponsor's own
    /// published results verify it: the 2024 winner (a Maine multi-op) scored
    /// 1,234 QSO points on 1,212 QSOs — i.e. total = QSOs + (Maine QSOs).
    func testInStateEntrantAlsoScoresByWorkedLocation() {
        let rows = [
            qso(call: "W1A", my: "CBL", their: "PEN"),   // another ME station → 2
            qso(call: "K5B", my: "CBL", their: "TX"),    // → 1
            qso(call: "K5C", my: "CBL", their: "CA"),    // → 1
            qso(call: "DL1D", my: "CBL", their: "DX"),   // → 1
        ]
        let s = ScoreEngine.score(log: inLog(rows), party: meqp)
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.qsoPoints, rows.count + 1,
                       "the sponsor's published arithmetic: QSOs + one extra per Maine contact")
    }

    /// Every other bundled party pays by mode alone and must keep doing so.
    func testLocationPointsAreOptInAndDoNotAffectOtherParties() throws {
        XCTAssertNil(try XCTUnwrap(PartyCatalog.party(id: "nhqp")).homeStationPoints)
        XCTAssertNil(try XCTUnwrap(PartyCatalog.party(id: "alqp")).homeStationPoints)
        let nhqp = try XCTUnwrap(PartyCatalog.party(id: "nhqp"))
        XCTAssertEqual(
            nhqp.pointsTable(forTheirLoc: "HIL", countyAbbrs: ["HIL"]).points(for: .cw), 2,
            "a nil homeStationPoints must fall through to the mode table"
        )
    }

    func testDigitalRowsAreInvalidNotZeroScored() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1A", mode: .cw, their: "CBL"),
            qso(call: "W1B", mode: .digital, their: "PEN"),
        ]), party: meqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1, "no digital category exists")
        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 1, "the digital row contributes no multiplier")
    }

    // MARK: Multipliers — per band AND per mode, identically for everyone

    /// "Each multiplier may be counted once on each mode on each of the six
    /// contest bands." A second band counts, and so does a second mode — the
    /// case that separates `perBandMode` from both `perBand` and `perMode`.
    func testCountiesCountPerBandAndPerMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1A", band: .m40, mode: .cw, their: "CBL"),
            qso(call: "W1A", band: .m20, mode: .cw, their: "CBL"),    // new band  → new mult
            qso(call: "W1A", band: .m40, mode: .phone, their: "CBL"), // new mode  → new mult
            qso(call: "W1A", band: .m20, mode: .phone, their: "CBL"), // both      → new mult
        ]), party: meqp)
        XCTAssertEqual(s.multiplierCount, 4,
                       "would be 2 under perBand, 2 under perMode, 1 under once")
        XCTAssertEqual(s.workedValues(.county), ["CBL"], "still one distinct county")
    }

    /// The same scope applies to states, provinces and DX — the rules say "Each
    /// multiplier", not "each county", and 401 multipliers in the sponsor's 2024
    /// results is unreachable from 16 counties alone (16 × 6 × 2 = 192).
    func testStatesProvincesAndDXAlsoCountPerBandAndPerMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K5A", band: .m40, mode: .cw, their: "TX"),
            qso(call: "K5A", band: .m20, mode: .phone, their: "TX"),
            qso(call: "VE3B", band: .m40, mode: .cw, their: "ON"),
            qso(call: "VE3B", band: .m20, mode: .phone, their: "ON"),
            qso(call: "DL1C", band: .m40, mode: .cw, their: "DX"),
            qso(call: "DL1C", band: .m20, mode: .phone, their: "DX"),
        ]), party: meqp)
        XCTAssertEqual(s.multiplierCount, 6, "three values × two band/mode slots each")
        XCTAssertEqual(s.classCounts[.state], 2)
        XCTAssertEqual(s.classCounts[.province], 2)
        XCTAssertEqual(s.classCounts[.dx], 2)
    }

    /// "Multipliers are the same for all participants" — Article 16's warning
    /// about asymmetry does not apply here, and that is a quoted rule, not an
    /// assumption, so it gets a test of its own.
    func testInStateAndOutOfStateRulesAreIdentical() {
        XCTAssertEqual(meqp.multipliers.inState, meqp.multipliers.outState)
        XCTAssertEqual(meqp.multipliers.inState.countScope, .perBandMode)
        XCTAssertEqual(Set(meqp.multipliers.outState.classes), [.county, .state, .province, .dx])
        XCTAssertNil(meqp.multipliers.inState.dxMultCap, "DXCC is uncapped in MEQP")

        let rows = [
            qso(call: "W1A", band: .m40, mode: .cw, their: "PEN"),
            qso(call: "K5B", band: .m40, mode: .cw, their: "CA"),
            qso(call: "VE1C", band: .m20, mode: .phone, their: "NS"),
        ]
        XCTAssertEqual(
            ScoreEngine.score(log: outLog(rows), party: meqp).multiplierCount,
            ScoreEngine.score(log: inLog(rows), party: meqp).multiplierCount,
            "the same log scores the same multipliers from inside or outside Maine"
        )
    }

    /// Maine is never received as a state token, and no rule says a Maine county
    /// also yields the ME state multiplier — the party's one open question.
    func testMaineIsNotAStateMultiplier() {
        XCTAssertFalse(meqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(meqp.multipliers.outState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "CBL", their: "PEN")]), party: meqp)
        XCTAssertEqual(s.workedValues(.state), [], "no ME state mult from a Maine county")
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertFalse(meqp.validOutStateTokens.contains("ME"))
    }

    // MARK: Canada — 14 tokens, Newfoundland and Labrador counted separately

    func testFourteenProvinceTokensWithNFAndLBSplit() {
        XCTAssertEqual(meqp.provinces.count, 14, "the sponsor lists 14, not the usual 13")
        XCTAssertEqual(
            meqp.provinces,
            ["NB", "NS", "QC", "ON", "MB", "SK", "AB", "BC", "NT", "NF", "LB", "YT", "PE", "NU"],
            "the sponsor's own list, verbatim"
        )
        XCTAssertFalse(meqp.provinces.contains("NL"),
                       "'Newfoundland (NF) and Labrador (LB) will count seperately' [sic]")

        let s = ScoreEngine.score(log: outLog([
            qso(call: "VO1A", band: .m40, mode: .cw, their: "NF"),
            qso(call: "VO2B", band: .m40, mode: .cw, their: "LB"),
        ]), party: meqp)
        XCTAssertEqual(s.workedValues(.province), ["NF", "LB"], "two multipliers, not one")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testNLIsNotAValidMEQPToken() {
        XCTAssertFalse(meqp.validOutStateTokens.contains("NL"))
        guard case .failure = ExchangeParser.parse("NL", party: meqp, role: .inState) else {
            return XCTFail("NL must be rejected — MEQP splits it into NF and LB")
        }
    }

    /// "For U.S. states, DC and MD will be counted as a single multiplier."
    func testDCCountsAsMaryland() {
        XCTAssertEqual(meqp.stateAliases["DC"], "MD")
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", band: .m40, mode: .cw, their: "MD"),
            qso(call: "W3B", band: .m40, mode: .cw, their: "DC"),
        ]), party: meqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "DC folds into MD")
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.qsoPoints, 2, "both are still valid one-point QSOs")
    }

    // MARK: Out-of-state entrants score non-Maine QSOs — explicitly

    func testNonMaineContactsCountForOutOfStateEntrants() {
        XCTAssertFalse(meqp.outStateWorksHomeStationsOnly,
                       "'all QSOs … are eligible for points—not just contacts with Maine stations'")
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K5A", their: "CA"),
            qso(call: "VE3B", their: "ON"),
        ]), party: meqp)
        XCTAssertEqual(s.outOfScopeCount, 0, "nothing is out of scope in MEQP")
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Dupes — once per band per mode

    func testDupesAndModeSplit() {
        let a = qso(call: "W1M", band: .m40, mode: .cw, their: "SAG")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "W1M", band: .m40, mode: .phone, their: "SAG")
        let otherBand = qso(call: "W1M", band: .m160, mode: .cw, their: "SAG")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, otherBand]), party: meqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 6, "three Maine QSOs at 2 points; the dupe pays nothing")
        XCTAssertEqual(s.multiplierCount, 3, "SAG on 40/CW, 40/phone and 160/CW")
    }

    /// "Mobiles that change counties are considered to be new stations, and can
    /// be worked for both multiplier and QSO point credit."
    func testMobileChangingCountyIsANewQSONotADupe() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1MOB", band: .m40, mode: .cw, their: "PSQ"),
            qso(call: "W1MOB", band: .m40, mode: .cw, their: "ARO"),
        ]), party: meqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 4, "both count for point credit")
        XCTAssertEqual(s.multiplierCount, 2, "and both count for multiplier credit")
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("cbl", party: meqp, role: .inState).get().locations, ["CBL"])
        XCTAssertEqual(try ExchangeParser.parse("PSQ", party: meqp, role: .inState).get().locations, ["PSQ"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: meqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: meqp, role: .inState).get().locations, ["DC"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: meqp, role: .inState).get().locations, ["DX"])
        XCTAssertEqual(try ExchangeParser.parse("LB", party: meqp, role: .inState).get().locations, ["LB"])
        guard case .failure = ExchangeParser.parse("ME", party: meqp, role: .inState) else {
            return XCTFail("ME must be rejected — Maine stations send a county")
        }
    }

    /// "County line QSO's should be logged as two separate QSO's" — so the entry
    /// field refuses a county-line entry outright. The limit is 1.
    func testCountyLineEntriesAreRejected() {
        XCTAssertEqual(meqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("CBL/YOR", party: meqp, role: .inState),
            .failure(.tooManyCounties(2)),
            "two counties are two QSOs in MEQP, not one two-county QSO"
        )
    }

    // MARK: Schedule — one continuous 24-hour window

    func testScheduleIsOneTwentyFourHourWindow() throws {
        let windows = try XCTUnwrap(meqp.schedule)
        XCTAssertEqual(windows.count, 1, "MEQP runs straight through, unlike NHQP or KSQP")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-09-26T12:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-09-27T12:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 24 * 3600)

        // The rules' formula is "the last full weekend in September"; 26 Sep 2026
        // is a Saturday. The PDF's contest-period line misprints the year as 2025
        // (26 Sep 2025 was a Friday) — see meqp_rules.md §2.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 26)
    }

    func testNotesRecordTheDXCCFixAndTheOpenQuestion() throws {
        let notes = meqp.notes ?? ""
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("DXCC ENTITIES COUNT ONE BY ONE"),
                      "the fix must be stated where the collapse used to be")
        XCTAssertTrue(notes.contains("ARRL DXCC List"), "and its source named")
        XCTAssertFalse(notes.contains("KNOWN SCORING LIMITATION"),
                       "the limitation is closed — the warning must not outlive it")
        let questions = try XCTUnwrap(meqp.openQuestions)
        XCTAssertTrue(questions.contains("state multiplier"))
    }

    /// This was the largest single scoring gap in the catalogue: DXCC entities
    /// are multipliers for **every** entrant here, uncapped, counted once per
    /// band **and** per mode — and all of them used to collapse into one.
    func testEachDXCCEntityCountsForBothRolesPerBandAndMode() {
        XCTAssertTrue(meqp.multipliers.inState.dxCountsEntities)
        XCTAssertTrue(meqp.multipliers.outState.dxCountsEntities)
        XCTAssertNil(meqp.multipliers.inState.dxMultCap, "uncapped, per the rules")

        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "CUM", their: "DX"),
            qso(call: "JA1B", my: "CUM", their: "DX"),
            qso(call: "G4C", my: "CUM", their: "DX"),
        ]), party: meqp)
        XCTAssertEqual(Set(s.workedValues(.dx)), ["DL", "JA", "G"])
        XCTAssertEqual(s.multiplierCount, 3)
    }
}

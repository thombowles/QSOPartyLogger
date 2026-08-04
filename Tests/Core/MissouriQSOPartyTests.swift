import XCTest
@testable import QSOPartyLogger

/// Missouri QSO Party — BEARS-St. Louis (`WØMA`). Built from the sponsor's
/// official 2026 rules PDF and its Missouri County Listing, read verbatim
/// 2026-07-26. See docs/research/moqp_rules.md.
///
/// **The party with the most bonus rules in the repo** — five, of which two fit,
/// two do not, and one is not about QSOs at all. And the only 2026 party whose
/// date was moved off its own formula, for Easter.
final class MissouriQSOPartyTests: XCTestCase {

    var moqp: PartyDefinition!

    override func setUpWithError() throws {
        moqp = try XCTUnwrap(PartyCatalog.party(id: "moqp"), "bundled MOQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W0ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "SLC"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_775_916_000 + seq),  // 2026-04-11 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "moqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(
        _ qsos: [QSO],
        from county: String = "SLC",
        station: StationProfile.CategoryStation = .fixed
    ) -> ContestLog {
        var log = ContestLog(partyID: "moqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: Entities — 115, because St. Louis City is not a county

    func testEntityCount() {
        XCTAssertEqual(moqp.counties.count, 115,
                       "Missouri's 114 counties plus the independent City of St. Louis")
        XCTAssertEqual(Set(moqp.counties.map(\.abbr)).count, 115)
        XCTAssertEqual(Set(moqp.counties.map(\.name)).count, 115)
        XCTAssertEqual(moqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// **The trap this party turns on.** Two adjacent, differently governed
    /// entities whose names differ by one word and whose codes share all three
    /// letters in a different order.
    func testStLouisCityIsSTLAndStLouisCountyIsSLC() {
        XCTAssertEqual(moqp.county(for: "STL")?.name, "St. Louis City")
        XCTAssertEqual(moqp.county(for: "SLC")?.name, "St. Louis County")
    }

    /// Five `C-l` codes, and the one that contracts is Caldwell.
    func testTheFiveCLCodes() {
        XCTAssertEqual(moqp.county(for: "CAL")?.name, "Callaway")
        XCTAssertEqual(moqp.county(for: "CLA")?.name, "Clay")
        XCTAssertEqual(moqp.county(for: "CLK")?.name, "Clark")
        XCTAssertEqual(moqp.county(for: "CLN")?.name, "Clinton")
        XCTAssertEqual(moqp.county(for: "CWL")?.name, "Caldwell")
    }

    /// Four `B` counties, and the two that contract are not the guessable ones.
    func testTheFourBCounties() {
        XCTAssertEqual(moqp.county(for: "BAR")?.name, "Barry")
        XCTAssertEqual(moqp.county(for: "BTN")?.name, "Barton")
        XCTAssertEqual(moqp.county(for: "BAT")?.name, "Bates")
        XCTAssertEqual(moqp.county(for: "BTR")?.name, "Butler")
    }

    /// The `S` block — eight codes, five of them `SC*`/`ST*`.
    func testTheSBlock() {
        XCTAssertEqual(moqp.county(for: "SAL")?.name, "Saline")
        XCTAssertEqual(moqp.county(for: "SCH")?.name, "Schuyler")
        XCTAssertEqual(moqp.county(for: "SCL")?.name, "St. Clair")
        XCTAssertEqual(moqp.county(for: "SCO")?.name, "Scott")
        XCTAssertEqual(moqp.county(for: "SCT")?.name, "Scotland")
        XCTAssertEqual(moqp.county(for: "STC")?.name, "St. Charles")
        XCTAssertEqual(moqp.county(for: "STF")?.name, "St. Francois")
        XCTAssertEqual(moqp.county(for: "STG")?.name, "St. Genevieve",
                       "the sponsor's spelling; the county is officially Ste. Genevieve")
        XCTAssertEqual(moqp.county(for: "cpg")?.name, "Cape Girardeau", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(moqp.cabrilloContest, "MO-QSO-PARTY",
                       "WA7BNM; the rules require Cabrillo but print no token")
        XCTAssertEqual(moqp.homeState, "MO")
        XCTAssertEqual(moqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(moqp.dxStyle, .token, "'the exchange \"DX\"'")
        XCTAssertTrue(moqp.exchangeIncludesRST)
        XCTAssertFalse(moqp.exchangeIncludesSerial)
        XCTAssertNil(moqp.scoreMultipliers, "power selects the entry class only")
        XCTAssertTrue(moqp.isPartiallyVerified)
    }

    func testTenBandsListedOutright() {
        XCTAssertEqual(moqp.validBands,
                       [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70])
        for excluded in [Band.m60, .m30, .m17, .m12] {
            XCTAssertFalse(moqp.validBands.contains(excluded))
        }
    }

    func testPointsByMode() {
        XCTAssertEqual(moqp.points.points(for: .phone), 1)
        XCTAssertEqual(moqp.points.points(for: .cw), 2)
        XCTAssertEqual(moqp.points.points(for: .digital), 2)
    }

    // MARK: Multipliers — once overall, fixed by the sponsor's maxima

    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(moqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(moqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", band: .m20, mode: .cw, their: "SLC"),
            qso(call: "W0A", band: .m40, mode: .cw, their: "SLC"),
            qso(call: "W0A", band: .m20, mode: .phone, their: "SLC"),
        ]), party: moqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfStateCeilingIs115() {
        XCTAssertEqual(Set(moqp.multipliers.outState.classes), [.county])
        let rows = moqp.counties.enumerated().map { i, c in qso(call: "W0\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: moqp).multiplierCount, 115)
    }

    /// "US states (**49** maximum)" — 49, not 50, so Missouri is excluded.
    func testMissouriIsNotAStateMultiplier() {
        XCTAssertFalse(moqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "SLC", their: "JAC")]), party: moqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(moqp.validOutStateTokens.contains("MO"))
    }

    /// "An additional multiplier of the value of **one** will be added if at
    /// least one DX station is worked" — exactly what the token style produces.
    func testAllDXIsWorthExactlyOneMultiplier() {
        let rows = (0..<5).map { qso(call: "DL\($0)AA", my: "SLC", their: "DX") }
        let s = ScoreEngine.score(log: inLog(rows), party: moqp)
        XCTAssertEqual(s.validQSOs, 5)
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Rule 3 — the county you make fifty contacts from

    /// "Any mobile or portable category entry that makes **50 or more valid
    /// contacts** from a county or county lines will be given the multiplier for
    /// that county or counties."
    ///
    /// **The highest threshold of the five parties with this rule** — five times
    /// TnQP's and VaQP's ten, fifty times SCQP's and NCQP's one.
    func testFiftyContactsFromACountyEarnsIt() throws {
        let act = try XCTUnwrap(moqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(act.minCount, 50)
        XCTAssertEqual(act.countUnit, .qsos, "\"50 or more valid CONTACTS\"")
        XCTAssertEqual(act.countScope, .once, "the stated maximum of 115 is a whole-log count")

        func rows(from county: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in
                qso(call: "K5C\(county)\(i)", band: .m40, mode: .cw, my: county, their: "TX")
            }
        }
        // SLC qualifies with 50; JAC falls one short with 49.
        let s = ScoreEngine.score(
            log: inLog(rows(from: "SLC", 50) + rows(from: "JAC", 49), station: .mobile),
            party: moqp
        )
        XCTAssertEqual(s.validQSOs, 99)
        XCTAssertEqual(s.selfActivatedCounties, ["SLC"], "fifty qualifies, forty-nine does not")
    }

    /// **The unit is contacts, not stations** — VaQP's rule reads almost the
    /// same and counts distinct callsigns. Fifty QSOs with one chaser would pay
    /// nothing there and pays here.
    func testTheThresholdCountsContactsRatherThanDistinctStations() {
        // Five chasers worked on ten bands each: fifty contacts, five stations.
        var rows: [QSO] = []
        for band in moqp.validBands {
            for i in 0..<5 {
                rows.append(qso(call: "K5C\(i)", band: band, mode: .cw, my: "SLC", their: "TX"))
            }
        }
        XCTAssertEqual(rows.count, 50, "ten bands × five stations")
        let s = ScoreEngine.score(log: inLog(rows, station: .mobile), party: moqp)
        XCTAssertEqual(s.validQSOs, 50)
        XCTAssertEqual(s.selfActivatedCounties, ["SLC"])
    }

    /// **OPEN QUESTION 1, pinned.** Rule 3 names "mobile or portable", and MOQP
    /// defines a third roving class it does not name there — Missouri
    /// Expedition. Expedition ships covered, because rule 3 pays "from a county
    /// or **county lines**" and the expedition is the class MOQP permits at
    /// "the intersection of two or more counties". A fixed station gains
    /// nothing either way.
    func testMobilePortableAndExpeditionQualifyAndFixedDoesNot() throws {
        let act = try XCTUnwrap(moqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(Set(act.categories), [.mobile, .portable, .expedition])

        let rows = (0..<50).map { i in
            qso(call: "K5C\(i)", band: .m40, mode: .cw, my: "SLC", their: "TX")
        }
        for category in StationProfile.CategoryStation.allCases {
            let s = ScoreEngine.score(log: inLog(rows, station: category), party: moqp)
            XCTAssertEqual(
                s.selfActivatedCounties,
                [.mobile, .portable, .expedition].contains(category) ? ["SLC"] : [],
                "\(category.rawValue)"
            )
        }
        XCTAssertTrue(try XCTUnwrap(moqp.notes).contains("WHETHER AN EXPEDITION EARNS"))
    }

    /// **The 115 ceiling settles this**, since rule 3 attaches no "if not
    /// otherwise worked" clause: "Missouri counties (**115 maximum**)" is
    /// exactly the entity list, so 116 is not an available total.
    func testACountyBothOperatedFromAndWorkedCountsOnce() throws {
        let act = try XCTUnwrap(moqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertTrue(act.notOtherwiseWorked, "116 is not an available total")

        var rows = (0..<49).map { i in
            qso(call: "K5C\(i)", band: .m40, mode: .cw, my: "SLC", their: "TX")
        }
        rows.append(qso(call: "W0SLC", band: .m40, mode: .cw, my: "SLC", their: "SLC"))
        let s = ScoreEngine.score(log: inLog(rows, station: .mobile), party: moqp)
        XCTAssertEqual(s.validQSOs, 50)
        XCTAssertEqual(s.workedValues(.county), ["SLC"])
        XCTAssertEqual(s.selfActivatedCounties, [], "already earned by working it")
        XCTAssertEqual(s.multiplierCount, 2, "SLC worked, and TX")
    }

    /// Out-of-state entrants never reach the rule.
    func testOutOfStateEntrantsAreUnaffected() {
        XCTAssertNil(moqp.multipliers.outState.activatedCountyMultiplier)
        XCTAssertEqual(
            ScoreEngine.score(log: outLog([qso(call: "W0A", their: "SLC")]), party: moqp)
                .selfActivatedCounties, []
        )
    }

    // MARK: Bonuses — two of the sponsor's five

    func testTheTwoSpecialEventStations() {
        XCTAssertEqual(moqp.bonuses, [
            .workStation(call: "W0MA", points: 100, scope: .once),
            .workStation(call: "K0GQ", points: 100, scope: .once),
        ])
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0MA", band: .m20, mode: .cw, their: "SLC"),
            qso(call: "W0MA", band: .m40, mode: .cw, their: "SLC"),
            qso(call: "K0GQ", band: .m20, mode: .phone, their: "JAC"),
        ]), party: moqp)
        XCTAssertEqual(s.bonusPoints, 200, "'a single 100-point bonus' each, not per band")
    }

    /// **KNOWN LIMITATION 1, pinned — and it affects every entrant.** Contacts on
    /// 40 and 80 m inside two six-hour daytime windows earn **+1 point each**, up
    /// to **250**. That is a band predicate, a time predicate and a cap — three
    /// things `BonusRule` has none of — and it adds to *QSO points*, so it is
    /// multiplied by the multiplier total as well.
    func testKnownGapThe40And80MetreDaytimeBonusIsNotApplied() throws {
        // A 40 m QSO inside the Saturday window scores the plain CW rate.
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", band: .m40, mode: .cw, their: "SLC"),
        ]), party: moqp)
        XCTAssertEqual(s.qsoPoints, 2, "current behaviour — the sponsor pays 3")

        let notes = try XCTUnwrap(moqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("TO CORRECT BY HAND"))
        XCTAssertTrue(notes.contains("BEFORE multiplying"),
                      "the operator must be told this one compounds")
    }

    /// **KNOWN LIMITATION 2, pinned.** A flat 100 points for submitting a
    /// Cabrillo log electronically — a bonus that is not about contacts at all,
    /// and the only such rule in the repo.
    func testKnownGapTheLogSubmissionBonusIsNotApplied() throws {
        XCTAssertEqual(moqp.bonuses.count, 2, "only the two station bonuses are modelled")
        XCTAssertTrue(try XCTUnwrap(moqp.notes).contains("KNOWN LIMITATION 2"))
    }

    // MARK: County lines, dupes, credit

    /// "the intersection of **two or more** counties", with no stated cap — so
    /// four is this app's own maximum, not a sponsor's number. Open question 2.
    func testCountyLinesAreUncappedSoTheDefaultApplies() throws {
        XCTAssertEqual(moqp.maxSimultaneousCounties, 4)
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W0EXP", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_775_916_000)
            ),
            myLocs: ["TX"],
            theirLocs: ["STL", "SLC", "STC"]
        )
        XCTAssertEqual(rows.count, 3, "'must log these contacts as separate QSOs'")
        let s = ScoreEngine.score(log: outLog(rows), party: moqp)
        XCTAssertEqual(s.multiplierCount, 3)
        XCTAssertTrue(try XCTUnwrap(moqp.openQuestions).contains("county-line limit"))
    }

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "SLC"),
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "JAC"),
        ]), party: moqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("slc", party: moqp, role: .inState).get().locations,
                       ["SLC"])
        XCTAssertEqual(try ExchangeParser.parse("STL", party: moqp, role: .inState).get().locations,
                       ["STL"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: moqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: moqp, role: .inState).get().locations,
                       ["DX"])
        guard case .failure = ExchangeParser.parse("MO", party: moqp, role: .inState) else {
            return XCTFail("MO must be rejected — Missouri stations send a county code")
        }
    }

    func testOutOfStateCreditIsRestrictedByInference() {
        XCTAssertTrue(moqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", their: "SLC"),
            qso(call: "K5B", their: "TX"),
        ]), party: moqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — moved a week for Easter

    /// **This is the only 2026 party whose date was moved off its own formula**,
    /// and the sponsor says why: "For 2026 due to the Easter weekend the contest
    /// is on 11-12th of April." The usual first full weekend would have been
    /// 4–5 April — the same weekend as Louisiana and Mississippi — so deriving
    /// this date from the formula would land a week early. This test pins that
    /// it is *not* the first weekend.
    func testScheduleIsTheSecondWeekendBecauseOfEaster() throws {
        let windows = try XCTUnwrap(moqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-11T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-12T04:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-04-12T14:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-04-12T20:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 14 * 3600)
        XCTAssertEqual(windows[1].end.timeIntervalSince(windows[1].start), 6 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 11)
        XCTAssertGreaterThan(utc.component(.day, from: windows[0].start), 7,
                             "NOT the first weekend — the formula would give 4–5 April")

        // …and it does not collide with the 4 April pair, which it otherwise would.
        for id in ["laqp", "msqp"] {
            let other = try XCTUnwrap(PartyCatalog.party(id: id))
            let theirs = try XCTUnwrap(other.schedule).first!
            XCTAssertLessThan(theirs.end, windows[0].start, "\(id) finishes a week earlier")
        }
    }

    func testNotesRecordTheEasterMoveAndBothRemainingLimitations() throws {
        let notes = try XCTUnwrap(moqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("DOES NOT FOLLOW THE USUAL FORMULA"))
        // Two, not three: rule 3's multiplier landed 2026-08-04.
        for n in 1...2 {
            XCTAssertTrue(notes.contains("KNOWN LIMITATION \(n)"), "limitation \(n)")
        }
        XCTAssertFalse(notes.contains("KNOWN LIMITATION 3"))
        XCTAssertTrue(notes.contains("FIFTY IS THE HIGHEST THRESHOLD OF ANY PARTY"))
        XCTAssertTrue(notes.contains("THE TRAP THIS PARTY TURNS ON IS STL versus SLC"))
    }
}

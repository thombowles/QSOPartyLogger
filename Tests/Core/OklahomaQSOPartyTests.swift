import XCTest
@testable import QSOPartyLogger

/// Oklahoma QSO Party — Oklahoma DX Association / OKQP, contact K5CM. Built from
/// the sponsor's official 2026 rules PDF, its county locator page and its 2026
/// summary page, read verbatim 2026-07-26. See docs/research/okqp_rules.md.
///
/// **The sharpest provenance trap of this run.** `qsl.net/okdxa/OKQP.htm` is the
/// **2003** rules, is still live, and is still the first search result — and it
/// is wrong in four scoring dimensions. `testTheShippedRulesAreThe2026OnesNotThe2003Ones`
/// is what stops a later session inheriting them.
final class OklahomaQSOPartyTests: XCTestCase {

    var okqp: PartyDefinition!

    override func setUpWithError() throws {
        okqp = try XCTUnwrap(PartyCatalog.party(id: "okqp"), "bundled OKQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W5ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "TUL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_773_496_800 + seq),  // 2026-03-14 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "okqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "TUL",
               station: StationProfile.CategoryStation = .fixed) -> ContestLog {
        var log = ContestLog(partyID: "okqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: County data — 77, and the sponsor names its own traps

    func testCountyData() {
        XCTAssertEqual(okqp.counties.count, 77, "Oklahoma has 77 counties")
        XCTAssertEqual(Set(okqp.counties.map(\.abbr)).count, 77)
        XCTAssertEqual(Set(okqp.counties.map(\.name)).count, 77)
        XCTAssertEqual(okqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// The seven pairs the sponsor itself says "cause considerable confusion".
    /// Every one is a case where the naive first three letters picks the *other*
    /// county of the pair — which makes them the best possible spot checks.
    func testTheSevenConfusionPairsTheSponsorNames() {
        XCTAssertEqual(okqp.county(for: "GAR")?.name, "Garfield")
        XCTAssertEqual(okqp.county(for: "GRV")?.name, "Garvin")
        XCTAssertEqual(okqp.county(for: "GRA")?.name, "Grady")
        XCTAssertEqual(okqp.county(for: "GNT")?.name, "Grant")
        XCTAssertEqual(okqp.county(for: "HAR")?.name, "Harmon")
        XCTAssertEqual(okqp.county(for: "HRP")?.name, "Harper")
        XCTAssertEqual(okqp.county(for: "MCL")?.name, "McClain")
        XCTAssertEqual(okqp.county(for: "MCU")?.name, "McCurtain")
        XCTAssertEqual(okqp.county(for: "ROG")?.name, "Rogers")
        XCTAssertEqual(okqp.county(for: "RGM")?.name, "Roger Mills")
        XCTAssertEqual(okqp.county(for: "WAS")?.name, "Washington")
        XCTAssertEqual(okqp.county(for: "WAT")?.name, "Washita")
        XCTAssertEqual(okqp.county(for: "WOO")?.name, "Woods")
        XCTAssertEqual(okqp.county(for: "WDW")?.name, "Woodward")
    }

    func testOtherCodesWorthChecking() {
        XCTAssertEqual(okqp.county(for: "MCI")?.name, "McIntosh", "the third Mc county")
        XCTAssertEqual(okqp.county(for: "LEF")?.name, "Le Flore", "two words")
        XCTAssertEqual(okqp.county(for: "OKL")?.name, "Oklahoma",
                       "the county — distinct from the OK token, which is never sent")
        XCTAssertEqual(okqp.county(for: "tul")?.name, "Tulsa", "case-insensitive")
        for absent in ["GARF", "HARP", "WOOD", "ROGE"] {
            XCTAssertNil(okqp.county(for: absent))
        }
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(okqp.cabrilloContest, "OK-QSO-PARTY",
                       "printed by the sponsor in its own Cabrillo example")
        XCTAssertEqual(okqp.homeState, "OK")
        XCTAssertEqual(okqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(okqp.dxStyle, .prefix, "'DX stations send … DXCC prefix'")
        XCTAssertTrue(okqp.exchangeIncludesRST)
        XCTAssertNil(okqp.scoreMultipliers, "power selects the entry class only")
        XCTAssertTrue(okqp.isPartiallyVerified)
    }

    /// **The 2003 page is still live and still first in search.** Every assertion
    /// here is a value it gets wrong, so building from it turns this test red
    /// instead of silently rescoring the party. Full diff in okqp_rules.md §1.
    func testTheShippedRulesAreThe2026OnesNotThe2003Ones() throws {
        XCTAssertFalse(okqp.exchangeIncludesSerial,
                       "the 2003 page says the exchange carries a QSO number; 2026 says a report")
        XCTAssertEqual(okqp.provinces.count, 13, "the 2003 page counts only 9 provinces")
        XCTAssertFalse(okqp.validBands.contains(.m160),
                       "the 2003 page lists 160 m; the 2026 rules start at 80 m")
        XCTAssertEqual(okqp.bonuses, [.activatedCountyCount(minQSOs: 10, points: 500)],
                       "the 2003 page has no activation bonus at all")
        XCTAssertTrue(try XCTUnwrap(okqp.notes).contains("IS THE 2003 RULES"))
    }

    /// "Operate **only** the 3.5, 7, 14, 21, 28, 50, and 144 MHz bands."
    func testSevenBandsWithNo160m() {
        XCTAssertEqual(okqp.validBands, [.m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for excluded in [Band.m160, .m60, .m30, .m17, .m12, .cm125, .cm70] {
            XCTAssertFalse(okqp.validBands.contains(excluded), "\(excluded.rawValue) excluded")
        }
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(okqp.points.points(for: .phone), 2)
        XCTAssertEqual(okqp.points.points(for: .cw), 3)
        XCTAssertEqual(okqp.points.points(for: .digital), 3)
        XCTAssertNil(okqp.homeStationPoints,
                     "stated identically for Oklahoma and non-Oklahoma stations")
    }

    /// "CW and Digital contacts will be scored separately, so you can work the
    /// same station on both CW and PSK and get credit for both modes." Exactly
    /// how `ModeClass` behaves — and the opposite of ILQP, which groups them.
    func testCWAndDigitalAreSeparateModesHere() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", band: .m20, mode: .cw, their: "TUL"),
            qso(call: "W5A", band: .m20, mode: .digital, their: "TUL"),
        ]), party: okqp)
        XCTAssertEqual(s.dupeCount, 0, "two modes, two QSOs")
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 6)
    }

    // MARK: Multipliers — once overall

    /// "A Multiplier counts once, regardless of the number bands or modes it is
    /// worked on." Neither a second band nor a second mode may add anything.
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(okqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(okqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", band: .m20, mode: .cw, their: "TUL"),
            qso(call: "W5A", band: .m40, mode: .cw, their: "TUL"),
            qso(call: "W5A", band: .m20, mode: .phone, their: "TUL"),
        ]), party: okqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfStateCeilingIs77Counties() {
        XCTAssertEqual(Set(okqp.multipliers.outState.classes), [.county])
        let rows = okqp.counties.enumerated().map { i, c in qso(call: "W5\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: okqp).multiplierCount, 77)
    }

    /// "DXCC countries (excluding US, Canada, KH6 and KL7)" with no cap — the
    /// sponsor's own aside calls it "the **unlimited** dxcc mult rule". This is
    /// the opposite of NCQP and MNQP, where all DX is one multiplier.
    func testDXCCCountriesAreUncappedForOklahomaStations() {
        XCTAssertNil(okqp.multipliers.inState.dxMultCap)
        let prefixes = ["DL", "JA", "G", "F", "I", "EA", "PY", "VK"]
        let rows = prefixes.enumerated().map { i, p in
            qso(call: "\(p)1AA\(i)", my: "TUL", their: p)
        }
        let s = ScoreEngine.score(log: inLog(rows), party: okqp)
        XCTAssertEqual(s.multiplierCount, 8, "every entity multiplies")
    }

    /// "The 50 states" is unqualified and Oklahoma is one of them, while OK
    /// stations always send a county — so the state is reachable only through a
    /// county. Shipped `true`; open question, since MNQP and NCQP both exclude
    /// their home state in so many words and this sponsor does not.
    func testOklahomaIsAMultiplierReachableThroughACounty() {
        XCTAssertTrue(okqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(okqp.validOutStateTokens.contains("OK"), "the token is never sent")
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W5A", my: "TUL", their: "OKL"),
        ]), party: okqp)
        XCTAssertEqual(s.workedValues(.county), ["OKL"])
        XCTAssertEqual(s.workedValues(.state), ["OK"], "the county yields the state too")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "The 50 states (**DC counts as Maryland**)" — as in VTQP, BCQP and MDC,
    /// and the opposite of MNQP, NCQP and SCQP. Six parties, split three-three.
    func testDCCountsAsMaryland() throws {
        XCTAssertEqual(okqp.stateAliases, ["DC": "MD"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: okqp, role: .inState).get().locations,
                       ["DC"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "TUL", their: "DC"),
            qso(call: "W3B", my: "TUL", their: "MD"),
        ]), party: okqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "one multiplier, not two")
    }

    /// "W/VE stations (**including KH6/KL7**) send … state or province. DX
    /// stations (**including KH2/KP4**) send … DXCC prefix." Stated in the same
    /// breath, and the split is unusual enough to pin.
    func testAlaskaAndHawaiiAreStatesWhileGuamAndPuertoRicoAreDX() throws {
        for token in ["AK", "HI"] {
            XCTAssertEqual(
                try ExchangeParser.parse(token, party: okqp, role: .inState).get().locations,
                [token]
            )
        }
        let s = ScoreEngine.score(log: inLog([
            qso(call: "KL7A", my: "TUL", their: "AK"),
            qso(call: "KH2B", my: "TUL", their: "KH2"),
            qso(call: "KP4C", my: "TUL", their: "KP4"),
        ]), party: okqp)
        XCTAssertEqual(s.workedValues(.state), ["AK"])
        XCTAssertEqual(Set(s.workedValues(.dx)), ["Guam", "Puerto Rico"], "US territories are DX here")
    }

    func testTheStandardThirteenProvinces() {
        XCTAssertEqual(okqp.provinces, MultClass.canadianProvinces)
        XCTAssertTrue(okqp.validOutStateTokens.contains("NL"))
    }

    // MARK: County lines — up to four, each on its own line

    /// "Oklahoma mobile stations operating on a 2, 3, or 4 county line may be
    /// counted as 2, 3, or 4 QSO and multipliers."
    func testUpToFourCounties() throws {
        XCTAssertEqual(okqp.maxSimultaneousCounties, 4)
        XCTAssertEqual(
            try ExchangeParser.parse("PIT/LAT/HAS", party: okqp, role: .inState).get().locations,
            ["PIT", "LAT", "HAS"],
            "the sponsor's own named junction"
        )
        XCTAssertEqual(
            ExchangeParser.parse("PIT/LAT/HAS/MCI/MUS", party: okqp, role: .inState),
            .failure(.tooManyCounties(5))
        )
    }

    /// "Do not put PIT/LAT/HAS on the same line in your log. Use a separate line
    /// for each county." Entering it here is *correct*: the expander writes the
    /// three separate lines the sponsor demands.
    func testTheSponsorsNamedJunctionExpandsToThreeLines() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "K5CM", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_773_496_800)
            ),
            myLocs: ["TX"],
            theirLocs: ["PIT", "LAT", "HAS"]
        )
        XCTAssertEqual(rows.count, 3, "'Use a separate line for each county'")
        let s = ScoreEngine.score(log: outLog(rows), party: okqp)
        XCTAssertEqual(s.validQSOs, 3, "'may be counted as 2, 3, or 4 QSO and multipliers'")
        XCTAssertEqual(s.qsoPoints, 9, "CW 3 points each")
        XCTAssertEqual(s.multiplierCount, 3)
    }

    // MARK: The mobile activation bonus — TnQP's rule, both numbers

    /// "Oklahoma Mobile stations can earn 500 points per county by making at
    /// least 10 QSO in the county."
    func testFiveHundredPointsPerCountyWithTenQSOs() {
        XCTAssertEqual(okqp.bonuses, [.activatedCountyCount(minQSOs: 10, points: 500)])

        func rows(_ county: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in qso(call: "W\(county)\(i)", my: county, their: "TX") }
        }
        // Ten QSOs from TUL pays; nine from OKL does not.
        var log = inLog(rows("TUL", 10) + rows("OKL", 9), station: .mobile)
        log.myLocation = .inState(counties: ["TUL"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: okqp).bonusPoints, 500)

        var both = inLog(rows("TUL", 10) + rows("OKL", 10), station: .mobile)
        both.myLocation = .inState(counties: ["TUL"])
        XCTAssertEqual(ScoreEngine.score(log: both, party: okqp).bonusPoints, 1000,
                       "500 per county activated")
    }

    /// The bonus is for Oklahoma **mobile** stations; a fixed entrant earns none.
    func testAFixedStationEarnsNoActivationBonus() {
        func rows(_ county: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in qso(call: "W\(county)\(i)", my: county, their: "TX") }
        }
        let s = ScoreEngine.score(log: inLog(rows("TUL", 12), station: .fixed), party: okqp)
        XCTAssertEqual(s.bonusPoints, 0)
    }

    // MARK: Dupes, exchange and scope of credit

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K5CM", band: .m40, mode: .cw, their: "TUL"),
            qso(call: "K5CM", band: .m40, mode: .cw, their: "OKL"),
        ]), party: okqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("tul", party: okqp, role: .inState).get().locations,
                       ["TUL"])
        XCTAssertEqual(try ExchangeParser.parse("RGM", party: okqp, role: .inState).get().locations,
                       ["RGM"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: okqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: okqp, role: .inState).get().locations,
                       ["DL"], "a DXCC prefix")
        guard case .failure = ExchangeParser.parse("OK", party: okqp, role: .inState) else {
            return XCTFail("OK must be rejected — Oklahoma stations send a county")
        }
    }

    /// "Non Oklahoma stations work only Oklahoma stations."
    func testOutOfStateEntrantsGetNoCreditForNonOklahomaContacts() {
        XCTAssertTrue(okqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", their: "TUL"),
            qso(call: "K5B", their: "TX"),
        ]), party: okqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — 12 + 8, and the CDT subtlety

    /// The sponsor's local anchors — "9 to 9 on Saturday, 9 to 5 on Sunday" —
    /// land exactly under **CDT**. Its note that "DST does NOT start on this
    /// weekend" means daylight time began the weekend *before* (8 March 2026),
    /// not that Oklahoma is on standard time. Under CST every anchor is an hour
    /// out, which is the trap this test pins.
    func testScheduleIsTwoWindowsTotallingTwentyHours() throws {
        let windows = try XCTUnwrap(okqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()

        XCTAssertEqual(windows[0].start, f.date(from: "2026-03-14T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-03-15T02:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600)

        XCTAssertEqual(windows[1].start, f.date(from: "2026-03-15T14:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-03-15T22:00:00Z"))
        XCTAssertEqual(windows[1].end.timeIntervalSince(windows[1].start), 8 * 3600)

        let total = windows.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        XCTAssertEqual(total, 20 * 3600,
                       "the rules' own '19 hour period' line agrees with nothing else")

        // The local anchors, checked against Oklahoma's actual offset that weekend.
        var cdt = Calendar(identifier: .gregorian)
        cdt.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(cdt.component(.hour, from: windows[0].start), 9, "9 am Saturday")
        XCTAssertEqual(cdt.component(.hour, from: windows[0].end), 21, "9 pm Saturday")
        XCTAssertEqual(cdt.component(.hour, from: windows[1].end), 17, "5 pm Sunday")
    }

    func testNotesRecordTheStalePageAndBothLimitations() throws {
        let notes = try XCTUnwrap(okqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"), "FT8/FT4 are barred")
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 2"), "the free-text CATEGORY line")
        XCTAssertTrue(notes.contains("DST BEGAN THE WEEKEND BEFORE".lowercased())
                        || notes.contains("BEGAN THE WEEKEND BEFORE"),
                      "the CDT reasoning must be recorded where an operator sees it")
        let questions = try XCTUnwrap(okqp.openQuestions)
        XCTAssertTrue(questions.contains("state multiplier for Oklahoma entrants"))
    }
}

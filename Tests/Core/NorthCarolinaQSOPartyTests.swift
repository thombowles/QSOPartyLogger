import XCTest
@testable import QSOPartyLogger

/// North Carolina QSO Party — NCQP Committee. Built from the sponsor's official
/// 2026 rules ("Updated 10/13/2025") and its county abbreviation sheet, read
/// verbatim 2026-07-26. See docs/research/ncqp_rules.md.
///
/// **The party with the most unmodellable scoring in the repo.** Its "Rarest of
/// NC" 10× QSO points and its five-county sweep both move every entrant's score
/// and neither fits the schema; the three `testKnownGap…` cases below pin what
/// the app does today so the gaps stay deliberate and visible.
final class NorthCarolinaQSOPartyTests: XCTestCase {

    var ncqp: PartyDefinition!

    override func setUpWithError() throws {
        ncqp = try XCTUnwrap(PartyCatalog.party(id: "ncqp"), "bundled NCQP should load")
    }

    /// The ten counties the sponsor designates "Rarest of NC", each worth 10×.
    static let rarest = ["CAB", "GRM", "VAN", "MAC", "DAV", "CUR", "PAM", "ALL", "PER", "CAS"]

    var seq: TimeInterval = 0
    /// NCQP exchanges call sign and location and **no signal report** — "Sending
    /// signal report (i.e., 59) is optional".
    func qso(
        call: String = "W4ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "WAK"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_772_377_200 + seq),  // 2026-03-01 15:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "ncqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(
        _ qsos: [QSO],
        from county: String = "WAK",
        station: StationProfile.CategoryStation = .fixed
    ) -> ContestLog {
        var log = ContestLog(partyID: "ncqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: County data — 100, read from the sheet's colour rather than its case

    func testCountyData() {
        XCTAssertEqual(ncqp.counties.count, 100, "North Carolina has 100 counties")
        XCTAssertEqual(Set(ncqp.counties.map(\.abbr)).count, 100)
        XCTAssertEqual(Set(ncqp.counties.map(\.name)).count, 100)
        XCTAssertEqual(ncqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// The sponsor encodes the code as the **dark-red** letters of the name, not
    /// as its capitals — and New Hanover is the county that proves the two are
    /// different. Its capital `H` is black, so a case-based read gives `NEWH`.
    func testNewHanoverIsNEWBecauseTheHIsBlack() {
        XCTAssertEqual(ncqp.county(for: "NEW")?.name, "New Hanover")
        XCTAssertNil(ncqp.county(for: "NEWH"),
                     "reading the capitals instead of the colour would produce this")
    }

    /// `DVD` Davidson against `DAV` Davie is the costliest confusion in this
    /// party: Davie is one of the ten rare counties, so mixing them swaps a
    /// 3-point QSO for a 30-point one.
    func testDavidsonAndDavieAreDifferentCountiesAndOnlyOneIsRare() {
        XCTAssertEqual(ncqp.county(for: "DVD")?.name, "Davidson")
        XCTAssertEqual(ncqp.county(for: "DAV")?.name, "Davie")
        XCTAssertTrue(Self.rarest.contains("DAV"))
        XCTAssertFalse(Self.rarest.contains("DVD"))
    }

    func testOtherCodesTheColourReadingHasToGetRight() {
        XCTAssertEqual(ncqp.county(for: "GRM")?.name, "Graham")
        XCTAssertEqual(ncqp.county(for: "GRA")?.name, "Granville", "GRA is not Graham")
        XCTAssertEqual(ncqp.county(for: "PEQ")?.name, "Perquimans")
        XCTAssertEqual(ncqp.county(for: "PER")?.name, "Person")
        XCTAssertEqual(ncqp.county(for: "WLK")?.name, "Wilkes")
        XCTAssertEqual(ncqp.county(for: "WIL")?.name, "Wilson", "WIL is Wilson, not Wilkes")
        XCTAssertEqual(ncqp.county(for: "MCD")?.name, "McDowell", "not 'Mcdowell'")
        XCTAssertEqual(ncqp.county(for: "LEE")?.name, "Lee",
                       "printed entirely in red, since the name is the code")
        XCTAssertEqual(ncqp.county(for: "wak")?.name, "Wake", "case-insensitive")
    }

    /// The sponsor's sheet misspells Chowan as "Chowen". Shipped as printed — the
    /// code is unaffected — and pinned so nobody "corrects" it later, exactly as
    /// the repo handles NHQP's "Merrimac".
    func testTheSponsorsChowanTypoShipsAsPrinted() {
        XCTAssertEqual(ncqp.county(for: "CHO")?.name, "Chowen")
    }

    /// All ten rare-county codes are cross-checked by the generator against the
    /// rules PDF, which prints them in plain text. Assert they all exist here.
    func testEveryRarestOfNCCodeIsARealCounty() {
        for code in Self.rarest {
            XCTAssertNotNil(ncqp.county(for: code), "\(code) must be a county")
        }
        XCTAssertEqual(Set(Self.rarest).count, 10)
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(ncqp.cabrilloContest, "NC-QSO-PARTY", "WA7BNM; the rules omit CONTEST:")
        XCTAssertEqual(ncqp.homeState, "NC")
        XCTAssertEqual(ncqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(ncqp.dxStyle, .token)
        XCTAssertFalse(ncqp.exchangeIncludesRST,
                       "'Sending signal report (i.e., 59) is optional'")
        XCTAssertFalse(ncqp.exchangeIncludesSerial)
        XCTAssertNil(ncqp.scoreMultipliers, "power selects the award class only")
        XCTAssertTrue(ncqp.isPartiallyVerified)
    }

    /// "Operate on 80/75, 40, 20, 15, 10, 6, and 2 meters. **No 160**, WARC, or
    /// above 2 meters." The only bundled party that runs 80 m and up while
    /// excluding 160.
    func testSevenBandsWith160mExcluded() {
        XCTAssertEqual(ncqp.validBands, [.m80, .m40, .m20, .m15, .m10, .m6, .m2])
        XCTAssertFalse(ncqp.validBands.contains(.m160), "explicitly excluded")
        for excluded in [Band.m60, .m30, .m17, .m12, .cm125, .cm70] {
            XCTAssertFalse(ncqp.validBands.contains(excluded))
        }
    }

    // MARK: Points — the only party where digital outscores CW

    func testPointsByMode() {
        XCTAssertEqual(ncqp.points.points(for: .phone), 2)
        XCTAssertEqual(ncqp.points.points(for: .cw), 3)
        XCTAssertEqual(ncqp.points.points(for: .digital), 5,
                       "the only bundled party where digital beats CW")
        XCTAssertNil(ncqp.homeStationPoints, "points are by mode, not by who was worked")
    }

    /// **KNOWN LIMITATION 1, pinned — the largest scoring gap in this app.** A QSO
    /// with one of the ten "Rarest of NC" counties is worth 10× (phone 20, CW 30,
    /// digital 50), *before* multiplication. `PointsTable` is keyed by mode alone,
    /// so the app pays the ordinary rate. This test records what it actually does.
    func testKnownGapRarestCountiesDoNotPayTenTimes() throws {
        let rare = ScoreEngine.score(log: outLog([
            qso(band: .m20, mode: .cw, their: "GRM"),
        ]), party: ncqp)
        XCTAssertEqual(rare.qsoPoints, 3, "current behaviour — the sponsor pays 30")

        let ordinary = ScoreEngine.score(log: outLog([
            qso(band: .m20, mode: .cw, their: "WAK"),
        ]), party: ncqp)
        XCTAssertEqual(rare.qsoPoints, ordinary.qsoPoints,
                       "a rare county scores exactly like any other today")

        let notes = try XCTUnwrap(ncqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("TO CORRECT BY HAND"),
                      "the operator must be given the arithmetic")
    }

    /// **KNOWN LIMITATION 2, pinned.** Five of the ten rare counties pays 500
    /// after multiplication. `sweepTiers` counts *any* counties, so it cannot be
    /// reused; nothing ships instead.
    func testKnownGapTheFiveRareCountySweepIsNotPaid() throws {
        let rows = Self.rarest.prefix(5).enumerated().map { i, c in
            qso(call: "W4R\(i)", their: c)
        }
        let s = ScoreEngine.score(log: outLog(Array(rows)), party: ncqp)
        XCTAssertEqual(s.validQSOs, 5)
        XCTAssertEqual(s.bonusPoints, 0, "current behaviour — the sponsor pays 500")
        XCTAssertEqual(ncqp.bonuses, [], "no sweep rule can express 'five of a named ten'")
        XCTAssertTrue(try XCTUnwrap(ncqp.notes).contains("KNOWN LIMITATION 2"))
    }

    // MARK: Multipliers — once overall, and the sponsor states the total

    /// "Count each multiplier worked only once across all modes, bands, and
    /// operating location." The Article 18 pair: neither a second band nor a
    /// second mode may add anything.
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(ncqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(ncqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", band: .m20, mode: .cw, their: "WAK"),
            qso(call: "W4A", band: .m40, mode: .cw, their: "WAK"),
            qso(call: "W4A", band: .m20, mode: .phone, their: "WAK"),
        ]), party: ncqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfStateCeilingIs100Counties() {
        XCTAssertEqual(Set(ncqp.multipliers.outState.classes), [.county])
        let rows = ncqp.counties.enumerated().map { i, c in qso(call: "W4\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: ncqp).multiplierCount, 100)
    }

    /// "Work 100 North Carolina Counties, 49 US States (not NC) plus DC, 13
    /// Canadian Provinces/Territories, plus one DX. **164 total possible.**"
    func testInStateMaximumIsExactlyTheSponsorsStated164() {
        XCTAssertEqual(Set(ncqp.multipliers.inState.classes), [.county, .state, .province, .dx])
        var rows: [QSO] = []
        for (i, c) in ncqp.counties.enumerated() {
            rows.append(qso(call: "W4C\(i)", my: "WAK", their: c.abbr))
        }
        let stateTokens = MultClass.acceptedStateTokens.subtracting(["NC"]).sorted()
        XCTAssertEqual(stateTokens.count, 50, "49 states + DC")
        for (i, t) in stateTokens.enumerated() {
            rows.append(qso(call: "K\(i)ST", my: "WAK", their: t))
        }
        for (i, p) in MultClass.canadianProvinces.sorted().enumerated() {
            rows.append(qso(call: "VE\(i)P", my: "WAK", their: p))
        }
        rows.append(qso(call: "JA1XX", my: "WAK", their: "DX"))

        let s = ScoreEngine.score(log: inLog(rows), party: ncqp)
        XCTAssertEqual(s.workedValues(.county).count, 100)
        XCTAssertEqual(s.workedValues(.state).count, 50)
        XCTAssertEqual(s.workedValues(.province).count, 13)
        XCTAssertEqual(s.workedValues(.dx), ["DX"], "'plus one DX' — all DX is one multiplier")
        XCTAssertEqual(s.multiplierCount, 164, "the sponsor's own stated maximum")
        // …and WAK, the county this log is operating from, is among the 100 it
        // worked. The county-activation multiplier is forfeit on a worked county
        // precisely so that this stays 164 rather than becoming 165, which is
        // how the arithmetic settles a rule the sponsor never qualified.
        XCTAssertEqual(s.selfActivatedCounties, [])
    }

    /// "49 US States (**not NC**)" — stated outright in the negative, as MNQP
    /// does and the opposite of SCQP.
    func testNorthCarolinaIsNotAStateMultiplier() {
        XCTAssertFalse(ncqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "WAK", their: "MEC")]), party: ncqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(ncqp.validOutStateTokens.contains("NC"))
    }

    func testDCCountsWithTheStatesAndIsNotAliased() throws {
        XCTAssertEqual(ncqp.stateAliases, [:])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: ncqp, role: .inState).get().locations,
                       ["DC"])
    }

    // MARK: The county you operate from — every NC station, fixed included

    /// "Note: **NC stations** may include the county from which operation takes
    /// place in the Multiplier count regardless of whether any QSOs are logged
    /// from that same county."
    ///
    /// **The broadest form of this rule in the catalogue.** Four other sponsors
    /// give it to roving categories; NCQP says "NC stations", naming Mobile and
    /// Portable only as the multi-county case — so a *fixed* NC station counts
    /// the county it sits in, and NCQP is the only party where that is true.
    func testEveryNCStationCountsTheCountyItOperatesFrom() throws {
        let act = try XCTUnwrap(ncqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(Set(act.categories), Set(StationProfile.CategoryStation.allCases))

        for category in StationProfile.CategoryStation.allCases {
            let s = ScoreEngine.score(
                log: inLog([qso(call: "K5A", my: "WAK", their: "TX")], station: category),
                party: ncqp
            )
            XCTAssertEqual(s.selfActivatedCounties, ["WAK"], "\(category.rawValue)")
            XCTAssertEqual(s.multiplierCount, 2, "TX worked, WAK sat in")
        }
    }

    /// "…this provision is applied to **each county activated where at least one
    /// QSO was completed**." A mobile counts every county it made a QSO from.
    func testAMobileCountsEachCountyItActivated() throws {
        let act = try XCTUnwrap(ncqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(act.minCount, 1)
        XCTAssertEqual(act.countUnit, .qsos)
        XCTAssertEqual(act.countScope, .once, "counted once, like everything else here")

        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", my: "WAK", their: "TX"),
            qso(call: "K5B", my: "MEC", their: "OK"),
            qso(call: "K5C", my: "GRM", their: "VA"),
        ], station: .mobile), party: ncqp)
        XCTAssertEqual(s.selfActivatedCounties, ["WAK", "MEC", "GRM"])
        XCTAssertEqual(s.multiplierCount, 6, "three states worked, three counties sat in")
    }

    /// **The 164 ceiling is what settles this**, since the rules attach no "if
    /// not otherwise worked" clause the way TnQP and VAQP do: 100 counties + 50
    /// state-class tokens + 13 provinces + 1 DX is exactly 164, so a county both
    /// operated from and worked cannot make it 165.
    func testACountyBothOperatedFromAndWorkedCountsOnce() throws {
        let act = try XCTUnwrap(ncqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertTrue(act.notOtherwiseWorked, "165 is not an available total")

        let s = ScoreEngine.score(log: inLog([
            qso(call: "W4A", my: "WAK", their: "WAK"),
        ], station: .mobile), party: ncqp)
        XCTAssertEqual(s.workedValues(.county), ["WAK"])
        XCTAssertEqual(s.selfActivatedCounties, [], "already earned by working it")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// Out-of-state entrants never reach the rule: it lives on the in-state side.
    func testOutOfStateEntrantsAreUnaffected() {
        XCTAssertNil(ncqp.multipliers.outState.activatedCountyMultiplier)
        let s = ScoreEngine.score(log: outLog([qso(call: "W4A", their: "WAK")]), party: ncqp)
        XCTAssertEqual(s.selfActivatedCounties, [])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: County lines — two, logged as two

    func testCountyLineIsTwoAndLogsAsTwoRows() throws {
        XCTAssertEqual(ncqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            ExchangeParser.parse("WAK/DUR/ORA", party: ncqp, role: .inState),
            .failure(.tooManyCounties(3)),
            "'A maximum of two counties may be worked simultaneously'"
        )
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W4LIN", rstSent: "", rstRcvd: "",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_772_377_200)
            ),
            myLocs: ["TX"],
            theirLocs: ["WAK", "DUR"]
        )
        XCTAssertEqual(rows.count, 2, "'must be logged as separate QSOs with two lines'")
        let s = ScoreEngine.score(log: outLog(rows), party: ncqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Dupes and scope of credit

    func testDupesAreOncePerBandPerMode() {
        let a = qso(call: "W4M", band: .m20, mode: .cw, their: "WAK")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let s = ScoreEngine.score(log: outLog([a, repeated]), party: ncqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 1)
    }

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4MOB", band: .m40, mode: .cw, their: "WAK"),
            qso(call: "W4MOB", band: .m40, mode: .cw, their: "DUR"),
        ]), party: ncqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("wak", party: ncqp, role: .inState).get().locations,
                       ["WAK"])
        XCTAssertEqual(try ExchangeParser.parse("NEW", party: ncqp, role: .inState).get().locations,
                       ["NEW"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: ncqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: ncqp, role: .inState).get().locations,
                       ["DX"])
        guard case .failure = ExchangeParser.parse("NC", party: ncqp, role: .inState) else {
            return XCTFail("NC must be rejected — North Carolina stations send a county")
        }
    }

    /// "Stations outside of North Carolina (Non-NC) work NC stations only."
    func testOutOfStateEntrantsGetNoCreditForNonNorthCarolinaContacts() {
        XCTAssertTrue(ncqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", their: "WAK"),
            qso(call: "K5B", their: "TX"),
        ]), party: ncqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — ten hours, Sunday only

    func testScheduleIsOneTenHourSundayWindow() throws {
        let windows = try XCTUnwrap(ncqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-03-01T15:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-03-02T01:00:00Z"),
                       "printed as a round instant — no last-minute notation to resolve")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 10 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 1, "Sunday, like ILQP")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 1)
        XCTAssertEqual(utc.component(.month, from: windows[0].start), 3)
    }

    func testNotesRecordEveryLimitationAndTheFT8Exclusion() throws {
        let notes = try XCTUnwrap(ncqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        // Two, not three: the county-activation multiplier stopped being a
        // limitation on 2026-08-04 and its prose is now a plain statement of
        // what the app does.
        for n in 1...2 {
            XCTAssertTrue(notes.contains("KNOWN LIMITATION \(n)"), "limitation \(n)")
        }
        XCTAssertFalse(notes.contains("KNOWN LIMITATION 3"))
        XCTAssertTrue(notes.contains("EVERY NC STATION COUNTS THE COUNTY IT OPERATES FROM"))
        XCTAssertTrue(notes.contains("KEEP FT8/FT4 OUT OF THIS LOG"),
                      "FT8/FT4 belong to the separate Weak Signal Showcase")
        XCTAssertTrue(notes.contains("ENCODED BY COLOUR"))
        let questions = try XCTUnwrap(ncqp.openQuestions)
        XCTAssertTrue(questions.contains("BOTH CHANGE THE FINAL SCORE FOR EVERY ENTRANT"))
    }
}

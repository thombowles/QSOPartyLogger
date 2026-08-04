import XCTest
@testable import QSOPartyLogger

/// South Carolina QSO Party — the SCQP Team, scqso.com. Built from the sponsor's
/// official 2026 PDF, header "SOUTH CAROLINA QSO PARTY RULES (rev. 2.2.26)",
/// read verbatim 2026-07-26. See docs/research/scqp_rules.md.
///
/// Two things set this party apart and both are easy to get backwards: **points
/// are paid by who was worked, not by mode** (2 for an SC station, 4 for anyone
/// else), and **South Carolina is a multiplier reachable only through a county**
/// — which the sponsor states more plainly than any other party in this repo.
final class SouthCarolinaQSOPartyTests: XCTestCase {

    var scqp: PartyDefinition!

    override func setUpWithError() throws {
        scqp = try XCTUnwrap(PartyCatalog.party(id: "scqp"), "bundled SCQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W4ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "RICH"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_772_290_800 + seq),  // 2026-02-28 15:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "scqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(
        _ qsos: [QSO],
        from county: String = "RICH",
        station: StationProfile.CategoryStation = .fixed
    ) -> ContestLog {
        var log = ContestLog(partyID: "scqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: County data — 46, with LEE the only 3-character code

    func testCountyData() {
        XCTAssertEqual(scqp.counties.count, 46, "South Carolina has 46 counties")
        XCTAssertEqual(Set(scqp.counties.map(\.abbr)).count, 46)
        XCTAssertEqual(Set(scqp.counties.map(\.name)).count, 46)
    }

    /// Mixed lengths, and unlike ILQP the rules give no note about it — the
    /// generator's assertion and this test are the only things that would catch
    /// a silent change.
    func testLeeIsTheOnlyThreeCharacterCode() {
        XCTAssertEqual(scqp.countyAbbrLengths, [3, 4])
        XCTAssertEqual(scqp.countyAbbrLengthHint, "3/4")
        XCTAssertEqual(scqp.counties.filter { $0.abbr.count == 3 }.map(\.abbr), ["LEE"])
        XCTAssertEqual(scqp.county(for: "LEE")?.name, "Lee")
    }

    /// `CHOU` is Calhoun, not `CALH` — **the same code Alabama uses for its own
    /// Calhoun**. Same code, same county name, two different parties; pinned in
    /// both so neither is "corrected" toward the other.
    func testCalhounIsCHOUHereJustAsInAlabama() throws {
        XCTAssertEqual(scqp.county(for: "CHOU")?.name, "Calhoun")
        XCTAssertNil(scqp.county(for: "CALH"))
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        XCTAssertEqual(alqp.county(for: "CHOU")?.name, "Calhoun",
                       "the coincidence is real and is worth knowing")
    }

    /// Three counties begin "Ch" and none of them is `CHER`.
    func testTheThreeChCounties() {
        XCTAssertEqual(scqp.county(for: "CHES")?.name, "Chester")
        XCTAssertEqual(scqp.county(for: "CHFD")?.name, "Chesterfield")
        XCTAssertEqual(scqp.county(for: "CKEE")?.name, "Cherokee")
        XCTAssertNil(scqp.county(for: "CHER"))
    }

    func testOtherIrregularAbbreviations() {
        XCTAssertEqual(scqp.county(for: "GVIL")?.name, "Greenville")
        XCTAssertEqual(scqp.county(for: "GRWD")?.name, "Greenwood")
        XCTAssertNil(scqp.county(for: "GREE"), "neither Greenville nor Greenwood is GREE")
        XCTAssertEqual(scqp.county(for: "LNCS")?.name, "Lancaster")
        XCTAssertEqual(scqp.county(for: "LAUR")?.name, "Laurens")
        XCTAssertEqual(scqp.county(for: "MCOR")?.name, "McCormick")
        XCTAssertEqual(scqp.county(for: "CLRN")?.name, "Clarendon")
        XCTAssertEqual(scqp.county(for: "ORNG")?.name, "Orangeburg")
        XCTAssertEqual(scqp.county(for: "rich")?.name, "Richland", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(scqp.cabrilloContest, "SC-QSO-PARTY",
                       "printed by the sponsor in its own example log")
        XCTAssertEqual(scqp.homeState, "SC")
        XCTAssertEqual(scqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(scqp.dxStyle, .token, "'Signal report and \"DX\" (not country)'")
        XCTAssertTrue(scqp.exchangeIncludesRST)
        XCTAssertFalse(scqp.exchangeIncludesSerial)
        XCTAssertNil(scqp.scoreMultipliers, "power selects the award category only")
        XCTAssertTrue(scqp.isPartiallyVerified)
    }

    /// "The SCQP shall be conducted on the 160, 80, 40, 20, 15, 10, 6 and 2 meter
    /// bands **only**" — the most explicit band list of any party built this run.
    /// The suggested-frequency table stops at 6 m; 2 m is in rule 3 and ships.
    func testEightBandsStatedOutright() {
        XCTAssertEqual(scqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for excluded in [Band.m60, .m30, .m17, .m12, .cm125, .cm70] {
            XCTAssertFalse(scqp.validBands.contains(excluded), "\(excluded.rawValue) excluded")
        }
        XCTAssertTrue(scqp.validBands.contains(.m2),
                      "2 m has no suggested frequency but is in the band rule")
    }

    // MARK: Points — by who was worked, not by mode

    /// The distinctive rule. An out-of-state entrant may only work SC stations,
    /// so **every** contact in their log is worth two points, in every mode.
    func testOutOfStateEntrantsEarnTwoPointsForEveryContact() {
        let s = ScoreEngine.score(log: outLog([
            qso(band: .m20, mode: .phone, their: "RICH"),
            qso(band: .m20, mode: .cw, their: "CHAR"),
            qso(band: .m20, mode: .digital, their: "BEAU"),
        ]), party: scqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 6, "2 each — phone, CW and digital alike")
    }

    /// An SC entrant is paid **4** for a contact outside the state and **2** for
    /// one with another SC station. Mode changes nothing on either side.
    func testInStateEntrantsEarnFourOutsideAndTwoInside() {
        let outside = ScoreEngine.score(log: inLog([
            qso(call: "K5A", mode: .phone, my: "RICH", their: "TX"),
            qso(call: "VE3B", mode: .cw, my: "RICH", their: "ON"),
            qso(call: "DL1C", mode: .digital, my: "RICH", their: "DX"),
        ]), party: scqp)
        XCTAssertEqual(outside.qsoPoints, 12, "4 each, every mode")

        let inside = ScoreEngine.score(log: inLog([
            qso(call: "W4D", mode: .phone, my: "RICH", their: "CHAR"),
            qso(call: "W4E", mode: .cw, my: "RICH", their: "BEAU"),
        ]), party: scqp)
        XCTAssertEqual(inside.qsoPoints, 4, "2 each for other South Carolina stations")
    }

    /// The two tables are the MEQP shape, and this is the first party where the
    /// *higher* value is for out-of-area contacts — MEQP pays more for home-state
    /// ones. Pinned so the direction cannot be flipped by reflex.
    func testTheTwoPointsTablesAndTheirDirection() throws {
        XCTAssertEqual(scqp.points, .init(phone: 4, cw: 4, digital: 4))
        XCTAssertEqual(try XCTUnwrap(scqp.homeStationPoints), .init(phone: 2, cw: 2, digital: 2))
        let abbrs = Set(scqp.counties.map(\.abbr))
        XCTAssertEqual(scqp.pointsTable(forTheirLoc: "RICH", countyAbbrs: abbrs).cw, 2)
        XCTAssertEqual(scqp.pointsTable(forTheirLoc: "TX", countyAbbrs: abbrs).cw, 4)
        XCTAssertEqual(scqp.pointsTable(forTheirLoc: "DX", countyAbbrs: abbrs).cw, 4)
    }

    // MARK: Multipliers — once per band and mode

    func testMultipliersCountOncePerBandAndMode() {
        XCTAssertEqual(scqp.multipliers.inState.countScope, .perBandMode)
        XCTAssertEqual(scqp.multipliers.outState.countScope, .perBandMode)

        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", band: .m20, mode: .cw, their: "RICH"),
            qso(call: "W4A", band: .m20, mode: .phone, their: "RICH"),
            qso(call: "W4A", band: .m40, mode: .cw, their: "RICH"),
        ]), party: scqp)
        XCTAssertEqual(s.multiplierCount, 3, "one county, three band/mode slots")

        // …and the same slot twice adds nothing.
        var second = qso(call: "W4B", band: .m20, mode: .cw, their: "RICH")
        second.id = UUID()
        let repeated = ScoreEngine.score(log: outLog([
            qso(call: "W4A", band: .m20, mode: .cw, their: "RICH"), second,
        ]), party: scqp)
        XCTAssertEqual(repeated.multiplierCount, 1)
    }

    func testOutOfStateCountsSouthCarolinaCountiesOnly() {
        XCTAssertEqual(Set(scqp.multipliers.outState.classes), [.county])
        let rows = scqp.counties.enumerated().map { i, c in qso(call: "W4\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: scqp).multiplierCount, 46)
    }

    /// **The repo's clearest statement of `homeStateCountsViaCounty`:** "Each USA
    /// state **including South Carolina** and Washington, D.C." followed at once
    /// by "When logging other SC stations, enter the SC County as the exchange
    /// (**not SC**)." A multiplier that exists, is reachable only through a
    /// county, and whose own token is forbidden.
    func testSouthCarolinaIsAMultiplierReachableOnlyThroughACounty() {
        XCTAssertTrue(scqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(scqp.validOutStateTokens.contains("SC"), "the token is never sent")

        let s = ScoreEngine.score(log: inLog([
            qso(call: "W4A", my: "RICH", their: "CHAR"),
        ]), party: scqp)
        XCTAssertEqual(s.workedValues(.county), ["CHAR"])
        XCTAssertEqual(s.workedValues(.state), ["SC"], "the county yields the state too")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testInStateCountsCountiesStatesAndProvinces() {
        XCTAssertEqual(Set(scqp.multipliers.inState.classes), [.county, .state, .province])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5B", my: "RICH", their: "TX"),
            qso(call: "VE3C", my: "RICH", their: "ON"),
        ]), party: scqp)
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "DX contacts count for QSO points only. Enter DX for the exchange."
    func testDXEarnsPointsButNoMultiplier() {
        XCTAssertFalse(scqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "JA1A", my: "RICH", their: "DX"),
            qso(call: "DL1B", band: .m40, my: "RICH", their: "DX"),
        ]), party: scqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 8, "4 each — they are outside South Carolina")
        XCTAssertEqual(s.multiplierCount, 0)
    }

    /// "Note that Washington, D.C. is a multiplier for contest purposes." SCQP
    /// counts DC in its own right, unlike VTQP, BCQP and MDC, which fold it into
    /// Maryland. Three of the last four parties have done this differently.
    func testDCIsItsOwnMultiplierAndIsNotAliased() throws {
        XCTAssertEqual(scqp.stateAliases, [:])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: scqp, role: .inState).get().locations,
                       ["DC"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "RICH", their: "DC"),
            qso(call: "W3B", my: "RICH", their: "MD"),
        ]), party: scqp)
        XCTAssertEqual(Set(s.workedValues(.state)), ["DC", "MD"], "two multipliers, not one")
    }

    // MARK: 9.2.2 item 3 — each SC county activated

    /// "**Each SC county activated.** At least one (1) QSO must be made from a
    /// county in order for it to count as activated." — 9.2.2, whose heading is
    /// *SC Mobile/Expedition Stations*.
    func testMobileCountsEachCountyItActivates() throws {
        let act = try XCTUnwrap(scqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(act.minCount, 1, "\"At least one (1) QSO\"")
        XCTAssertEqual(act.countUnit, .qsos)

        // A mobile that has worked one Texan from each of two SC counties.
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", band: .m20, mode: .cw, my: "RICH", their: "TX"),
            qso(call: "K5B", band: .m20, mode: .cw, my: "CHAR", their: "TX"),
        ], station: .mobile), party: scqp)
        XCTAssertEqual(s.selfActivatedCounties, ["RICH", "CHAR"])
        XCTAssertEqual(s.multiplierCount, 3, "TX worked, plus the two counties sat in")
    }

    /// "Expedition stations that operate from more than one county will receive
    /// a multiplier (**ONCE PER MODE PER BAND**) for each county activated" —
    /// the sponsor scopes it themselves, and it matches how SCQP counts
    /// everything else.
    func testTheActivationCountsOncePerBandPerMode() throws {
        let act = try XCTUnwrap(scqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(act.countScope, .perBandMode)

        // One county, four band/mode slots operated from it.
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", band: .m20, mode: .cw, my: "RICH", their: "TX"),
            qso(call: "K5B", band: .m20, mode: .phone, my: "RICH", their: "TX"),
            qso(call: "K5C", band: .m40, mode: .cw, my: "RICH", their: "TX"),
            qso(call: "K5D", band: .m40, mode: .phone, my: "RICH", their: "TX"),
        ], station: .expedition), party: scqp)
        XCTAssertEqual(
            s.multiplierKeys.filter { $0.activated }.count, 4,
            "RICH once in each of the four slots it was operated from"
        )
        // The case that would pass under the wrong scope: `once` would give 1.
        XCTAssertEqual(s.multiplierCount, 8, "four TX slots plus four RICH slots")
    }

    /// Mobile, Portable and Expedition qualify; Fixed does not, and neither does
    /// Rover — SCQP has no such class. 6.2.1 is why Portable is in: "A single
    /// mobile **or portable** station that operates from at least two (2)
    /// different South Carolina counties".
    func testOnlyTheCategoriesRule922NamesQualify() throws {
        let act = try XCTUnwrap(scqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(Set(act.categories), [.mobile, .portable, .expedition])

        let rows = [qso(call: "K5A", my: "RICH", their: "TX")]
        for category in StationProfile.CategoryStation.allCases {
            let s = ScoreEngine.score(log: inLog(rows, station: category), party: scqp)
            XCTAssertEqual(
                s.selfActivatedCounties,
                [.mobile, .portable, .expedition].contains(category) ? ["RICH"] : [],
                "\(category.rawValue)"
            )
        }

        // And an out-of-state entrant never reaches the rule at all.
        XCTAssertNil(scqp.multipliers.outState.activatedCountyMultiplier)
        XCTAssertEqual(
            ScoreEngine.score(log: outLog([qso(call: "W4A", their: "RICH")]), party: scqp)
                .selfActivatedCounties, []
        )
    }

    /// **SCQP is the only one of the five parties with this rule that is
    /// additive.** 9.2.2 lists "1. Each South Carolina county" and "3. Each SC
    /// county activated" as separate numbered multipliers, adds no "if not
    /// otherwise worked" clause, and prints no county ceiling — so a mobile that
    /// both sits in a county and works somebody there counts it twice in that
    /// slot. Recorded as an open question; see `notes`.
    func testAnActivatedCountyThatWasAlsoWorkedCountsTwice() throws {
        let act = try XCTUnwrap(scqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertFalse(act.notOtherwiseWorked)

        let s = ScoreEngine.score(log: inLog([
            qso(call: "W4A", band: .m20, mode: .cw, my: "RICH", their: "RICH"),
        ], station: .mobile), party: scqp)
        XCTAssertEqual(s.workedValues(.county), ["RICH"])
        XCTAssertEqual(s.selfActivatedCounties, ["RICH"])
        XCTAssertEqual(
            s.multiplierCount, 3,
            "RICH worked, RICH activated, and SC via the county"
        )
    }

    /// The activation is a multiplier, not a bonus: it multiplies QSO points.
    /// SCQP has no `activatedCountyCount` bonus, so this is the whole of it.
    func testTheActivationMultipliesRatherThanAdds() {
        XCTAssertFalse(
            scqp.bonuses.contains {
                if case .activatedCountyCount = $0 { return true }
                return false
            },
            "SCQP pays for activation with a multiplier and nothing else"
        )
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", band: .m20, mode: .cw, my: "RICH", their: "TX"),
        ], station: .mobile), party: scqp)
        XCTAssertEqual(s.qsoPoints, 4, "a Texan is worth 4")
        XCTAssertEqual(s.multiplierCount, 2, "TX worked, RICH activated")
        XCTAssertEqual(s.total, 4 * 2, "no bonus points anywhere in this log")
    }

    // MARK: Three bonus stations, once per band per mode

    /// "Bonus Stations may be worked ONCE per BAND per MODE for bonus points…
    /// 350 points - W4CAE, 250 points - WW4SF, 250 points - K4YTZ." The scope is
    /// the case added to `WorkStationScope` in the preceding commit.
    func testTheThreeBonusStations() {
        XCTAssertEqual(scqp.bonuses, [
            .workStation(call: "W4CAE", points: 350, scope: .perBandMode),
            .workStation(call: "WW4SF", points: 250, scope: .perBandMode),
            .workStation(call: "K4YTZ", points: 250, scope: .perBandMode),
        ])
        let all3 = ScoreEngine.score(log: outLog([
            qso(call: "W4CAE", their: "RICH"),
            qso(call: "WW4SF", their: "CHAR"),
            qso(call: "K4YTZ", their: "YORK"),
        ]), party: scqp)
        XCTAssertEqual(all3.bonusPoints, 850, "350 + 250 + 250 in one band/mode slot")
    }

    /// The sponsor's own worked example: "You can work WW4SF/CHAR, WW4SF/GVIL,
    /// WW4SF/JASP and WW4SF/HORR on 40m CW, but only the first contact with WW4SF
    /// on 40m CW will qualify for Bonus Station points." Those four still pay QSO
    /// points and four county multipliers.
    func testTheSponsorsOwnMobileBonusExample() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "WW4SF", band: .m40, mode: .cw, their: "CHAR"),
            qso(call: "WW4SF", band: .m40, mode: .cw, their: "GVIL"),
            qso(call: "WW4SF", band: .m40, mode: .cw, their: "JASP"),
            qso(call: "WW4SF", band: .m40, mode: .cw, their: "HORR"),
        ]), party: scqp)
        XCTAssertEqual(s.validQSOs, 4, "a mobile changing county is a new station")
        XCTAssertEqual(s.qsoPoints, 8, "2 points each")
        XCTAssertEqual(s.multiplierCount, 4, "four counties, all on 40 m CW")
        XCTAssertEqual(s.bonusPoints, 250, "but the bonus pays once on 40 m CW")
        XCTAssertEqual(s.total, 8 * 4 + 250, "QSO points × multipliers + bonus")
    }

    func testAnotherBandOrModeAddsTheBonusAgain() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4CAE", band: .m40, mode: .cw, their: "RICH"),
            qso(call: "W4CAE", band: .m40, mode: .phone, their: "RICH"),
            qso(call: "W4CAE", band: .m20, mode: .cw, their: "RICH"),
        ]), party: scqp)
        XCTAssertEqual(s.bonusPoints, 1050, "350 in each of three band/mode slots")
    }

    // MARK: Dupes

    /// "for contest purposes, FT8, FT4, PSK, RTTY, JT65 or other digital modes
    /// shall be considered equivalent. Thus a FT8/4 and RTTY contact on the same
    /// band with the same station is considered a dupe." — which is exactly what
    /// `ModeClass.digital` already does, and the exact opposite of VTQP.
    func testAllDigitalModesAreOneModeHere() {
        var ft8 = qso(call: "W4M", band: .m20, mode: .digital, their: "RICH")
        ft8.rawMode = "FT8"
        var rtty = qso(call: "W4M", band: .m20, mode: .digital, their: "RICH")
        rtty.rawMode = "RTTY"
        rtty.id = UUID()
        let s = ScoreEngine.score(log: outLog([ft8, rtty]), party: scqp)
        XCTAssertEqual(s.dupeCount, 1, "the sponsor calls this a dupe, and so does this app")
        XCTAssertEqual(s.validQSOs, 1)
    }

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4MOB", band: .m40, mode: .cw, their: "CHAR"),
            qso(call: "W4MOB", band: .m40, mode: .cw, their: "JASP"),
        ]), party: scqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange and scope of credit

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("rich", party: scqp, role: .inState).get().locations,
                       ["RICH"])
        XCTAssertEqual(try ExchangeParser.parse("LEE", party: scqp, role: .inState).get().locations,
                       ["LEE"], "the 3-character code parses alongside the 4-character ones")
        XCTAssertEqual(try ExchangeParser.parse("TX", party: scqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: scqp, role: .inState).get().locations,
                       ["DX"])
        guard case .failure = ExchangeParser.parse("SC", party: scqp, role: .inState) else {
            return XCTFail("SC must be rejected — the rules say to enter the county, not SC")
        }
    }

    /// County-line contacts are permitted; the sponsor mandates only the logging
    /// shape, and caps nothing. Four is this app's own maximum, not a sponsor's
    /// number — open question 1.
    func testCountyLinesAreAllowedWithNoStatedLimit() throws {
        XCTAssertEqual(scqp.maxSimultaneousCounties, 4)
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W4LIN", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_772_290_800)
            ),
            myLocs: ["TX"],
            theirLocs: ["CHAR", "BERK"]
        )
        XCTAssertEqual(rows.count, 2, "'must appear in the log as separate contacts'")
        let s = ScoreEngine.score(log: outLog(rows), party: scqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertTrue(try XCTUnwrap(scqp.openQuestions).contains("county-line limit"))
    }

    /// Rule 9.5, stated as its own numbered rule.
    func testOutOfStateEntrantsGetNoCreditForNonSouthCarolinaContacts() {
        XCTAssertTrue(scqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", their: "RICH"),
            qso(call: "K5B", their: "TX"),
            qso(call: "DL1C", their: "DX"),
        ]), party: scqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 2, "non-SC stations and DX alike")
    }

    // MARK: Schedule — eleven hours, and the only window that crosses a month

    func testScheduleIsOneElevenHourWindowCrossingIntoMarch() throws {
        let windows = try XCTUnwrap(scqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-02-28T15:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-03-01T02:00:00Z"),
                       "printed as 0159Z; the stated '11 hours total' settles it")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 11 * 3600)

        // "the 4th Saturday in February": 28 February 2026.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 28)
        XCTAssertEqual(utc.component(.month, from: windows[0].start), 2)
        XCTAssertEqual(utc.component(.month, from: windows[0].end), 3,
                       "the only bundled party whose window ends in another month")
    }

    func testNotesRecordBothOpenQuestions() throws {
        let notes = try XCTUnwrap(scqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("THE FILENAME LIES"),
                      "the 2024-looking URL for a 2026 document must stay recorded")
        let questions = try XCTUnwrap(scqp.openQuestions)
        XCTAssertTrue(questions.contains("county-line limit"))
        XCTAssertTrue(questions.contains("COUNTS ONCE OR TWICE"),
                      "the additive reading of 9.2.2's numbered list")
    }

    /// The activation multiplier closed this party's only `scoreAffecting`
    /// item, so SCQP no longer warns. What remains is an inference about how
    /// 9.2.2 reads, which is real and auditable and not worth interrupting a
    /// contest for.
    func testThePartyNoLongerRaisesAWarning() {
        XCTAssertEqual(scqp.blockingCaveats, [], "the undercount is fixed, not deferred")
        XCTAssertEqual(scqp.advisoryCaveats.map(\.kind), [.ruleInference])
    }
}

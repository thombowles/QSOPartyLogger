import XCTest
@testable import QSOPartyLogger

/// Nebraska QSO Party — built from the Nebraska QSO Party Committee's own rules,
/// read verbatim 2026-07-26. See docs/research/neqp_rules.md.
///
/// The most feature-rich party of the season: a power multiplier, **seven** bonus
/// stations, a satellite category, and a **second contest inside the first** for
/// FT8/FT4. Three of those cannot be modelled, and each is pinned below.
final class NebraskaQSOPartyTests: XCTestCase {

    var neqp: PartyDefinition!

    override func setUpWithError() throws {
        neqp = try XCTUnwrap(PartyCatalog.party(id: "neqp"), "bundled NEQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W0ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "DGLS"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_125_600 + seq),  // 2026-04-25 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO], power: StationProfile.CategoryPower = .high) -> ContestLog {
        var log = ContestLog(partyID: "neqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "DGLS") -> ContestLog {
        var log = ContestLog(partyID: "neqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties

    func testCountyData() {
        XCTAssertEqual(neqp.counties.count, 93, "Nebraska has 93 counties")
        XCTAssertEqual(Set(neqp.counties.map(\.abbr)).count, 93)
        XCTAssertEqual(Set(neqp.counties.map(\.name)).count, 93)
        XCTAssertEqual(neqp.countyAbbrLengths, [4], "uniformly 4 letters")
    }

    /// **The sponsor misspells one county**: `CUMI` is printed "Cumming" where
    /// Nebraska's is **Cuming**, one *m*. Shipped as printed, so a correction is
    /// noticed rather than absorbed.
    func testTheSponsorsMisspellingShipsAsPrinted() {
        XCTAssertEqual(neqp.county(for: "CUMI")?.name, "Cumming")
    }

    /// `DGLS` is the one code that drops its vowels rather than truncating —
    /// every other four-letter code is a prefix of its county's name.
    func testDouglasDropsItsVowels() {
        XCTAssertEqual(neqp.county(for: "DGLS")?.name, "Douglas")
        XCTAssertNil(neqp.county(for: "DOUG"))
    }

    func testTheThreeWayGroups() {
        for (code, name) in [("CHAS", "Chase"), ("CHER", "Cherry"), ("CHEY", "Cheyenne"),
                             ("DAKO", "Dakota"), ("DAWE", "Dawes"), ("DAWS", "Dawson"),
                             ("FRNK", "Franklin"), ("FRON", "Frontier"), ("FURN", "Furnas")] {
            XCTAssertEqual(neqp.county(for: code)?.name, name)
        }
        XCTAssertEqual(neqp.county(for: "dgls")?.name, "Douglas", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(neqp.cabrilloContest, "NE-QSO-PARTY")
        XCTAssertEqual(neqp.homeState, "NE")
        XCTAssertEqual(neqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertFalse(neqp.exchangeIncludesSerial)
        XCTAssertEqual(neqp.dxStyle, .prefix, "DXCC countries are counted individually")
        XCTAssertTrue(neqp.isPartiallyVerified)
    }

    /// "All **VHF/UHF** bands are allowed. **WARC band contacts do not count**."
    func testTenBandsWithWARCExcluded() {
        XCTAssertEqual(neqp.validBands,
                       [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70])
        for warc in [Band.m30, .m17, .m12] {
            XCTAssertFalse(neqp.validBands.contains(warc))
        }
    }

    /// "Each unique digital contact is **1** points, Phone is worth **2** points,
    /// CW is worth **3** points." Three distinct values, which four bundled
    /// parties have — but Nebraska is **the only one where digital pays less than
    /// phone**. Everywhere else digital ranks above it.
    func testDigitalIsTheCheapestContactWhichIsUniqueHere() throws {
        XCTAssertEqual(neqp.points.points(for: .digital), 1)
        XCTAssertEqual(neqp.points.points(for: .phone), 2)
        XCTAssertEqual(neqp.points.points(for: .cw), 3)

        let cheaperDigital = PartyCatalog.loadBundled().filter {
            $0.allowedModeClasses.contains(.digital)
                && $0.points.points(for: .digital) < $0.points.points(for: .phone)
        }.map(\.id)
        XCTAssertEqual(cheaperDigital, ["neqp"])
    }

    /// "Contacts with the same station on different bands are considered unique,
    /// and … on the same band but with different modes are also considered
    /// unique."
    func testDupeScope() {
        XCTAssertEqual(neqp.dupeScope, .bandMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0NE", band: .m40, mode: .cw, their: "DGLS"),
            qso(call: "W0NE", band: .m40, mode: .phone, their: "DGLS"),
            qso(call: "W0NE", band: .m20, mode: .cw, their: "DGLS"),
            qso(call: "W0NE", band: .m40, mode: .cw, their: "DGLS"),
        ]), party: neqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.qsoPoints, 3 + 2 + 3)
    }

    // MARK: Multipliers and the power multiplier

    /// "Count each Nebraska county, and each S/P/C, **only once per contest**."
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(neqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(neqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", band: .m20, mode: .cw, their: "DGLS"),
            qso(call: "W0A", band: .m40, mode: .cw, their: "DGLS"),
            qso(call: "W0A", band: .m20, mode: .phone, their: "DGLS"),
        ]), party: neqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// "The multiplier for out-of-state stations has a **maximum of 93 counties**."
    func testOutOfStateCeilingIs93() {
        XCTAssertEqual(Set(neqp.multipliers.outState.classes), [.county])
        let rows = neqp.counties.enumerated().map { i, c in qso(call: "W0\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: neqp).multiplierCount, 93)
    }

    /// "**The maximum number of states worked is 50**" — fifty, not forty-nine, so
    /// Nebraska is inside it; and NE stations send counties, so `NE` is never
    /// received. Same arithmetic as New Mexico.
    func testNebraskaCountsAsAStateThroughACounty() {
        XCTAssertTrue(neqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(neqp.validOutStateTokens.contains("NE"))
        let s = ScoreEngine.score(log: inLog([qso(my: "DGLS", their: "CASS")]), party: neqp)
        XCTAssertEqual(s.workedValues(.county), ["CASS"])
        XCTAssertEqual(s.workedValues(.state), ["NE"])
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "…QRP (5 watts or less) the power multiplier is **5**; if less than 100
    /// watts, the multiplier is **2**; otherwise … **1**." Whole numbers, so it
    /// ships — the second party to manage that, after New Mexico, with the
    /// identical 5/2/1 shape.
    func testThePowerMultiplierShipsAndMatchesNewMexicos() throws {
        let mults = try XCTUnwrap(neqp.scoreMultipliers)
        XCTAssertEqual(mults.factor(power: .qrp, station: .fixed), 5)
        XCTAssertEqual(mults.factor(power: .low, station: .fixed), 2)
        XCTAssertEqual(mults.factor(power: .high, station: .fixed), 1)

        let nmqp = try XCTUnwrap(PartyCatalog.party(id: "nmqp"))
        for p in [StationProfile.CategoryPower.qrp, .low, .high] {
            XCTAssertEqual(mults.factor(power: p, station: .fixed),
                           nmqp.scoreMultipliers?.factor(power: p, station: .fixed),
                           "the same 5/2/1 shape as New Mexico's")
        }

        let rows = [qso(call: "W0A", their: "DGLS"), qso(call: "W0B", their: "CASS")]
        let qrp = ScoreEngine.score(log: outLog(rows, power: .qrp), party: neqp)
        let high = ScoreEngine.score(log: outLog(rows, power: .high), party: neqp)
        XCTAssertEqual(qrp.categoryFactor, 5)
        XCTAssertEqual(qrp.total, high.total * 5)
    }

    /// "**Final Score equals (QSO Points x Power Multiplier x Geo Multiplier) plus
    /// Bonus points.**" — the engine's formula, stated by the sponsor.
    func testTheSponsorsScoreFormulaIsTheEngines() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "KA0BOJ", mode: .cw, their: "DGLS"),
            qso(call: "W0B", mode: .phone, their: "CASS"),
        ], power: .low), party: neqp)
        XCTAssertEqual(s.qsoPoints, 3 + 2)
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertEqual(s.categoryFactor, 2)
        XCTAssertEqual(s.bonusPoints, 100)
        XCTAssertEqual(s.total, 5 * 2 * 2 + 100)
    }

    // MARK: The seven bonus stations

    /// "There will be **100 bonus points** for any QSO with Nebraska SM **KAØBOJ**
    /// and **50 bonus points** for all other appointees in the section." Seven
    /// stations, parsed from the sponsor's own table rather than typed. The
    /// slashed zero is typography, not part of the callsign.
    func testSevenSectionAppointeesEachPayABonus() {
        XCTAssertEqual(neqp.bonuses.count, 7)
        XCTAssertEqual(neqp.bonuses.first, .workStation(call: "KA0BOJ", points: 100, scope: .once))
        for call in ["K0SMM", "K0RPT", "K0NEB", "NF0N", "N0FER", "KE0XQ"] {
            XCTAssertTrue(neqp.bonuses.contains(.workStation(call: call, points: 50, scope: .once)),
                          "\(call) should pay 50")
        }
        let all = ScoreEngine.score(log: outLog(
            ["KA0BOJ", "K0SMM", "K0RPT", "K0NEB", "NF0N", "N0FER", "KE0XQ"]
                .map { qso(call: $0, their: "DGLS") }
        ), party: neqp)
        XCTAssertEqual(all.bonusPoints, 100 + 6 * 50)
    }

    /// **OPEN QUESTION 2, pinned.** "100 bonus points for **any** QSO with…" reads
    /// either as *once, if worked at all* or as *for each such QSO*. `.once`
    /// ships as the conservative reading — per-QSO across ten bands and three
    /// modes would dominate the score, which argues the same way.
    func testTheBonusScopeIsOnceAndThatIsAJudgementCall() throws {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "KA0BOJ", band: .m20, mode: .cw, their: "DGLS"),
            qso(call: "KA0BOJ", band: .m40, mode: .cw, their: "CASS"),
            qso(call: "KA0BOJ", band: .m20, mode: .phone, their: "ADMS"),
        ]), party: neqp)
        XCTAssertEqual(s.validQSOs, 3, "each is a valid QSO")
        XCTAssertEqual(s.bonusPoints, 100, "…but the bonus is claimed once")
        XCTAssertTrue(try XCTUnwrap(neqp.notes).contains("OPEN QUESTION 2"))
    }

    // MARK: What is deliberately not modelled

    /// **KNOWN LIMITATION 1, pinned.** The FT8/FT4 competition is a whole second
    /// contest — its own points, its own multiplier class (grid squares), its own
    /// power multiplier, its own log and its own formula. The schema describes one
    /// contest per party, so it has no representation at all.
    func testKnownGapTheFT8CompetitionIsNotModelled() throws {
        let notes = try XCTUnwrap(neqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("WHOLE SECOND CONTEST"))
        // And the exclusion inside the main contest is the Illinois/North Dakota
        // gap again — an FT8 row still scores as digital.
        var ft8 = qso(call: "W0FT", mode: .digital, their: "DGLS")
        ft8.rawMode = "FT8"
        XCTAssertEqual(ScoreEngine.score(log: outLog([ft8]), party: neqp).qsoPoints, 1)
    }

    /// **KNOWN LIMITATION 2, pinned.** Satellite is a fourth mode worth 4 points,
    /// and `ModeClass` has three cases — so a satellite QSO scores whichever mode
    /// it is logged under. First user of that gap.
    func testKnownGapSatelliteQSOsCannotScoreFourPoints() throws {
        var sat = qso(call: "W0SAT", mode: .phone, their: "DGLS")
        sat.rawMode = "SSB SAT"
        XCTAssertEqual(ScoreEngine.score(log: outLog([sat]), party: neqp).qsoPoints, 2,
                       "the sponsor pays 4; the app can only see phone")
        XCTAssertTrue(try XCTUnwrap(neqp.notes).contains("KNOWN LIMITATION 2"))
    }

    /// **KNOWN LIMITATION 3, pinned.** The rare-grid bonus pays on *activating*
    /// DN91CE/DN91DE/DN91EE, and the app has no notion of the operator's grid.
    func testKnownGapTheRareGridBonusIsNotModelled() throws {
        XCTAssertFalse(neqp.bonuses.contains { bonus in
            if case .activatedCountyCount = bonus { return true }
            return false
        }, "nothing is invented for a grid-square rule")
        XCTAssertTrue(try XCTUnwrap(neqp.notes).contains("KNOWN LIMITATION 3"))
    }

    // MARK: Credit, county lines, exchange

    /// "Stations outside of Nebraska to work as many Nebraska stations/counties as
    /// possible. **Stations in Nebraska to work everyone.**"
    func testOutOfStateEntrantsWorkNebraskaOnly() {
        XCTAssertTrue(neqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", their: "DGLS"),
            qso(call: "K5B", their: "TX"),
        ]), party: neqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "…may operate from county lines, but **only two counties at a time**. A
    /// single exchange on the air is ok, but **enter it twice in the log**" —
    /// which is `CountyLineExpander` described from the sponsor's side.
    func testCountyLinesTakeTwoCounties() throws {
        XCTAssertEqual(neqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            try ExchangeParser.parse("DGLS/CASS", party: neqp, role: .inState).get().locations,
            ["DGLS", "CASS"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("DGLS/CASS/ADMS", party: neqp, role: .inState),
            .failure(.tooManyCounties(3))
        )
    }

    func testMobileChangingCountyIsANewStation() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "DGLS"),
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "CASS"),
        ]), party: neqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "**exchange of signal report is optional**" — which no other bundled party
    /// says. The field still ships: having it costs nothing, and hiding it would
    /// lose information the sponsor accepts.
    func testRSTIsOptionalForTheSponsorButTheFieldStillShips() {
        XCTAssertTrue(neqp.exchangeIncludesRST)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("adms", party: neqp, role: .inState).get().locations,
                       ["ADMS"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: neqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: neqp, role: .inState).get().locations,
                       ["DL"], "DXCC countries are prefixes here")
        guard case .failure = ExchangeParser.parse("NE", party: neqp, role: .inState) else {
            return XCTFail("NE must be rejected — Nebraska stations send a county")
        }
    }

    // MARK: Schedule — and the hour the sponsor contradicts itself about

    /// "…start Saturday, April 25th, **1400 UTC** … and end … **0200 UTC**", with
    /// "no scheduled breaks and you can operate the ENTIRE time scheduled".
    /// Thirty-six unbroken hours — joint-longest with Hawaii, behind Vermont's 48.
    func testScheduleIsOneThirtySixHourWindow() throws {
        let windows = try XCTUnwrap(neqp.schedule)
        XCTAssertEqual(windows.count, 1, "no scheduled breaks")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-25T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-27T02:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 36 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 25)
        XCTAssertEqual(utc.component(.day, from: windows[0].end), 27,
                       "the sponsor's own end date — Sunday evening local is Monday in UTC")
    }

    /// **OPEN QUESTION 1, pinned.** April is CDT (UTC−5), so 1400 UTC is 9 AM
    /// local — but the rules gloss it "(8:00 AM CDT)", and gloss the 0200 UTC
    /// finish "(08:00 PM CDT)" where it is 9 PM. Both parentheticals are one hour
    /// off, consistently. WA7BNM trusted the local times and publishes
    /// 1300Z–0100Z; the sponsor's own UTC ships, per Article 19.
    func testTheSponsorsLocalTimesDisagreeWithItsOwnUTCByAnHour() throws {
        var central = Calendar(identifier: .gregorian)
        central.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        let w = try XCTUnwrap(neqp.schedule?.first)

        XCTAssertEqual(central.component(.hour, from: w.start), 9,
                       "1400Z is 9 AM CDT — the rules say 8, which is the CST offset")
        XCTAssertEqual(central.component(.hour, from: w.end), 21,
                       "0200Z is 9 PM CDT — the rules say 8")
        XCTAssertTrue(try XCTUnwrap(neqp.notes).contains("OPEN QUESTION 1"))
    }

    func testNotesRecordBothRetrievalTraps() throws {
        let notes = try XCTUnwrap(neqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("nebraskaqsoparty.ORG IS NOT THE SPONSOR"))
        XCTAssertTrue(notes.contains("URL THAT SAYS 2022"))
        XCTAssertTrue(notes.contains("SPONSOR MISSPELLING SHIPPED AS PRINTED"))
    }
}

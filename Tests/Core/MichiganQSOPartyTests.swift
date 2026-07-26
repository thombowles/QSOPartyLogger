import XCTest
@testable import QSOPartyLogger

/// Michigan QSO Party — built from the Mad River Radio Club's own site, read
/// verbatim 2026-07-26. See docs/research/miqp_rules.md.
///
/// **The live site had already rolled forward to 2027** by the time this was
/// built, so the 2026 rules came from the Wayback Machine and both editions were
/// diffed. Exactly one sentence differs, and a second source settles what it
/// means — see `testTheDistrictOfColumbiaIsAMultiplierInBothEditions`.
final class MichiganQSOPartyTests: XCTestCase {

    var miqp: PartyDefinition!

    override func setUpWithError() throws {
        miqp = try XCTUnwrap(PartyCatalog.party(id: "miqp"), "bundled MiQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K8MQP",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "OAKL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_776_528_000 + seq),  // 2026-04-18 16:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "miqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "OAKL") -> ContestLog {
        var log = ContestLog(partyID: "miqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties

    func testCountyData() {
        XCTAssertEqual(miqp.counties.count, 83, "Michigan has 83 counties")
        XCTAssertEqual(Set(miqp.counties.map(\.abbr)).count, 83)
        XCTAssertEqual(Set(miqp.counties.map(\.name)).count, 83)
    }

    /// Four letters everywhere except Bay, which has only three to work with —
    /// the same shape as Georgia's `LEE`.
    func testBAYIsTheOnlyThreeLetterCode() {
        XCTAssertEqual(miqp.countyAbbrLengths, [3, 4])
        XCTAssertEqual(miqp.counties.filter { $0.abbr.count == 3 }.map(\.abbr), ["BAY"])
        XCTAssertEqual(miqp.county(for: "BAY")?.name, "Bay")
    }

    func testCodesWorthChecking() {
        XCTAssertEqual(miqp.county(for: "OAKL")?.name, "Oakland",
                       "the county in the sponsor's own worked example")
        XCTAssertEqual(miqp.county(for: "WASH")?.name, "Washtenaw",
                       "and the one in its Cabrillo example — not Washington")
        XCTAssertEqual(miqp.county(for: "GRTR")?.name, "Grand Traverse")
        XCTAssertEqual(miqp.county(for: "STCL")?.name, "St Clair",
                       "no full stop — the sponsor prints none")
        XCTAssertEqual(miqp.county(for: "STJO")?.name, "St Joseph")
        XCTAssertEqual(miqp.county(for: "oakl")?.name, "Oakland", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(miqp.cabrilloContest, "MI-QSO-PARTY")
        XCTAssertEqual(miqp.homeState, "MI")
        XCTAssertTrue(miqp.exchangeIncludesRST)
        XCTAssertFalse(miqp.exchangeIncludesSerial,
                       "the exchange changed from a QSO number to RST in 2022")
        XCTAssertEqual(miqp.dxStyle, .token)
        XCTAssertTrue(miqp.bonuses.isEmpty)
        XCTAssertNil(miqp.scoreMultipliers,
                     "power categorises entrants; it does not scale the score")
        XCTAssertTrue(miqp.isPartiallyVerified)
    }

    /// "CW and SSB on **80, 40, 20, 15 and 10 meters**" — five bands and two
    /// modes, the narrowest band list in the app. No 160, no 6, no digital.
    func testFiveBandsAndTwoModesIsTheNarrowestListBundled() {
        XCTAssertEqual(miqp.validBands, [.m80, .m40, .m20, .m15, .m10])
        XCTAssertEqual(miqp.allowedModeClasses, [.phone, .cw])

        let narrowest = PartyCatalog.loadBundled().map(\.validBands.count).min()
        XCTAssertEqual(miqp.validBands.count, narrowest,
                       "no bundled party has fewer bands")
    }

    /// The sponsor works the dupe arithmetic out loud: "K8MQP may be contacted
    /// on each of the (5) bands on each of the (2) modes for a maximum of **(10)
    /// ten QSOs**." So the log below is exactly ten, and an eleventh is a dupe.
    func testTheSponsorsOwnTenQSOMaximum() {
        XCTAssertEqual(miqp.dupeScope, .bandMode)
        var rows: [QSO] = []
        for band in miqp.validBands {
            for mode in [ModeClass.cw, .phone] {
                rows.append(qso(call: "K8MQP", band: band, mode: mode, their: "OAKL"))
            }
        }
        rows.append(qso(call: "K8MQP", band: .m20, mode: .cw, their: "OAKL"))

        let s = ScoreEngine.score(log: outLog(rows), party: miqp)
        XCTAssertEqual(s.validQSOs, 10, "the sponsor's stated maximum, reached exactly")
        XCTAssertEqual(s.dupeCount, 1, "the eleventh")
        XCTAssertEqual(s.qsoPoints, 5 * 2 + 5 * 1, "CW twice, SSB once, on five bands")
    }

    func testPointsByMode() {
        XCTAssertEqual(miqp.points.points(for: .phone), 1)
        XCTAssertEqual(miqp.points.points(for: .cw), 2)
    }

    // MARK: Multipliers

    /// "Multipliers are counted **once per mode**. Working the same multiplier on
    /// both CW and SSB counts as **two multipliers**."
    func testMultipliersCountPerMode() {
        XCTAssertEqual(miqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(miqp.multipliers.outState.countScope, .perMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W8A", band: .m20, mode: .cw, their: "OAKL"),
            qso(call: "W8A", band: .m40, mode: .cw, their: "OAKL"),
            qso(call: "W8A", band: .m20, mode: .phone, their: "OAKL"),
        ]), party: miqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 2, "one Oakland on CW, one on SSB")
    }

    func testOutOfStateCeilingIs83CountiesPerMode() {
        XCTAssertEqual(Set(miqp.multipliers.outState.classes), [.county])
        var rows: [QSO] = []
        for (i, c) in miqp.counties.enumerated() {
            rows.append(qso(call: "W8\(i)", mode: .cw, their: c.abbr))
            rows.append(qso(call: "W8\(i)", mode: .phone, their: c.abbr))
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: miqp).multiplierCount, 166,
                       "83 counties on each of two modes")
    }

    /// **The one sentence that differs between the 2026 and 2027 editions.** The
    /// 2027 rules add "+ 1 District of Columbia" to the Michigan-station list.
    /// It reads like a scoring change and is not one: the rules defer to the
    /// Official List of Mults twice in *both* editions, and the list archived
    /// four days before the 2026 contest already carried DC. So DC ships as a
    /// multiplier, correct for both years.
    func testTheDistrictOfColumbiaIsAMultiplierInBothEditions() throws {
        XCTAssertTrue(miqp.validOutStateTokens.contains("DC"))
        XCTAssertTrue(miqp.stateAliases.isEmpty, "DC is itself, not an alias for Maryland")
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", mode: .cw, my: "OAKL", their: "DC"),
            qso(call: "W3B", mode: .cw, my: "OAKL", their: "MD"),
        ]), party: miqp)
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertTrue(try XCTUnwrap(miqp.notes).contains("EXACTLY ONE SENTENCE DIFFERS"))
    }

    /// "49 American states (**excluding Michigan**)" — Michigan is not a state
    /// multiplier; MI stations count the 83 counties instead. Same shape as
    /// North Dakota one party earlier.
    func testMichiganIsNotAStateMultiplier() throws {
        XCTAssertFalse(miqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(miqp.validOutStateTokens.contains("MI"))
        let s = ScoreEngine.score(log: inLog([qso(mode: .cw, my: "OAKL", their: "WASH")]),
                                  party: miqp)
        XCTAssertEqual(s.workedValues(.county), ["WASH"])
        XCTAssertTrue(s.workedValues(.state).isEmpty, "no phantom MI multiplier")
        XCTAssertEqual(s.multiplierCount, 1)

        let ndqp = try XCTUnwrap(PartyCatalog.party(id: "ndqp"))
        XCTAssertFalse(ndqp.multipliers.inState.homeStateCountsViaCounty, "and so is ND's")
    }

    /// **DX is a real multiplier here** — one per mode, since the exchange is the
    /// literal token. Michigan is therefore *not* another
    /// points-but-no-multiplier party; the contrast with the two built
    /// immediately before it is worth keeping straight.
    func testDXIsARealMultiplierUnlikeGeorgiaAndNorthDakota() throws {
        XCTAssertTrue(miqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", mode: .cw, my: "OAKL", their: "DX"),
            qso(call: "JA1BB", mode: .cw, my: "OAKL", their: "DX"),
            qso(call: "DL1AA", mode: .phone, my: "OAKL", their: "DX"),
        ]), party: miqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        XCTAssertEqual(s.multiplierCount, 2, "one DX on CW and one on SSB — never more")

        for id in ["gaqp", "ndqp"] {
            let other = try XCTUnwrap(PartyCatalog.party(id: id))
            XCTAssertFalse(other.multipliers.inState.classes.contains(.dx),
                           "\(id) pays points for DX and grants no multiplier")
        }
    }

    /// The sponsor lists its thirteen in full, and they **are** the app's
    /// thirteen — unlike North Dakota's, which needed an override. Worth
    /// checking rather than assuming, one party later.
    func testTheProvincesAreTheStandardThirteen() throws {
        XCTAssertEqual(miqp.provinces, MultClass.canadianProvinces)
        XCTAssertEqual(miqp.provinces.count, 13)

        let ndqp = try XCTUnwrap(PartyCatalog.party(id: "ndqp"))
        XCTAssertNotEqual(ndqp.provinces, MultClass.canadianProvinces,
                          "North Dakota's are not — that contrast is the point")
    }

    // MARK: Credit and county lines

    /// "**Non-Michigan stations may work only Michigan stations**, while Michigan
    /// stations may contact anyone."
    func testOutOfStateEntrantsWorkMichiganOnly() {
        XCTAssertTrue(miqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W8A", their: "OAKL"),
            qso(call: "K5B", their: "TX"),
        ]), party: miqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "**No station may claim simultaneous operation in more than one county,
    /// state, or province.**" Michigan forbids the claim itself — stricter than
    /// North Dakota, which permits parking on the line and merely requires
    /// separate contacts.
    func testCountyLinesAreForbiddenOutright() throws {
        XCTAssertEqual(miqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("OAKL/WASH", party: miqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
        XCTAssertEqual(
            try ExchangeParser.parse("OAKL", party: miqp, role: .inState).get().locations,
            ["OAKL"]
        )
    }

    /// "Mobile or Rover stations that change the geographic entity they're
    /// operating from (**counties for Michigan stations, state or province for
    /// others**) are considered to be a new station."
    func testARoverChangingCountyIsANewStation() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W8ROV", band: .m40, mode: .cw, their: "OAKL"),
            qso(call: "W8ROV", band: .m40, mode: .cw, their: "WASH"),
            qso(call: "W8ROV", band: .m40, mode: .cw, their: "OAKL"),
        ]), party: miqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// The sponsor rules on the awkward entities in the exchange itself: Hawaii
    /// and Alaska are W/VE and send their state; the Virgin Islands and Puerto
    /// Rico are not and send "DX".
    func testExchangeParsing() throws {
        for token in ["HI", "AK", "TX", "ON", "DX", "DC"] {
            XCTAssertEqual(
                try ExchangeParser.parse(token, party: miqp, role: .inState).get().locations,
                [token]
            )
        }
        guard case .failure = ExchangeParser.parse("MI", party: miqp, role: .inState) else {
            return XCTFail("MI must be rejected — Michigan stations send a county")
        }
    }

    // MARK: Schedule

    /// "…annually on the **Saturday of the third full weekend in April**… 16Z
    /// Saturday until 04Z Sunday UTC… the full **twelve hours**." The rules name
    /// no year at all, which is why the site rolling over to 2027 left them
    /// intact.
    func testScheduleIsTheSaturdayOfTheThirdFullWeekendInApril() throws {
        let windows = try XCTUnwrap(miqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-18T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-19T04:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 18)

        // Noon to midnight in Detroit, which is what the sponsor actually says.
        var detroit = Calendar(identifier: .gregorian)
        detroit.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Detroit"))
        XCTAssertEqual(detroit.component(.hour, from: windows[0].start), 12)
        XCTAssertEqual(detroit.component(.hour, from: windows[0].end), 0)
    }

    /// The formula, applied independently: April 2026 opens on a Wednesday, so
    /// the first weekend with **both** days in April is the 4th–5th, and the
    /// third is the 18th–19th. Recomputed here rather than asserted, so the
    /// reading is checked and not just the answer.
    func testTheThirdFullWeekendFormulaProducesTheEighteenth() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        func thirdFullWeekendSaturday(ofApril year: Int) throws -> Int {
            var saturdays: [Int] = []
            for day in 1...30 {
                let d = try XCTUnwrap(utc.date(from: DateComponents(
                    year: year, month: 4, day: day, hour: 12)))
                // A "full weekend" needs its Sunday in April too, so a Saturday
                // on the 30th does not qualify.
                if utc.component(.weekday, from: d) == 7, day + 1 <= 30 {
                    saturdays.append(day)
                }
            }
            return saturdays[2]
        }

        XCTAssertEqual(try thirdFullWeekendSaturday(ofApril: 2026), 18)
        XCTAssertEqual(try thirdFullWeekendSaturday(ofApril: 2027), 17,
                       "the sponsor's own site says \"Next MiQP Sat 17 Apr 2027\"")
    }

    func testNotesRecordTheRolloverAndTheDiff() throws {
        let notes = try XCTUnwrap(miqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("THE LIVE SITE HAD ALREADY ROLLED FORWARD TO 2027"))
        XCTAssertTrue(notes.contains("THAT IS A CLARIFICATION, NOT A RULE CHANGE"))
        XCTAssertTrue(notes.contains("NO OPEN QUESTIONS"))
    }
}

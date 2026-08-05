import XCTest
@testable import QSOPartyLogger

/// Ontario QSO Party — built from Contest Club Ontario's own site, read verbatim
/// 2026-07-26. See docs/research/oqp_rules.md.
///
/// **The site rolled forward to 2027 but the rules did not**: the landing page
/// advertises the 30th Annual OQP while `rules.htm` is still headed "2026 Ontario
/// QSO Party Rules (revised 01 March 2026)". Two hours moved from Saturday to
/// Sunday for 2026 and phone doubled from 1 point to 2, so **any pre-2026 source
/// is wrong about both**.
final class OntarioQSOPartyTests: XCTestCase {

    var oqp: PartyDefinition!

    override func setUpWithError() throws {
        oqp = try XCTUnwrap(PartyCatalog.party(id: "oqp"), "bundled OQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "VE3ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "TOR"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_776_535_200 + seq),  // 2026-04-18 18:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "oqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from mult: String = "TOR") -> ContestLog {
        var log = ContestLog(partyID: "oqp")
        log.myLocation = .inState(counties: [mult])
        log.qsos = qsos
        return log
    }

    // MARK: The multiplier list — and it is not all counties

    func testMultiplierData() {
        XCTAssertEqual(oqp.counties.count, 50, "Ontario has 50 multiplier areas")
        XCTAssertEqual(Set(oqp.counties.map(\.abbr)).count, 50)
        XCTAssertEqual(Set(oqp.counties.map(\.name)).count, 50)
        XCTAssertEqual(oqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// **`HAL` is the Town of Haldimand, not Halton** — two adjacent
    /// southern-Ontario entities, and the obvious abbreviation belongs to the
    /// smaller one. Halton is `HTN`.
    func testHALIsHaldimandAndHaltonIsHTN() {
        XCTAssertEqual(oqp.county(for: "HAL")?.name, "Town of Haldimand")
        XCTAssertEqual(oqp.county(for: "HTN")?.name, "Halton Regional Municipality")
    }

    /// A county and the city inside it are both multipliers in their own right,
    /// and three unrelated places share a `PE?` prefix.
    func testOtherConfusableCodes() {
        XCTAssertEqual(oqp.county(for: "BRA")?.name, "Brant County")
        XCTAssertEqual(oqp.county(for: "BFD")?.name, "City of Brantford")
        XCTAssertEqual(oqp.county(for: "PED")?.name, "City of Prince Edward")
        XCTAssertEqual(oqp.county(for: "PEL")?.name, "Peel Regional Municipality")
        XCTAssertEqual(oqp.county(for: "PER")?.name, "Perth County")
        XCTAssertEqual(oqp.county(for: "NOR")?.name, "Northumberland County")
        XCTAssertEqual(oqp.county(for: "NFK")?.name, "Town of Norfolk")
        XCTAssertEqual(oqp.county(for: "MAN")?.name, "Manitoulin District",
                       "not Manitoba, which is the province token MB")
        XCTAssertEqual(oqp.county(for: "tor")?.name, "City of Toronto", "case-insensitive")
    }

    /// The sponsor explains why the list is not 50 counties: "A number of former
    /// counties (e.g. Brant) have recently become 'single tier municipalities',
    /// so are now listed as cities or towns." Six kinds of entity, all present.
    func testTheListMixesSixKindsOfEntity() {
        let names = oqp.counties.map(\.name)
        for kind in ["County", "District", "City of", "Town of",
                     "Regional Municipality", "United Counties"] {
            XCTAssertTrue(names.contains { $0.contains(kind) }, "expected some \(kind)")
        }
        XCTAssertEqual(oqp.county(for: "SDG")?.name,
                       "United Counties of Stormont, Dundas & Glengarry",
                       "three counties, one multiplier")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(oqp.cabrilloContest, "ON-QSO-PARTY")
        XCTAssertEqual(oqp.homeState, "ON")
        XCTAssertEqual(oqp.allowedModeClasses, [.phone, .cw])
        XCTAssertTrue(oqp.exchangeIncludesRST)
        XCTAssertFalse(oqp.exchangeIncludesSerial)
        XCTAssertNil(oqp.scoreMultipliers, "power categorises; it does not scale")
        XCTAssertTrue(oqp.isPartiallyVerified)
    }

    /// "All Bands **160-2 meters** with the exception of the **WARC bands**."
    func testEightBands() {
        XCTAssertEqual(oqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for warc in [Band.m30, .m17, .m12] {
            XCTAssertFalse(oqp.validBands.contains(warc))
        }
        XCTAssertFalse(oqp.validBands.contains(.m60), "OPEN QUESTION 1 — see the notes")
    }

    /// "Score **2 QSO points** for each station worked on phone per band. Score
    /// **2 QSO points** for each station worked on CW per band." Phone doubled
    /// from 1 point for 2026, so a 2025 source gets this wrong.
    func testFlatTwoPointsBothModes() {
        XCTAssertEqual(oqp.points.points(for: .phone), 2)
        XCTAssertEqual(oqp.points.points(for: .cw), 2)
    }

    /// "You may work a station **TWICE per band: once on phone and once on CW**."
    func testTwicePerBand() {
        XCTAssertEqual(oqp.dupeScope, .bandMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VE3A", band: .m40, mode: .cw, their: "TOR"),
            qso(call: "VE3A", band: .m40, mode: .phone, their: "TOR"),
            qso(call: "VE3A", band: .m40, mode: .cw, their: "TOR"),
        ]), party: oqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.qsoPoints, 4)
    }

    // MARK: Multipliers — per band, not per mode

    /// "Stations claim 1 multiplier point for each Ontario county worked **on
    /// each band**." The band is the axis; the mode is not — even though a
    /// station is worked twice per band.
    func testMultipliersCountPerBandAndNotPerMode() {
        XCTAssertEqual(oqp.multipliers.inState.countScope, .perBand)
        XCTAssertEqual(oqp.multipliers.outState.countScope, .perBand)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VE3A", band: .m20, mode: .cw, their: "TOR"),
            qso(call: "VE3A", band: .m20, mode: .phone, their: "TOR"),
            qso(call: "VE3B", band: .m40, mode: .cw, their: "TOR"),
        ]), party: oqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 2,
                       "Toronto on 20 m and Toronto on 40 m — the two modes do not split")
    }

    func testOutOfStateCeilingIsFiftyPerBand() {
        XCTAssertEqual(Set(oqp.multipliers.outState.classes), [.county])
        var rows: [QSO] = []
        for (i, c) in oqp.counties.enumerated() {
            rows.append(qso(call: "VE3\(i)", band: .m20, their: c.abbr))
            rows.append(qso(call: "VE3\(i)", band: .m40, their: c.abbr))
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: oqp).multiplierCount, 100,
                       "fifty multiplier areas on each of two bands")
    }

    /// Ontario stations claim the 50 areas directly, and `ON` is not among the
    /// provinces they count.
    func testOntarioClaimsItsOwnAreasAndIsNotAProvinceMultiplier() {
        XCTAssertFalse(oqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertEqual(oqp.provinces.count, 12)
        XCTAssertFalse(oqp.provinces.contains("ON"))
        XCTAssertEqual(MultClass.canadianProvinces.subtracting(oqp.provinces), ["ON"])

        let s = ScoreEngine.score(log: inLog([qso(my: "TOR", their: "HAL")]), party: oqp)
        XCTAssertEqual(s.workedValues(.county), ["HAL"])
        XCTAssertTrue(s.workedValues(.province).isEmpty)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// "…each Canadian province/territory, U.S. state (**plus District of
    /// Columbia**) and DXCC country worked on each band."
    func testInStateClassesIncludeStatesProvincesAndDX() throws {
        XCTAssertEqual(Set(oqp.multipliers.inState.classes), [.county, .state, .province, .dx])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", my: "TOR", their: "MA"),
            qso(call: "W3B", my: "TOR", their: "DC"),
            qso(call: "VE1C", my: "TOR", their: "NS"),
            qso(call: "VE3D", my: "TOR", their: "OTT"),
        ]), party: oqp)
        XCTAssertEqual(s.multiplierCount, 4)
    }

    /// The sponsor counts DXCC countries individually, so `prefix` ships and
    /// each entity is its own multiplier — and it also says that when an
    /// Ontario station logs one, "the abbreviation 'DX' is also acceptable".
    /// Both now hold: the literal token used to be rejected because prefix
    /// mode had no way to admit it, and it is loggable again.
    func testDXCCCountriesCountIndividuallyAndTheLiteralDXIsLoggable() throws {
        XCTAssertEqual(oqp.dxStyle, .prefix)
        XCTAssertTrue(ExchangeParser.acceptsDXPrefix(party: oqp, role: .inState))

        XCTAssertTrue(oqp.multipliers.inState.dxCountsEntities)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", band: .m20, my: "TOR", their: "DL"),
            qso(call: "JA1BB", band: .m20, my: "TOR", their: "JA"),
        ]), party: oqp)
        XCTAssertEqual(s.multiplierCount, 2, "two entities, two multipliers")
        XCTAssertEqual(Set(s.workedValues(.dx)), ["DL", "JA"],
                       "labelled by the prefix worked, not by the entity name")

        // Two prefixes of one entity are one multiplier — the whole point of
        // counting entities rather than tokens.
        let sameEntity = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", band: .m20, my: "TOR", their: "DL"),
            qso(call: "DJ2BB", band: .m20, my: "TOR", their: "DJ"),
        ]), party: oqp)
        XCTAssertEqual(sameEntity.workedValues(.dx), ["DL"])
        XCTAssertEqual(sameEntity.multiplierCount, 1, "DL and DJ are both Germany")

        XCTAssertTrue(oqp.acceptsDXToken)
        XCTAssertEqual(
            try ExchangeParser.parse("DX", party: oqp, role: .inState).get().locations,
            ["DX"],
            "the rules call the literal DX acceptable, so it must log"
        )

        // North Dakota used to be the mirror image — it kept DX and lost the
        // prefix. Both parties get both forms now.
        let ndqp = try XCTUnwrap(PartyCatalog.party(id: "ndqp"))
        XCTAssertEqual(ndqp.dxStyle, .prefix)
        XCTAssertTrue(ndqp.acceptsDXToken)
        XCTAssertEqual(
            try ExchangeParser.parse("DX", party: ndqp, role: .inState).get().locations, ["DX"])
    }

    /// **KNOWN LIMITATION 1, pinned.** The sponsor pays **10 QSO points** for
    /// working five club stations, and QSO points sit *inside* the
    /// multiplication. The nearest schema shape adds to `bonusPoints`, which the
    /// engine applies *after* it — so nothing ships for these five and their
    /// QSOs score the ordinary 2 points. A wrong number that looks deliberate is
    /// harder to notice than a missing one.
    func testKnownGapTheTenPointClubStationsAreNotModelled() throws {
        for call in ["VA3CCO", "VE3CCO", "VE3ODX", "VA3RAC", "VE3RHQ"] {
            let s = ScoreEngine.score(log: outLog([qso(call: call, their: "TOR")]), party: oqp)
            XCTAssertEqual(s.qsoPoints, 2, "\(call) scores the ordinary two points")
            XCTAssertEqual(s.bonusPoints, 0, "…and nothing is invented for it")
        }
        XCTAssertFalse(oqp.bonuses.contains { bonus in
            if case .workStation = bonus { return true }
            return false
        }, "modelling these as a bonus would place the points after multiplication")
        XCTAssertTrue(try XCTUnwrap(oqp.notes).contains("KNOWN LIMITATION 1"))
    }

    // MARK: Bonus, credit, county lines

    /// "Mobile/Rover stations add **300 bonus points for each Ontario multiplier
    /// activated**", needing at least three contacts from the area.
    func testMobileActivationBonus() throws {
        XCTAssertEqual(oqp.bonuses, [.activatedCountyCount(minQSOs: 3, points: 300)])

        func rows(_ area: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in qso(call: "W\(area)\(i)", my: area, their: "TX") }
        }
        var log = inLog(rows("TOR", 3) + rows("OTT", 2))
        log.station.categoryStation = .mobile
        log.myLocation = .inState(counties: ["TOR"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: oqp).bonusPoints, 300,
                       "three qualifies, two does not")
    }

    /// **KNOWN LIMITATION 3, pinned.** The sponsor wants "three contacts with
    /// **three different stations**"; the schema counts three QSOs, which three
    /// bands' worth of one station satisfies. Bounded at 300 points per area.
    func testKnownGapThreeQSOsWithOneStationStillEarnsTheBonus() throws {
        var log = inLog([
            qso(call: "W1SAME", band: .m20, my: "TOR", their: "TX"),
            qso(call: "W1SAME", band: .m40, my: "TOR", their: "TX"),
            qso(call: "W1SAME", band: .m80, my: "TOR", their: "TX"),
        ])
        log.station.categoryStation = .mobile
        log.myLocation = .inState(counties: ["TOR"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: oqp).bonusPoints, 300,
                       "the sponsor would want three different stations")
        XCTAssertTrue(try XCTUnwrap(oqp.notes).contains("KNOWN LIMITATION 2"))
    }

    /// "Ontario stations work everyone. **Non-Ontario stations work Ontario
    /// stations only.**"
    func testOutOfOntarioEntrantsWorkOntarioOnly() {
        XCTAssertTrue(oqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VE3A", their: "TOR"),
            qso(call: "K5B", their: "TX"),
        ]), party: oqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "…**(within 250m of a county line)**, a separate QSO and complete exchange
    /// must be made and logged for each county worked." The 250-metre definition
    /// is new for 2026.
    func testEachCountyNeedsItsOwnQSO() {
        XCTAssertEqual(oqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("TOR/YRK", party: oqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
    }

    func testMobileChangingAreaIsANewStation() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VE3MOB", band: .m40, their: "TOR"),
            qso(call: "VE3MOB", band: .m40, their: "YRK"),
        ]), party: oqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Schedule

    /// "**For 2026, the contest periods are 1800Z April 18 to 0300Z April 19, and
    /// 1200Z to 2000Z April 19.**" Two hours moved from Saturday night to Sunday
    /// for 2026 — the 2025 legs ended 0500Z and 1800Z.
    func testScheduleIsTwoLegsTotallingSeventeenHours() throws {
        let windows = try XCTUnwrap(oqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-18T18:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-19T03:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-04-19T12:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-04-19T20:00:00Z"))

        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 9 * 3600)
        XCTAssertEqual(windows[1].end.timeIntervalSince(windows[1].start), 8 * 3600)
        XCTAssertEqual(
            windows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, 17 * 3600)

        // Not the 2025 shape, which a stale source would produce.
        XCTAssertNotEqual(windows[0].end, f.date(from: "2026-04-19T05:00:00Z"),
                          "two hours moved off Saturday night for 2026")
        XCTAssertNotEqual(windows[1].end, f.date(from: "2026-04-19T18:00:00Z"),
                          "…and onto Sunday")
    }

    /// Ontario shares the third full weekend of April with Michigan, whose rules
    /// phrase the formula identically.
    func testItSharesItsWeekendWithMichigan() throws {
        let miqp = try XCTUnwrap(PartyCatalog.party(id: "miqp"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let mine = try XCTUnwrap(oqp.schedule?.first?.start)
        let theirs = try XCTUnwrap(miqp.schedule?.first?.start)
        XCTAssertTrue(utc.isDate(mine, inSameDayAs: theirs), "both open on 18 April")
        XCTAssertEqual(utc.component(.day, from: mine), 18)
    }

    /// **The hub calls it ONQP, not OQP.** `oqp-table.php` 404s. The party id
    /// follows the sponsor, which calls itself OQP throughout; the URL follows
    /// the hub — California already proved the prefix is not derivable from the
    /// id, and this is the second party where they differ.
    func testTheHubServesItUnderADifferentPrefix() throws {
        let hub = try XCTUnwrap(oqp.hubSpots, "the hub does serve Ontario")
        XCTAssertEqual(hub.tableURL, "http://qsopartyhub.com/onqp-table.php")
        XCTAssertEqual(hub.postURL, "http://qsopartyhub.com/onqp-spots.php")
        XCTAssertFalse(hub.tableURL.contains("/oqp-"), "that URL 404s")
    }

    func testNotesRecordTheEditionSplitAndAllThreeLimitations() throws {
        let notes = try XCTUnwrap(oqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("THE SITE ROLLED FORWARD TO 2027 BUT THE RULES DID NOT"))
        XCTAssertTrue(notes.contains("PRE-2026 SOURCE IS WRONG"))
        for n in ["KNOWN LIMITATION 1", "KNOWN LIMITATION 2"] {
            XCTAssertTrue(notes.contains(n), n)
        }
        XCTAssertFalse(notes.contains("KNOWN LIMITATION 3"),
                       "the literal-DX limitation closed and the rest renumbered")
        XCTAssertTrue(notes.contains("BOTH DX FORMS THE SPONSOR NAMES NOW WORK"))
        XCTAssertTrue(notes.contains("OPEN QUESTION 1"))
    }
}

import XCTest
@testable import QSOPartyLogger

/// Florida QSO Party — built from the Florida Contest Group's own site, read
/// verbatim 2026-07-26. See docs/research/fqp_rules.md.
///
/// **Everything here is first-party, including the Cabrillo header** — the first
/// time in six parties — and that header is `FCG-FQP`, not the `FL-QSO-PARTY`
/// the pattern would suggest.
final class FloridaQSOPartyTests: XCTestCase {

    var fqp: PartyDefinition!

    override func setUpWithError() throws {
        fqp = try XCTUnwrap(PartyCatalog.party(id: "fqp"), "bundled FQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K4ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "POL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_132_800 + seq),  // 2026-04-25 16:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO], power: StationProfile.CategoryPower = .high) -> ContestLog {
        var log = ContestLog(partyID: "fqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "POL") -> ContestLog {
        var log = ContestLog(partyID: "fqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties

    func testCountyData() {
        XCTAssertEqual(fqp.counties.count, 67, "Florida has 67 counties")
        XCTAssertEqual(Set(fqp.counties.map(\.abbr)).count, 67)
        XCTAssertEqual(Set(fqp.counties.map(\.name)).count, 67)
        XCTAssertEqual(fqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// **The sponsor flags its own trap**, which no other sponsor this run does:
    /// "Pay attention to 'MIAMI-DADE' COUNTY as the abbreviation is **DAD**."
    func testDADIsMiamiDade() {
        XCTAssertEqual(fqp.county(for: "DAD")?.name, "Miami-Dade")
        XCTAssertNil(fqp.county(for: "MIA"))
        XCTAssertNil(fqp.county(for: "DADE"))
    }

    /// `BAY` and `LEE` are their own codes — both names are already three
    /// letters. A parser that collapses repeated lines loses exactly these two,
    /// which is how they were nearly lost here.
    func testBAYAndLEEAreTheirOwnCodes() {
        XCTAssertEqual(fqp.county(for: "BAY")?.name, "Bay")
        XCTAssertEqual(fqp.county(for: "LEE")?.name, "Lee")
    }

    /// Four codes that are not simple truncations — `CLR` and `CLM` would both
    /// truncate to `COL`.
    func testTheCodesThatAreNotTruncations() {
        XCTAssertEqual(fqp.county(for: "CAH")?.name, "Calhoun")
        XCTAssertEqual(fqp.county(for: "CLR")?.name, "Collier")
        XCTAssertEqual(fqp.county(for: "CLM")?.name, "Columbia")
        XCTAssertEqual(fqp.county(for: "IDR")?.name, "Indian River")
        XCTAssertEqual(fqp.county(for: "MTE")?.name, "Manatee")
        XCTAssertEqual(fqp.county(for: "MAO")?.name, "Marion")
        XCTAssertEqual(fqp.county(for: "pol")?.name, "Polk", "case-insensitive")
    }

    // MARK: Shape

    /// **`FCG-FQP`, printed by the sponsor in its own Cabrillo specification** —
    /// not the `FL-QSO-PARTY` that every other party's pattern would suggest, and
    /// the first party in six needing no Article 1 exception for its header.
    func testTheCabrilloHeaderIsFirstPartyAndNotTheObviousGuess() {
        XCTAssertEqual(fqp.cabrilloContest, "FCG-FQP")
        XCTAssertNotEqual(fqp.cabrilloContest, "FL-QSO-PARTY")
    }

    func testPartyShape() {
        XCTAssertEqual(fqp.homeState, "FL")
        XCTAssertEqual(fqp.allowedModeClasses, [.phone, .cw])
        XCTAssertTrue(fqp.exchangeIncludesRST)
        XCTAssertFalse(fqp.exchangeIncludesSerial)
        XCTAssertEqual(fqp.dxStyle, .prefix, "\"DX operators send DXCC prefix\"")
        XCTAssertTrue(fqp.bonuses.isEmpty)
        XCTAssertTrue(fqp.isPartiallyVerified)
    }

    /// "**No 160 or 80 meters, WARC or VHF bands**" — four bands, fewer than any
    /// other bundled party. The sponsor's own arithmetic fixes the count:
    /// "worked once per mode per band for a total of **8 maximum QSOs**".
    func testFourBandsIsTheNarrowestListBundled() {
        XCTAssertEqual(fqp.validBands, [.m40, .m20, .m15, .m10])
        XCTAssertFalse(fqp.validBands.contains(.m160))
        XCTAssertFalse(fqp.validBands.contains(.m80))
        XCTAssertFalse(fqp.validBands.contains(.m6))

        let narrowest = PartyCatalog.loadBundled()
            .sorted { ($0.validBands.count, $1.id) < ($1.validBands.count, $0.id) }
            .prefix(2).map { "\($0.id) \($0.validBands.count)" }
        XCTAssertEqual(Array(narrowest.prefix(1)), ["fqp 4"])
        XCTAssertEqual(narrowest.count, 2, "and the runner-up has more")
    }

    /// The sponsor's stated maximum, reached exactly: four bands × two modes.
    func testTheSponsorsEightQSOMaximum() {
        XCTAssertEqual(fqp.dupeScope, .bandMode)
        var rows: [QSO] = []
        for band in fqp.validBands {
            for mode in [ModeClass.cw, .phone] {
                rows.append(qso(call: "K4FL", band: band, mode: mode, their: "POL"))
            }
        }
        rows.append(qso(call: "K4FL", band: .m20, mode: .cw, their: "POL"))

        let s = ScoreEngine.score(log: outLog(rows), party: fqp)
        XCTAssertEqual(s.validQSOs, 8, "the sponsor's stated maximum")
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.qsoPoints, 4 * 2 + 4 * 1)
    }

    func testPointsByMode() {
        XCTAssertEqual(fqp.points.points(for: .phone), 1)
        XCTAssertEqual(fqp.points.points(for: .cw), 2)
    }

    // MARK: Multipliers

    /// "A multiplier is counted **once per mode**, regardless of the number of
    /// bands on which it is worked."
    func testMultipliersCountPerMode() {
        XCTAssertEqual(fqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(fqp.multipliers.outState.countScope, .perMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4A", band: .m20, mode: .cw, their: "POL"),
            qso(call: "K4A", band: .m40, mode: .cw, their: "POL"),
            qso(call: "K4A", band: .m20, mode: .phone, their: "POL"),
        ]), party: fqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 2, "Polk on CW and on phone — bands do not split")
    }

    func testOutOfStateCeilingIs67PerMode() {
        XCTAssertEqual(Set(fqp.multipliers.outState.classes), [.county])
        var rows: [QSO] = []
        for (i, c) in fqp.counties.enumerated() {
            rows.append(qso(call: "K4\(i)", mode: .cw, their: c.abbr))
            rows.append(qso(call: "K4\(i)", mode: .phone, their: c.abbr))
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: fqp).multiplierCount, 134,
                       "67 counties on each of two modes")
    }

    /// "**There is no in-state County multiplier.**" A Florida entrant gets
    /// nothing for working the other 66 counties — the mirror of North Dakota,
    /// where in-state entrants count *only* their own counties.
    func testFloridaEntrantsGetNoCountyMultipliers() throws {
        XCTAssertFalse(fqp.multipliers.inState.classes.contains(.county))
        XCTAssertEqual(Set(fqp.multipliers.inState.classes), [.state, .province, .dx])

        let s = ScoreEngine.score(log: inLog([
            qso(call: "K4A", my: "POL", their: "DAD"),
            qso(call: "K4B", my: "POL", their: "BAY"),
        ]), party: fqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.workedValues(.county), [], "no county credit at all in-state")

        let ndqp = try XCTUnwrap(PartyCatalog.party(id: "ndqp"))
        XCTAssertTrue(ndqp.multipliers.inState.classes.contains(.county),
                      "North Dakota is the mirror image")
    }

    /// "50 States (**including Florida**)" — fifty, not forty-nine, so Florida is
    /// inside it; and Florida stations send counties, which the sponsor insists
    /// on: "Don't log the exchange as FL."
    func testFloridaCountsAsAStateThroughACounty() {
        XCTAssertTrue(fqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(fqp.validOutStateTokens.contains("FL"))
        let s = ScoreEngine.score(log: inLog([qso(my: "POL", their: "DAD")]), party: fqp)
        XCTAssertEqual(s.workedValues(.state), ["FL"])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// "…5 watts or less, use a Power Multiplier of **3** … less than 100 watts
    /// … **2** … more than 100 watts … **no** Power Multiplier." Whole numbers,
    /// so it ships — the third party to manage that.
    func testThePowerMultiplierShips() throws {
        let mults = try XCTUnwrap(fqp.scoreMultipliers)
        XCTAssertEqual(mults.factor(power: .qrp, station: .fixed), 3)
        XCTAssertEqual(mults.factor(power: .low, station: .fixed), 2)
        XCTAssertEqual(mults.factor(power: .high, station: .fixed), 1)

        let rows = [qso(call: "K4A", their: "POL"), qso(call: "K4B", their: "DAD")]
        let qrp = ScoreEngine.score(log: outLog(rows, power: .qrp), party: fqp)
        XCTAssertEqual(qrp.categoryFactor, 3)
        XCTAssertEqual(qrp.total, ScoreEngine.score(log: outLog(rows), party: fqp).total * 3)

        let withPower = PartyCatalog.loadBundled().filter { $0.scoreMultipliers != nil }
            .map(\.id).sorted()
        XCTAssertTrue(withPower.contains("fqp"))
        XCTAssertTrue(withPower.contains("nmqp") && withPower.contains("neqp"))
    }

    // MARK: The Spelling Bee

    /// "20 special 1×1 stations whose suffixes spell **US BIRTHDAY**" — the second
    /// party to use `oneByOne`, after Kansas. **The word is 2026-only**: it marks
    /// the USA's 250th, so a 2027 session must replace it.
    func testTheSpellingBeeWordShipsAndIs2026Only() throws {
        let config = try XCTUnwrap(fqp.oneByOne)
        XCTAssertEqual(config.words, ["USBIRTHDAY"])
        XCTAssertNil(config.wildcard, "Kansas has one; Florida does not")
        XCTAssertEqual(config.words[0].count, 10,
                       "ten suffix letters, two stations each, twenty in all")
        XCTAssertTrue(try XCTUnwrap(fqp.notes).contains("2026-ONLY"))

        let ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        XCTAssertNotNil(ksqp.oneByOne, "the only other user of this field")
    }

    // MARK: Credit, county lines, exchange

    /// **OPEN QUESTION 1, pinned.** The Object is asymmetric — non-Florida
    /// amateurs are directed at Florida stations while "Florida operators can
    /// work anyone" — but no sentence forbids a non-Florida station claiming a
    /// non-Florida contact. `true` ships as the reading every FQP summary takes.
    func testOutOfStateEntrantsWorkFloridaOnly() throws {
        XCTAssertTrue(fqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4A", their: "POL"),
            qso(call: "K5B", their: "TX"),
        ]), party: fqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
        XCTAssertTrue(try XCTUnwrap(fqp.notes).contains("OPEN QUESTION 1"))
    }

    /// "Florida stations on a county line (**maximum of two counties**) may be
    /// claimed as a separate QSO and multiplier from each county."
    func testCountyLinesTakeTwo() throws {
        XCTAssertEqual(fqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            try ExchangeParser.parse("POL/DAD", party: fqp, role: .inState).get().locations,
            ["POL", "DAD"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("POL/DAD/BAY", party: fqp, role: .inState),
            .failure(.tooManyCounties(3))
        )
    }

    func testMobileChangingCountyIsANewStation() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4MOB", band: .m40, mode: .cw, their: "POL"),
            qso(call: "K4MOB", band: .m40, mode: .cw, their: "DAD"),
        ]), party: fqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("bay", party: fqp, role: .inState).get().locations,
                       ["BAY"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: fqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: fqp, role: .inState).get().locations,
                       ["DL"], "DXCC prefixes, stated outright")
        guard case .failure = ExchangeParser.parse("FL", party: fqp, role: .inState) else {
            return XCTFail("\"Don't log the exchange as FL\" — the sponsor's own words")
        }
    }

    /// **KNOWN LIMITATION 1, pinned.** The rules give maritime-mobile stations
    /// their own exchange — "send ITU Region (1, 2 or 3)" — and make R1, R2 and
    /// R3 multipliers for Florida entrants. `MultClass` has no region class, so
    /// `MultClass` has no region class — and **they do not merely fail to
    /// count**. Because `dxStyle` is `.prefix`, `R1` is a *plausible DXCC
    /// prefix* — 1–5 alphanumerics containing a letter, matching no county,
    /// state or province — so it parses and is credited as a **DX country**
    /// instead. Same shape as the Mississippi grid-square finding: the QSO
    /// scores and the exchange logs, only the class is wrong, and since both
    /// count once per mode the total lands right by accident.
    func testKnownGapMaritimeMobileRegionsAreCreditedAsDXCountries() throws {
        XCTAssertEqual(
            try ExchangeParser.parse("R1", party: fqp, role: .inState).get().locations,
            ["R1"], "it parses — as a phantom DXCC prefix")

        let s = ScoreEngine.score(log: inLog([
            qso(call: "K4MM1", my: "POL", their: "R1"),
            qso(call: "K4MM2", my: "POL", their: "R2"),
            qso(call: "K4MM3", my: "POL", their: "R3"),
        ]), party: fqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(Set(s.workedValues(.dx)), ["R1", "R2", "R3"],
                       "three multipliers, but filed under DX rather than region")
        XCTAssertEqual(s.multiplierCount, 3, "…the right count for the wrong reason")

        XCTAssertTrue(try XCTUnwrap(fqp.notes).contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(try XCTUnwrap(fqp.notes).contains("MARITIME MOBILE ITU REGIONS"))
    }

    /// **The hub calls it FLQP, not FQP** — `fqp-table.php` 404s. The party id
    /// follows the sponsor; the URL follows the hub. Third party where they
    /// differ, after California and Ontario.
    func testTheHubServesItUnderADifferentPrefix() throws {
        let hub = try XCTUnwrap(fqp.hubSpots)
        XCTAssertEqual(hub.tableURL, "http://qsopartyhub.com/flqp-table.php")
        XCTAssertFalse(hub.tableURL.contains("/fqp-"), "that URL 404s")
    }

    // MARK: Schedule

    /// "Saturday **16:00:00Z** (Noon EDT) – Sunday **01:59:59Z**… Sunday
    /// **12:00:00Z** (8 AM EDT) – **21:59:59Z**", two 10-hour legs separated by a
    /// 10-hour break.
    func testScheduleIsTwoTenHourLegsWithATenHourBreak() throws {
        let windows = try XCTUnwrap(fqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-25T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-26T02:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-04-26T12:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-04-26T22:00:00Z"))

        for w in windows {
            XCTAssertEqual(w.end.timeIntervalSince(w.start), 10 * 3600)
        }
        XCTAssertEqual(windows[1].start.timeIntervalSince(windows[0].end), 10 * 3600,
                       "\"separated by a 10-hour break period\"")
    }

    /// **All four of the sponsor's local-time glosses convert correctly** — worth
    /// asserting after Nebraska, where none of them did.
    func testEveryLocalTimeGlossCheckesOut() throws {
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let w = try XCTUnwrap(fqp.schedule)
        XCTAssertEqual(eastern.component(.hour, from: w[0].start), 12, "Noon EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[0].end), 22, "10 PM EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[1].start), 8, "8 AM EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[1].end), 18, "6 PM EDT")
    }

    func testNotesRecordTheFirstPartyCabrilloAndTheGap() throws {
        let notes = try XCTUnwrap(fqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("NOT THE OBVIOUS ONE"))
        XCTAssertTrue(notes.contains("NO COUNTY MULTIPLIERS AT ALL"))
    }
}

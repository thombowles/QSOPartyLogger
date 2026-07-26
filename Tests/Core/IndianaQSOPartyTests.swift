import XCTest
@testable import QSOPartyLogger

/// Indiana QSO Party — built from the Hoosier DX and Contest Club's own rules,
/// read verbatim 2026-07-26. See docs/research/inqp_rules.md.
///
/// **QSO points changed for 2026** — flat 2 for both modes, where phone used to
/// be worth one — and the old wording is *still in the page* as an HTML comment.
final class IndianaQSOPartyTests: XCTestCase {

    var inqp: PartyDefinition!

    override func setUpWithError() throws {
        inqp = try XCTUnwrap(PartyCatalog.party(id: "inqp"), "bundled INQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W9ABC", band: Band = .m20, mode: ModeClass = .cw,
        my: String = "TX", their: String = "INMRN"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_734_000 + seq),  // 2026-05-02 15:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "inqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "INMRN") -> ContestLog {
        var log = ContestLog(partyID: "inqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties

    func testCountyData() {
        XCTAssertEqual(inqp.counties.count, 92, "Indiana has 92 counties")
        XCTAssertEqual(Set(inqp.counties.map(\.abbr)).count, 92)
        XCTAssertEqual(inqp.countyAbbrLengths, [5], "IN + three letters")
        XCTAssertTrue(inqp.counties.allSatisfy { $0.abbr.hasPrefix("IN") })
    }

    /// The exchange is a **5-character state+county code** — the same shape as
    /// 7QP's — but Indiana is a single state, so no county carries one and the
    /// multi-state schema stays untouched.
    func testTheCodeIsFiveCharactersButThePartyIsSingleState() throws {
        XCTAssertEqual(inqp.homeStates, ["IN"])
        XCTAssertTrue(inqp.counties.allSatisfy { $0.state == nil })
        XCTAssertEqual(inqp.state(forCounty: "INMRN"), "IN")

        let sevenqp = try XCTUnwrap(PartyCatalog.party(id: "sevenqp"))
        XCTAssertEqual(sevenqp.countyAbbrLengths, [5], "the same code shape…")
        XCTAssertEqual(sevenqp.homeStates.count, 8, "…for a very different reason")
    }

    /// "…an Indiana station in Marion county would send **59 INMRN**" — and
    /// `INMAR`, the naive truncation, does not exist.
    func testMarionIsINMRNNotINMAR() {
        XCTAssertEqual(inqp.county(for: "INMRN")?.name, "Marion")
        XCTAssertNil(inqp.county(for: "INMAR"))
        XCTAssertEqual(inqp.county(for: "inmrn")?.name, "Marion", "case-insensitive")
    }

    func testOtherCodes() {
        XCTAssertEqual(inqp.county(for: "INADA")?.name, "Adams")
        XCTAssertEqual(inqp.county(for: "INALL")?.name, "Allen")
        XCTAssertEqual(inqp.county(for: "INBAR")?.name, "Bartholomew")
        XCTAssertEqual(inqp.county(for: "INHAN")?.name, "Hancock")
        XCTAssertEqual(inqp.county(for: "INHAR")?.name, "Harrison")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(inqp.cabrilloContest, "IN-QSO-PARTY")
        XCTAssertEqual(inqp.homeState, "IN")
        XCTAssertEqual(inqp.allowedModeClasses, [.phone, .cw])
        XCTAssertEqual(inqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10])
        XCTAssertTrue(inqp.exchangeIncludesRST)
        XCTAssertTrue(inqp.bonuses.isEmpty)
        XCTAssertNil(inqp.scoreMultipliers)
        XCTAssertTrue(inqp.isPartiallyVerified)
    }

    /// **"Count two points for each complete two-way QSO (both CW and Phone) —
    /// Rule change for 2026."** Phone used to be worth one. A 2025 source, or a
    /// scraper that reads the page's own HTML comment, gets this wrong.
    func testFlatTwoPointsIsTheTwentyTwentySixRule() {
        XCTAssertEqual(inqp.points.points(for: .phone), 2)
        XCTAssertEqual(inqp.points.points(for: .cw), 2)
        XCTAssertNotEqual(inqp.points.points(for: .phone), 1, "the pre-2026 value")
    }

    /// "The same fixed station could theoretically be worked **twelve times**" —
    /// six bands × two modes, the sponsor's own arithmetic.
    func testTheSponsorsTwelveQSOMaximum() {
        XCTAssertEqual(inqp.dupeScope, .bandMode)
        var rows: [QSO] = []
        for band in inqp.validBands {
            for mode in [ModeClass.cw, .phone] {
                rows.append(qso(call: "W9IN", band: band, mode: mode, their: "INMRN"))
            }
        }
        rows.append(qso(call: "W9IN", band: .m20, mode: .cw, their: "INMRN"))
        let s = ScoreEngine.score(log: outLog(rows), party: inqp)
        XCTAssertEqual(s.validQSOs, 12, "the sponsor's stated maximum")
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.qsoPoints, 24, "flat two points, twelve times")
    }

    // MARK: Multipliers

    /// "Multipliers count **once per mode** (i.e. once on CW and once on phone)."
    func testMultipliersCountPerMode() {
        XCTAssertEqual(inqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(inqp.multipliers.outState.countScope, .perMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9A", band: .m20, mode: .cw, their: "INMRN"),
            qso(call: "W9A", band: .m40, mode: .cw, their: "INMRN"),
            qso(call: "W9A", band: .m20, mode: .phone, their: "INMRN"),
        ]), party: inqp)
        XCTAssertEqual(s.multiplierCount, 2, "Marion on CW and on phone")
    }

    func testOutOfStateCeilingIs92PerMode() {
        XCTAssertEqual(Set(inqp.multipliers.outState.classes), [.county])
        var rows: [QSO] = []
        for (i, c) in inqp.counties.enumerated() {
            rows.append(qso(call: "W9\(i)", mode: .cw, their: c.abbr))
            rows.append(qso(call: "W9\(i)", mode: .phone, their: c.abbr))
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: inqp).multiplierCount, 184)
    }

    /// "**The other 49 U.S. states**" — Indiana is not among them, and Indiana
    /// entrants count the 92 counties themselves instead.
    func testIndianaIsNotAStateMultiplierAndCountsItsOwnCounties() {
        XCTAssertFalse(inqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertEqual(Set(inqp.multipliers.inState.classes), [.county, .state, .province])
        XCTAssertFalse(inqp.validOutStateTokens.contains("IN"))
        let s = ScoreEngine.score(log: inLog([qso(my: "INMRN", their: "INADA")]), party: inqp)
        XCTAssertEqual(s.workedValues(.county), ["INADA"])
        XCTAssertTrue(s.workedValues(.state).isEmpty, "no phantom IN multiplier")
    }

    /// "(**District of Columbia counts as Maryland**.)"
    func testDCCountsAsMaryland() {
        XCTAssertEqual(inqp.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", mode: .cw, my: "INMRN", their: "DC"),
            qso(call: "W3B", mode: .cw, my: "INMRN", their: "MD"),
        ]), party: inqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "one multiplier, not two")
    }

    /// "Indiana stations may work DX stations for **QSO point credit, but there
    /// are no DX multipliers**." The third party with that shape, after Georgia
    /// and North Dakota.
    func testDXPaysPointsAndNoMultiplier() throws {
        XCTAssertFalse(inqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", my: "INMRN", their: "DX"),
            qso(call: "JA1BB", my: "INMRN", their: "DX"),
        ]), party: inqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 4)
        XCTAssertEqual(s.multiplierCount, 0)

        let others = ["gaqp", "ndqp"].compactMap { PartyCatalog.party(id: $0) }
        XCTAssertEqual(others.count, 2)
        XCTAssertTrue(others.allSatisfy { !$0.multipliers.inState.classes.contains(.dx) })
    }

    // MARK: Credit, county lines, schedule

    /// "**Non-Indiana stations may work only Indiana stations.**"
    func testOutOfStateEntrantsWorkIndianaOnly() {
        XCTAssertTrue(inqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9A", their: "INMRN"),
            qso(call: "K5B", their: "TX"),
        ]), party: inqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "…may operate from only **one or two counties at a time**. In other words,
    /// **three and four county operations are not allowed**." The sponsor spells
    /// out the refusal, which few do.
    func testCountyLinesTakeTwoAndThreeIsRefusedByName() throws {
        XCTAssertEqual(inqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            try ExchangeParser.parse("INMRN/INADA", party: inqp, role: .inState).get().locations,
            ["INMRN", "INADA"])
        XCTAssertEqual(
            ExchangeParser.parse("INMRN/INADA/INALL", party: inqp, role: .inState),
            .failure(.tooManyCounties(3)))
    }

    /// "Contest starts at **1500 UTC** Saturday and ends at **0259 UTC** Sunday…
    /// (Saturday **11am to 11pm EDT or 10am to 10pm CDT**.)" Indiana straddles
    /// two zones and the sponsor gives both; both convert correctly.
    func testScheduleIsTwelveHoursAndBothZonesCheckOut() throws {
        let w = try XCTUnwrap(inqp.schedule)
        XCTAssertEqual(w.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(w[0].start, f.date(from: "2026-05-02T15:00:00Z"))
        XCTAssertEqual(w[0].end, f.date(from: "2026-05-03T03:00:00Z"))
        XCTAssertEqual(w[0].end.timeIntervalSince(w[0].start), 12 * 3600)

        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Indiana/Indianapolis"))
        XCTAssertEqual(eastern.component(.hour, from: w[0].start), 11, "11 AM EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[0].end), 23, "11 PM EDT")

        var central = Calendar(identifier: .gregorian)
        central.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(central.component(.hour, from: w[0].start), 10, "10 AM CDT")
        XCTAssertEqual(central.component(.hour, from: w[0].end), 22, "10 PM CDT")
    }

    /// Indiana shares 2 May with the 7th Call Area and Delaware.
    func testItSharesItsSaturdayWithTheSeventhCallArea() throws {
        let sevenqp = try XCTUnwrap(PartyCatalog.party(id: "sevenqp"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let mine = try XCTUnwrap(inqp.schedule?.first?.start)
        XCTAssertTrue(utc.isDate(mine, inSameDayAs: try XCTUnwrap(sevenqp.schedule?.first?.start)))
    }

    /// **The hub does not serve Indiana** — `inqp-table.php` 302-redirects to a
    /// login page, exactly as 7QP's does.
    func testThereIsNoHubSource() {
        XCTAssertNil(inqp.hubSpots)
    }

    func testNotesRecordTheRuleChangeAndTheCommentTrap() throws {
        let notes = try XCTUnwrap(inqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("QSO POINTS CHANGED FOR 2026"))
        XCTAssertTrue(notes.contains("STILL IN THE PAGE AS AN HTML COMMENT"))
        XCTAssertTrue(notes.contains("ABBREVIATIONS CHANGED IN 2017"))
    }
}

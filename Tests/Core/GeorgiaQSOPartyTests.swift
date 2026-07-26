import XCTest
@testable import QSOPartyLogger

/// Georgia QSO Party — built from the sponsor's own site (gaqsoparty.com), read
/// verbatim 2026-07-26. See docs/research/gaqp_rules.md.
///
/// **159 counties — the third-largest list in the app**, behind the 7th Call
/// Area's 259 (eight states' worth) and Texas's 254. The sponsor states its own multiplier ceilings —
/// 128 and 318 — and both are arithmetic that checks the county count and the
/// class lists at once.
final class GeorgiaQSOPartyTests: XCTestCase {

    var gaqp: PartyDefinition!

    override func setUpWithError() throws {
        gaqp = try XCTUnwrap(PartyCatalog.party(id: "gaqp"), "bundled GQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W4ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "FULT"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_775_930_400 + seq),  // 2026-04-11 18:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "gaqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "FULT") -> ContestLog {
        var log = ContestLog(partyID: "gaqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties — 159, the largest list bundled

    func testCountyData() {
        XCTAssertEqual(gaqp.counties.count, 159, "Georgia has 159 counties")
        XCTAssertEqual(Set(gaqp.counties.map(\.abbr)).count, 159)
        XCTAssertEqual(Set(gaqp.counties.map(\.name)).count, 159)
    }

    /// Georgia's is the third-largest list bundled — behind the 7th Call Area's
    /// 259, which is eight states' worth, and Texas's 254. Pinned as a ranking
    /// rather than a superlative, which is what caught 7QP overtaking it.
    func testGeorgiaHasTheThirdLargestCountyListBundled() {
        // Combined entries are unions of several parties' lists, so they are
        // not counted here - the ranking is about a single sponsor's counties.
        let ranked = PartyCatalog.loadBundled()
            .filter { $0.combines.isEmpty }
            .sorted { ($0.counties.count, $1.id) > ($1.counties.count, $0.id) }
            .prefix(4)
            .map { "\($0.id) \($0.counties.count)" }
        XCTAssertEqual(Array(ranked), ["sevenqp 259", "tqp 254", "gaqp 159", "vaqp 133"])
    }

    /// **`CHAT` is Chattahoochee, not Chatham.** Four counties begin "Cha", and
    /// the obvious code belongs to the one nobody would guess — Chatham, which
    /// contains Savannah, is `CHTM`. This is New Mexico's `SAN` trap again.
    func testCHATIsChattahoocheeAndChathamIsCHTM() {
        XCTAssertEqual(gaqp.county(for: "CHAT")?.name, "Chattahoochee")
        XCTAssertEqual(gaqp.county(for: "CHTM")?.name, "Chatham")
        XCTAssertEqual(gaqp.county(for: "CHGA")?.name, "Chattooga")
        XCTAssertEqual(gaqp.county(for: "CHAR")?.name, "Charlton")
    }

    /// The only three-way group, separated by a single fourth letter — and
    /// `HARR` is the county in the sponsor's own county-line example.
    func testTheThreeWayHarGroup() {
        XCTAssertEqual(gaqp.county(for: "HARA")?.name, "Haralson")
        XCTAssertEqual(gaqp.county(for: "HARR")?.name, "Harris")
        XCTAssertEqual(gaqp.county(for: "HART")?.name, "Hart")
    }

    func testOtherCodesWorthChecking() {
        XCTAssertEqual(gaqp.county(for: "JEFF")?.name, "Jefferson")
        XCTAssertEqual(gaqp.county(for: "JFDA")?.name, "Jeff Davis",
                       "two counties named for a Jefferson, and they do not collide")
        XCTAssertEqual(gaqp.county(for: "MCDU")?.name, "McDuffie")
        XCTAssertEqual(gaqp.county(for: "MCIN")?.name, "McIntosh")
        XCTAssertEqual(gaqp.county(for: "COLQ")?.name, "Colquitt")
        XCTAssertEqual(gaqp.county(for: "COLU")?.name, "Columbia")
        XCTAssertEqual(gaqp.county(for: "fult")?.name, "Fulton", "case-insensitive")
    }

    /// Every code is four letters except Lee, which has only three to work with.
    func testLEEIsTheOnlyThreeLetterCode() {
        XCTAssertEqual(gaqp.countyAbbrLengths, [3, 4])
        XCTAssertEqual(gaqp.counties.filter { $0.abbr.count == 3 }.map(\.abbr), ["LEE"])
        XCTAssertEqual(gaqp.county(for: "LEE")?.name, "Lee")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(gaqp.cabrilloContest, "GA-QSO-PARTY",
                       "printed by the sponsor in a spec written for logging-program authors")
        XCTAssertEqual(gaqp.homeState, "GA")
        XCTAssertTrue(gaqp.exchangeIncludesRST)
        XCTAssertFalse(gaqp.exchangeIncludesSerial)
        XCTAssertEqual(gaqp.dxStyle, .token, "the rules name the literal token: send \"DX\"")
        XCTAssertTrue(gaqp.bonuses.isEmpty, "no bonus rule anywhere in the rules")
        XCTAssertNil(gaqp.scoreMultipliers,
                     "\"Multiply total QSO points by total multipliers\" — a bare product")
        XCTAssertTrue(gaqp.isPartiallyVerified)
    }

    /// "NOTE: Digital contacts aren't allowed in the Georgia QSO Party."
    func testDigitalIsNotALegalMode() {
        XCTAssertEqual(gaqp.allowedModeClasses, [.phone, .cw])
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", mode: .cw, their: "FULT"),
            qso(call: "W4B", mode: .digital, their: "CHTM"),
        ]), party: gaqp)
        XCTAssertEqual(s.validQSOs, 1, "the FT8 row is not a contest QSO at all")
        XCTAssertEqual(s.multiplierCount, 1, "…and yields no multiplier")
    }

    func testPointsByMode() {
        XCTAssertEqual(gaqp.points.points(for: .phone), 1)
        XCTAssertEqual(gaqp.points.points(for: .cw), 2)
    }

    func testSevenBands() {
        XCTAssertEqual(gaqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6])
    }

    // MARK: The scope asymmetry — the rule most likely to be got wrong

    /// "Stations may be worked **once per band and mode** for QSO Points… Each
    /// multiplier may be counted **once per mode. (Not per band.)**" The
    /// parenthesis is the sponsor's; it exists because this trips people up.
    func testQSOCreditIsPerBandAndModeButMultiplierCreditIsPerModeOnly() {
        XCTAssertEqual(gaqp.dupeScope, .bandMode)
        XCTAssertEqual(gaqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(gaqp.multipliers.outState.countScope, .perMode)

        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", band: .m20, mode: .cw, their: "FULT"),
            qso(call: "W4A", band: .m40, mode: .cw, their: "FULT"),
            qso(call: "W4A", band: .m15, mode: .cw, their: "FULT"),
            qso(call: "W4A", band: .m20, mode: .phone, their: "FULT"),
        ]), party: gaqp)
        XCTAssertEqual(s.dupeCount, 0, "four different band/mode pairs, four QSOs")
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.qsoPoints, 2 + 2 + 2 + 1)
        XCTAssertEqual(s.multiplierCount, 2,
                       "one Fulton on CW and one on SSB — the three bands do not multiply")
    }

    // MARK: The sponsor's own ceilings

    /// "**318 possible multipliers.** (once on CW and once on SSB)" — 159 × 2.
    func testOutOfStateCeilingIs318() {
        XCTAssertEqual(Set(gaqp.multipliers.outState.classes), [.county])
        var rows: [QSO] = []
        for (i, c) in gaqp.counties.enumerated() {
            rows.append(qso(call: "W4\(i)", mode: .cw, their: c.abbr))
            rows.append(qso(call: "W4\(i)", mode: .phone, their: c.abbr))
        }
        let s = ScoreEngine.score(log: outLog(rows), party: gaqp)
        XCTAssertEqual(s.validQSOs, 318)
        XCTAssertEqual(s.multiplierCount, 318, "the sponsor's stated ceiling, reached exactly")
    }

    /// "Each USA State and DC, including Georgia (51) · Each Canadian Province
    /// (13) · **128 possible multipliers.**" — (51 + 13) × 2.
    func testInStateCeilingIs128() {
        XCTAssertEqual(Set(gaqp.multipliers.inState.classes), [.state, .province])
        var rows: [QSO] = []
        var tokens = Array(gaqp.validOutStateTokens).sorted()
        tokens.append(contentsOf: gaqp.provinces.sorted())
        for (i, t) in tokens.enumerated() {
            rows.append(qso(call: "W\(i)AA", mode: .cw, my: "FULT", their: t))
            rows.append(qso(call: "W\(i)AA", mode: .phone, my: "FULT", their: t))
        }
        // …plus Georgia itself, which only ever arrives as a county.
        rows.append(qso(call: "W4GA", mode: .cw, my: "FULT", their: "CHTM"))
        rows.append(qso(call: "W4GA", mode: .phone, my: "FULT", their: "CHTM"))

        let s = ScoreEngine.score(log: inLog(rows), party: gaqp)
        XCTAssertEqual(s.multiplierCount, 128, "the sponsor's stated ceiling, reached exactly")
    }

    /// "including Georgia (51)" — fifty-one is 50 states plus DC, so Georgia is
    /// inside it; and Georgia stations send a county, so `GA` is never received.
    func testGeorgiaCountsAsAStateThroughACounty() {
        XCTAssertTrue(gaqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(gaqp.validOutStateTokens.contains("GA"))
        let s = ScoreEngine.score(log: inLog([qso(my: "FULT", their: "CHTM")]), party: gaqp)
        XCTAssertEqual(s.workedValues(.state), ["GA"])
        XCTAssertEqual(s.multiplierCount, 1, "the county itself is not a multiplier in-state")
    }

    /// **DC is its own multiplier here, not an alias.** 51 = 50 states + DC —
    /// the exact opposite of New Mexico's DC→MD one party earlier, and the
    /// arithmetic is the only thing that distinguishes the two.
    func testDCIsItsOwnMultiplierAndNotAliasedToMaryland() throws {
        XCTAssertTrue(gaqp.stateAliases.isEmpty)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", mode: .cw, my: "FULT", their: "DC"),
            qso(call: "W3B", mode: .cw, my: "FULT", their: "MD"),
        ]), party: gaqp)
        XCTAssertEqual(s.multiplierCount, 2, "two multipliers, not one")

        let nmqp = try XCTUnwrap(PartyCatalog.party(id: "nmqp"))
        XCTAssertEqual(nmqp.stateAliases, ["DC": "MD"], "the contrast is deliberate")
    }

    /// "**DX counts for QSO points only, there are no country multipliers.**"
    /// One of two bundled parties that pay points for a class they grant no
    /// multiplier for — North Dakota, the same weekend, is the other. Modelled
    /// by omitting `dx` from the in-state classes,
    /// since the engine scores every in-scope row and consults `classes` for
    /// multipliers alone.
    func testDXPaysPointsAndNoMultiplier() {
        XCTAssertFalse(gaqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", mode: .cw, my: "FULT", their: "DX"),
            qso(call: "JA1BB", mode: .cw, my: "FULT", their: "DX"),
        ]), party: gaqp)
        XCTAssertEqual(s.validQSOs, 2, "both are contest QSOs")
        XCTAssertEqual(s.qsoPoints, 4, "…and both pay two points on CW")
        XCTAssertTrue(s.workedValues(.dx).isEmpty, "…and neither is a multiplier")
        XCTAssertEqual(s.multiplierCount, 0)
    }

    // MARK: Out-of-state credit

    /// "Stations outside Georgia may not count contacts with non-Georgia or DX
    /// stations", and, in the Objective, "Amateurs INSIDE the state of Georgia
    /// can make contacts with everyone."
    func testOutOfStateEntrantsWorkGeorgiaOnly() {
        XCTAssertTrue(gaqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", their: "FULT"),
            qso(call: "K5B", their: "TX"),
            qso(call: "DL1AA", their: "DX"),
        ]), party: gaqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 2, "the Texan and the DX station both")
    }

    // MARK: Rovers and county lines

    /// "GEORGIA ROVER stations may be worked once per county, per mode, per band
    /// for QSO Points… Rovers that move to a new county can work everyone again."
    func testARoverChangingCountyIsANewQSOAndANewMultiplier() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "KU8E", band: .m40, mode: .cw, their: "HARR"),
            qso(call: "KU8E", band: .m40, mode: .cw, their: "MUSC"),
            qso(call: "KU8E", band: .m40, mode: .cw, their: "HARR"),
        ]), party: gaqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.dupeCount, 1, "back to Harris on the same band and mode")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// **OPEN QUESTION 2.** The sponsor states no maximum — it defers to MARAC's
    /// county-hunter rules and its own example shows two (`KU8E/HARR/MUSC`). The
    /// schema default of 4 ships, because refusing a legal exchange mid-contest
    /// is the worse failure. Pinned so a later reading of the rules is a visible
    /// change.
    func testCountyLinesUseTheSchemaDefaultOfFour() throws {
        XCTAssertEqual(gaqp.maxSimultaneousCounties, 4)
        XCTAssertEqual(
            try ExchangeParser.parse("HARR/MUSC", party: gaqp, role: .inState).get().locations,
            ["HARR", "MUSC"],
            "the sponsor's own worked example"
        )
        XCTAssertEqual(gaqp.county(for: "MUSC")?.name, "Muscogee")
        XCTAssertTrue(try XCTUnwrap(gaqp.notes).contains("OPEN QUESTION 2"))
    }

    // MARK: Exchange

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("fult", party: gaqp, role: .inState).get().locations,
                       ["FULT"])
        XCTAssertEqual(try ExchangeParser.parse("LEE", party: gaqp, role: .inState).get().locations,
                       ["LEE"], "the one three-letter code")
        XCTAssertEqual(try ExchangeParser.parse("TX", party: gaqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: gaqp, role: .inState).get().locations,
                       ["DC"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: gaqp, role: .inState).get().locations,
                       ["DX"])
        guard case .failure = ExchangeParser.parse("GA", party: gaqp, role: .inState) else {
            return XCTFail("GA must be rejected — Georgia stations send a county")
        }
    }

    // MARK: Schedule

    /// "…the 2nd full weekend of April. There are two operating periods: 1800Z
    /// Saturday until 0359Z and Sunday and 1400Z to 2359Z", with the home page
    /// stating outright that "The 2026 Dates were April 11th – April 12th."
    func testScheduleIsTwoTenHourLegs() throws {
        let windows = try XCTUnwrap(gaqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-11T18:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-12T04:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-04-12T14:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-04-13T00:00:00Z"))

        for w in windows {
            XCTAssertEqual(w.end.timeIntervalSince(w.start), 10 * 3600, "each leg is 10 hours")
        }
        XCTAssertEqual(
            windows.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, 20 * 3600,
            "the home page's \"two 10 hour periods\""
        )

        // The second *full* weekend: April 2026 opens on a Wednesday, so the
        // first full weekend is the 4th–5th and this one is the 11th–12th.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 11)
        XCTAssertEqual(utc.component(.day, from: windows[1].start), 12)
    }

    /// Four parties share 11 April 2026 — the busiest Saturday of the season.
    /// Georgia starts four hours after Missouri and New Mexico, and at the same
    /// minute as North Dakota.
    func testGeorgiaSharesItsSaturdayWithThreeOtherParties() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let opening = try XCTUnwrap(gaqp.schedule?.first?.start)

        let sameDay = PartyCatalog.loadBundled().filter { party in
            party.schedule?.contains { utc.isDate($0.start, inSameDayAs: opening) } == true
        }.map(\.id).sorted()
        XCTAssertEqual(sameDay, ["gaqp", "moqp", "ndqp", "nmqp"])
    }

    func testNotesRecordBothOpenQuestions() throws {
        let notes = try XCTUnwrap(gaqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("OPEN QUESTION 1: THE BAND LIST IS INFERRED"))
        XCTAssertTrue(notes.contains("OPEN QUESTION 2: NO STATED MAXIMUM"))
        XCTAssertTrue(notes.contains("DIGITAL IS NOT A LEGAL MODE"))
    }
}

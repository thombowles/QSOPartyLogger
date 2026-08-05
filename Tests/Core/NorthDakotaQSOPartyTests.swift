import XCTest
@testable import QSOPartyLogger

/// North Dakota QSO Party — built from the ARRL North Dakota Section's own
/// "2026 ND QSO Party Rules" (Last-Modified 2026-03-06), read verbatim
/// 2026-07-26. See docs/research/ndqp_rules.md.
///
/// The thing that sets it apart is the **Canadian list, which is not the
/// standard thirteen**: `NF` and `LB` in place of `NL`, and no Nunavut — the
/// pre-2001 RAC nomenclature, which needs a `provinces` override.
final class NorthDakotaQSOPartyTests: XCTestCase {

    var ndqp: PartyDefinition!

    override func setUpWithError() throws {
        ndqp = try XCTUnwrap(PartyCatalog.party(id: "ndqp"), "bundled NDQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W0ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "CSS"
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
        var log = ContestLog(partyID: "ndqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "CSS") -> ContestLog {
        var log = ContestLog(partyID: "ndqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties

    func testCountyData() {
        XCTAssertEqual(ndqp.counties.count, 53, "North Dakota has 53 counties")
        XCTAssertEqual(Set(ndqp.counties.map(\.abbr)).count, 53)
        XCTAssertEqual(Set(ndqp.counties.map(\.name)).count, 53)
        XCTAssertEqual(ndqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// Four `Mc` counties separated by a single third letter, and every one is
    /// real — a parser that dropped one would still leave a plausible list.
    func testTheFourMcCounties() {
        XCTAssertEqual(ndqp.county(for: "MCH")?.name, "McHenry")
        XCTAssertEqual(ndqp.county(for: "MCI")?.name, "McIntosh")
        XCTAssertEqual(ndqp.county(for: "MCK")?.name, "McKenzie")
        XCTAssertEqual(ndqp.county(for: "MCL")?.name, "McLean")
    }

    /// The two-word names, which is where the PDF's inconsistent separator does
    /// the most damage — the sponsor prints "Golden Valley CountyGNV" with no
    /// separator at all.
    func testTwoWordCountyNamesSurvivedTheParse() {
        XCTAssertEqual(ndqp.county(for: "GNV")?.name, "Golden Valley")
        XCTAssertEqual(ndqp.county(for: "GFK")?.name, "Grand Forks")
        XCTAssertEqual(ndqp.county(for: "LMR")?.name, "La Moure",
                       "the sponsor's spelling; the county spells itself LaMoure")
        XCTAssertEqual(ndqp.county(for: "css")?.name, "Cass", "case-insensitive")
    }

    // MARK: The Canadian list — not the standard thirteen

    /// "Canadian Abbreviations (13) … **LB Labrador** … **NF Newfoundland** …" —
    /// thirteen tokens, but not the app's thirteen. This is pre-2001 RAC
    /// nomenclature: Newfoundland and Labrador are two, and Nunavut does not
    /// exist yet.
    func testTheProvinceOverrideSplitsNewfoundlandAndHasNoNunavut() {
        XCTAssertEqual(ndqp.provinces.count, 13)
        XCTAssertTrue(ndqp.provinces.contains("NF"))
        XCTAssertTrue(ndqp.provinces.contains("LB"))
        XCTAssertFalse(ndqp.provinces.contains("NL"), "the sponsor splits it in two")
        XCTAssertFalse(ndqp.provinces.contains("NU"), "the sponsor's list predates Nunavut")

        XCTAssertEqual(ndqp.provinces.subtracting(MultClass.canadianProvinces), ["NF", "LB"])
        XCTAssertEqual(MultClass.canadianProvinces.subtracting(ndqp.provinces), ["NL", "NU"])
    }

    /// The override has to reach the parser, not just the definition: `LB` must
    /// be loggable and `NU` must not.
    func testTheOverrideIsWhatTheExchangeParserUses() throws {
        XCTAssertEqual(try ExchangeParser.parse("LB", party: ndqp, role: .inState).get().locations,
                       ["LB"])
        XCTAssertEqual(try ExchangeParser.parse("NF", party: ndqp, role: .inState).get().locations,
                       ["NF"])
        for rejected in ["NL", "NU"] {
            guard case .failure = ExchangeParser.parse(rejected, party: ndqp, role: .inState) else {
                return XCTFail("\(rejected) is not on the sponsor's list")
            }
        }
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(ndqp.cabrilloContest, "ND-QSO-PARTY")
        XCTAssertEqual(ndqp.homeState, "ND")
        XCTAssertEqual(ndqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertTrue(ndqp.exchangeIncludesRST)
        XCTAssertFalse(ndqp.exchangeIncludesSerial)
        XCTAssertTrue(ndqp.bonuses.isEmpty)
        XCTAssertNil(ndqp.scoreMultipliers,
                     "\"There are no power limitations in this contest\"")
        XCTAssertTrue(ndqp.isPartiallyVerified)
    }

    func testEightBandsWithWARCExcluded() {
        XCTAssertEqual(ndqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for excluded in [Band.m60, .m30, .m17, .m12] {
            XCTAssertFalse(ndqp.validBands.contains(excluded), "\(excluded.rawValue) is WARC")
        }
    }

    /// "All contacts count as **1 point** per non-duplicated phone, CW or
    /// Digital contact on each band" — said twice, and flat across every mode,
    /// which is unusual in a season where CW normally pays double.
    func testFlatOnePointForEveryMode() throws {
        XCTAssertEqual(ndqp.points.points(for: .phone), 1)
        XCTAssertEqual(ndqp.points.points(for: .cw), 1)
        XCTAssertEqual(ndqp.points.points(for: .digital), 1)

        // Georgia, the party immediately before it on the same weekend, pays
        // double for CW — the contrast is what makes this worth pinning.
        let gaqp = try XCTUnwrap(PartyCatalog.party(id: "gaqp"))
        XCTAssertEqual(gaqp.points.points(for: .cw), 2)
    }

    /// "You are allowed to make a Phone, CW and a Digital contact with the same
    /// station on the same band in each mode."
    func testTheSameStationOnOneBandInThreeModes() {
        XCTAssertEqual(ndqp.dupeScope, .bandMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0ND", band: .m40, mode: .phone, their: "CSS"),
            qso(call: "W0ND", band: .m40, mode: .cw, their: "CSS"),
            qso(call: "W0ND", band: .m40, mode: .digital, their: "CSS"),
            qso(call: "W0ND", band: .m40, mode: .cw, their: "CSS"),
        ]), party: ndqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.dupeCount, 1, "the second CW contact is the dupe")
        XCTAssertEqual(s.qsoPoints, 3)
    }

    // MARK: Multipliers — and the sponsor's arithmetic

    /// "**Multipliers count once overall, not once per band or mode**" — both
    /// alternatives named and refused in one sentence.
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(ndqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(ndqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", band: .m20, mode: .cw, their: "CSS"),
            qso(call: "W0A", band: .m40, mode: .cw, their: "CSS"),
            qso(call: "W0A", band: .m20, mode: .phone, their: "CSS"),
        ]), party: ndqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfStateCeilingIs53Counties() {
        XCTAssertEqual(Set(ndqp.multipliers.outState.classes), [.county])
        let rows = ndqp.counties.enumerated().map { i, c in qso(call: "W0\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: ndqp).multiplierCount, 53)
    }

    /// "…**49 states excluding North Dakota** + DC, + 10 Canadian provinces + 3
    /// Canadian Territories = **63** … **116 Total Multipliers**". North Dakota
    /// is not a state multiplier at all — an ND station counts its own counties
    /// instead, which is why the ceiling is 116 rather than 63.
    func testInStateCeilingIs116AndNorthDakotaIsNotAStateMultiplier() {
        XCTAssertFalse(ndqp.multipliers.inState.homeStateCountsViaCounty,
                       "\"49 states excluding North Dakota\"")
        XCTAssertEqual(Set(ndqp.multipliers.inState.classes), [.county, .state, .province])
        XCTAssertEqual(ndqp.validOutStateTokens.subtracting(["DX"]).count, 63,
                       "49 states + DC + the sponsor's 13 Canadians")

        var rows: [QSO] = []
        for (i, t) in ndqp.validOutStateTokens.subtracting(["DX"]).sorted().enumerated() {
            rows.append(qso(call: "W\(i)AA", my: "CSS", their: t))
        }
        for (i, c) in ndqp.counties.enumerated() {
            rows.append(qso(call: "W0N\(i)", my: "CSS", their: c.abbr))
        }
        let s = ScoreEngine.score(log: inLog(rows), party: ndqp)
        XCTAssertEqual(s.multiplierCount, 116, "the sponsor's stated total, reached exactly")
        XCTAssertTrue(s.workedValues(.state).isEmpty || !s.workedValues(.state).contains("ND"))
    }

    /// "North Dakota stations may work DXCC countries **for points only — no
    /// multipliers**." The second party in a row with that shape, after Georgia
    /// one day earlier on the calendar.
    func testDXPaysPointsAndNoMultiplier() throws {
        XCTAssertFalse(ndqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", my: "CSS", their: "DX"),
            qso(call: "JA1BB", my: "CSS", their: "DX"),
        ]), party: ndqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 0)

        let gaqp = try XCTUnwrap(PartyCatalog.party(id: "gaqp"))
        XCTAssertFalse(gaqp.multipliers.inState.classes.contains(.dx), "Georgia does the same")
    }

    /// **KNOWN LIMITATION 1, pinned.** The rules ask for the DX *country* in the
    /// log, but `ExchangeParser` guesses at DXCC prefixes only where DX is a
    /// multiplier class — a deliberate gate, since the guess is loose enough to
    /// validate every mistyped county. North Dakota grants DX no multipliers, so
    /// `prefix` would be inert *and* would drop the literal `DX` token, leaving
    /// no way to log the contact at all. `token` is strictly better; the score
    /// is unaffected either way.
    func testAnNDStationCanLogTheCountryPrefixTheRulesAskFor() throws {
        XCTAssertEqual(ndqp.dxStyle, .prefix)
        XCTAssertTrue(ExchangeParser.acceptsDXPrefix(party: ndqp, role: .inState))
        XCTAssertEqual(try ExchangeParser.parse("DL", party: ndqp, role: .inState).get().locations,
                       ["DL"], "the country the rules ask for")

        // And the literal token stays, for a country the operator did not catch.
        XCTAssertTrue(ndqp.acceptsDXToken)
        XCTAssertEqual(try ExchangeParser.parse("DX", party: ndqp, role: .inState).get().locations,
                       ["DX"])

        // A mistyped county is still an error — that gate was the reason the
        // prefix form could not be offered before, and the ARRL list replaced it.
        guard case .failure = ExchangeParser.parse("SAF", party: ndqp, role: .inState) else {
            return XCTFail("a token the ARRL list does not carry must not validate")
        }

        // The score is unaffected either way: DX is never a multiplier here.
        XCTAssertFalse(ndqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", my: "CSS", their: "DL"),
        ]), party: ndqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.multiplierCount, 0, "logged faithfully, and worth no multiplier")
        XCTAssertTrue(try XCTUnwrap(ndqp.notes).contains("CAN NOW LOG THE DX COUNTRY"))
    }

    /// **KNOWN LIMITATION 1, pinned.** "Digital = (RTTY/PSK), **NO FT8**" cannot
    /// be enforced: `digital` is one mode class and the party admits RTTY and
    /// PSK under it, so an FT8 row scores. **Illinois wants the same thing** —
    /// second user of that gap, which meets the repo's two-user bar.
    func testKnownGapFT8CannotBeRefused() throws {
        var ft8 = qso(call: "W0FT", mode: .digital, their: "CSS")
        ft8.rawMode = "FT8"
        let s = ScoreEngine.score(log: outLog([ft8]), party: ndqp)
        XCTAssertEqual(s.validQSOs, 1, "the sponsor forbids it; the app cannot tell")
        XCTAssertEqual(s.qsoPoints, 1)
        XCTAssertTrue(try XCTUnwrap(ndqp.notes).contains("KNOWN LIMITATION 1"))
    }

    // MARK: County lines and credit

    /// "Mobile stations may park on a county line but **each county must be
    /// worked in a separate contact**" — which is not the same as forbidding
    /// line-sitting, but has the same effect on the exchange. The opposite of
    /// Georgia, where the rover sends both counties at once.
    func testEachCountyMustBeASeparateContact() throws {
        XCTAssertEqual(ndqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("CSS/BRN", party: ndqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
        let gaqp = try XCTUnwrap(PartyCatalog.party(id: "gaqp"))
        XCTAssertEqual(gaqp.maxSimultaneousCounties, 4, "Georgia takes both at once")
    }

    /// "Mobile ND stations that change counties are considered to be a **new
    /// station in each new county**."
    func testMobileChangingCountyIsANewStation() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "CSS"),
            qso(call: "W0MOB", band: .m40, mode: .cw, their: "BRN"),
        ]), party: ndqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "Contacts with only ND Stations count."
    func testOutOfStateEntrantsWorkNorthDakotaOnly() {
        XCTAssertTrue(ndqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", their: "CSS"),
            qso(call: "K5B", their: "TX"),
        ]), party: ndqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("mck", party: ndqp, role: .inState).get().locations,
                       ["MCK"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: ndqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: ndqp, role: .inState).get().locations,
                       ["DC"], "DC is one of the 63")
        guard case .failure = ExchangeParser.parse("ND", party: ndqp, role: .inState) else {
            return XCTFail("ND must be rejected — North Dakota stations send a county")
        }
    }

    // MARK: Schedule

    /// "Starts at **1800Z** (1:00 PM CDST) April 11th, 2026 until **1800Z**
    /// (1:00 PM CDST) April 12th, 2026" — both instants, both years, UTC and
    /// local. Nothing derived.
    func testScheduleIsOneUnbrokenTwentyFourHourWindow() throws {
        let windows = try XCTUnwrap(ndqp.schedule)
        XCTAssertEqual(windows.count, 1, "one window, not two legs")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-11T18:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-12T18:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 24 * 3600)

        var central = Calendar(identifier: .gregorian)
        central.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(central.component(.hour, from: windows[0].start), 13, "1:00 PM CDT")
        XCTAssertEqual(central.component(.hour, from: windows[0].end), 13)
    }

    /// One unbroken 24-hour window — a shape North Dakota shares with exactly
    /// two other bundled parties, Maine and South Dakota. Pinned as the group
    /// rather than as a superlative, so a fourth joining is a visible change.
    func testTheSingleWindowTwentyFourHourParties() {
        let matches = PartyCatalog.loadBundled().filter { party in
            guard let s = party.schedule, s.count == 1 else { return false }
            return s[0].end.timeIntervalSince(s[0].start) == 24 * 3600
        }.map(\.id).sorted()
        XCTAssertEqual(matches, ["meqp", "ndqp", "sdqp"])
    }

    /// Four parties share 11 April 2026, and North Dakota opens at the same
    /// minute as Georgia.
    func testFourPartiesShareTheEleventhOfApril() throws {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let opening = try XCTUnwrap(ndqp.schedule?.first?.start)

        let sameDay = PartyCatalog.loadBundled().filter { party in
            party.schedule?.contains { utc.isDate($0.start, inSameDayAs: opening) } == true
        }.map(\.id).sorted()
        XCTAssertEqual(sameDay, ["gaqp", "moqp", "ndqp", "nmqp"])

        let gaqp = try XCTUnwrap(PartyCatalog.party(id: "gaqp"))
        XCTAssertEqual(gaqp.schedule?.first?.start, opening, "Georgia opens at the same minute")
    }

    func testNotesRecordTheRemainingLimitationAndTheSponsorsOwnErrors() throws {
        let notes = try XCTUnwrap(ndqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertFalse(notes.contains("KNOWN LIMITATION 2"),
                       "the DX-country limitation closed, leaving only the FT8 one")
        XCTAssertTrue(notes.contains("THE CANADIAN LIST IS NOT THE STANDARD THIRTEEN"))
        XCTAssertTrue(notes.contains("SPONSOR ERRORS SHIPPED AS PRINTED"))
    }
}

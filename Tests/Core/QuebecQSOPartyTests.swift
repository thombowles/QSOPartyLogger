import XCTest
@testable import QSOPartyLogger

/// Quebec QSO Party — built from Club Radio Amateur de l'Outaouais's own rules,
/// read verbatim 2026-07-26 in **both** the French and English editions. See
/// docs/research/qcqp_rules.md.
///
/// The bilingual publication is a real second source, and it earns its keep:
/// the two editions **disagree about what `NT` means**, and both carry a
/// fourteenth Canadian row for a territory already listed.
final class QuebecQSOPartyTests: XCTestCase {

    var qcqp: PartyDefinition!

    override func setUpWithError() throws {
        qcqp = try XCTUnwrap(PartyCatalog.party(id: "qcqp"), "bundled QCQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "VE2ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "MTL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_776_603_600 + seq),  // 2026-04-19 13:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "qcqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from region: String = "MTL") -> ContestLog {
        var log = ContestLog(partyID: "qcqp")
        log.myLocation = .inState(counties: [region])
        log.qsos = qsos
        return log
    }

    // MARK: The 17 administrative regions

    func testRegionData() {
        XCTAssertEqual(qcqp.counties.count, 17, "Quebec has 17 administrative regions")
        XCTAssertEqual(Set(qcqp.counties.map(\.abbr)).count, 17)
        XCTAssertEqual(Set(qcqp.counties.map(\.name)).count, 17)
        XCTAssertEqual(qcqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// **`QUE` is region 3, the Capitale-Nationale** — the Quebec City region,
    /// not the province. The province is not a valid entry at all: "Note that
    /// the Province of Quebec (QC) is not a valid territory entry."
    func testQUEIsTheCapitaleNationaleAndNotTheProvince() {
        XCTAssertEqual(qcqp.county(for: "QUE")?.name, "Capitale-Nationale")
        XCTAssertFalse(qcqp.provinces.contains("QC"))
        XCTAssertFalse(qcqp.validOutStateTokens.contains("QC"))
    }

    /// Region names ship with the French edition's accents — they are the correct
    /// proper nouns, and the French page is the sponsor's primary language. The
    /// English edition strips them.
    func testRegionNamesCarryTheirAccents() {
        XCTAssertEqual(qcqp.county(for: "MTL")?.name, "Montréal")
        XCTAssertEqual(qcqp.county(for: "CND")?.name, "Côte-Nord")
        XCTAssertEqual(qcqp.county(for: "MEE")?.name, "Montérégie")
        XCTAssertEqual(qcqp.county(for: "ATE")?.name, "Abitibi-Témiscamingue")
    }

    /// Three codes one letter apart, meaning three different parts of Quebec.
    func testTheThreeConfusableQuebecCodes() {
        XCTAssertEqual(qcqp.county(for: "CDQ")?.name, "Centre-du-Québec")
        XCTAssertEqual(qcqp.county(for: "NDQ")?.name, "Nord-du-Québec")
        XCTAssertEqual(qcqp.county(for: "CND")?.name, "Côte-Nord")
        XCTAssertEqual(qcqp.county(for: "mtl")?.name, "Montréal", "case-insensitive")
    }

    // MARK: Appendix II — fourteen rows for thirteen entities

    /// **`NT` and `NWT` are the same territory**, and the sponsor lists both. The
    /// English edition even mislabels `NT` as "Northern Territories" where the
    /// French correctly says "Territoires du Nord-Ouest". All fourteen tokens
    /// ship as printed: accepting `NWT` never blocks a legal exchange, and
    /// rejecting it would.
    func testAllFourteenCanadianTokensShipIncludingTheDuplicate() throws {
        XCTAssertEqual(qcqp.provinces.count, 14, "fourteen rows for thirteen entities")
        XCTAssertTrue(qcqp.provinces.contains("NT"))
        XCTAssertTrue(qcqp.provinces.contains("NWT"))
        for token in ["NT", "NWT"] {
            XCTAssertEqual(
                try ExchangeParser.parse(token, party: qcqp, role: .inState).get().locations,
                [token], "\(token) is printed by the sponsor, so it must parse")
        }
        XCTAssertTrue(try XCTUnwrap(qcqp.notes).contains("FOURTEEN ROWS FOR THIRTEEN"))
    }

    /// Newfoundland is split into `NF` + `LB`, as North Dakota's list also splits
    /// it — but unlike North Dakota's, this one carries Nunavut.
    func testNewfoundlandIsSplitAndNunavutIsPresent() throws {
        XCTAssertTrue(qcqp.provinces.contains("NF"))
        XCTAssertTrue(qcqp.provinces.contains("LB"))
        XCTAssertFalse(qcqp.provinces.contains("NL"))
        XCTAssertTrue(qcqp.provinces.contains("NU"))

        let ndqp = try XCTUnwrap(PartyCatalog.party(id: "ndqp"))
        XCTAssertTrue(ndqp.provinces.contains("NF"), "North Dakota splits it too")
        XCTAssertFalse(ndqp.provinces.contains("NU"), "…but has no Nunavut")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(qcqp.cabrilloContest, "QC-QSO-PARTY")
        XCTAssertEqual(qcqp.homeState, "QC")
        XCTAssertEqual(qcqp.allowedModeClasses, [.phone, .cw])
        XCTAssertTrue(qcqp.exchangeIncludesRST)
        XCTAssertFalse(qcqp.exchangeIncludesSerial)
        XCTAssertTrue(qcqp.isPartiallyVerified)
    }

    /// "All amateur bands between **80 et 2 m**, excepted WARC bands" — seven
    /// bands, and **no 160 m**, which Ontario the day before does have.
    func testSevenBandsStartingAtEightyNotOneSixty() throws {
        XCTAssertEqual(qcqp.validBands, [.m80, .m40, .m20, .m15, .m10, .m6, .m2])
        XCTAssertFalse(qcqp.validBands.contains(.m160), "the range starts at 80 m")
        XCTAssertFalse(qcqp.validBands.contains(.m60), "OPEN QUESTION 1 — see the notes")

        let oqp = try XCTUnwrap(PartyCatalog.party(id: "oqp"))
        XCTAssertTrue(oqp.validBands.contains(.m160), "Ontario's does not")
    }

    /// "**1 point** per QSO on phone… **2 points** per QSO on CW." Ontario, which
    /// shares the weekend, raised phone to 2 for 2026 — Quebec did not, and the
    /// two neighbours now score phone differently.
    func testPhoneIsOnePointUnlikeOntario() throws {
        XCTAssertEqual(qcqp.points.points(for: .phone), 1)
        XCTAssertEqual(qcqp.points.points(for: .cw), 2)

        let oqp = try XCTUnwrap(PartyCatalog.party(id: "oqp"))
        XCTAssertEqual(oqp.points.points(for: .phone), 2, "Ontario's 2026 change")
    }

    /// "A station can be contacted **twice per band, once on phone and once on
    /// CW**. … Additional logged QSOs have no value but are not penalized."
    func testTwicePerBandAndDupesAreWorthZeroNotNegative() {
        XCTAssertEqual(qcqp.dupeScope, .bandMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VE2A", band: .m40, mode: .cw, their: "MTL"),
            qso(call: "VE2A", band: .m40, mode: .phone, their: "MTL"),
            qso(call: "VE2A", band: .m40, mode: .cw, their: "MTL"),
        ]), party: qcqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.qsoPoints, 3, "2 for the CW, 1 for the phone, 0 for the dupe")
    }

    // MARK: Multipliers — per band, and the mode axis denied outright

    /// "…on each frequency band worked on these regions. **No additional
    /// multipliers are given for working multiple modes.**" The clearest
    /// statement of that scope anywhere in the app.
    func testMultipliersCountPerBandAndModeIsExplicitlyDenied() {
        XCTAssertEqual(qcqp.multipliers.inState.countScope, .perBand)
        XCTAssertEqual(qcqp.multipliers.outState.countScope, .perBand)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VE2A", band: .m20, mode: .cw, their: "MTL"),
            qso(call: "VE2A", band: .m20, mode: .phone, their: "MTL"),
            qso(call: "VE2B", band: .m40, mode: .cw, their: "MTL"),
        ]), party: qcqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 2, "Montréal on 20 m and on 40 m — not per mode")
    }

    func testOutOfStateCeilingIsSeventeenPerBand() {
        XCTAssertEqual(Set(qcqp.multipliers.outState.classes), [.county])
        var rows: [QSO] = []
        for (i, c) in qcqp.counties.enumerated() {
            rows.append(qso(call: "VE2\(i)", band: .m20, their: c.abbr))
            rows.append(qso(call: "VE2\(i)", band: .m40, their: c.abbr))
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: qcqp).multiplierCount, 34,
                       "seventeen regions on each of two bands")
    }

    /// **`dxStyle: token` is the rule here, not an approximation of it.** "Only
    /// one DX multiplier is given for entities worked outside of Canada or USA",
    /// and "Other DXCC entities must be logged as DX". Ontario, one day earlier,
    /// has the opposite shape and pays for it.
    func testOneDXMultiplierIsExactlyWhatTheSponsorPays() throws {
        XCTAssertEqual(qcqp.dxStyle, .token)
        XCTAssertTrue(qcqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", band: .m20, my: "MTL", their: "DX"),
            qso(call: "JA1BB", band: .m20, my: "MTL", their: "DX"),
            qso(call: "DL1AA", band: .m40, my: "MTL", their: "DX"),
        ]), party: qcqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 2, "one DX per band — which is the rule")

        let oqp = try XCTUnwrap(PartyCatalog.party(id: "oqp"))
        XCTAssertEqual(oqp.dxStyle, .prefix, "Ontario counts entities individually")
    }

    func testInStateAlsoCountsStatesAndProvinces() {
        XCTAssertEqual(Set(qcqp.multipliers.inState.classes),
                       [.county, .state, .province, .dx])
        XCTAssertFalse(qcqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", my: "MTL", their: "MA"),
            qso(call: "W3B", my: "MTL", their: "DC"),
            qso(call: "VE1C", my: "MTL", their: "NS"),
            qso(call: "VE3D", my: "MTL", their: "ON"),
        ]), party: qcqp)
        XCTAssertEqual(s.multiplierCount, 4)
    }

    // MARK: Credit, boundaries, bonuses

    /// "The VE2 stations obtain points for contacts with **all stations**. Non-VE2
    /// stations obtain points for contacts for **VE2 stations only**."
    func testNonVE2StationsWorkQuebecOnly() {
        XCTAssertTrue(qcqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VE2A", their: "MTL"),
            qso(call: "K5B", their: "TX"),
        ]), party: qcqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "If a mobile station is on a boundary between 2 or more administrative
    /// regions, a **separate QSO and complete exchange must be made and logged
    /// for each**."
    func testEachRegionNeedsItsOwnQSO() {
        XCTAssertEqual(qcqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("MTL/LVL", party: qcqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
    }

    /// "**Starting in 2026, there is no bonus station(s)**", so the only bonus is
    /// the mobile activation — word for word the same rule Ontario has.
    func testTheOnlyBonusIsTheMobileActivation() throws {
        XCTAssertEqual(qcqp.bonuses, [.activatedCountyCount(minQSOs: 3, points: 300)])
        let oqp = try XCTUnwrap(PartyCatalog.party(id: "oqp"))
        XCTAssertEqual(qcqp.bonuses, oqp.bonuses, "identical to Ontario's, wording and all")

        func rows(_ region: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in qso(call: "W\(region)\(i)", my: region, their: "TX") }
        }
        var log = inLog(rows("MTL", 3) + rows("LVL", 2))
        log.station.categoryStation = .mobile
        log.myLocation = .inState(counties: ["MTL"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: qcqp).bonusPoints, 300)
    }

    /// **KNOWN LIMITATION, pinned.** The sponsor wants "three contacts with three
    /// different stations"; the schema counts three QSOs. **Second user of that
    /// gap after Ontario, one day apart on the calendar** — which meets the
    /// repo's two-user bar.
    func testKnownGapThreeQSOsWithOneStationStillEarnsTheBonus() throws {
        var log = inLog([
            qso(call: "W1SAME", band: .m20, my: "MTL", their: "TX"),
            qso(call: "W1SAME", band: .m40, my: "MTL", their: "TX"),
            qso(call: "W1SAME", band: .m80, my: "MTL", their: "TX"),
        ])
        log.station.categoryStation = .mobile
        log.myLocation = .inState(counties: ["MTL"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: qcqp).bonusPoints, 300)
        XCTAssertTrue(try XCTUnwrap(qcqp.notes).contains("KNOWN LIMITATION"))
    }

    /// **Paragraph 20's "multiplier of two for lower power" must not reach the
    /// score.** It lives under "Awards per club, inside Quebec"; paragraph 16
    /// fixes the entrant's score as QSO points × multipliers. A reader skimming
    /// for "multiplier of two" would give every low-power entrant a wrong ×2.
    func testTheLowPowerDoublingIsAnAwardTallyAndNotAScoreMultiplier() {
        XCTAssertNil(qcqp.scoreMultipliers)
        let rows = [qso(call: "VE2A", their: "MTL"), qso(call: "VE2B", their: "QUE")]
        var low = outLog(rows); low.station.categoryPower = .low
        var high = outLog(rows); high.station.categoryPower = .high
        XCTAssertEqual(ScoreEngine.score(log: low, party: qcqp).total,
                       ScoreEngine.score(log: high, party: qcqp).total,
                       "power changes the award tally, never the score")
    }

    // MARK: Schedule

    /// "The Quebec QSO Party will be held on **Sunday April 19th, 2026, from
    /// 13:00 to 24:00 UTC**", and the home page adds the local anchor: "9 AM to
    /// 8 PM Eastern Daylight Time".
    func testScheduleIsOneElevenHourWindowOnTheSunday() throws {
        let windows = try XCTUnwrap(qcqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-19T13:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-20T00:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 11 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 1, "Sunday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 19)

        var montreal = Calendar(identifier: .gregorian)
        montreal.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Montreal"))
        XCTAssertEqual(montreal.component(.hour, from: windows[0].start), 9, "9 AM EDT")
        XCTAssertEqual(montreal.component(.hour, from: windows[0].end), 20, "8 PM EDT")
    }

    /// Quebec runs on the Sunday of Ontario's weekend and overlaps its second
    /// leg — Ontario 1200–2000Z, Quebec 1300–2400Z.
    func testItOverlapsOntariosSundayLeg() throws {
        let oqp = try XCTUnwrap(PartyCatalog.party(id: "oqp"))
        let ontarioSunday = try XCTUnwrap(oqp.schedule?.last)
        let mine = try XCTUnwrap(qcqp.schedule?.first)
        XCTAssertLessThan(mine.start, ontarioSunday.end, "they overlap")
        XCTAssertGreaterThan(mine.start, ontarioSunday.start, "Quebec starts an hour later")
        XCTAssertGreaterThan(mine.end, ontarioSunday.end, "…and runs four hours longer")
    }

    func testNotesRecordTheBilingualSourceAndTheAppendixDefect() throws {
        let notes = try XCTUnwrap(qcqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("BOTH A FRENCH AND AN ENGLISH EDITION"))
        XCTAssertTrue(notes.contains("FOURTEEN ROWS FOR THIRTEEN ENTITIES"))
        XCTAssertTrue(notes.contains("AWARD TALLY, NOT A SCORE"))
        XCTAssertTrue(notes.contains("OPEN QUESTION 1"))
    }
}

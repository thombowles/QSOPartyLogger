import XCTest
@testable import QSOPartyLogger

/// Mississippi QSO Party — Vicksburg Amateur Radio Club, manager W5XX. Built
/// from the sponsor's official 2026 rules PDF and its County Check List, read
/// verbatim 2026-07-26. See docs/research/msqp_rules.md.
///
/// **The first party here that builds FT4/FT8 in on purpose** — four parties
/// this run bar it outright — and every one of its four limitations flows from
/// that: grid-square multipliers, a grid-square exchange, an RTTY-vs-FT4/8 mode
/// split, and per-county mobile scoring.
final class MississippiQSOPartyTests: XCTestCase {

    var msqp: PartyDefinition!

    override func setUpWithError() throws {
        msqp = try XCTUnwrap(PartyCatalog.party(id: "msqp"), "bundled MSQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W5ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "HIN"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_775_311_200 + seq),  // 2026-04-04 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "msqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "HIN") -> ContestLog {
        var log = ContestLog(partyID: "msqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 82, with some of the densest clusters in the repo

    func testCountyData() {
        XCTAssertEqual(msqp.counties.count, 82, "Mississippi has 82 counties")
        XCTAssertEqual(Set(msqp.counties.map(\.abbr)).count, 82)
        XCTAssertEqual(Set(msqp.counties.map(\.name)).count, 82)
        XCTAssertEqual(msqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// Four `Ca-`/`Cl-` counties, and `CLA` is **Clay** — not Claiborne, not
    /// Clarke, and not Calhoun.
    func testTheFourCaAndClCounties() {
        XCTAssertEqual(msqp.county(for: "CAL")?.name, "Calhoun")
        XCTAssertEqual(msqp.county(for: "CLA")?.name, "Clay")
        XCTAssertEqual(msqp.county(for: "CLB")?.name, "Claiborne")
        XCTAssertEqual(msqp.county(for: "CLK")?.name, "Clarke")
    }

    func testTheFourLaCountiesAndTheFourWaCounties() {
        XCTAssertEqual(msqp.county(for: "LAF")?.name, "Lafayette")
        XCTAssertEqual(msqp.county(for: "LAM")?.name, "Lamar")
        XCTAssertEqual(msqp.county(for: "LAU")?.name, "Lauderdale")
        XCTAssertEqual(msqp.county(for: "LAW")?.name, "Lawrence")
        XCTAssertEqual(msqp.county(for: "WAL")?.name, "Walthall")
        XCTAssertEqual(msqp.county(for: "WAR")?.name, "Warren")
        XCTAssertEqual(msqp.county(for: "WAS")?.name, "Washington")
        XCTAssertEqual(msqp.county(for: "WAY")?.name, "Wayne")
    }

    /// `GRN` Greene against `GRE` Grenada — one letter apart, with the
    /// shorter-looking code on the longer name.
    func testGreeneAgainstGrenadaAndMarshallAgainstMarion() {
        XCTAssertEqual(msqp.county(for: "GRN")?.name, "Greene")
        XCTAssertEqual(msqp.county(for: "GRE")?.name, "Grenada")
        XCTAssertEqual(msqp.county(for: "MAR")?.name, "Marshall")
        XCTAssertEqual(msqp.county(for: "MRN")?.name, "Marion")
        XCTAssertEqual(msqp.county(for: "MAD")?.name, "Madison")
    }

    /// The Jefferson pair Louisiana also has, with different codes — and DeSoto,
    /// which Louisiana prints as two words.
    func testTheCodesSharedWithLouisianaDiffer() throws {
        XCTAssertEqual(msqp.county(for: "JEF")?.name, "Jefferson")
        XCTAssertEqual(msqp.county(for: "JDV")?.name, "Jefferson Davis")
        XCTAssertEqual(msqp.county(for: "DES")?.name, "DeSoto", "one word here")

        let laqp = try XCTUnwrap(PartyCatalog.party(id: "laqp"))
        XCTAssertEqual(laqp.county(for: "JEFF")?.name, "Jefferson", "Louisiana uses four letters")
        XCTAssertEqual(laqp.county(for: "DESO")?.name, "De Soto", "…and two words")
        XCTAssertEqual(msqp.county(for: "hin")?.name, "Hinds", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(msqp.cabrilloContest, "MS-QSO-PARTY",
                       "WA7BNM; the rules print none and do not require Cabrillo")
        XCTAssertEqual(msqp.homeState, "MS")
        XCTAssertEqual(msqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(msqp.dxStyle, .prefix, "'DX stations send signal report and Country'")
        XCTAssertTrue(msqp.exchangeIncludesRST)
        XCTAssertFalse(msqp.exchangeIncludesSerial)
        XCTAssertEqual(msqp.bonuses, [], "no bonus station and no activation bonus")
        XCTAssertNil(msqp.scoreMultipliers, "'No separate mode or power categories'")
        XCTAssertTrue(msqp.isPartiallyVerified)
    }

    func testEightBandsListedOutright() {
        XCTAssertEqual(msqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for excluded in [Band.m60, .m30, .m17, .m12, .cm125, .cm70] {
            XCTAssertFalse(msqp.validBands.contains(excluded))
        }
    }

    // MARK: Points

    /// "SSB = 1; CW = 2; RTTY = 2; FT4/8 = 2" — four sponsor modes into three
    /// mode classes with **no loss of points accuracy**, because RTTY and FT4/8
    /// pay alike. The difference between them matters for multipliers and dupes.
    func testPointsByMode() {
        XCTAssertEqual(msqp.points.points(for: .phone), 1)
        XCTAssertEqual(msqp.points.points(for: .cw), 2)
        XCTAssertEqual(msqp.points.points(for: .digital), 2)
    }

    // MARK: Multipliers — once overall

    /// "Multipliers: (Earned ONCE regardless of band/mode worked.)" — stated in
    /// the heading, before the list.
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(msqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(msqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", band: .m20, mode: .cw, their: "HIN"),
            qso(call: "W5A", band: .m40, mode: .cw, their: "HIN"),
            qso(call: "W5A", band: .m20, mode: .phone, their: "HIN"),
        ]), party: msqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfStateCeilingIs82Counties() {
        XCTAssertEqual(Set(msqp.multipliers.outState.classes), [.county])
        let rows = msqp.counties.enumerated().map { i, c in qso(call: "W5\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: msqp).multiplierCount, 82)
    }

    /// "1 for each of the **remaining** States worked (**49** possible)" — 49,
    /// not 50, so Mississippi is excluded.
    func testMississippiIsNotAStateMultiplier() {
        XCTAssertFalse(msqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "HIN", their: "WAR")]), party: msqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(msqp.validOutStateTokens.contains("MS"))
    }

    func testInStateCountsCountiesStatesProvincesAndDXCC() {
        XCTAssertEqual(Set(msqp.multipliers.inState.classes), [.county, .state, .province, .dx])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W5A", my: "HIN", their: "WAR"),
            qso(call: "K5B", my: "HIN", their: "TX"),
            qso(call: "VE3C", my: "HIN", their: "ON"),
            qso(call: "DL1D", my: "HIN", their: "DL"),
        ]), party: msqp)
        XCTAssertEqual(s.multiplierCount, 4)
    }

    /// **KNOWN LIMITATION 1, pinned — the largest gap here.** On FT4/8 the
    /// sponsor counts **MS grid squares** as multipliers: up to nine
    /// (EM41–44, EM50–54) for an out-of-state entrant on a base of 82, and
    /// *grids ÷ 4 rounded up*, uncapped, for an MS entrant. `MultClass` has no
    /// grid case and `QSO` has no grid field, so none of it is counted.
    ///
    /// The grids still are not counted, and that half of the limitation
    /// stands. What is gone is the *phantom*: this party's DX style is
    /// `.prefix`, and the old `isPlausibleDXPrefix` accepted any 1–5
    /// alphanumeric token with a letter in it, so `EM42` parsed happily as a
    /// DX prefix and an MS entrant who logged one earned a DXCC multiplier
    /// that does not exist. `DXCCTable` checks the ARRL list instead, so the
    /// grid square is an error again.
    func testGridSquaresAreRejectedRatherThanCountedAsAPhantomEntity() throws {
        guard case .failure(let error) =
                ExchangeParser.parse("EM42", party: msqp, role: .inState) else {
            return XCTFail("a grid square is not a DXCC prefix and must not validate")
        }
        guard case .unknownAbbreviation(let token, _) = error else {
            return XCTFail("expected an unknown-abbreviation error, got \(error)")
        }
        XCTAssertEqual(token, "EM42")

        // `EM` alone IS Ukraine's, which is exactly why shape was never a safe
        // test: the grid square's own first two letters are a real prefix.
        XCTAssertTrue(msqp.isDXPrefix("EM"))
        XCTAssertFalse(msqp.isDXPrefix("EM42"))

        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1AW", mode: .digital, my: "HIN", their: "EM42"),
        ]), party: msqp)
        XCTAssertEqual(s.workedValues(.dx), [], "no phantom entity")
        XCTAssertEqual(s.multiplierCount, 0)

        let notes = try XCTUnwrap(msqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("ADD THEM BY HAND"))
        XCTAssertTrue(notes.contains("FT4/8 CONTACTS ARE BEST KEPT OUT OF THIS LOG"))
        XCTAssertFalse(notes.contains("PHANTOM DX MULTIPLIER"),
                       "the phantom is fixed — the warning must not outlive it")
    }

    /// **KNOWN LIMITATION 3, pinned.** The sponsor's own example works one
    /// station on "20m CW, 20m SSB, 20m RTTY, 20m FT4/8" — four QSOs. This app
    /// collapses RTTY and FT4/8 into one mode class and flags the fourth as a
    /// dupe. VTQP wants the identical finer split.
    func testKnownGapRTTYAndFT4Or8ShareOneModeClass() throws {
        var rtty = qso(call: "W1AW", band: .m20, mode: .digital, their: "HIN")
        rtty.rawMode = "RTTY"
        var ft8 = qso(call: "W1AW", band: .m20, mode: .digital, their: "HIN")
        ft8.rawMode = "FT8"
        ft8.id = UUID()
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1AW", band: .m20, mode: .cw, their: "HIN"),
            qso(call: "W1AW", band: .m20, mode: .phone, their: "HIN"),
            rtty, ft8,
        ]), party: msqp)
        XCTAssertEqual(s.validQSOs, 3, "the sponsor's example has four")
        XCTAssertEqual(s.dupeCount, 1, "the FT4/8 contact is flagged, wrongly")
        XCTAssertTrue(try XCTUnwrap(msqp.notes).contains("KNOWN LIMITATION 3"))
    }

    // MARK: County lines — the rules say nothing

    /// **The rules contain no county-line provision at all** — neither
    /// permitting nor forbidding. Shipped at 1 on the reading that silence is
    /// not permission; open question 2. Contrast SCQP, which permits line
    /// contacts without capping them and therefore ships the schema default.
    func testCountyLinesAreRejectedBecauseTheRulesAreSilent() throws {
        XCTAssertEqual(msqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("HIN/WAR", party: msqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
        let scqp = try XCTUnwrap(PartyCatalog.party(id: "scqp"))
        XCTAssertEqual(scqp.maxSimultaneousCounties, 4,
                       "SCQP permits them and caps nothing — the contrasting call")
        XCTAssertTrue(try XCTUnwrap(msqp.openQuestions).contains("NOT MENTIONED ANYWHERE"))
    }

    // MARK: Dupes, exchange, credit

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5MOB", band: .m40, mode: .cw, their: "HIN"),
            qso(call: "W5MOB", band: .m40, mode: .cw, their: "WAR"),
        ]), party: msqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("hin", party: msqp, role: .inState).get().locations,
                       ["HIN"])
        XCTAssertEqual(try ExchangeParser.parse("JDV", party: msqp, role: .inState).get().locations,
                       ["JDV"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: msqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: msqp, role: .inState).get().locations,
                       ["DL"])
        guard case .failure = ExchangeParser.parse("MS", party: msqp, role: .inState) else {
            return XCTFail("MS must be rejected — Mississippi stations send a county")
        }
    }

    /// Inferred rather than stated — the objectives and the multiplier list both
    /// point that way but no sentence forbids other contacts. Open question 3.
    func testOutOfStateCreditIsRestrictedByInference() {
        XCTAssertTrue(msqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", their: "HIN"),
            qso(call: "K5B", their: "TX"),
        ]), party: msqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — the cleanest of the run

    /// The rules print **both instants and the duration**, all three agreeing,
    /// and the sponsor's separate activity page states "April 4, 2026, 9:00 am –
    /// 9:00 pm CDT" — which is exactly this window. Nothing is derived.
    func testScheduleIsStatedThreeWaysAndAgrees() throws {
        let windows = try XCTUnwrap(msqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-04T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-05T02:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600,
                       "the rules state 'Duration: 12 Hours' as well as both instants")

        // The activity page's local hours, against a real zone.
        var central = Calendar(identifier: .gregorian)
        central.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(central.component(.hour, from: windows[0].start), 9, "9 am CDT")
        XCTAssertEqual(central.component(.hour, from: windows[0].end), 21, "9 pm CDT")
    }

    /// Mississippi and Louisiana share 4 April and overlap for their whole
    /// twelve hours — worth pinning, since an operator will be running both.
    func testItOverlapsLouisianaCompletely() throws {
        let laqp = try XCTUnwrap(PartyCatalog.party(id: "laqp"))
        XCTAssertEqual(try XCTUnwrap(laqp.schedule).first, try XCTUnwrap(msqp.schedule).first,
                       "identical windows, so both can be worked together")
    }

    func testNotesRecordAllFourLimitations() throws {
        let notes = try XCTUnwrap(msqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        for n in 1...4 {
            XCTAssertTrue(notes.contains("KNOWN LIMITATION \(n)"), "limitation \(n)")
        }
        XCTAssertTrue(notes.contains("BUILDS FT4/FT8 IN ON PURPOSE"))
    }
}

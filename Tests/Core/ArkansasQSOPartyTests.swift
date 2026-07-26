import XCTest
@testable import QSOPartyLogger

/// Arkansas QSO Party — built from arkqp.com, read verbatim 2026-07-26. See
/// docs/research/arqp_rules.md.
///
/// Two things worth knowing: the rules state **no contest times at all**, and
/// the "2 points for mobile" rule — which looks unmodellable — **fits exactly**,
/// because the engine's formula is associative.
final class ArkansasQSOPartyTests: XCTestCase {

    var arqp: PartyDefinition!

    override func setUpWithError() throws {
        arqp = try XCTUnwrap(PartyCatalog.party(id: "arqp"), "bundled ARQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W5ABC", band: Band = .m20, mode: ModeClass = .cw,
        my: String = "TX", their: String = "PUL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_778_940_000 + seq),  // 2026-05-16 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO], station: StationProfile.CategoryStation = .fixed) -> ContestLog {
        var log = ContestLog(partyID: "arqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "PUL") -> ContestLog {
        var log = ContestLog(partyID: "arqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties

    func testCountyData() {
        XCTAssertEqual(arqp.counties.count, 75, "Arkansas has 75 counties")
        XCTAssertEqual(Set(arqp.counties.map(\.abbr)).count, 75)
        XCTAssertEqual(arqp.countyAbbrLengths, [3])
    }

    /// **Clark is `CLK` because Clay took `CLA`** — the only pair here where both
    /// counties exist to explain the collision. Polk and Jackson are spelled
    /// oddly with nothing to blame: `POL` and `JAC` are simply unused.
    func testTheCodesAreNotTruncations() {
        XCTAssertEqual(arqp.county(for: "CLA")?.name, "Clay")
        XCTAssertEqual(arqp.county(for: "CLK")?.name, "Clark")
        XCTAssertEqual(arqp.county(for: "PLK")?.name, "Polk")
        XCTAssertNil(arqp.county(for: "POL"))
        XCTAssertEqual(arqp.county(for: "JAK")?.name, "Jackson")
        XCTAssertNil(arqp.county(for: "JAC"))
        XCTAssertEqual(arqp.county(for: "HSP")?.name, "Hot Spring")
    }

    /// There is an **Arkansas County in Arkansas**, and its code is `ARK`.
    func testArkansasCounty() {
        XCTAssertEqual(arqp.county(for: "ARK")?.name, "Arkansas")
        XCTAssertEqual(arqp.county(for: "ark")?.name, "Arkansas", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(arqp.cabrilloContest, "AR-QSO-PARTY")
        XCTAssertEqual(arqp.homeState, "AR")
        XCTAssertEqual(arqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(arqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        XCTAssertTrue(arqp.exchangeIncludesRST)
        XCTAssertTrue(arqp.isPartiallyVerified)
    }

    func testFlatOnePointBeforeTheCategoryFactor() {
        for mode in ModeClass.allCases {
            XCTAssertEqual(arqp.points.points(for: mode), 1, "\(mode) — flat, any band")
        }
    }

    /// **"Mobile, Portable, and Rover stations claim 2 points per QSO… All other
    /// categories claim 1 point."** That keys points on the *entrant's* category,
    /// which `PointsTable` cannot express — but the engine computes
    /// `qsoPoints × mults × categoryFactor + bonus`, so doubling the points and
    /// doubling the factor give the same total. **This is exact, not an
    /// approximation.**
    func testTheTwoPointMobileRuleIsExactRatherThanApproximated() throws {
        let m = try XCTUnwrap(arqp.scoreMultipliers)
        for station in [StationProfile.CategoryStation.mobile, .portable, .rover] {
            XCTAssertEqual(m.factor(power: .high, station: station), 2, "\(station)")
        }
        for station in [StationProfile.CategoryStation.fixed, .expedition, .school] {
            XCTAssertEqual(m.factor(power: .high, station: station), 1, "\(station)")
        }

        let rows = [qso(call: "W5A", their: "PUL"), qso(call: "W5B", their: "ARK")]
        let fixed = ScoreEngine.score(log: outLog(rows), party: arqp)
        let mobile = ScoreEngine.score(log: outLog(rows, station: .mobile), party: arqp)

        XCTAssertEqual(fixed.qsoPoints, 2, "one point each")
        XCTAssertEqual(mobile.total, fixed.total * 2)
        // The identity that makes it exact: 2 points x mults == 1 point x mults x 2.
        XCTAssertEqual(mobile.total, (fixed.qsoPoints * 2) * fixed.multiplierCount)
    }

    // MARK: Multipliers

    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(arqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(arqp.multipliers.outState.countScope, .once)
    }

    func testOutOfStateCeilingIs75() {
        XCTAssertEqual(Set(arqp.multipliers.outState.classes), [.county])
        let rows = arqp.counties.enumerated().map { i, c in qso(call: "W5\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: arqp).multiplierCount, 75)
    }

    /// "U.S. States **EXCEPT Arkansas**" — Arkansas is not a state multiplier;
    /// its entrants count the 75 counties directly.
    func testArkansasIsNotAStateMultiplier() {
        XCTAssertFalse(arqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertEqual(Set(arqp.multipliers.inState.classes),
                       [.county, .state, .province, .dx])
        XCTAssertFalse(arqp.validOutStateTokens.contains("AR"))
        let s = ScoreEngine.score(log: inLog([qso(my: "PUL", their: "ARK")]), party: arqp)
        XCTAssertEqual(s.workedValues(.county), ["ARK"])
        XCTAssertTrue(s.workedValues(.state).isEmpty)
    }

    /// **The DX cap actually binds here.** "Regardless of number of DX QSOs made,
    /// only count **1** DX multiplier" — and since the exchange is the literal
    /// token, one is exactly what the engine produces. The first party where
    /// `dxMultCap` and the token style agree instead of fighting.
    func testTheDXCapBindsRatherThanBeingUnreachable() throws {
        XCTAssertEqual(arqp.multipliers.inState.dxMultCap, 1)
        let rows = (0..<8).map { qso(call: "DL\($0)AA", my: "PUL", their: "DX") }
        let s = ScoreEngine.score(log: inLog(rows), party: arqp)
        XCTAssertEqual(s.validQSOs, 8)
        XCTAssertEqual(s.workedValues(.dx), ["DX"], "one, which is the rule exactly")

        let nhqp = try XCTUnwrap(PartyCatalog.party(id: "nhqp"))
        XCTAssertEqual(nhqp.multipliers.inState.dxMultCap, 10,
                       "New Hampshire's cap of ten can never be reached")
    }

    // MARK: Bonuses

    /// "All stations claim **200 points for each valid QSO** with bonus station
    /// **WR5P**" — per QSO, which the rules state explicitly.
    func testTheBonusStationPaysPerQSO() {
        XCTAssertEqual(arqp.bonuses.first,
                       .workStation(call: "WR5P", points: 200, scope: .perQSO))
        let s = ScoreEngine.score(log: outLog([
            qso(call: "WR5P", band: .m20, mode: .cw, their: "PUL"),
            qso(call: "WR5P", band: .m40, mode: .cw, their: "PUL"),
            qso(call: "WR5P", band: .m20, mode: .phone, their: "PUL"),
        ]), party: arqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.bonusPoints, 600, "200 for each")
    }

    /// "…can claim **200 points for each Arkansas county** from which they make a
    /// QSO" — one QSO is enough, which is the lowest threshold in the app.
    func testTwoHundredPerActivatedCountyWithASingleQSO() {
        XCTAssertEqual(arqp.bonuses.last, .activatedCountyCount(minQSOs: 1, points: 200))
        var log = inLog([
            qso(call: "W5A", my: "PUL", their: "TX"),
            qso(call: "W5B", my: "ARK", their: "OK"),
        ])
        log.station.categoryStation = .mobile
        log.myLocation = .inState(counties: ["PUL"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: arqp).bonusPoints, 400,
                       "one QSO from each of two counties")
    }

    /// **KNOWN LIMITATION 1, pinned.** The 500-point live-streaming bonus, new
    /// for 2026, pays for streaming to YouTube or Twitch — not something a logger
    /// can observe, and no `BonusRule` shape describes it.
    func testKnownGapTheLiveStreamingBonusIsNotModelled() throws {
        XCTAssertEqual(arqp.bonuses.count, 2, "the two that can be observed on the air")
        XCTAssertTrue(try XCTUnwrap(arqp.notes).contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(try XCTUnwrap(arqp.notes).contains("LIVE-STREAMING BONUS"))
    }

    // MARK: Credit, county lines, schedule

    /// "Contacts made by outside-Arkansas stations with other outside-Arkansas
    /// stations **will not be counted**."
    func testOutOfStateEntrantsWorkArkansasOnly() {
        XCTAssertTrue(arqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", their: "PUL"),
            qso(call: "K5B", their: "TX"),
        ]), party: arqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "…within three miles of a county line… can transmit county abbreviations
    /// for **all of the applicable counties**", with no cap stated — so the
    /// schema default ships.
    func testCountyLinesUseTheSchemaDefault() throws {
        XCTAssertEqual(arqp.maxSimultaneousCounties, 4)
        XCTAssertEqual(
            try ExchangeParser.parse("PUL/ARK", party: arqp, role: .inState).get().locations,
            ["PUL", "ARK"])
    }

    /// **OPEN QUESTION 1, pinned.** "Contest Period: **The third Saturday in
    /// May**" and nothing else — the rules state no times at all, exactly as
    /// Delaware's do. The date derives; the hours come from the Challenge
    /// calendar.
    func testTheDateDerivesButTheHoursDoNot() throws {
        let w = try XCTUnwrap(arqp.schedule)
        XCTAssertEqual(w.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(w[0].start, f.date(from: "2026-05-16T14:00:00Z"))
        XCTAssertEqual(w[0].end, f.date(from: "2026-05-17T02:00:00Z"))
        XCTAssertEqual(w[0].end.timeIntervalSince(w[0].start), 12 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: w[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: w[0].start), 16,
                       "the third Saturday in May 2026")

        XCTAssertTrue(try XCTUnwrap(arqp.notes).contains("OPEN QUESTION 1"))
        XCTAssertTrue(try XCTUnwrap(arqp.notes).contains("NO CONTEST TIMES"))
    }

    func testNotesRecordTheCountyListDate() throws {
        let notes = try XCTUnwrap(arqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("NEW for 2022"))
    }
}

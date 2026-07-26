import XCTest
@testable import QSOPartyLogger

/// Kentucky QSO Party — built from the Kentucky Contest Group's own site, read
/// verbatim 2026-07-26. See docs/research/kyqp_rules.md.
///
/// **The site has rolled forward to 2027 and it does not matter** — the rules
/// give a formula and year-independent times, so the 2026 window derives from
/// the sponsor rather than from the page's headline date.
final class KentuckyQSOPartyTests: XCTestCase {

    var kyqp: PartyDefinition!

    override func setUpWithError() throws {
        kyqp = try XCTUnwrap(PartyCatalog.party(id: "kyqp"), "bundled KYQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W4ABC", band: Band = .m20, mode: ModeClass = .cw,
        my: String = "TX", their: String = "ADA"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_780_750_800 + seq),  // 2026-06-06 13:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO], power: StationProfile.CategoryPower = .high) -> ContestLog {
        var log = ContestLog(partyID: "kyqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "ADA") -> ContestLog {
        var log = ContestLog(partyID: "kyqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties

    func testCountyData() {
        XCTAssertEqual(kyqp.counties.count, 120, "Kentucky has 120 counties")
        XCTAssertEqual(Set(kyqp.counties.map(\.abbr)).count, 120)
        XCTAssertEqual(kyqp.countyAbbrLengths, [3])
    }

    /// The codes are truncations **only where the letters were free**. Five
    /// counties start `Gr`, and the sponsor had to spread them across five
    /// codes; Hardin and Harlan, and Monroe and Montgomery, are the same story.
    func testTheCodesDivergeWhereTheObviousLettersWereTaken() {
        XCTAssertEqual(kyqp.county(for: "HAR")?.name, "Hardin")
        XCTAssertEqual(kyqp.county(for: "HRL")?.name, "Harlan")
        XCTAssertEqual(kyqp.county(for: "MON")?.name, "Monroe")
        XCTAssertEqual(kyqp.county(for: "MOT")?.name, "Montgomery")
        for (code, name) in [("GRE", "Green"), ("GRP", "Greenup"), ("GRT", "Grant"),
                             ("GRV", "Graves"), ("GRY", "Grayson")] {
            XCTAssertEqual(kyqp.county(for: code)?.name, name)
        }
        XCTAssertEqual(kyqp.county(for: "ada")?.name, "Adair", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(kyqp.cabrilloContest, "KYQP")
        XCTAssertEqual(kyqp.homeState, "KY")
        XCTAssertEqual(kyqp.validBands, [.m80, .m40, .m20, .m15, .m10, .m6, .m2],
                       "no 160 m")
        XCTAssertEqual(kyqp.allowedModeClasses, [.phone, .cw], "NO digital QSOs")
        XCTAssertTrue(kyqp.exchangeIncludesRST)
        XCTAssertTrue(kyqp.isPartiallyVerified)
    }

    func testPointsByMode() {
        XCTAssertEqual(kyqp.points.points(for: .phone), 1)
        XCTAssertEqual(kyqp.points.points(for: .cw), 2)
    }

    /// "High Power … **1**. Low Power … **2**. QRP … **3**." — the fifth party to
    /// ship a power multiplier.
    func testThePowerMultiplierShips() throws {
        let m = try XCTUnwrap(kyqp.scoreMultipliers)
        XCTAssertEqual(m.factor(power: .qrp, station: .fixed), 3)
        XCTAssertEqual(m.factor(power: .low, station: .fixed), 2)
        XCTAssertEqual(m.factor(power: .high, station: .fixed), 1)

        let rows = [qso(call: "W4A", their: "ADA"), qso(call: "W4B", their: "ALL")]
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows, power: .qrp), party: kyqp).total,
                       ScoreEngine.score(log: outLog(rows), party: kyqp).total * 3)
    }

    // MARK: Multipliers

    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(kyqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(kyqp.multipliers.outState.countScope, .once)
    }

    func testOutOfStateCeilingIs120() {
        XCTAssertEqual(Set(kyqp.multipliers.outState.classes), [.county])
        let rows = kyqp.counties.enumerated().map { i, c in qso(call: "W4\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: kyqp).multiplierCount, 120)
    }

    /// Kentucky entrants count the 120 counties directly, plus states (including
    /// DC) and provinces. Kentucky itself is never received — "enter the County
    /// as the exchange (**not KY**)".
    func testKentuckyEntrantsCountCountiesAndKYIsNotAToken() {
        XCTAssertFalse(kyqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertEqual(Set(kyqp.multipliers.inState.classes), [.county, .state, .province])
        XCTAssertFalse(kyqp.validOutStateTokens.contains("KY"))
        XCTAssertTrue(kyqp.validOutStateTokens.contains("DC"))
    }

    /// "KY stations log DX contacts **for QSO points only**" — the fourth party
    /// with that shape, after Georgia, North Dakota and Indiana.
    func testDXPaysPointsAndNoMultiplier() throws {
        XCTAssertFalse(kyqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1AA", my: "ADA", their: "DX"),
            qso(call: "JA1BB", my: "ADA", their: "DX"),
        ]), party: kyqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 4)
        XCTAssertEqual(s.multiplierCount, 0)

        let shape = ["gaqp", "ndqp", "inqp", "kyqp"].compactMap { PartyCatalog.party(id: $0) }
        XCTAssertEqual(shape.count, 4)
        XCTAssertTrue(shape.allSatisfy { !$0.multipliers.inState.classes.contains(.dx) })
    }

    // MARK: The bonus station

    /// "**K4KCG may be worked once per BAND and MODE for 100 bonus points per
    /// QSO**" — which is exactly the `perBandMode` scope this run added for
    /// South Carolina. Second user, and it fits without adjustment.
    func testTheBonusStationUsesThePerBandModeScope() throws {
        XCTAssertEqual(kyqp.bonuses,
                       [.workStation(call: "K4KCG", points: 100, scope: .perBandMode)])
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K4KCG", band: .m20, mode: .cw, their: "ADA"),
            qso(call: "K4KCG", band: .m20, mode: .phone, their: "ADA"),
            qso(call: "K4KCG", band: .m40, mode: .cw, their: "ADA"),
            qso(call: "K4KCG", band: .m40, mode: .cw, their: "ADA"),
        ]), party: kyqp)
        XCTAssertEqual(s.validQSOs, 3, "the fourth is a dupe")
        XCTAssertEqual(s.bonusPoints, 300, "100 for each distinct band/mode pair")

        let scqp = try XCTUnwrap(PartyCatalog.party(id: "scqp"))
        XCTAssertTrue(scqp.bonuses.contains { bonus in
            if case .workStation(_, _, .perBandMode) = bonus { return true }
            return false
        }, "South Carolina is where that scope came from")
    }

    /// **KNOWN LIMITATION 1, pinned.** The 100-point log-submission bonus pays
    /// for uploading a Cabrillo file, not for anything on the air — the same gap
    /// Delaware has with its 50-point version.
    func testKnownGapTheSubmissionBonusIsNotModelled() throws {
        XCTAssertEqual(kyqp.bonuses.count, 1, "only the one that happens on the air")
        XCTAssertTrue(try XCTUnwrap(kyqp.notes).contains("KNOWN LIMITATION 1"))
    }

    /// **KNOWN LIMITATION 2, pinned.** County-line permission is per *category*
    /// here — fixed stations must pick one county, mobiles may send several —
    /// and `maxSimultaneousCounties` is one number for the whole party. The
    /// permissive default ships, because refusing a legal mobile exchange would
    /// be the worse failure.
    func testKnownGapCountyLinePermissionIsPerCategory() throws {
        XCTAssertEqual(kyqp.maxSimultaneousCounties, 4)
        XCTAssertEqual(
            try ExchangeParser.parse("ADA/ALL", party: kyqp, role: .inState).get().locations,
            ["ADA", "ALL"])
        XCTAssertTrue(try XCTUnwrap(kyqp.notes).contains("KNOWN LIMITATION 2"))
    }

    // MARK: Credit and schedule

    func testOutOfStateEntrantsWorkKentuckyOnly() {
        XCTAssertTrue(kyqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", their: "ADA"),
            qso(call: "K5B", their: "TX"),
        ]), party: kyqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "**UTC: 13Z – 01Z**", "always **1st Saturday in June**". The site's
    /// headline says 2027; the formula and times are year-independent, so 2026
    /// derives from the sponsor.
    func testScheduleDerivesFromTheFormulaNotThePagesHeadline() throws {
        let w = try XCTUnwrap(kyqp.schedule)
        XCTAssertEqual(w.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(w[0].start, f.date(from: "2026-06-06T13:00:00Z"))
        XCTAssertEqual(w[0].end, f.date(from: "2026-06-07T01:00:00Z"))
        XCTAssertEqual(w[0].end.timeIntervalSince(w[0].start), 12 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: w[0].start), 7, "Saturday")
        XCTAssertLessThanOrEqual(utc.component(.day, from: w[0].start), 7,
                                 "the FIRST Saturday in June")

        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(eastern.component(.hour, from: w[0].start), 9, "9 AM EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[0].end), 21, "9 PM EDT")
    }

    func testNotesRecordTheRolloverAndTheBonusWarning() throws {
        let notes = try XCTUnwrap(kyqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("ROLLED FORWARD TO 2027 AND IT DOES NOT MATTER"))
        XCTAssertTrue(notes.contains("Bonus stations may change each year"))
    }
}

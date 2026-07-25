import XCTest
@testable import QSOPartyLogger

/// Colorado QSO Party — Grand Mesa Contesters rules, revised 2026-07-15,
/// re-verified 2026-07-24. See docs/research/coqp_rules.md.
final class ColoradoQSOPartyTests: XCTestCase {

    var coqp: PartyDefinition!

    override func setUpWithError() throws {
        coqp = try XCTUnwrap(PartyCatalog.party(id: "coqp"), "bundled COQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K0ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "DEN"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_300_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "coqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(
        _ qsos: [QSO],
        from county: String = "DEN",
        station: StationProfile.CategoryStation = .fixed
    ) -> ContestLog {
        var log = ContestLog(partyID: "coqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: County data — 64 counties, and the collision-prone abbreviations

    func testCountyData() {
        XCTAssertEqual(coqp.counties.count, 64, "Colorado has 64 counties")
        XCTAssertEqual(Set(coqp.counties.map(\.abbr)).count, 64)
        XCTAssertTrue(coqp.counties.allSatisfy { $0.abbr.count == 3 })
    }

    /// Colorado's abbreviations collide constantly. `MON` is the one that would
    /// silently mis-credit a multiplier if guessed from the name.
    func testLookalikeAbbreviations() {
        XCTAssertEqual(coqp.county(for: "MON")?.name, "Montezuma", "MON is NOT Montrose")
        XCTAssertEqual(coqp.county(for: "MOT")?.name, "Montrose")
        XCTAssertEqual(coqp.county(for: "MOF")?.name, "Moffat")
        XCTAssertEqual(coqp.county(for: "MOR")?.name, "Morgan")
        XCTAssertEqual(coqp.county(for: "LAK")?.name, "Lake")
        XCTAssertEqual(coqp.county(for: "LAP")?.name, "La Plata")
        XCTAssertEqual(coqp.county(for: "LAR")?.name, "Larimer")
        XCTAssertEqual(coqp.county(for: "LAA")?.name, "Las Animas")
        XCTAssertEqual(coqp.county(for: "ELP")?.name, "El Paso")
        XCTAssertEqual(coqp.county(for: "ELB")?.name, "Elbert")
        XCTAssertEqual(coqp.county(for: "SAG")?.name, "Saguache")
        XCTAssertEqual(coqp.county(for: "SAJ")?.name, "San Juan")
        XCTAssertEqual(coqp.county(for: "SAM")?.name, "San Miguel")
        XCTAssertEqual(coqp.county(for: "KIO")?.name, "Kiowa")
        XCTAssertEqual(coqp.county(for: "KIC")?.name, "Kit Carson")
        XCTAssertEqual(coqp.county(for: "RIB")?.name, "Rio Blanco")
        XCTAssertEqual(coqp.county(for: "RIG")?.name, "Rio Grande")
        XCTAssertEqual(coqp.county(for: "CLC")?.name, "Clear Creek")
        XCTAssertEqual(coqp.county(for: "clc")?.name, "Clear Creek", "case-insensitive")
    }

    func testPartyShape() {
        XCTAssertEqual(coqp.cabrilloContest, "COQP")
        XCTAssertEqual(coqp.homeState, "CO")
        XCTAssertEqual(coqp.countyAbbrLength, 3)
        XCTAssertEqual(coqp.allowedModeClasses, [.phone, .cw], "digital is not permitted")
        XCTAssertEqual(coqp.dxStyle, .token)
        XCTAssertTrue(coqp.exchangeIncludesRST)
        XCTAssertTrue(coqp.outStateWorksHomeStationsOnly,
                      "QSOs must include at least one Colorado station")
        XCTAssertEqual(coqp.maxSimultaneousCounties, 2,
                       "county lines are logged as two entries")
        XCTAssertNil(coqp.scoreMultipliers, "no power or category multiplier")
        XCTAssertFalse(coqp.isPartiallyVerified, "dated 2026 revision, fully verified")
        // "80, 40, 20, 15, 10, 6, and 2 meters" — notably no 160 m.
        XCTAssertEqual(coqp.validBands, [.m80, .m40, .m20, .m15, .m10, .m6, .m2])
        XCTAssertFalse(coqp.validBands.contains(.m160), "COQP has no 160 m")
    }

    // MARK: Points — flat 2 per QSO

    func testTwoPointsPerQSOInBothModes() {
        XCTAssertEqual(coqp.points.points(for: .phone), 2)
        XCTAssertEqual(coqp.points.points(for: .cw), 2)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K0A", mode: .cw, their: "DEN"),
            qso(call: "K0B", mode: .phone, their: "BOU"),
        ]), party: coqp)
        XCTAssertEqual(s.qsoPoints, 4)
    }

    func testDigitalRowsAreInvalid() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K0A", mode: .cw, their: "DEN"),
            qso(call: "K0B", mode: .digital, their: "BOU"),
        ]), party: coqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1)
    }

    // MARK: Multipliers are per MODE, not per band

    func testMultsCountPerModeNotPerBand() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K0A", band: .m40, mode: .cw, their: "DEN"),
            qso(call: "K0A", band: .m40, mode: .phone, their: "DEN"), // 2nd mult
            qso(call: "K0B", band: .m20, mode: .cw, their: "DEN"),    // no new mult
        ]), party: coqp)
        XCTAssertEqual(s.multiplierCount, 2,
                       "'a county worked on both CW and Phone counts as two multipliers'")
    }

    /// Rules: out-of-state "Maximum multipliers per mode: 64."
    func testOutOfStateCeilingIs64PerMode() {
        var rows: [QSO] = []
        var n = 0
        for abbr in coqp.counties.map(\.abbr) {
            n += 1
            rows.append(qso(call: "K0\(n)", band: .m40, mode: .cw, their: abbr))
            // Same county on a second band must add nothing.
            rows.append(qso(call: "K0\(n)b", band: .m20, mode: .cw, their: abbr))
        }
        let s = ScoreEngine.score(log: outLog(rows), party: coqp)
        XCTAssertEqual(s.multiplierCount, 64, "64 counties, one mode, bands irrelevant")
    }

    /// Rules: in-state "Maximum multipliers per mode: 128" — which is only
    /// reachable if Colorado itself counts among the 50 states, earned via a
    /// Colorado county. This is the assertion that pins
    /// `homeStateCountsViaCounty`.
    func testInStateCeilingIs128PerModeIncludingColoradoItself() {
        XCTAssertTrue(coqp.multipliers.inState.homeStateCountsViaCounty)

        var rows: [QSO] = []
        var n = 0
        func add(_ loc: String) {
            n += 1
            rows.append(qso(call: "W\(n)", band: .m40, mode: .cw, my: "DEN", their: loc))
        }
        coqp.counties.map(\.abbr).forEach(add)
        // Every state token except CO (never sent) and DC (credited as MD).
        MultClass.usStates.subtracting(["CO"]).sorted().forEach(add)
        MultClass.canadianProvinces.sorted().forEach(add)
        add("DX")

        let s = ScoreEngine.score(log: inLog(rows), party: coqp)
        XCTAssertEqual(s.workedValues(.county).count, 64)
        XCTAssertTrue(s.workedValues(.state).contains("CO"),
                      "Colorado is earned via a Colorado county")
        XCTAssertEqual(s.workedValues(.state).count, 50, "49 worked + CO via county")
        XCTAssertEqual(s.workedValues(.province).count, 13)
        XCTAssertEqual(s.workedValues(.dx).count, 1, "one DX mult regardless of how many")
        XCTAssertEqual(s.multiplierCount, 128, "the rules' own stated ceiling")
    }

    /// A single Colorado county yields both the county and the CO state mult.
    func testFirstColoradoCountyAlsoYieldsTheStateMultiplier() {
        let s = ScoreEngine.score(log: inLog([qso(my: "DEN", their: "MES")]), party: coqp)
        XCTAssertEqual(s.workedValues(.county), ["MES"])
        XCTAssertEqual(s.workedValues(.state), ["CO"])
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// Out-of-state entrants get counties only — no CO state mult, no provinces.
    func testOutOfStateGetsCountiesOnly() {
        let s = ScoreEngine.score(log: outLog([qso(their: "MES")]), party: coqp)
        XCTAssertEqual(s.workedValues(.county), ["MES"])
        XCTAssertEqual(s.workedValues(.state), [], "no state class for out-of-state entrants")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Misc rules — DC, AK/HI, USA/Canada not DX

    func testDCCountsAsMarylandAndAKHIAreStates() {
        XCTAssertEqual(coqp.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K3A", my: "DEN", their: "DC"),
            qso(call: "K3B", my: "DEN", their: "MD"),
            qso(call: "KL7C", my: "DEN", their: "AK"),
            qso(call: "KH6D", my: "DEN", their: "HI"),
        ]), party: coqp)
        XCTAssertEqual(s.workedValues(.state), ["MD", "AK", "HI"],
                       "DC folds into MD; AK/HI are states; no CO — none of these "
                           + "contacts was with a Colorado county")
        XCTAssertEqual(s.workedValues(.dx), [], "neither USA nor Canada counts as DX")
    }

    func testOneDXMultiplierRegardlessOfCount() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "DEN", their: "DX"),
            qso(call: "JA1B", my: "DEN", their: "DX"),
            qso(call: "G4C", my: "DEN", their: "DX"),
        ]), party: coqp)
        XCTAssertEqual(s.workedValues(.dx), ["DX"], "'one DX multiplier if any DX is worked'")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: "QSOs must include at least one Colorado station"

    func testOutOfStateEarnsNothingForNonColoradoContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K0A", their: "DEN"),
            qso(call: "K5B", their: "TX"),
            qso(call: "VE3C", their: "ON"),
            qso(call: "DL1D", their: "DX"),
        ]), party: coqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 3)
        XCTAssertEqual(s.qsoPoints, 2)
    }

    // MARK: Dupes — the sponsor spells out our exact key

    func testDupeKeyIsCallBandModeAndCounty() {
        let a = qso(call: "K0M", band: .m40, mode: .cw, their: "SUM")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "K0M", band: .m40, mode: .phone, their: "SUM")
        let movedCounty = qso(call: "K0M", band: .m40, mode: .cw, their: "PAR")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, movedCounty]), party: coqp)
        XCTAssertEqual(s.dupeCount, 1, "only same call+band+mode+county repeats")
        XCTAssertEqual(s.validQSOs, 3)
    }

    // MARK: Bonus — 500 per activated county, 15 QSOs required (not TnQP's 10)

    func testActivationBonusRequiresFifteenQSOs() {
        func rows(_ county: String, _ count: Int) -> [QSO] {
            (0..<count).map { i in
                qso(call: "W\(county)\(i)", mode: .cw, my: county, their: "DEN")
            }
        }
        // SUM qualifies with 15; PAR falls short with 14 — TnQP's 10 must not apply.
        let log = inLog(rows("SUM", 15) + rows("PAR", 14), station: .mobile)
        let s = ScoreEngine.score(log: log, party: coqp)
        XCTAssertEqual(s.bonusPoints, 500, "only the county with 15+ QSOs pays")

        let twoCounties = inLog(rows("SUM", 15) + rows("PAR", 15), station: .portable)
        XCTAssertEqual(ScoreEngine.score(log: twoCounties, party: coqp).bonusPoints, 1000)

        // A fixed Colorado station earns no activation bonus.
        var fixed = log
        fixed.station.categoryStation = .fixed
        XCTAssertEqual(ScoreEngine.score(log: fixed, party: coqp).bonusPoints, 0)
    }

    /// "Final score equals the total number of QSO points … times the total
    /// number of multipliers. Any bonus points are then added to that product."
    func testBonusAddedAfterMultiplying() {
        let rows = (0..<15).map { i in
            qso(call: "W\(i)", mode: .cw, my: "SUM", their: "DEN")
        }
        let s = ScoreEngine.score(log: inLog(rows, station: .mobile), party: coqp)
        XCTAssertEqual(s.qsoPoints, 30, "15 QSOs x 2 points")
        XCTAssertEqual(s.multiplierCount, 2, "DEN county + CO via county")
        XCTAssertEqual(s.bonusPoints, 500)
        XCTAssertEqual(s.total, 30 * 2 + 500, "bonus is not multiplied")
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("den", party: coqp, role: .inState).get().locations, ["DEN"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: coqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: coqp, role: .inState).get().locations, ["DX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: coqp, role: .inState).get().locations, ["DC"],
                       "loggable, credited as MD")
        // Two-county line is legal.
        XCTAssertEqual(
            try ExchangeParser.parse("SUM/PAR", party: coqp, role: .inState).get().locations,
            ["SUM", "PAR"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("SUM/PAR/DEN", party: coqp, role: .inState),
            .failure(.tooManyCounties(3))
        )
        guard case .failure = ExchangeParser.parse("CO", party: coqp, role: .inState) else {
            return XCTFail("CO token must be rejected — Colorado stations send a county")
        }
    }

    // MARK: Schedule — new for 2026: second Saturday in September

    func testSchedule() throws {
        let windows = try XCTUnwrap(coqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-09-12T14:00:00Z"),
                       "second Saturday in September, new from 2026")
        XCTAssertEqual(windows[0].end, f.date(from: "2026-09-13T04:00:00Z"),
                       "'through 03:59 UTC Sunday' closes at 0400Z")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 14 * 3600)
    }
}

import XCTest
@testable import QSOPartyLogger

/// Washington Salmon Run — WWDXC rules "Updated – July 22, 2024", re-read
/// verbatim 2026-07-24. See docs/research/warun_rules.md.
final class SalmonRunTests: XCTestCase {

    var warun: PartyDefinition!

    override func setUpWithError() throws {
        warun = try XCTUnwrap(PartyCatalog.party(id: "warun"), "bundled Salmon Run should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W7ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "KING"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_900_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "warun")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "KING") -> ContestLog {
        var log = ContestLog(partyID: "warun")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 39 counties, and the only MIXED-LENGTH list in the repo

    func testCountyData() {
        XCTAssertEqual(warun.counties.count, 39, "Washington has 39 counties")
        XCTAssertEqual(Set(warun.counties.map(\.abbr)).count, 39)
    }

    /// Washington is the only bundled party mixing abbreviation lengths, because
    /// the 4-character codes exist to split same-prefix pairs.
    func testAbbreviationLengthsAreMixed() {
        XCTAssertEqual(warun.countyAbbrLengths, [3, 4])
        XCTAssertEqual(warun.countyAbbrLengthHint, "3/4",
                       "the entry-field hint must show both, not a single number")
        // Every other party is uniform, so the hint is a bare number there.
        for id in ["ksqp", "mdc", "hqp", "iaqp", "nhqp"] {
            let party = PartyCatalog.party(id: id)
            XCTAssertEqual(party?.countyAbbrLengths.count, 1, "\(id) should be uniform")
        }
    }

    func testSamePrefixPairsAreDistinct() {
        XCTAssertEqual(warun.county(for: "CLAL")?.name, "Clallam")
        XCTAssertEqual(warun.county(for: "CLAR")?.name, "Clark")
        XCTAssertEqual(warun.county(for: "GRAN")?.name, "Grant")
        XCTAssertEqual(warun.county(for: "GRAY")?.name, "Grays Harbor")
        XCTAssertEqual(warun.county(for: "KITS")?.name, "Kitsap")
        XCTAssertEqual(warun.county(for: "KITT")?.name, "Kittitas")
        XCTAssertEqual(warun.county(for: "SKAG")?.name, "Skagit")
        XCTAssertEqual(warun.county(for: "SKAM")?.name, "Skamania")
        XCTAssertEqual(warun.county(for: "PEND")?.name, "Pend Oreille")
        // Three-character neighbours that must not be confused with those.
        XCTAssertEqual(warun.county(for: "COL")?.name, "Columbia")
        XCTAssertEqual(warun.county(for: "COW")?.name, "Cowlitz")
        XCTAssertEqual(warun.county(for: "KLI")?.name, "Klickitat")
        XCTAssertEqual(warun.county(for: "WAH")?.name, "Wahkiakum")
        XCTAssertEqual(warun.county(for: "WAL")?.name, "Walla Walla")
        XCTAssertEqual(warun.county(for: "king")?.name, "King", "case-insensitive")
        // A 3-char truncation of a 4-char county must not resolve.
        XCTAssertNil(warun.county(for: "CLA"), "ambiguous prefix must not resolve")
        XCTAssertNil(warun.county(for: "KIT"))
    }

    func testPartyShape() {
        XCTAssertEqual(warun.cabrilloContest, "WA-SALMON-RUN", "the sponsor's 'official name'")
        XCTAssertEqual(warun.homeState, "WA")
        XCTAssertEqual(warun.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6])
        XCTAssertEqual(warun.allowedModeClasses, [.phone, .cw],
                       "digital is not a contest mode — WSJT modes cannot be accepted")
        XCTAssertEqual(warun.dxStyle, .prefix, "DX stations send their DXCC entity prefix")
        XCTAssertTrue(warun.exchangeIncludesRST)
        XCTAssertEqual(warun.maxSimultaneousCounties, 2,
                       "only one two-county line at a time, even at a 3-county intersection")
        XCTAssertNil(warun.scoreMultipliers, "no power multiplier")
        XCTAssertFalse(warun.isPartiallyVerified, "fully verified against the sponsor's rules")
    }

    /// OBJECT: "Stations outside Washington state work only Washington state
    /// stations" — stated outright, unlike NJQP/IAQP/NHQP where it is implied.
    func testOutOfStateWorksOnlyWashington() {
        XCTAssertTrue(warun.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7A", their: "KING"),
            qso(call: "K5B", their: "TX"),
            qso(call: "VE7C", their: "BC"),
            qso(call: "DL1D", their: "DL"),
        ]), party: warun)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 3)
        XCTAssertEqual(s.qsoPoints, 3, "one CW QSO")
    }

    // MARK: Points — phone 2, CW 3, digital invalid

    func testPointsByMode() {
        XCTAssertEqual(warun.points.points(for: .phone), 2)
        XCTAssertEqual(warun.points.points(for: .cw), 3, "3, not the older editions' 4")
    }

    func testDigitalRowsAreInvalidNotZeroScored() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7A", mode: .cw, their: "KING"),
            qso(call: "W7B", mode: .digital, their: "PIE"),
        ]), party: warun)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.multiplierCount, 1, "the digital row contributes no multiplier")
    }

    // MARK: "Each multiplier may be counted ONLY ONCE regardless of mode or band"

    func testMultipliersCountOnceRegardlessOfBandOrMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7A", band: .m40, mode: .cw, their: "KING"),
            qso(call: "W7A", band: .m20, mode: .cw, their: "KING"),
            qso(call: "W7A", band: .m40, mode: .phone, their: "KING"),
        ]), party: warun)
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.validQSOs, 3, "all three are workable for points")
    }

    /// Rules: 39 counties + "US States less WA (49)" + "VE multipliers (13)" +
    /// "Up to 10 DXCC entities" = 111.
    func testInStateCeilingIs111() {
        var rows: [QSO] = []
        var n = 0
        func add(_ loc: String) {
            n += 1
            rows.append(qso(call: "W\(n)", my: "KING", their: loc))
        }
        warun.counties.map(\.abbr).forEach(add)
        MultClass.usStates.subtracting(["WA"]).sorted().forEach(add)
        MultClass.canadianProvinces.sorted().forEach(add)
        // 12 distinct DXCC prefixes offered; only 10 may count. These are chosen
        // to avoid US-state and province collisions — see
        // testDXPrefixesCollidingWithStateCodesAreReadAsStates.
        ["DL", "G", "JA", "F", "I", "EA", "SM", "OZ", "HB", "LZ", "YU", "SP"].forEach(add)

        let s = ScoreEngine.score(log: inLog(rows), party: warun)
        XCTAssertEqual(s.workedValues(.county).count, 39)
        XCTAssertEqual(s.workedValues(.state).count, 49, "50 states less WA")
        XCTAssertEqual(s.workedValues(.province).count, 13)
        XCTAssertEqual(s.workedValues(.dx).count, 10, "capped at 10 DXCC entities")
        XCTAssertEqual(s.multiplierCount, 111, "the rules' own stated ceiling")
    }

    /// This is the only bundled party where `dxMultCap` actually binds, because
    /// DX stations send a prefix rather than the literal token "DX".
    func testDXCapBindsBecauseDXSendsAPrefix() {
        XCTAssertEqual(warun.multipliers.inState.dxMultCap, 10)
        let prefixes = ["DL", "G", "JA", "F", "I", "EA", "SM", "OZ", "HB", "LZ", "YU", "SP"]
        let rows = prefixes.enumerated().map { i, p in
            qso(call: "X\(i)", my: "KING", their: p)
        }
        let s = ScoreEngine.score(log: inLog(rows), party: warun)
        XCTAssertEqual(s.validQSOs, 12, "all 12 are valid QSOs worth points")
        XCTAssertEqual(s.qsoPoints, 36)
        XCTAssertEqual(s.workedValues(.dx).count, 10, "but only 10 count as multipliers")
    }

    /// Salmon Run is the party where DX prefixes actually carry multiplier
    /// weight, so it is also where `isPlausibleDXPrefix`'s documented collision
    /// limitation bites: a real DXCC prefix that happens to equal a US state or
    /// Canadian province code is read as that state/province. PA is the
    /// Netherlands, OK is Slovakia, LA is Norway, ON is Belgium — all shadowed.
    /// This test exists so the behaviour is deliberate and visible rather than a
    /// surprise in someone's score.
    func testDXPrefixesCollidingWithStateCodesAreReadAsStates() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "PA0AAA", my: "KING", their: "PA"),   // Netherlands → Pennsylvania
            qso(call: "OK1BBB", my: "KING", their: "OK"),   // Slovakia    → Oklahoma
            qso(call: "LA1CCC", my: "KING", their: "LA"),   // Norway      → Louisiana
            qso(call: "ON4DDD", my: "KING", their: "ON"),   // Belgium     → Ontario
            qso(call: "DL1EEE", my: "KING", their: "DL"),   // Germany, no collision
        ]), party: warun)
        XCTAssertEqual(s.workedValues(.state), ["PA", "OK", "LA"],
                       "three DXCC prefixes shadowed by state codes")
        XCTAssertEqual(s.workedValues(.province), ["ON"], "and one by a province code")
        XCTAssertEqual(s.workedValues(.dx), ["DL"], "only the non-colliding prefix is DX")
        XCTAssertFalse(warun.isPlausibleDXPrefix("PA"))
        XCTAssertTrue(warun.isPlausibleDXPrefix("DL"))
    }

    func testWashingtonIsNeverAStateMultiplier() {
        XCTAssertFalse(warun.multipliers.inState.homeStateCountsViaCounty,
                       "'US States less WA (49)'")
        let s = ScoreEngine.score(log: inLog([qso(my: "KING", their: "PIE")]), party: warun)
        XCTAssertEqual(s.workedValues(.state), [], "a WA county yields no WA state mult")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// "District of Columbia counts as MD, Alaska and Hawaii count as states."
    func testDCCountsAsMarylandAndAKHIAreStates() {
        XCTAssertEqual(warun.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K3A", my: "KING", their: "DC"),
            qso(call: "K3B", my: "KING", their: "MD"),
            qso(call: "KL7C", my: "KING", their: "AK"),
            qso(call: "KH6D", my: "KING", their: "HI"),
        ]), party: warun)
        XCTAssertEqual(s.workedValues(.state), ["MD", "AK", "HI"])
        XCTAssertEqual(s.workedValues(.dx), [], "AK/HI are states, never DXCC entities")
    }

    // MARK: W7DX bonus — 500 per MODE, capped at 1000, added after multiplying

    func testW7DXBonusIsPerModeNotPerBand() {
        // Four QSOs with W7DX across two bands and two modes.
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7DX", band: .m40, mode: .cw, their: "KING"),
            qso(call: "W7DX", band: .m20, mode: .cw, their: "KING"),
            qso(call: "W7DX", band: .m40, mode: .phone, their: "KING"),
            qso(call: "W7DX", band: .m20, mode: .phone, their: "KING"),
        ]), party: warun)
        XCTAssertEqual(s.bonusPoints, 1000,
                       "500 per mode, capped at 1000 — 'not 500 points for each QSO "
                           + "on each different band'")
    }

    func testW7DXSingleModeEarnsFiveHundredOnly() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7DX", band: .m40, mode: .cw, their: "KING"),
            qso(call: "W7DX", band: .m20, mode: .cw, their: "KING"),
            qso(call: "W7DX", band: .m15, mode: .cw, their: "KING"),
        ]), party: warun)
        XCTAssertEqual(s.bonusPoints, 500, "one mode worked, so one 500-point bonus")
    }

    /// "Bonus points are added after all other scoring is completed (they are not
    /// multiplied by the 'multiplier'). The Special Bonus Station will count for
    /// its normal county multiplier … and will also earn 2 points on phone and 3
    /// points on CW."
    func testBonusAddedAfterMultiplyingAndW7DXStillScoresNormally() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7DX", band: .m40, mode: .cw, their: "KING"),
            qso(call: "W7B", band: .m40, mode: .phone, their: "PIE"),
        ]), party: warun)
        XCTAssertEqual(s.qsoPoints, 3 + 2, "W7DX earns normal QSO points too")
        XCTAssertEqual(s.multiplierCount, 2, "KING via W7DX + PIE — its county still counts")
        XCTAssertEqual(s.bonusPoints, 500)
        XCTAssertEqual(s.total, 5 * 2 + 500, "bonus is not multiplied")
    }

    // MARK: County lines — two counties, logged as two QSOs

    func testCountyLineIsTwoCountiesMaximum() throws {
        XCTAssertEqual(
            try ExchangeParser.parse("CLAL/JEFF", party: warun).get().locations,
            ["CLAL", "JEFF"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("CLAL/JEFF/KING", party: warun),
            .failure(.tooManyCounties(3)),
            "only one two-county line at a time, even at a 3-county intersection"
        )
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("king", party: warun).get().locations, ["KING"])
        XCTAssertEqual(try ExchangeParser.parse("COL", party: warun).get().locations, ["COL"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: warun).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: warun).get().locations, ["DL"],
                       "DX sends a DXCC prefix")
        guard case .failure = ExchangeParser.parse("WA", party: warun) else {
            return XCTFail("WA must be rejected — WA stations send a county")
        }
    }

    // MARK: Schedule — two windows totalling the stated 23 hours

    func testScheduleTotals23Hours() throws {
        let windows = try XCTUnwrap(warun.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-09-19T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-09-20T07:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-09-20T16:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-09-21T00:00:00Z"))

        let total = windows.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        XCTAssertEqual(total, 23 * 3600, "the rules state 'the full 23 hours of the contest'")
    }
}

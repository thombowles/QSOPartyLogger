import XCTest
@testable import QSOPartyLogger

/// California QSO Party — NCCC rules "Last Update: 19-July-2026 at 1500 UTC",
/// read verbatim 2026-07-24. See docs/research/cqp_rules.md.
///
/// CQP is the first bundled party to cap the multiplier total it will pay for
/// (58 of 63), and the first to state "the first CA county counts as CA" in the
/// sponsor's own words rather than leaving it to arithmetic.
final class CaliforniaQSOPartyTests: XCTestCase {

    var cqp: PartyDefinition!

    override func setUpWithError() throws {
        cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"), "bundled CQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W6ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "SCLA"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "cqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "SCLA") -> ContestLog {
        var log = ContestLog(partyID: "cqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 58, four letters

    func testCountyData() {
        XCTAssertEqual(cqp.counties.count, 58, "California has 58 counties")
        XCTAssertEqual(Set(cqp.counties.map(\.abbr)).count, 58)
        XCTAssertEqual(Set(cqp.counties.map(\.name)).count, 58)
        XCTAssertTrue(cqp.counties.allSatisfy { $0.abbr.count == 4 })
        XCTAssertEqual(cqp.countyAbbrLengths, [4])
        XCTAssertEqual(cqp.countyAbbrLength, 4)
    }

    /// The abbreviations the sponsor itself calls out as breaking its own
    /// "first 4 characters" rule, plus the San/Santa fold. `KERN`→Kern would
    /// prove nothing (Article 18).
    func testIrregularAbbreviations() {
        XCTAssertEqual(cqp.county(for: "CCOS")?.name, "Contra Costa", "not CONT")
        XCTAssertEqual(cqp.county(for: "LANG")?.name, "Los Angeles", "not LOSA")
        XCTAssertEqual(cqp.county(for: "MARN")?.name, "Marin", "not MARI")
        XCTAssertEqual(cqp.county(for: "MARP")?.name, "Mariposa", "also not MARI")
        XCTAssertEqual(cqp.county(for: "SFRA")?.name, "San Francisco", "San → S")
        XCTAssertEqual(cqp.county(for: "SLUI")?.name, "San Luis Obispo")
        XCTAssertEqual(cqp.county(for: "SCRU")?.name, "Santa Cruz", "Santa → S")
        XCTAssertEqual(cqp.county(for: "DELN")?.name, "Del Norte", "space removed")
        XCTAssertEqual(cqp.county(for: "ELDO")?.name, "El Dorado")
        XCTAssertEqual(cqp.county(for: "scla")?.name, "Santa Clara", "case-insensitive")
    }

    /// The sponsor prints exactly which short forms are ambiguous. None of them
    /// may resolve to a county.
    func testSponsorsNamedAmbiguousFormsAreRejected() {
        for bad in ["MON", "MAR", "SB", "SAN"] {
            XCTAssertNil(cqp.county(for: bad), "'\(bad)' is ambiguous and must not resolve")
        }
        XCTAssertEqual(cqp.county(for: "MONT")?.name, "Monterey")
        XCTAssertEqual(cqp.county(for: "MONO")?.name, "Mono")
        XCTAssertEqual(cqp.county(for: "SBEN")?.name, "San Benito")
        XCTAssertEqual(cqp.county(for: "SBER")?.name, "San Bernardino")
        XCTAssertEqual(cqp.county(for: "SBAR")?.name, "Santa Barbara")
    }

    /// Four state tokens are prefixes of county abbreviations. The sponsor lists
    /// each as a common logging error; a 2-letter token is always the state.
    func testStateTokensThatShadowCountyAbbreviations() throws {
        for (state, county) in [("AL", "ALAM"), ("LA", "LANG"), ("NV", "NEVA"), ("OR", "ORAN")] {
            XCTAssertEqual(try ExchangeParser.parse(state, party: cqp).get().locations, [state],
                           "\(state) is the state, not \(county)")
            XCTAssertEqual(try ExchangeParser.parse(county, party: cqp).get().locations, [county])
            XCTAssertNil(cqp.county(for: state))
        }
    }

    func testPartyShape() {
        XCTAssertEqual(cqp.cabrilloContest, "CA-QSO-PARTY", "WA7BNM registry; sponsor prints none")
        XCTAssertEqual(cqp.homeState, "CA")
        XCTAssertEqual(cqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10],
                       "160, 80, 40, 20, 15, 10 — six bands, no WARC, no VHF")
        XCTAssertEqual(cqp.allowedModeClasses, [.phone, .cw], "MODES: CW, Phone")
        XCTAssertEqual(cqp.dxStyle, .token, "'or \"DX\"' — the sponsor's preferred form")
        XCTAssertEqual(cqp.dupeScope, .bandMode)
        XCTAssertEqual(cqp.maxSimultaneousCounties, 4,
                       "county lines are one exchange; the sponsor's guide shows up to 4")
        XCTAssertTrue(cqp.bonuses.isEmpty, "award categories are SOAPBOX lines, not score")
        XCTAssertNil(cqp.scoreMultipliers, "power class decides the award, not the score")
        XCTAssertFalse(cqp.isPartiallyVerified, "rules are current and fully verified")
    }

    /// "California stations send QSO number and 4-letter county abbreviation" —
    /// no RST anywhere in the exchange, the second party after MDC.
    func testExchangeCarriesNoRST() {
        XCTAssertFalse(cqp.exchangeIncludesRST)
    }

    // MARK: Points — 3 and 3 after the 2026 change

    func testPointsAfterThe2026PhoneChange() {
        XCTAssertEqual(cqp.points.points(for: .phone), 3,
                       "phone rose from 2 to 3 for 2026 — the sponsor marks it **NEW in 2026**")
        XCTAssertEqual(cqp.points.points(for: .cw), 3)
        XCTAssertNil(cqp.homeStationPoints, "CQP pays by mode, not by who was worked")

        let s = ScoreEngine.score(log: outLog([
            qso(call: "W6A", mode: .cw, their: "SCLA"),
            qso(call: "W6B", mode: .phone, their: "ALAM"),
        ]), party: cqp)
        XCTAssertEqual(s.qsoPoints, 6, "3 + 3 — CW and phone now pay alike")
    }

    func testDigitalRowsAreInvalidNotZeroScored() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W6A", mode: .cw, their: "SCLA"),
            qso(call: "W6B", mode: .digital, their: "ALAM"),
        ]), party: cqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1, "no digital category exists")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Multipliers — asymmetric, and counted once

    /// Non-CA: "Count all 58 California Counties for a maximum of 58
    /// multipliers." Once each — a second band must add nothing.
    func testOutOfStateCountsCountiesOnceNotPerBand() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W6A", band: .m40, mode: .cw, their: "SCLA"),
            qso(call: "W6A", band: .m20, mode: .cw, their: "SCLA"),    // other band
            qso(call: "W6A", band: .m40, mode: .phone, their: "SCLA"), // other mode
        ]), party: cqp)
        XCTAssertEqual(s.multiplierCount, 1,
                       "would be 3 under perBandMode, 2 under perBand or perMode")
        XCTAssertEqual(s.validQSOs, 3, "all three are still valid, non-duplicate QSOs")
    }

    /// The sponsor's own out-of-state ceiling: all 58, and no more.
    func testOutOfStateCeilingIs58() {
        let rows = cqp.counties.enumerated().map { i, county in
            qso(call: "W6\(i)", their: county.abbr)
        }
        let s = ScoreEngine.score(log: outLog(rows), party: cqp)
        XCTAssertEqual(s.multiplierCount, 58, "the rules' own stated maximum")
        XCTAssertEqual(s.workedValues(.county).count, 58)
    }

    /// CA stations count states and provinces — never counties.
    func testInStateCountsStatesAndProvincesNotCounties() {
        XCTAssertEqual(Set(cqp.multipliers.inState.classes), [.state, .province])
        XCTAssertFalse(cqp.multipliers.inState.classes.contains(.county))

        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", my: "SCLA", their: "TX"),
            qso(call: "VE3B", my: "SCLA", their: "ON"),
        ]), party: cqp)
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "The first valid CA QSO logged with 4-letter county abbreviation will
    /// count as the multiplier for California" — stated by the sponsor, whose
    /// multiplier table lists the CA row as "1st CA county counts as CA".
    func testFirstCACountyYieldsTheCaliforniaStateMultiplier() {
        XCTAssertTrue(cqp.multipliers.inState.homeStateCountsViaCounty)

        let s = ScoreEngine.score(log: inLog([
            qso(call: "W6A", my: "SCLA", their: "ALAM"),
            qso(call: "W6B", my: "SCLA", their: "KERN"),   // a second CA county
        ]), party: cqp)
        XCTAssertEqual(s.workedValues(.state), ["CA"], "both CA QSOs yield the one CA mult")
        XCTAssertEqual(s.workedValues(.county), [], "counties are not an in-state class")
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.qsoPoints, 6, "both are still 3-point QSOs")
    }

    /// Out-of-state entrants get no such thing — CA is not one of their classes.
    func testOutOfStateGetsNoCaliforniaStateMultiplier() {
        XCTAssertFalse(cqp.multipliers.outState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: outLog([qso(their: "ALAM")]), party: cqp)
        XCTAssertEqual(s.workedValues(.county), ["ALAM"])
        XCTAssertEqual(s.workedValues(.state), [])
    }

    // MARK: The 58-of-63 cap

    /// "Although there are 63 possible multipliers that can accrue toward the CA
    /// station's multiplier tally, the maximum number of counted multipliers
    /// toward the CA station's final score is 58."
    func testCaliforniaMultipliersAreCappedAt58OutOf63() {
        XCTAssertEqual(cqp.multipliers.inState.maxScoredMultipliers, 58)
        XCTAssertNil(cqp.multipliers.outState.maxScoredMultipliers,
                     "the 58 counties are their own ceiling; no cap needed")

        // 49 states other than CA, + CA via a county, + all 13 provinces = 63.
        var rows: [QSO] = []
        var n = 0
        for state in MultClass.usStates.subtracting(["CA"]).sorted() {
            n += 1
            rows.append(qso(call: "K\(n)AA", my: "SCLA", their: state))
        }
        for province in MultClass.canadianProvinces.sorted() {
            n += 1
            rows.append(qso(call: "VE\(n)AA", my: "SCLA", their: province))
        }
        rows.append(qso(call: "W6CA", my: "SCLA", their: "ALAM"))

        let s = ScoreEngine.score(log: inLog(rows), party: cqp)
        XCTAssertEqual(s.multiplierKeys.count, 63, "all 63 still accrue to the tally")
        XCTAssertEqual(s.workedValues(.state).count, 50, "49 worked directly + CA via county")
        XCTAssertTrue(s.workedValues(.state).contains("CA"))
        XCTAssertEqual(s.workedValues(.province).count, 13)
        XCTAssertEqual(s.multiplierCount, 58, "but only 58 reach the score")
        XCTAssertEqual(s.total, s.qsoPoints * 58, "the cap is what multiplies QSO points")
    }

    /// Under the cap nothing changes — the cap must not clamp a small log.
    func testCapDoesNotAffectLogsBelowIt() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K5A", my: "SCLA", their: "TX"),
            qso(call: "K4B", my: "SCLA", their: "FL"),
        ]), party: cqp)
        XCTAssertEqual(s.multiplierCount, 2)
        XCTAssertEqual(s.total, s.qsoPoints * 2)
    }

    /// Past the ceiling the "new mult" badge must go quiet, or it sends the
    /// operator chasing a multiplier worth nothing.
    func testNewMultiplierBadgeRespectsTheCap() {
        // 49 states other than CA + 9 provinces = exactly the 58-mult ceiling.
        let states = MultClass.usStates.subtracting(["CA"]).sorted()
        let provinces = MultClass.canadianProvinces.sorted()
        var rows: [QSO] = []
        var n = 0
        for token in states + provinces.prefix(9) {
            n += 1
            rows.append(qso(call: "K\(n)AA", my: "SCLA", their: token))
        }
        let log = inLog(rows)
        XCTAssertEqual(ScoreEngine.score(log: log, party: cqp).multiplierCount, 58)

        let unworked = try? XCTUnwrap(provinces.dropFirst(9).first)
        XCTAssertFalse(
            ScoreEngine.wouldAddMultiplier(
                theirLocs: [unworked ?? "YT"], band: .m20, modeClass: .cw, log: log, party: cqp
            ),
            "a 59th multiplier cannot reach the score"
        )
        // …and one below the ceiling still badges.
        let shorter = inLog(Array(rows.dropLast()))
        XCTAssertTrue(
            ScoreEngine.wouldAddMultiplier(
                theirLocs: [unworked ?? "YT"], band: .m20, modeClass: .cw, log: shorter, party: cqp
            ),
            "at 57 multipliers the next one still pays"
        )
    }

    /// Every other bundled party is uncapped and must stay that way.
    func testCapIsOptInAndDoesNotAffectOtherParties() throws {
        for id in ["nhqp", "meqp", "alqp", "warun"] {
            let party = try XCTUnwrap(PartyCatalog.party(id: id))
            XCTAssertNil(party.multipliers.inState.maxScoredMultipliers, "\(id) in-state")
            XCTAssertNil(party.multipliers.outState.maxScoredMultipliers, "\(id) out-of-state")
        }
    }

    // MARK: DX — points for CA stations, never a multiplier for anyone

    func testDXScoresPointsForCaliforniaButIsNeverAMultiplier() {
        XCTAssertFalse(cqp.multipliers.inState.classes.contains(.dx))
        XCTAssertFalse(cqp.multipliers.outState.classes.contains(.dx))

        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "SCLA", their: "DX"),
            qso(call: "JA1B", band: .m20, my: "SCLA", their: "DX"),
        ]), party: cqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 6, "DX QSOs count as QSO credit")
        XCTAssertEqual(s.multiplierCount, 0, "there are no DX multipliers")
    }

    // MARK: "Non-CA to non-CA contacts do not count for QSO credit"

    func testOutOfStateEntrantsGetNoCreditForNonCaliforniaContacts() {
        XCTAssertTrue(cqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W6A", their: "SCLA"),
            qso(call: "K5B", their: "TX"),     // non-CA to non-CA
            qso(call: "DL1C", their: "DX"),    // "DX QSOs do not count for non-CA"
        ]), party: cqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 2)
        XCTAssertEqual(s.qsoPoints, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// California stations, by contrast, "work everyone".
    func testCaliforniaStationsWorkEveryone() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W6A", my: "SCLA", their: "ALAM"),
            qso(call: "K5B", my: "SCLA", their: "TX"),
            qso(call: "DL1C", my: "SCLA", their: "DX"),
        ]), party: cqp)
        XCTAssertEqual(s.outOfScopeCount, 0)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 9)
    }

    // MARK: Dupes — once per band per mode, 12 with any one station

    func testTwelveQSOsWithOneStationThenDupes() {
        var rows: [QSO] = []
        for band in cqp.validBands {
            for mode in [ModeClass.cw, .phone] {
                rows.append(qso(call: "W6X", band: band, mode: mode, their: "SCLA"))
            }
        }
        let extra = qso(call: "W6X", band: .m40, mode: .cw, their: "SCLA")
        let s = ScoreEngine.score(log: outLog(rows + [extra]), party: cqp)
        XCTAssertEqual(s.validQSOs, 12, "'maximum of 12 QSOs with any one station'")
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.multiplierCount, 1, "one county, counted once")
        XCTAssertEqual(s.qsoPoints, 36)
    }

    /// "California Mobile stations which change counties or states are
    /// considered to be new stations and may be contacted again for point and
    /// multiplier credit."
    func testMobileChangingCountyIsANewQSONotADupe() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W6MOB", band: .m40, mode: .cw, their: "MARN"),
            qso(call: "W6MOB", band: .m40, mode: .cw, their: "MARP"),
        ]), party: cqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.qsoPoints, 6)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("scla", party: cqp).get().locations, ["SCLA"])
        XCTAssertEqual(try ExchangeParser.parse("CCOS", party: cqp).get().locations, ["CCOS"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: cqp).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: cqp).get().locations, ["DC"])
        XCTAssertEqual(try ExchangeParser.parse("NL", party: cqp).get().locations, ["NL"],
                       "Canada is the standard 13 here, unlike MEQP and NJQP")
        XCTAssertEqual(try ExchangeParser.parse("DX", party: cqp).get().locations, ["DX"])
        guard case .failure = ExchangeParser.parse("CA", party: cqp) else {
            return XCTFail("CA must be rejected — California stations send a county")
        }
    }

    /// "sending all such counties in a single exchange" — the sponsor's own
    /// guide uses DELN/SISK/HUMB and offers four Writelog county fields.
    func testCountyLineUpToFourCounties() throws {
        XCTAssertEqual(
            try ExchangeParser.parse("DELN/SISK/HUMB", party: cqp).get().locations,
            ["DELN", "SISK", "HUMB"],
            "the sponsor's own worked example"
        )
        XCTAssertEqual(
            try ExchangeParser.parse("DELN/SISK/HUMB/TRIN", party: cqp).get().locations.count, 4,
            "four is the limit, and it is allowed"
        )
        XCTAssertEqual(
            ExchangeParser.parse("DELN/SISK/HUMB/TRIN/MODO", party: cqp),
            .failure(.tooManyCounties(5))
        )
    }

    /// "DC counts as Maryland" — the multiplier table prints "MD Maryland & DC".
    func testDCCountsAsMaryland() {
        XCTAssertEqual(cqp.stateAliases["DC"], "MD")
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "SCLA", their: "MD"),
            qso(call: "W3B", my: "SCLA", their: "DC"),
        ]), party: cqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"])
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.qsoPoints, 6, "both are still valid 3-point QSOs")
    }

    // MARK: Schedule — one continuous 30-hour window

    func testScheduleIsOneThirtyHourWindow() throws {
        let windows = try XCTUnwrap(cqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-10-03T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-10-04T22:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 30 * 3600,
                       "the class table's multi-op maximum of 30 operating hours")
    }

    /// The serial-number gap must stay visible until it is fixed: CQP accepts
    /// Cabrillo only, and the QSO-number element is part of its exchange.
    func testNotesRecordTheSerialNumberLimitationAndThe2026PointsChange() throws {
        let notes = try XCTUnwrap(cqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION"),
                      "serial numbers are unmodelled — that must not be buried")
        XCTAssertTrue(notes.contains("RULE CHANGE FOR 2026"))
        XCTAssertNil(cqp.openQuestions, "nothing about the rules themselves is unresolved")
    }
}

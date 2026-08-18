import XCTest
@testable import QSOPartyLogger

/// Minnesota QSO Party — Minnesota Wireless Association. Built from the
/// sponsor's 2026 rules, `MNQP_Contest_Rules rev 31.pdf`, footer
/// "Rev 31 – December 31, 2025", read verbatim 2026-07-26.
/// See docs/research/mnqp_rules.md.
///
/// The first party in this repo whose published rules had already moved past the
/// year being built: w0aa.org now serves only the 2027 edition, which changes
/// four scoring rules. `testTheShippedRulesAreThe2026OnesNotThe2027Ones` is what
/// stops a later session applying them by accident.
final class MinnesotaQSOPartyTests: XCTestCase {

    var mnqp: PartyDefinition!

    override func setUpWithError() throws {
        mnqp = try XCTUnwrap(PartyCatalog.party(id: "mnqp"), "bundled MNQP should load")
    }

    var seq: TimeInterval = 0
    /// MNQP exchanges a name and a location and **no signal report**, so the
    /// report fields are empty here — which is also what the app records.
    func qso(
        call: String = "W0ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "HEN"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_476_400 + seq),  // 2026-02-07 15:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "mnqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "HEN") -> ContestLog {
        var log = ContestLog(partyID: "mnqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 87, cross-checked against the sponsor's own second table

    func testCountyData() {
        XCTAssertEqual(mnqp.counties.count, 87, "Minnesota has 87 counties")
        XCTAssertEqual(Set(mnqp.counties.map(\.abbr)).count, 87)
        XCTAssertEqual(Set(mnqp.counties.map(\.name)).count, 87)
        XCTAssertEqual(mnqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// None of these is the naive first three letters, and several sit one letter
    /// apart. `CAR` and `KAN` are not designators in this party at all.
    func testIrregularDesignators() {
        XCTAssertEqual(mnqp.county(for: "CRL")?.name, "Carlton")
        XCTAssertEqual(mnqp.county(for: "CRV")?.name, "Carver")
        XCTAssertEqual(mnqp.county(for: "CRO")?.name, "Crow Wing")
        XCTAssertNil(mnqp.county(for: "CAR"), "three Car-/Cro- counties, and none of them is CAR")

        XCTAssertEqual(mnqp.county(for: "KNB")?.name, "Kanabec")
        XCTAssertEqual(mnqp.county(for: "KND")?.name, "Kandiyohi")
        XCTAssertNil(mnqp.county(for: "KAN"))

        XCTAssertEqual(mnqp.county(for: "MRS")?.name, "Marshall")
        XCTAssertEqual(mnqp.county(for: "MRT")?.name, "Martin")
        XCTAssertEqual(mnqp.county(for: "LKW")?.name, "Lake of the Woods")
        XCTAssertEqual(mnqp.county(for: "LAK")?.name, "Lake", "distinct from Lake of the Woods")
        XCTAssertEqual(mnqp.county(for: "hen")?.name, "Hennepin", "case-insensitive")
    }

    /// Both are printed unconventionally by the sponsor, and both ship as printed:
    /// "St Louis" carries no period (unlike ILQP's `SCLA` St. Clair) and Otter
    /// Tail is one word.
    func testTheSponsorsOwnSpellingsSurvive() {
        XCTAssertEqual(mnqp.county(for: "STL")?.name, "St Louis")
        XCTAssertEqual(mnqp.county(for: "OTT")?.name, "Ottertail")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(mnqp.cabrilloContest, "MN-QSO-PARTY", "WA7BNM 238; sponsor prints none")
        XCTAssertEqual(mnqp.homeState, "MN")
        XCTAssertEqual(mnqp.dxStyle, .token, "'DX Stations: First name only… logged as DX'")
        XCTAssertFalse(mnqp.exchangeIncludesSerial)
        XCTAssertNil(mnqp.scoreMultipliers, "'final score is QSO points total times multiplier total'")
        XCTAssertEqual(mnqp.bonuses, [], "no bonus station, no bonus points — awards only")
        XCTAssertTrue(mnqp.isPartiallyVerified)
    }

    /// "HF: 160m - 10m (excluding WARC bands)" — and unlike VTQP, no VHF or UHF
    /// at all. The sponsor's suggested-frequency table carries exactly one
    /// frequency per band per mode, which is what fixes the count at six.
    func testSixHFBandsOnly() {
        XCTAssertEqual(mnqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10])
        for excluded in [Band.m60, .m30, .m17, .m12] {
            XCTAssertFalse(mnqp.validBands.contains(excluded), "\(excluded.rawValue) excluded")
        }
        for vhf in [Band.m6, .m2, .cm125, .cm70] {
            XCTAssertFalse(mnqp.validBands.contains(vhf), "MNQP is HF only")
        }
    }

    // MARK: Points — flat, and the sponsor says so

    /// "Score 2 QSO points for all QSO's, i.e. Phone and CW QSO's equal 2 QSO
    /// points each."
    func testEveryQSOIsWorthTwoPoints() {
        XCTAssertEqual(mnqp.points.points(for: .phone), 2)
        XCTAssertEqual(mnqp.points.points(for: .cw), 2)
        let s = ScoreEngine.score(log: outLog([
            qso(band: .m40, mode: .cw, their: "HEN"),
            qso(band: .m40, mode: .phone, their: "HEN"),
        ]), party: mnqp)
        XCTAssertEqual(s.qsoPoints, 4, "phone and CW alike")
    }

    /// "Phone (SSB, DSB, FM, AM all count as Phone) / CW - only". A digital row
    /// is invalid rather than zero-point: no points, no multiplier, counted.
    func testDigitalIsInvalidNotZeroPoint() {
        XCTAssertEqual(mnqp.allowedModeClasses, [.phone, .cw])
        let s = ScoreEngine.score(log: outLog([
            qso(band: .m40, mode: .cw, their: "HEN"),
            qso(call: "W0DIG", band: .m20, mode: .digital, their: "RAM"),
        ]), party: mnqp)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.qsoPoints, 2, "the digital row earns nothing")
        XCTAssertEqual(s.multiplierCount, 1, "and yields no multiplier")
    }

    // MARK: Multipliers — ONCE OVERALL, the only bundled party with that on both sides

    /// "Multipliers count once overall - not once per band or mode." The Article
    /// 18 pair: a second band must add nothing (it would under `perBand`) and a
    /// second *mode* must add nothing either (it would under `perMode`).
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(mnqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(mnqp.multipliers.outState.countScope, .once)

        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", band: .m40, mode: .cw, their: "HEN"),
            qso(call: "W0A", band: .m20, mode: .cw, their: "HEN"),
            qso(call: "W0A", band: .m40, mode: .phone, their: "HEN"),
        ]), party: mnqp)
        XCTAssertEqual(s.validQSOs, 3, "workable once per band and mode")
        XCTAssertEqual(s.qsoPoints, 6)
        XCTAssertEqual(s.multiplierCount, 1,
                       "neither another band nor another mode adds a multiplier")
    }

    func testOutOfStateCeilingIs87Counties() {
        XCTAssertEqual(Set(mnqp.multipliers.outState.classes), [.county])
        let rows = mnqp.counties.enumerated().map { i, c in qso(call: "W0\(i)", their: c.abbr) }
        let s = ScoreEngine.score(log: outLog(rows), party: mnqp)
        XCTAssertEqual(s.multiplierCount, 87, "'MN counties: 87 maximum'")
    }

    /// The sponsor states its own in-state maximum, which makes it the cheapest
    /// possible verification of the whole multiplier model:
    /// "87 Minnesota counties, 49 states (does not include Minnesota), 1 District
    /// of Columbia, 10 Canadian provinces, 3 Canadian Territories, and 1 DX;
    /// **151 maximum**."
    func testInStateMaximumIsExactlyTheSponsorsStated151() {
        XCTAssertEqual(Set(mnqp.multipliers.inState.classes), [.county, .state, .province, .dx])

        var rows: [QSO] = []
        for (i, c) in mnqp.counties.enumerated() {
            rows.append(qso(call: "W0C\(i)", my: "HEN", their: c.abbr))
        }
        // 49 states + DC: every accepted state token except Minnesota's own.
        let stateTokens = MultClass.acceptedStateTokens.subtracting(["MN"]).sorted()
        XCTAssertEqual(stateTokens.count, 50, "49 states + District of Columbia")
        for (i, t) in stateTokens.enumerated() {
            rows.append(qso(call: "K\(i)ST", my: "HEN", their: t))
        }
        for (i, p) in MultClass.canadianProvinces.sorted().enumerated() {
            rows.append(qso(call: "VE\(i)P", my: "HEN", their: p))
        }
        rows.append(qso(call: "DL1XX", my: "HEN", their: "DX"))

        let s = ScoreEngine.score(log: inLog(rows), party: mnqp)
        XCTAssertEqual(s.workedValues(.county).count, 87)
        XCTAssertEqual(s.workedValues(.state).count, 50, "49 states plus DC")
        XCTAssertEqual(s.workedValues(.province).count, 13)
        XCTAssertEqual(s.workedValues(.dx).count, 1)
        XCTAssertEqual(s.multiplierCount, 151, "the sponsor's own stated maximum")
    }

    /// "Minnesota stations may work DXCC countries for points and receive **1
    /// multiplier** for working a DX station." The token style is what delivers
    /// that: every DX contact yields the single value DX, so no cap is needed.
    func testAllDXIsWorthExactlyOneMultiplier() {
        let rows = (0..<6).map { qso(call: "DL\($0)AA", my: "HEN", their: "DX") }
        let s = ScoreEngine.score(log: inLog(rows), party: mnqp)
        XCTAssertEqual(s.validQSOs, 6, "all six count for points")
        XCTAssertEqual(s.qsoPoints, 12)
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertNil(mnqp.multipliers.inState.dxMultCap, "structural, not a numeric cap")
    }

    /// "49 states (**does not include Minnesota**)" — stated outright, and in the
    /// negative, which is rare. The 2027 edition reverses exactly this.
    func testMinnesotaIsNotAStateMultiplier() {
        XCTAssertFalse(mnqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "HEN", their: "RAM")]), party: mnqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(mnqp.validOutStateTokens.contains("MN"))
    }

    /// "1 District of Columbia" is counted **separately from** the 50 states, so
    /// DC must stay itself. MNQP is the first party to count DC in its own right
    /// — VTQP and MDC both alias it.
    func testDCIsItsOwnMultiplierAndIsNotAliased() throws {
        XCTAssertEqual(mnqp.stateAliases, [:], "no alias, unlike VTQP's DC→MD")
        XCTAssertEqual(try ExchangeParser.parse("DC", party: mnqp, role: .inState).get().locations,
                       ["DC"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "HEN", their: "DC"),
            qso(call: "W3B", my: "HEN", their: "MD"),
        ]), party: mnqp)
        XCTAssertEqual(Set(s.workedValues(.state)), ["DC", "MD"], "two multipliers, not one")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// The county PDF's province table prints the standard 13 with the standard
    /// `NL` spelling ("Newfoundland & Labrador NL"). Read, not assumed.
    func testTheStandardThirteenProvinces() {
        XCTAssertEqual(mnqp.provinces, MultClass.canadianProvinces)
        XCTAssertEqual(mnqp.provinces.count, 13, "10 provinces + 3 territories")
        XCTAssertTrue(mnqp.validOutStateTokens.contains("NL"))
        XCTAssertFalse(mnqp.validOutStateTokens.contains("NF"))
    }

    // MARK: County lines are FORBIDDEN

    /// "No station may claim simultaneous operation in more than one county,
    /// state, or province." Only the second party after ALQP to forbid it.
    func testCountyLineOperationIsRejected() throws {
        XCTAssertEqual(mnqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            try ExchangeParser.parse("AIT", party: mnqp, role: .inState).get().locations, ["AIT"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("AIT/ANO", party: mnqp, role: .inState),
            .failure(.tooManyCounties(2)),
            "the sponsor forbids simultaneous operation in two counties"
        )
    }

    /// "Mobile or rover stations that change geographic area … are considered to
    /// be a new station and may be contacted again for QSO points and multiplier
    /// credit." Sequential county changes are fine — it is the *simultaneous*
    /// claim that is forbidden.
    func testMobileChangingCountyIsANewQSOAndANewMultiplier() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0AA", band: .m40, mode: .cw, their: "DAK"),
            qso(call: "W0AA", band: .m40, mode: .cw, their: "HEN"),
        ]), party: mnqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Dupes

    func testDupesAreOncePerBandPerMode() {
        let a = qso(call: "W0M", band: .m40, mode: .cw, their: "RAM")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let s = ScoreEngine.score(log: outLog([a, repeated]), party: mnqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 1)
    }

    // MARK: Exchange — a name and a location, and no signal report at all

    /// "MN Stations: First name & county… W/VE Stations: First name and state /
    /// province… DX Stations: First name only." MNQP is the second party after
    /// MDC to carry no signal report, and the first to replace it with a name.
    func testExchangeCarriesNoSignalReport() {
        XCTAssertFalse(mnqp.exchangeIncludesRST)
        XCTAssertFalse(mnqp.exchangeIncludesSerial)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("hen", party: mnqp, role: .inState).get().locations,
                       ["HEN"])
        XCTAssertEqual(try ExchangeParser.parse("STL", party: mnqp, role: .inState).get().locations,
                       ["STL"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: mnqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("ON", party: mnqp, role: .inState).get().locations,
                       ["ON"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: mnqp, role: .inState).get().locations,
                       ["DX"], "the literal token, not a prefix")
        guard case .failure = ExchangeParser.parse("MN", party: mnqp, role: .inState) else {
            return XCTFail("MN must be rejected — Minnesota stations send a county")
        }
    }

    /// KNOWN LIMITATION 1, closed 2026-07-27. The name half of the exchange
    /// was the one gap that blocked submission — `QSO` had no name field and
    /// the ex1 column exported empty. Name exchanges (forced in by the NAQP
    /// pair) closed it: the flag is on, the received name gates logging, and
    /// Cabrillo writes the sponsor's own template (`AC0W BILL MOW`).
    func testTheNameHalfOfTheExchangeIsLoggedAndExported() throws {
        XCTAssertTrue(mnqp.exchangeIncludesName)
        XCTAssertFalse(mnqp.exchangeIncludesRST, "a name and a location, nothing else")

        let notes = try XCTUnwrap(mnqp.notes)
        XCTAssertFalse(notes.contains("KNOWN LIMITATION"),
                       "the export blocker is closed; only the archive question remains")
        XCTAssertTrue(notes.contains("NAME EXCHANGES LANDED 2026-07-27"),
                      "Article 20: the caveat's disappearance must read as a fix")
        XCTAssertFalse(mnqp.caveats.contains { $0.kind == .exportBlocking })

        let named = QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_000_000),
            call: "W0AA", band: .m20, modeClass: .cw, rawMode: "CW",
            rstSent: "", rstRcvd: "",
            nameSent: "TOM", nameRcvd: "BILL",
            myLoc: "TX", theirLoc: "DAK"
        )
        let fields = CabrilloExporter.qsoLine(named, myCall: "KE5CW",
                                              contest: try PartyLowering.lower(mnqp),
                                              side: PartyLowering.outsideID)
            .split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(6)), ["KE5CW", "TOM", "TX", "W0AA", "BILL", "DAK"],
                       "the sponsor's template: name in ex1, ahead of the location")
    }

    /// "MN stations work everyone; all other W/VE & DX work MN stations."
    func testOutOfStateEntrantsGetNoCreditForNonMinnesotaContacts() {
        XCTAssertTrue(mnqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W0A", their: "HEN"),
            qso(call: "K5B", their: "TX"),
        ]), party: mnqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — ten hours, one Saturday

    func testScheduleIsOneTenHourSaturdayWindow() throws {
        let windows = try XCTUnwrap(mnqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-02-07T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-02-08T00:00:00Z"),
                       "'through 2359 UTC' includes that minute; the main page says 2400Z")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 10 * 3600)

        // "always the first Saturday in February": 7 February 2026.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 7)
        XCTAssertEqual(utc.component(.month, from: windows[0].start), 2)
        XCTAssertEqual(utc.component(.year, from: windows[0].start), 2026)
    }

    // MARK: Article 20 — the shipped rules are 2026's, not the live 2027 ones

    /// w0aa.org now serves only `MNQP_2027_Contest_Rules_A.pdf`, which flags four
    /// of its own changes as "NEW 2027". Every assertion here is a value the 2027
    /// edition changes, so applying that document by accident turns this test
    /// red instead of silently rescoring the party. The full diff is in
    /// docs/research/mnqp_rules.md §14.
    func testTheShippedRulesAreThe2026OnesNotThe2027Ones() throws {
        XCTAssertEqual(mnqp.points.points(for: .cw), 2, "2027 raises CW to 3")
        XCTAssertEqual(mnqp.multipliers.inState.countScope, .once, "2027 moves to perMode")
        XCTAssertEqual(mnqp.multipliers.outState.countScope, .once, "2027 moves to perMode")
        XCTAssertTrue(mnqp.multipliers.inState.classes.contains(.county),
                      "2027 stops counting MN counties for MN stations")
        XCTAssertFalse(mnqp.multipliers.inState.homeStateCountsViaCounty,
                       "2027 starts including Minnesota among the states")
        XCTAssertEqual(mnqp.maxSimultaneousCounties, 1, "2027 lets rovers claim 2")

        let notes = try XCTUnwrap(mnqp.notes)
        XCTAssertTrue(notes.contains("Rev 31"), "the edition must be named in the notes")
        XCTAssertTrue(notes.contains("NO LONGER PUBLISHES THE 2026 RULES"))
    }

    /// One open question remains — the archive provenance — and it is the
    /// whole reason the party is still `verified: partial`. The name gap that
    /// used to be question (1) closed 2026-07-27 and is recorded as prose,
    /// not as a marked item, so it cannot re-raise the alert it resolves.
    func testNotesRecordTheOneRemainingOpenQuestion() throws {
        let notes = try XCTUnwrap(mnqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        let questions = try XCTUnwrap(mnqp.openQuestions)
        XCTAssertTrue(questions.contains("web archive"))
        XCTAssertTrue(questions.contains("mnqp-committee@w0aa.org"))
        XCTAssertEqual(mnqp.operatorAlerts.count, 1, "\(mnqp.operatorAlerts)")
    }
}

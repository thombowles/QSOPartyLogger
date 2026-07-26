import XCTest
@testable import QSOPartyLogger

/// British Columbia QSO Party — Orca DX and Contest Club. Built from the
/// sponsor's own 2026 rules page (footer "Updated: Feb. 5, 2026 VA7ST"), its
/// official multiplier list, its FAQ and its score summary sheet, all read
/// verbatim 2026-07-26. See docs/research/bcqp_rules.md.
///
/// **The first non-US party in this repo.** British Columbia has no counties, so
/// the county class carries the 43 federal electoral districts. Three of this
/// party's rules exist *only* in the FAQ, and each would be a scoring error if
/// missed — see `testDXEarnsPointsButNoMultiplier`,
/// `testThereIsNoPowerMultiple` and `testDistrictLineOperationIsRejected`.
final class BritishColumbiaQSOPartyTests: XCTestCase {

    var bcqp: PartyDefinition!

    override func setUpWithError() throws {
        bcqp = try XCTUnwrap(PartyCatalog.party(id: "bcqp"), "bundled BCQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "VA7ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "VAC"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_485_400 + seq),  // 2026-02-07 17:30Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "bcqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from district: String = "VAC") -> ContestLog {
        var log = ContestLog(partyID: "bcqp")
        log.myLocation = .inState(counties: [district])
        log.qsos = qsos
        return log
    }

    // MARK: District data — 43, and the list is new for 2026

    func testDistrictData() {
        XCTAssertEqual(bcqp.counties.count, 43, "the 2025 redistribution gave BC 43 districts")
        XCTAssertEqual(Set(bcqp.counties.map(\.abbr)).count, 43)
        XCTAssertEqual(Set(bcqp.counties.map(\.name)).count, 43)
        XCTAssertEqual(bcqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// The worst trap in the list is a near-anagram: both codes are built from a
    /// K-word and both districts end in "Rockies".
    func testTheAnagramPairCKSAndKSC() {
        XCTAssertEqual(bcqp.county(for: "CKS")?.name, "Columbia-Kootenay-Southern Rockies")
        XCTAssertEqual(bcqp.county(for: "KSC")?.name, "Kamloops-Shuwswap-Central Rockies")
        XCTAssertEqual(bcqp.county(for: "KTN")?.name, "Kamloops-Thompson-Nicola",
                       "the second Kamloops district")
    }

    /// Three sponsor spellings that are wrong as place names and right as data.
    /// Pinned so nobody "corrects" them: Shuswap is printed *Shuwswap*, Okanagan
    /// is printed *Okangan*, and Richmond Center takes the US spelling even
    /// though the same list writes Surrey *Centre*.
    func testTheSponsorsOwnMisspellingsSurvive() {
        XCTAssertEqual(bcqp.county(for: "KSC")?.name.contains("Shuwswap"), true)
        XCTAssertEqual(bcqp.county(for: "SSW")?.name, "Similkameen-South Okangan-West Kootenay")
        XCTAssertEqual(bcqp.county(for: "RCM")?.name, "Richmond Center-Marpole")
        XCTAssertEqual(bcqp.county(for: "SUC")?.name, "Surrey Centre",
                       "the sponsor is inconsistent with itself, and both ship as printed")
    }

    /// Dense clusters where the naive abbreviation belongs to nobody.
    func testClusteredCodes() {
        XCTAssertEqual(bcqp.county(for: "SUN")?.name, "Surrey Newton")
        XCTAssertEqual(bcqp.county(for: "SWR")?.name, "South Surrey-White Rock")
        XCTAssertEqual(bcqp.county(for: "BUC")?.name, "Burnaby Central")
        XCTAssertEqual(bcqp.county(for: "BNS")?.name, "Burnaby North-Seymour")
        XCTAssertEqual(bcqp.county(for: "VAC")?.name, "Vancouver Centre")
        XCTAssertEqual(bcqp.county(for: "VAQ")?.name, "Vancouver Quadra")
        XCTAssertEqual(bcqp.county(for: "VSB")?.name, "Vancouver Fraserview-South Burnaby")
        XCTAssertEqual(bcqp.county(for: "vic")?.name, "Victoria", "case-insensitive")
        for absent in ["VAN", "BUR", "SUR", "KAM"] {
            XCTAssertNil(bcqp.county(for: absent), "\(absent) is not a district code")
        }
    }

    /// `NWB` is the retired code the sponsor's **own Cabrillo sample** still
    /// shows, because the sample predates the 2025 redistribution. It is the
    /// reason a stale district list is this party's obvious failure mode.
    func testTheRetiredCodeInTheSponsorsOwnSampleIsNotADistrict() {
        XCTAssertNil(bcqp.county(for: "NWB"),
                     "NWB is pre-2025 — the sample log was never regenerated")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(bcqp.cabrilloContest, "BC-QSO-PARTY",
                       "printed by the sponsor itself, not taken from WA7BNM")
        XCTAssertEqual(bcqp.homeState, "BC", "a province, and the schema is content with that")
        XCTAssertEqual(bcqp.allowedModeClasses, [.phone, .cw], "'Contest modes: Phone and CW'")
        XCTAssertEqual(bcqp.dxStyle, .token)
        XCTAssertTrue(bcqp.exchangeIncludesRST)
        XCTAssertFalse(bcqp.exchangeIncludesSerial)
        XCTAssertTrue(bcqp.isPartiallyVerified)
    }

    func testSixHFBandsOnly() {
        XCTAssertEqual(bcqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10])
        for excluded in [Band.m60, .m30, .m17, .m12, .m6, .m2, .cm125, .cm70] {
            XCTAssertFalse(bcqp.validBands.contains(excluded), "\(excluded.rawValue) excluded")
        }
    }

    // MARK: Points — CW at 4 is the highest in the repo

    func testPointsByMode() {
        XCTAssertEqual(bcqp.points.points(for: .phone), 2)
        XCTAssertEqual(bcqp.points.points(for: .cw), 4, "the highest CW value of any party here")
    }

    func testDigitalIsInvalidNotZeroPoint() {
        let s = ScoreEngine.score(log: outLog([
            qso(band: .m20, mode: .cw, their: "VAC"),
            qso(call: "VA7DIG", band: .m40, mode: .digital, their: "DEL"),
        ]), party: bcqp)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.qsoPoints, 4)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Multipliers — once per band AND mode

    /// "Multipliers can be counted only once per band and mode. Example: A mixed
    /// mode op can count DEL on CW 20 and Phone 20 as well as CW 40 and Phone
    /// 40, etc." — the sponsor's own example, reproduced.
    func testTheSponsorsOwnPerBandModeExample() {
        XCTAssertEqual(bcqp.multipliers.outState.countScope, .perBandMode)
        XCTAssertEqual(bcqp.multipliers.inState.countScope, .perBandMode)

        let s = ScoreEngine.score(log: outLog([
            qso(call: "VA7D", band: .m20, mode: .cw, their: "DEL"),
            qso(call: "VA7D", band: .m20, mode: .phone, their: "DEL"),
            qso(call: "VA7D", band: .m40, mode: .cw, their: "DEL"),
            qso(call: "VA7D", band: .m40, mode: .phone, their: "DEL"),
        ]), party: bcqp)
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.multiplierCount, 4, "one district, four band/mode slots")
        XCTAssertEqual(s.qsoPoints, 12, "CW 4 + phone 2, twice")
    }

    /// The Article 18 pair, stated the other way round: the *same* band and mode
    /// again must add nothing, so `perBandMode` is not silently behaving like a
    /// per-QSO count.
    func testSameBandAndModeAgainAddsNoMultiplier() {
        let a = qso(call: "VA7D", band: .m20, mode: .cw, their: "DEL")
        var later = a
        later.id = UUID()
        later.call = "VA7E"
        later.timestampUTC = a.timestampUTC.addingTimeInterval(1800)
        let s = ScoreEngine.score(log: outLog([a, later]), party: bcqp)
        XCTAssertEqual(s.validQSOs, 2, "two different stations in the same district")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfProvinceCeilingIs43PerBandPerMode() {
        XCTAssertEqual(Set(bcqp.multipliers.outState.classes), [.county])
        let rows = bcqp.counties.enumerated().map { i, c in qso(call: "VA7\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: bcqp).multiplierCount, 43)

        let bothModes = rows + bcqp.counties.enumerated().map { i, c in
            qso(call: "VA7\(i)", mode: .phone, their: c.abbr)
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(bothModes), party: bcqp).multiplierCount, 86,
                       "43 × 2 modes on one band; the full ceiling is 43 × 6 × 2 = 516")
    }

    /// **This rule appears only in the FAQ**, not on the rules page: "DX contacts
    /// are worth QSO points but do not provide a multiplier." Missing it would
    /// give a BC entrant a phantom multiplier on every band and mode.
    func testDXEarnsPointsButNoMultiplier() {
        XCTAssertFalse(bcqp.multipliers.inState.classes.contains(.dx))
        XCTAssertFalse(bcqp.multipliers.outState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "JA1ABC", my: "VAC", their: "DX"),
            qso(call: "DL1ABC", band: .m40, my: "VAC", their: "DX"),
        ]), party: bcqp)
        XCTAssertEqual(s.validQSOs, 2, "both count for points")
        XCTAssertEqual(s.qsoPoints, 8)
        XCTAssertEqual(s.multiplierCount, 0, "and neither multiplies anything")
    }

    func testInProvinceCountsDistrictsStatesAndProvinces() {
        XCTAssertEqual(Set(bcqp.multipliers.inState.classes), [.county, .state, .province])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "VA7A", my: "VAC", their: "DEL"),
            qso(call: "K5B", my: "VAC", their: "TX"),
            qso(call: "VE3C", my: "VAC", their: "ON"),
        ]), party: bcqp)
        XCTAssertEqual(s.workedValues(.county), ["DEL"])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.multiplierCount, 3)
    }

    /// "Note: In BCQP, Alaska and Hawaii are 'states' rather than 'DX'." The
    /// sponsor says it twice, and it is the opposite of most parties' treatment
    /// of KH6/KL7 as separate DXCC entities.
    func testAlaskaAndHawaiiAreStatesNotDX() throws {
        for token in ["AK", "HI"] {
            XCTAssertEqual(
                try ExchangeParser.parse(token, party: bcqp, role: .inState).get().locations,
                [token]
            )
        }
        let s = ScoreEngine.score(log: inLog([
            qso(call: "KL7A", my: "VAC", their: "AK"),
            qso(call: "KH6B", my: "VAC", their: "HI"),
        ]), party: bcqp)
        XCTAssertEqual(Set(s.workedValues(.state)), ["AK", "HI"])
        XCTAssertEqual(s.workedValues(.dx), [], "not DX here")
    }

    /// "Maryland and DC are lumped together as MD" — and the sponsor's own state
    /// table has 50 rows with no DC row at all.
    func testDCIsLumpedIntoMaryland() throws {
        XCTAssertEqual(bcqp.stateAliases, ["DC": "MD"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: bcqp, role: .inState).get().locations,
                       ["DC"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "VAC", their: "DC"),
            qso(call: "W3B", my: "VAC", their: "MD"),
        ]), party: bcqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "one multiplier, not two")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// The province list is the standard 13 **less BC**, because a BC station
    /// always sends a district and can never send the token `BC`. Left to the
    /// default, `BC` would be loggable: `validOutStateTokens` unions `provinces`
    /// in *after* subtracting `excludedStateTokens`, so excluding the home
    /// region cannot remove it. See bcqp_rules.md §6 — this is open question 1.
    func testProvincesAreTheStandardThirteenLessBritishColumbia() {
        XCTAssertEqual(bcqp.provinces.count, 12)
        XCTAssertEqual(bcqp.provinces, MultClass.canadianProvinces.subtracting(["BC"]))
        XCTAssertFalse(bcqp.validOutStateTokens.contains("BC"),
                       "no BC station can send it, so it must not be loggable")
        XCTAssertTrue(bcqp.validOutStateTokens.contains("NL"))
        XCTAssertFalse(bcqp.multipliers.inState.homeStateCountsViaCounty)
    }

    // MARK: The bonus station, and where it lands in the formula

    /// "Any QSO with the Orca DXCC station, VA7ODX, will be worth an additional
    /// 20 points… added after calculating QSO points and location multipliers",
    /// and the FAQ's "Each QSO… (5 x 20)" fixes the scope at per-QSO.
    ///
    /// This case is arithmetic all the way through: VA7ODX in Delta worked on
    /// three bands in both modes is 6 QSOs, 6 multipliers (per band *and* mode),
    /// 3×4 + 3×2 = 18 QSO points, and 6 × 20 = 120 bonus —
    /// (18 × 6) + 120 = **228**.
    func testVA7ODXPaysTwentyPerQSOAfterMultiplying() {
        XCTAssertEqual(bcqp.bonuses, [.workStation(call: "VA7ODX", points: 20, scope: .perQSO)])

        var rows: [QSO] = []
        for band in [Band.m20, .m40, .m80] {
            rows.append(qso(call: "VA7ODX", band: band, mode: .cw, their: "DEL"))
            rows.append(qso(call: "VA7ODX", band: band, mode: .phone, their: "DEL"))
        }
        let s = ScoreEngine.score(log: outLog(rows), party: bcqp)
        XCTAssertEqual(s.validQSOs, 6)
        XCTAssertEqual(s.multiplierCount, 6, "one district × 3 bands × 2 modes")
        XCTAssertEqual(s.qsoPoints, 18, "3 × CW 4 + 3 × phone 2")
        XCTAssertEqual(s.bonusPoints, 120, "20 per QSO, not once")
        XCTAssertEqual(s.total, 228, "(QSO points × multipliers) + bonus — the sponsor's formula")
    }

    /// "There is no power multiple." — FAQ, and the only place it is said.
    func testThereIsNoPowerMultiple() {
        XCTAssertNil(bcqp.scoreMultipliers)
        let s = ScoreEngine.score(log: outLog([qso(their: "VAC")]), party: bcqp)
        XCTAssertEqual(s.categoryFactor, 1)
    }

    // MARK: No mobile or rover category, so no district lines

    /// "Is there a mobile or rover category? No." — the sponsor removes the
    /// category rather than forbidding the practice, which comes to the same
    /// thing: no station may claim two districts at once.
    func testDistrictLineOperationIsRejected() throws {
        XCTAssertEqual(bcqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            try ExchangeParser.parse("VAC", party: bcqp, role: .inState).get().locations, ["VAC"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("VAC/VAE", party: bcqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
    }

    // MARK: Exchange and scope of credit

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("del", party: bcqp, role: .inState).get().locations,
                       ["DEL"])
        XCTAssertEqual(try ExchangeParser.parse("CKS", party: bcqp, role: .inState).get().locations,
                       ["CKS"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: bcqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: bcqp, role: .inState).get().locations,
                       ["DX"])
        guard case .failure = ExchangeParser.parse("BC", party: bcqp, role: .inState) else {
            return XCTFail("BC must be rejected — British Columbia stations send a district")
        }
    }

    /// "Stations outside British Columbia to work only BC stations in the 43 BC
    /// Federal Electoral Districts. Stations in BC to work anyone, anywhere."
    func testOutOfProvinceEntrantsGetNoCreditForNonBCContacts() {
        XCTAssertTrue(bcqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "VA7A", their: "VAC"),
            qso(call: "K5B", their: "TX"),
        ]), party: bcqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — two segments totalling the sponsor's stated 20 hours

    func testScheduleIsTwoSegmentsTotallingTwentyHours() throws {
        let windows = try XCTUnwrap(bcqp.schedule)
        XCTAssertEqual(windows.count, 2, "two segments with a gap you may not operate in")
        let f = ISO8601DateFormatter()

        XCTAssertEqual(windows[0].start, f.date(from: "2026-02-07T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-02-08T04:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600,
                       "the sponsor states twelve hours")

        XCTAssertEqual(windows[1].start, f.date(from: "2026-02-08T16:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-02-09T00:00:00Z"))
        XCTAssertEqual(windows[1].end.timeIntervalSince(windows[1].start), 8 * 3600,
                       "…and eight for the second")

        let total = windows.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        XCTAssertEqual(total, 20 * 3600, "'Participants may operate all 20 hours of the contest'")
        XCTAssertEqual(windows[1].start.timeIntervalSince(windows[0].end), 12 * 3600,
                       "a twelve-hour gap — the second segment is NOT 'Feb. 2, 2025' as the "
                           + "rules' own sentence mistypes it")

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.weekday, from: windows[1].start), 1, "Sunday")
        XCTAssertEqual(utc.component(.day, from: windows[1].start), 8)
    }

    func testNotesRecordTheLimitationAndTheOpenQuestion() throws {
        let notes = try XCTUnwrap(bcqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("BRITISH COLUMBIA HAS NO COUNTIES"))
        XCTAssertTrue(notes.contains("DX CONTACTS EARN POINTS BUT NO MULTIPLIER"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION"), "the ADIF county-field shape")
        let questions = try XCTUnwrap(bcqp.openQuestions)
        XCTAssertTrue(questions.contains("NO BC STATION CAN EVER SEND THE TOKEN 'BC'"))
        XCTAssertTrue(questions.contains("va7bec@gmail.com"))
    }
}

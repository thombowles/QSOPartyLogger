import XCTest
@testable import QSOPartyLogger

/// Vermont QSO Party — Radio Amateurs of Northern Vermont. Built from the
/// sponsor's OFFICIAL 2026 rules document (ranv.org/vtqso.doc, footer
/// 13-JAN-2026), with the summary page for county names. Read verbatim
/// 2026-07-26. See docs/research/vtqp_rules.md.
///
/// The opening party of the 2026 season, and a party of extremes: the longest
/// window (48 hours), the smallest county list (14), the highest CW value (3),
/// and the first fractional power multiplier in the repo — which is exactly why
/// it ships without one.
final class VermontQSOPartyTests: XCTestCase {

    var vtqp: PartyDefinition!

    override func setUpWithError() throws {
        vtqp = try XCTUnwrap(PartyCatalog.party(id: "vtqp"), "bundled VTQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W1ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "CHI"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_770_422_400 + seq),  // 2026-02-07
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    /// Both helpers default to **high power**, whose factor is ×1, so that every
    /// test about points, multipliers or dupes measures what it is about. Rule 4
    /// makes it the sponsor's own default too: *"Logs not showing power output
    /// category will be listed as high power."*
    func outLog(
        _ qsos: [QSO],
        power: StationProfile.CategoryPower = .high
    ) -> ContestLog {
        var log = ContestLog(partyID: "vtqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(
        _ qsos: [QSO],
        from county: String = "CHI",
        power: StationProfile.CategoryPower = .high
    ) -> ContestLog {
        var log = ContestLog(partyID: "vtqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    // MARK: County data — 14, the smallest list in the repo

    func testCountyData() {
        XCTAssertEqual(vtqp.counties.count, 14, "Vermont has 14 counties")
        XCTAssertEqual(Set(vtqp.counties.map(\.abbr)).count, 14)
        XCTAssertEqual(Set(vtqp.counties.map(\.name)).count, 14)
        XCTAssertEqual(vtqp.countyAbbrLengths, [3], "uniformly 3 letters")
        XCTAssertEqual(vtqp.countyAbbrLengthHint, "3")
    }

    /// The sponsor names its own worst trap: "Take care to not mix up WiNdHam
    /// (WNH) and WiNdSor (WNS)!!" Neither is the naive WIN, and getting it wrong
    /// costs the QSO and — under rule 7(C) — the multiplier with it.
    func testWindhamAndWindsorAreTheTrapTheRulesThemselvesName() {
        XCTAssertEqual(vtqp.county(for: "WNH")?.name, "Windham")
        XCTAssertEqual(vtqp.county(for: "WNS")?.name, "Windsor")
        XCTAssertNil(vtqp.county(for: "WIN"), "the naive abbreviation belongs to neither")
        XCTAssertNil(vtqp.county(for: "WND"))
    }

    /// GRA is Grand Isle. The page's KI1P operating schedule says "Grand
    /// Island/Chittenden Co."; the county table says GRAND ISLE. Pinned so the
    /// schedule's loose prose is never mistaken for a correction.
    func testGrandIsleIsNotGrandIsland() {
        XCTAssertEqual(vtqp.county(for: "GRA")?.name, "Grand Isle")
        XCTAssertFalse(vtqp.counties.contains { $0.name.contains("Island") })
    }

    func testTheOtherAbbreviationsWorthChecking() {
        // ORA/ORL differ by one letter and are adjacent in the list.
        XCTAssertEqual(vtqp.county(for: "ORA")?.name, "Orange")
        XCTAssertEqual(vtqp.county(for: "ORL")?.name, "Orleans")
        XCTAssertEqual(vtqp.county(for: "CAL")?.name, "Caledonia")
        XCTAssertEqual(vtqp.county(for: "CHI")?.name, "Chittenden")
        XCTAssertEqual(vtqp.county(for: "LAM")?.name, "Lamoille")
        XCTAssertEqual(vtqp.county(for: "ESS")?.name, "Essex")
        XCTAssertEqual(vtqp.county(for: "chi")?.name, "Chittenden", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(vtqp.cabrilloContest, "VT-QSO-PARTY", "WA7BNM 236; sponsor prints none")
        XCTAssertEqual(vtqp.homeState, "VT")
        XCTAssertEqual(vtqp.allowedModeClasses, ModeClass.allCases,
                       "'Entrants may use any combination of modes'")
        XCTAssertEqual(vtqp.dxStyle, .prefix,
                       "DX sends a report only, but the logged exchange carries the DXCC prefix")
        XCTAssertTrue(vtqp.exchangeIncludesRST)
        XCTAssertFalse(vtqp.exchangeIncludesSerial)
        XCTAssertTrue(vtqp.isPartiallyVerified)
    }

    /// Rule 7(D)(1), and the first fractional factor in the repo:
    ///
    /// > "If all QSO's were made using 5W or less, multiply your score by 2 · If
    /// > all QSO's were made using more than 5W and less than or equal to 150W
    /// > output, multiply your score by 1.5 · If any or all QSO's were made
    /// > using more than 150W, multiply your score by 1"
    func testThePowerMultiplierShipsIncludingItsHalf() throws {
        let mults = try XCTUnwrap(vtqp.scoreMultipliers)
        XCTAssertEqual(mults.factor(power: .qrp, station: .fixed), 2)
        XCTAssertEqual(mults.factor(power: .high, station: .fixed), 1)
        XCTAssertEqual(mults.factor(power: .low, station: .fixed),
                       ScoreFactor(numerator: 3, denominator: 2), "×1.5, exactly")
    }

    /// Applied, not merely stored. Four CW QSOs in four counties: 12 QSO points
    /// × 4 multipliers = 48, and low power takes that to 72.
    func testTheLowPowerHalfReachesTheScore() {
        let rows = ["CHI", "ADD", "BEN", "CAL"].enumerated().map {
            qso(call: "W1\($0.offset)", their: $0.element)
        }
        let high = ScoreEngine.score(log: outLog(rows, power: .high), party: vtqp)
        XCTAssertEqual(high.qsoPoints, 12, "4 CW QSOs at 3 points")
        XCTAssertEqual(high.multiplierCount, 4)
        XCTAssertEqual(high.total, 48)

        let low = ScoreEngine.score(log: outLog(rows, power: .low), party: vtqp)
        XCTAssertEqual(low.total, 72, "48 × 1.5")

        let qrp = ScoreEngine.score(log: outLog(rows, power: .qrp), party: vtqp)
        XCTAssertEqual(qrp.total, 96, "48 × 2")
    }

    /// **The sponsor states no rounding rule for the final score.** Its only
    /// rounding instruction anywhere is rule 7(B)(f), on a fractional multiplier
    /// count: *"dividing by 3, and rounding down"*. One CW QSO — 3 points ×
    /// 1 multiplier — lands a low-power entrant on 4.5, and this app rounds it
    /// down, which is both the sponsor's own idiom and the direction that cannot
    /// overstate a `CLAIMED-SCORE:`.
    func testAHalfPointIsRoundedDownAsTheSponsorRoundsItsOwnFractions() {
        let s = ScoreEngine.score(log: outLog([qso(mode: .cw)], power: .low), party: vtqp)
        XCTAssertEqual(s.qsoPoints, 3, "CW is 3 points, the highest of any bundled party")
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.total, 4, "3 × 1 × 1.5 = 4.5 → 4, never 5")
    }

    /// KNOWN LIMITATION 1, pinned — and the reason it is an *inference* rather
    /// than a gap. Rule 1A(F) calls the W1AW/1 credit "an additional 2 point
    /// bonus", which reads as QSO points, but rule 7(D)'s formula names only
    /// "Total Points X Total Multipliers X Power Multiplier" and the bonus lives
    /// in section 1A rather than section 7. This app adds it last, so it is
    /// scaled by neither the multipliers nor the power factor.
    func testTheW1AWBonusIsAddedAfterThePowerFactorRatherThanInsideIt() throws {
        let rows = [qso(call: "W1AW/1", their: "CHI")]
        let low = ScoreEngine.score(log: outLog(rows, power: .low), party: vtqp)

        XCTAssertEqual(low.bonusPoints, 2, "rule 1A(F): 2 points per W1AW/1 QSO")
        XCTAssertEqual(low.qsoPoints, 3)
        XCTAssertEqual(low.multiplierCount, 1)
        XCTAssertEqual(low.total, 6, "⌊3 × 1 × 1.5⌋ = 4, + 2 unscaled — not (3 + 2) × 1.5 = 7")
        XCTAssertTrue(try XCTUnwrap(vtqp.notes).contains("KNOWN LIMITATION 1"))
    }

    /// No band list is published — rule 8 gives one prohibition and one blanket
    /// permission. 30/17/12 are IN because the sponsor explicitly allows FT8/FT4
    /// there and `validBands` is not mode-scoped; 60 m is OUT as an open question.
    func testThirteenBandsDerivedFromAProhibitionRatherThanAList() throws {
        XCTAssertEqual(vtqp.validBands,
                       [.m160, .m80, .m40, .m30, .m20, .m17, .m15, .m12, .m10,
                        .m6, .m2, .cm125, .cm70])
        for warc in [Band.m30, .m17, .m12] {
            XCTAssertTrue(vtqp.validBands.contains(warc),
                          "\(warc.rawValue) is allowed for FT8/FT4 — KNOWN LIMITATION 4")
        }
        for vhf in [Band.m6, .m2, .cm125, .cm70] {
            XCTAssertTrue(vtqp.validBands.contains(vhf), "'VHF and UHF frequencies are allowed'")
        }
        XCTAssertFalse(vtqp.validBands.contains(.m60), "60 m is excluded — open question 2")
        XCTAssertTrue(try XCTUnwrap(vtqp.openQuestions).contains("60 m"))
    }

    // MARK: Points — CW at 3 is the highest in the repo

    func testPointsByMode() {
        XCTAssertEqual(vtqp.points.points(for: .phone), 1)
        XCTAssertEqual(vtqp.points.points(for: .cw), 3, "'CW contact is worth 3 points'")
        XCTAssertEqual(vtqp.points.points(for: .digital), 2,
                       "RTTY and WSJT-X both pay 2, so one mode class loses no accuracy")
        XCTAssertNil(vtqp.homeStationPoints, "points are by mode, not by who was worked")
    }

    /// Every mode class is legal here, so unlike ALQP/OhQP/COQP there is no
    /// invalid-mode case to assert — asserted explicitly so the absence is
    /// deliberate rather than an omission.
    func testNoModeIsInvalidInThisParty() {
        let s = ScoreEngine.score(log: outLog([
            qso(band: .m40, mode: .phone, their: "CHI"),
            qso(band: .m40, mode: .cw, their: "CHI"),
            qso(band: .m40, mode: .digital, their: "CHI"),
        ]), party: vtqp)
        XCTAssertEqual(s.invalidModeCount, 0)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 6, "1 + 3 + 2")
    }

    // MARK: Multipliers — once per mode, on BOTH sides

    /// "A multiplier can be counted only once per mode, regardless of the number
    /// of bands on which it is worked." The two halves of this test are the
    /// Article 18 pair: a second *band* must not add a multiplier (it would under
    /// `perBand`), and a second *mode* must (it would not under `once`).
    func testOutOfStateCountsCountiesOncePerMode() {
        XCTAssertEqual(vtqp.multipliers.outState.countScope, .perMode)
        XCTAssertEqual(Set(vtqp.multipliers.outState.classes), [.county])

        let secondBand = ScoreEngine.score(log: outLog([
            qso(call: "W1A", band: .m40, mode: .cw, their: "CHI"),
            qso(call: "W1A", band: .m20, mode: .cw, their: "CHI"),
        ]), party: vtqp)
        XCTAssertEqual(secondBand.validQSOs, 2)
        XCTAssertEqual(secondBand.multiplierCount, 1, "a second band adds no multiplier")

        let secondMode = ScoreEngine.score(log: outLog([
            qso(call: "W1A", band: .m40, mode: .cw, their: "CHI"),
            qso(call: "W1A", band: .m40, mode: .phone, their: "CHI"),
        ]), party: vtqp)
        XCTAssertEqual(secondMode.multiplierCount, 2, "the same county in a second mode does")
    }

    func testInStateCountsEverythingOncePerMode() {
        XCTAssertEqual(vtqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(Set(vtqp.multipliers.inState.classes), [.county, .state, .province, .dx])

        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", my: "CHI", their: "WNH"),
            qso(call: "K5B", my: "CHI", their: "TX"),
            qso(call: "VE3C", my: "CHI", their: "ON"),
            qso(call: "DL1D", my: "CHI", their: "DL"),
        ]), party: vtqp)
        XCTAssertEqual(s.workedValues(.county), ["WNH"])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["DL"])
        XCTAssertEqual(s.multiplierCount, 4)
    }

    func testOutOfStateCeilingIsFourteenCountiesPerMode() {
        let rows = vtqp.counties.enumerated().map { i, c in qso(call: "W1\(i)", their: c.abbr) }
        let s = ScoreEngine.score(log: outLog(rows), party: vtqp)
        XCTAssertEqual(s.multiplierCount, 14, "every county, once, on CW")

        let bothModes = rows + vtqp.counties.enumerated().map { i, c in
            qso(call: "W1\(i)", mode: .phone, their: c.abbr)
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(bothModes), party: vtqp).multiplierCount, 28,
                       "and again on phone — 'only once per mode'")
    }

    /// No DX cap is stated on either side, unlike ILQP's 5 and PAQP's 1.
    func testNoDXCapOnEitherSide() {
        XCTAssertNil(vtqp.multipliers.inState.dxMultCap)
        XCTAssertNil(vtqp.multipliers.outState.dxMultCap)
        let prefixes = ["DL", "JA", "G", "F", "I", "EA", "PY"]
        let rows = prefixes.enumerated().map { i, p in
            qso(call: "\(p)1AA\(i)", my: "CHI", their: p)
        }
        let s = ScoreEngine.score(log: inLog(rows), party: vtqp)
        XCTAssertEqual(s.multiplierCount, 7, "every entity multiplies")
    }

    /// Vermont stations send a county, so the token VT is never received, and no
    /// rule says a VT county also yields the VT state multiplier. Open question 1.
    func testVermontIsNotAStateMultiplier() {
        XCTAssertFalse(vtqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "CHI", their: "WNS")]), party: vtqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(vtqp.validOutStateTokens.contains("VT"))
    }

    /// "13 Canadian Provinces and Territories (per RAC listing): AB, BC, MB, NB,
    /// NL, NS, NT, NU, ON, PE, QC, SK, YT" — the standard 13 with the standard
    /// NL spelling. Read rather than assumed: OhQP counts 11, NJQP spells it NF,
    /// MEQP splits NF/LB. VTQP is the control case.
    func testTheStandardThirteenProvincesWithNL() {
        XCTAssertEqual(vtqp.provinces, MultClass.canadianProvinces)
        XCTAssertEqual(vtqp.provinces.count, 13)
        for p in ["AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT"] {
            XCTAssertTrue(vtqp.validOutStateTokens.contains(p), "\(p) must be loggable")
        }
        XCTAssertFalse(vtqp.validOutStateTokens.contains("NF"), "NJQP's spelling, not Vermont's")
    }

    // MARK: DC counts as MD

    /// "Use standard 2-leter postal abbreviations. DC is counted as MD." [sic]
    /// The first party to alias DC *away* from its own home state — MDC aliases
    /// it toward one.
    func testDCLogsAndCreditsMaryland() throws {
        XCTAssertEqual(vtqp.stateAliases, ["DC": "MD"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: vtqp, role: .inState).get().locations,
                       ["DC"], "DC is a loggable token")
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "CHI", their: "DC"),
            qso(call: "W3B", my: "CHI", their: "MD"),
        ]), party: vtqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "DC credits Maryland, and only once")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: The W1AW/1 bonus — 2 points per QSO, and 2026 only

    /// "Stations OUTSIDE of Vermont will get an additional 2 point bonus for each
    /// W1AW/1 station they work", and 1A(E) allows it "in each Vermont County on
    /// each band/mode" — hence per QSO, not once.
    func testW1AWSlashOnePaysTwoPointsPerQSO() {
        XCTAssertEqual(vtqp.bonuses, [.workStation(call: "W1AW/1", points: 2, scope: .perQSO)])

        let one = ScoreEngine.score(log: outLog([qso(call: "W1AW/1", their: "CHI")]), party: vtqp)
        XCTAssertEqual(one.bonusPoints, 2)

        let many = ScoreEngine.score(log: outLog([
            qso(call: "W1AW/1", band: .m40, mode: .cw, their: "CHI"),
            qso(call: "W1AW/1", band: .m20, mode: .cw, their: "CHI"),
            qso(call: "W1AW/1", band: .m40, mode: .phone, their: "WNS"),
        ]), party: vtqp)
        XCTAssertEqual(many.bonusPoints, 6, "every distinct QSO pays, unlike ILQP's once-each")
        XCTAssertEqual(many.total, many.qsoPoints * many.multiplierCount + 6)
    }

    /// KNOWN LIMITATION 2, pinned. Rule 1A(F) ends "Vermont stations will not get
    /// this bonus" and `bonusPoints` has no in/out-of-state condition, so a
    /// Vermont entrant is over-credited. Deliberate: for the out-of-state
    /// operator this app is used by, the bonus is exactly right.
    func testKnownGapVermontEntrantsAlsoReceiveTheBonusTheyShouldNot() throws {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1AW/1", my: "CHI", their: "WNS"),
        ]), party: vtqp)
        XCTAssertEqual(s.bonusPoints, 2, "current behaviour — the sponsor would pay 0")
        XCTAssertTrue(try XCTUnwrap(vtqp.notes).contains("KNOWN LIMITATION 2"))
    }

    // MARK: County lines — two counties, two QSOs, two multipliers

    /// "Vermont stations on a county line may be claimed as a QSO and a
    /// multiplier from each county (2 QSO's and 2 multipliers)."
    func testCountyLineIsTwoAndOnlyTwo() throws {
        XCTAssertEqual(vtqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            try ExchangeParser.parse("ESS/CAL", party: vtqp, role: .inState).get().locations,
            ["ESS", "CAL"],
            "K1IB's advertised Essex/Caledonia line"
        )
        XCTAssertEqual(
            ExchangeParser.parse("ESS/CAL/ORA", party: vtqp, role: .inState),
            .failure(.tooManyCounties(3)),
            "the sponsor's number is two"
        )
    }

    /// The page says "Do not try to enter both counties on the same log line!" —
    /// which is what this produces: one entry, two separate rows.
    func testCountyLineExpandsToTwoSeparateLoggedQSOs() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "K1IB", rstSent: "599", rstRcvd: "599",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_770_422_400)
            ),
            myLocs: ["TX"],
            theirLocs: ["ESS", "CAL"]
        )
        XCTAssertEqual(rows.count, 2, "two separate log lines, not one line with two counties")
        let s = ScoreEngine.score(log: outLog(rows), party: vtqp)
        XCTAssertEqual(s.validQSOs, 2, "'2 QSO's'")
        XCTAssertEqual(s.qsoPoints, 6, "CW 3 points each")
        XCTAssertEqual(s.multiplierCount, 2, "'and 2 multipliers'")
    }

    // MARK: Dupes

    func testDupesAreOncePerBandPerMode() {
        let a = qso(call: "W1M", band: .m40, mode: .cw, their: "RUT")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let s = ScoreEngine.score(log: outLog([a, repeated]), party: vtqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 1)

        // "WC4E may be worked on 20 CW, 20 SSB, and 20 digital for credit."
        let threeModes = ScoreEngine.score(log: outLog([
            qso(call: "WC4E", band: .m20, mode: .cw, their: "RUT"),
            qso(call: "WC4E", band: .m20, mode: .phone, their: "RUT"),
            qso(call: "WC4E", band: .m20, mode: .digital, their: "RUT"),
        ]), party: vtqp)
        XCTAssertEqual(threeModes.dupeCount, 0)
        XCTAssertEqual(threeModes.validQSOs, 3)
    }

    /// Rule 3(C) defines Mobile/Rover as "stations operating from multiple
    /// counties in Vermont", so the county change makes a new QSO.
    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K1IB", band: .m40, mode: .cw, their: "ESS"),
            qso(call: "K1IB", band: .m40, mode: .cw, their: "CAL"),
        ]), party: vtqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// KNOWN LIMITATION 3, pinned. "RTTY is considered a legacy mode and is not
    /// part of this digital group" — the sponsor has four modes where this app
    /// has three mode classes, and since multipliers count once per mode, a
    /// Vermont entrant loses one per state worked on both RTTY and FT8.
    func testKnownGapRTTYAndFT8ShareOneModeClass() throws {
        var rtty = qso(call: "K5B", band: .m20, mode: .digital, my: "CHI", their: "TX")
        rtty.rawMode = "RTTY"
        var ft8 = qso(call: "K5B", band: .m40, mode: .digital, my: "CHI", their: "TX")
        ft8.rawMode = "FT8"
        let s = ScoreEngine.score(log: inLog([rtty, ft8]), party: vtqp)
        XCTAssertEqual(s.multiplierCount, 1, "current behaviour — the sponsor would count two")
        XCTAssertTrue(try XCTUnwrap(vtqp.notes).contains("KNOWN LIMITATION 3"))
    }

    // MARK: Exchange parsing and the scope of credit

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("chi", party: vtqp, role: .inState).get().locations,
                       ["CHI"])
        XCTAssertEqual(try ExchangeParser.parse("WNH", party: vtqp, role: .inState).get().locations,
                       ["WNH"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: vtqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("ON", party: vtqp, role: .inState).get().locations,
                       ["ON"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: vtqp, role: .inState).get().locations,
                       ["DL"], "a DXCC prefix, which is what the log carries")
        guard case .failure = ExchangeParser.parse("VT", party: vtqp, role: .inState) else {
            return XCTFail("VT must be rejected — Vermont stations send a county")
        }
    }

    /// "Stations outside Vermont work Vermont stations. Stations within Vermont
    /// work everyone." Stated outright in rule 1 and repeated on the page — the
    /// eighth party to state it rather than imply it.
    func testOutOfStateEntrantsGetNoCreditForNonVermontContacts() {
        XCTAssertTrue(vtqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1A", their: "CHI"),
            qso(call: "K5B", their: "TX"),
        ]), party: vtqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — 48 hours, the longest window in the repo

    func testScheduleIsOneFortyEightHourWindow() throws {
        let windows = try XCTUnwrap(vtqp.schedule)
        XCTAssertEqual(windows.count, 1, "one continuous period, not a split weekend")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-02-07T00:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-02-09T00:00:00Z"),
                       "'2400 UTC on February 8' is midnight ending the 8th")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 48 * 3600,
                       "'This is a 48 hour period' — the longest of any bundled party")

        // "the first full weekend of February": Saturday 7 February 2026.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 7)
        XCTAssertEqual(utc.component(.month, from: windows[0].start), 2)
        XCTAssertEqual(utc.component(.year, from: windows[0].start), 2026)
    }

    // MARK: Notes

    func testNotesRecordEveryLimitationAndBothOpenQuestions() throws {
        let notes = try XCTUnwrap(vtqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        for n in 1...5 {
            XCTAssertTrue(notes.contains("KNOWN LIMITATION \(n)"), "limitation \(n) must be stated")
        }
        XCTAssertTrue(notes.contains("W1AW/1 IS A 2026-ONLY RULE"),
                      "so a 2027 session deletes the bonus rather than inheriting it")
        let questions = try XCTUnwrap(vtqp.openQuestions)
        XCTAssertTrue(questions.contains("state multiplier for Vermont entrants"))
        XCTAssertTrue(questions.contains("60 m"))
        XCTAssertTrue(questions.contains("w1sj@arrl.net"), "the operator needs somewhere to ask")
    }
}

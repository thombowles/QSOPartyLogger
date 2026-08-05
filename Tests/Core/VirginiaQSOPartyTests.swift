import XCTest
@testable import QSOPartyLogger

/// Virginia QSO Party — Sterling Park Amateur Radio Club. Built from the
/// sponsor's official 2026 rules PDF and its entity list, read verbatim
/// 2026-07-26. See docs/research/vaqp_rules.md.
///
/// **The first bundled party whose entities are not all counties** — 95 counties
/// *and* 38 independent cities — and the first where **names are not unique**:
/// Fairfax, Franklin, Richmond and Roanoke each exist twice.
final class VirginiaQSOPartyTests: XCTestCase {

    var vaqp: PartyDefinition!

    override func setUpWithError() throws {
        vaqp = try XCTUnwrap(PartyCatalog.party(id: "vaqp"), "bundled VAQP should load")
    }

    var seq: TimeInterval = 0
    /// The exchange is a QSO number and a location — no signal report.
    func qso(
        call: String = "W4ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "FFX",
        serialRcvd: Int? = 1
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_774_101_600 + seq),  // 2026-03-21 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            serialSent: 1, serialRcvd: serialRcvd,
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "vaqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from entity: String = "FFX",
               station: StationProfile.CategoryStation = .fixed) -> ContestLog {
        var log = ContestLog(partyID: "vaqp")
        log.myLocation = .inState(counties: [entity])
        log.station.categoryStation = station
        log.qsos = qsos
        return log
    }

    // MARK: Entities — 95 counties + 38 independent cities

    func testEntityCount() {
        XCTAssertEqual(vaqp.counties.count, 133, "95 counties + 38 independent cities")
        XCTAssertEqual(Set(vaqp.counties.map(\.abbr)).count, 133, "codes are unique")
        XCTAssertEqual(vaqp.countyAbbrLengths, [3], "uniformly 3 characters")
        XCTAssertEqual(vaqp.counties.filter { $0.name.hasSuffix(" (City)") }.count, 38)
    }

    /// **Four names exist twice — once as a county, once as an independent
    /// city.** Virginia's arrangement, and the reason no test here may assert
    /// that names are unique the way every other party's does.
    func testTheFourNamesThatAreBothACountyAndACity() {
        XCTAssertEqual(vaqp.county(for: "FFX")?.name, "Fairfax")
        XCTAssertEqual(vaqp.county(for: "FXX")?.name, "Fairfax (City)")
        XCTAssertEqual(vaqp.county(for: "FRA")?.name, "Franklin")
        XCTAssertEqual(vaqp.county(for: "FRX")?.name, "Franklin (City)")
        XCTAssertEqual(vaqp.county(for: "RIC")?.name, "Richmond")
        XCTAssertEqual(vaqp.county(for: "RIX")?.name, "Richmond (City)")
        XCTAssertEqual(vaqp.county(for: "ROA")?.name, "Roanoke")
        XCTAssertEqual(vaqp.county(for: "ROX")?.name, "Roanoke (City)")
    }

    /// The `(City)` suffix renders the sponsor's own asterisk. Without it, four
    /// pairs of entities would be indistinguishable in the picker and an
    /// operator could log `FRA` meaning `FRX`.
    func testTheCitySuffixMakesAllDisplayNamesUnique() {
        XCTAssertEqual(Set(vaqp.counties.map(\.name)).count, 133)
        let bare = vaqp.counties.map { $0.name.replacingOccurrences(of: " (City)", with: "") }
        XCTAssertEqual(Set(bare).count, 129, "four names are shared before the suffix")
    }

    /// Most city codes end in `X`, but that is the sponsor's convention and not
    /// a rule: **`FFX` is Fairfax *County*.** The asterisk in the sponsor's list
    /// is the authority, which is what the generator reads.
    func testEndingInXIsNotACityTest() {
        XCTAssertEqual(vaqp.county(for: "FFX")?.name, "Fairfax", "a COUNTY, despite the X")
        XCTAssertFalse(try! XCTUnwrap(vaqp.county(for: "FFX")).name.hasSuffix(" (City)"))
        XCTAssertTrue(try! XCTUnwrap(vaqp.county(for: "FXX")).name.hasSuffix(" (City)"))
    }

    func testOtherCodesWorthChecking() {
        XCTAssertEqual(vaqp.county(for: "CCY")?.name, "Charles City")
        XCTAssertEqual(vaqp.county(for: "KQN")?.name, "King Queen")
        XCTAssertEqual(vaqp.county(for: "KGE")?.name, "King George")
        XCTAssertEqual(vaqp.county(for: "KWM")?.name, "King William")
        XCTAssertEqual(vaqp.county(for: "IOW")?.name, "Isle of Wight")
        XCTAssertEqual(vaqp.county(for: "MPX")?.name, "Manassas Park (City)")
        XCTAssertEqual(vaqp.county(for: "VBX")?.name, "Virginia Beach (City)")
        XCTAssertEqual(vaqp.county(for: "acc")?.name, "Accomack", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(vaqp.cabrilloContest, "VA-QSO-PARTY", "WA7BNM; the rules print none")
        XCTAssertEqual(vaqp.homeState, "VA")
        XCTAssertEqual(vaqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(vaqp.dxStyle, .token)
        XCTAssertNil(vaqp.scoreMultipliers, "power selects the award category only")
        XCTAssertTrue(vaqp.isPartiallyVerified)
    }

    /// "Exchange QSO number and QTH" — and no signal report appears anywhere in
    /// the rules. The third party to send a serial, after CQP and PAQP, and all
    /// three pair it with no report.
    func testExchangeIsASerialAndALocationWithNoReport() throws {
        XCTAssertTrue(vaqp.exchangeIncludesSerial)
        XCTAssertFalse(vaqp.exchangeIncludesRST)
        for id in ["cqp", "paqp"] {
            let other = try XCTUnwrap(PartyCatalog.party(id: id))
            XCTAssertTrue(other.exchangeIncludesSerial, "\(id) is the same shape")
            XCTAssertFalse(other.exchangeIncludesRST)
        }
    }

    func testTenBands() {
        XCTAssertEqual(vaqp.validBands,
                       [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70])
        for warc in [Band.m30, .m17, .m12] {
            XCTAssertFalse(vaqp.validBands.contains(warc), "no WARC band QSO's permitted")
        }
        XCTAssertFalse(vaqp.validBands.contains(.m60))
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(vaqp.points.points(for: .phone), 1)
        XCTAssertEqual(vaqp.points.points(for: .cw), 2)
        XCTAssertEqual(vaqp.points.points(for: .digital), 2)
        XCTAssertNil(vaqp.homeStationPoints)
    }

    /// **KNOWN LIMITATION 1, pinned.** "…and 3 points per contact made with a
    /// Virginia Mobile, Expedition, or Rover." The worked station's category is
    /// not in the exchange — only in its callsign suffix, by convention — so this
    /// app pays the by-mode rate. In a party with 133 entities most multipliers
    /// come from mobiles, so this under-credits nearly every serious entrant.
    func testKnownGapContactsWithVirginiaMobilesDoNotPayThreePoints() throws {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4MOB/M", band: .m20, mode: .phone, their: "FFX"),
        ]), party: vaqp)
        XCTAssertEqual(s.qsoPoints, 1, "current behaviour — the sponsor pays 3")

        let notes = try XCTUnwrap(vaqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("TO CORRECT BY HAND"))
    }

    // MARK: Multipliers — once overall

    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(vaqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(vaqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", band: .m20, mode: .cw, their: "FFX"),
            qso(call: "W4A", band: .m40, mode: .cw, their: "FFX"),
            qso(call: "W4A", band: .m20, mode: .phone, their: "FFX"),
        ]), party: vaqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// "the total number of Virginia Counties (95) and Independent Cities (38)
    /// worked" — 133, and the county *and* city of a shared name count
    /// separately.
    func testOutOfStateCeilingIs133AndSharedNamesCountSeparately() {
        XCTAssertEqual(Set(vaqp.multipliers.outState.classes), [.county])
        let rows = vaqp.counties.enumerated().map { i, c in qso(call: "W4\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: vaqp).multiplierCount, 133)

        let pair = ScoreEngine.score(log: outLog([
            qso(call: "W4A", their: "FRA"),
            qso(call: "W4B", their: "FRX"),
        ]), party: vaqp)
        XCTAssertEqual(pair.multiplierCount, 2, "Franklin county and Franklin city are separate")
    }

    /// "U. S. States (**except Virginia**)", and again "No extra DX multiplier
    /// for … Virginia". Stated twice, in the negative.
    func testVirginiaIsNotAStateMultiplier() {
        XCTAssertFalse(vaqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "FFX", their: "RIC")]), party: vaqp)
        XCTAssertEqual(s.workedValues(.state), [])
        XCTAssertFalse(vaqp.validOutStateTokens.contains("VA"))
    }

    func testInStateCountsEntitiesStatesProvincesAndDX() {
        XCTAssertEqual(Set(vaqp.multipliers.inState.classes), [.county, .state, .province, .dx])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W4A", my: "FFX", their: "RIX"),
            qso(call: "K5B", my: "FFX", their: "TX"),
            qso(call: "VE3C", my: "FFX", their: "ON"),
            qso(call: "JA1D", my: "FFX", their: "DX"),
        ]), party: vaqp)
        XCTAssertEqual(s.multiplierCount, 4)
    }

    /// DC is never mentioned in the rules, so it stays its own state-class
    /// token — as in MNQP, NCQP and SCQP, and unlike VTQP, BCQP, OKQP and WIQP.
    func testDCIsNotAliased() throws {
        XCTAssertEqual(vaqp.stateAliases, [:])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: vaqp, role: .inState).get().locations,
                       ["DC"])
    }

    // MARK: County lines — permitted, but they pay for ONE

    /// "Stations on County or Independent City lines count as **one QSO and one**
    /// County/Independent City multiplier." Neither of the usual shapes: not
    /// forbidden as in ALQP and WIQP, and not per-county as in IAQP and OKQP.
    func testCountyLinesPayForExactlyOneEntity() throws {
        XCTAssertEqual(vaqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            try ExchangeParser.parse("FFX", party: vaqp, role: .inState).get().locations, ["FFX"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("FFX/FXX", party: vaqp, role: .inState),
            .failure(.tooManyCounties(2)),
            "the operator picks which of the two to claim"
        )
    }

    // MARK: Bonuses

    /// "…a bonus of 100 additional points for each Virginia County/Independent
    /// City from which they log a valid QSO" — a threshold of one.
    func testOneHundredPointsPerEntityActivated() {
        XCTAssertEqual(vaqp.bonuses, [.activatedCountyCount(minQSOs: 1, points: 100)])
        var log = inLog([
            qso(call: "W4A", my: "FFX", their: "TX"),
            qso(call: "W4B", my: "RIX", their: "MD"),
        ], station: .rover)
        log.myLocation = .inState(counties: ["FFX"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: vaqp).bonusPoints, 200,
                       "one QSO from each of two entities")
    }

    // MARK: The entity you work ten stations from — and it is stations, not QSOs

    /// "Mobile, Rover, and Expedition stations that contact **10 (ten) or more
    /// different stations** while operating from a county or independent city
    /// may claim it as a multiplier, if not otherwise worked."
    ///
    /// **The only party of the five with this rule that counts stations.** The
    /// case that separates the two readings: one chaser worked on ten bands is
    /// ten QSOs and one station, and pays nothing.
    func testTenDifferentStationsNotTenQSOs() throws {
        let act = try XCTUnwrap(vaqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(act.minCount, 10)
        XCTAssertEqual(act.countUnit, .stations, "\"10 (ten) or more different stations\"")

        // Ten QSOs from FFX, all with the same station on ten different bands.
        let oneChaser = vaqp.validBands.prefix(10).map { band in
            qso(call: "K5SAME", band: band, mode: .cw, my: "FFX", their: "TX")
        }
        let s = ScoreEngine.score(log: inLog(Array(oneChaser), station: .rover), party: vaqp)
        XCTAssertEqual(s.validQSOs, 10, "ten valid QSOs — a new band is not a dupe")
        XCTAssertEqual(s.selfActivatedCounties, [], "but only one different station")

        // Ten different stations on one band does qualify.
        let tenChasers = (0..<10).map { i in
            qso(call: "K5C\(i)", band: .m40, mode: .cw, my: "FFX", their: "TX")
        }
        XCTAssertEqual(
            ScoreEngine.score(log: inLog(tenChasers, station: .rover), party: vaqp)
                .selfActivatedCounties, ["FFX"]
        )

        // Nine falls short — the threshold is inclusive at ten and not below.
        XCTAssertEqual(
            ScoreEngine.score(log: inLog(Array(tenChasers.dropLast()), station: .rover), party: vaqp)
                .selfActivatedCounties, []
        )
    }

    /// "Mobile, Rover, and Expedition stations" — VAQP's station classes are
    /// Fixed, Mobile, Expedition and Rover, with no Portable, so those three
    /// are the whole of the roving side. A fixed Virginia station gains nothing.
    func testOnlyMobilesRoversAndExpeditionsClaimIt() throws {
        let act = try XCTUnwrap(vaqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertEqual(Set(act.categories), [.mobile, .rover, .expedition])

        let tenChasers = (0..<10).map { i in
            qso(call: "K5C\(i)", band: .m40, mode: .cw, my: "FFX", their: "TX")
        }
        for category in StationProfile.CategoryStation.allCases {
            let s = ScoreEngine.score(log: inLog(tenChasers, station: category), party: vaqp)
            XCTAssertEqual(
                s.selfActivatedCounties,
                [.mobile, .rover, .expedition].contains(category) ? ["FFX"] : [],
                "\(category.rawValue)"
            )
        }
    }

    /// "…**if not otherwise worked**." The first of the five sponsors to state
    /// the condition outright, and the reason it is a field.
    func testAnEntityAlreadyWorkedIsNotClaimedAgain() throws {
        let act = try XCTUnwrap(vaqp.multipliers.inState.activatedCountyMultiplier)
        XCTAssertTrue(act.notOtherwiseWorked)

        // Ten different stations from FFX, one of them *in* FFX.
        var rows = (0..<9).map { i in
            qso(call: "K5C\(i)", band: .m40, mode: .cw, my: "FFX", their: "TX")
        }
        rows.append(qso(call: "W4FFX", band: .m40, mode: .cw, my: "FFX", their: "FFX"))
        let s = ScoreEngine.score(log: inLog(rows, station: .rover), party: vaqp)
        XCTAssertEqual(s.workedValues(.county), ["FFX"])
        XCTAssertEqual(s.selfActivatedCounties, [], "FFX was otherwise worked")
        XCTAssertEqual(s.multiplierCount, 2, "FFX worked, and TX")
    }

    /// The multiplier and the 100-point bonus are **separate rules with
    /// different thresholds** — one valid QSO for the bonus, ten different
    /// stations for the multiplier — and both apply to the same log.
    func testTheMultiplierAndTheBonusAreIndependent() {
        // One QSO from RIX: the bonus pays, the multiplier does not.
        let thin = ScoreEngine.score(log: inLog([
            qso(call: "K5A", my: "RIX", their: "TX"),
        ], station: .rover), party: vaqp)
        XCTAssertEqual(thin.bonusPoints, 100, "\"from which they log a valid QSO\"")
        XCTAssertEqual(thin.selfActivatedCounties, [], "one station is not ten")

        // Ten different stations from RIX: both pay.
        let full = ScoreEngine.score(log: inLog((0..<10).map { i in
            qso(call: "K5C\(i)", band: .m40, mode: .cw, my: "RIX", their: "TX")
        }, station: .rover), party: vaqp)
        XCTAssertEqual(full.bonusPoints, 100)
        XCTAssertEqual(full.selfActivatedCounties, ["RIX"])
        XCTAssertEqual(full.multiplierCount, 2, "TX worked, RIX activated")
        XCTAssertEqual(full.qsoPoints, 20, "ten CW QSOs at 2")
        XCTAssertEqual(full.total, 20 * 2 + 100, "multiplied, then the bonus added")
    }

    /// Out-of-state entrants never reach the rule.
    func testOutOfStateEntrantsAreUnaffected() {
        XCTAssertNil(vaqp.multipliers.outState.activatedCountyMultiplier)
        XCTAssertEqual(
            ScoreEngine.score(log: outLog([qso(call: "W4A", their: "FFX")]), party: vaqp)
                .selfActivatedCounties, []
        )
    }

    /// **KNOWN LIMITATION 2, pinned.** "A QSO with each different VA QSO Party
    /// Bonus Station gives a one-time bonus of 50 points. **Bonus stations are
    /// listed on the VaQP Web Site**" — the rules name none, so none can ship.
    /// The same call PAQP's unannounced 2026 station got.
    func testKnownGapBonusStationsAreNotNamedInTheRules() throws {
        XCTAssertFalse(vaqp.bonuses.contains { if case .workStation = $0 { return true }
                                               else { return false } })
        XCTAssertTrue(try XCTUnwrap(vaqp.notes).contains("KNOWN LIMITATION 2"))
    }

    // MARK: Dupes, exchange, credit

    func testMobileChangingEntityIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4MOB", band: .m40, mode: .cw, their: "FFX"),
            qso(call: "W4MOB", band: .m40, mode: .cw, their: "FXX"),
        ]), party: vaqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("ffx", party: vaqp, role: .inState).get().locations,
                       ["FFX"])
        XCTAssertEqual(try ExchangeParser.parse("FXX", party: vaqp, role: .inState).get().locations,
                       ["FXX"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: vaqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: vaqp, role: .inState).get().locations,
                       ["DX"])
        guard case .failure = ExchangeParser.parse("VA", party: vaqp, role: .inState) else {
            return XCTFail("VA must be rejected — Virginia stations send a county or city")
        }
    }

    /// "Virginia stations work all stations. Out-of-State stations work Virginia
    /// stations only."
    func testOutOfStateEntrantsGetNoCreditForNonVirginiaContacts() {
        XCTAssertTrue(vaqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W4A", their: "FFX"),
            qso(call: "K5B", their: "TX"),
        ]), party: vaqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — 26 hours in two windows

    func testScheduleIsTwoWindowsTotallingTwentySixHours() throws {
        let windows = try XCTUnwrap(vaqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-03-21T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-03-22T04:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-03-22T12:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-03-23T00:00:00Z"),
                       "'2400 UTC' on the 22nd is midnight ending that day")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 14 * 3600)
        XCTAssertEqual(windows[1].end.timeIntervalSince(windows[1].start), 12 * 3600)

        // All four local anchors, against a real zone: 10 am / midnight / 8 am / 8 pm.
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(eastern.component(.hour, from: windows[0].start), 10)
        XCTAssertEqual(eastern.component(.hour, from: windows[0].end), 0)
        XCTAssertEqual(eastern.component(.hour, from: windows[1].start), 8)
        XCTAssertEqual(eastern.component(.hour, from: windows[1].end), 20)
    }

    func testNotesRecordBothRemainingLimitations() throws {
        let notes = try XCTUnwrap(vaqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        // Two, not three: the self-activation multiplier landed 2026-08-04.
        for n in 1...2 {
            XCTAssertTrue(notes.contains("KNOWN LIMITATION \(n)"), "limitation \(n)")
        }
        XCTAssertFalse(notes.contains("KNOWN LIMITATION 3"))
        XCTAssertTrue(notes.contains("TEN DIFFERENT STATIONS, NOT TEN QSOS"),
                      "the unit is the trap this party sets for the next maintainer")
        XCTAssertTrue(notes.contains("FOUR NAMES APPEAR TWICE"))
        XCTAssertTrue(try XCTUnwrap(vaqp.openQuestions).contains("VaQP web site"))
    }
}

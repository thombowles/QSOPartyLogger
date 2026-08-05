import XCTest
@testable import QSOPartyLogger

/// Wisconsin QSO Party — West Allis Radio Amateur Club (`W9FK`). Built from the
/// sponsor's 2026 rules page, its official Multiplier List and its Cabrillo
/// guide, read verbatim 2026-07-26. See docs/research/wiqp_rules.md.
///
/// **The second party to want a fractional power multiplier**, with the identical
/// factors to VTQP's — which meets the repo's own two-user bar for building the
/// field. See `testKnownGapPowerMultiplierIsNotAppliedBecauseItIsFractional`.
final class WisconsinQSOPartyTests: XCTestCase {

    var wiqp: PartyDefinition!

    override func setUpWithError() throws {
        wiqp = try XCTUnwrap(PartyCatalog.party(id: "wiqp"), "bundled WIQP should load")
    }

    var seq: TimeInterval = 0
    /// The exchange is call + location with no signal report, which the
    /// sponsor's own Cabrillo example confirms.
    func qso(
        call: String = "W9ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "MIL"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_773_597_600 + seq),  // 2026-03-15 18:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            myLoc: my, theirLoc: their
        )
    }

    /// Both helpers default to **high power**, whose factor is ×1, so that every
    /// test about points, multipliers, bonuses or dupes measures what it is
    /// about rather than the power multiplier.
    func outLog(
        _ qsos: [QSO],
        power: StationProfile.CategoryPower = .high
    ) -> ContestLog {
        var log = ContestLog(partyID: "wiqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "MIL",
               station: StationProfile.CategoryStation = .fixed,
               power: StationProfile.CategoryPower = .high) -> ContestLog {
        var log = ContestLog(partyID: "wiqp")
        log.myLocation = .inState(counties: [county])
        log.station.categoryStation = station
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    // MARK: County data — 72, with three dense clusters

    func testCountyData() {
        XCTAssertEqual(wiqp.counties.count, 72, "Wisconsin has 72 counties")
        XCTAssertEqual(Set(wiqp.counties.map(\.abbr)).count, 72)
        XCTAssertEqual(Set(wiqp.counties.map(\.name)).count, 72)
        XCTAssertEqual(wiqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// Three counties begin "Mar-" and only Marathon takes the naive code.
    func testTheThreeMarCounties() {
        XCTAssertEqual(wiqp.county(for: "MAR")?.name, "Marathon")
        XCTAssertEqual(wiqp.county(for: "MRN")?.name, "Marinette")
        XCTAssertEqual(wiqp.county(for: "MRQ")?.name, "Marquette")
    }

    /// Three begin "Gr-", and `GRE`/`GRL` are two different counties one letter
    /// apart — Green and Green Lake.
    func testTheThreeGrCounties() {
        XCTAssertEqual(wiqp.county(for: "GRA")?.name, "Grant")
        XCTAssertEqual(wiqp.county(for: "GRE")?.name, "Green")
        XCTAssertEqual(wiqp.county(for: "GRL")?.name, "Green Lake")
    }

    /// Six begin with W, and neither Washburn nor Waushara takes the naive form.
    func testTheSixWCounties() {
        XCTAssertEqual(wiqp.county(for: "WAL")?.name, "Walworth")
        XCTAssertEqual(wiqp.county(for: "WAS")?.name, "Washington")
        XCTAssertEqual(wiqp.county(for: "WSB")?.name, "Washburn")
        XCTAssertEqual(wiqp.county(for: "WAU")?.name, "Waukesha")
        XCTAssertEqual(wiqp.county(for: "WAP")?.name, "Waupaca")
        XCTAssertEqual(wiqp.county(for: "WSR")?.name, "Waushara")
    }

    /// Multi-word names, printed by the sponsor without punctuation.
    func testMultiWordCountyNames() {
        XCTAssertEqual(wiqp.county(for: "FON")?.name, "Fond du Lac")
        XCTAssertEqual(wiqp.county(for: "LAC")?.name, "La Crosse")
        XCTAssertEqual(wiqp.county(for: "STC")?.name, "St Croix", "no period, as in MNQP's STL")
        XCTAssertEqual(wiqp.county(for: "EAU")?.name, "Eau Claire")
        XCTAssertEqual(wiqp.county(for: "one")?.name, "Oneida", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(wiqp.cabrilloContest, "WI-QSO-PARTY",
                       "printed by the sponsor in its own Cabrillo guide")
        XCTAssertEqual(wiqp.homeState, "WI")
        XCTAssertEqual(wiqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertFalse(wiqp.exchangeIncludesRST,
                       "the sponsor's Cabrillo example carries call + location only")
        XCTAssertFalse(wiqp.exchangeIncludesSerial)
        XCTAssertTrue(wiqp.isPartiallyVerified)
    }

    /// **`dxStyle` was decided by the sponsor's Cabrillo guide, not its rules.**
    /// The rules say non-Wisconsin stations send "State or Province or Country",
    /// which reads like a prefix — but the sponsor's own example logs `DL6QK` as
    /// the literal token `DX`. Reading only the rules page would have shipped
    /// `.prefix` and rejected the sponsor's own sample line.
    func testDXIsALiteralTokenBecauseTheSponsorsExampleSaysSo() throws {
        XCTAssertEqual(wiqp.dxStyle, .token)
        XCTAssertEqual(try ExchangeParser.parse("DX", party: wiqp, role: .inState).get().locations,
                       ["DX"])
    }

    /// "DX countries worked count for QSO points but not as multipliers."
    func testDXEarnsPointsButNoMultiplier() {
        XCTAssertFalse(wiqp.multipliers.inState.classes.contains(.dx))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL6QK", my: "MIL", their: "DX"),
        ]), party: wiqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 0)
    }

    /// No band list is published — "all amateur bands not prohibited for
    /// contesting" — so the suggested-frequency table fixes the set at ten, the
    /// largest of any bundled party.
    func testTenBandsDerivedFromTheFrequencyTable() {
        XCTAssertEqual(wiqp.validBands,
                       [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70])
        for excluded in [Band.m60, .m30, .m17, .m12] {
            XCTAssertFalse(wiqp.validBands.contains(excluded),
                           "\(excluded.rawValue) is prohibited for contesting")
        }
    }

    // MARK: Points and multipliers

    func testPointsByMode() {
        XCTAssertEqual(wiqp.points.points(for: .phone), 1)
        XCTAssertEqual(wiqp.points.points(for: .cw), 2)
        XCTAssertEqual(wiqp.points.points(for: .digital), 2)
    }

    /// The sponsor's stated maxima — 72 counties, 50 states, 13 provinces — are
    /// what settle the scope: a per-band or per-mode count could not have a
    /// maximum of 72. Neither a second band nor a second mode may add anything.
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(wiqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(wiqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9A", band: .m20, mode: .cw, their: "MIL"),
            qso(call: "W9A", band: .m40, mode: .cw, their: "MIL"),
            qso(call: "W9A", band: .m20, mode: .phone, their: "MIL"),
        ]), party: wiqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfStateCeilingIs72Counties() {
        XCTAssertEqual(Set(wiqp.multipliers.outState.classes), [.county])
        let rows = wiqp.counties.enumerated().map { i, c in qso(call: "W9\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: wiqp).multiplierCount, 72)
    }

    /// "Wisconsin may be counted as a state multiplier" — stated outright, and
    /// the multiplier list corroborates by including `WI Wisconsin` among the
    /// states. WI stations send a county, so the token is never received.
    func testWisconsinIsAMultiplierReachableThroughACounty() {
        XCTAssertTrue(wiqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(wiqp.validOutStateTokens.contains("WI"))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W9A", my: "MIL", their: "DAN"),
        ]), party: wiqp)
        XCTAssertEqual(s.workedValues(.county), ["DAN"])
        XCTAssertEqual(s.workedValues(.state), ["WI"])
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// DC appears **nowhere in the rules** — only in the multiplier list, as the
    /// single row `MD Maryland/(D.C.)`.
    func testDCCountsAsMaryland() throws {
        XCTAssertEqual(wiqp.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "MIL", their: "DC"),
            qso(call: "W3B", my: "MIL", their: "MD"),
        ]), party: wiqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"], "one multiplier, not two")
    }

    // MARK: The two bonuses, and where each over-credits

    /// "Add 500 bonus points for each county that you operate from… A minimum of
    /// 12 QSO's per county is required."
    func testFiveHundredPerCountyWithTwelveQSOs() {
        func rows(_ county: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in qso(call: "W\(county)\(i)", my: county, their: "TX") }
        }
        var log = inLog(rows("MIL", 12) + rows("DAN", 11), station: .mobile)
        log.myLocation = .inState(counties: ["MIL"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: wiqp).bonusPoints, 500,
                       "twelve qualifies, eleven does not")
    }

    /// **KNOWN LIMITATION 2, pinned.** The sponsor pays 500 only for counties
    /// "outside your home county"; the engine counts every county with ≥12 QSOs,
    /// including home. In-state mobiles and portables only.
    func testKnownGapTheHomeCountyIsCreditedWhenItShouldNotBe() throws {
        func rows(_ county: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in qso(call: "W\(county)\(i)", my: county, their: "TX") }
        }
        var log = inLog(rows("MIL", 12), station: .mobile)
        log.myLocation = .inState(counties: ["MIL"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: wiqp).bonusPoints, 500,
                       "current behaviour — the sponsor pays 0 for the home county")
        XCTAssertTrue(try XCTUnwrap(wiqp.notes).contains("KNOWN LIMITATION 2"))
    }

    /// "Add 100 points for each time you work W9FK on each band and mode below
    /// 50MHz" — the `perBandMode` scope's second user, after SCQP.
    func testW9FKPaysOneHundredPerBandAndMode() {
        XCTAssertEqual(wiqp.bonuses.last,
                       .workStation(call: "W9FK", points: 100, scope: .perBandMode))
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9FK", band: .m40, mode: .cw, their: "MIL"),
            qso(call: "W9FK", band: .m40, mode: .phone, their: "MIL"),
            qso(call: "W9FK", band: .m20, mode: .cw, their: "MIL"),
        ]), party: wiqp)
        XCTAssertEqual(s.bonusPoints, 300, "three band/mode slots")
    }

    /// **KNOWN LIMITATION 2, pinned.** The sponsor caps the W9FK bonus *below
    /// 50 MHz*; the engine counts 6 m and up too.
    func testKnownGapTheW9FKBonusIsNotBandLimited() throws {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9FK", band: .m6, mode: .phone, their: "MIL"),
        ]), party: wiqp)
        XCTAssertEqual(s.bonusPoints, 100, "current behaviour — the sponsor pays 0 above 50 MHz")
        XCTAssertTrue(try XCTUnwrap(wiqp.notes).contains("KNOWN LIMITATION 2"))
    }

    /// The POWER LEVEL table, verbatim: *"QRP — less than 5 watts — Power Mult =
    /// 2 · Low — 5 to 100 watts — Power Mult = 1.5 · High — over 100 watts —
    /// Power Mult = 1"*. **Identical factors to Vermont's**, on different
    /// wattage boundaries — the second sponsor to want the same fraction, which
    /// is what met this repo's two-user bar for building it.
    func testThePowerMultiplierShipsIncludingItsHalf() throws {
        let mults = try XCTUnwrap(wiqp.scoreMultipliers)
        XCTAssertEqual(mults.factor(power: .qrp, station: .fixed), 2)
        XCTAssertEqual(mults.factor(power: .high, station: .fixed), 1)
        XCTAssertEqual(mults.factor(power: .low, station: .fixed),
                       ScoreFactor(numerator: 3, denominator: 2), "×1.5, exactly")

        let vtqp = try XCTUnwrap(PartyCatalog.party(id: "vtqp"))
        XCTAssertEqual(vtqp.scoreMultipliers, wiqp.scoreMultipliers,
                       "two sponsors, one table — the same three numbers")
    }

    /// Applied, not merely stored. Four CW QSOs in four counties: 8 QSO points
    /// × 4 multipliers = 32, and low power takes that to 48.
    func testTheLowPowerHalfReachesTheScore() {
        let rows = ["MIL", "DAN", "BRO", "CAL"].enumerated().map {
            qso(call: "W9\($0.offset)", their: $0.element)
        }
        let high = ScoreEngine.score(log: outLog(rows, power: .high), party: wiqp)
        XCTAssertEqual(high.qsoPoints, 8, "4 CW QSOs at 2 points")
        XCTAssertEqual(high.multiplierCount, 4)
        XCTAssertEqual(high.total, 32)

        XCTAssertEqual(ScoreEngine.score(log: outLog(rows, power: .low), party: wiqp).total, 48)
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows, power: .qrp), party: wiqp).total, 64)
    }

    /// **The sponsor prints no rounding rule at all** — not in the rules, the
    /// Multiplier List or the Cabrillo guide. Three phone QSOs in three counties
    /// put a low-power entrant on 13.5, and this app rounds down, the direction
    /// that cannot overstate a `CLAIMED-SCORE:`.
    func testAHalfPointIsRoundedDown() {
        let rows = ["MIL", "DAN", "BRO"].enumerated().map {
            qso(call: "W9\($0.offset)", mode: .phone, their: $0.element)
        }
        let s = ScoreEngine.score(log: outLog(rows, power: .low), party: wiqp)
        XCTAssertEqual(s.qsoPoints, 3)
        XCTAssertEqual(s.multiplierCount, 3)
        XCTAssertEqual(s.total, 13, "3 × 3 × 1.5 = 13.5 → 13, never 14")
    }

    /// The sponsor's SCORING section states the order outright, and it is what
    /// the engine computes: *"Add CW, Phone and Digital points. Then multiply by
    /// Power Level multiplier. Then multiply by your multiplier count under
    /// MULTIPLIERS. **Finally, add your bonus points.**"* — so the W9FK bonus is
    /// added after the power factor and is never scaled by it.
    func testBonusPointsAreAddedAfterThePowerMultiplierAsTheSponsorSays() {
        let rows = [qso(call: "W9FK", their: "MIL")]
        let s = ScoreEngine.score(log: outLog(rows, power: .low), party: wiqp)

        XCTAssertEqual(s.qsoPoints, 2)
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertEqual(s.bonusPoints, 100)
        XCTAssertEqual(s.total, 103, "⌊2 × 1 × 1.5⌋ = 3, + 100 unscaled — not (2 + 100) × 1.5")
    }

    // MARK: County lines forbidden, dupes, credit

    /// "Mobiles or portables may not sit on a county line."
    func testCountyLineOperationIsRejected() throws {
        XCTAssertEqual(wiqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("MIL/DAN", party: wiqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
    }

    /// "Cannot work the same station on more than one Digital mode on the same
    /// band" — exactly what `ModeClass.digital` enforces.
    func testAllDigitalModesAreOneMode() {
        var psk = qso(call: "W9M", band: .m20, mode: .digital, their: "MIL")
        psk.rawMode = "PSK31"
        var rtty = qso(call: "W9M", band: .m20, mode: .digital, their: "MIL")
        rtty.rawMode = "RTTY"
        rtty.id = UUID()
        let s = ScoreEngine.score(log: outLog([psk, rtty]), party: wiqp)
        XCTAssertEqual(s.dupeCount, 1)
    }

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9MOB", band: .m40, mode: .cw, their: "MIL"),
            qso(call: "W9MOB", band: .m40, mode: .cw, their: "DAN"),
        ]), party: wiqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("mil", party: wiqp, role: .inState).get().locations,
                       ["MIL"])
        XCTAssertEqual(try ExchangeParser.parse("GRL", party: wiqp, role: .inState).get().locations,
                       ["GRL"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: wiqp, role: .inState).get().locations,
                       ["TX"])
        guard case .failure = ExchangeParser.parse("WI", party: wiqp, role: .inState) else {
            return XCTFail("WI must be rejected — Wisconsin stations send a county")
        }
    }

    /// "Only Wisconsin stations may be worked."
    func testOutOfStateEntrantsGetNoCreditForNonWisconsinContacts() {
        XCTAssertTrue(wiqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W9A", their: "MIL"),
            qso(call: "K5B", their: "TX"),
        ]), party: wiqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule — seven hours, the shortest in the repo

    func testScheduleIsOneSevenHourWindow() throws {
        let windows = try XCTUnwrap(wiqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-03-15T18:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-03-16T01:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 7 * 3600,
                       "the shortest window of any bundled party")

        // The local anchors, against a real zone: 1 pm to 8 pm CDT.
        var central = Calendar(identifier: .gregorian)
        central.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Chicago"))
        XCTAssertEqual(central.component(.hour, from: windows[0].start), 13)
        XCTAssertEqual(central.component(.hour, from: windows[0].end), 20)
    }

    /// **Total** operating time, not single-window length — the distinction the
    /// first draft of this test got wrong. KSQP and TQP each have a six-hour
    /// Sunday session, shorter than WIQP's seven, but both run eighteen hours
    /// overall. Pinned so the claim in the README and the notes stays true.
    func testItIsTheShortestTotalOperatingTimeOfAnyBundledParty() throws {
        func total(_ p: PartyDefinition) -> TimeInterval {
            (p.schedule ?? []).reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        }
        let mine = total(wiqp)
        XCTAssertEqual(mine, 7 * 3600)
        for party in PartyCatalog.loadBundled() where party.id != "wiqp" {
            guard !(party.schedule ?? []).isEmpty else { continue }
            XCTAssertGreaterThan(total(party), mine,
                                 "\(party.id) runs no longer than WIQP overall")
        }
        // ...and the claim is specifically NOT about single windows.
        let shortestElsewhere = PartyCatalog.loadBundled()
            .filter { $0.id != "wiqp" }
            .flatMap { $0.schedule ?? [] }
            .map { $0.end.timeIntervalSince($0.start) }
            .min()
        XCTAssertEqual(shortestElsewhere, 6 * 3600,
                       "KSQP and TQP each have a shorter single session")
    }

    /// Two, since 2026-07-28: the power multiplier was the third and is now
    /// applied. Both survivors are bonus rules that over-credit a narrow case.
    func testNotesRecordBothRemainingLimitations() throws {
        let notes = try XCTUnwrap(wiqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        for n in 1...2 {
            XCTAssertTrue(notes.contains("KNOWN LIMITATION \(n)"), "limitation \(n)")
        }
        XCTAssertFalse(notes.contains("KNOWN LIMITATION 3"), "the power multiplier ships now")
        XCTAssertFalse(notes.contains("MULTIPLY THE FINAL SCORE YOURSELF"),
                       "the operator no longer does the power arithmetic by hand")
        XCTAssertTrue(notes.contains("READING THE SPONSOR'S CABRILLO GUIDE CHANGED A FIELD"))
    }
}

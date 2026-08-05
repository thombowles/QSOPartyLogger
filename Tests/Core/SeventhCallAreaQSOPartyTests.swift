import XCTest
@testable import QSOPartyLogger

/// 7th Call Area QSO Party — built from the 7QP consortium's own site, read
/// verbatim 2026-07-26. See docs/research/sevenqp_rules.md.
///
/// **The first multi-state party**, on the schema added in its own commit
/// immediately before this one. One log covers every member state — and there
/// are **eight**, not the seven the worklist's sketch listed.
final class SeventhCallAreaQSOPartyTests: XCTestCase {

    var qp: PartyDefinition!

    override func setUpWithError() throws {
        qp = try XCTUnwrap(PartyCatalog.party(id: "sevenqp"), "bundled 7QP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W7ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "AZYVP"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_726_800 + seq),  // 2026-05-02 13:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "sevenqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "AZYVP") -> ContestLog {
        var log = ContestLog(partyID: "sevenqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Eight states, one log

    /// **It is eight states, not seven.** The worklist's sketch listed
    /// AZ ID MT NV OR UT WY and left Washington out — presumably because
    /// Washington runs its own Salmon Run. It does, *and* it is in the 7th call
    /// area, which is what W7 means.
    func testItCoversEightStatesIncludingWashington() {
        XCTAssertEqual(qp.homeStates, ["AZ", "ID", "MT", "NV", "OR", "UT", "WA", "WY"])
        XCTAssertEqual(qp.homeStates.count, 8)
        XCTAssertTrue(qp.homeStates.contains("WA"), "the state the sketch omitted")
    }

    /// Washington is in two bundled parties at once, and they are different
    /// contests on different weekends.
    func testWashingtonIsAlsoItsOwnParty() throws {
        let warun = try XCTUnwrap(PartyCatalog.party(id: "warun"))
        XCTAssertEqual(warun.homeState, "WA")
        XCTAssertEqual(warun.homeStates, ["WA"], "the Salmon Run is single-state")
        XCTAssertNotEqual(warun.schedule?.first?.start, qp.schedule?.first?.start)
    }

    /// "**259** worked" — the sponsor's own total, in its scoring rule.
    func testTwoHundredFiftyNineCounties() {
        XCTAssertEqual(qp.counties.count, 259)
        XCTAssertEqual(Set(qp.counties.map(\.abbr)).count, 259, "codes are unique")
        XCTAssertEqual(qp.countyAbbrLengths, [5], "state + county, uniformly five letters")
    }

    /// "Exchange state and county, e.g. **AZYVP for Yavapai AZ**" — the code is
    /// the two concatenated, so `County.state` here is a decomposition of what
    /// the sponsor already prints rather than an invention.
    func testTheCodeCarriesItsOwnState() {
        XCTAssertEqual(qp.county(for: "AZYVP")?.name, "Yavapai")
        XCTAssertEqual(qp.state(forCounty: "AZYVP"), "AZ")
        XCTAssertEqual(qp.county(for: "ORDES")?.name, "Deschutes")
        XCTAssertEqual(qp.state(forCounty: "ORDES"), "OR")
        XCTAssertEqual(qp.state(forCounty: "wawha"), "WA", "case-insensitive")

        for county in qp.counties {
            XCTAssertEqual(String(county.abbr.prefix(2)), county.state,
                           "\(county.abbr) should begin with its own state")
        }
    }

    /// **County names repeat freely across the eight states** — Lincoln exists in
    /// six of them — which is exactly why the code carries the state and why the
    /// usual "names must be unique" assertion does not apply here.
    func testCountyNamesRepeatAcrossStatesAndOnlyCodesAreUnique() {
        let lincolns = qp.counties.filter { $0.name == "Lincoln" }
        XCTAssertGreaterThanOrEqual(lincolns.count, 4, "Lincoln is not one county here")
        XCTAssertEqual(Set(lincolns.map(\.abbr)).count, lincolns.count, "…but the codes differ")
        XCTAssertLessThan(Set(qp.counties.map(\.name)).count, qp.counties.count,
                          "names repeat; codes do not")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(qp.cabrilloContest, "7QP")
        XCTAssertEqual(qp.inStateLabel, "the 7th call area",
                       "the setup sheet cannot say \"Inside AZ\" for this one")
        XCTAssertEqual(qp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10])
        XCTAssertEqual(qp.allowedModeClasses, ModeClass.allCases)
        XCTAssertTrue(qp.bonuses.isEmpty)
        XCTAssertNil(qp.scoreMultipliers)
        XCTAssertTrue(qp.isPartiallyVerified)
    }

    /// **No member state is a loggable token** — a station in any of the eight
    /// sends a county code, never a bare state. That falls out of
    /// `excludedStateTokens` defaulting to `homeStates`.
    func testNoMemberStateCanBeLogged() throws {
        XCTAssertEqual(qp.excludedStateTokens, qp.homeStates)
        for token in qp.homeStates {
            XCTAssertFalse(qp.validOutStateTokens.contains(token), token)
            guard case .failure = ExchangeParser.parse(token, party: qp, role: .inState) else {
                return XCTFail("\(token) must be rejected — its stations send county codes")
            }
        }
        XCTAssertEqual(try ExchangeParser.parse("TX", party: qp, role: .inState).get().locations,
                       ["TX"])
    }

    /// "2 points per SSB QSO, 3 points per CW QSO, **4 points per Digital QSO**"
    /// — digital pays most here, which few parties do.
    func testDigitalIsTheHighestPayingMode() {
        XCTAssertEqual(qp.points.points(for: .phone), 2)
        XCTAssertEqual(qp.points.points(for: .cw), 3)
        XCTAssertEqual(qp.points.points(for: .digital), 4)
    }

    /// "Work stations once per band/mode… The same station may be worked on each
    /// band on CW, Phone, and Digital."
    func testDupeScope() {
        XCTAssertEqual(qp.dupeScope, .bandMode)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7A", band: .m20, mode: .cw, their: "AZYVP"),
            qso(call: "W7A", band: .m20, mode: .phone, their: "AZYVP"),
            qso(call: "W7A", band: .m20, mode: .digital, their: "AZYVP"),
            qso(call: "W7A", band: .m20, mode: .cw, their: "AZYVP"),
        ]), party: qp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.qsoPoints, 3 + 2 + 4)
    }

    // MARK: Multipliers — and one log earning several states

    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(qp.multipliers.inState.countScope, .once)
        XCTAssertEqual(qp.multipliers.outState.countScope, .once)
    }

    func testOutOfAreaCeilingIs259() {
        XCTAssertEqual(Set(qp.multipliers.outState.classes), [.county])
        let rows = qp.counties.enumerated().map { i, c in qso(call: "W7\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: qp).multiplierCount, 259)
    }

    /// **The point of the whole schema change.** A station inside the call area
    /// works counties in several member states from one log, and each state's
    /// multiplier is credited separately — because the state comes from the
    /// county, not from the party.
    func testOneLogEarnsEachMemberStateSeparately() {
        XCTAssertTrue(qp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W7A", their: "AZYVP"),
            qso(call: "W7B", their: "AZPMA"),
            qso(call: "W7C", their: "ORDES"),
            qso(call: "W7D", their: "WAWHA"),
            qso(call: "W7E", their: "WYPAR"),
        ], from: "AZYVP"), party: qp)
        XCTAssertEqual(s.validQSOs, 5)
        XCTAssertEqual(Set(s.workedValues(.state)), ["AZ", "OR", "WA", "WY"],
                       "two Arizona counties give one AZ; the rest give their own")
        XCTAssertEqual(s.multiplierCount, 4, "in-state counts states, not counties")
    }

    /// "…and other **DXCC entities (maximum of 10)** worked."
    func testTheDXCCCapIsRecorded() {
        XCTAssertEqual(qp.multipliers.inState.dxMultCap, 10)
    }

    /// "Other DXCC entities (maximum of 10)" — a cap that could never bind
    /// while non-7th-area stations sent the literal `DX` and every entity
    /// collapsed into one. The entity comes from the worked callsign now, so
    /// twelve entities offered pay the ten the sponsor allows.
    func testTheDXCCCapBinds() throws {
        XCTAssertEqual(qp.dxStyle, .token)
        XCTAssertTrue(qp.multipliers.inState.dxCountsEntities)
        XCTAssertEqual(qp.multipliers.inState.dxMultCap, 10)

        let calls = ["DL1A", "JA1B", "G4C", "F5D", "I2E", "EA3F",
                     "SM4G", "OZ5H", "HB9I", "LZ6J", "YU7K", "SP8L"]
        let s = ScoreEngine.score(log: inLog(calls.map {
            qso(call: $0, my: "AZYVP", their: "DX")
        }), party: qp)
        XCTAssertEqual(s.validQSOs, 12)
        XCTAssertEqual(s.workedValues(.dx).count, 10, "ten of the twelve offered")

        // Twelve contacts inside one entity are still one multiplier.
        let same = ScoreEngine.score(log: inLog((0..<12).map {
            qso(call: "DL\($0)AA", my: "AZYVP", their: "DX")
        }), party: qp)
        XCTAssertEqual(same.workedValues(.dx), ["DL"])
    }

    /// **KNOWN LIMITATION 1, pinned.** "WSJT modes do not support the 7QP
    /// exchange, so are not allowed" — but RTTY and PSK *are* allowed, and both
    /// are `.digital`. Fourth user of that gap.
    func testKnownGapTheWSJTExclusionCannotBeEnforced() throws {
        var ft8 = qso(call: "W7FT", mode: .digital, their: "AZYVP")
        ft8.rawMode = "FT8"
        XCTAssertEqual(ScoreEngine.score(log: outLog([ft8]), party: qp).qsoPoints, 4,
                       "it scores as digital, which this party does allow")
        XCTAssertTrue(try XCTUnwrap(qp.notes).contains("KNOWN LIMITATION 1"))
    }

    // MARK: Credit, county lines, schedule

    /// "7th call area stations work everyone, **others work 7th-area stations
    /// only**."
    func testOutOfAreaEntrantsWorkTheCallAreaOnly() {
        XCTAssertTrue(qp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7A", their: "AZYVP"),
            qso(call: "K5B", their: "TX"),
        ]), party: qp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "County-line stations send multiple codes, e.g., **UTRIC/IDBEA**" — and a
    /// county line here can cross a *state* line, which no single-state party
    /// can express.
    func testACountyLineCanCrossAStateLine() throws {
        let parsed = try ExchangeParser.parse("UTRIC/IDBEA", party: qp, role: .inState).get()
        XCTAssertEqual(parsed.locations, ["UTRIC", "IDBEA"])
        XCTAssertEqual(qp.state(forCounty: "UTRIC"), "UT")
        XCTAssertEqual(qp.state(forCounty: "IDBEA"), "ID")
        XCTAssertEqual(qp.county(for: "UTRIC")?.name, "Rich")
        XCTAssertEqual(qp.county(for: "IDBEA")?.name, "Bear Lake")
    }

    /// **OPEN QUESTION 1, pinned.** The rules cap nothing — they require
    /// operation within 500 feet of the line and print a two-county example.
    /// The schema default of 4 ships, which never refuses a legal exchange.
    ///
    /// Note also the sponsor's shorthand `ORDES/JEF`, where the second county
    /// reuses the first's state. This app wants both codes in full.
    func testCountyLinesUseTheSchemaDefaultAndTheShorthandIsNotAccepted() throws {
        XCTAssertEqual(qp.maxSimultaneousCounties, 4)
        XCTAssertEqual(
            try ExchangeParser.parse("ORDES/ORJEF", party: qp, role: .inState).get().locations,
            ["ORDES", "ORJEF"])
        guard case .failure = ExchangeParser.parse("ORDES/JEF", party: qp, role: .inState) else {
            return XCTFail("the sponsor's shorthand is a keystroke difference, not a score one")
        }
        XCTAssertTrue(try XCTUnwrap(qp.notes).contains("OPEN QUESTION 1"))
    }

    func testMobileChangingCountyIsANewStation() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W7MOB", band: .m40, mode: .cw, their: "ORDES"),
            qso(call: "W7MOB", band: .m40, mode: .cw, their: "ORJEF"),
        ]), party: qp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "**1300 UTC Saturday to 0700 UTC Sunday** (6 AM to midnight PDT the first
    /// Saturday in May)" — eighteen hours, one window, and both local glosses
    /// convert correctly.
    func testScheduleIsEighteenHoursFromTheFirstSaturdayInMay() throws {
        let windows = try XCTUnwrap(qp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-05-02T13:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-05-03T07:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 18 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 2,
                       "the first Saturday in May 2026")

        var pacific = Calendar(identifier: .gregorian)
        pacific.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        XCTAssertEqual(pacific.component(.hour, from: windows[0].start), 6, "6 AM PDT")
        XCTAssertEqual(pacific.component(.hour, from: windows[0].end), 0, "midnight PDT")
    }

    /// **The hub does not serve 7QP** — `7qp-table.php` 302-redirects to a login
    /// page, the same trap California's `qp-table.php` sets, where a guessed
    /// prefix yields a poller that runs forever and shows nothing.
    func testThereIsNoHubSource() {
        XCTAssertNil(qp.hubSpots)
    }

    func testNotesRecordTheEightStatesAndTheGaps() throws {
        let notes = try XCTUnwrap(qp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("EIGHT, NOT SEVEN"))
        XCTAssertTrue(notes.contains("ONE LOG COVERS ALL EIGHT MEMBER STATES"))
        XCTAssertTrue(notes.contains("OPEN QUESTION 1"))
    }
}

import XCTest
@testable import QSOPartyLogger

/// New Hampshire QSO Party — PCARC rules "Revised August 19, 2025" (the revision
/// that carries the 2026 dates), read live 2026-07-24. See
/// docs/research/nhqp_rules.md.
final class NewHampshireQSOPartyTests: XCTestCase {

    var nhqp: PartyDefinition!

    override func setUpWithError() throws {
        nhqp = try XCTUnwrap(PartyCatalog.party(id: "nhqp"), "bundled NHQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W1ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "HIL"
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
        var log = ContestLog(partyID: "nhqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "HIL") -> ContestLog {
        var log = ContestLog(partyID: "nhqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — only 10, the smallest county list in the repo

    func testCountyData() {
        XCTAssertEqual(nhqp.counties.count, 10, "New Hampshire has 10 counties")
        XCTAssertEqual(Set(nhqp.counties.map(\.abbr)).count, 10)
        XCTAssertTrue(nhqp.counties.allSatisfy { $0.abbr.count == 3 })
        XCTAssertEqual(nhqp.county(for: "BEL")?.name, "Belknap")
        XCTAssertEqual(nhqp.county(for: "CAR")?.name, "Carroll")
        XCTAssertEqual(nhqp.county(for: "CHE")?.name, "Cheshire")
        XCTAssertEqual(nhqp.county(for: "COO")?.name, "Coos")
        XCTAssertEqual(nhqp.county(for: "GRA")?.name, "Grafton")
        XCTAssertEqual(nhqp.county(for: "HIL")?.name, "Hillsborough")
        XCTAssertEqual(nhqp.county(for: "ROC")?.name, "Rockingham")
        XCTAssertEqual(nhqp.county(for: "STR")?.name, "Strafford")
        XCTAssertEqual(nhqp.county(for: "SUL")?.name, "Sullivan")
        XCTAssertEqual(nhqp.county(for: "hil")?.name, "Hillsborough", "case-insensitive")
    }

    /// The sponsor's rules print "Merrimac (MER)"; the county is Merrimack. The
    /// abbreviation is unaffected — this exists so nobody "fixes" the name back.
    func testMerrimackSpelling() {
        XCTAssertEqual(nhqp.county(for: "MER")?.name, "Merrimack",
                       "sponsor prints 'Merrimac', the county is Merrimack")
    }

    func testPartyShape() {
        XCTAssertEqual(nhqp.cabrilloContest, "NH-QSO-PARTY")
        XCTAssertEqual(nhqp.homeState, "NH")
        XCTAssertEqual(nhqp.countyAbbrLength, 3)
        XCTAssertEqual(nhqp.validBands, [.m80, .m40, .m20, .m15, .m10],
                       "80 through 10 m except WARC — no 160 m, no VHF")
        XCTAssertEqual(nhqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(nhqp.dxStyle, .token, "DX stations send the literal word DX")
        XCTAssertTrue(nhqp.exchangeIncludesRST)
        XCTAssertEqual(nhqp.maxSimultaneousCounties, 1, "no county-line provision exists")
        XCTAssertTrue(nhqp.bonuses.isEmpty, "no bonus station, no bonus points")
        XCTAssertNil(nhqp.scoreMultipliers, "no final-score multiplier")
        XCTAssertTrue(nhqp.isPartiallyVerified)
    }

    /// Two clauses in the superseded June 2025 PDF are gone from the current
    /// revision, so neither is modeled — notably the DC alias that four other
    /// bundled parties do have.
    func testNoDCAliasUnlikeOtherParties() {
        XCTAssertTrue(nhqp.stateAliases.isEmpty,
                      "the 'DC counts as Maryland' clause was removed in the Aug 2025 revision")
        XCTAssertTrue(nhqp.validOutStateTokens.contains("DC"),
                      "DC remains loggable as its own state token")
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(nhqp.points.points(for: .phone), 1)
        XCTAssertEqual(nhqp.points.points(for: .cw), 2)
        XCTAssertEqual(nhqp.points.points(for: .digital), 2)
    }

    // MARK: The asymmetry — out-of-state PER BAND, in-state ONCE

    func testOutOfStateCountsCountiesPerBand() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1A", band: .m40, mode: .cw, their: "HIL"),
            qso(call: "W1A", band: .m20, mode: .cw, their: "HIL"),    // new band: new mult
            qso(call: "W1A", band: .m40, mode: .phone, their: "HIL"), // new mode: nothing
        ]), party: nhqp)
        XCTAssertEqual(s.multiplierCount, 2, "HIL on 40 m and on 20 m; mode is irrelevant")
    }

    /// Rules: "Maximum multiplier count: 50 (10 counties per band, 5 bands)".
    func testOutOfStateCeilingIs50() {
        var rows: [QSO] = []
        var n = 0
        for band in nhqp.validBands {
            for abbr in nhqp.counties.map(\.abbr) {
                n += 1
                rows.append(qso(call: "W1\(n)", band: band, mode: .cw, their: abbr))
            }
        }
        let s = ScoreEngine.score(log: outLog(rows), party: nhqp)
        XCTAssertEqual(s.multiplierCount, 50, "the rules' own stated maximum")
        XCTAssertEqual(s.workedValues(.county).count, 10)
    }

    /// In-state is the opposite: "one multiplier only … once", not per band.
    func testInStateCountsOnceForTheContest() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", band: .m40, my: "HIL", their: "COO"),
            qso(call: "W1A", band: .m20, my: "HIL", their: "COO"),   // same county, other band
            qso(call: "K5B", band: .m40, my: "HIL", their: "TX"),
            qso(call: "K5B", band: .m20, my: "HIL", their: "TX"),    // same state, other band
        ]), party: nhqp)
        XCTAssertEqual(s.multiplierCount, 2, "COO once + TX once, explicitly not per band")
    }

    func testInStateCountsCountiesStatesAndProvinces() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", my: "HIL", their: "COO"),
            qso(call: "K5B", my: "HIL", their: "TX"),
            qso(call: "VE3C", my: "HIL", their: "ON"),
        ]), party: nhqp)
        XCTAssertEqual(s.workedValues(.county), ["COO"])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.multiplierCount, 3)
    }

    /// New Hampshire itself is not described as a state multiplier, and there is
    /// no in-state maximum to settle it by arithmetic, so it does not count.
    func testNewHampshireIsNotAStateMultiplier() {
        XCTAssertFalse(nhqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([qso(my: "HIL", their: "COO")]), party: nhqp)
        XCTAssertEqual(s.workedValues(.state), [], "no NH state mult from an NH county")
        XCTAssertEqual(s.multiplierCount, 1)
        XCTAssertFalse(nhqp.validOutStateTokens.contains("NH"))
    }

    // MARK: The DXCC cap, which the entity table made reachable

    /// "Up to 10 DXCC country" used to be unenforceable: the exchange is
    /// `RS(T) + "DX"`, so every DX station sent the same token and all of them
    /// collapsed to one multiplier. The entity comes from the worked callsign
    /// now, so three entities are three multipliers.
    func testEachDXCCEntityIsItsOwnMultiplier() {
        XCTAssertEqual(nhqp.multipliers.inState.dxMultCap, 10,
                       "'up to 10 DXCC country' is recorded on the rule")
        XCTAssertTrue(nhqp.multipliers.inState.dxCountsEntities)

        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "HIL", their: "DX"),
            qso(call: "JA1B", my: "HIL", their: "DX"),
            qso(call: "G4C", my: "HIL", their: "DX"),
        ]), party: nhqp)
        XCTAssertEqual(s.validQSOs, 3, "all three are valid QSOs worth points")
        XCTAssertEqual(s.qsoPoints, 6)
        XCTAssertEqual(Set(s.workedValues(.dx)), ["Germany", "Japan", "England"],
                       "resolved from the callsign, since the exchange carries no country")
        XCTAssertEqual(s.multiplierCount, 3)
    }

    /// Two stations in one entity are still one multiplier — the point of
    /// counting entities rather than contacts.
    func testTwoStationsInOneEntityAreOneMultiplier() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "HIL", their: "DX"),
            qso(call: "DJ2B", band: .m40, my: "HIL", their: "DX"),
        ]), party: nhqp)
        XCTAssertEqual(s.workedValues(.dx), ["Germany"])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// And the cap now binds, which is what it was recorded for.
    func testTheTenEntityCapBinds() {
        let calls = ["DL1A", "JA1B", "G4C", "F5D", "I2E", "EA3F", "SM4G",
                     "OZ5H", "HB9I", "LZ6J", "YU7K", "SP8L"]
        let s = ScoreEngine.score(log: inLog(calls.map {
            qso(call: $0, my: "HIL", their: "DX")
        }), party: nhqp)
        XCTAssertEqual(s.validQSOs, 12, "all twelve are worth points")
        XCTAssertEqual(s.workedValues(.dx).count, 10, "but only ten count")
        XCTAssertEqual(s.multiplierCount, 10)
    }

    /// A callsign the ARRL list cannot place still earns its contact a
    /// multiplier — falling back to the bare token rather than losing it.
    func testAnUnresolvableCallsignFallsBackToTheBareToken() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "QQ1ZZ", my: "HIL", their: "DX"),
        ]), party: nhqp)
        XCTAssertNil(DXCCTable.shared.entity(forCallsign: "QQ1ZZ"))
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// Out-of-state entrants are unaffected by that limitation: DX is not one of
    /// their multiplier classes at all.
    func testOutOfStateHasNoDXMultiplierClass() {
        XCTAssertFalse(nhqp.multipliers.outState.classes.contains(.dx))
        XCTAssertNil(nhqp.multipliers.outState.dxMultCap)
    }

    // MARK: Dupes — once per band per mode

    func testDupesAndModeSplit() {
        let a = qso(call: "W1M", band: .m40, mode: .cw, their: "STR")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "W1M", band: .m40, mode: .digital, their: "STR")
        let otherBand = qso(call: "W1M", band: .m20, mode: .cw, their: "STR")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, otherBand]), party: nhqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 2,
                       "STR on 40 m and on 20 m — the extra mode adds no multiplier")
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("hil", party: nhqp, role: .inState).get().locations, ["HIL"])
        XCTAssertEqual(try ExchangeParser.parse("MER", party: nhqp, role: .inState).get().locations, ["MER"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: nhqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: nhqp, role: .inState).get().locations, ["DX"])
        guard case .failure = ExchangeParser.parse("NH", party: nhqp, role: .inState) else {
            return XCTFail("NH must be rejected — NH stations send a county")
        }
        XCTAssertEqual(
            ExchangeParser.parse("HIL/COO", party: nhqp, role: .inState),
            .failure(.tooManyCounties(2)),
            "no county-line provision exists"
        )
    }

    // MARK: Schedule — two windows totalling the stated 22 hours

    func testScheduleHasTwoWindowsTotalling22Hours() throws {
        let windows = try XCTUnwrap(nhqp.schedule)
        XCTAssertEqual(windows.count, 2, "Saturday evening and Sunday daytime")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-09-19T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-09-20T04:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-09-20T12:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-09-20T22:00:00Z"))

        let total = windows.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        XCTAssertEqual(total, 22 * 3600, "the rules state 'Total operating time 22 hours'")
    }

    func testNotesRecordTheDXCCFixAndOpenQuestions() throws {
        let notes = nhqp.notes ?? ""
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("THE 10-DXCC ALLOWANCE IS REAL AGAIN"),
                      "the fix must be stated where the undercount used to be")
        XCTAssertTrue(notes.contains("ARRL DXCC List"), "and its source named")
        XCTAssertFalse(notes.contains("KNOWN SCORING LIMITATION"),
                       "the limitation is closed — the warning must not outlive it")
        let questions = try XCTUnwrap(nhqp.openQuestions)
        XCTAssertTrue(questions.contains("only NH stations"))
    }
}

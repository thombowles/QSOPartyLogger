import XCTest
@testable import QSOPartyLogger

/// New England QSO Party — built from neqp.org, read verbatim 2026-07-26. See
/// docs/research/neqp_rules.md.
///
/// **Its id is `newenglandqp`, not `neqp`** — Nebraska took that, and has the
/// better claim to it, since every single-state party's id is its state
/// abbreviation. Both are called NEQP in the wild; their Cabrillo headers
/// disambiguate them.
///
/// **The second multi-state party**, on the schema 7QP proved: one log covers
/// all six member states. **Connecticut no longer uses counties** — it moved to
/// Regional Councils of Government in 2024 — and the sponsor's own example of
/// why 5-letter codes are needed has gone stale as a result.
final class NewEnglandQSOPartyTests: XCTestCase {

    var neqp: PartyDefinition!

    override func setUpWithError() throws {
        neqp = try XCTUnwrap(PartyCatalog.party(id: "newenglandqp"), "bundled NEQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W1ABC", band: Band = .m20, mode: ModeClass = .cw,
        my: String = "TX", their: String = "MAMID"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_752_000 + seq),  // 2026-05-02 20:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "newenglandqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "MAMID") -> ContestLog {
        var log = ContestLog(partyID: "newenglandqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Six states, one log

    func testItCoversSixStates() {
        XCTAssertEqual(neqp.homeStates, ["CT", "MA", "ME", "NH", "RI", "VT"])
        XCTAssertEqual(neqp.inStateLabel, "New England")
        XCTAssertEqual(neqp.counties.count, 68)
        XCTAssertEqual(neqp.countyAbbrLengths, [5], "state + county")
    }

    /// "…for a total of **68 (CT/9 MA/14 ME/16 NH/10 RI/5 VT/14)**" — the
    /// sponsor's own per-state breakdown, which is the arithmetic check.
    func testTheSponsorsPerStateBreakdown() {
        var counts: [String: Int] = [:]
        for c in neqp.counties {
            counts[c.state ?? "?", default: 0] += 1
        }
        XCTAssertEqual(counts, ["CT": 9, "MA": 14, "ME": 16, "NH": 10, "RI": 5, "VT": 14])
        XCTAssertEqual(counts.values.reduce(0, +), 68)
    }

    /// **Connecticut no longer uses counties.** "Note that CT switched from
    /// counties to Regional Councils of Government (2024)" — so its nine are
    /// COGs, and Hartford, New Haven, Fairfield and Litchfield are not
    /// multipliers any more.
    func testConnecticutsNineAreCouncilsOfGovernment() {
        XCTAssertEqual(neqp.county(for: "CTCAP")?.name, "Capital Region")
        XCTAssertEqual(neqp.county(for: "CTNAU")?.name, "Naugatuck Valley")
        XCTAssertEqual(neqp.county(for: "CTNOW")?.name, "Northwest Hills")

        let ctNames = Set(neqp.counties.filter { $0.state == "CT" }.map(\.name))
        for gone in ["Hartford", "New Haven", "Fairfield", "Litchfield"] {
            XCTAssertFalse(ctNames.contains(gone), "\(gone) stopped being a multiplier in 2024")
        }
    }

    /// **The sponsor's own example of why 5-letter codes are needed has gone
    /// stale.** It cites "Middlesex is in MA and CT" — which *was* true, until
    /// Connecticut's Middlesex went with the 2024 COG switch. The convention is
    /// still fully justified, just not by that example: four names still repeat.
    func testTheDuplicateNamesThatJustifyTheCodes() {
        XCTAssertEqual(neqp.counties.filter { $0.name == "Middlesex" }.map(\.abbr), ["MAMID"],
                       "the sponsor's cited example is now a single entry")

        var byName: [String: [String]] = [:]
        for c in neqp.counties { byName[c.name, default: []].append(c.abbr) }
        let dups = byName.filter { $0.value.count > 1 }.mapValues { $0.sorted() }
        XCTAssertEqual(dups, [
            "Franklin": ["MAFRA", "MEFRA", "VTFRA"],
            "Washington": ["MEWAS", "RIWAS", "VTWAS"],
            "Bristol": ["MABRI", "RIBRI"],
            "Essex": ["MAESS", "VTESS"],
        ])
    }

    func testEveryCodeBeginsWithItsOwnState() {
        for c in neqp.counties {
            XCTAssertEqual(String(c.abbr.prefix(2)), c.state, c.abbr)
            XCTAssertEqual(neqp.state(forCounty: c.abbr), c.state)
        }
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(neqp.cabrilloContest, "NEQP")
        XCTAssertEqual(neqp.validBands, [.m80, .m40, .m20, .m15, .m10],
                       "80 through 10 — no 160 m and no VHF")
        XCTAssertEqual(neqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertTrue(neqp.bonuses.isEmpty)
        XCTAssertNil(neqp.scoreMultipliers)
        XCTAssertNil(neqp.hubSpots)
        XCTAssertTrue(neqp.isPartiallyVerified)
    }

    /// "Count one point per phone QSO, two points per CW **(includes digital
    /// modes)** QSO" — digital scores as CW, which the sponsor says outright.
    func testDigitalScoresAsCW() {
        XCTAssertEqual(neqp.points.points(for: .phone), 1)
        XCTAssertEqual(neqp.points.points(for: .cw), 2)
        XCTAssertEqual(neqp.points.points(for: .digital), 2)
    }

    func testNoMemberStateCanBeLogged() throws {
        XCTAssertEqual(neqp.excludedStateTokens, neqp.homeStates)
        for token in neqp.homeStates {
            guard case .failure = ExchangeParser.parse(token, party: neqp, role: .inState) else {
                return XCTFail("\(token) must be rejected — its stations send county codes")
            }
        }
    }

    // MARK: Multipliers

    /// "Total score is QSO points times the multiplier" — no band or mode axis.
    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(neqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(neqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1A", band: .m20, mode: .cw, their: "MAMID"),
            qso(call: "W1A", band: .m40, mode: .cw, their: "MAMID"),
            qso(call: "W1A", band: .m20, mode: .phone, their: "MAMID"),
        ]), party: neqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfAreaCeilingIs68() {
        XCTAssertEqual(Set(neqp.multipliers.outState.classes), [.county])
        let rows = neqp.counties.enumerated().map { i, c in qso(call: "W1\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: neqp).multiplierCount, 68)
    }

    /// "New England stations use states(50)(Count DC as MD), Canadian
    /// provinces(14) and DXCC countries (not USA)" — and **no counties**, so a
    /// New England pair earns points only.
    func testNewEnglandEntrantsCountNoCounties() {
        XCTAssertEqual(Set(neqp.multipliers.inState.classes), [.state, .province, .dx])
        XCTAssertFalse(neqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", my: "MAMID", their: "VTESS"),
            qso(call: "W5B", my: "MAMID", their: "TX"),
        ]), party: neqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.workedValues(.county), [])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
    }

    func testDCCountsAsMaryland() {
        XCTAssertEqual(neqp.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "MAMID", their: "DC"),
            qso(call: "W3B", my: "MAMID", their: "MD"),
        ]), party: neqp)
        XCTAssertEqual(s.workedValues(.state), ["MD"])
    }

    /// **OPEN QUESTION 1, pinned.** "Canadian provinces(**14** – VO1/VO2 are
    /// separate)" gives the count and the reason but **names none of the
    /// tokens**. `NF`/`LB` ship, following the only two other sponsors in this
    /// app that split Newfoundland.
    func testFourteenProvincesWithNewfoundlandSplit() throws {
        XCTAssertEqual(neqp.provinces.count, 14)
        XCTAssertTrue(neqp.provinces.contains("NF"))
        XCTAssertTrue(neqp.provinces.contains("LB"))
        XCTAssertFalse(neqp.provinces.contains("NL"))
        XCTAssertTrue(neqp.provinces.contains("NU"), "unlike North Dakota's list")
        XCTAssertTrue(try XCTUnwrap(neqp.notes).contains("OPEN QUESTION 1"))
    }

    // MARK: Credit, county lines, schedule

    func testOutOfAreaEntrantsWorkNewEnglandOnly() {
        XCTAssertTrue(neqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1A", their: "MAMID"),
            qso(call: "K5B", their: "TX"),
        ]), party: neqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "**County line QSOs should be logged as two separate QSOs.**"
    func testCountyLinesAreLoggedSeparately() {
        XCTAssertEqual(neqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("MAMID/MAESS", party: neqp, role: .inState),
            .failure(.tooManyCounties(2)))
    }

    /// "**2000Z Saturday until 0500Z Sunday** … and **1300Z Sunday until 2400Z
    /// Sunday**" — 20 hours in two legs, and all four local glosses convert.
    func testScheduleIsTwentyHoursInTwoLegs() throws {
        let w = try XCTUnwrap(neqp.schedule)
        XCTAssertEqual(w.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(w[0].start, f.date(from: "2026-05-02T20:00:00Z"))
        XCTAssertEqual(w[0].end, f.date(from: "2026-05-03T05:00:00Z"))
        XCTAssertEqual(w[1].start, f.date(from: "2026-05-03T13:00:00Z"))
        XCTAssertEqual(w[1].end, f.date(from: "2026-05-04T00:00:00Z"))
        XCTAssertEqual(
            w.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }, 20 * 3600,
            "the site's own headline: 20 hours")

        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(eastern.component(.hour, from: w[0].start), 16, "4pm EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[0].end), 1, "1am EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[1].start), 9, "9am EDT")
        XCTAssertEqual(eastern.component(.hour, from: w[1].end), 20, "8pm EDT")
    }

    /// Both multi-state parties open on the same Saturday, which is why the
    /// schema had to land before either.
    func testItSharesItsWeekendWithTheSeventhCallArea() throws {
        let sevenqp = try XCTUnwrap(PartyCatalog.party(id: "sevenqp"))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertTrue(utc.isDate(try XCTUnwrap(neqp.schedule?.first?.start),
                                 inSameDayAs: try XCTUnwrap(sevenqp.schedule?.first?.start)))
        // The two real multi-state contests. The combined May-weekend entry is
        // multi-state too, but it is a shared-log convenience rather than a
        // contest, so it is excluded here.
        XCTAssertEqual(Set(PartyCatalog.loadBundled()
            .filter { $0.homeStates.count > 1 && $0.combines.isEmpty }.map(\.id)),
                       ["sevenqp", "newenglandqp"])
    }

    /// **Regression guard for a real collision.** Both parties are called NEQP,
    /// and the generator for this one first wrote to `neqp.json` — clobbering
    /// Nebraska. They must coexist, with distinct ids, names and Cabrillo
    /// headers.
    func testNebraskaAndNewEnglandBothExistAndAreDistinct() throws {
        let nebraska = try XCTUnwrap(PartyCatalog.party(id: "neqp"))
        XCTAssertEqual(nebraska.name, "Nebraska QSO Party")
        XCTAssertEqual(nebraska.counties.count, 93)
        XCTAssertEqual(nebraska.cabrilloContest, "NE-QSO-PARTY")

        XCTAssertEqual(neqp.name, "New England QSO Party")
        XCTAssertEqual(neqp.counties.count, 68)
        XCTAssertEqual(neqp.cabrilloContest, "NEQP")

        let ids = PartyCatalog.loadBundled().map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "party ids must be unique")
    }

    func testNotesRecordTheConnecticutChange() throws {
        let notes = try XCTUnwrap(neqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("CONNECTICUT NO LONGER USES COUNTIES"))
        XCTAssertTrue(notes.contains("ONE LOG COVERS ALL SIX MEMBER STATES"))
    }
}

import XCTest
@testable import QSOPartyLogger

/// Hawai'i QSO Party — rules read from hawaiiqsoparty.org/rules-page/ on
/// 2026-07-24. See docs/research/hqp_rules.md for the full research, including
/// the sponsor's self-contradictory operating window.
final class HawaiiQSOPartyTests: XCTestCase {

    var hqp: PartyDefinition!

    override func setUpWithError() throws {
        hqp = try XCTUnwrap(PartyCatalog.party(id: "hqp"), "bundled HQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "KH6ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "HON"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "hqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from district: String = "HON") -> ContestLog {
        var log = ContestLog(partyID: "hqp")
        log.myLocation = .inState(counties: [district])
        log.qsos = qsos
        return log
    }

    // MARK: District data — the 14 multipliers from the sponsor's map

    func testDistrictData() {
        XCTAssertEqual(hqp.counties.count, 14, "14 Hawai'i districts")
        XCTAssertEqual(Set(hqp.counties.map(\.abbr)).count, 14)
        // Four districts inside Honolulu County alone — these are not counties.
        XCTAssertEqual(hqp.county(for: "HON")?.name, "Honolulu")
        XCTAssertEqual(hqp.county(for: "LHN")?.name, "Leeward")
        XCTAssertEqual(hqp.county(for: "PRL")?.name, "Pearl Harbor Area")
        XCTAssertEqual(hqp.county(for: "WHN")?.name, "Windward")
        // Four more inside Hawai'i County.
        XCTAssertEqual(hqp.county(for: "KOH")?.name, "Kohala")
        XCTAssertEqual(hqp.county(for: "KON")?.name, "Kona")
        XCTAssertEqual(hqp.county(for: "VOL")?.name, "Volcano Park")
        XCTAssertEqual(hqp.county(for: "HIL")?.name, "Hilo")
        // Kalawao is a county with exactly one district of the same name.
        XCTAssertEqual(hqp.county(for: "KAL")?.name, "Kalawao")
        // Sparsely populated but valid entities.
        XCTAssertEqual(hqp.county(for: "NII")?.name, "Niihau")
        XCTAssertEqual(hqp.county(for: "LNI")?.name, "Lana'i")
        XCTAssertEqual(hqp.county(for: "kau")?.name, "Kauai", "lookup is case-insensitive")
    }

    func testPartyShape() {
        XCTAssertEqual(hqp.cabrilloContest, "HI-QSO-PARTY")
        XCTAssertEqual(hqp.homeState, "HI")
        XCTAssertEqual(hqp.countyAbbrLength, 3)
        XCTAssertEqual(hqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10],
                       "rule 2: 10/15/20/40/80/160 only")
        XCTAssertEqual(hqp.allowedModeClasses, ModeClass.allCases,
                       "all three modes are legal — digital is first class here")
        XCTAssertEqual(hqp.dxStyle, .token, "non-USA/Canada send the literal 'DX'")
        XCTAssertTrue(hqp.exchangeIncludesRST, "exchange is signal report + QTH")
        XCTAssertTrue(hqp.outStateWorksHomeStationsOnly,
                      "non-Hawai'i stations work only Hawai'i")
        XCTAssertEqual(hqp.maxSimultaneousCounties, 1, "no district-line provision")
        XCTAssertTrue(hqp.bonuses.isEmpty, "no bonus station, no bonus points")
        XCTAssertNil(hqp.scoreMultipliers, "score is points x mults, nothing else")
    }

    // MARK: Points — SSB 2, CW 3, digital 3

    func testPointsByMode() {
        XCTAssertEqual(hqp.points.points(for: .phone), 2)
        XCTAssertEqual(hqp.points.points(for: .cw), 3)
        XCTAssertEqual(hqp.points.points(for: .digital), 3)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "KH6A", mode: .phone, their: "HON"),
            qso(call: "KH6B", mode: .cw, their: "HIL"),
            qso(call: "KH6C", mode: .digital, their: "MAU"),
        ]), party: hqp)
        XCTAssertEqual(s.qsoPoints, 2 + 3 + 3)
        XCTAssertEqual(s.invalidModeCount, 0, "digital is a legal mode in HQP")
    }

    // MARK: Out-of-state multipliers count PER BAND — ceiling 84

    func testOutOfStateDistrictsCountPerBand() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "KH6A", band: .m40, mode: .cw, their: "HON"),
            qso(call: "KH6A", band: .m20, mode: .cw, their: "HON"),   // new band: new mult
            qso(call: "KH6A", band: .m40, mode: .phone, their: "HON"), // new mode only: no new mult
        ]), party: hqp)
        XCTAssertEqual(s.multiplierCount, 2, "HON on 40 m and HON on 20 m; mode is irrelevant")
        XCTAssertEqual(s.validQSOs, 3, "all three are workable — once per band-mode")
    }

    /// The rules' own ceiling: "Maximum of 84 (6 bands x 14 districts)".
    func testOutOfStateMultiplierCeilingIs84() {
        var rows: [QSO] = []
        for band in hqp.validBands {
            for district in hqp.counties.map(\.abbr) {
                rows.append(qso(call: "KH6\(district)", band: band, mode: .cw, their: district))
            }
        }
        let s = ScoreEngine.score(log: outLog(rows), party: hqp)
        XCTAssertEqual(s.multiplierCount, 84, "6 bands x 14 districts")
        XCTAssertEqual(s.workedValues(.county).count, 14)
    }

    // MARK: In-state multipliers count ONCE — "NOT PER BAND"

    func testInStateMultipliersCountOnceForTheContest() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "KH6A", band: .m40, my: "HON", their: "HIL"),
            qso(call: "KH6A", band: .m20, my: "HON", their: "HIL"),   // same district, other band
            qso(call: "K5B", band: .m40, my: "HON", their: "TX"),     // state
            qso(call: "K5B", band: .m20, my: "HON", their: "TX"),     // same state, other band
        ]), party: hqp)
        XCTAssertEqual(s.multiplierCount, 2, "HIL once + TX once, explicitly not per band")
    }

    func testInStateCountsAllFourClasses() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "KH6A", my: "HON", their: "KON"),   // district
            qso(call: "K5B", my: "HON", their: "TX"),     // state
            qso(call: "K3C", my: "HON", their: "DC"),     // DC counts as a state
            qso(call: "VE3D", my: "HON", their: "ON"),    // province
            qso(call: "JA1E", my: "HON", their: "DX"),    // DXCC via the DX token
        ]), party: hqp)
        XCTAssertEqual(s.workedValues(.county), ["KON"])
        XCTAssertEqual(s.workedValues(.state), ["TX", "DC"], "states including DC")
        XCTAssertEqual(s.workedValues(.province), ["ON"])
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        XCTAssertEqual(s.multiplierCount, 5)
    }

    /// Unlike NHQP, Hawai'i stations have no cap on DXCC multipliers.
    func testNoDXMultiplierCap() {
        XCTAssertNil(hqp.multipliers.inState.dxMultCap)
    }

    // MARK: "non-Hawai'i stations work only Hawai'i"

    func testOutOfStateEarnsNothingForNonHawaiiContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "KH6A", their: "HON"),   // Hawai'i: counts
            qso(call: "K5B", their: "TX"),     // mainland: no credit
            qso(call: "VE3C", their: "ON"),    // province: no credit
            qso(call: "JA1D", their: "DX"),    // DX: no credit
        ]), party: hqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 3)
        XCTAssertEqual(s.qsoPoints, 3, "only the Hawai'i CW contact scores")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    /// The same log scored as a Hawai'i entrant: everyone counts.
    func testInStateWorksAnyone() {
        let rows = [
            qso(call: "KH6A", my: "HON", their: "KAU"),
            qso(call: "K5B", my: "HON", their: "TX"),
            qso(call: "VE3C", my: "HON", their: "ON"),
            qso(call: "JA1D", my: "HON", their: "DX"),
        ]
        let s = ScoreEngine.score(log: inLog(rows), party: hqp)
        XCTAssertEqual(s.outOfScopeCount, 0)
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.qsoPoints, 12, "four CW QSOs at 3 points")
    }

    // MARK: Dupes — once per band-mode, so three contacts per band

    func testThreeContactsPerBandOneEachMode() {
        let rows = [
            qso(call: "KH6M", band: .m40, mode: .cw, their: "MOL"),
            qso(call: "KH6M", band: .m40, mode: .phone, their: "MOL"),
            qso(call: "KH6M", band: .m40, mode: .digital, their: "MOL"),
        ]
        var withDupe = rows
        var repeated = rows[0]
        repeated.id = UUID()
        repeated.timestampUTC = rows[0].timestampUTC.addingTimeInterval(600)
        withDupe.append(repeated)

        let s = ScoreEngine.score(log: outLog(withDupe), party: hqp)
        XCTAssertEqual(s.validQSOs, 3, "once each on CW, SSB, digital")
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.multiplierCount, 1, "one district on one band, regardless of mode")
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("hon", party: hqp).get().locations, ["HON"])
        XCTAssertEqual(try ExchangeParser.parse("VOL", party: hqp).get().locations, ["VOL"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: hqp).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: hqp).get().locations, ["DX"],
                       "non-USA/Canada send the literal token")
        XCTAssertEqual(try ExchangeParser.parse("DC", party: hqp).get().locations, ["DC"])
        // Hawai'i stations send a district, so the bare state token is invalid.
        guard case .failure = ExchangeParser.parse("HI", party: hqp) else {
            return XCTFail("HI token must be rejected — Hawai'i stations send a district")
        }
        // No district-line provision.
        XCTAssertEqual(
            ExchangeParser.parse("HON/LHN", party: hqp),
            .failure(.tooManyCounties(2))
        )
    }

    // MARK: Schedule — see hqp_rules.md §2; sponsor's rule 1 contradicts itself

    func testScheduleUsesTheOnly36HourReading() throws {
        let windows = try XCTUnwrap(hqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-08-22T16:00:00Z"),
                       "6am Saturday Hawaii time (HST = UTC-10)")
        XCTAssertEqual(windows[0].end, f.date(from: "2026-08-24T04:00:00Z"),
                       "6pm Sunday Hawaii time")
        XCTAssertEqual(
            windows[0].end.timeIntervalSince(windows[0].start), 36 * 3600,
            "rule 1 says 36 hours; only 1600Z->0400Z satisfies that and both HST anchors"
        )
    }

    /// The party ships `verified: partial` precisely because of that conflict —
    /// guard the marker so nobody quietly promotes it without re-verifying.
    func testNotesRecordThePartialVerification() {
        let notes = hqp.notes ?? ""
        XCTAssertTrue(notes.contains("verified: partial"), "notes must carry the marker")
        XCTAssertTrue(notes.contains("info@hawaiiqsoparty.org"),
                      "notes must say who to ask to resolve the open question")
    }
}

import XCTest
@testable import QSOPartyLogger

/// Ohio QSO Party — rules from ohqp.org (captured 2026-07-23, re-checked
/// 2026-07-24). See docs/research/ohqp_rules.md.
final class OhioQSOPartyTests: XCTestCase {

    var ohqp: PartyDefinition!

    override func setUpWithError() throws {
        ohqp = try XCTUnwrap(PartyCatalog.party(id: "ohqp"), "bundled OhQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "K8ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "CUYA"
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
        var log = ContestLog(partyID: "ohqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "CUYA") -> ContestLog {
        var log = ContestLog(partyID: "ohqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — the sponsor's official list

    func testCountyData() {
        XCTAssertEqual(ohqp.counties.count, 88, "Ohio has 88 counties")
        XCTAssertEqual(Set(ohqp.counties.map(\.abbr)).count, 88)
        XCTAssertTrue(ohqp.counties.allSatisfy { $0.abbr.count == 4 },
                      "OhQP abbreviations are 4 letters")
        XCTAssertEqual(ohqp.county(for: "CUYA")?.name, "Cuyahoga")
        XCTAssertEqual(ohqp.county(for: "TUSC")?.name, "Tuscarawas")
        XCTAssertEqual(ohqp.county(for: "WYAN")?.name, "Wyandot", "Wyandot, not Wyandotte")
        XCTAssertEqual(ohqp.county(for: "MUSK")?.name, "Muskingum")
        XCTAssertEqual(ohqp.county(for: "COSH")?.name, "Coshocton")
        XCTAssertEqual(ohqp.county(for: "GUER")?.name, "Guernsey")
        XCTAssertEqual(ohqp.county(for: "ashl")?.name, "Ashland", "lookup is case-insensitive")
        // Ashland and Ashtabula both start ASH — the abbreviations must not collide.
        XCTAssertEqual(ohqp.county(for: "ASHT")?.name, "Ashtabula")
    }

    /// The sponsor's official list misspells two counties; the generator keeps
    /// their abbreviations verbatim and corrects the display names.
    func testSponsorCountyNameTyposAreCorrected() {
        XCTAssertEqual(ohqp.county(for: "AUGL")?.name, "Auglaize", "sponsor prints 'Auglaze'")
        XCTAssertEqual(ohqp.county(for: "VANW")?.name, "Van Wert", "sponsor prints 'VanWert'")
    }

    func testPartyShape() {
        XCTAssertEqual(ohqp.cabrilloContest, "MRRC-OHQP")
        XCTAssertEqual(ohqp.homeState, "OH")
        XCTAssertEqual(ohqp.countyAbbrLength, 4)
        XCTAssertEqual(ohqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10])
        XCTAssertEqual(ohqp.allowedModeClasses, [.phone, .cw], "CW and SSB only")
        XCTAssertEqual(ohqp.dxStyle, .token, "DX stations send the literal 'DX'")
        XCTAssertTrue(ohqp.exchangeIncludesRST)
        XCTAssertTrue(ohqp.outStateWorksHomeStationsOnly,
                      "non-Ohio stations may work only Ohio stations")
        XCTAssertEqual(ohqp.maxSimultaneousCounties, 1,
                       "simultaneous multi-county operation is forbidden")
        XCTAssertTrue(ohqp.bonuses.isEmpty)
        XCTAssertNil(ohqp.scoreMultipliers)
    }

    // MARK: Points — phone 1, CW 2, no digital

    func testPointsByMode() {
        XCTAssertEqual(ohqp.points.points(for: .phone), 1)
        XCTAssertEqual(ohqp.points.points(for: .cw), 2)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K8A", mode: .cw, their: "CUYA"),
            qso(call: "K8B", mode: .phone, their: "FRAN"),
        ]), party: ohqp)
        XCTAssertEqual(s.qsoPoints, 3)
    }

    func testDigitalRowsAreInvalid() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K8A", mode: .cw, their: "CUYA"),
            qso(call: "K8B", mode: .digital, their: "FRAN"),
        ]), party: ohqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1, "digital is not an OhQP mode")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Multipliers count PER MODE

    func testMultsCountPerModeNotPerBand() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K8A", band: .m40, mode: .cw, their: "CUYA"),
            qso(call: "K8A", band: .m40, mode: .phone, their: "CUYA"),  // other mode: 2nd mult
            qso(call: "K8B", band: .m20, mode: .cw, their: "CUYA"),     // other band: NO new mult
        ]), party: ohqp)
        XCTAssertEqual(s.multiplierCount, 2,
                       "CUYA on CW + CUYA on phone; the band change adds nothing")
        XCTAssertEqual(s.validQSOs, 3)
    }

    /// Rules: "Total of 150 multipliers for Ohio Stations" — 88 counties + 49
    /// states + DC + 11 provinces + 1 DX. Built through the engine.
    func testOhioStationMultiplierUniverseIs150() {
        var rows: [QSO] = []
        var n = 0
        func add(_ loc: String) {
            n += 1
            rows.append(qso(call: "W\(n)", mode: .cw, my: "CUYA", their: loc))
        }
        ohqp.counties.map(\.abbr).forEach(add)
        MultClass.acceptedStateTokens.subtracting(["OH"]).sorted().forEach(add)
        ohqp.provinces.sorted().forEach(add)
        add("DX")

        let s = ScoreEngine.score(log: inLog(rows), party: ohqp)
        XCTAssertEqual(s.workedValues(.county).count, 88)
        XCTAssertEqual(s.workedValues(.state).count, 50, "49 states + DC, Ohio excluded")
        XCTAssertEqual(s.workedValues(.province).count, 11)
        XCTAssertEqual(s.workedValues(.dx).count, 1)
        XCTAssertEqual(s.multiplierCount, 150, "the rules' own stated total")
    }

    /// …and because mults are per mode, working that universe on both modes
    /// doubles it.
    func testPerModeScopeDoublesTheUniverse() {
        var rows: [QSO] = []
        var n = 0
        for mode in [ModeClass.cw, .phone] {
            for abbr in ohqp.counties.map(\.abbr) {
                n += 1
                rows.append(qso(call: "W\(n)", mode: mode, their: abbr))
            }
        }
        let s = ScoreEngine.score(log: outLog(rows), party: ohqp)
        XCTAssertEqual(s.multiplierCount, 176, "88 counties x 2 modes")
    }

    // MARK: Provinces — only 11, and NT is the combined Yukon/NWT/Nunavut entity

    func testOnlyElevenProvincesCountAndNTIsCombined() {
        XCTAssertEqual(ohqp.provinces.count, 11, "rules count 11, not the usual 13")
        XCTAssertTrue(ohqp.provinces.contains("NT"), "NT = Yukon-NWT-Nu, one multiplier")
        XCTAssertFalse(ohqp.provinces.contains("YT"), "Yukon is folded into NT")
        XCTAssertFalse(ohqp.provinces.contains("NU"), "Nunavut is folded into NT")
        XCTAssertEqual(
            ohqp.provinces,
            ["NL", "PE", "NS", "NB", "QC", "ON", "MB", "SK", "AB", "BC", "NT"].reduce(into: Set()) {
                $0.insert($1)
            }
        )
        // NT scores as a province; YT and NU are not valid tokens at all.
        let s = ScoreEngine.score(log: inLog([qso(my: "CUYA", their: "NT")]), party: ohqp)
        XCTAssertEqual(s.workedValues(.province), ["NT"])
    }

    func testYukonAndNunavutTokensAreRejected() {
        XCTAssertTrue(ohqp.validOutStateTokens.contains("NT"))
        XCTAssertFalse(ohqp.validOutStateTokens.contains("YT"),
                       "a Yukon station sends NT per the official list")
        XCTAssertFalse(ohqp.validOutStateTokens.contains("NU"))
        guard case .failure = ExchangeParser.parse("YT", party: ohqp, role: .inState) else {
            return XCTFail("YT must be rejected — the official list folds it into NT")
        }
    }

    // MARK: "Non-Ohio stations may work only Ohio stations"

    func testOutOfStateEarnsNothingForNonOhioContacts() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K8A", their: "CUYA"),   // Ohio: counts
            qso(call: "K5B", their: "TX"),     // no credit
            qso(call: "VE3C", their: "ON"),    // no credit
            qso(call: "JA1D", their: "DX"),    // no credit
        ]), party: ohqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 3)
        XCTAssertEqual(s.qsoPoints, 2, "one CW QSO")
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testInStateWorksAnyone() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K8A", my: "CUYA", their: "FRAN"),
            qso(call: "K5B", my: "CUYA", their: "TX"),
            qso(call: "VE3C", my: "CUYA", their: "ON"),
            qso(call: "JA1D", my: "CUYA", their: "DX"),
        ]), party: ohqp)
        XCTAssertEqual(s.outOfScopeCount, 0)
        XCTAssertEqual(s.multiplierCount, 4)
    }

    // MARK: Dupes — 12 contacts per station max (6 bands x 2 modes)

    func testTwelveContactsPerStationCeiling() {
        var rows: [QSO] = []
        for band in ohqp.validBands {
            for mode in [ModeClass.cw, .phone] {
                rows.append(qso(call: "K8MAD", band: band, mode: mode, their: "MEDI"))
            }
        }
        var withDupe = rows
        var repeated = rows[0]
        repeated.id = UUID()
        repeated.timestampUTC = rows[0].timestampUTC.addingTimeInterval(900)
        withDupe.append(repeated)

        let s = ScoreEngine.score(log: outLog(withDupe), party: ohqp)
        XCTAssertEqual(s.validQSOs, 12, "6 bands x 2 modes")
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.multiplierCount, 2, "one county, per mode — not per band")
    }

    func testMobileCountyChangeIsANewStation() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K8MOB", band: .m40, mode: .cw, their: "LUCA"),
            qso(call: "K8MOB", band: .m40, mode: .cw, their: "WOOD"),
        ]), party: ohqp)
        XCTAssertEqual(s.validQSOs, 2, "rovers changing county may be worked again")
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("cuya", party: ohqp, role: .inState).get().locations, ["CUYA"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: ohqp, role: .inState).get().locations, ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DC", party: ohqp, role: .inState).get().locations, ["DC"],
                       "DC is its own multiplier")
        XCTAssertEqual(try ExchangeParser.parse("DX", party: ohqp, role: .inState).get().locations, ["DX"])
        // "Ohio stations must list county abbreviation and NOT OH or OHIO!"
        guard case .failure = ExchangeParser.parse("OH", party: ohqp, role: .inState) else {
            return XCTFail("OH token must be rejected")
        }
        // Simultaneous multi-county operation is forbidden.
        XCTAssertEqual(
            ExchangeParser.parse("LUCA/WOOD", party: ohqp, role: .inState),
            .failure(.tooManyCounties(2))
        )
    }

    // MARK: Schedule — fourth Saturday of August, 12 hours

    func testSchedule() throws {
        let windows = try XCTUnwrap(ohqp.schedule)
        XCTAssertEqual(windows.count, 1, "a single 12-hour period")
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-08-22T16:00:00Z"),
                       "noon EDT on the fourth Saturday of August 2026")
        XCTAssertEqual(windows[0].end, f.date(from: "2026-08-23T04:00:00Z"),
                       "midnight EDT")
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600)
    }

    // MARK: Cabrillo — the sponsor is strict about the QSO line

    func testCabrilloQSOLineMatchesSponsorSpec() {
        // "Correct number of fields: 10" and "Mode is CW or PH".
        let line = CabrilloExporter.qsoLine(
            qso(call: "K8ABC", band: .m40, mode: .phone, my: "TX", their: "CUYA"),
            myCall: "KE5CW"
        )
        let fields = line.split(separator: " ", omittingEmptySubsequences: true)
        XCTAssertEqual(fields.first, "QSO:")
        XCTAssertEqual(fields.count, 11, "the QSO: tag plus the sponsor's 10 fields")
        XCTAssertEqual(fields[2], "PH", "phone must be PH, not SSB")
        XCTAssertEqual(CabrilloExporter.cabrilloMode("CW"), "CW")
    }
}

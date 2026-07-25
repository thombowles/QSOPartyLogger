import XCTest
@testable import QSOPartyLogger

/// Pennsylvania QSO Party — PA QSO Party Association rules PDF, `Revision:
/// 08/19/25`, plus the sponsor's two official abbreviation PDFs, all read
/// verbatim 2026-07-24. See docs/research/paqp_rules.md.
///
/// PAQP is the first party whose non-county exchange is an **ARRL/RAC section**
/// rather than a state or province, and the first to be granted multipliers
/// outright (EPA and WPA, which nobody ever sends).
final class PennsylvaniaQSOPartyTests: XCTestCase {

    var paqp: PartyDefinition!

    override func setUpWithError() throws {
        paqp = try XCTUnwrap(PartyCatalog.party(id: "paqp"), "bundled PAQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W3ABC",
        band: Band = .m40,
        mode: ModeClass = .cw,
        my: String = "NTX",
        their: String = "ALL",
        serialSent: Int? = 1,
        serialRcvd: Int? = 1
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_600_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            serialSent: serialSent, serialRcvd: serialRcvd,
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "paqp")
        log.myLocation = .outOfState(location: "NTX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "ALL") -> ContestLog {
        var log = ContestLog(partyID: "paqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 67, ten of them irregular

    func testCountyData() {
        XCTAssertEqual(paqp.counties.count, 67, "rule 10.b: 'Out-of-State Multipliers: 67 PA Counties'")
        XCTAssertEqual(Set(paqp.counties.map(\.abbr)).count, 67)
        XCTAssertEqual(Set(paqp.counties.map(\.name)).count, 67)
        XCTAssertTrue(paqp.counties.allSatisfy { $0.abbr.count == 3 })
        XCTAssertEqual(paqp.countyAbbrLengths, [3])
    }

    /// The ten abbreviations that are not the first three letters. Each exists to
    /// break a collision cluster — `ALL`→Allegheny would prove nothing.
    func testIrregularAbbreviations() {
        XCTAssertEqual(paqp.county(for: "BUX")?.name, "Bucks", "not BUC — BUT is Butler")
        XCTAssertEqual(paqp.county(for: "BUT")?.name, "Butler")
        XCTAssertEqual(paqp.county(for: "CMB")?.name, "Cambria", "CAM would collide with Cameron")
        XCTAssertEqual(paqp.county(for: "CRN")?.name, "Cameron")
        XCTAssertEqual(paqp.county(for: "CAR")?.name, "Carbon")
        XCTAssertEqual(paqp.county(for: "DCO")?.name, "Delaware", "not DEL")
        XCTAssertEqual(paqp.county(for: "INN")?.name, "Indiana", "not IND")
        XCTAssertEqual(paqp.county(for: "MOE")?.name, "Monroe")
        XCTAssertEqual(paqp.county(for: "MGY")?.name, "Montgomery")
        XCTAssertEqual(paqp.county(for: "MTR")?.name, "Montour")
        XCTAssertEqual(paqp.county(for: "NHA")?.name, "Northampton")
        XCTAssertEqual(paqp.county(for: "NUM")?.name, "Northumberland")
        XCTAssertEqual(paqp.county(for: "MCK")?.name, "McKean", "internal capital")
        XCTAssertEqual(paqp.county(for: "bux")?.name, "Bucks", "case-insensitive")

        for wrong in ["BUC", "CAM", "DEL", "IND", "MON", "NOR"] {
            XCTAssertNil(paqp.county(for: wrong), "'\(wrong)' is ambiguous or wrong in PAQP")
        }
    }

    func testPartyShape() {
        XCTAssertEqual(paqp.cabrilloContest, "PA-QSO-PARTY", "WA7BNM registry; sponsor prints none")
        XCTAssertEqual(paqp.homeState, "PA")
        XCTAssertEqual(paqp.allowedModeClasses, [.phone, .cw],
                       "the change log records 'Removed digital modes'")
        XCTAssertEqual(paqp.dxStyle, .token, "'or \"DX\"' — the literal token")
        XCTAssertEqual(paqp.dupeScope, .bandMode, "'Work stations once per band and mode'")
        XCTAssertEqual(paqp.maxSimultaneousCounties, 4,
                       "'at least two or more adjacent counties', no stated maximum")
        XCTAssertTrue(paqp.outStateWorksHomeStationsOnly)
        XCTAssertTrue(paqp.isPartiallyVerified, "2025 rules revision + unannounced bonus station")
    }

    /// "Sequential serial number plus PA county, ARRL section, Canadian section,
    /// or 'DX'" — a number, and no signal report. Second party to need serials.
    func testExchangeIsASerialWithNoRST() {
        XCTAssertTrue(paqp.exchangeIncludesSerial)
        XCTAssertFalse(paqp.exchangeIncludesRST)
    }

    /// Ten bands — everything but the WARC exclusions.
    func testValidBands() {
        XCTAssertEqual(
            paqp.validBands,
            [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2, .cm125, .cm70],
            "the widest band list of any bundled party"
        )
        for warc in [Band.m12, .m17, .m30, .m60] {
            XCTAssertFalse(paqp.validBands.contains(warc),
                           "rule 3.b excludes \(warc.rawValue)")
        }
        // The rules also permit 630 m / 2200 m, which Band cannot express — a
        // limitation recorded in notes rather than silently dropped.
        XCTAssertTrue(try! XCTUnwrap(paqp.notes).contains("630 m"))
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(paqp.points.points(for: .cw), 2, "CW: 2 points/QSO")
        XCTAssertEqual(paqp.points.points(for: .phone), 1, "Phone: 1 point/QSO")
        XCTAssertNil(paqp.homeStationPoints, "PAQP pays by mode, not by who was worked")
    }

    func testDigitalRowsAreInvalidNotZeroScored() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", mode: .cw, their: "ALL"),
            qso(call: "W3B", mode: .digital, their: "PHI"),
        ]), party: paqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 1)
        XCTAssertEqual(s.qsoPoints, 2)
    }

    // MARK: Sections — the reason this party needed a new multiplier class

    func testSectionsSupplantStatesAndProvinces() {
        XCTAssertTrue(paqp.usesSections)
        XCTAssertEqual(paqp.sections.count, 85, "71 US + 14 Canadian")

        // Sections that are not state codes at all.
        for section in ["EMA", "WMA", "NLI", "ENY", "NNY", "SNJ", "NFL", "SFL", "WCF",
                        "NTX", "STX", "WTX", "EB", "LAX", "ORG", "PAC", "SCV", "SDG",
                        "SJV", "SV", "EWA", "WWA", "MDC", "EPA", "WPA"] {
            XCTAssertTrue(paqp.sections.contains(section), "\(section) is an ARRL section")
        }
        // State and province codes that are NOT PAQP tokens.
        for notAToken in ["TX", "NY", "CA", "FL", "MA", "WA", "NJ", "PA", "ON", "NT", "NU", "YT"] {
            XCTAssertFalse(paqp.sections.contains(notAToken),
                           "'\(notAToken)' is a state/province code, not a PAQP section")
            XCTAssertFalse(paqp.validOutStateTokens.contains(notAToken))
        }
    }

    /// Canada is 14 sections, and differs in kind from every previous party's
    /// list — Ontario alone is four tokens and the territories are one.
    func testCanadaIsFourteenSectionsNotThirteenProvinces() {
        for canadian in ["AB", "BC", "GH", "MB", "NB", "NL", "NS",
                         "ONE", "ONN", "ONS", "PE", "QC", "SK", "TER"] {
            XCTAssertTrue(paqp.sections.contains(canadian), canadian)
        }
        XCTAssertTrue(paqp.sections.contains("GH"), "Ontario Golden Horseshoe")
        for gone in ["NT", "NU", "YT"] {
            XCTAssertFalse(paqp.sections.contains(gone), "\(gone) is TER in PAQP")
        }
    }

    func testSectionsScoreForInStateEntrants() {
        XCTAssertEqual(Set(paqp.multipliers.inState.classes), [.county, .section, .dx])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", my: "ALL", their: "EMA"),
            qso(call: "K5B", my: "ALL", their: "NTX"),
            qso(call: "VE3C", my: "ALL", their: "ONS"),
        ]), party: paqp)
        // EPA and WPA are always there, granted by rule 12.d.
        XCTAssertEqual(s.workedValues(.section), ["EMA", "NTX", "ONS", "EPA", "WPA"])
        XCTAssertEqual(s.workedValues(.state), [], "PAQP has no state class")
        XCTAssertEqual(s.workedValues(.province), [])
        XCTAssertEqual(s.multiplierCount, 5, "three worked sections plus the two granted")
    }

    // MARK: EPA and WPA, granted outright

    /// Rule 12.d: "EPA and WPA multipliers are automatically added during the
    /// rescore process – there is no need to enter them." PA stations send a
    /// county, so neither token is ever transmitted.
    func testEPAAndWPAAreGrantedToInStateEntrants() {
        XCTAssertEqual(
            paqp.multipliers.inState.granted,
            [.init(multClass: .section, value: "EPA"),
             .init(multClass: .section, value: "WPA")]
        )
        let empty = ScoreEngine.score(log: inLog([]), party: paqp)
        XCTAssertEqual(empty.workedValues(.section), ["EPA", "WPA"])
        XCTAssertEqual(empty.multiplierCount, 2)

        let s = ScoreEngine.score(log: inLog([
            qso(call: "W1A", my: "ALL", their: "EMA"),
        ]), party: paqp)
        XCTAssertEqual(s.multiplierCount, 3, "EPA + WPA granted, EMA worked")
        XCTAssertEqual(s.total, 2 * 3, "2 CW points × 3 multipliers")
    }

    /// Out-of-state entrants count the 67 counties and nothing else, so they get
    /// no free sections.
    func testOutOfStateGetsNoGrantedSections() {
        XCTAssertTrue(paqp.multipliers.outState.granted.isEmpty)
        XCTAssertEqual(Set(paqp.multipliers.outState.classes), [.county])
        let s = ScoreEngine.score(log: outLog([qso(their: "ALL")]), party: paqp)
        XCTAssertEqual(s.workedValues(.section), [])
        XCTAssertEqual(s.multiplierCount, 1)
    }

    // MARK: Multipliers count ONCE — clarified deliberately in 2023

    func testMultipliersCountOnceNotPerBandOrMode() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", band: .m40, mode: .cw, their: "ALL"),
            qso(call: "W3A", band: .m20, mode: .cw, their: "ALL"),    // other band
            qso(call: "W3A", band: .m40, mode: .phone, their: "ALL"), // other mode
        ]), party: paqp)
        XCTAssertEqual(s.multiplierCount, 1,
                       "would be 3 under perBandMode, 2 under perBand or perMode")
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 5, "CW 2 + CW 2 + phone 1")
    }

    func testOutOfStateCeilingIs67() {
        let rows = paqp.counties.enumerated().map { i, c in qso(call: "W3\(i)", their: c.abbr) }
        let s = ScoreEngine.score(log: outLog(rows), party: paqp)
        XCTAssertEqual(s.multiplierCount, 67, "the rules' own stated maximum")
    }

    /// "+ 1 DX" — the tightest DX cap in the repo, and the token exchange
    /// collapses every DX station to one multiplier in any case.
    func testExactlyOneDXMultiplier() {
        XCTAssertEqual(paqp.multipliers.inState.dxMultCap, 1)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "DL1A", my: "ALL", their: "DX"),
            qso(call: "JA1B", my: "ALL", their: "DX"),
            qso(call: "G4C", my: "ALL", their: "DX"),
        ]), party: paqp)
        XCTAssertEqual(s.validQSOs, 3, "all three are valid QSOs worth points")
        XCTAssertEqual(s.qsoPoints, 6)
        XCTAssertEqual(s.workedValues(.dx), ["DX"])
        // 3 DX QSOs → 1 DX mult, plus the two granted PA sections.
        XCTAssertEqual(s.multiplierCount, 3)
    }

    // MARK: QRP as a final-score multiplier

    /// "QRP Operation Multiplier: Multiply QSO Points times 2."
    func testQRPDoublesTheScore() throws {
        let mults = try XCTUnwrap(paqp.scoreMultipliers)
        XCTAssertEqual(mults.power?["QRP"], 2)
        XCTAssertEqual(mults.power?["HIGH"], 1)
        XCTAssertEqual(mults.power?["LOW"], 1)

        var log = outLog([qso(call: "W3A", mode: .cw, their: "ALL")])
        log.station.categoryPower = .high
        let high = ScoreEngine.score(log: log, party: paqp)
        XCTAssertEqual(high.total, 2 * 1, "2 points × 1 mult × 1")

        log.station.categoryPower = .qrp
        let qrp = ScoreEngine.score(log: log, party: paqp)
        XCTAssertEqual(qrp.total, 2 * 1 * 2, "and doubled for QRP")
    }

    // MARK: The 500-point mobile/rover bonus, and the absent bonus station

    /// "Add 500 Points to final score for each PA County you operated from where
    /// you made at least 10 valid QSOs."
    func testMobileActivationBonus() {
        XCTAssertEqual(paqp.bonuses, [.activatedCountyCount(minQSOs: 10, points: 500)])

        var log = inLog((1...10).map { qso(call: "W3\($0)", my: "ALL", their: "EMA") })
        log.station.categoryStation = .mobile
        XCTAssertEqual(ScoreEngine.score(log: log, party: paqp).bonusPoints, 500,
                       "ten QSOs from Allegheny earns it")

        var short = inLog((1...9).map { qso(call: "W3\($0)", my: "ALL", their: "EMA") })
        short.station.categoryStation = .mobile
        XCTAssertEqual(ScoreEngine.score(log: short, party: paqp).bonusPoints, 0,
                       "nine does not")
    }

    /// The 2026 bonus station is unannounced, so none ships — shipping the 2025
    /// call would credit a phantom 200 points per QSO.
    func testNoBonusStationShipsUntil2026IsAnnounced() throws {
        for bonus in paqp.bonuses {
            if case .workStation = bonus {
                XCTFail("no bonus station may ship while the 2026 call is unknown")
            }
        }
        let notes = try XCTUnwrap(paqp.notes)
        XCTAssertTrue(notes.contains("359,200 bonus points"),
                      "the sponsor's own arithmetic for 200 points per QSO is recorded")
        // Working last year's call must earn nothing extra.
        let s = ScoreEngine.score(log: outLog([qso(call: "N3XF", their: "SOM")]), party: paqp)
        XCTAssertEqual(s.bonusPoints, 0)
    }

    // MARK: Dupes, mobiles, county lines

    func testDupesAndModeSplit() {
        let a = qso(call: "W3M", band: .m40, mode: .cw, their: "LEH")
        var repeated = a
        repeated.id = UUID()
        repeated.timestampUTC = a.timestampUTC.addingTimeInterval(600)
        let otherMode = qso(call: "W3M", band: .m40, mode: .phone, their: "LEH")
        let otherBand = qso(call: "W3M", band: .m2, mode: .cw, their: "LEH")

        let s = ScoreEngine.score(log: outLog([a, repeated, otherMode, otherBand]), party: paqp)
        XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1, "LEH once, however many band/mode slots")
    }

    /// "Work Rovers and Mobiles again when they change counties."
    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3MOB", band: .m40, mode: .cw, their: "MOE"),
            qso(call: "W3MOB", band: .m40, mode: .cw, their: "MGY"),
        ]), party: paqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "A County Line station sends a single report with the multiple county
    /// abbreviations (CAR/LEH). The County Line and receiving station logs a QSO
    /// for each county." One exchange, one serial, several rows.
    func testCountyLineIsOneExchangeWithOneSerial() throws {
        XCTAssertEqual(
            try ExchangeParser.parse("CAR/LEH", party: paqp, role: .inState).get().locations,
            ["CAR", "LEH"],
            "the sponsor's own worked example"
        )
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W3CL", rstSent: "", rstRcvd: "",
                serialSent: 5, serialRcvd: 77,
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_791_600_000)
            ),
            myLocs: ["NTX"],
            theirLocs: ["CAR", "LEH"]
        )
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.serialSent)), [5], "one report, one serial as sent")
        var log = outLog(rows)
        XCTAssertEqual(log.nextSerial, 6)
        log.qsos = rows
        let s = ScoreEngine.score(log: log, party: paqp)
        XCTAssertEqual(s.validQSOs, 2, "both stations receive QSO points for each entry")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    // MARK: Exchange parsing

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("all", party: paqp, role: .inState).get().locations, ["ALL"])
        XCTAssertEqual(try ExchangeParser.parse("NHA", party: paqp, role: .inState).get().locations, ["NHA"])
        XCTAssertEqual(try ExchangeParser.parse("EMA", party: paqp, role: .inState).get().locations, ["EMA"])
        XCTAssertEqual(try ExchangeParser.parse("NTX", party: paqp, role: .inState).get().locations, ["NTX"])
        XCTAssertEqual(try ExchangeParser.parse("TER", party: paqp, role: .inState).get().locations, ["TER"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: paqp, role: .inState).get().locations, ["DX"])
        // The tokens every other party would accept, rejected here.
        for bad in ["TX", "PA", "ON", "NT", "DC"] {
            guard case .failure = ExchangeParser.parse(bad, party: paqp, role: .inState) else {
                return XCTFail("'\(bad)' is not a PAQP token — PAQP counts sections")
            }
        }
    }

    // MARK: Schedule — two windows, 21 hours

    func testScheduleIsTwoWindowsTotalling21Hours() throws {
        let windows = try XCTUnwrap(paqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-10-10T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-10-11T04:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-10-11T13:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-10-11T22:00:00Z"))

        let total = windows.reduce(0.0) { $0 + $1.end.timeIntervalSince($1.start) }
        XCTAssertEqual(total, 21 * 3600, "12 h Saturday + 9 h Sunday")

        // "Always the 2nd Full Weekend in October": Oct 10 2026 is a Saturday,
        // and the rules' EDT parentheticals hold — 1600Z is 1200 EDT.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 10)

        let ny = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(ny.secondsFromGMT(for: windows[0].start), -4 * 3600,
                       "still EDT in October — DST ends 1 November 2026")
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = ny
        XCTAssertEqual(eastern.component(.hour, from: windows[0].start), 12, "1200 EDT")
        XCTAssertEqual(eastern.component(.hour, from: windows[1].start), 9, "0900 EDT")
    }

    func testNotesRecordAllThreeOpenQuestions() throws {
        let notes = try XCTUnwrap(paqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION"), "630 m / 2200 m are unloggable")
        let questions = try XCTUnwrap(paqp.openQuestions)
        XCTAssertTrue(questions.contains("2025 revision"))
        XCTAssertTrue(questions.contains("2026 BONUS STATION IS NOT ANNOUNCED"))
        XCTAssertTrue(questions.contains("only PA stations"))
    }
}

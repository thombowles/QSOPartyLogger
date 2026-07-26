import XCTest
@testable import QSOPartyLogger

/// Idaho QSO Party ("The SPUD RUN") — built from the sponsor's own rules page and
/// its 44-county map/list, read verbatim 2026-07-26. See docs/research/idqp_rules.md.
///
/// **Its dates are reconstructed, not copied.** The sponsor's date block carries
/// four errors in eleven lines, including a literal `xxxxZ` placeholder — see
/// `testScheduleIsReconstructedFromFormulaDurationAndEDTAnchors`.
///
/// Idaho is also one of 7QP's seven states, so this county list is reusable when
/// the 7th Call Area party is built.
final class IdahoQSOPartyTests: XCTestCase {

    var idqp: PartyDefinition!

    override func setUpWithError() throws {
        idqp = try XCTUnwrap(PartyCatalog.party(id: "idqp"), "bundled IDQP should load")
    }

    var seq: TimeInterval = 0
    /// The exchange carries no signal report — "the RST is no longer part of the
    /// contest" — so the report fields are empty, as the app records them.
    func qso(
        call: String = "K7ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "ADA"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_773_504_000 + seq),  // 2026-03-14 16:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "idqp")
        log.myLocation = .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "ADA") -> ContestLog {
        var log = ContestLog(partyID: "idqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: County data — 44, and the B cluster is the worst in the repo

    func testCountyData() {
        XCTAssertEqual(idqp.counties.count, 44, "Idaho has 44 counties")
        XCTAssertEqual(Set(idqp.counties.map(\.abbr)).count, 44)
        XCTAssertEqual(Set(idqp.counties.map(\.name)).count, 44)
        XCTAssertEqual(idqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// **Ten counties begin with B, and `BON` is not a code at all** — Bonner and
    /// Bonneville would both claim it, so the sponsor gave neither the naive
    /// abbreviation.
    func testTheBClusterAndTheMissingBON() {
        XCTAssertEqual(idqp.county(for: "BNR")?.name, "Bonner")
        XCTAssertEqual(idqp.county(for: "BNV")?.name, "Bonneville")
        XCTAssertNil(idqp.county(for: "BON"), "neither Bonner nor Bonneville is BON")

        for (code, name) in [("BAN", "Bannock"), ("BEA", "Bear Lake"), ("BEN", "Benewah"),
                             ("BIN", "Bingham"), ("BLA", "Blaine"), ("BOI", "Boise"),
                             ("BOU", "Boundary"), ("BUT", "Butte")] {
            XCTAssertEqual(idqp.county(for: code)?.name, name)
        }
        XCTAssertEqual(idqp.counties.filter { $0.abbr.hasPrefix("B") }.count, 10)
    }

    func testTheOtherDenseClusters() {
        XCTAssertEqual(idqp.county(for: "CAM")?.name, "Camas")
        XCTAssertEqual(idqp.county(for: "CAN")?.name, "Canyon")
        XCTAssertEqual(idqp.county(for: "CAR")?.name, "Caribou")
        XCTAssertEqual(idqp.county(for: "CAS")?.name, "Cassia")
        XCTAssertEqual(idqp.county(for: "CLA")?.name, "Clark")
        XCTAssertEqual(idqp.county(for: "CLE")?.name, "Clearwater")
        XCTAssertEqual(idqp.county(for: "LAT")?.name, "Latah")
        XCTAssertEqual(idqp.county(for: "LEM")?.name, "Lemhi")
        XCTAssertEqual(idqp.county(for: "LEW")?.name, "Lewis")
        XCTAssertEqual(idqp.county(for: "LIN")?.name, "Lincoln")
        XCTAssertEqual(idqp.county(for: "NEZ")?.name, "Nez Perce", "two words")
        XCTAssertEqual(idqp.county(for: "TWI")?.name, "Twin Falls", "two words")
        XCTAssertEqual(idqp.county(for: "IDA")?.name, "Idaho",
                       "the county — distinct from the ID token, which is never sent")
        XCTAssertEqual(idqp.county(for: "koo")?.name, "Kootenai", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(idqp.cabrilloContest, "ID-QSO-PARTY", "WA7BNM; the rules print none")
        XCTAssertEqual(idqp.homeState, "ID")
        XCTAssertEqual(idqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertEqual(idqp.dxStyle, .prefix, "'DX stations send your DXCC prefix/country'")
        XCTAssertFalse(idqp.exchangeIncludesRST,
                       "'the RST is no longer part of the contest'")
        XCTAssertFalse(idqp.exchangeIncludesSerial)
        XCTAssertNil(idqp.scoreMultipliers)
        XCTAssertTrue(idqp.isPartiallyVerified)
    }

    /// "Bands, only 160 - 80 - 40 - 20 - 15 - 10 meters" — stated twice, HF only.
    func testSixHFBands() {
        XCTAssertEqual(idqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10])
        for excluded in [Band.m60, .m30, .m17, .m12, .m6, .m2, .cm125, .cm70] {
            XCTAssertFalse(idqp.validBands.contains(excluded), "\(excluded.rawValue) excluded")
        }
    }

    // MARK: Points

    func testPointsByMode() {
        XCTAssertEqual(idqp.points.points(for: .phone), 1)
        XCTAssertEqual(idqp.points.points(for: .cw), 2)
        XCTAssertEqual(idqp.points.points(for: .digital), 2)
    }

    /// **KNOWN LIMITATION 1, pinned.** "ALL QRP QSO's count 5 points. voice, CW,
    /// digital." `PointsTable` is keyed by mode and knows nothing of the
    /// entrant's power class at scoring time, so a QRP entrant is understated by
    /// between 2.5× and 5× per QSO. Everyone else is exact.
    func testKnownGapQRPQSOsDoNotPayFivePoints() throws {
        var log = outLog([
            qso(band: .m20, mode: .phone, their: "ADA"),
            qso(band: .m20, mode: .cw, their: "BNR"),
        ])
        log.station.categoryPower = .qrp
        let s = ScoreEngine.score(log: log, party: idqp)
        XCTAssertEqual(s.qsoPoints, 3, "current behaviour — the sponsor pays 5 + 5 = 10")

        var high = log
        high.station.categoryPower = .high
        XCTAssertEqual(ScoreEngine.score(log: high, party: idqp).qsoPoints, 3,
                       "power does not affect points here today, for anyone")

        let notes = try XCTUnwrap(idqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("TO CORRECT BY HAND"))
    }

    /// **KNOWN LIMITATION 2, pinned.** The dormant-county bonus pays 500, 1000 or
    /// 1500 *depending which county*, from a separately published list that
    /// changes yearly. `activatedCountyCount` carries one value, so none ships.
    func testKnownGapTheDormantCountyBonusIsNotPaid() throws {
        XCTAssertEqual(idqp.bonuses, [], "no single points value can express 500/1000/1500")
        XCTAssertTrue(try XCTUnwrap(idqp.notes).contains("KNOWN LIMITATION 2"))
    }

    // MARK: Multipliers — once per mode

    /// "A multiplier is counted once per mode, regardless of the number of bands
    /// on which it is worked." The Article 18 pair: a second *band* adds nothing,
    /// a second *mode* adds one.
    func testMultipliersCountOncePerMode() {
        XCTAssertEqual(idqp.multipliers.inState.countScope, .perMode)
        XCTAssertEqual(idqp.multipliers.outState.countScope, .perMode)

        let secondBand = ScoreEngine.score(log: outLog([
            qso(call: "K7A", band: .m20, mode: .cw, their: "ADA"),
            qso(call: "K7A", band: .m40, mode: .cw, their: "ADA"),
        ]), party: idqp)
        XCTAssertEqual(secondBand.validQSOs, 2)
        XCTAssertEqual(secondBand.multiplierCount, 1, "a second band adds nothing")

        let secondMode = ScoreEngine.score(log: outLog([
            qso(call: "K7A", band: .m20, mode: .cw, their: "ADA"),
            qso(call: "K7A", band: .m20, mode: .phone, their: "ADA"),
        ]), party: idqp)
        XCTAssertEqual(secondMode.multiplierCount, 2, "a second mode does")
    }

    func testOutOfStateCeilingIs44CountiesPerMode() {
        XCTAssertEqual(Set(idqp.multipliers.outState.classes), [.county])
        let rows = idqp.counties.enumerated().map { i, c in qso(call: "K7\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: idqp).multiplierCount, 44)
    }

    /// "count each US state (**including Idaho**), Canada province, and DXCC
    /// country" — stated outright, as SCQP does, while Idaho stations send a
    /// county so the token `ID` is never received.
    func testIdahoIsAMultiplierReachableThroughACounty() {
        XCTAssertTrue(idqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(idqp.validOutStateTokens.contains("ID"))
        let s = ScoreEngine.score(log: inLog([
            qso(call: "K7A", my: "ADA", their: "KOO"),
        ]), party: idqp)
        XCTAssertEqual(s.workedValues(.county), ["KOO"])
        XCTAssertEqual(s.workedValues(.state), ["ID"], "the county yields the state too")
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// DXCC countries count individually and are uncapped for Idaho stations.
    func testDXCCCountriesAreUncappedForIdahoStations() {
        XCTAssertNil(idqp.multipliers.inState.dxMultCap)
        let prefixes = ["DL", "JA", "G", "F", "I", "EA"]
        let rows = prefixes.enumerated().map { i, p in
            qso(call: "\(p)1AA\(i)", my: "ADA", their: p)
        }
        XCTAssertEqual(ScoreEngine.score(log: inLog(rows), party: idqp).multiplierCount, 6)
    }

    /// "W/VE stations (including KH6/KL7)… DX stations (including KH2/KP4)" —
    /// the same split OKQP states, one party earlier.
    func testAlaskaAndHawaiiAreStatesWhileGuamAndPuertoRicoAreDX() throws {
        for token in ["AK", "HI"] {
            XCTAssertEqual(
                try ExchangeParser.parse(token, party: idqp, role: .inState).get().locations,
                [token]
            )
        }
        let s = ScoreEngine.score(log: inLog([
            qso(call: "KL7A", my: "ADA", their: "AK"),
            qso(call: "KH2B", my: "ADA", their: "KH2"),
        ]), party: idqp)
        XCTAssertEqual(s.workedValues(.state), ["AK"])
        XCTAssertEqual(s.workedValues(.dx), ["KH2"])
    }

    // MARK: County lines — two

    /// "Idaho stations on a county line may be claimed as a QSO and a multiplier
    /// from each county (**2 QSO's and 2 multipliers**)."
    func testCountyLineIsTwoAndPaysTwoOfEach() throws {
        XCTAssertEqual(idqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            ExchangeParser.parse("ADA/BOI/CAN", party: idqp, role: .inState),
            .failure(.tooManyCounties(3))
        )
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "K7IQP", rstSent: "", rstRcvd: "",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date(timeIntervalSince1970: 1_773_504_000)
            ),
            myLocs: ["TX"],
            theirLocs: ["ADA", "BOI"]
        )
        XCTAssertEqual(rows.count, 2)
        let s = ScoreEngine.score(log: outLog(rows), party: idqp)
        XCTAssertEqual(s.validQSOs, 2, "'2 QSO's'")
        XCTAssertEqual(s.qsoPoints, 4, "CW 2 points each")
        XCTAssertEqual(s.multiplierCount, 2, "'and 2 multipliers'")
    }

    // MARK: Dupes, exchange, credit

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K7IQP", band: .m40, mode: .cw, their: "ADA"),
            qso(call: "K7IQP", band: .m40, mode: .cw, their: "KOO"),
        ]), party: idqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("ada", party: idqp, role: .inState).get().locations,
                       ["ADA"])
        XCTAssertEqual(try ExchangeParser.parse("BNV", party: idqp, role: .inState).get().locations,
                       ["BNV"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: idqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DL", party: idqp, role: .inState).get().locations,
                       ["DL"])
        guard case .failure = ExchangeParser.parse("ID", party: idqp, role: .inState) else {
            return XCTFail("ID must be rejected — Idaho stations send a county")
        }
    }

    /// Inferred rather than stated — the objective and the multiplier rules point
    /// this way but no sentence forbids other contacts outright, unlike MNQP's
    /// and NCQP's. Shipped on so a stray contact is visibly flagged; open
    /// question 2.
    func testOutOfStateCreditIsRestrictedByInference() throws {
        XCTAssertTrue(idqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "K7A", their: "ADA"),
            qso(call: "K5B", their: "TX"),
        ]), party: idqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
        XCTAssertTrue(try XCTUnwrap(idqp.openQuestions).contains("no sentence forbids"))
    }

    // MARK: Schedule — reconstructed, and the reconstruction is the test

    /// The sponsor's date block carries four errors: it calls 13 March a
    /// Saturday, prints a literal `xxxxZ` placeholder, dates the Saturday end
    /// `14/March/2025`, and labels 1400Z on the 14th as the *Sunday* start.
    ///
    /// These four instants come from the three things that do agree — the
    /// formula ("second full weekend of March"), the printed "12 Hours" per day,
    /// and the local anchors **under EDT**, daylight time having begun 8 March.
    func testScheduleIsReconstructedFromFormulaDurationAndEDTAnchors() throws {
        let windows = try XCTUnwrap(idqp.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()

        XCTAssertEqual(windows[0].start, f.date(from: "2026-03-14T16:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-03-15T04:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-03-15T14:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-03-16T02:00:00Z"))
        for w in windows {
            XCTAssertEqual(w.end.timeIntervalSince(w.start), 12 * 3600, "'ON THE AIR 12 Hours'")
        }

        // The second full weekend of March 2026 is the 14th–15th.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday the 14th")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 14)
        XCTAssertEqual(utc.component(.weekday, from: windows[1].start), 1, "Sunday the 15th")
        XCTAssertEqual(utc.component(.day, from: windows[1].start), 15)

        // The local anchors, against a real zone rather than a fixed offset —
        // which is what makes the EDT-vs-EST trap detectable.
        var eastern = Calendar(identifier: .gregorian)
        eastern.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(eastern.component(.hour, from: windows[0].start), 12, "12 noon Saturday")
        XCTAssertEqual(eastern.component(.hour, from: windows[1].start), 10, "10 am Sunday")
        XCTAssertEqual(eastern.component(.hour, from: windows[1].end), 22,
                       "the printed 9:59 pm, rounded up to the stated 12 hours")
    }

    func testNotesRecordTheReconstructionAndEveryOpenQuestion() throws {
        let notes = try XCTUnwrap(idqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("THE DATES ARE RECONSTRUCTED, NOT COPIED"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 1"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 2"))
        XCTAssertTrue(notes.contains("KEEP FT8 OUT OF THE LOG"))
        let questions = try XCTUnwrap(idqp.openQuestions)
        XCTAssertTrue(questions.contains("idahoqso@gmail.com"))
    }
}

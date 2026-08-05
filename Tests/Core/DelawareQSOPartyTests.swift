import XCTest
@testable import QSOPartyLogger

/// Delaware QSO Party — built from the First State Amateur Radio Club's own
/// rules, read verbatim 2026-07-26. See docs/research/deqp_rules.md.
///
/// **Three counties, the smallest list in the app** — and the one party where
/// the list is trivial and nothing else is. Its newest rules are titled 2024,
/// it states no contest times at all, and its QSO points depend on which side
/// of the state line you are on.
final class DelawareQSOPartyTests: XCTestCase {

    var deqp: PartyDefinition!

    override func setUpWithError() throws {
        deqp = try XCTUnwrap(PartyCatalog.party(id: "deqp"), "bundled DEQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W3ABC", band: Band = .m20, mode: ModeClass = .cw,
        my: String = "TX", their: String = "NDE"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_777_741_200 + seq),  // 2026-05-02 17:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO], power: StationProfile.CategoryPower = .high) -> ContestLog {
        var log = ContestLog(partyID: "deqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "NDE") -> ContestLog {
        var log = ContestLog(partyID: "deqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Three counties

    /// The smallest county list in the app, and the codes are the county's
    /// **initial plus DE** rather than a truncation of its name.
    func testThreeCountiesCodedByInitial() {
        XCTAssertEqual(deqp.counties.count, 3)
        XCTAssertEqual(deqp.county(for: "NDE")?.name, "New Castle")
        XCTAssertEqual(deqp.county(for: "KDE")?.name, "Kent")
        XCTAssertEqual(deqp.county(for: "SDE")?.name, "Sussex")
        XCTAssertNil(deqp.county(for: "NEW"), "not a truncation")
        XCTAssertEqual(deqp.county(for: "nde")?.name, "New Castle", "case-insensitive")

        // The Skeeter Hunt enumerates nothing at all (its multipliers are
        // the standard tables), so the superlative is among the parties
        // that enumerate.
        let smallest = PartyCatalog.loadBundled()
            .map(\.counties.count)
            .filter { $0 > 0 }
            .min()
        XCTAssertEqual(smallest, 3, "no enumerating party has fewer")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(deqp.cabrilloContest, "DE-QSO-PARTY")
        XCTAssertEqual(deqp.homeState, "DE")
        XCTAssertEqual(deqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertTrue(deqp.exchangeIncludesRST)
        XCTAssertTrue(deqp.bonuses.isEmpty)
        XCTAssertTrue(deqp.isPartiallyVerified)
        XCTAssertNil(deqp.hubSpots)
    }

    /// "…over 100 watts **×1**, 100 watts or less **×2**, 5 watts or less **×3**."
    func testThePowerMultiplierShips() throws {
        let m = try XCTUnwrap(deqp.scoreMultipliers)
        XCTAssertEqual(m.factor(power: .qrp, station: .fixed), 3)
        XCTAssertEqual(m.factor(power: .low, station: .fixed), 2)
        XCTAssertEqual(m.factor(power: .high, station: .fixed), 1)
    }

    // MARK: The asymmetric points

    /// **QSO points depend on which side of the state line you are on.**
    /// "Stations inside DE earn 1 point per phone QSO… Stations outside DE earn
    /// **10** points per phone QSO" — exactly ten times as much.
    ///
    /// An out-of-state entrant's valid QSOs are all with Delaware, so they all
    /// take the 10/20/20 table. This is the case that matters most and it is
    /// right.
    func testAnOutOfStateEntrantEarnsTenTimesAsMuch() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", mode: .phone, their: "NDE"),
            qso(call: "W3B", mode: .cw, their: "KDE"),
            qso(call: "W3C", mode: .digital, their: "SDE"),
        ]), party: deqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.qsoPoints, 10 + 20 + 20)
    }

    /// A Delaware station working outside Delaware takes the 1/2/2 table, which
    /// is also right.
    func testADelawareStationWorkingOutsideEarnsTheSmallValues() {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W5A", mode: .phone, my: "NDE", their: "TX"),
            qso(call: "W5B", mode: .cw, my: "NDE", their: "CA"),
        ]), party: deqp)
        XCTAssertEqual(s.qsoPoints, 1 + 2)
    }

    /// **KNOWN LIMITATION 1, pinned.** `pointsTable` keys on the *received*
    /// location, not the entrant's role — so a Delaware station working another
    /// Delaware station takes the out-of-state table and scores 10/20/20 where
    /// the sponsor pays 1/2/2.
    ///
    /// It is the smallest wrong case available: those contacts earn no
    /// multiplier either way, by the sponsor's own rule, and they are a minority
    /// of a Delaware log.
    func testKnownGapDelawareToDelawareTakesTheWrongPointsTable() throws {
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3DE", mode: .phone, my: "NDE", their: "KDE"),
        ]), party: deqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.qsoPoints, 10, "the sponsor pays 1 — see KNOWN LIMITATION 1")
        XCTAssertEqual(s.multiplierCount, 0,
                       "…and the sponsor grants no multiplier either way, which caps the harm")
        XCTAssertTrue(try XCTUnwrap(deqp.notes).contains("KNOWN LIMITATION 1"))
    }

    /// **KNOWN LIMITATION 2, pinned.** "…any band and mode **6 meters and up**…
    /// 1 point per voice contact, 2 points per digital contact to include CW."
    /// Points are keyed by mode, never by band, so a 6 m contact scores the HF
    /// value.
    func testKnownGapVHFContactsScoreTheHFValue() throws {
        XCTAssertTrue(deqp.validBands.contains(.m6))
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", band: .m6, mode: .phone, their: "NDE"),
        ]), party: deqp)
        XCTAssertEqual(s.qsoPoints, 10, "the sponsor pays 1 above 6 m")
        XCTAssertTrue(try XCTUnwrap(deqp.notes).contains("KNOWN LIMITATION 2"))
    }

    /// **KNOWN LIMITATIONS 3 and 4, pinned.** The 50-point bonus pays for how the
    /// log is *sent*, and FT8 uses a Field Day exchange grammar entirely.
    func testKnownGapsTheSubmissionBonusAndTheFieldDayExchange() throws {
        XCTAssertTrue(deqp.bonuses.isEmpty, "nothing is invented for a submission bonus")
        let notes = try XCTUnwrap(deqp.notes)
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 3"))
        XCTAssertTrue(notes.contains("KNOWN LIMITATION 4"))
    }

    // MARK: Multipliers

    /// "**Multipliers are by Band.**"
    func testMultipliersCountPerBand() {
        XCTAssertEqual(deqp.multipliers.inState.countScope, .perBand)
        XCTAssertEqual(deqp.multipliers.outState.countScope, .perBand)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", band: .m20, mode: .cw, their: "NDE"),
            qso(call: "W3A", band: .m20, mode: .phone, their: "NDE"),
            qso(call: "W3B", band: .m40, mode: .cw, their: "NDE"),
        ]), party: deqp)
        XCTAssertEqual(s.multiplierCount, 2, "New Castle on 20 m and on 40 m")
    }

    /// "Delaware stations use, states, Canadian provinces, and DXCC countries" —
    /// **not counties**, which is why "Delaware stations may contact other
    /// Delaware stations but only count for QSO point credit."
    func testDelawareEntrantsCountNoCounties() {
        XCTAssertEqual(Set(deqp.multipliers.inState.classes), [.state, .province, .dx])
        XCTAssertFalse(deqp.multipliers.inState.homeStateCountsViaCounty)
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "NDE", their: "KDE"),
            qso(call: "W5B", my: "NDE", their: "TX"),
        ]), party: deqp)
        XCTAssertEqual(s.workedValues(.county), [])
        XCTAssertEqual(s.workedValues(.state), ["TX"])
    }

    func testOutOfStateCeilingIsThreePerBand() {
        XCTAssertEqual(Set(deqp.multipliers.outState.classes), [.county])
        var rows: [QSO] = []
        for band in [Band.m20, .m40] {
            for (i, c) in deqp.counties.enumerated() {
                rows.append(qso(call: "W3\(i)", band: band, their: c.abbr))
            }
        }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: deqp).multiplierCount, 6)
    }

    // MARK: Credit, county lines, schedule

    /// "**Non-Delaware stations work Delaware only.**"
    func testOutOfStateEntrantsWorkDelawareOnly() {
        XCTAssertTrue(deqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W3A", their: "NDE"),
            qso(call: "K5B", their: "TX"),
        ]), party: deqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    /// "**County line QSOs should be logged as two separate QSOs.**"
    func testCountyLinesAreLoggedSeparately() {
        XCTAssertEqual(deqp.maxSimultaneousCounties, 1)
        XCTAssertEqual(
            ExchangeParser.parse("NDE/KDE", party: deqp, role: .inState),
            .failure(.tooManyCounties(2)))
    }

    /// **OPEN QUESTION 1, pinned.** The rules state **no contest times at all** —
    /// only "Date: First full weekend in May". The date is the sponsor's; the
    /// hours come from the SQP Challenge calendar, because no sponsor document
    /// carries any.
    func testTheScheduleHoursAreNotTheSponsorsAndThatIsRecorded() throws {
        let w = try XCTUnwrap(deqp.schedule)
        XCTAssertEqual(w.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(w[0].start, f.date(from: "2026-05-02T17:00:00Z"))
        XCTAssertEqual(w[0].end, f.date(from: "2026-05-04T00:00:00Z"))

        // The DATE is derivable from the sponsor: the first full weekend in May
        // 2026 is the 2nd and 3rd.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: w[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: w[0].start), 2)

        XCTAssertTrue(try XCTUnwrap(deqp.notes).contains("OPEN QUESTION 1"))
        XCTAssertTrue(try XCTUnwrap(deqp.notes).contains("NO CONTEST TIMES AT ALL"))
    }

    func testNotesRecordTheStaleRulesChain() throws {
        let notes = try XCTUnwrap(deqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("NEWEST RULES ARE TITLED 2024"))
        XCTAssertTrue(notes.contains("THE SITE'S OWN LINKS LAND SHORT"))
    }
}

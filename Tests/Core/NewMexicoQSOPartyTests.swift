import XCTest
@testable import QSOPartyLogger

/// New Mexico QSO Party — built from the sponsor's own "2026 New Mexico QSO Party
/// Form Packet" (last modified 09 April 2026), read verbatim 2026-07-26. See
/// docs/research/nmqp_rules.md.
///
/// **The first party this run whose power multiplier actually fits** — QRP ×5,
/// Low ×2, High ×1, all whole numbers. VTQP and WIQP have the same shape with a
/// ×1.5 low-power factor and cannot ship one; NMQP can.
final class NewMexicoQSOPartyTests: XCTestCase {

    var nmqp: PartyDefinition!

    override func setUpWithError() throws {
        nmqp = try XCTUnwrap(PartyCatalog.party(id: "nmqp"), "bundled NMQP should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "W5ABC",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "BER"
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_775_916_000 + seq),  // 2026-04-11 14:00Z
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: mode == .phone ? "59" : "599",
            rstRcvd: mode == .phone ? "59" : "599",
            myLoc: my, theirLoc: their
        )
    }

    func outLog(_ qsos: [QSO], power: StationProfile.CategoryPower = .high) -> ContestLog {
        var log = ContestLog(partyID: "nmqp")
        log.myLocation = .outOfState(location: "TX")
        log.station.categoryPower = power
        log.qsos = qsos
        return log
    }

    func inLog(_ qsos: [QSO], from county: String = "BER") -> ContestLog {
        var log = ContestLog(partyID: "nmqp")
        log.myLocation = .inState(counties: [county])
        log.qsos = qsos
        return log
    }

    // MARK: Counties — 33, and the San/Santa trap

    func testCountyData() {
        XCTAssertEqual(nmqp.counties.count, 33, "New Mexico has 33 counties")
        XCTAssertEqual(Set(nmqp.counties.map(\.abbr)).count, 33)
        XCTAssertEqual(Set(nmqp.counties.map(\.name)).count, 33)
        XCTAssertEqual(nmqp.countyAbbrLengths, [3], "uniformly 3 letters")
    }

    /// **`SAN` is Sandoval** — not San Juan, not San Miguel, not Santa Fe. Four
    /// entities in the cluster and the obvious code belongs to none of them.
    func testSANIsSandovalAndNotAnyOfTheSanOrSantaCounties() {
        XCTAssertEqual(nmqp.county(for: "SAN")?.name, "Sandoval")
        XCTAssertEqual(nmqp.county(for: "SJU")?.name, "San Juan")
        XCTAssertEqual(nmqp.county(for: "SMI")?.name, "San Miguel")
        XCTAssertEqual(nmqp.county(for: "SFE")?.name, "Santa Fe")
    }

    func testOtherCodesWorthChecking() {
        XCTAssertEqual(nmqp.county(for: "COL")?.name, "Colfax")
        XCTAssertEqual(nmqp.county(for: "CIB")?.name, "Cibola")
        XCTAssertEqual(nmqp.county(for: "LOS")?.name, "Los Alamos")
        XCTAssertEqual(nmqp.county(for: "RIO")?.name, "Rio Arriba")
        XCTAssertEqual(nmqp.county(for: "DEB")?.name, "De Baca")
        XCTAssertEqual(nmqp.county(for: "DON")?.name, "Dona Ana",
                       "the sponsor drops the tilde of the official Doña Ana")
        XCTAssertEqual(nmqp.county(for: "mck")?.name, "McKinley", "case-insensitive")
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(nmqp.cabrilloContest, "NM-QSO-PARTY",
                       "printed by the sponsor in its own sample log")
        XCTAssertEqual(nmqp.homeState, "NM")
        XCTAssertEqual(nmqp.allowedModeClasses, ModeClass.allCases)
        XCTAssertTrue(nmqp.exchangeIncludesRST)
        XCTAssertFalse(nmqp.exchangeIncludesSerial)
        XCTAssertTrue(nmqp.isPartiallyVerified)
    }

    func testEightBandsWith60mNamedSeparatelyFromWARC() {
        XCTAssertEqual(nmqp.validBands, [.m160, .m80, .m40, .m20, .m15, .m10, .m6, .m2])
        for excluded in [Band.m60, .m30, .m17, .m12, .cm125, .cm70] {
            XCTAssertFalse(nmqp.validBands.contains(excluded), "\(excluded.rawValue) excluded")
        }
    }

    func testPointsByMode() {
        XCTAssertEqual(nmqp.points.points(for: .phone), 1)
        XCTAssertEqual(nmqp.points.points(for: .cw), 2)
        XCTAssertEqual(nmqp.points.points(for: .digital), 2)
    }

    // MARK: The power multiplier — the one that fits

    /// "QRP (5 watts or less): ×5 · Low Power (> 5 – 150 watts): ×2 · High Power
    /// (> 150 watts): ×1." **Whole numbers**, so it ships — and ×5 is the largest
    /// score multiplier in the repo.
    func testThePowerMultiplierShipsAndIsApplied() throws {
        let mults = try XCTUnwrap(nmqp.scoreMultipliers)
        XCTAssertEqual(mults.factor(power: .qrp, station: .fixed), 5)
        XCTAssertEqual(mults.factor(power: .low, station: .fixed), 2)
        XCTAssertEqual(mults.factor(power: .high, station: .fixed), 1)

        let rows = [qso(call: "W5A", their: "BER"), qso(call: "W5B", their: "SAN")]
        let qrp = ScoreEngine.score(log: outLog(rows, power: .qrp), party: nmqp)
        XCTAssertEqual(qrp.categoryFactor, 5)
        XCTAssertEqual(qrp.total, qrp.qsoPoints * qrp.multiplierCount * 5)

        let high = ScoreEngine.score(log: outLog(rows, power: .high), party: nmqp)
        XCTAssertEqual(high.total, qrp.total / 5, "the QRP entrant scores five times as much")
    }

    /// The contrast with the two parties whose shape is identical except for a
    /// **×1.5** low-power factor. That fraction is why `ScoreFactor` exists;
    /// New Mexico's ×2 never needed it, and every NMQP factor is still a whole
    /// number.
    func testTheContrastWithVermontAndWisconsin() throws {
        let mults = try XCTUnwrap(nmqp.scoreMultipliers)
        for power in StationProfile.CategoryPower.allCases {
            XCTAssertTrue(mults.factor(power: power, station: .fixed).isWholeNumber,
                          "\(power.rawValue) fits in a whole number, which is why NMQP shipped first")
        }
        let vtqp = try XCTUnwrap(PartyCatalog.party(id: "vtqp"))
        XCTAssertEqual(vtqp.scoreMultipliers?.factor(power: .low, station: .fixed),
                       ScoreFactor(numerator: 3, denominator: 2),
                       "Vermont's ×1.5 is the fraction New Mexico's rules did not have")
    }

    // MARK: Multipliers — once overall

    func testMultipliersCountOnceOverall() {
        XCTAssertEqual(nmqp.multipliers.inState.countScope, .once)
        XCTAssertEqual(nmqp.multipliers.outState.countScope, .once)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", band: .m20, mode: .cw, their: "BER"),
            qso(call: "W5A", band: .m40, mode: .cw, their: "BER"),
            qso(call: "W5A", band: .m20, mode: .phone, their: "BER"),
        ]), party: nmqp)
        XCTAssertEqual(s.validQSOs, 3)
        XCTAssertEqual(s.multiplierCount, 1)
    }

    func testOutOfStateCeilingIs33Counties() {
        XCTAssertEqual(Set(nmqp.multipliers.outState.classes), [.county])
        let rows = nmqp.counties.enumerated().map { i, c in qso(call: "W5\(i)", their: c.abbr) }
        XCTAssertEqual(ScoreEngine.score(log: outLog(rows), party: nmqp).multiplierCount, 33)
    }

    /// "states worked (**up to 50**)" — fifty, not forty-nine, so New Mexico is
    /// included; and NM stations send a county, so `NM` is never received. The
    /// arithmetic is the whole argument, as it was for MNQP and NCQP in reverse.
    func testNewMexicoCountsAsAStateThroughACounty() {
        XCTAssertTrue(nmqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(nmqp.validOutStateTokens.contains("NM"))
        let s = ScoreEngine.score(log: inLog([qso(my: "BER", their: "SAN")]), party: nmqp)
        XCTAssertEqual(s.workedValues(.county), ["SAN"])
        XCTAssertEqual(s.workedValues(.state), ["NM"])
        XCTAssertEqual(s.multiplierCount, 2)
    }

    /// "District of Columbia (DC) counts as Maryland."
    func testDCCountsAsMaryland() throws {
        XCTAssertEqual(nmqp.stateAliases, ["DC": "MD"])
        let s = ScoreEngine.score(log: inLog([
            qso(call: "W3A", my: "BER", their: "DC"),
            qso(call: "W3B", my: "BER", their: "MD"),
        ]), party: nmqp)
        XCTAssertEqual(s.workedValues(.state).filter { $0 != "NM" }, ["MD"],
                       "one multiplier, not two")
    }

    /// The rules count "DX entities worked" individually while the log format
    /// carries the literal `DX` — the packet says so and its sample log shows
    /// `LY2ZZ 599 DX`. Ten entities used to become one multiplier. The
    /// sponsor's own scorer faces the same problem and must derive the entity
    /// from the callsign, which is now exactly what this does.
    func testEachDXEntityCountsIndividually() throws {
        XCTAssertEqual(nmqp.dxStyle, .token)
        XCTAssertTrue(nmqp.multipliers.inState.dxCountsEntities)

        // Ten different entities, one contact each.
        let calls = ["DL1AA", "JA1BB", "G4CC", "F5DD", "I2EE",
                     "EA3FF", "SM4GG", "OZ5HH", "HB9II", "LZ6JJ"]
        let s = ScoreEngine.score(log: inLog(calls.map {
            qso(call: $0, my: "BER", their: "DX")
        }), party: nmqp)
        XCTAssertEqual(s.validQSOs, 10, "all ten count for points")
        XCTAssertEqual(s.workedValues(.dx).count, 10, "…and yield ten multipliers, not one")

        // The packet's own sample log row.
        XCTAssertEqual(DXCCTable.shared.entity(forCallsign: "LY2ZZ")?.name, "Lithuania")
        XCTAssertTrue(try XCTUnwrap(nmqp.notes).contains("DX ENTITIES COUNT ONE BY ONE"))
    }

    /// Ten contacts with one entity are still one multiplier.
    func testTenContactsInOneEntityAreOneMultiplier() {
        let rows = (0..<10).map { qso(call: "DL\($0)AA", my: "BER", their: "DX") }
        let s = ScoreEngine.score(log: inLog(rows), party: nmqp)
        XCTAssertEqual(s.validQSOs, 10)
        XCTAssertEqual(s.workedValues(.dx), ["DL"])
    }

    // MARK: Bonuses — both fit

    /// "Add an additional **250** points… for a valid contact with W1AW/5. Bonus
    /// points are valid for **one (1)** W1AW/5 QSO only, regardless of band,
    /// mode, or W1AW/5's county." Note 250, **not** the 500 the packet's own
    /// change log records being cut on 09 April.
    func testW1AW5PaysTwoHundredFiftyOnce() {
        XCTAssertEqual(nmqp.bonuses.first,
                       .workStation(call: "W1AW/5", points: 250, scope: .once))
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W1AW/5", band: .m20, mode: .cw, their: "BER"),
            qso(call: "W1AW/5", band: .m40, mode: .cw, their: "SAN"),
            qso(call: "W1AW/5", band: .m20, mode: .phone, their: "SFE"),
        ]), party: nmqp)
        XCTAssertEqual(s.validQSOs, 3, "each county activation is a new station for QSO credit")
        XCTAssertEqual(s.bonusPoints, 250, "…but the bonus is claimed only once")
    }

    /// "Add an additional **5,000 points**… for every county from which at least
    /// **15 valid QSOs** were made" — by far the largest activation bonus here.
    func testFiveThousandPerCountyWithFifteenQSOs() throws {
        XCTAssertEqual(nmqp.bonuses.last, .activatedCountyCount(minQSOs: 15, points: 5000))
        func rows(_ county: String, _ n: Int) -> [QSO] {
            (0..<n).map { i in qso(call: "W\(county)\(i)", my: county, their: "TX") }
        }
        var log = inLog(rows("BER", 15) + rows("SAN", 14))
        log.station.categoryStation = .mobile
        log.myLocation = .inState(counties: ["BER"])
        XCTAssertEqual(ScoreEngine.score(log: log, party: nmqp).bonusPoints, 5000,
                       "fifteen qualifies, fourteen does not")

        // …and it dwarfs every other activation bonus in the repo.
        for id in ["tnqp", "okqp", "wiqp", "vaqp", "laqp"] {
            let other = try XCTUnwrap(PartyCatalog.party(id: id))
            for bonus in other.bonuses {
                if case .activatedCountyCount(_, let points) = bonus {
                    XCTAssertLessThan(points, 5000, "\(id)'s activation bonus is smaller")
                }
            }
        }
    }

    // MARK: County lines — two, with three ruled out

    /// "…**only two counties at a time may be counted** for the same contact",
    /// with the three-county intersection ruled out by name.
    func testCountyLineIsTwoAndThreeIsRefused() throws {
        XCTAssertEqual(nmqp.maxSimultaneousCounties, 2)
        XCTAssertEqual(
            try ExchangeParser.parse("BER/SAN", party: nmqp, role: .inState).get().locations,
            ["BER", "SAN"]
        )
        XCTAssertEqual(
            ExchangeParser.parse("BER/SAN/SFE", party: nmqp, role: .inState),
            .failure(.tooManyCounties(3)),
            "the sponsor rules the three-county case out explicitly"
        )
    }

    // MARK: Dupes, exchange, credit

    func testMobileChangingCountyIsANewQSO() {
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5MOB", band: .m40, mode: .cw, their: "BER"),
            qso(call: "W5MOB", band: .m40, mode: .cw, their: "SAN"),
        ]), party: nmqp)
        XCTAssertEqual(s.dupeCount, 0)
        XCTAssertEqual(s.multiplierCount, 2)
    }

    func testExchangeParsing() throws {
        XCTAssertEqual(try ExchangeParser.parse("ber", party: nmqp, role: .inState).get().locations,
                       ["BER"])
        XCTAssertEqual(try ExchangeParser.parse("SJU", party: nmqp, role: .inState).get().locations,
                       ["SJU"])
        XCTAssertEqual(try ExchangeParser.parse("TX", party: nmqp, role: .inState).get().locations,
                       ["TX"])
        XCTAssertEqual(try ExchangeParser.parse("DX", party: nmqp, role: .inState).get().locations,
                       ["DX"])
        guard case .failure = ExchangeParser.parse("NM", party: nmqp, role: .inState) else {
            return XCTFail("NM must be rejected — New Mexico stations send a county")
        }
    }

    /// "Non-NM stations: Work NM stations for NM counties only."
    func testOutOfStateEntrantsGetNoCreditForNonNewMexicoContacts() {
        XCTAssertTrue(nmqp.outStateWorksHomeStationsOnly)
        let s = ScoreEngine.score(log: outLog([
            qso(call: "W5A", their: "BER"),
            qso(call: "K5B", their: "TX"),
        ]), party: nmqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.outOfScopeCount, 1)
    }

    // MARK: Schedule

    /// "Second Saturday of April, 8:00 MDT (1400 UTC) to 20:00 MDT (0200 UTC).
    /// Duration: 12 hours" — formula, both UTC instants, both local instants and
    /// the duration, all in one sentence.
    func testScheduleIsTheSecondSaturdayOfApril() throws {
        let windows = try XCTUnwrap(nmqp.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-04-11T14:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-04-12T02:00:00Z"))
        XCTAssertEqual(windows[0].end.timeIntervalSince(windows[0].start), 12 * 3600)

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        XCTAssertEqual(utc.component(.weekday, from: windows[0].start), 7, "Saturday")
        XCTAssertEqual(utc.component(.day, from: windows[0].start), 11)
        XCTAssertTrue((8...14).contains(utc.component(.day, from: windows[0].start)),
                      "the second Saturday of April")

        // The local anchors, against a real zone: 8 am to 8 pm MDT.
        var mountain = Calendar(identifier: .gregorian)
        mountain.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Denver"))
        XCTAssertEqual(mountain.component(.hour, from: windows[0].start), 8)
        XCTAssertEqual(mountain.component(.hour, from: windows[0].end), 20)
    }

    func testNotesRecordThe2026OnlyBonusAndTheDXGap() throws {
        let notes = try XCTUnwrap(nmqp.notes)
        XCTAssertTrue(notes.contains("verified: partial"))
        XCTAssertTrue(notes.contains("REDUCED FROM 500 TO 250 POINTS"),
                      "the change log's cut must stay recorded")
        XCTAssertTrue(notes.contains("2026-ONLY RULE"),
                      "so a 2027 session deletes the W1AW/5 bonus")
        XCTAssertFalse(notes.contains("KNOWN LIMITATION"),
                       "the DX collapse was the only one, and it is closed")
        XCTAssertEqual(nmqp.caveats.count, 1, "only the 2026-only bonus remains")
    }
}

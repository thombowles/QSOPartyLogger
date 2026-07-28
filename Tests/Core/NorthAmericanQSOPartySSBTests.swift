import XCTest
@testable import QSOPartyLogger

/// North American QSO Party, SSB — NCJ's phone event of the same rules
/// document as the CW party, read verbatim 2026-07-27. See
/// docs/research/naqpssb_rules.md.
///
/// One document governs all three NAQP modes, so this file pins what differs
/// (mode, dates, Cabrillo name) and asserts the rest is *identical* to the
/// CW party rather than merely similar — the same discipline
/// CatalogConsistencyTests applies to overlapping county lists.
@MainActor
final class NorthAmericanQSOPartySSBTests: XCTestCase {

    var naqp: PartyDefinition!

    override func setUpWithError() throws {
        naqp = try XCTUnwrap(PartyCatalog.party(id: "naqpssb"), "bundled NAQP SSB should load")
    }

    var seq: TimeInterval = 0
    func qso(
        call: String = "N2CU", band: Band = .m20, mode: ModeClass = .phone,
        my: String = "TX", their: String = "NY",
        nameSent: String? = "TOM", nameRcvd: String? = "BILL"
    ) -> QSO {
        seq += 60
        // 2026-08-15 18:00Z + n minutes — inside the August window.
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_786_816_800 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY",
            rstSent: "", rstRcvd: "",
            nameSent: nameSent, nameRcvd: nameRcvd,
            myLoc: my, theirLoc: their
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        var log = ContestLog(partyID: "naqpssb")
        log.myLocation = .outOfState(location: "TX")
        log.station.callsign = "KE5CW"
        log.exchangeName = "TOM"
        log.qsos = qsos
        return log
    }

    // MARK: What differs from the CW party

    func testTheSSBShape() {
        XCTAssertEqual(naqp.cabrilloContest, "NAQP-SSB", "WA7BNM entry 229")
        XCTAssertEqual(naqp.allowedModeClasses, [.phone], "rule 7: SSB only in phone parties")
        XCTAssertEqual(naqp.name, "North American QSO Party, SSB")
    }

    /// Rule 4's SSB rows: the third full weekends of January and August.
    func testScheduleIsBothTwelveHourRunnings() throws {
        let windows = try XCTUnwrap(naqp.schedule)
        let iso = ISO8601DateFormatter()
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].start, iso.date(from: "2026-01-17T18:00:00Z"))
        XCTAssertEqual(windows[0].end, iso.date(from: "2026-01-18T06:00:00Z"))
        XCTAssertEqual(windows[1].start, iso.date(from: "2026-08-15T18:00:00Z"))
        XCTAssertEqual(windows[1].end, iso.date(from: "2026-08-16T06:00:00Z"))
    }

    /// Rule 7 the other way around: a CW or digital row in the phone party is
    /// invalid — no points, no multipliers — not merely worth zero.
    func testOnlyPhoneCounts() {
        let s = ScoreEngine.score(log: log([
            qso(call: "K5OT", mode: .phone, their: "TX"),
            qso(call: "W1AW", mode: .cw, their: "CT"),
            qso(call: "W9PA", mode: .digital, their: "IL"),
        ]), party: naqp)
        XCTAssertEqual(s.validQSOs, 1)
        XCTAssertEqual(s.invalidModeCount, 2)
        XCTAssertEqual(s.qsoPoints, 1)
        XCTAssertEqual(s.workedValues(.state), ["TX"])
    }

    // MARK: Everything else is the CW party, asserted as identity

    /// The two NAQP definitions must never drift apart: same country list
    /// byte for byte, same multiplier rules, same exchange shape, same bands.
    func testEverythingSharedIsIdenticalToTheCWParty() throws {
        let cw = try XCTUnwrap(PartyCatalog.party(id: "naqpcw"))
        XCTAssertEqual(naqp.counties, cw.counties, "one checklist, one generator")
        XCTAssertEqual(naqp.multipliers, cw.multipliers)
        XCTAssertEqual(naqp.validBands, cw.validBands)
        XCTAssertEqual(naqp.homeState, cw.homeState)
        XCTAssertEqual(naqp.homeStates, cw.homeStates)
        XCTAssertEqual(naqp.inStateLabel, cw.inStateLabel)
        XCTAssertEqual(naqp.excludedStateTokens, cw.excludedStateTokens)
        XCTAssertEqual(naqp.provinces, cw.provinces)
        XCTAssertEqual(naqp.stateAliases, cw.stateAliases)
        XCTAssertEqual(naqp.dxStyle, cw.dxStyle)
        XCTAssertEqual(naqp.maxSimultaneousCounties, cw.maxSimultaneousCounties)
        XCTAssertEqual(naqp.points, cw.points)
        XCTAssertEqual(naqp.dupeScope, cw.dupeScope)
        XCTAssertEqual(naqp.exchangeIncludesRST, cw.exchangeIncludesRST)
        XCTAssertEqual(naqp.exchangeIncludesSerial, cw.exchangeIncludesSerial)
        XCTAssertEqual(naqp.exchangeIncludesName, cw.exchangeIncludesName)
        XCTAssertEqual(naqp.bonuses, cw.bonuses)
        XCTAssertEqual(naqp.scoreMultipliers, cw.scoreMultipliers)
        XCTAssertEqual(naqp.outStateWorksHomeStationsOnly, cw.outStateWorksHomeStationsOnly)
        XCTAssertEqual(naqp.caveats.map(\.kind), cw.caveats.map(\.kind))
        XCTAssertNil(naqp.hubSpots)
        XCTAssertFalse(naqp.isPartiallyVerified)
    }

    /// The floor's own spot checks, so this file stands alone if the CW
    /// party ever changes: the join's hard cases and the two shadows.
    func testCountryListSpotChecks() {
        XCTAssertEqual(naqp.counties.count, 46)
        XCTAssertEqual(naqp.county(for: "XE")?.name, "Mexico")
        XCTAssertEqual(naqp.county(for: "4U1")?.name, "United Nations HQ")
        XCTAssertEqual(naqp.county(for: "CM")?.name, "Cuba")
        XCTAssertEqual(naqp.county(for: "KP4")?.name, "Puerto Rico")
        XCTAssertEqual(naqp.county(for: "CY0")?.name, "Sable I.")
        XCTAssertEqual(naqp.county(for: "VP2V")?.name, "British Virgin Is.")
        XCTAssertNil(naqp.county(for: "HI"), "the Dominican shadow — see the caveat")
        XCTAssertNil(naqp.county(for: "CO"), "Cuba is CM; CO stays Colorado")
    }

    func testMultipliersCountAgainOnEachBand() {
        let s = ScoreEngine.score(log: log([
            qso(call: "XE2X", band: .m20, their: "XE"),
            qso(call: "XE2X", band: .m40, their: "XE"),
            qso(call: "K5OT", band: .m20, their: "TX"),
            qso(call: "W5KU", band: .m20, their: "TX"),
        ]), party: naqp)
        XCTAssertEqual(s.validQSOs, 4)
        XCTAssertEqual(s.multiplierKeys.count, 3, "XE twice (two bands), TX once")
        XCTAssertEqual(s.total, 12)
    }

    func testDXPaysAPointAndNeverAMultiplier() {
        let s = ScoreEngine.score(log: log([qso(call: "G4XYZ", their: "DX")]), party: naqp)
        XCTAssertEqual(s.qsoPoints, 1)
        XCTAssertEqual(s.multiplierCount, 0)
    }

    func testDupesArePerBand() {
        let s = ScoreEngine.score(log: log([
            qso(call: "N2CU", band: .m20, their: "NY"),
            qso(call: "N2CU", band: .m20, their: "NY"),
            qso(call: "N2CU", band: .m15, their: "NY"),
        ]), party: naqp)
        XCTAssertEqual(s.validQSOs, 2)
        XCTAssertEqual(s.dupeCount, 1)
    }

    func testExchangeParsing() {
        for token in ["XE", "TX", "DC", "ON", "DX"] {
            guard case .success = ExchangeParser.parse(token, party: naqp, role: .outOfState) else {
                return XCTFail("\(token) should be valid")
            }
        }
        for bad in ["TXX", "NA"] {
            if case .success = ExchangeParser.parse(bad, party: naqp, role: .outOfState) {
                XCTFail("\(bad) should not validate")
            }
        }
        guard case .failure(.tooManyCounties(2)) = ExchangeParser.parse(
            "XE/6Y", party: naqp, role: .outOfState
        ) else { return XCTFail("one location per exchange") }
    }

    /// The name gate, end to end, in the phone party.
    func testLoggingRequiresTheReceivedName() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "naqpssb",
            exchangeName: "Tom",
            undoManager: nil
        )
        let flow = EntryFlow(document: doc)
        let context = EntryFlow.Context(
            band: .m20, modeClass: .phone, rawMode: "SSB",
            freqKHz: nil, radioConnected: false, cursor: .call,
            keying: KeyingSettings()
        )

        flow.entry.call = "N2CU"
        flow.entry.exchangeTyped = "NY"
        XCTAssertEqual(flow.logContact(context, undoManager: nil), .nothing)

        flow.entry.nameRcvd = "BILL"
        guard case .logged(let rows, _) = flow.logContact(context, undoManager: nil) else {
            return XCTFail("a complete exchange logs")
        }
        XCTAssertEqual(rows[0].nameSent, "TOM")
        XCTAssertEqual(rows[0].nameRcvd, "BILL")
        XCTAssertEqual(rows[0].modeClass, .phone)
    }

    // MARK: Not a Challenge contest

    /// Same requirement as the CW party (KE5CW, 2026-07-27): absent from the
    /// approved list, shown under "not approved", contributing nothing.
    func testNAQPSSBIsNotAChallengeContest() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        XCTAssertNil(calendar.contest(partyID: "naqpssb"))
        XCTAssertNil(calendar.contest(named: "North American QSO Party, SSB"))

        var naqpLog = log([qso(call: "N2CU", their: "NY")])
        naqpLog.station.callsign = "KE5CW"
        let records = [naqpLog].compactMap {
            ContestRecord.make(
                from: $0,
                snapshot: ScoreSnapshot.countsOnly(log: $0),
                updatedAt: Date(timeIntervalSince1970: 1_786_816_800),
                sourceFileName: nil
            )
        }
        let standing = ChallengeStanding.compute(
            records: records, calendar: calendar, year: 2026,
            partyNames: ["naqpssb": "North American QSO Party, SSB"]
        )
        XCTAssertEqual(standing.notApproved.map(\.partyID), ["naqpssb"])
        XCTAssertEqual(standing.points, 0)
    }
}

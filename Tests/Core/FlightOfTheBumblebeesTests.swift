import XCTest
@testable import QSOPartyLogger

/// ARS Flight of the Bumblebees — the catalogue's second QRP sprint, and
/// the event the Skeeter Hunt was modelled on. Four hours twice a year, CW
/// only, no counties, every contact three points, and the only multiplier
/// is Bumblebees worked, counted again on each band and never below one.
/// Rules research: docs/research/fobb_rules.md; the printed formula was
/// verified against all 90 rows of the sponsor-designated 3830 calculator's
/// July 2026 table, which gen_fobb.py re-verifies.
@MainActor
final class FlightOfTheBumblebeesTests: XCTestCase {

    var fobb: PartyDefinition!

    override func setUpWithError() throws {
        fobb = try XCTUnwrap(PartyCatalog.party(id: "fobb"), "fobb.json must load")
    }

    var seq: TimeInterval = 0
    /// Inside the Fall 2026 window (17:00–21:00Z, 2026-09-20) by construction.
    func qso(
        call: String,
        band: Band = .m20,
        mode: ModeClass = .cw,
        their: String = "NC",
        memberRcvd: String?
    ) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_923_600 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : (mode == .digital ? "FT8" : "CW"),
            rstSent: "599", rstRcvd: "599",
            memberSent: "5W", memberRcvd: memberRcvd,
            myLoc: "TX", theirLoc: their
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "fobb",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "5W"
        )
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(fobb.name, "ARS Flight of the Bumblebees")
        XCTAssertEqual(fobb.cabrilloContest, "ARS-FOBB")
        XCTAssertEqual(fobb.homeState, "NA", "a pseudo-state, labels only")
        XCTAssertFalse(fobb.hasHomeRegion)
        XCTAssertTrue(fobb.counties.isEmpty, "the S/P/C earns nothing; nothing to enumerate")
        XCTAssertEqual(fobb.allowedModeClasses, [.cw], "'QRP CW Contacts'")
        XCTAssertEqual(fobb.validBands, [.m80, .m40, .m20, .m15, .m10])
        XCTAssertEqual(fobb.maxSimultaneousCounties, 1)
        XCTAssertEqual(fobb.dxStyle, .prefix)
        XCTAssertTrue(fobb.acceptsDXToken)
        XCTAssertTrue(fobb.exchangeIncludesRST)
        XCTAssertFalse(fobb.exchangeIncludesSerial)
        XCTAssertFalse(fobb.exchangeIncludesName)
        XCTAssertNil(fobb.scoreMultipliers)
        XCTAssertTrue(fobb.entryClasses.isEmpty, "no X-classes here, unlike Skeeter")
        XCTAssertTrue(fobb.bonuses.isEmpty, "no bonus of any kind — an explicit NONE")
        XCTAssertNil(fobb.hubSpots)
        XCTAssertTrue(fobb.combines.isEmpty)
        XCTAssertTrue(fobb.isPartiallyVerified)
        XCTAssertFalse(fobb.outStateWorksHomeStationsOnly, "everyone works everyone")

        for rule in [fobb.multipliers.inState, fobb.multipliers.outState] {
            XCTAssertEqual(rule.classes, [.member],
                           "the ONLY multiplier is Bumblebees worked")
            XCTAssertEqual(rule.countScope, .perBand,
                           "'an additional Bumblebee Worked' on each new band")
            XCTAssertEqual(rule.multiplierFloor, 1, "'(Defaults to … = 1)'")
            XCTAssertFalse(rule.dxCountsEntities)
            XCTAssertNil(rule.dxMultCap)
            XCTAssertNil(rule.maxScoredMultipliers)
        }
        XCTAssertEqual(fobb.multipliers.inState, fobb.multipliers.outState,
                       "no home region — the sides cannot differ")
    }

    func testMemberExchangeIsTheBumblebeeNumbers() throws {
        let member = try XCTUnwrap(fobb.memberExchange)
        XCTAssertEqual(member.term, "Bumblebee number")
        XCTAssertEqual(member.shortTerm, "BB #")
        XCTAssertEqual(member.memberPlural, "Bumblebees")
        XCTAssertEqual(member.memberPoints, 3)
        XCTAssertEqual(member.qrpPoints, 3, "the element never moves the rate here")
        XCTAssertEqual(member.otherPoints, 3)
        XCTAssertEqual(member.qrpMaxWatts.limit(for: .cw), 5, "'5W QRP Maximum'")
    }

    /// Both sponsor-printed 2026 windows, exact instants (the NAQP
    /// precedent for a contest that runs twice a year).
    func testBothFourHourWindowsShip() throws {
        let windows = try XCTUnwrap(fobb.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-07-26T17:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-07-26T21:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-09-20T17:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-09-20T21:00:00Z"))
    }

    // MARK: Exchange parsing

    func testEveryPeerLocationShapeParses() {
        for token in ["NJ", "TX", "ON", "BC", "DC"] {
            guard case .success(let parsed) = ExchangeParser.parse(
                token, party: fobb, role: .outOfState) else {
                return XCTFail("\(token) must parse")
            }
            XCTAssertEqual(parsed.locations, [token])
        }
        // The C in S/P/C: a country typed as its prefix, or the bare token.
        for token in ["DL", "G", "XE", "DX"] {
            guard case .success = ExchangeParser.parse(
                token, party: fobb, role: .outOfState) else {
                return XCTFail("\(token) must parse")
            }
        }
        guard case .failure = ExchangeParser.parse("QQ", party: fobb, role: .outOfState)
        else { return XCTFail("garbage must not validate") }
    }

    /// The element refuses only text the party cannot read. A *blank* field
    /// logs: a station that sends no number is a home station.
    func testUnreadableElementBlocksLoggingButABlankOneDoesNot() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "fobb",
            exchangeMember: "5W",
            undoManager: nil
        )
        let flow = EntryFlow(document: doc)
        let context = EntryFlow.Context()

        flow.entry.call = "W4KAC/BB"
        flow.entry.exchangeTyped = "NC"
        flow.entry.memberRcvd = "seven"
        XCTAssertEqual(flow.logContact(context, undoManager: nil), .nothing,
                       "an unreadable element is a typo, not an exchange")
        XCTAssertTrue(doc.log.qsos.isEmpty)

        flow.entry.memberRcvd = "7"
        guard case .logged(let rows, _) = flow.logContact(context, undoManager: nil) else {
            return XCTFail("a complete exchange logs")
        }
        XCTAssertEqual(rows[0].memberSent, "5W", "the log's contest-long element")
        XCTAssertEqual(rows[0].memberRcvd, "7")
        XCTAssertEqual(rows[0].call, "W4KAC/BB", "the call as sent, suffix and all")
    }

    // MARK: Scoring — contacts × Bumblebees × 3

    /// The sponsor's product end to end: 4 contacts, one bee on two bands =
    /// 2 Bumblebees → 12 points × 2 = 24 = 4 × 2 × 3.
    func testThePrintedFormulaEndToEnd() {
        let rows = [
            qso(call: "W4KAC/BB", band: .m20, memberRcvd: "7"),
            qso(call: "W4KAC/BB", band: .m40, memberRcvd: "7"),
            qso(call: "K1HOME", band: .m20, their: "NH", memberRcvd: "5W"),
            qso(call: "AC7A", band: .m20, their: "AZ", memberRcvd: nil),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertEqual(score.validQSOs, 4)
        XCTAssertEqual(score.qsoPoints, 12, "every valid contact pays 3")
        XCTAssertEqual(score.memberQSOs, 2, "'an additional Bumblebee Worked'")
        XCTAssertEqual(score.multiplierCount, 2)
        XCTAssertEqual(score.total, 4 * 2 * 3)
    }

    /// The floor: contacts and no bee still score contacts × 1 × 3.
    func testABeeLessLogScoresContactsTimesThree() {
        let rows = [
            qso(call: "K1HOME", their: "NH", memberRcvd: "5W"),
            qso(call: "AC7A", their: "AZ", memberRcvd: nil),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertTrue(score.multiplierKeys.isEmpty)
        XCTAssertEqual(score.multiplierCount, 1, "'(Defaults to … = 1)'")
        XCTAssertEqual(score.total, 2 * 1 * 3)
    }

    func testAnEmptyLogIsZeroNotThree() {
        XCTAssertEqual(ScoreEngine.score(log: log([]), party: fobb).total, 0,
                       "the K4UPG row: the sponsor's calculator scored 0/0 as 0")
    }

    /// The S/P/C earns nothing — the case that would fail if the state,
    /// province or dx classes ever crept into this party's rule.
    func testLocationsNeverMultiply() {
        let rows = [
            qso(call: "K1NH", their: "NH", memberRcvd: "5W"),
            qso(call: "VE3ON", their: "ON", memberRcvd: "5W"),
            qso(call: "DL1AA", their: "DL", memberRcvd: "5W"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertTrue(score.workedValues(.state).isEmpty)
        XCTAssertTrue(score.workedValues(.province).isEmpty)
        XCTAssertTrue(score.workedValues(.dx).isEmpty)
        XCTAssertEqual(score.multiplierCount, 1, "the floor, not the locations")
        XCTAssertEqual(score.total, 3 * 1 * 3)
    }

    /// A DX bee counts like any bee: a prefix location, and a member key.
    func testADXBumblebeeIsABumblebee() {
        let score = ScoreEngine.score(
            log: log([qso(call: "G4CIB/P", their: "G", memberRcvd: "31")]),
            party: fobb)
        XCTAssertEqual(score.memberQSOs, 1)
        XCTAssertEqual(score.workedValues(.member), ["G4CIB/P"])
        XCTAssertEqual(score.total, 1 * 1 * 3)
    }

    /// A miniature of the sponsor's own scoreboard arithmetic, in the shape
    /// of its top row: N5GW claimed 79 × 52 × 3 = 12,324.
    func testTheScoreIsTheProductOfContactsAndBees() {
        var rows: [QSO] = []
        for i in 0..<6 { rows.append(qso(call: "N\(i)BB/BB", band: .m20, memberRcvd: "\(i + 1)")) }
        for i in 0..<4 { rows.append(qso(call: "K\(i)HOME", band: .m20, memberRcvd: "100W")) }
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertEqual(score.validQSOs, 10)
        XCTAssertEqual(score.multiplierCount, 6)
        XCTAssertEqual(score.total, 10 * 6 * 3)
    }

    // MARK: Dupes

    func testSameBandIsADupeNewBandIsNewContactAndNewBee() {
        let rows = [
            qso(call: "N7CQR/BB", band: .m20, memberRcvd: "23"),
            qso(call: "N7CQR/BB", band: .m20, memberRcvd: "23"),
            qso(call: "N7CQR/BB", band: .m40, memberRcvd: "23"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertEqual(score.dupeCount, 1, "'once on each Band'")
        XCTAssertEqual(score.validQSOs, 2)
        XCTAssertEqual(score.multiplierCount, 2)
        XCTAssertEqual(score.total, 2 * 2 * 3)
    }

    /// "QRP CW" — a phone row is invalid, not zero-point.
    func testPhoneRowsAreInvalidNotZeroPoint() {
        let score = ScoreEngine.score(
            log: log([qso(call: "W4KAC/BB", mode: .phone, memberRcvd: "7")]),
            party: fobb)
        XCTAssertEqual(score.invalidModeCount, 1)
        XCTAssertEqual(score.validQSOs, 0)
        XCTAssertTrue(score.multiplierKeys.isEmpty)
        XCTAssertEqual(score.qsoPoints, 0)
    }

    // MARK: The live badge

    /// A bee on a fresh band lights NEW MULT; the same bee there again, or
    /// a home station, does not — "try looking for Bumblebees on all of the
    /// bands that are open during this event".
    func testNewMultBadgeChasesBeesAcrossBands() {
        let contest = log([qso(call: "W4KAC/BB", band: .m20, memberRcvd: "7")])
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: fobb, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m20, modeClass: .cw,
            log: contest, party: fobb, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NH"], band: .m40, modeClass: .cw,
            log: contest, party: fobb, call: "K1HOME", memberRcvd: "100W"))
    }

    // MARK: Exports

    func testCabrilloCarriesTheElementsAndTheEntrantsToken() throws {
        let contest = log([qso(call: "W4KAC/BB", memberRcvd: "7")])
        let score = ScoreEngine.score(log: contest, party: fobb)
        let export = CabrilloExporter.export(log: contest, party: fobb, score: score)

        XCTAssertTrue(export.contains("CONTEST: ARS-FOBB"), export)
        XCTAssertTrue(export.contains("LOCATION: TX"), "the entrant's own state")
        let line = try XCTUnwrap(export.split(separator: "\n").first { $0.hasPrefix("QSO:") })
        let fields = line.split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(8)),
                       ["KE5CW", "599", "TX", "5W", "W4KAC/BB", "599", "NC", "7"])
    }

    func testAdifCarriesTheElementInAppFields() throws {
        let contest = try PartyLowering.lower(fobb)
        let record = AdifExporter.record(
            qso(call: "W4KAC/BB", memberRcvd: "7"),
            myCall: "KE5CW", contest: contest, side: PartyLowering.allID,
            counties: contest.countyRoster(), myState: "TX", writesEntity: false
        )
        XCTAssertTrue(record.contains("<app_qsopartylogger_member_sent:2>5W"), record)
        XCTAssertTrue(record.contains("<app_qsopartylogger_member_rcvd:1>7"), record)
    }

    // MARK: Messages

    func testDefaultMessagesTrailTheLocationWithTheElement() {
        let sets = MessageSets.defaults(for: fobb)
        XCTAssertTrue(sets.searchPounce.contains("{RST} {EXCH} {MEMBER}"),
                      "\(sets.searchPounce)")
    }

    // MARK: The roster source

    func testCallHistoryIsTheSponsorsRosterReport() throws {
        let source = try XCTUnwrap(fobb.callHistory)
        XCTAssertEqual(source.kind, .arsFobbRoster)
        XCTAssertEqual(source.pageURL,
                       "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php")
        XCTAssertEqual(source.filePrefix, "FOBB")
        XCTAssertEqual(source.token, "FOBB ROSTER")
    }

    // MARK: Verification posture

    /// Partial on exactly one open question, and nothing badges: the score
    /// and the export are exact on every case the sponsor has published.
    func testCaveatsAreNamedAndNoneBadge() {
        XCTAssertEqual(fobb.caveats.count, 4)
        XCTAssertTrue(fobb.blockingCaveats.isEmpty,
                      "nothing here mis-scores or mis-exports")
        XCTAssertEqual(fobb.operatorAlerts.count, 3,
                       "one open question and two limitations; provenance stands alone")
    }

    // MARK: Not a Challenge contest

    func testFOBBIsUpcomingButNotAChallengeContest() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        XCTAssertNil(calendar.contest(partyID: "fobb"))
        XCTAssertNil(calendar.contest(named: "ARS Flight of the Bumblebees"))

        let eve = ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z")!
        let upcoming = UpcomingContests.upcoming(
            now: eve,
            parties: PartyCatalog.loadBundled(),
            calendar: calendar,
            records: []
        )
        let entry = upcoming.first { $0.partyID == "fobb" }
        XCTAssertNotNil(entry, "a bundled schedule surfaces by itself")
        XCTAssertEqual(entry?.isApproved, false, "deliberately outside the Challenge")
        XCTAssertEqual(entry?.nextWindow.start,
                       ISO8601DateFormatter().date(from: "2026-09-20T17:00:00Z"),
                       "the July window is past; the Fall one is next")
    }
}

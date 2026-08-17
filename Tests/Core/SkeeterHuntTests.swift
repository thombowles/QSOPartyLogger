import XCTest
@testable import QSOPartyLogger

/// NJQRP Skeeter Hunt — the catalogue's first QRP sprint, and its second
/// non-State-QSO-Party contest (NAQP was the first). Four hours, no
/// counties, points by what the worked station *is* (Skeeter 3 / QRP 2 /
/// QRO 1, from the received number-or-power element), S/P/Cs once, a
/// self-declared X1–X4 class multiplying the whole score, and blackjack.
/// Rules research: docs/research/skeeter_rules.md; the score formula is
/// nowhere printed and was verified against the sponsor's own 2025
/// scoreboard (§8), which gen_skeeter.py re-derives.
@MainActor
final class SkeeterHuntTests: XCTestCase {

    var skeeter: PartyDefinition!

    override func setUpWithError() throws {
        skeeter = try XCTUnwrap(PartyCatalog.party(id: "skeeter"), "skeeter.json must load")
    }

    var seq: TimeInterval = 0
    /// Inside the 2026 window (17:00–21:00Z, 2026-08-16) by construction.
    func qso(
        call: String,
        band: Band = .m20,
        mode: ModeClass = .cw,
        their: String,
        memberRcvd: String?
    ) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_786_899_600 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : (mode == .digital ? "FT8" : "CW"),
            rstSent: "599", rstRcvd: "599",
            memberSent: "20", memberRcvd: memberRcvd,
            myLoc: "TX", theirLoc: their
        )
    }

    func log(_ qsos: [QSO], classID: String = "X1") -> ContestLog {
        ContestLog(
            partyID: "skeeter",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "20",
            entryClassID: classID
        )
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(skeeter.name, "NJQRP Skeeter Hunt")
        XCTAssertEqual(skeeter.cabrilloContest, "SKEETER-HUNT")
        XCTAssertEqual(skeeter.homeState, "NA", "a pseudo-state, labels only")
        XCTAssertFalse(skeeter.hasHomeRegion)
        XCTAssertTrue(skeeter.counties.isEmpty,
                      "the multipliers are the standard tables; nothing to enumerate")
        XCTAssertEqual(skeeter.allowedModeClasses, [.phone, .cw], "'Mode – CW, SSB'")
        XCTAssertEqual(skeeter.maxSimultaneousCounties, 1)
        XCTAssertEqual(skeeter.dxStyle, .prefix)
        XCTAssertTrue(skeeter.acceptsDXToken, "a bare DX resolves from the callsign")
        XCTAssertTrue(skeeter.exchangeIncludesRST)
        XCTAssertFalse(skeeter.exchangeIncludesSerial)
        XCTAssertFalse(skeeter.exchangeIncludesName)
        XCTAssertNil(skeeter.scoreMultipliers,
                     "the class factor is entryClasses, not a category product")
        XCTAssertNil(skeeter.hubSpots)
        XCTAssertTrue(skeeter.combines.isEmpty)
        XCTAssertTrue(skeeter.isPartiallyVerified)
        XCTAssertFalse(skeeter.outStateWorksHomeStationsOnly, "everyone works everyone")
        XCTAssertEqual(skeeter.provinces, MultClass.canadianProvinces,
                       "the sponsor publishes no list; the standard 13 apply")

        for rule in [skeeter.multipliers.inState, skeeter.multipliers.outState] {
            XCTAssertEqual(rule.classes, [.state, .province, .dx])
            XCTAssertEqual(rule.countScope, .once, "'S/P/C's only count once'")
            XCTAssertTrue(rule.dxCountsEntities, "each country is its own multiplier")
            XCTAssertFalse(rule.homeStateCountsViaCounty)
            XCTAssertNil(rule.dxMultCap)
        }
        XCTAssertEqual(skeeter.multipliers.inState, skeeter.multipliers.outState,
                       "no home region — the sides cannot differ")
    }

    func testMemberExchangeIsTheSkeeterNumbers() throws {
        let member = try XCTUnwrap(skeeter.memberExchange)
        XCTAssertEqual(member.term, "Skeeter number")
        XCTAssertEqual(member.shortTerm, "Skeeter #")
        XCTAssertEqual(member.memberPlural, "Skeeters",
                       "the sidebar counts stations, not numbers")
        XCTAssertEqual(member.memberPoints, 3)
        XCTAssertEqual(member.qrpPoints, 2)
        XCTAssertEqual(member.otherPoints, 1)
        XCTAssertEqual(member.qrpMaxWatts.limit(for: .cw), 5, "'5W max CW'")
        XCTAssertEqual(member.qrpMaxWatts.limit(for: .phone), 10, "'10 Watts max SSB'")
    }

    func testEntryClassesAreTheSponsorsFour() {
        XCTAssertEqual(skeeter.entryClasses.map(\.id), ["X1", "X2", "X3", "X4"])
        XCTAssertEqual(skeeter.entryClasses.map(\.factor),
                       [1, 2, 3, 4].map { ScoreFactor($0) })
        XCTAssertEqual(skeeter.resolvedEntryClass(id: "")?.id, "X1",
                       "unchosen scores the lowest, never a guess upward")
    }

    func testFiveBandsNoWARCNo160() {
        XCTAssertEqual(skeeter.validBands, [.m80, .m40, .m20, .m15, .m10])
    }

    /// One four-hour window, the sponsor's own instants: "Sunday August
    /// 16th, 2026 … from 17:00 UTC to 21:00 UTC".
    func testScheduleIsTheFourHourSprint() throws {
        let windows = try XCTUnwrap(skeeter.schedule)
        XCTAssertEqual(windows.count, 1)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-08-16T17:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-08-16T21:00:00Z"))
    }

    // MARK: Exchange parsing

    func testEveryPeerLocationShapeParses() {
        for token in ["NJ", "TX", "ON", "BC", "DC"] {
            guard case .success(let parsed) = ExchangeParser.parse(
                token, party: skeeter, role: .outOfState) else {
                return XCTFail("\(token) must parse")
            }
            XCTAssertEqual(parsed.locations, [token])
        }
        // The C in S/P/C: a DX country typed as its prefix, or the bare token.
        for token in ["DL", "G", "XE", "DX"] {
            guard case .success = ExchangeParser.parse(
                token, party: skeeter, role: .outOfState) else {
                return XCTFail("\(token) must parse")
            }
        }
        // Not ZZ — that sits inside Brazil's DXCC block (ZV–ZZ) and rightly
        // parses. The Q block is allocated to nobody.
        guard case .failure = ExchangeParser.parse("QQ", party: skeeter, role: .outOfState)
        else { return XCTFail("garbage must not validate") }
    }

    /// The element refuses only text the party cannot read — a mis-keyed
    /// number would score as QRO in silence. A *blank* field logs, because
    /// that is the QRO case (see the POTA test below).
    func testUnreadableElementBlocksLoggingButABlankOneDoesNot() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "skeeter",
            exchangeMember: "20",
            entryClassID: "X3",
            undoManager: nil
        )
        let flow = EntryFlow(document: doc)
        let context = EntryFlow.Context()

        flow.entry.call = "W2LJ"
        flow.entry.exchangeTyped = "NJ"
        flow.entry.memberRcvd = "watts"
        XCTAssertEqual(flow.logContact(context, undoManager: nil), .nothing,
                       "an unreadable element is a typo, not an exchange")
        XCTAssertTrue(doc.log.qsos.isEmpty)

        flow.entry.memberRcvd = "13"
        guard case .logged(let rows, _) = flow.logContact(context, undoManager: nil) else {
            return XCTFail("a complete exchange logs")
        }
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].memberSent, "20", "the log's contest-long element")
        XCTAssertEqual(rows[0].memberRcvd, "13")
        XCTAssertEqual(rows[0].theirLoc, "NJ")
    }

    /// A POTA activator answering the sprint sends a report and a state and
    /// nothing else. That contact logs with the element blank and scores as
    /// the sponsor's "any other QRO station" — one point.
    func testAStationThatSendsNoElementLogsAsQRO() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "skeeter",
            exchangeMember: "20",
            undoManager: nil
        )
        let flow = EntryFlow(document: doc)
        let context = EntryFlow.Context()

        flow.entry.call = "K4POTA"
        flow.entry.exchangeTyped = "GA"
        guard case .logged(let rows, _) = flow.logContact(context, undoManager: nil) else {
            return XCTFail("a blank element must not block a real contact")
        }
        XCTAssertNil(rows[0].memberRcvd)

        let score = ScoreEngine.score(log: doc.log, party: skeeter)
        XCTAssertEqual(score.qsoPoints, 1)
        XCTAssertEqual(score.otherQSOs, 1)
        XCTAssertEqual(score.multiplierCount, 1, "GA still counts")
    }

    // MARK: Points — 3 / 2 / 1 from the received element

    func testPointsByWorkedStationClass() {
        let rows = [
            qso(call: "W2LJ", their: "NJ", memberRcvd: "13"),    // Skeeter: 3
            qso(call: "K1SW", their: "NH", memberRcvd: "5W"),    // QRP: 2
            qso(call: "W9XYZ", their: "IL", memberRcvd: "100W"), // QRO: 1
            qso(call: "K4POTA", their: "GA", memberRcvd: nil),   // QRO: 1
        ]
        let score = ScoreEngine.score(log: log(rows), party: skeeter)
        XCTAssertEqual(score.qsoPoints, 7)
        XCTAssertEqual(score.memberQSOs, 1)
        XCTAssertEqual(score.qrpQSOs, 1)
        XCTAssertEqual(score.otherQSOs, 2, "a stated 100 W and an unstated power")
    }

    /// Regression (2026-08-16, on the air): the score card said 70 points
    /// while every row in the log list read 1 — the list was recomputing
    /// from the party's mode table, which knows nothing of the received
    /// element. Each row must carry what the engine actually paid for it.
    func testEachRowIsPaidByWhatTheWorkedStationIs() {
        let rows = [
            qso(call: "W2LJ", their: "NJ", memberRcvd: "13"),    // Skeeter: 3
            qso(call: "K1SW", their: "NH", memberRcvd: "5W"),    // QRP: 2
            qso(call: "W9XYZ", their: "IL", memberRcvd: "100W"), // QRO: 1
            qso(call: "K4POTA", their: "GA", memberRcvd: nil),   // QRO: 1
        ]
        let score = ScoreEngine.score(log: log(rows), party: skeeter)
        XCTAssertEqual(rows.map { score.pointsByRowID[$0.id] }, [3, 2, 1, 1])
    }

    /// The QRP ceiling is the event's own power rule, per mode and
    /// inclusive: 10 W is QRP on phone and QRO on CW.
    func testQRPBoundaryFollowsTheModePowerLimits() {
        let phone = ScoreEngine.score(
            log: log([qso(call: "K1SW", mode: .phone, their: "NH", memberRcvd: "10W")]),
            party: skeeter)
        XCTAssertEqual(phone.qsoPoints, 2)

        let cw = ScoreEngine.score(
            log: log([qso(call: "K1SW", mode: .cw, their: "NH", memberRcvd: "10W")]),
            party: skeeter)
        XCTAssertEqual(cw.qsoPoints, 1)
    }

    /// "Mode – CW, SSB" — a digital row is invalid, not zero-point.
    func testDigitalRowsAreInvalidNotZeroPoint() {
        let score = ScoreEngine.score(
            log: log([qso(call: "W2LJ", mode: .digital, their: "NJ", memberRcvd: "13")]),
            party: skeeter)
        XCTAssertEqual(score.invalidModeCount, 1)
        XCTAssertEqual(score.validQSOs, 0)
        XCTAssertEqual(score.qsoPoints, 0)
        XCTAssertTrue(score.multiplierKeys.isEmpty)
    }

    // MARK: Multipliers — S/P/Cs once, would fail under any per-band scope

    func testSPCsCountOnceForTheContest() {
        let rows = [
            qso(call: "W2LJ", band: .m40, their: "NJ", memberRcvd: "13"),
            qso(call: "W2LJ", band: .m20, their: "NJ", memberRcvd: "13"),
            qso(call: "W2LJ", band: .m15, their: "NJ", memberRcvd: "13"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: skeeter)
        // The sponsor's own example: three different Skeeter QSOs, one NJ.
        XCTAssertEqual(score.validQSOs, 3)
        XCTAssertEqual(score.qsoPoints, 9)
        XCTAssertEqual(score.multiplierCount, 1,
                       "'you can only count NJ once for S/P/C muliplier credit' [sic]")
    }

    func testProvincesAndDXEntitiesArePeerMultipliers() {
        let rows = [
            qso(call: "VE3ABC", their: "ON", memberRcvd: "5W"),
            qso(call: "DL1AA", their: "DL", memberRcvd: "5W"),
            qso(call: "DJ2BB", band: .m40, their: "DL", memberRcvd: "5W"),
            qso(call: "F5XYZ", their: "F", memberRcvd: "5W"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: skeeter)
        XCTAssertEqual(score.workedValues(.province), ["ON"])
        XCTAssertEqual(score.workedValues(.dx).count, 2,
                       "Germany once however many Germans, France once")
        XCTAssertEqual(score.multiplierCount, 3)
    }

    // MARK: Dupes

    func testSameBandModeIsADupeNewBandIsNot() {
        let rows = [
            qso(call: "W2LJ", band: .m20, their: "NJ", memberRcvd: "13"),
            qso(call: "W2LJ", band: .m20, their: "NJ", memberRcvd: "13"),
            qso(call: "W2LJ", band: .m40, their: "NJ", memberRcvd: "13"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: skeeter)
        XCTAssertEqual(score.dupeCount, 1)
        XCTAssertEqual(score.validQSOs, 2, "'Stations can be worked on different bands'")
    }

    // MARK: The whole formula, end to end

    /// A miniature of the sponsor's scoreboard arithmetic:
    /// (3·2 + 2·1 + 1·1) points × 4 S/P/Cs × X3 + 1000 blackjack
    /// (N0AA + W2BB + WD8CC + W1DD = 10 + 2 + 8 + 1 = 21).
    func testTheVerifiedScoreFormulaEndToEnd() {
        let rows = [
            qso(call: "N0AA", their: "MO", memberRcvd: "5"),     // Skeeter, 3
            qso(call: "W2BB", their: "NJ", memberRcvd: "7"),     // Skeeter, 3
            qso(call: "WD8CC", their: "OH", memberRcvd: "5W"),   // QRP, 2
            qso(call: "W1DD", their: "NH", memberRcvd: "100W"),  // QRO, 1
        ]
        let score = ScoreEngine.score(log: log(rows, classID: "X3"), party: skeeter)
        XCTAssertEqual(score.qsoPoints, 9)
        XCTAssertEqual(score.multiplierCount, 4)
        XCTAssertEqual(score.categoryFactor, ScoreFactor(3))
        XCTAssertEqual(score.bonusPoints, 1000)
        XCTAssertEqual(score.total, 9 * 4 * 3 + 1000)
    }

    func testBlackjackNeedsExactlyTwentyOne() {
        // 10 + 2 + 8 = 20: no subset reaches 21.
        let rows = [
            qso(call: "N0AA", their: "MO", memberRcvd: "5"),
            qso(call: "W2BB", their: "NJ", memberRcvd: "7"),
            qso(call: "WD8CC", their: "OH", memberRcvd: "5W"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: skeeter)
        XCTAssertEqual(score.bonusPoints, 0)
    }

    // MARK: Exports

    func testCabrilloCarriesTheElementsAndTheEntrantsToken() throws {
        let contest = log([qso(call: "W2LJ", their: "NJ", memberRcvd: "13")])
        let score = ScoreEngine.score(log: contest, party: skeeter)
        let export = CabrilloExporter.export(log: contest, party: skeeter, score: score)

        XCTAssertTrue(export.contains("CONTEST: SKEETER-HUNT"), export)
        XCTAssertTrue(export.contains("LOCATION: TX"), "the entrant's own state")
        let line = try XCTUnwrap(export.split(separator: "\n").first { $0.hasPrefix("QSO:") })
        let fields = line.split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(8)),
                       ["KE5CW", "599", "TX", "20", "W2LJ", "599", "NJ", "13"])
    }

    func testAdifCarriesTheElementInAppFields() {
        let record = AdifExporter.record(
            qso(call: "W2LJ", their: "NJ", memberRcvd: "13"),
            myCall: "KE5CW", party: skeeter, countyNames: [:], myState: "TX"
        )
        XCTAssertTrue(record.contains("<app_qsopartylogger_member_sent:2>20"), record)
        XCTAssertTrue(record.contains("<app_qsopartylogger_member_rcvd:2>13"), record)
        XCTAssertTrue(record.contains("<state:2>NJ"), record)
    }

    // MARK: Messages

    func testDefaultMessagesTrailTheLocationWithTheElement() {
        let sets = MessageSets.defaults(for: skeeter)
        XCTAssertTrue(sets.searchPounce.contains("{RST} {EXCH} {MEMBER}"),
                      "\(sets.searchPounce)")
        XCTAssertTrue(sets.run.contains("{CALL} {RST} {EXCH} {MEMBER}"),
                      "\(sets.run)")
    }

    // MARK: The roster source

    func testCallHistoryIsTheSponsorsRosterPage() throws {
        let source = try XCTUnwrap(skeeter.callHistory)
        XCTAssertEqual(source.kind, .w2ljRosterPage)
        // HTTPS, not the http:// the sponsor links: App Transport Security
        // refuses plain HTTP outright, so the http form never loaded at all.
        XCTAssertEqual(source.pageURL, "https://w2lj.blogspot.com/p/njqrp-skeeter-hunt.html")
        XCTAssertEqual(source.filePrefix, "SKEETER")
        XCTAssertEqual(source.token, "SKEETER ROSTER")
    }

    /// No bundled party may carry a plain-HTTP source URL — ATS blocks it,
    /// and the operator sees a policy message instead of a roster.
    func testNoBundledSourceURLIsPlainHTTP() {
        for party in PartyCatalog.loadBundled() {
            guard let pageURL = party.callHistory?.pageURL else { continue }
            XCTAssertTrue(pageURL.hasPrefix("https://"), "\(party.id): \(pageURL)")
        }
    }

    // MARK: Verification posture

    /// Partial, with every gap named and none of them badge-raising: the
    /// score and the export are exact, and the open questions are
    /// inferences an operator can read before entering.
    func testCaveatsAreNamedAndNoneBadge() {
        XCTAssertEqual(skeeter.caveats.count, 6)
        XCTAssertTrue(skeeter.blockingCaveats.isEmpty,
                      "nothing here mis-scores or mis-exports")
        XCTAssertEqual(skeeter.operatorAlerts.count, 5,
                       "the five numbered items; the provenance caveat stands alone")
    }

    // MARK: Not a Challenge contest

    func testSkeeterHuntIsUpcomingButNotAChallengeContest() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        XCTAssertNil(calendar.contest(partyID: "skeeter"))
        XCTAssertNil(calendar.contest(named: "NJQRP Skeeter Hunt"))

        let eve = ISO8601DateFormatter().date(from: "2026-08-10T12:00:00Z")!
        let upcoming = UpcomingContests.upcoming(
            now: eve,
            parties: PartyCatalog.loadBundled(),
            calendar: calendar,
            records: []
        )
        let entry = upcoming.first { $0.partyID == "skeeter" }
        XCTAssertNotNil(entry, "a bundled schedule surfaces by itself")
        XCTAssertEqual(entry?.isApproved, false, "deliberately outside the Challenge")
    }
}

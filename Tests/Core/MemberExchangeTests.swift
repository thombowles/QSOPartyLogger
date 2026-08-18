import XCTest
@testable import QSOPartyLogger

/// The member-number-or-power exchange element — QRP sprints whose third
/// token is a club number for members and an output power for everyone else,
/// and whose QSO points are decided by it. Skeeter Hunt: "Skeeter Stations -
/// RST, S/P/C, Skeeter number / Non-Skeeter Stations - RST, S/P/C, Output
/// power (For example - 559 NY 5W)", paying 3/2/1.
/// See docs/superpowers/specs/2026-08-04-skeeter-hunt-design.md.
///
/// **Party-free by design** (constitution Article 4): every party in this
/// file is synthetic, so the structural change is proved without a sponsor's
/// rules riding along in the same commit.
final class MemberExchangeTests: XCTestCase {

    var seq: TimeInterval = 0
    func qso(
        call: String = "N2CU",
        band: Band = .m20,
        mode: ModeClass = .cw,
        my: String = "TX",
        their: String = "NY",
        memberSent: String? = nil,
        memberRcvd: String? = nil
    ) -> QSO {
        seq += 60
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_791_000_000 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : "CW",
            rstSent: "599", rstRcvd: "599",
            memberSent: memberSent, memberRcvd: memberRcvd,
            myLoc: my, theirLoc: their
        )
    }

    /// The Skeeter Hunt's own numbers, on a synthetic party.
    static let memberBlock = """
    ,"memberExchange":{"term":"Skeeter number","shortTerm":"Skeeter #",
    "memberPlural":"Skeeters",
    "memberPoints":3,"qrpPoints":2,"otherPoints":1,
    "qrpMaxWatts":{"phone":10,"cw":5,"digital":5}}
    """

    /// A minimal party, optionally with the member block — decoded rather
    /// than registered, because the capability ships before any bundled
    /// party carries it.
    func party(_ extra: String = "") throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"m","name":"M","cabrilloContest":"M","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m","20m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[{"abbr":"ALL","name":"Allen"}]\(extra)}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    func memberParty() throws -> PartyDefinition {
        try party(Self.memberBlock)
    }

    func log(_ qsos: [QSO], party: PartyDefinition? = nil) -> ContestLog {
        ContestLog(
            partyID: party?.id ?? "m",
            station: StationProfile(),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos
        )
    }

    // MARK: The value grammar

    func testDigitsAloneAreAMemberNumber() {
        XCTAssertEqual(MemberExchange.parse("13"), .member(number: "13"))
        XCTAssertEqual(MemberExchange.parse(" 260 "), .member(number: "260"))
        XCTAssertEqual(MemberExchange.parse("013"), .member(number: "013"),
                       "kept verbatim — the display is what was copied")
    }

    func testPowersRequireTheirUnit() {
        XCTAssertEqual(MemberExchange.parse("5W"), .power(watts: 5))
        XCTAssertEqual(MemberExchange.parse("5w"), .power(watts: 5))
        XCTAssertEqual(MemberExchange.parse("2.5W"), .power(watts: 2.5))
        XCTAssertEqual(MemberExchange.parse("500MW"), .power(watts: 0.5))
        XCTAssertEqual(MemberExchange.parse("1KW"), .power(watts: 1000))
        XCTAssertEqual(MemberExchange.parse("100W"), .power(watts: 100))
    }

    /// The two forms an operator actually types for a non-member's power,
    /// lower case and with the space they land on between number and unit.
    func testTypedPowerFormsAllRead() {
        for (typed, watts) in [("5w", 5.0), ("5 w", 5.0), ("100w", 100.0),
                               ("100 W", 100.0), (" 5W ", 5.0)] {
            XCTAssertEqual(MemberExchange.parse(typed), .power(watts: watts), typed)
        }
    }

    func testUnreadableElementsParseToNil() {
        XCTAssertNil(MemberExchange.parse(""))
        XCTAssertNil(MemberExchange.parse("  "))
        XCTAssertNil(MemberExchange.parse("W"), "a unit with no number")
        XCTAssertNil(MemberExchange.parse("5X"), "not a unit")
        XCTAssertNil(MemberExchange.parse("NR13"), "the NR prefix is CW framing, not data")
        XCTAssertNil(MemberExchange.parse("5.5.5W"), "one decimal point only")
        XCTAssertNil(MemberExchange.parse("QRP"))
    }

    // MARK: Points from the received element

    func testPointsByReceivedElement() throws {
        let member = try XCTUnwrap(memberParty().memberExchange)
        XCTAssertEqual(member.points(forReceived: "13", modeClass: .cw), 3)
        XCTAssertEqual(member.points(forReceived: "5W", modeClass: .cw), 2)
        XCTAssertEqual(member.points(forReceived: "100W", modeClass: .cw), 1)
        XCTAssertEqual(member.points(forReceived: "500MW", modeClass: .phone), 2)
    }

    /// A station that sends no element is a QRO station — the sponsor's own
    /// third line, "Working any other QRO station - 1 point". Claiming the
    /// QRP rate for an unknown power would overstate the score.
    func testAnAbsentElementIsAQROStation() throws {
        let member = try XCTUnwrap(memberParty().memberExchange)
        XCTAssertEqual(member.workedClass(forReceived: nil, modeClass: .cw), .other)
        XCTAssertEqual(member.workedClass(forReceived: "", modeClass: .cw), .other)
        XCTAssertEqual(member.points(forReceived: nil, modeClass: .cw), 1)
        XCTAssertEqual(member.points(forReceived: "junk", modeClass: .cw), 1)
    }

    /// The QRP ceiling is per mode class and inclusive: the event's own power
    /// rule is "5W max CW, 10 Watts max SSB", so 10 W is QRP on phone and
    /// QRO on CW, and the limits themselves are QRP exactly.
    func testQRPBoundaryIsInclusiveAndPerMode() throws {
        let member = try XCTUnwrap(memberParty().memberExchange)
        XCTAssertEqual(member.points(forReceived: "5W", modeClass: .cw), 2)
        XCTAssertEqual(member.points(forReceived: "10W", modeClass: .phone), 2)
        XCTAssertEqual(member.points(forReceived: "10W", modeClass: .cw), 1)
        XCTAssertEqual(member.points(forReceived: "6W", modeClass: .cw), 1)
        XCTAssertEqual(member.points(forReceived: "12W", modeClass: .phone), 1)
    }

    // MARK: Defaults — nothing changes for the parties without the element

    func testMemberFieldsDefaultToNilOnTheModel() {
        let q = QSO(
            timestampUTC: Date(), call: "W1A", band: .m40, modeClass: .cw,
            rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "HIL", theirLoc: "TX"
        )
        XCTAssertNil(q.memberSent)
        XCTAssertNil(q.memberRcvd)
    }

    /// A log written before member support must decode unchanged.
    func testLogsWithoutMemberKeysStillDecode() throws {
        let json = """
        {"id":"\(UUID().uuidString)","groupID":"\(UUID().uuidString)",
         "timestampUTC":770000000,"call":"W1ABC","band":"40m","modeClass":"cw",
         "rawMode":"CW","rstSent":"599","rstRcvd":"599","myLoc":"HIL","theirLoc":"TX"}
        """
        let decoded = try JSONDecoder().decode(QSO.self, from: Data(json.utf8))
        XCTAssertNil(decoded.memberSent)
        XCTAssertNil(decoded.memberRcvd)
    }

    func testExchangeMemberDefaultsEmptyAndRoundTrips() throws {
        let old = try ContestLog.decode(from: ContestLog(partyID: "ksqp").encoded())
        XCTAssertEqual(old.exchangeMember, "")

        var log = ContestLog(partyID: "ksqp")
        log.exchangeMember = "13"
        let reopened = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(reopened.exchangeMember, "13")
    }

    func testBlockDecodesFromJSON() throws {
        XCTAssertNil(try party().memberExchange, "absent means none")
        let member = try XCTUnwrap(memberParty().memberExchange)
        XCTAssertEqual(member.term, "Skeeter number")
        XCTAssertEqual(member.shortTerm, "Skeeter #")
        XCTAssertEqual(member.memberPlural, "Skeeters")
        XCTAssertEqual(member.memberPoints, 3)
        XCTAssertEqual(member.qrpPoints, 2)
        XCTAssertEqual(member.otherPoints, 1)
        XCTAssertEqual(member.qrpMaxWatts.limit(for: .cw), 5)
        XCTAssertEqual(member.qrpMaxWatts.limit(for: .phone), 10)
    }

    /// The bundled parties whose exchange carries the element, named so a
    /// party cannot gain one incidentally — each flip is its own commit
    /// (Article 9). The Skeeter Hunt was the first; FOBB, the ARS sprint it
    /// was modelled on, is the second — and the first whose element decides
    /// only the multiplier, never the rate (all three of its rates are 3).
    func testWhichPartiesCarryAMemberExchange() {
        let withMember = PartyCatalog.loadBundled()
            .filter { $0.memberExchange != nil }.map(\.id).sorted()
        XCTAssertEqual(withMember, ["fobb", "skeeter"],
                       "a party gaining the element is a deliberate edit here")
    }

    // MARK: Scoring

    func testScoringPaysByTheReceivedElement() throws {
        let party = try memberParty()
        let rows = [
            qso(call: "W2LJ", their: "NJ", memberRcvd: "13"),      // 3
            qso(call: "K1QRP", their: "NH", memberRcvd: "5W"),     // 2
            qso(call: "W9BIG", their: "IL", memberRcvd: "100W"),   // 1
        ]
        let score = ScoreEngine.score(log: log(rows, party: party), party: party)
        XCTAssertEqual(score.qsoPoints, 6)
        XCTAssertEqual(score.memberQSOs, 1)
        XCTAssertEqual(score.qrpQSOs, 1)
        XCTAssertEqual(score.otherQSOs, 1)
    }

    /// A row with no element is a QRO contact: one point, and counted in the
    /// QRO tally, because that is a real station the summary email reports.
    func testAMissingElementScoresAndCountsAsQRO() throws {
        let party = try memberParty()
        let score = ScoreEngine.score(
            log: log([qso(call: "W1AW", their: "CT")], party: party), party: party)
        XCTAssertEqual(score.qsoPoints, 1)
        XCTAssertEqual(score.otherQSOs, 1, "a POTA station answering the sprint")
        XCTAssertEqual(score.memberQSOs + score.qrpQSOs, 0)
    }

    /// A dupe's element earns nothing — the classification counters count
    /// valid rows only, because they are the summary email's numbers.
    func testDupesDoNotReachThePointsOrTheCounters() throws {
        let party = try memberParty()
        let rows = [
            qso(call: "W2LJ", their: "NJ", memberRcvd: "13"),
            qso(call: "W2LJ", their: "NJ", memberRcvd: "13"),
        ]
        let score = ScoreEngine.score(log: log(rows, party: party), party: party)
        XCTAssertEqual(score.qsoPoints, 3)
        XCTAssertEqual(score.memberQSOs, 1)
        XCTAssertEqual(score.dupeCount, 1)
    }

    /// A report party's scoring is untouched by the element machinery: no
    /// member block, no branch (Article 4).
    func testReportPartiesScoreExactlyAsBefore() throws {
        let party = try party()
        let rows = [qso(call: "W1AW", their: "CT", memberRcvd: "13")]
        let score = ScoreEngine.score(log: log(rows, party: party), party: party)
        XCTAssertEqual(score.qsoPoints, 1,
                       "a stray member value on a row cannot move a report party's score")
        XCTAssertEqual(score.memberQSOs, 0)
    }

    // MARK: One contact, one element

    func testOneElementPerContactAcrossACountyLine() {
        let rows = CountyLineExpander.expand(
            entry: .init(
                call: "W0GXQ", rstSent: "599", rstRcvd: "599",
                memberSent: "20", memberRcvd: "5W",
                band: .m40, modeClass: .cw, rawMode: "CW",
                freqKHz: nil, timestampUTC: Date()
            ),
            myLocs: ["TX"],
            theirLocs: ["KNB", "MIL"]
        )
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(row.memberSent, "20")
            XCTAssertEqual(row.memberRcvd, "5W")
        }
    }

    // MARK: Cabrillo

    /// The element trails each side's location, the way it is sent
    /// ("559 NJ NR 13" → `... 599 TX 20 ... 599 NJ 13`).
    func testCabrilloLineCarriesTheElementAfterEachLocation() throws {
        let line = CabrilloExporter.qsoLine(
            qso(call: "W2LJ", their: "NJ", memberSent: "20", memberRcvd: "13"),
            myCall: "KE5CW",
            contest: try PartyLowering.lower(memberParty()), side: PartyLowering.outsideID
        )
        let fields = line.split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(8)),
                       ["KE5CW", "599", "TX", "20", "W2LJ", "599", "NJ", "13"])
    }

    /// A row with no element renders exactly as it always has (Article 4).
    func testCabrilloLineWithoutTheElementIsUnchanged() throws {
        let fields = CabrilloExporter.qsoLine(qso(call: "W1AW", their: "CT"), myCall: "KE5CW",
                                              contest: try PartyLowering.lower(party()),
                                              side: PartyLowering.outsideID)
            .split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(6)), ["KE5CW", "599", "TX", "W1AW", "599", "CT"])
    }

    // MARK: ADIF

    func testAdifCarriesTheElementOnlyWhenPresent() throws {
        let memberContest = try PartyLowering.lower(memberParty())
        let carried = AdifExporter.record(
            qso(memberSent: "20", memberRcvd: "5W"),
            myCall: "KE5CW", contest: memberContest, side: PartyLowering.outsideID,
            counties: memberContest.countyRoster(), myState: "TX", writesEntity: false
        )
        XCTAssertTrue(carried.contains("<app_qsopartylogger_member_sent:2>20"), carried)
        XCTAssertTrue(carried.contains("<app_qsopartylogger_member_rcvd:2>5W"), carried)

        let plainContest = try PartyLowering.lower(party())
        let plain = AdifExporter.record(
            qso(), myCall: "KE5CW", contest: plainContest, side: PartyLowering.outsideID,
            counties: plainContest.countyRoster(), myState: "TX", writesEntity: false
        )
        XCTAssertFalse(plain.contains("app_qsopartylogger_member"), plain)
    }

    // MARK: The {MEMBER} macro

    func testMemberMacroExpandsVerbatimAndNeverCuts() {
        let text = AppSettings.expandMacros(
            "{RST} {EXCH} {MEMBER}",
            myCall: "KE5CW", call: "N2CU", rst: "599",
            exchange: "TX", member: "NR 190",
            cutNumbers: true, cutOne: true
        )
        XCTAssertEqual(text, "5NN TX NR 190",
                       "the report cuts; the member value goes out as copied")
    }

    func testMemberMacroExpandsEmptyWhenUnset() {
        let text = AppSettings.expandMacros(
            "{EXCH} {MEMBER}", myCall: "KE5CW", call: "", rst: "599", exchange: "TX"
        )
        XCTAssertEqual(text, "TX", "an unset element vanishes, like an unset serial")
    }

    // MARK: Default messages

    /// The default exchange message follows the party's shape, with the
    /// element after the location — the order it is sent in ("559 NJ NR 13").
    func testDefaultMessagesForAMemberPartyTrailTheLocation() throws {
        let sets = MessageSets.defaults(for: try memberParty())
        XCTAssertTrue(sets.searchPounce.contains("{RST} {EXCH} {MEMBER}"),
                      "\(sets.searchPounce)")

        let plain = MessageSets.defaults(for: try party())
        XCTAssertFalse(plain.run.contains { $0.contains("{MEMBER}") },
                       "report parties are untouched")
    }

    // MARK: The entry row

    /// Blank logs — it is the QRO case, and a real contact. Only text the
    /// party cannot read is refused, because a mis-keyed number would
    /// silently score as QRO.
    func testOnlyUnreadableTextBlocksLogging() throws {
        let entry = EntryState()
        let memberParty = try memberParty()

        XCTAssertFalse(entry.invalidMember(party: memberParty),
                       "blank is a QRO station, not a half-copied exchange")
        entry.memberRcvd = "   "
        XCTAssertFalse(entry.invalidMember(party: memberParty), "whitespace is blank")
        entry.memberRcvd = "junk"
        XCTAssertTrue(entry.invalidMember(party: memberParty))
        entry.memberRcvd = "13"
        XCTAssertFalse(entry.invalidMember(party: memberParty))
        entry.memberRcvd = "100w"
        XCTAssertFalse(entry.invalidMember(party: memberParty))

        entry.memberRcvd = "junk"
        XCTAssertFalse(entry.invalidMember(party: try party()),
                       "parties without the element never gate on it")
        XCTAssertFalse(entry.invalidMember(party: nil))
    }

    func testPendingStashCarriesTheElement() {
        let entry = EntryState()
        let pending = EntryState.Pending(
            exchange: "NJ", serialRcvd: "", memberRcvd: "13")
        XCTAssertFalse(pending.isEmpty)
        entry.restorePending(pending)
        XCTAssertEqual(entry.memberRcvd, "13")

        let memberOnly = EntryState.Pending(exchange: "", serialRcvd: "", memberRcvd: "13")
        XCTAssertFalse(memberOnly.isEmpty, "a copied element alone is worth keeping")
    }

    func testClearForNextContactResetsTheElement() {
        let entry = EntryState()
        entry.memberRcvd = "13"
        entry.clearForNextContact(modeClass: .cw)
        XCTAssertEqual(entry.memberRcvd, "")
    }

    // MARK: Call-history prefill

    /// The roster's number rides `Entry.locations` beside the S/P/C, and the
    /// two channels cannot collide: the number fails the location parse, the
    /// state token fails the digits test.
    func testCandidateSplitsLocationAndMemberFromOneEntry() throws {
        let parsed = CallHistoryFile.parse("""
        !!Order!!,Call,Name,State,Exch1
        W2LJ,LARRY,NJ,13
        """)
        let member = CallHistoryFile.candidate(
            for: "W2LJ", in: parsed, party: try memberParty(), role: .outOfState)
        XCTAssertEqual(member?.exchange, "NJ")
        XCTAssertEqual(member?.member, "13")

        let plain = CallHistoryFile.candidate(
            for: "W2LJ", in: parsed, party: try party(), role: .outOfState)
        XCTAssertNil(plain?.member, "the member channel opens only for member parties")
    }
}

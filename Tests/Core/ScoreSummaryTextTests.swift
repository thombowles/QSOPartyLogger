import XCTest
@testable import QSOPartyLogger

/// Golden strings for the pasteable score summary. Byte-for-byte, because the
/// whole value of the format is that it lines up in somebody's email.
final class ScoreSummaryTextTests: XCTestCase {

    var ksqp: PartyDefinition!
    var skeeter: PartyDefinition!
    var naqpCW: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        skeeter = try XCTUnwrap(PartyCatalog.party(id: "skeeter"))
        naqpCW = try XCTUnwrap(PartyCatalog.party(id: "naqpcw"))
    }

    func log(
        partyID: String = "ksqp",
        callsign: String = "KE5CW",
        qsos: [QSO] = [],
        inState: Bool = true
    ) -> ContestLog {
        var log = ContestLog(partyID: partyID)
        log.station.callsign = callsign
        log.myLocation = inState ? .inState(counties: ["JOH"]) : .outOfState(location: "TX")
        log.qsos = qsos
        return log
    }

    func qso(
        call: String,
        band: Band = .m40,
        modeClass: ModeClass = .cw,
        rawMode: String = "CW",
        theirLoc: String = "TX",
        memberRcvd: String? = nil
    ) -> QSO {
        QSO(
            call: call, band: band, modeClass: modeClass, rawMode: rawMode,
            rstSent: "599", rstRcvd: "599", memberRcvd: memberRcvd,
            myLoc: "JOH", theirLoc: theirLoc
        )
    }

    func summary(_ log: ContestLog, party: PartyDefinition, members: [PartyDefinition] = []) -> String {
        ScoreSummaryText.make(
            log: log, party: party,
            score: ScoreEngine.score(log: log, party: party),
            members: members
        )
    }

    // MARK: A multi-mode party's matrix

    /// KSQP runs all three mode classes, so the matrix carries a column for
    /// each plus the row total — the sidebar's own shape. Byte-for-byte, so a
    /// column that silently shifts is a failing test rather than a crooked
    /// email.
    func testMultiModeMatrixGoldenString() throws {
        let contacts = [
            qso(call: "W1AW", band: .m40, modeClass: .cw, rawMode: "CW", theirLoc: "TX"),
            qso(call: "K2ABC", band: .m40, modeClass: .phone, rawMode: "SSB", theirLoc: "OK"),
            qso(call: "N3DEF", band: .m20, modeClass: .cw, rawMode: "CW", theirLoc: "MO"),
        ]
        let text = summary(log(qsos: contacts), party: ksqp)

        XCTAssertTrue(text.hasPrefix("""
            KE5CW — Kansas QSO Party

             Band  PH  CW  DIG  QSOs
              40m   1   1    0     2
              20m   0   1    0     1
            Total   1   2    0     3

            """), text)
    }

    // MARK: A single-mode party

    /// A CW-only party gets no mode columns: for NAQP CW the CW column and the
    /// QSOs column would carry identical figures under two headings.
    func testSingleModePartyOmitsTheModeColumns() {
        let contacts = [
            qso(call: "W1AW", band: .m40, theirLoc: "TX"),
            qso(call: "K2ABC", band: .m20, theirLoc: "OK"),
        ]
        let text = summary(
            log(partyID: "naqpcw", qsos: contacts, inState: false), party: naqpCW
        )
        XCTAssertTrue(text.contains(" Band  QSOs"), text)
        XCTAssertFalse(text.contains("CW  QSOs"), text)
    }

    // MARK: A member party's three-way split

    /// The Skeeter Hunt's summary email asks for Skeeter / QRP / QRO counts by
    /// name, and the sidebar keeps them on screen — so the paste carries them
    /// under the same labels.
    func testMemberPartyCarriesTheThreeWaySplit() throws {
        let member = try XCTUnwrap(skeeter.memberExchange)
        let contacts = [
            qso(call: "W1AW", theirLoc: "TX", memberRcvd: "13"),
            qso(call: "K2ABC", band: .m20, theirLoc: "OK", memberRcvd: "5W"),
        ]
        let text = summary(log(partyID: "skeeter", qsos: contacts), party: skeeter)
        XCTAssertTrue(text.contains(member.memberPlural), text)
        XCTAssertTrue(text.contains("QRP / QRO"), text)
    }

    // MARK: An empty log

    /// An empty clipboard reads as a failed copy. A log with nothing in it still
    /// says whose it is and that the score is zero.
    func testAnEmptyLogStillProducesAHeaderAndAZeroScore() {
        let text = summary(log(), party: ksqp)
        XCTAssertEqual(text, """
            KE5CW — Kansas QSO Party

             Band  PH  CW  DIG  QSOs
            Total   0   0    0     0

            QSO points    0
            Multipliers   0
            Bonus        +0
            Score         0

            """)
    }

    /// The score block on its own, from a breakdown built by hand — so the
    /// column arithmetic is pinned without also pinning the scoring engine's
    /// answer for some party's rules.
    func testScoreBlockGoldenString() {
        var score = ScoreEngine.ScoreBreakdown()
        score.qsoPoints = 1_240
        score.multiplierKeys = Set(
            ["JOH", "MIA", "AND"].map {
                ScoreEngine.MultKey(multClass: .county, value: $0, scope: "")
            }
        )
        score.bonusPoints = 50
        score.dupeCount = 2

        let text = ScoreSummaryText.make(log: log(), party: ksqp, score: score)
        XCTAssertTrue(text.hasSuffix("""
            QSO points   1,240
            Multipliers      3
            Bonus          +50
            Dupes            2
            Score        3,770

            """), text)
    }

    // MARK: Formatting invariants

    /// The figures are formatted for a fixed locale — `Int.formatted()` follows
    /// the run's own, so a golden test would pass in Kansas and fail in Köln.
    func testLargeFiguresGroupWithCommas() {
        var score = ScoreEngine.ScoreBreakdown()
        score.qsoPoints = 12_345
        let text = ScoreSummaryText.make(log: log(), party: ksqp, score: score)
        XCTAssertTrue(text.contains("12,345"), text)
    }

    func testNoLineShipsTrailingWhitespace() {
        let contacts = [qso(call: "W1AW"), qso(call: "K2ABC", band: .m20)]
        let text = summary(log(qsos: contacts), party: ksqp)
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            XCTAssertEqual(
                String(line), String(line).replacingOccurrences(
                    of: " +$", with: "", options: .regularExpression
                ),
                "trailing space on: '\(line)'"
            )
        }
    }

    /// The dupe line appears only when there are dupes — a summary should not
    /// report a category the log has nothing in.
    func testDupesAppearOnlyWhenThereAreSome() {
        let clean = summary(log(qsos: [qso(call: "W1AW")]), party: ksqp)
        XCTAssertFalse(clean.contains("Dupes"), clean)

        let duped = summary(
            log(qsos: [qso(call: "W1AW"), qso(call: "W1AW")]), party: ksqp
        )
        XCTAssertTrue(duped.contains("Dupes"), duped)
    }
}

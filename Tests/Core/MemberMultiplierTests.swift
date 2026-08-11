import XCTest
@testable import QSOPartyLogger

/// The `member` multiplier class: the worked station's received member
/// number is itself the multiplier, keyed by the raw logged callsign —
/// FOBB's "Working the same Bumblebee on a different band counts as an
/// additional Contact and as an additional Bumblebee Worked."
/// Rules research: docs/research/fobb_rules.md §6.
final class MemberMultiplierTests: XCTestCase {

    /// A minimal member-mult party, decoded rather than constructed.
    func party() throws -> PartyDefinition {
        let json = """
        {
          "schemaVersion": 1, "id": "membertest", "name": "Member Test",
          "cabrilloContest": "TEST", "homeState": "NA", "countyAbbrLength": 2,
          "validBands": ["40m", "20m"],
          "points": {"phone": 3, "cw": 3, "digital": 3},
          "dupeScope": "bandMode",
          "multipliers": {
            "inState":  {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"},
            "outState": {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"}
          },
          "bonuses": [], "counties": [], "hasHomeRegion": false,
          "allowedModes": ["cw"],
          "memberExchange": {
            "term": "Bumblebee number", "shortTerm": "BB #",
            "memberPlural": "Bumblebees",
            "memberPoints": 3, "qrpPoints": 3, "otherPoints": 3,
            "qrpMaxWatts": {"phone": 5, "cw": 5, "digital": 5}
          }
        }
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    var seq: TimeInterval = 0
    func qso(_ call: String, band: Band = .m20, member: String?) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_923_600 + seq),
            call: call, band: band, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599",
            memberSent: "5W", memberRcvd: member,
            myLoc: "TX", theirLoc: "NC"
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "membertest",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "5W"
        )
    }

    /// A received number contributes one member key per band; a power or a
    /// blank element contributes nothing.
    func testOnlyAParsedNumberContributes() throws {
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", member: "7"),      // bee
            qso("K1ABC", member: "5W"),        // power: no key
            qso("AC7A", member: nil),          // blank: no key
        ]), party: try party())
        XCTAssertEqual(score.multiplierKeys.count, 1)
        XCTAssertEqual(score.workedValues(.member), ["W4KAC/BB"])
        XCTAssertEqual(score.memberQSOs, 1)
    }

    /// Per-band scope: the same bee on a second band is a second key — the
    /// case that would fail under a `once` scope.
    func testSameBeeNewBandIsANewMultiplier() throws {
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", band: .m20, member: "7"),
            qso("W4KAC/BB", band: .m40, member: "7"),
        ]), party: try party())
        XCTAssertEqual(score.multiplierKeys.count, 2)
        XCTAssertEqual(score.workedValues(.member), ["W4KAC/BB"])
    }

    /// Same band twice is a dupe — no second key, no second point.
    func testSameBeeSameBandIsADupe() throws {
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", member: "7"),
            qso("W4KAC/BB", member: "7"),
        ]), party: try party())
        XCTAssertEqual(score.dupeCount, 1)
        XCTAssertEqual(score.multiplierKeys.count, 1)
        XCTAssertEqual(score.qsoPoints, 3)
    }

    /// The raw call is the key: /BB and bare forms are distinct values, and
    /// the location contributes nothing when the party wants only members.
    func testRawCallIdentityAndNoLocationKeys() throws {
        let score = ScoreEngine.score(log: log([
            qso("K3JZD/BB", band: .m20, member: "12"),
            qso("K3JZD", band: .m40, member: "12"),
        ]), party: try party())
        XCTAssertEqual(score.workedValues(.member), ["K3JZD/BB", "K3JZD"])
        XCTAssertTrue(score.workedValues(.state).isEmpty,
                      "NC was received but state is not a wanted class")
    }

    /// A party that does not list the class gets no member keys however the
    /// element parses — the wantedClasses gate.
    func testPartiesWithoutTheClassAreUntouched() throws {
        let skeeter = try XCTUnwrap(PartyCatalog.party(id: "skeeter"))
        let contest = ContestLog(
            partyID: "skeeter",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: [qso("W2LJ", member: "13")],
            exchangeMember: "20"
        )
        let score = ScoreEngine.score(log: contest, party: skeeter)
        XCTAssertTrue(score.workedValues(.member).isEmpty)
    }

    /// The NEW MULT badge sees the live member text: a bee not yet worked
    /// on this band is a new multiplier; a bee already worked there, a
    /// power, or a blank is not.
    func testWouldAddMultiplierReadsTheMemberElement() throws {
        let p = try party()
        let contest = log([qso("W4KAC/BB", band: .m20, member: "7")])
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: p, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m20, modeClass: .cw,
            log: contest, party: p, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: p, call: "K1ABC", memberRcvd: "100W"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: p, call: "K1ABC", memberRcvd: nil))
    }
}

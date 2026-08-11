import XCTest
@testable import QSOPartyLogger

/// `MultRule.multiplierFloor` — FOBB's printed "(Defaults to [Total
/// Contacts] = 1 and [Number of Bumblebees] = 1)": the multiplier count
/// that reaches the score never drops below the floor. Default 0 leaves
/// every existing party exactly as it was (max(n, 0) == n).
/// Research: docs/research/fobb_rules.md §8 and OPEN QUESTION 1.
final class MultiplierFloorTests: XCTestCase {

    func party(floor: String) throws -> PartyDefinition {
        let json = """
        {
          "schemaVersion": 1, "id": "floortest", "name": "Floor Test",
          "cabrilloContest": "TEST", "homeState": "NA", "countyAbbrLength": 2,
          "validBands": ["40m", "20m"],
          "points": {"phone": 3, "cw": 3, "digital": 3},
          "dupeScope": "bandMode",
          "multipliers": {
            "inState":  {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"\(floor)},
            "outState": {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"\(floor)}
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
    func qso(_ call: String, member: String?) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_923_600 + seq),
            call: call, band: .m20, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599",
            memberSent: "5W", memberRcvd: member,
            myLoc: "TX", theirLoc: "NC"
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "floortest",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "5W"
        )
    }

    /// Absent from the JSON, the floor is 0 and nothing anywhere moves.
    func testDefaultFloorIsZero() throws {
        let p = try party(floor: "")
        XCTAssertEqual(p.multipliers.inState.multiplierFloor, 0)
    }

    /// Contacts but no member worked: the floor holds the multiplier at 1,
    /// so three contacts score 3 × 3 × 1 = 9 — FOBB's contacts × 1 × 3.
    func testFloorHoldsTheProductUpWithZeroKeys() throws {
        let p = try party(floor: ", \"multiplierFloor\": 1")
        let score = ScoreEngine.score(log: log([
            qso("K1ABC", member: "100W"),
            qso("K2DEF", member: nil),
            qso("K3GHI", member: "5W"),
        ]), party: p)
        XCTAssertTrue(score.multiplierKeys.isEmpty)
        XCTAssertEqual(score.multiplierCount, 1)
        XCTAssertEqual(score.total, 9)
    }

    /// An empty log still totals 0 — qsoPoints is 0 whatever the floor
    /// says (the K4UPG row on the sponsor's calculator).
    func testAnEmptyLogIsStillZero() throws {
        let p = try party(floor: ", \"multiplierFloor\": 1")
        let score = ScoreEngine.score(log: log([]), party: p)
        XCTAssertEqual(score.multiplierCount, 1)
        XCTAssertEqual(score.total, 0)
    }

    /// Once real keys exist the floor is inert.
    func testFloorIsInertOnceKeysExist() throws {
        let p = try party(floor: ", \"multiplierFloor\": 1")
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", member: "7"),
            qso("N7CQR/BB", member: "23"),
        ]), party: p)
        XCTAssertEqual(score.multiplierCount, 2)
        XCTAssertEqual(score.total, 6 * 2)
    }
}

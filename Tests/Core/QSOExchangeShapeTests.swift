// Tests/Core/QSOExchangeShapeTests.swift
import XCTest
@testable import QSOPartyLogger

/// The v2 row: two maps, element id → value, with the typed v1 accessors as
/// views over them. New saves write the maps only; v1 rows decode unchanged.
final class QSOExchangeShapeTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1_788_013_920)

    func testTypedInitFillsTheMapsAndTheViewsReadThemBack() {
        let q = QSO(timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "579", serialSent: 12, serialRcvd: 7,
                    nameSent: "TOM", nameRcvd: "BOB", memberSent: "13", memberRcvd: "5W",
                    myLoc: "TX", theirLoc: "MRN")
        XCTAssertEqual(q.sent, ["rst": "599", "serial": "12", "name": "TOM", "member": "13", "location": "TX"])
        XCTAssertEqual(q.rcvd, ["rst": "579", "serial": "7", "name": "BOB", "member": "5W", "location": "MRN"])
        XCTAssertEqual(q.rstSent, "599"); XCTAssertEqual(q.rstRcvd, "579")
        XCTAssertEqual(q.serialSent, 12); XCTAssertEqual(q.serialRcvd, 7)
        XCTAssertEqual(q.nameSent, "TOM"); XCTAssertEqual(q.nameRcvd, "BOB")
        XCTAssertEqual(q.memberSent, "13"); XCTAssertEqual(q.memberRcvd, "5W")
        XCTAssertEqual(q.myLoc, "TX"); XCTAssertEqual(q.theirLoc, "MRN")
    }

    func testAbsentElementsHaveOneRepresentation() {
        let q = QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "", rstRcvd: "599", nameSent: "", memberRcvd: nil, myLoc: "TX", theirLoc: "MRN")
        XCTAssertNil(q.sent["rst"], "an empty value is not stored")
        XCTAssertNil(q.sent["name"])
        XCTAssertEqual(q.rstSent, "", "the typed view reads an absent report as empty")
        XCTAssertNil(q.nameSent)
        XCTAssertNil(q.serialSent)
        var edited = q
        edited.theirLoc = "LIN"; edited.nameRcvd = "SUE"; edited.serialRcvd = 44
        XCTAssertEqual(edited.rcvd, ["rst": "599", "location": "LIN", "name": "SUE", "serial": "44"])
        edited.nameRcvd = nil; edited.rstRcvd = ""; edited.rcvd["zone"] = ""
        XCTAssertEqual(edited.rcvd, ["location": "LIN", "serial": "44"], "setters and direct writes both drop empties")
    }

    func testMapInitAndAnyElementId() {
        let q = QSO(call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW",
                    sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14", "": "x"])
        XCTAssertEqual(q.sent["zone"], "4")
        XCTAssertEqual(q.rcvd, ["rst": "599", "zone": "14"], "an empty id is not an element")
        XCTAssertEqual(q.myLoc, "", "no location element — the view is empty, not a crash")
    }

    func testEncodesTheMapsOnlyAndRoundTrips() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.qsos = [QSO(timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                        rstSent: "599", rstRcvd: "599", serialSent: 3, myLoc: "TX", theirLoc: "MRN")]
        let data = try log.encoded()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let row = try XCTUnwrap((json["qsos"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["sent"] as? [String: String], ["rst": "599", "serial": "3", "location": "TX"])
        XCTAssertEqual(row["rcvd"] as? [String: String], ["rst": "599", "location": "MRN"])
        for legacy in ["rstSent", "rstRcvd", "serialSent", "serialRcvd", "nameSent", "nameRcvd", "memberSent", "memberRcvd", "myLoc", "theirLoc"] {
            XCTAssertNil(row[legacy], "\(legacy) is a v1 key and is no longer written")
        }
        XCTAssertEqual(try ContestLog.decode(from: data), log)
    }

    /// A row exactly as every build before this one wrote it.
    func testDecodesAV1Row() throws {
        let v1 = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},
         "operatingMode":"S&P","setupCompleted":true,"exchangeName":"","exchangeMember":"","entryClassID":"","usedSpots":false,"myPotaRefs":[],
         "messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW","freqKHz":14042,
                  "rstSent":"599","rstRcvd":"579","serialSent":2,"nameRcvd":"BOB","memberSent":"","myLoc":"TX","theirLoc":"MRN"}]}
        """
        let log = try ContestLog.decode(from: Data(v1.utf8))
        let q = try XCTUnwrap(log.qsos.first)
        XCTAssertEqual(q.sent, ["rst": "599", "serial": "2", "location": "TX"], "an empty v1 member is absent")
        XCTAssertEqual(q.rcvd, ["rst": "579", "name": "BOB", "location": "MRN"])
        XCTAssertEqual(q.rstRcvd, "579"); XCTAssertEqual(q.serialSent, 2); XCTAssertNil(q.serialRcvd)
        XCTAssertEqual(q.theirLoc, "MRN"); XCTAssertEqual(q.freqKHz, 14042)
    }

    func testAV2RowWithOnlySentDecodes() throws {
        let v2 = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},"operatingMode":"S&P","setupCompleted":true,"messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW",
                  "sent":{"rst":"599","location":"TX"}}]}
        """
        let log = try ContestLog.decode(from: Data(v2.utf8))
        let q = try XCTUnwrap(log.qsos.first)
        XCTAssertEqual(q.sent, ["rst": "599", "location": "TX"])
        XCTAssertEqual(q.rcvd, [:], "no rcvd key at all — the v2 branch still fills it in as empty")
        XCTAssertEqual(q.theirLoc, "")
    }

    func testV2ValuesAreCompactedOnDecode() throws {
        let v2 = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},"operatingMode":"S&P","setupCompleted":true,"messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW",
                  "sent":{"rst":"599","name":"","":"x"},"rcvd":{"rst":"","location":"MRN"}}]}
        """
        let log = try ContestLog.decode(from: Data(v2.utf8))
        let q = try XCTUnwrap(log.qsos.first)
        XCTAssertEqual(q.sent, ["rst": "599"], "empty value, empty id, and empty-value-with-empty-id all drop")
        XCTAssertEqual(q.rcvd, ["location": "MRN"])
    }

    func testV2KeysWinOverStrayV1Keys() throws {
        let v2 = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},"operatingMode":"S&P","setupCompleted":true,"messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW",
                  "sent":{"rst":"599","location":"TX"},"rcvd":{"rst":"579","location":"MRN"},
                  "rstSent":"111","myLoc":"ZZ"}]}
        """
        let log = try ContestLog.decode(from: Data(v2.utf8))
        let q = try XCTUnwrap(log.qsos.first)
        XCTAssertEqual(q.rstSent, "599", "sent/rcvd present means the legacy container is never consulted")
        XCTAssertEqual(q.myLoc, "TX")
    }

    func testAV1RowMissingARequiredKeyStillFails() {
        let broken = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},
         "operatingMode":"S&P","setupCompleted":true,"messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW",
                  "rstSent":"599","myLoc":"TX","theirLoc":"MRN"}]}
        """
        XCTAssertThrowsError(try ContestLog.decode(from: Data(broken.utf8)), "rstRcvd was required in v1 and stays required for a v1 row") { error in
            guard case DecodingError.keyNotFound(let key, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(key.stringValue, "rstRcvd")
        }
    }

    func testEmptyParkListsDecodeAsNil() throws {
        let v2 = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},"operatingMode":"S&P","setupCompleted":true,"messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW",
                  "sent":{"rst":"599","location":"TX"},"rcvd":{"rst":"579","location":"MRN"},
                  "myPotaRefs":[],"theirPotaRefs":[]}]}
        """
        let log = try ContestLog.decode(from: Data(v2.utf8))
        let q = try XCTUnwrap(log.qsos.first)
        XCTAssertNil(q.myPotaRefs, "the inits treat an empty list as absent; decode must match")
        XCTAssertNil(q.theirPotaRefs)
    }
}

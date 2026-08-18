// Tests/Core/ContestLogShapeTests.swift
import XCTest
@testable import QSOPartyLogger

final class ContestLogShapeTests: XCTestCase {

    func testMyLocationIsAViewOverSideAndSentExchange() {
        var log = ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["MRN", "CHS"]), exchangeName: "TOM", exchangeMember: "13")
        XCTAssertEqual(log.sideID, "inside")
        XCTAssertEqual(log.sentExchange, ["location": ["MRN", "CHS"], "name": ["TOM"], "member": ["13"]])
        XCTAssertEqual(log.myLocation, .inState(counties: ["MRN", "CHS"]))
        XCTAssertEqual(log.exchangeName, "TOM"); XCTAssertEqual(log.exchangeMember, "13")
        log.myLocation = .outOfState(location: "TX")
        XCTAssertEqual(log.sideID, "outside")
        XCTAssertEqual(log.sentExchange["location"], ["TX"])
        log.exchangeName = ""; log.exchangeMember = ""
        XCTAssertNil(log.sentExchange["name"]); XCTAssertNil(log.sentExchange["member"])
        log.myLocation = .outOfState(location: "")
        XCTAssertNil(log.sentExchange["location"], "an empty location is absent")
        XCTAssertEqual(log.myLocation, .outOfState(location: ""), "and reads back as the empty out-of-state it was")
        log.sideID = "all"; log.sentExchange = ["zone": ["4"], "rst": [""]]
        XCTAssertEqual(log.sentExchange, ["zone": ["4"]], "empties are dropped on direct writes too")
        XCTAssertEqual(log.myLocation, .outOfState(location: ""), "a side that is not `inside` reads as out-of-state")
    }

    func testDerivedOperatingModeFollowsTheSide() {
        XCTAssertEqual(ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["MRN"])).derivedOperatingMode, .run)
        XCTAssertEqual(ContestLog(partyID: "ksqp", myLocation: .outOfState(location: "TX")).derivedOperatingMode, .searchPounce)
    }

    func testEncodesV2KeysOnlyAndRoundTrips() throws {
        var log = ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["MRN"]), exchangeName: "TOM")
        log.station.callsign = "KE5CW"
        log.selectedObjectives = ["1o", "3o"]
        log.declaredBonuses = ["emergencyPower": 3]
        let data = try log.encoded()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        XCTAssertEqual(json["sideID"] as? String, "inside")
        XCTAssertEqual(json["sentExchange"] as? [String: [String]], ["location": ["MRN"], "name": ["TOM"]])
        XCTAssertEqual(json["selectedObjectives"] as? [String], ["1o", "3o"])
        XCTAssertEqual(json["declaredBonuses"] as? [String: Int], ["emergencyPower": 3])
        for legacy in ["myLocation", "exchangeName", "exchangeMember"] { XCTAssertNil(json[legacy], "\(legacy) is a v1 key") }
        XCTAssertEqual(try ContestLog.decode(from: data), log)
        // Empty objective/bonus collections write no key at all.
        var plain = log; plain.selectedObjectives = []; plain.declaredBonuses = [:]
        let plainJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: try plain.encoded()) as? [String: Any])
        XCTAssertNil(plainJSON["selectedObjectives"]); XCTAssertNil(plainJSON["declaredBonuses"])
    }

    func testDecodesAV1Document() throws {
        let v1 = """
        {"schemaVersion":1,"partyID":"naqpcw","station":{"callsign":"KE5CW","categoryPower":"LOW"},
         "myLocation":{"outOfState":{"location":"TX"}},"exchangeName":"TOM","exchangeMember":"",
         "operatingMode":"Run","setupCompleted":true,"entryClassID":"","usedSpots":true,"myPotaRefs":["US-3315"],
         "qsos":[]}
        """
        let log = try ContestLog.decode(from: Data(v1.utf8))
        XCTAssertEqual(log.schemaVersion, 2, "the in-memory log is always the current shape")
        XCTAssertEqual(log.sideID, "outside")
        XCTAssertEqual(log.sentExchange, ["location": ["TX"], "name": ["TOM"]])
        XCTAssertEqual(log.myLocation, .outOfState(location: "TX"))
        XCTAssertEqual(log.exchangeName, "TOM"); XCTAssertEqual(log.exchangeMember, "")
        XCTAssertEqual(log.operatingMode, .run); XCTAssertTrue(log.usedSpots); XCTAssertEqual(log.myPotaRefs, ["US-3315"])
        XCTAssertEqual(log.selectedObjectives, []); XCTAssertEqual(log.declaredBonuses, [:])
        let inside = try ContestLog.decode(from: Data("""
        {"schemaVersion":1,"partyID":"ksqp","station":{},"myLocation":{"inState":{"counties":["MRN","CHS"]}},"qsos":[]}
        """.utf8))
        XCTAssertEqual(inside.sideID, "inside"); XCTAssertEqual(inside.sentExchange["location"], ["MRN", "CHS"])
        XCTAssertEqual(inside.operatingMode, .run, "derived from the side, as before from the location")
    }

    func testADocumentWithNeitherSideNorLocationIsRefused() {
        XCTAssertThrowsError(try ContestLog.decode(from: Data("""
        {"schemaVersion":2,"partyID":"ksqp","station":{},"qsos":[]}
        """.utf8))) { error in
            guard case let DecodingError.keyNotFound(key, _) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(key.stringValue, "myLocation")
        }
    }

    func testCategoryValues() {
        var log = ContestLog(partyID: "cqwwcw")
        log.station.categoryOperator = .singleOp; log.station.categoryPower = .high
        log.station.categoryOverlay = "CLASSIC"; log.station.categoryBand = "20M"
        log.qsos = [QSO(call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW", sent: [:], rcvd: [:])]
        XCTAssertEqual(log.categoryValues, ["operator": "SINGLE-OP", "assisted": "NON-ASSISTED", "power": "HIGH", "station": "FIXED",
                                            "transmitter": "ONE", "band": "20M", "mode": "CW", "overlay": "CLASSIC", "time": ""])
        XCTAssertTrue(OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 60, appliesTo: ["overlay": "CLASSIC"]).applies(to: log.categoryValues))
        XCTAssertFalse(OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 60, appliesTo: ["overlay": "ROOKIE"]).applies(to: log.categoryValues))
    }

    func testStationProfileAdditionsDecodeWithDefaultsAndEncodeOnlyWhenSet() throws {
        let old = try JSONDecoder().decode(StationProfile.self, from: Data(#"{"callsign":"KE5CW"}"#.utf8))
        XCTAssertNil(old.categoryBand); XCTAssertNil(old.categoryOverlay); XCTAssertNil(old.categoryTime)
        XCTAssertEqual(old.exchangeDefaults, [:])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(old)) as? [String: Any])
        for key in ["categoryBand", "categoryOverlay", "categoryTime", "exchangeDefaults"] { XCTAssertNil(json[key], "\(key) is written only when set") }
        var s = old
        s.categoryOverlay = "classic"; s.exchangeDefaults = ["section": "ntx", "zone": "4"]
        let n = s.normalized()
        XCTAssertEqual(n.categoryOverlay, "CLASSIC"); XCTAssertEqual(n.exchangeDefaults, ["section": "NTX", "zone": "4"])
        let back = try JSONDecoder().decode(StationProfile.self, from: try JSONEncoder().encode(n))
        XCTAssertEqual(back, n)
    }

    func testANewerSchemaIsRefused() {
        XCTAssertThrowsError(try ContestLog.decode(from: Data("""
        {"schemaVersion":3,"partyID":"ksqp","station":{},"sideID":"all","sentExchange":{},"qsos":[]}
        """.utf8))) { error in
            guard case DecodingError.dataCorrupted = error else { return XCTFail("\(error)") }
        }
    }

    func testUnfinishedV1SetupsRoundTrip() throws {
        let inside = try ContestLog.decode(from: Data("""
        {"schemaVersion":1,"partyID":"ksqp","station":{},"myLocation":{"inState":{"counties":[]}},"qsos":[]}
        """.utf8))
        XCTAssertEqual(inside.myLocation, .inState(counties: []))
        XCTAssertEqual(inside.sideID, "inside")
        XCTAssertEqual(inside.sentExchange, [:])
        XCTAssertEqual(try ContestLog.decode(from: try inside.encoded()), inside)

        let outside = try ContestLog.decode(from: Data("""
        {"schemaVersion":1,"partyID":"ksqp","station":{},"myLocation":{"outOfState":{"location":""}},"qsos":[]}
        """.utf8))
        XCTAssertEqual(outside.myLocation, .outOfState(location: ""))
        XCTAssertEqual(outside.sideID, "outside")
        XCTAssertEqual(outside.sentExchange, [:])
        XCTAssertEqual(try ContestLog.decode(from: try outside.encoded()), outside)
    }

    func testStationProfileNormalizesEmptyAdditionsToAbsent() throws {
        var s = StationProfile()
        s.categoryOverlay = ""
        s.categoryBand = " 20m "
        s.exchangeDefaults = ["section": "", "zone": "4"]
        let n = s.normalized()
        XCTAssertNil(n.categoryOverlay)
        XCTAssertEqual(n.categoryBand, "20M")
        XCTAssertEqual(n.exchangeDefaults, ["zone": "4"])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(n)) as? [String: Any])
        XCTAssertNil(json["categoryOverlay"])
        XCTAssertEqual(json["categoryBand"] as? String, "20M")
    }
}

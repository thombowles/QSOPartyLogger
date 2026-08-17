import XCTest
@testable import QSOPartyLogger

final class ExchangeElementTests: XCTestCase {
    func testDefaultsByKind() {
        let rst = ExchangeElement(id: "rst", kind: .rst, sentBy: ["all": .init()])
        XCTAssertEqual(rst.label, "RST")
        XCTAssertEqual(rst.cabrilloWidth, 3)
        XCTAssertFalse(rst.fixed)
        XCTAssertTrue(rst.required)
        let zone = ExchangeElement(id: "zone", kind: .cqZone, sentBy: ["all": .init()], fixed: true)
        XCTAssertEqual(zone.cabrilloWidth, 6)
        XCTAssertEqual(zone.label, "Zone")
        XCTAssertEqual(ExchangeElement(id: "precedence", kind: .precedence, sentBy: [:], letters: ["Q","A","B","U","M","S"]).cabrilloWidth, 1)
        XCTAssertEqual(ExchangeElement(id: "check", kind: .check, sentBy: [:]).cabrilloWidth, 2)
    }

    func testDecodesTheSpecShape() throws {
        let json = """
        {"id":"location","kind":"token","label":"County/State",
         "sentBy":{"inside":{"sets":["counties"],"multi":{"max":2}},
                   "outside":{"sets":["states","provinces","dxToken"]}},
         "fixed":true,"cabrilloWidth":6,"prefill":["callHistory","spot"]}
        """
        let e = try JSONDecoder().decode(ExchangeElement.self, from: Data(json.utf8))
        XCTAssertEqual(e.kind, .token)
        XCTAssertEqual(e.sentBy["inside"]?.sets, ["counties"])
        XCTAssertEqual(e.sentBy["inside"]?.multi?.max, 2)
        XCTAssertNil(e.sentBy["outside"]?.multi)
        XCTAssertEqual(e.prefill, [.callHistory, .spot])
        XCTAssertEqual(e.setsSent(by: ["inside", "outside"]), ["counties", "states", "provinces", "dxToken"])
        XCTAssertTrue(e.fixed)
    }

    func testDerivationTableFirstMatchWins() throws {
        let json = """
        {"id":"precedence","kind":"precedence","letters":["Q","A","B","U","M","S"],"sentBy":{"wve":{}},"fixed":true,
         "derived":{"kind":"categoryTable","table":[
           {"when":{"operator":"SINGLE-OP","assisted":"NON-ASSISTED","power":"QRP"},"value":"Q"},
           {"when":{"operator":"SINGLE-OP","assisted":"NON-ASSISTED","power":"LOW"},"value":"A"},
           {"when":{"operator":"SINGLE-OP","assisted":"NON-ASSISTED","power":"HIGH"},"value":"B"},
           {"when":{"operator":"SINGLE-OP","assisted":"ASSISTED"},"value":"U"},
           {"when":{"operator":"MULTI-OP","station":"SCHOOL"},"value":"S"},
           {"when":{"operator":"MULTI-OP"},"value":"M"}]}}
        """
        let e = try JSONDecoder().decode(ExchangeElement.self, from: Data(json.utf8))
        let d = try XCTUnwrap(e.derived)
        XCTAssertEqual(d.value(for: ["operator": "SINGLE-OP", "assisted": "NON-ASSISTED", "power": "LOW"]), "A")
        XCTAssertEqual(d.value(for: ["operator": "SINGLE-OP", "assisted": "ASSISTED", "power": "QRP"]), "U")
        XCTAssertEqual(d.value(for: ["operator": "MULTI-OP", "station": "SCHOOL"]), "S")
        XCTAssertEqual(d.value(for: ["operator": "MULTI-OP", "station": "FIXED"]), "M")
        XCTAssertNil(d.value(for: ["operator": "CHECKLOG"]))
    }

    func testMemberSpecRoundTrips() throws {
        let m = MemberSpec(term: "Skeeter number", shortTerm: "Skeeter #", memberPlural: "Skeeters",
                           qrpMaxWatts: .init(phone: 10, cw: 5, digital: 5))
        let e = ExchangeElement(id: "member", kind: .memberOrPower, sentBy: ["all": .init()], fixed: true, member: m)
        let back = try JSONDecoder().decode(ExchangeElement.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back, e)
        XCTAssertEqual(back.member?.qrpMaxWatts.limit(for: .phone), 10)
    }
}

import XCTest
@testable import QSOPartyLogger

final class MultiplierClassTests: XCTestCase {
    func testDecodesTheCQWWClasses() throws {
        let json = """
        [{"id":"zone","term":"zone","resolvers":[{"kind":"cqZone","from":"received"}],
          "counting":{"all":"perBand"},"roster":"cqZones","layout":"zoneGrid"},
         {"id":"country","term":"country","termPlural":"countries",
          "resolvers":[{"kind":"dxccEntity","from":"callsign","list":"arrlPlusWAE","unlessSuffix":["MM"]}],
          "counting":{"all":"perBand"},"layout":"workedOnly"}]
        """
        let classes = try JSONDecoder().decode([MultiplierClass].self, from: Data(json.utf8))
        XCTAssertEqual(classes[0].termPlural, "zones")               // default: term + "s"
        XCTAssertEqual(classes[0].counting["all"], .perBand)
        XCTAssertEqual(classes[0].resolvers[0].kind, .cqZone)
        XCTAssertEqual(classes[1].resolvers[0].list, .arrlPlusWAE)
        XCTAssertEqual(classes[1].resolvers[0].unlessSuffix, ["MM"])
        XCTAssertTrue(classes[1].resolvers[0].countEntities)          // default true
        XCTAssertEqual(classes[1].layout, .workedOnly)
        XCTAssertNil(classes[1].caps)
    }

    func testResolverAppliesToSideAndSuffix() {
        let r = Resolver(kind: .receivedToken, element: "location", set: "counties", mapTo: "group", sides: ["inside"])
        XCTAssertTrue(r.applies(side: "inside", call: "K5ABC"))
        XCTAssertFalse(r.applies(side: "outside", call: "K5ABC"))
        let mm = Resolver(kind: .dxccEntity, from: .callsign, unlessSuffix: ["MM", "AM"])
        XCTAssertTrue(mm.applies(side: "all", call: "PA0AAA"))
        XCTAssertFalse(mm.applies(side: "all", call: "PA0AAA/MM"))
        XCTAssertFalse(mm.applies(side: "all", call: "K5ABC/am"))
    }

    func testCountsForSide() {
        let c = MultiplierClass(id: "county", term: "county", termPlural: "counties",
                                resolvers: [Resolver(kind: .receivedToken, element: "location", set: "counties")],
                                counting: ["outside": .perBand], roster: "counties", layout: .groupedTokens)
        XCTAssertEqual(c.scope(for: "outside"), .perBand)
        XCTAssertNil(c.scope(for: "inside"))
    }
}

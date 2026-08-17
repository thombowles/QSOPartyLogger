import XCTest
@testable import QSOPartyLogger

final class TokenSetTests: XCTestCase {
    func testCanonicalFoldsCaseAndAliases() {
        let set = TokenSet(id: "states", term: "state", termPlural: "states",
                           tokens: [.init(abbr: "MD"), .init(abbr: "TX")],
                           aliases: ["DC": "MD"])
        XCTAssertEqual(set.canonical("tx"), "TX")
        XCTAssertEqual(set.canonical("dc"), "MD")
        XCTAssertNil(set.canonical("ZZ"))
        XCTAssertTrue(set.accepts("DC"))
        XCTAssertEqual(set.acceptedTokens, ["MD", "TX", "DC"])
    }

    func testUSStatesHasFiftyPlusDC() {
        XCTAssertEqual(TokenSet.usStates.tokens.count, 51)
        XCTAssertTrue(TokenSet.usStates.accepts("DC"))
        XCTAssertTrue(TokenSet.usStates.accepts("HI"))
        XCTAssertEqual(TokenSet.usStates.term, "state")
    }

    func testProvincesAreTheThirteen() {
        XCTAssertEqual(Set(TokenSet.provinces.tokens.map(\.abbr)), MultClass.canadianProvinces)
    }

    func testZoneSetsEnumerateOneToFortyAndNinety() {
        XCTAssertEqual(TokenSet.cqZones.tokens.first?.abbr, "1")
        XCTAssertEqual(TokenSet.cqZones.tokens.last?.abbr, "40")
        XCTAssertEqual(TokenSet.ituZones.tokens.count, 90)
        XCTAssertEqual(TokenSet.cqZones.canonical("05"), "5")
    }

    func testDXTokenSet() {
        XCTAssertEqual(TokenSet.dxToken.acceptedTokens, ["DX"])
    }

    func testBuiltInLookup() {
        XCTAssertNotNil(TokenSet.builtIn(id: "usStates"))
        XCTAssertNil(TokenSet.builtIn(id: "counties"))
    }

    func testTokenGroupsSurviveJSON() throws {
        let set = TokenSet(id: "counties", term: "county", termPlural: "counties",
                           tokens: [.init(abbr: "ADA", name: "Ada", group: "ID")])
        let data = try JSONEncoder().encode(set)
        let back = try JSONDecoder().decode(TokenSet.self, from: data)
        XCTAssertEqual(back, set)
        XCTAssertEqual(back.tokens[0].group, "ID")
    }
}

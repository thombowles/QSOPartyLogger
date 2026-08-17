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
        XCTAssertEqual(TokenSet.builtIn(id: "usStates"), TokenSet.usStates)
        XCTAssertEqual(TokenSet.builtIn(id: "provinces"), TokenSet.provinces)
        XCTAssertEqual(TokenSet.builtIn(id: "cqZones"), TokenSet.cqZones)
        XCTAssertEqual(TokenSet.builtIn(id: "ituZones"), TokenSet.ituZones)
        XCTAssertEqual(TokenSet.builtIn(id: "dxToken"), TokenSet.dxToken)
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

    func testDecodeUppercasesAbbrsAndAliases() throws {
        let json = """
        {"id":"x","term":"t","termPlural":"ts","tokens":[{"abbr":"md"}],"aliases":{"dc":"md"}}
        """
        let set = try JSONDecoder().decode(TokenSet.self, from: Data(json.utf8))
        XCTAssertEqual(set.canonical("MD"), "MD")
        XCTAssertEqual(set.canonical("dc"), "MD")
        XCTAssertEqual(set.token(for: "md")?.abbr, "MD")
    }

    func testAliasCollisionKeepsTheFirstAndDoesNotTrap() {
        let set = TokenSet(id: "x", term: "t", termPlural: "ts",
                           tokens: [.init(abbr: "MD"), .init(abbr: "VA")],
                           aliases: ["Dc": "MD", "DC": "VA"])
        XCTAssertEqual(set.aliases.count, 1)
        guard let resolved = set.canonical("DC") else {
            return XCTFail("DC should resolve to whichever of MD/VA the collision kept")
        }
        XCTAssertTrue(["MD", "VA"].contains(resolved))
    }

    func testValidate() {
        let duplicate = TokenSet(id: "x", term: "t", termPlural: "ts",
                                 tokens: [.init(abbr: "MD"), .init(abbr: "MD")])
        XCTAssertThrowsError(try duplicate.validate()) { error in
            XCTAssertEqual(error as? TokenSetError, .duplicateAbbreviation("MD"))
        }

        let missingTarget = TokenSet(id: "x", term: "t", termPlural: "ts",
                                     tokens: [.init(abbr: "MD")],
                                     aliases: ["DC": "XX"])
        XCTAssertThrowsError(try missingTarget.validate()) { error in
            XCTAssertEqual(error as? TokenSetError, .aliasTargetMissing("DC", "XX"))
        }

        let shadowing = TokenSet(id: "x", term: "t", termPlural: "ts",
                                 tokens: [.init(abbr: "MD"), .init(abbr: "VA")],
                                 aliases: ["MD": "VA"])
        XCTAssertThrowsError(try shadowing.validate()) { error in
            XCTAssertEqual(error as? TokenSetError, .aliasShadowsToken("MD"))
        }

        XCTAssertNoThrow(try TokenSet.usStates.validate())
        XCTAssertNoThrow(try TokenSet.provinces.validate())
        XCTAssertNoThrow(try TokenSet.cqZones.validate())
        XCTAssertNoThrow(try TokenSet.ituZones.validate())
        XCTAssertNoThrow(try TokenSet.dxToken.validate())
    }

    func testEncodeDoesNotEmitDerivedFields() throws {
        let set = TokenSet(id: "x", term: "t", termPlural: "ts", tokens: [.init(abbr: "MD")])
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(set)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?.keys.sorted(), ["aliases", "id", "term", "termPlural", "tokens"])
    }
}

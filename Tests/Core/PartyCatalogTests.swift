import XCTest
@testable import QSOPartyLogger

final class PartyCatalogTests: XCTestCase {

    func loadedParty(_ id: String) throws -> PartyDefinition {
        let party = PartyCatalog.party(id: id)
        return try XCTUnwrap(party, "bundled party '\(id)' should load")
    }

    func testBundledPartiesLoad() throws {
        let parties = PartyCatalog.loadBundled()
        XCTAssertEqual(Set(parties.map(\.id)), ["alqp", "hqp", "ksqp", "mdc", "tqp"])
    }

    func testKSQPCountyData() throws {
        let ksqp = try loadedParty("ksqp")
        XCTAssertEqual(ksqp.counties.count, 105)
        XCTAssertEqual(Set(ksqp.counties.map(\.abbr)).count, 105, "abbrs unique")
        XCTAssertEqual(ksqp.county(for: "WYA")?.name, "Wyandotte")
        XCTAssertEqual(ksqp.county(for: "MCP")?.name, "McPherson")
        XCTAssertEqual(ksqp.county(for: "mrn")?.name, "Marion")
        XCTAssertEqual(ksqp.countyAbbrLength, 3)
        XCTAssertEqual(ksqp.homeState, "KS")
        XCTAssertEqual(ksqp.cabrilloContest, "KS-QSO-PARTY")
        XCTAssertEqual(ksqp.points.points(for: .phone), 2)
        XCTAssertEqual(ksqp.points.points(for: .cw), 3)
        XCTAssertEqual(ksqp.points.points(for: .digital), 3)
        XCTAssertEqual(ksqp.oneByOne?.words.count, 4)
        XCTAssertEqual(ksqp.oneByOne?.wildcard, "KS0KS")
        XCTAssertEqual(ksqp.bonuses, [.workStation(call: "KS0KS", points: 100, scope: .once)])
        XCTAssertTrue(ksqp.multipliers.inState.homeStateCountsViaCounty)
        XCTAssertFalse(ksqp.validBands.contains(.m160), "KSQP has no 160m")
    }

    func testTQPCountyData() throws {
        let tqp = try loadedParty("tqp")
        XCTAssertEqual(tqp.counties.count, 254)
        XCTAssertEqual(Set(tqp.counties.map(\.abbr)).count, 254)
        XCTAssertEqual(tqp.county(for: "DSMI")?.name, "Deaf Smith")
        XCTAssertEqual(tqp.county(for: "EPAS")?.name, "El Paso")
        XCTAssertEqual(tqp.county(for: "TGRE")?.name, "Tom Green")
        XCTAssertEqual(tqp.county(for: "BEE")?.name, "Bee")
        XCTAssertEqual(tqp.county(for: "HARR")?.name, "Harris")
        XCTAssertEqual(tqp.county(for: "HRSN")?.name, "Harrison")
        XCTAssertEqual(tqp.countyAbbrLength, 4)
        XCTAssertEqual(tqp.bonuses, [.mobileCountyCount(per: 5, points: 500)])
    }

    func testOutStateTokensExcludeHomeState() throws {
        let ksqp = try loadedParty("ksqp")
        XCTAssertFalse(ksqp.validOutStateTokens.contains("KS"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("TX"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("ON"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("DX"))
        XCTAssertTrue(ksqp.validOutStateTokens.contains("DC"))
        XCTAssertEqual(MultClass.canadianProvinces.count, 13)
        XCTAssertEqual(MultClass.usStates.count, 50)
    }

    func testDuplicateAbbreviationRejected() throws {
        let json = """
        {"schemaVersion":1,"id":"bad","name":"Bad","cabrilloContest":"BAD","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],
        "counties":[{"abbr":"ALL","name":"Allen"},{"abbr":"ALL","name":"Other"}]}
        """
        XCTAssertThrowsError(try PartyCatalog.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? PartyValidationError, .duplicateAbbreviation("ALL"))
        }
    }

    func testBonusRuleRoundTrip() throws {
        let rules: [BonusRule] = [
            .workStation(call: "KS0KS", points: 100, scope: .once),
            .mobileCountyCount(per: 5, points: 500),
        ]
        let data = try JSONEncoder().encode(rules)
        let decoded = try JSONDecoder().decode([BonusRule].self, from: data)
        XCTAssertEqual(decoded, rules)
    }
}

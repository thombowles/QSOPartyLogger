import XCTest
@testable import QSOPartyLogger

final class CTYTableTests: XCTestCase {
    // Synthetic file: deterministic mechanics.
    private let csv = """
    K,United States,291,NA,5,8,37.53,91.67,5.0,K W N AA AB K5(4)[7] W6(3)[6] =K1ABC(5)[8] =W6XYZ/7(3)[6];
    VE,Canada,1,NA,5,9,44.35,78.75,5.0,VE VA VO VY VE3(4)[4] =VER20260814;
    *IT9,Sicily,248,EU,15,28,37.50,-14.00,-1.0,IT9 IW9 =IT9/K5ZD;
    DL,Fed. Rep. of Germany,230,EU,14,28,51.00,-10.00,-1.0,DA DB DC DD DL;
    X9,Empty Code Land,,AS,26,50,0.0,0.0,0.0,X9;
    """

    func testParsesFieldsOverridesExactCallsAndWAE() throws {
        let t = try CTYTable.parse(csv: csv)
        XCTAssertEqual(t.entities.count, 5)
        XCTAssertEqual(t.release, "VER20260814")
        let k5 = try XCTUnwrap(t.match(callsign: "K5ABC"))
        XCTAssertEqual(k5.entity.entityCode, 291)
        XCTAssertEqual(k5.entity.name, "United States")
        XCTAssertEqual(k5.continent, "NA")
        XCTAssertEqual(k5.cqZone, 4)      // K5(4)[7] — the longest listed prefix wins
        XCTAssertEqual(k5.ituZone, 7)
        XCTAssertFalse(k5.exact)
        XCTAssertEqual(try XCTUnwrap(t.match(callsign: "KE5CW")).cqZone, 5)   // no KE5 rule in this synthetic file → entity default
        let w1 = try XCTUnwrap(t.match(callsign: "W1AW"))
        XCTAssertEqual(w1.cqZone, 5)       // entity default
        XCTAssertEqual(w1.ituZone, 8)
        let exact = try XCTUnwrap(t.match(callsign: "k1abc"))
        XCTAssertTrue(exact.exact)
        XCTAssertEqual(exact.cqZone, 5)
        XCTAssertEqual(try XCTUnwrap(t.match(callsign: "W6XYZ/7")).cqZone, 3)   // exact call with a slash
        let ve3 = try XCTUnwrap(t.match(callsign: "VE3XYZ"))
        XCTAssertEqual(ve3.entity.entityCode, 1)
        XCTAssertEqual(ve3.cqZone, 4)
        let it9 = try XCTUnwrap(t.match(callsign: "IT9ABC"))
        XCTAssertTrue(it9.entity.waeOnly)
        XCTAssertEqual(it9.entity.entityCode, 248)
        XCTAssertEqual(it9.entity.name, "Sicily")
        XCTAssertEqual(it9.entity.primaryPrefix, "IT9")
        XCTAssertEqual(try XCTUnwrap(t.match(callsign: "DL1AA/P")).entity.entityCode, 230)   // portable suffix stripped
        XCTAssertNil(t.match(callsign: "X9AA")?.entity.entityCode)   // empty code field: Int("") fails to parse — the defensive branch
        XCTAssertNil(t.match(callsign: "ZZ9ZZ"))
        XCTAssertNil(t.match(callsign: ""))
    }

    func testEntityNameMayContainACommaAndDXCCPrefixLookup() throws {
        let t = try CTYTable.parse(csv: "VP2E,Anguilla, The Valley,12,NA,8,11,18.22,63.07,4.0,VP2E;\n")
        XCTAssertEqual(t.entities.first?.name, "Anguilla, The Valley")
        XCTAssertEqual(t.entity(forPrimaryPrefix: "VP2E")?.entityCode, 12)
    }

    // Bundled file: facts that do not move between releases.
    func testBundledFileLoadsAndResolvesWellKnownCalls() throws {
        let t = try XCTUnwrap(CTYTable.load(bundle: .main))
        XCTAssertGreaterThanOrEqual(t.entities.filter { !$0.waeOnly }.count, 340,
                                   "non-WAE entity count — a change here is a cty/DXCC data refresh, not a code regression")
        XCTAssertNotNil(t.release?.range(of: #"^VER\d{8}$"#, options: .regularExpression))
        XCTAssertEqual(t.match(callsign: "KE5CW")?.entity.entityCode, 291)
        XCTAssertEqual(t.match(callsign: "KE5CW")?.continent, "NA")
        XCTAssertEqual(t.match(callsign: "VE3XYZ")?.entity.entityCode, 1)
        XCTAssertEqual(t.match(callsign: "DL1AA")?.entity.entityCode, 230)
        XCTAssertEqual(t.match(callsign: "DL1AA")?.continent, "EU")
        XCTAssertEqual(t.match(callsign: "JA1AA")?.entity.entityCode, 339)
        XCTAssertEqual(t.match(callsign: "G3AAA")?.entity.entityCode, 223)
        XCTAssertEqual(t.match(callsign: "VK2AA")?.continent, "OC")
        XCTAssertTrue(t.entities.contains { $0.waeOnly && $0.primaryPrefix == "IT9" })
        XCTAssertEqual(t.match(callsign: "IG9ABC")?.entity.entityCode, 248)
        XCTAssertEqual(t.match(callsign: "IG9ABC")?.entity.waeOnly, true)
    }

    func testARRLRosterAndCTYAgreeOnEveryCurrentEntity() throws {
        let cty = try XCTUnwrap(CTYTable.load(bundle: .main))
        let arrl = DXCCTable.shared
        XCTAssertEqual(arrl.entities.count, 340)
        let ctyCodes = Set(cty.entities.filter { !$0.waeOnly }.compactMap(\.entityCode))
        let arrlCodes = Set(arrl.entities.compactMap { Int($0.code) })
        XCTAssertEqual(ctyCodes, arrlCodes, "cty/ARRL disagree on: \(ctyCodes.symmetricDifference(arrlCodes))")
    }

    func testSharedAndHasPrefix() {
        XCTAssertNotNil(CTYTable.shared)
        XCTAssertTrue(CTYTable.shared!.hasPrefix("DL"))
        XCTAssertFalse(CTYTable.shared!.hasPrefix("DL1AA"))   // a full call is not a prefix key
        XCTAssertFalse(CTYTable.shared!.hasPrefix(""))
        XCTAssertTrue(CTYTable.shared!.hasPrefix("CE0Y"))   // Easter Island: primary prefix, not a token in its own list
    }
}

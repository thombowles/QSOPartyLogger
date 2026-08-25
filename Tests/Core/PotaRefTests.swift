import XCTest
@testable import QSOPartyLogger

final class PotaRefTests: XCTestCase {

    // Every accept case is an example row from the ADIF 3.1.4 POTARef data
    // type (docs/research/pota/SOURCES.md), plus the current-era US prefix.
    func testSpecExamplesNormalize() {
        for ref in ["K-5033", "K-10000", "VE-5082@CA-AB", "8P-0012",
                    "VK-0556", "K-4562@US-CA", "US-0817"] {
            XCTAssertEqual(PotaRef.normalize(ref), ref, "spec example \(ref)")
        }
    }

    func testNormalizeTrimsAndUppercases() {
        XCTAssertEqual(PotaRef.normalize(" us-3315 "), "US-3315")
        XCTAssertEqual(PotaRef.normalize("ve-5082@ca-ab"), "VE-5082@CA-AB")
    }

    func testMalformedReferencesAreRejected() {
        for bad in ["US3315",          // no hyphen
                    "US-331",          // 3-digit number
                    "US-123456",       // 6-digit number
                    "US 3315",         // interior space
                    "K-4562@US-CALIF", // suffix over 6 characters
                    "TOOLONG-1234",    // program over 4 characters
                    "-1234", "US-", ""] {
            XCTAssertNil(PotaRef.normalize(bad), "should reject \(bad)")
        }
    }

    func testParseListSplitsNormalizesAndDedupes() throws {
        let refs = try PotaRef.parseList("us-0088, US-4571,US-0088").get()
        XCTAssertEqual(refs, ["US-0088", "US-4571"])
    }

    func testParseListEmptyIsAValidEmptyList() throws {
        XCTAssertEqual(try PotaRef.parseList("").get(), [])
        XCTAssertEqual(try PotaRef.parseList("  ").get(), [])
        XCTAssertEqual(try PotaRef.parseList(" , ").get(), [])
    }

    func testParseListNamesTheBadToken() {
        guard case .failure(let failure) = PotaRef.parseList("US-3315,USA-331") else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(failure.message.contains("USA-331"), failure.message)
    }

    // MARK: Shorthand (spec 2026-08-25 decision 13)

    func testDigitsExpandToUSPark() {
        XCTAssertEqual(PotaRef.expandShorthand("2518"), "US-2518")
        XCTAssertEqual(PotaRef.expandShorthand("12345"), "US-12345")
        XCTAssertEqual(PotaRef.expandShorthand("2518, 0001"), "US-2518,US-0001")
        XCTAssertEqual(PotaRef.expandShorthand("US-2518,4576"), "US-2518,US-4576")
    }

    func testNonShorthandPassesThroughAsTyped() {
        XCTAssertEqual(PotaRef.expandShorthand("US-2518"), "US-2518")
        XCTAssertEqual(PotaRef.expandShorthand("VE-5082@CA-AB"), "VE-5082@CA-AB")
        XCTAssertEqual(PotaRef.expandShorthand(""), "")
        XCTAssertEqual(PotaRef.expandShorthand("251"), "251", "three digits is not a park number")
        XCTAssertEqual(PotaRef.expandShorthand("251879"), "251879", "six digits is not a park number")
        XCTAssertEqual(PotaRef.expandShorthand("K-TEST"), "K-TEST")
    }
}

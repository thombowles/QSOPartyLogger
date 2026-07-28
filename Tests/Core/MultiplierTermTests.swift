import XCTest
@testable import QSOPartyLogger

/// What a party calls the class in its `counties` slot.
///
/// The slot holds whatever a sponsor's finest enumerated multiplier class is,
/// and for several parties that is not a county: NAQP ships the ARRL DXCC
/// entities its rule 11 names, BCQP ships electoral districts, QCQP ships
/// Quebec's administrative regions. Calling all of them "Counties" in the
/// score sidebar is the app telling the operator something false about their
/// own contest.
final class MultiplierTermTests: XCTestCase {

    /// The overwhelming majority really are counties, and say so without any
    /// party file carrying the words.
    func testTheDefaultTermIsCounty() throws {
        let ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        XCTAssertEqual(ksqp.countyTerm, "county")
        XCTAssertEqual(ksqp.countyTermPlural, "counties")
    }

    /// NAQP rule 11: "other North American entities as defined by the ARRL
    /// DXCC List". Entity, not country — the shipped list includes United
    /// Nations HQ, Desecheo I. and Aves I., which are entities and not
    /// countries.
    func testNAQPCountsEntities() throws {
        for id in ["naqpcw", "naqpssb"] {
            let party = try XCTUnwrap(PartyCatalog.party(id: id))
            XCTAssertEqual(party.countyTerm, "NA entity", id)
            XCTAssertEqual(party.countyTermPlural, "NA entities", id)
        }
    }

    /// BCQP's rules, quoted in its research: "British Columbia stations send:
    /// RS(T) and District (three letter abbreviation)."
    func testBCQPCountsDistricts() throws {
        let bcqp = try XCTUnwrap(PartyCatalog.party(id: "bcqp"))
        XCTAssertEqual(bcqp.countyTerm, "district")
        XCTAssertEqual(bcqp.countyTermPlural, "districts")
    }

    /// QCQP's rules: "VE2 stations … must send a signal report and their
    /// administrative region."
    func testQCQPCountsRegions() throws {
        let qcqp = try XCTUnwrap(PartyCatalog.party(id: "qcqp"))
        XCTAssertEqual(qcqp.countyTerm, "region")
        XCTAssertEqual(qcqp.countyTermPlural, "regions")
    }

    /// HQP's rules: "Non-Hawaiian stations: 14 Hawai'i districts per band."
    /// Hawaii does have counties; they are not what this party counts.
    func testHQPCountsDistricts() throws {
        let hqp = try XCTUnwrap(PartyCatalog.party(id: "hqp"))
        XCTAssertEqual(hqp.countyTerm, "district")
        XCTAssertEqual(hqp.countyTermPlural, "districts")
    }

    /// Terms are stored lowercase so a heading can capitalize the first
    /// letter without flattening an acronym in the middle of one.
    func testSentenceCasingKeepsAnAcronymIntact() {
        XCTAssertEqual("counties".sentenceCased, "Counties")
        XCTAssertEqual("NA entities".sentenceCased, "NA entities")
        XCTAssertEqual("".sentenceCased, "")
    }

    /// A party supplying only the singular gets the regular plural, so the
    /// common case ("district") costs one line in the JSON.
    func testARegularPluralIsDerived() throws {
        let party = try Self.party(extraKeys: #""countyTerm": "district","#)
        XCTAssertEqual(party.countyTerm, "district")
        XCTAssertEqual(party.countyTermPlural, "districts")
    }

    /// An irregular one is supplied outright rather than mangled.
    func testAnIrregularPluralIsSupplied() throws {
        let party = try Self.party(
            extraKeys: #""countyTerm": "parish", "countyTermPlural": "parishes","#
        )
        XCTAssertEqual(party.countyTermPlural, "parishes")
    }

    private static func party(extraKeys: String) throws -> PartyDefinition {
        let json = """
        {
          "schemaVersion": 1,
          "id": "test",
          "name": "Test Party",
          "cabrilloContest": "TEST",
          "homeState": "KS",
          "countyAbbrLength": 2,
          \(extraKeys)
          "validBands": ["20m"],
          "points": {"phone": 1, "cw": 2, "digital": 2},
          "dupeScope": "bandMode",
          "multipliers": {
            "inState": {"classes": ["county"], "homeStateCountsViaCounty": false,
                        "countScope": "once"},
            "outState": {"classes": ["county"], "homeStateCountsViaCounty": false,
                         "countScope": "once"}
          },
          "bonuses": [],
          "counties": [{"abbr": "AL", "name": "Allen"}]
        }
        """
        return try JSONDecoder().decode(PartyDefinition.self, from: Data(json.utf8))
    }
}

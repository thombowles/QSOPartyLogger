import XCTest
@testable import QSOPartyLogger

/// The ARRL DXCC List as this app reads it.
///
/// The count assertions live in `docs/research/gen_dxcc.py` too (Article 2),
/// but a generator only runs when someone runs it. These run on every build,
/// so a resource that fails to bundle, or a schema change that quietly drops
/// half the prefixes, fails here rather than in a contest.
final class DXCCTableTests: XCTestCase {

    private var table: DXCCTable { DXCCTable.shared }

    // MARK: The list itself

    /// The ARRL document states its own total, and that is what is asserted —
    /// 340 in the January 2026 edition. A new edition changes this number
    /// deliberately, through the generator, never by accident.
    func testTheBundledListIsTheWholeARRLList() {
        XCTAssertEqual(table.entities.count, 340,
                       "ARRL's January 2026 edition states 340 current entities")
        XCTAssertEqual(Set(table.entities.map(\.code)).count, 340, "entity codes must be unique")
        XCTAssertEqual(Set(table.entities.map(\.name)).count, 340, "entity names must be unique")
        XCTAssertTrue(table.source.contains("ARRL DXCC List"), table.source)
        XCTAssertEqual(table.fetched, "2026-07-27")
    }

    func testEveryPrefixResolvesToAListedEntity() {
        let codes = Set(table.entities.map(\.code))
        for (prefix, code) in table.prefixes {
            XCTAssertTrue(codes.contains(code), "\(prefix) points at unknown entity \(code)")
            XCTAssertNotNil(table.entity(forPrefix: prefix), prefix)
        }
        XCTAssertGreaterThan(table.prefixes.count, 700, "the ranges must be expanded")
    }

    // MARK: Prefixes, chosen from the irregular rows

    /// Spot checks drawn from the rows a naive parse gets wrong: expanded
    /// ranges, footnote digits glued to the prefix, and prefix cells that
    /// wrap onto a second line.
    func testIrregularPrefixesResolve() {
        let expected: [String: String] = [
            "DL": "Germany",            // inside the DA-DR range
            "DA": "Germany",
            "DR": "Germany",
            "JA": "Japan",              // JA-JS range
            "G": "England",
            "GM": "Scotland",           // not England
            "XE": "Mexico",             // XA-XI range
            "K": "United States of America",   // prefix cell wraps to "AA-AK"
            "AA": "United States of America",
            "KL": "Alaska",             // wraps to "WL"
            "VE": "Canada",             // wraps to "VO,VY"
            "VO": "Canada",
            "TR": "Gabon",              // "TR32" — 32 is a footnote
            "BS7": "Scarborough Reef",  // "BS711" — 11 is a footnote
            "9G": "Ghana",              // "9G7" — 7 is a footnote
            "Z3": "North Macedonia",    // "Z341" — 41 is a footnote
            "T31": "C. Kiribati",       // NOT T3 + footnote 1
            "1A": "Sov. Mil. Order of Malta",  // "1A1" — 1 IS a footnote
            "Z6": "Republic of Kosovo",        // "Z61,55" — both are footnotes
            "7O": "Yemen",
            "KP4": "Puerto Rico",       // "KP3,4" — bare digit shares the stem
            "KP3": "Puerto Rico",
            "KH6": "Hawaii",
            "4U_UN": "United Nations HQ",
        ]
        for (prefix, name) in expected {
            XCTAssertEqual(table.entity(forPrefix: prefix)?.name, name, prefix)
        }
    }

    /// Longer prefixes win, or Balearic calls would count as Spain.
    func testLongerPrefixesBeatShorterOnes() {
        XCTAssertEqual(table.entity(forPrefix: "EA")?.name, "Spain")
        XCTAssertEqual(table.entity(forPrefix: "EA6")?.name, "Balearic Is.")
        XCTAssertEqual(table.entity(forPrefix: "EA8")?.name, "Canary Is.")
        XCTAssertEqual(table.entity(forPrefix: "EA9")?.name, "Ceuta & Melilla")
        XCTAssertEqual(table.entity(forCallsign: "EA6XYZ")?.name, "Balearic Is.")
        XCTAssertEqual(table.entity(forCallsign: "EA1XYZ")?.name, "Spain")
    }

    /// A range must stop where the source stops it.
    func testRangesDoNotOverrun() {
        XCTAssertNil(table.entity(forPrefix: "DS"), "DA-DR must not reach DS")
        XCTAssertNil(table.entity(forPrefix: "ZZZZ"))
        XCTAssertNil(table.entity(forPrefix: ""))
    }

    // MARK: Callsigns

    func testEntityComesFromTheCallsign() {
        let expected: [String: String] = [
            "DL1ABC": "Germany",
            "G0XYZ": "England",
            "PA0AAA": "Netherlands",
            "ON4DDD": "Belgium",
            "OK1AA": "Czech Republic",
            "LA9ZZ": "Norway",
            "OH2BH": "Finland",
            "JA1XYZ": "Japan",
            "VK3ABC": "Australia",
            "LY2ZZ": "Lithuania",
            "W1AW": "United States of America",
            "VE3ABC": "Canada",
            "XE1ABC": "Mexico",
        ]
        for (call, name) in expected {
            XCTAssertEqual(table.entity(forCallsign: call)?.name, name, call)
        }
    }

    /// Operating suffixes say how a station works, not where it is; a
    /// location prefix says where. Both conventions read the same way.
    func testPortableAndSlashedCallsigns() {
        XCTAssertEqual(table.entity(forCallsign: "G0XYZ/P")?.name, "England")
        XCTAssertEqual(table.entity(forCallsign: "DL1ABC/QRP")?.name, "Germany")
        XCTAssertEqual(table.entity(forCallsign: "W1AW/4")?.name, "United States of America")
        XCTAssertEqual(table.entity(forCallsign: "KH6/DL1ABC")?.name, "Hawaii")
        XCTAssertEqual(table.entity(forCallsign: "DL1ABC/KH6")?.name, "Hawaii")
        XCTAssertEqual(table.entity(forCallsign: "VP2E/W1AW")?.name, "Anguilla")
        XCTAssertEqual(table.entity(forCallsign: "dl1abc")?.name, "Germany", "case-insensitive")
        XCTAssertNil(table.entity(forCallsign: ""))
        XCTAssertNil(table.entity(forCallsign: "/"))
    }

    // MARK: The gaps, asserted so they stay deliberate

    /// The ARRL list gives fourteen prefix blocks to more than one entity.
    /// Each resolves to one, and the ones that lose are named — so a future
    /// edition that splits them trips the generator rather than moving a
    /// score quietly.
    func testSharedPrefixBlocksResolveToTheirDesignatedEntity() {
        XCTAssertEqual(table.mergedPrefixes.count, 14)
        XCTAssertEqual(table.entity(forPrefix: "FO")?.name, "French Polynesia")
        XCTAssertEqual(table.mergedPrefixes["FO"]?.alsoClaimedBy.sorted(),
                       ["Austral I.", "Clipperton I.", "Marquesas Is."])
        XCTAssertEqual(table.entity(forPrefix: "VP6")?.name, "Pitcairn I.")
        XCTAssertEqual(table.mergedPrefixes["VP6"]?.alsoClaimedBy, ["Ducie I."])
        XCTAssertEqual(table.entity(forPrefix: "CU")?.name, "Azores",
                       "the Azores' own row beats the tail of Portugal's CQ-CU range")
        for (prefix, merged) in table.mergedPrefixes {
            XCTAssertEqual(table.entity(forPrefix: prefix)?.name, merged.entity, prefix)
            XCTAssertFalse(merged.alsoClaimedBy.isEmpty, prefix)
        }
    }

    /// France shares TO and TX across several entities in this very list, so
    /// no call beginning with either can be attributed. Their entities keep
    /// the prefixes stations actually sign.
    func testSharedFrenchPoolsResolveToNothing() {
        XCTAssertNil(table.entity(forPrefix: "TO"))
        XCTAssertNil(table.entity(forPrefix: "TX"))
        XCTAssertEqual(table.entity(forPrefix: "FG")?.name, "Guadeloupe")
        XCTAssertEqual(table.entity(forPrefix: "FM")?.name, "Martinique")
        XCTAssertEqual(table.entity(forPrefix: "FR")?.name, "Reunion I.")
        XCTAssertEqual(table.entity(forPrefix: "FS")?.name, "Saint Martin")
    }

    /// Spratly's prefix cell is empty in the ARRL PDF's own text layer. The
    /// entity ships without one rather than with a remembered value.
    func testSpratlyShipsWithoutAPrefix() {
        XCTAssertEqual(table.withoutPrefix, ["247": "Spratly Is."])
        XCTAssertNil(table.entity(forPrefix: "1S"))
        XCTAssertNotNil(table.entities.first { $0.code == "247" })
        XCTAssertEqual(table.entities.first { $0.code == "247" }?.prefixes, [])
    }

    // MARK: Agreement with the other reader of the same file

    /// `gen_naqp.py` reads this same ARRL text for the 46 North American
    /// entity names NAQP counts. Both readings must agree, or one of them is
    /// wrong about the source — with two exemptions that are themselves facts
    /// about the sources rather than slack in the test.
    func testAgreesWithTheNAQPCountryList() throws {
        let naqp = try XCTUnwrap(
            PartyCatalog.loadBundled().first { $0.id == "naqpcw" },
            "naqpcw must be bundled"
        )
        XCTAssertEqual(naqp.counties.count, 46)

        // NAQP's own rewrite: the sponsor's checklist token is "4U1/u", and
        // "/" is the county-line separator, so it ships as 4U1. The ARRL row
        // is 4U_UN, and the callsign that resolves is 4U1UN.
        XCTAssertNil(table.entity(forPrefix: "4U1"))
        XCTAssertEqual(table.entity(forCallsign: "4U1UN")?.name, "United Nations HQ")

        // FO is one of the fourteen blocks the ARRL list shares. NAQP counts
        // North American entities only, so its reading is forced to the NA
        // row (Clipperton); this table has no such constraint and designates
        // the entity a US state party is far likelier to work.
        XCTAssertEqual(naqp.counties.first { $0.abbr == "FO" }?.name, "Clipperton I.")
        XCTAssertEqual(table.entity(forPrefix: "FO")?.name, "French Polynesia")
        XCTAssertNotNil(table.mergedPrefixes["FO"])

        let divergent: Set<String> = ["4U1", "FO"]
        for county in naqp.counties where !divergent.contains(county.abbr) {
            let entity = table.entity(forPrefix: county.abbr)
            XCTAssertNotNil(entity, "NAQP ships \(county.abbr); the DXCC table has no such prefix")
            XCTAssertEqual(entity?.name, county.name, county.abbr)
        }
    }
}

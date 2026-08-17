import XCTest
@testable import QSOPartyLogger

final class ArrlSectionsTests: XCTestCase {
    func testEightyFiveSectionsFromTheSponsorsList() throws {
        let sections = try XCTUnwrap(TokenSet.sections(bundle: .main))
        XCTAssertEqual(sections.id, "sections")
        XCTAssertEqual(sections.tokens.count, 85)
        XCTAssertEqual(sections.abbrs.count, 85)
        XCTAssertNoThrow(try sections.validate())
        XCTAssertEqual(Set(sections.tokens.compactMap(\.name)).count, 85)
        // Irregular ones (Article 18's habit): not the obvious two-letter states.
        XCTAssertEqual(sections.token(for: "NTX")?.name, "North Texas")
        XCTAssertEqual(sections.token(for: "TER")?.name, "Territories")
        XCTAssertEqual(sections.token(for: "GH")?.name, "Ontario Golden Horseshoe")
        XCTAssertEqual(sections.token(for: "PAC")?.name, "Pacific")
        XCTAssertEqual(sections.token(for: "MDC")?.name, "Maryland-DC")
        XCTAssertEqual(sections.token(for: "NLI")?.name, "New York City-Long Island")
        XCTAssertEqual(sections.token(for: "WCF")?.group, "U.S. Call Area 4")
        XCTAssertEqual(sections.token(for: "AB")?.group, "Canada")
        XCTAssertFalse(sections.accepts("TX"))     // a state, not a section
        XCTAssertFalse(sections.accepts("YT"))     // Yukon sends TER in 2026
    }
}

import XCTest
@testable import QSOPartyLogger

final class ContestCatalogStandaloneTests: XCTestCase {
    /// The Setup picker's tail section: v2-only contests — ids no
    /// PartyDefinition claims. Exactly POTA today; every party stays in the
    /// party rows it has always had.
    func testStandaloneIsExactlyPota() {
        let standalone = ContestCatalog.standalone(bundle: .main)
        XCTAssertEqual(standalone.map(\.id), ["pota"])
        let partyIDs = Set(PartyCatalog.loadBundled(bundle: .main).map(\.id))
        XCTAssertTrue(partyIDs.isDisjoint(with: standalone.map(\.id)))
    }
}

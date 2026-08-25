import XCTest
@testable import QSOPartyLogger

/// Contest-aware default messages (spec 2026-08-25 decision 14): the same
/// derivation as the party form, read off the exchange elements, plus the
/// contest's own CQ word. The equality test is what lets `LogDocument`
/// resolve defaults through the ContestCatalog without any log's "untouched
/// messages" sentinel moving.
final class MessageSetsContestDefaultsTests: XCTestCase {

    func testContestDefaultsEqualPartyDefaultsForEveryParty() {
        for party in PartyCatalog.loadBundled(bundle: .main) {
            guard let lowered = try? PartyLowering.lower(party) else {
                return XCTFail("\(party.id) does not lower")
            }
            XCTAssertEqual(MessageSets.defaults(for: lowered),
                           MessageSets.defaults(for: party), party.id)
        }
    }

    func testNilContestEqualsNilParty() {
        XCTAssertEqual(MessageSets.defaults(for: nil as ContestDefinition?),
                       MessageSets.defaults(for: nil as PartyDefinition?))
    }

    func testPotaDefaultsSayCQPOTAAndCarryNoExchangeMacro() throws {
        let pota = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        let sets = MessageSets.defaults(for: pota)
        XCTAssertEqual(sets.run[0], "CQ POTA {MYCALL}")
        XCTAssertEqual(sets.run[1], "{CALL} {RST}")
        XCTAssertFalse(sets.run.joined().contains("{EXCH}"),
                       "no location element, no location macro")
        XCTAssertFalse(sets.searchPounce.joined().contains("{EXCH}"))
    }

    func testMyParkMacroExpands() {
        let expanded = AppSettings.expandMacros(
            "AT {MYPARK} 73", myCall: "KE5CW", call: "W1AW", rst: "599",
            exchange: "", myParks: "US-1111 US-2222")
        XCTAssertEqual(expanded, "AT US-1111 US-2222 73")
    }

    func testMyParkMacroEmptyWhenNotActivating() {
        let expanded = AppSettings.expandMacros(
            "{MYPARK}73", myCall: "KE5CW", call: "", rst: "599", exchange: "")
        XCTAssertEqual(expanded, "73")
    }
}

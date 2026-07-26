import XCTest
@testable import QSOPartyLogger

/// Where an umbrella party and a standalone party cover the same state, they
/// describe the same counties — so a future edit to one cannot silently drift
/// from the other.
///
/// This is not a hypothetical. Six state-sets are duplicated across the
/// catalogue today: New England carries Maine's, New Hampshire's and Vermont's
/// alongside Connecticut, Massachusetts and Rhode Island, and the 7th Call Area
/// carries Arizona's, Idaho's and Washington's alongside five more. They were
/// verified equal by hand on 2026-07-26; this keeps them that way.
///
/// Abbreviations are deliberately **not** compared. They differ by design — the
/// umbrella parties use 5-letter state-prefixed codes (`MEAND`, `AZYVP`) where
/// the standalones use 3 or 4 (`AND`, `YAV`) — and that is the sponsors' choice,
/// not a defect.
final class CatalogConsistencyTests: XCTestCase {

    private var parties: [PartyDefinition] { PartyCatalog.loadBundled() }

    /// Every (umbrella, standalone) pair sharing a state, discovered rather
    /// than listed, so a new multi-state party is covered the day it lands.
    private func overlaps() -> [(umbrella: PartyDefinition,
                                 standalone: PartyDefinition,
                                 state: String)] {
        let all = parties
        let umbrellas = all.filter { $0.homeStates.count > 1 && $0.combines.isEmpty }
        var found: [(PartyDefinition, PartyDefinition, String)] = []
        for umbrella in umbrellas {
            for state in umbrella.homeStates {
                let standalones = all.filter {
                    $0.homeStates.count == 1 && $0.homeState == state
                }
                for standalone in standalones {
                    found.append((umbrella, standalone, state))
                }
            }
        }
        return found
    }

    private func names(_ party: PartyDefinition, inState state: String) -> Set<String> {
        Set(party.counties
            .filter { ($0.state ?? party.homeState) == state }
            .map { $0.name.uppercased() })
    }

    func testOverlappingStatesAgreeOnCountyNames() {
        let pairs = overlaps()
        XCTAssertFalse(pairs.isEmpty, "no overlaps found — the discovery is broken")

        for (umbrella, standalone, state) in pairs {
            let fromUmbrella = names(umbrella, inState: state)
            let fromStandalone = names(standalone, inState: state)
            XCTAssertEqual(
                fromUmbrella, fromStandalone,
                """
                \(umbrella.id) and \(standalone.id) disagree about \(state).
                Only in \(umbrella.id): \(fromUmbrella.subtracting(fromStandalone).sorted())
                Only in \(standalone.id): \(fromStandalone.subtracting(fromUmbrella).sorted())
                """
            )
        }
    }

    /// The six overlaps that exist today. A change here means a party was added
    /// or removed, which should be deliberate.
    func testOverlapRosterIsExactlyAsExpected() {
        let actual = Set(overlaps().map { "\($0.umbrella.id)/\($0.standalone.id):\($0.state)" })
        XCTAssertEqual(actual, [
            "newenglandqp/meqp:ME",
            "newenglandqp/nhqp:NH",
            "newenglandqp/vtqp:VT",
            "sevenqp/azqp:AZ",
            "sevenqp/idqp:ID",
            "sevenqp/warun:WA",
        ])
    }

    /// Both umbrella parties tag every county with its state. Without that the
    /// comparison above silently compares nothing, and `state(forCounty:)` falls
    /// back to `homeState` for counties that are not in it.
    func testMultiStatePartiesTagEveryCountyWithItsState() {
        for party in parties where party.homeStates.count > 1 {
            for county in party.counties {
                XCTAssertNotNil(
                    county.state,
                    "\(party.id): \(county.abbr) carries no state"
                )
            }
        }
    }

    /// The sponsors' own totals, which is what makes the county lists
    /// self-checking rather than merely self-consistent.
    func testSponsorStatedTotals() {
        let expected = ["newenglandqp": 68, "sevenqp": 259]
        for (id, total) in expected {
            let party = parties.first { $0.id == id }
            XCTAssertEqual(party?.counties.count, total, "\(id) multiplier count")
        }
        XCTAssertEqual(parties.first { $0.id == "neqp" }?.counties.count, 93)
    }

    /// New England is six states and the 7th Call Area is eight — Washington
    /// included, which the party was originally built without.
    func testUmbrellaMemberStatesAreComplete() {
        XCTAssertEqual(
            parties.first { $0.id == "newenglandqp" }?.homeStates.sorted(),
            ["CT", "MA", "ME", "NH", "RI", "VT"]
        )
        XCTAssertEqual(
            parties.first { $0.id == "sevenqp" }?.homeStates.sorted(),
            ["AZ", "ID", "MT", "NV", "OR", "UT", "WA", "WY"]
        )
    }
}

import XCTest
@testable import QSOPartyLogger

/// The short name a log goes by — in the band map's title and header, so
/// with several contests in tabs each map says whose it is. The same token
/// the file name carries (`defaultDisplayName`): the party's id in capitals,
/// or the park for a POTA activation.
final class ContestShortLabelTests: XCTestCase {

    func testAPartyIsItsIdInCapitals() {
        XCTAssertEqual(LogDocument.contestShortLabel(partyID: "ksqp"), "KSQP")
        XCTAssertEqual(LogDocument.contestShortLabel(partyID: "naqpcw"), "NAQPCW")
    }

    func testAPotaActivationIsItsPark() {
        XCTAssertEqual(
            LogDocument.contestShortLabel(partyID: "pota", activatedParks: ["us-1234"], potaProgram: true),
            "US-1234"
        )
    }

    /// A POTA log with no park yet — hunting, or setup not done — is POTA.
    func testAPotaLogWithoutAParkIsPota() {
        XCTAssertEqual(
            LogDocument.contestShortLabel(partyID: "pota", activatedParks: [], potaProgram: true),
            "POTA"
        )
    }

    /// A contest worked from a park is still the contest — the park is on
    /// the POTA side of the dashboard, not in the map's title.
    func testAContestFromAParkIsStillTheContest() {
        XCTAssertEqual(
            LogDocument.contestShortLabel(partyID: "ksqp", activatedParks: ["US-1234"], potaProgram: false),
            "KSQP"
        )
    }

    func testNoPartyIsNoLabel() {
        XCTAssertEqual(LogDocument.contestShortLabel(partyID: ""), "")
    }
}

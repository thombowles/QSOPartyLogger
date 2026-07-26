import XCTest
@testable import QSOPartyLogger

/// Which station the spot command means.
///
/// One shortcut, not two. Two spot commands a single modifier apart is how a
/// sheet ends up open with your own call in it mid-QSO, so the operating mode
/// decides instead: running means advertising your own frequency, searching
/// means putting the station you just found on the board.
final class SpotCommandTests: XCTestCase {

    // MARK: Running

    func testRunningSpotsYourself() {
        XCTAssertEqual(SpotCommand.target(mode: .run, entryCall: ""), .myself)
    }

    /// Even mid-QSO. An operator calling CQ with a half-copied call in the
    /// field still means their own run — guessing otherwise would bring back
    /// the ambiguity this command exists to remove.
    func testRunningSpotsYourselfEvenWithACallInTheField() {
        XCTAssertEqual(SpotCommand.target(mode: .run, entryCall: "N4RT"), .myself)
    }

    // MARK: Searching

    func testSearchingSpotsTheStationInTheCallField() {
        XCTAssertEqual(
            SpotCommand.target(mode: .searchPounce, entryCall: "N4RT"),
            .station("N4RT")
        )
    }

    func testTheSpottedCallIsNormalized() {
        XCTAssertEqual(
            SpotCommand.target(mode: .searchPounce, entryCall: " n4rt "),
            .station("N4RT")
        )
    }

    /// Nobody in the field yet — you heard a call and reached for the command
    /// before typing it. The sheet still opens; it just opens empty.
    func testSearchingWithAnEmptyCallFieldOpensABlankSpot() {
        XCTAssertEqual(SpotCommand.target(mode: .searchPounce, entryCall: ""), .blankStation)
        XCTAssertEqual(SpotCommand.target(mode: .searchPounce, entryCall: "   "), .blankStation)
    }
}

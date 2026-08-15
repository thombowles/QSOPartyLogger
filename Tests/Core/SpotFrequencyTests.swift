import XCTest
@testable import QSOPartyLogger

/// Kilohertz the way every board's form asks for it. Not `%g`: six
/// significant digits turn 14045.25 into 14045.2 — 50 Hz off, broadcast to
/// everyone reading the board.
final class SpotFrequencyTests: XCTestCase {

    func testWholeKilohertzHaveNoDecimalPoint() {
        XCTAssertEqual(SpotFrequency.text(kHz: 7047), "7047")
        XCTAssertEqual(SpotFrequency.text(kHz: 14150.0), "14150")
    }

    func testFractionsKeepTwoDecimalsAndDropTrailingZeros() {
        XCTAssertEqual(SpotFrequency.text(kHz: 14045.25), "14045.25")
        XCTAssertEqual(SpotFrequency.text(kHz: 7047.5), "7047.5")
        XCTAssertEqual(SpotFrequency.text(kHz: 7047.10), "7047.1")
    }

    /// The hub's formatter is this formatter — one place to be right about
    /// what a frequency looks like on a public board.
    func testTheHubFormatterIsTheSameFormatter() {
        XCTAssertEqual(HubSelfSpot.formattedFrequency(14045.25), SpotFrequency.text(kHz: 14045.25))
    }
}

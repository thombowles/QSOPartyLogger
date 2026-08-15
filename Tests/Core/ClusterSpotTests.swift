import XCTest
@testable import QSOPartyLogger

/// The `DX` command as DXSpider and AR-Cluster both take it — frequency
/// first, in kilohertz, remarks after the call. Sources banked in
/// `docs/research/dxcluster-dx-command.md`.
final class ClusterSpotTests: XCTestCase {

    private func fields(
        call: String = "KE5CW", kHz: Double = 7047, remarks: String = ""
    ) -> ClusterSpot.Fields {
        .init(call: call, frequencyKHz: kHz, remarks: remarks)
    }

    // MARK: The command

    func testTheCommandIsFrequencyThenCallThenRemarks() {
        XCTAssertEqual(
            ClusterSpot.command(fields(remarks: "AL-QSO-PARTY MDSN")),
            "DX 7047 KE5CW AL-QSO-PARTY MDSN"
        )
    }

    func testNoRemarksMeansNoTrailingSpace() {
        XCTAssertEqual(ClusterSpot.command(fields()), "DX 7047 KE5CW")
        XCTAssertEqual(ClusterSpot.command(fields(remarks: "   ")), "DX 7047 KE5CW")
    }

    func testTheCallGoesOutUpperCasedAndTrimmed() {
        XCTAssertEqual(ClusterSpot.command(fields(call: " ke5cw ")), "DX 7047 KE5CW")
    }

    func testFractionalKilohertzKeepTheirDecimals() {
        XCTAssertEqual(ClusterSpot.command(fields(kHz: 14045.25)), "DX 14045.25 KE5CW")
    }

    /// A newline would end the command early and send the rest as a second
    /// one; a control character has no place on the air.
    func testRemarksAreOneLineSingleSpacedAndPrintable() {
        XCTAssertEqual(ClusterSpot.sanitize("MDSN\r\nsh/dx\t  30 \u{7}bell"), "MDSN sh/dx 30 bell")
        XCTAssertEqual(ClusterSpot.command(fields(remarks: "a\nbye")), "DX 7047 KE5CW a bye")
    }

    func testRemarksAreContestThenCountyThenComment() {
        XCTAssertEqual(
            ClusterSpot.remarks(contest: "AL-QSO-PARTY", county: "MDSN/LIME", comment: "mobile"),
            "AL-QSO-PARTY MDSN/LIME mobile"
        )
        XCTAssertEqual(ClusterSpot.remarks(contest: "NAQP-CW", county: nil, comment: ""), "NAQP-CW")
        XCTAssertEqual(ClusterSpot.remarks(contest: nil, county: nil, comment: " hi "), "hi")
    }

    func testValidationNeedsACallAndAFrequency() {
        XCTAssertEqual(ClusterSpot.validate(fields(call: " ")), .missingCall)
        XCTAssertEqual(ClusterSpot.validate(fields(kHz: 0)), .missingFrequency)
        XCTAssertNil(ClusterSpot.validate(fields()))
    }

    // MARK: Echo — the node's "proof of receipt"

    private func spot(call: String = "KE5CW", spotter: String = "KE5CW", kHz: Double = 7047.0) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: spotter, comment: "", receivedAt: Date())
    }

    func testOurOwnSpotBackFromTheNodeIsAnEcho() {
        XCTAssertTrue(ClusterSpot.isEcho(spot(), of: fields(), poster: "ke5cw"))
        XCTAssertTrue(ClusterSpot.isEcho(spot(), of: fields(call: " ke5cw"), poster: " KE5CW "))
    }

    func testAnotherSpotterOrCallIsNotOurEcho() {
        XCTAssertFalse(ClusterSpot.isEcho(spot(spotter: "N4RT"), of: fields(), poster: "KE5CW"))
        XCTAssertFalse(ClusterSpot.isEcho(spot(call: "N4RT"), of: fields(), poster: "KE5CW"))
    }

    /// Nodes print to 100 Hz, so a rounded frequency is still ours; a moved
    /// one is somebody else's spot of the same call.
    func testTheEchoMayBeRoundedButNotMoved() {
        XCTAssertTrue(ClusterSpot.isEcho(spot(kHz: 7047.2), of: fields(kHz: 7047.25), poster: "KE5CW"))
        XCTAssertFalse(ClusterSpot.isEcho(spot(kHz: 7048), of: fields(), poster: "KE5CW"))
    }
}

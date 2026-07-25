import XCTest
@testable import QSOPartyLogger

/// Mode inference constrained by the party's own rules.
///
/// The generic band plan in `SpotFilter.segments` is tuned for DX cluster
/// spots, where the FT8 watering holes matter. A QSO party that forbids
/// digital has no such segment — its CW activity simply runs further up the
/// band. Inferring "digital" there is not a cosmetic slip: `wouldAddMultiplier`
/// refuses any mode the party disallows, so the multiplier badge silently
/// disappears on a station that is worth chasing.
final class PartyModeInferenceTests: XCTestCase {

    /// Live ALQP spot, 2026-07-25 22:01:10Z: `KC4TEO 7047.0 MDSN`.
    ///
    /// The 40 m CW segment boundary is 7045, so the unconstrained band plan
    /// calls 7047.0 digital. ALQP runs phone and CW only, and its CW activity
    /// legitimately extends to about 7060.
    func testLiveAlabamaSpotAboveTheCWBoundaryInfersCWNotDigital() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        XCTAssertEqual(
            SpotFilter.modeClass(freqKHz: 7047.0, comment: "",
                                 allowedModes: alqp.allowedModeClasses),
            .cw
        )
    }

    /// The consequence, stated as the operator experiences it: a needed
    /// Alabama county on a real live frequency must still badge as a new
    /// multiplier. Inferring digital suppresses it entirely.
    func testNeededCountyStillCountsAsAMultiplierAtThatFrequency() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        var log = ContestLog(partyID: "alqp")
        log.myLocation = .outOfState(location: "TX")

        let mode = SpotFilter.modeClass(freqKHz: 7047.0, comment: "",
                                        allowedModes: alqp.allowedModeClasses)
        XCTAssertTrue(
            ScoreEngine.wouldAddMultiplier(
                theirLocs: ["MDSN"], band: .m40, modeClass: mode,
                log: log, party: alqp
            ),
            "Madison County is unworked — it must badge as a new multiplier"
        )
    }

    /// Unconstrained inference is untouched, so cluster spots in parties that
    /// do allow digital keep classifying exactly as before.
    func testUnconstrainedInferenceIsUnchanged() {
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 7047.0, comment: ""), .digital)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 7074, comment: ""), .digital)
        XCTAssertEqual(SpotFilter.modeClass(freqKHz: 14074, comment: ""), .digital)
    }

    /// A party that permits digital keeps it.
    func testPartyAllowingDigitalStillInfersDigital() throws {
        let ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        XCTAssertTrue(ksqp.allowedModeClasses.contains(.digital),
                      "precondition: KSQP allows digital")
        XCTAssertEqual(
            SpotFilter.modeClass(freqKHz: 7074, comment: "",
                                 allowedModes: ksqp.allowedModeClasses),
            .digital
        )
    }

    /// The operator's own comment still wins over the band plan, and is then
    /// held to the party's rules like any other inference.
    func testCommentStillWinsButIsHeldToThePartysModes() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        XCTAssertEqual(
            SpotFilter.modeClass(freqKHz: 7047.0, comment: "SSB",
                                 allowedModes: alqp.allowedModeClasses),
            .phone,
            "a spotter who says SSB is believed"
        )
        XCTAssertEqual(
            SpotFilter.modeClass(freqKHz: 7047.0, comment: "FT8",
                                 allowedModes: alqp.allowedModeClasses),
            .cw,
            "FT8 is not a legal ALQP mode, so it folds to the neighbouring segment"
        )
    }

    /// An empty allow-list means "no constraint", so a party definition that
    /// omits `allowedModes` behaves exactly as it does today.
    func testEmptyAllowListImposesNoConstraint() {
        XCTAssertEqual(
            SpotFilter.modeClass(freqKHz: 7047.0, comment: "", allowedModes: []),
            .digital
        )
    }

    /// The band map's own mode filter has to agree with the badge. A CW-only
    /// view that hides a station the scoring engine counts as a CW multiplier
    /// is the same defect wearing a different hat.
    func testBandMapModeFilterUsesThePartysModes() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let spot = Spot(call: "KC4TEO", freqKHz: 7047.0, spotter: "N4EMP",
                        comment: "", receivedAt: Date())

        var options = SpotFilter.Options()
        options.modes = [.cw]
        XCTAssertFalse(SpotFilter.matches(spot, options: options),
                       "precondition: unconstrained, 7047.0 is classed digital")

        options.allowedModes = alqp.allowedModeClasses
        XCTAssertTrue(SpotFilter.matches(spot, options: options),
                      "under ALQP's rules this is a CW spot and belongs in a CW view")
    }

    /// Every bundled party must classify every one of its own valid bands to a
    /// mode it actually permits. A party whose rules cannot express what the
    /// band plan infers would badge inconsistently all contest long.
    func testEveryPartyClassifiesItsOwnBandsToAPermittedMode() {
        for party in PartyCatalog.loadBundled() {
            let allowed = Set(party.allowedModeClasses)
            for band in party.validBands {
                let edges = band.rangeKHz
                for freq in stride(from: Double(edges.lowerBound),
                                   through: Double(edges.upperBound), by: 5) {
                    let mode = SpotFilter.modeClass(
                        freqKHz: freq, comment: "",
                        allowedModes: party.allowedModeClasses
                    )
                    XCTAssertTrue(
                        allowed.contains(mode),
                        "\(party.id): \(freq) kHz on \(band.rawValue) inferred \(mode), which the party forbids"
                    )
                }
            }
        }
    }
}

import XCTest
import CoreLocation
@testable import QSOPartyLogger

/// Filling the grid square from the Mac's location. The Core Location glue
/// itself cannot be unit-tested, so the decisions either side of it — what a
/// fix becomes, and what each failure tells the operator to do — live in
/// `GridLocate` and `LocationFailure` and are pinned here.
///
/// The regression these guard is the 2026-08-05 one: `currentLocation()`
/// called `requestLocation()` in the same breath as
/// `requestWhenInUseAuthorization()`, which the CoreLocation header says
/// resolves asynchronously via the delegate — so the first press always
/// raced the grant and failed, and the operator was told only "couldn't get
/// a location", which names neither the cause nor the remedy.
@MainActor
final class GridLocateTests: XCTestCase {

    struct ScriptedProvider: LocationProviding {
        var authorized = true
        var result: Result<LocationFix, LocationFailure>
        var isAuthorized: Bool { authorized }
        func currentLocation() async -> Result<LocationFix, LocationFailure> { result }
    }

    func testAFixBecomesASixCharacterGrid() async {
        let fix = LocationFix(latitude: 41.714775, longitude: -72.727260)
        let provider = ScriptedProvider(result: .success(fix))
        let outcome = await GridLocate.run(provider)
        XCTAssertEqual(outcome, .filled(grid: "FN31PR", fix: fix))
    }

    /// Every failure names its own remedy: a denied permission and a Mac
    /// that cannot see itself need different actions, and both need to say
    /// that typing the grid square is always available.
    func testEachFailureNamesItsOwnRemedy() async {
        for failure in [LocationFailure.denied, .unavailable, .timedOut,
                        .failed("boom")] {
            let outcome = await GridLocate.run(ScriptedProvider(result: .failure(failure)))
            guard case .failed(let message) = outcome else {
                return XCTFail("\(failure) should fail")
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertTrue(message.lowercased().contains("grid square"),
                          "every failure points at the field that always works: \(message)")
        }
        // And they are not all the same sentence.
        let messages = Set([LocationFailure.denied, .unavailable, .timedOut]
            .map(\.message))
        XCTAssertEqual(messages.count, 3, "a denial and a blank fix read differently")
    }

    /// Denial sends the operator to the one place that can undo it.
    func testDenialPointsAtSystemSettings() {
        XCTAssertTrue(LocationFailure.denied.message.contains("System Settings"),
                      LocationFailure.denied.message)
    }

    /// Core Location's own error codes, mapped to what they mean for the
    /// operator (CLError.h: kCLErrorLocationUnknown = 0, kCLErrorDenied = 1).
    func testCoreLocationErrorsAreMapped() {
        let denied = NSError(domain: CLError.errorDomain,
                             code: CLError.Code.denied.rawValue)
        XCTAssertEqual(LocationFailure.from(denied), .denied)

        let unknown = NSError(domain: CLError.errorDomain,
                              code: CLError.Code.locationUnknown.rawValue)
        XCTAssertEqual(LocationFailure.from(unknown), .unavailable)

        let network = NSError(domain: CLError.errorDomain,
                              code: CLError.Code.network.rawValue)
        XCTAssertEqual(LocationFailure.from(network), .unavailable)

        // Anything else keeps its own words rather than being flattened.
        let other = NSError(domain: "SomethingElse", code: 42,
                            userInfo: [NSLocalizedDescriptionKey: "strange"])
        XCTAssertEqual(LocationFailure.from(other), .failed("strange"))
    }

    /// A fix off the globe cannot become a locator, and that is a failure
    /// with a message — not a silently empty field.
    func testAnUnconvertibleFixFails() async {
        let provider = ScriptedProvider(
            result: .success(LocationFix(latitude: 99, longitude: 0)))
        guard case .failed(let message) = await GridLocate.run(provider) else {
            return XCTFail("an impossible coordinate cannot fill the field")
        }
        XCTAssertFalse(message.isEmpty)
    }
}

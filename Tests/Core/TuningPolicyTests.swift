import XCTest
@testable import QSOPartyLogger

/// Run ⇄ S&P follows the VFO around the CQ frequency, as N1MM's does
/// (Entry window, "Run mode and S+P mode", fetched 2026-08-15): "Normally
/// when you are on your CQ-frequency you will be in Run mode and QSYing will
/// switch to S&P mode" and "if you are in S&P mode and you tune within the
/// tuning tolerance of the marker, the program will switch automatically to
/// Run mode." The leave distance is this app's own, larger than the tolerance,
/// so a QRM dodge stays in Run — Tom's "reasonable amount of vfo change".
final class TuningPolicyTests: XCTestCase {

    // MARK: Zones

    func testOnFrequencyUpToAndIncludingTheTolerance() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_000, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .onFrequency)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_300, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .onFrequency, "the boundary is inside")
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_039_700, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .onFrequency, "either side")
    }

    func testNearBetweenToleranceAndLeaveDistance() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_301, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .near)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_041_000, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .near, "the leave boundary is still near")
    }

    func testAwayBeyondTheLeaveDistance() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_041_001, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .away)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_030_000, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .away)
    }

    /// A leave distance smaller than the tolerance is treated as equal to it:
    /// `near` simply never occurs.
    func testLeaveDistanceBelowToleranceCollapsesNear() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_200, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 100), .onFrequency)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_400, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 100), .away)
    }

    // MARK: Leaving Run

    func testLeavingRunFromNearGoesToSearchPounce() {
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .near, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true),
            .searchPounce
        )
    }

    func testLeavingRunStraightFromTheFrequencyGoesToSearchPounce() {
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .onFrequency, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true),
            .searchPounce
        )
    }

    /// The QRM dodge: off the frequency but inside the leave distance is still Run.
    func testDodgingWithinTheLeaveDistanceStaysInRun() {
        XCTAssertNil(TuningPolicy.modeChange(from: .onFrequency, to: .near, mode: .run, leaveEnabled: true, returnEnabled: true))
    }

    func testLeaveOffLeavesRunAlone() {
        XCTAssertNil(TuningPolicy.modeChange(from: .near, to: .away, mode: .run, leaveEnabled: false, returnEnabled: true))
    }

    /// Already searching and moving away is nothing new.
    func testMovingAwayWhileSearchingChangesNothing() {
        XCTAssertNil(TuningPolicy.modeChange(from: .near, to: .away, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
    }

    // MARK: Returning to Run

    func testComingBackOntoTheFrequencyReturnsToRun() {
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .near, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true),
            .run
        )
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .away, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true),
            .run, "a big jump straight back — ⌘J's own path lands here too"
        )
    }

    /// N1MM's "Do not automatically switch to Run on CQ-frequency".
    func testReturnOffKeepsSearchPounce() {
        XCTAssertNil(TuningPolicy.modeChange(from: .away, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: false))
    }

    /// Approaching is not arriving.
    func testApproachingToNearDoesNotReturnToRun() {
        XCTAssertNil(TuningPolicy.modeChange(from: .away, to: .near, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
    }

    // MARK: Edge-triggered — ⌘R is never fought

    /// Switch to S&P by hand while sitting on the CQ frequency: nothing flips
    /// you back, because the zone did not change.
    func testSameZoneNeverActs() {
        XCTAssertNil(TuningPolicy.modeChange(from: .onFrequency, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
        XCTAssertNil(TuningPolicy.modeChange(from: .away, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true),
                     "Run chosen by hand five kHz away stays Run")
    }

    /// The first observation after a CQ frequency appears only records the zone.
    func testNoPreviousZoneNeverActs() {
        XCTAssertNil(TuningPolicy.modeChange(from: nil, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true))
        XCTAssertNil(TuningPolicy.modeChange(from: nil, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
    }

    // MARK: Distances

    func testDefaultsAreN1MMsForCWAndDigitalAndWiderForPhone() {
        XCTAssertEqual(TuningDistances.defaultTolerance.hz(for: .cw), 300)
        XCTAssertEqual(TuningDistances.defaultTolerance.hz(for: .digital), 300)
        XCTAssertEqual(TuningDistances.defaultTolerance.hz(for: .phone), 1000)
        XCTAssertEqual(TuningDistances.defaultLeaveRun.hz(for: .cw), 1000)
        XCTAssertEqual(TuningDistances.defaultLeaveRun.hz(for: .digital), 1000)
        XCTAssertEqual(TuningDistances.defaultLeaveRun.hz(for: .phone), 3000)
    }

    func testSetChangesOnlyThatMode() {
        var distances = TuningDistances.defaultTolerance
        distances.set(500, for: .phone)
        XCTAssertEqual(distances.hz(for: .phone), 500)
        XCTAssertEqual(distances.hz(for: .cw), 300)
        XCTAssertEqual(distances.hz(for: .digital), 300)
    }

    func testDistancesRoundTripThroughJSON() throws {
        let original = TuningDistances(cwHz: 200, phoneHz: 1500, digitalHz: 400)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(TuningDistances.self, from: data), original)
    }
}

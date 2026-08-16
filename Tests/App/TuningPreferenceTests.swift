import XCTest
@testable import QSOPartyLogger

/// The tuning preferences behind the band map's TUNING section — defaults,
/// persistence under their own keys, and the JSON round trip of the per-mode
/// distances.
final class TuningPreferenceTests: XCTestCase {

    /// A fixed suite name — `removePersistentDomain` leaves the plist behind,
    /// so a per-run UUID would litter Preferences (see PreferenceIsolationTests).
    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.tuning"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    @MainActor
    func testAnEmptyStoreHasEverythingOnAtN1MMsDistances() throws {
        let settings = AppSettings(defaults: try scratchStore())
        XCTAssertTrue(settings.callFrameEnabled)
        XCTAssertTrue(settings.autoLeaveRun)
        XCTAssertTrue(settings.autoReturnToRun)
        XCTAssertEqual(settings.tuningToleranceHz, .defaultTolerance)
        XCTAssertEqual(settings.leaveRunDistanceHz, .defaultLeaveRun)
    }

    @MainActor
    func testTheTogglesPersistUnderTheirOwnKeys() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.callFrameEnabled = false
        settings.autoLeaveRun = false
        settings.autoReturnToRun = false
        XCTAssertEqual(scratch.object(forKey: "callFrameEnabled") as? Bool, false)
        XCTAssertEqual(scratch.object(forKey: "autoLeaveRun") as? Bool, false)
        XCTAssertEqual(scratch.object(forKey: "autoReturnToRun") as? Bool, false)
        let reread = AppSettings(defaults: scratch)
        XCTAssertFalse(reread.callFrameEnabled)
        XCTAssertFalse(reread.autoLeaveRun)
        XCTAssertFalse(reread.autoReturnToRun)
    }

    @MainActor
    func testTheDistancesAreReadBackOnTheNextLaunch() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.tuningToleranceHz.set(500, for: .phone)
        settings.leaveRunDistanceHz.set(2000, for: .cw)
        XCTAssertNotNil(scratch.data(forKey: "tuningToleranceHz"))
        XCTAssertNotNil(scratch.data(forKey: "leaveRunDistanceHz"))
        let reread = AppSettings(defaults: scratch)
        XCTAssertEqual(reread.tuningToleranceHz.hz(for: .phone), 500)
        XCTAssertEqual(reread.tuningToleranceHz.hz(for: .cw), 300, "untouched modes keep their default")
        XCTAssertEqual(reread.leaveRunDistanceHz.hz(for: .cw), 2000)
    }

    /// A hand-edited or downgraded preference file falls back to the defaults
    /// rather than to nothing.
    @MainActor
    func testUnreadableDistancesFallBackToTheDefaults() throws {
        let scratch = try scratchStore(seeding: ["tuningToleranceHz": Data("garbage".utf8)])
        XCTAssertEqual(AppSettings(defaults: scratch).tuningToleranceHz, .defaultTolerance)
    }

    @MainActor
    func testNothingLeaksIntoTheAppWideStore() throws {
        let scratch = try scratchStore()
        AppSettings(defaults: scratch).callFrameEnabled = false
        XCTAssertNil(Preferences.store.object(forKey: "callFrameEnabled"),
                     "an injected store must not write through to the app-wide one")
    }
}

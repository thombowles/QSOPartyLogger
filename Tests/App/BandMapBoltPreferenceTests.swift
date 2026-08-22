import XCTest
@testable import QSOPartyLogger

/// `AppSettings.bandMapBolted` and `bandMapBoltSide` — defaults, persistence,
/// and the fallback that keeps a bolted map from ever having no side.
final class BandMapBoltPreferenceTests: XCTestCase {

    /// A fixed suite name rather than a per-run UUID — the
    /// `SpotLabelSizePreferenceTests` reasoning.
    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.bandMapBolt"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    /// Off: the map floats exactly as it always has until the operator bolts
    /// it — and when he does, it goes to the right, continuing the score
    /// sidebar's column.
    @MainActor
    func testAnEmptyStoreFloatsTheMapAndWouldBoltItOnTheRight() throws {
        let settings = AppSettings(defaults: try scratchStore())
        XCTAssertFalse(settings.bandMapBolted)
        XCTAssertEqual(settings.bandMapBoltSide, .right)
    }

    @MainActor
    func testTheBoltPersistsUnderItsOwnKeys() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.bandMapBolted = true
        settings.bandMapBoltSide = .left
        XCTAssertEqual(scratch.bool(forKey: "bandMapBolted"), true)
        XCTAssertEqual(scratch.string(forKey: "bandMapBoltSide"), "left")
    }

    @MainActor
    func testAStoredBoltIsReadBackOnTheNextLaunch() throws {
        let scratch = try scratchStore()
        let first = AppSettings(defaults: scratch)
        first.bandMapBolted = true
        first.bandMapBoltSide = .left
        let next = AppSettings(defaults: scratch)
        XCTAssertTrue(next.bandMapBolted)
        XCTAssertEqual(next.bandMapBoltSide, .left)
    }

    /// A hand-edited or downgraded preference file must not leave a bolted
    /// map with no side — it falls back to the default rather than to nothing.
    @MainActor
    func testAnUnrecognisedSideTokenFallsBackToRight() throws {
        let scratch = try scratchStore(seeding: ["bandMapBolted": true, "bandMapBoltSide": "sideways"])
        let settings = AppSettings(defaults: scratch)
        XCTAssertTrue(settings.bandMapBolted, "the bolt itself is not lost with its side")
        XCTAssertEqual(settings.bandMapBoltSide, .right)
    }

    @MainActor
    func testTheBoltDoesNotLeakIntoTheAppWideStore() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.bandMapBolted = true
        settings.bandMapBoltSide = .left
        XCTAssertNil(Preferences.store.object(forKey: "bandMapBolted"),
                     "an injected store must not write through to the app-wide one")
        XCTAssertNil(Preferences.store.object(forKey: "bandMapBoltSide"))
    }
}

import XCTest
@testable import QSOPartyLogger

/// `AppSettings.spotLabelSize` — persistence, and the fallbacks that keep the
/// band map from ever being left with no size at all.
final class SpotLabelSizePreferenceTests: XCTestCase {

    /// A fixed suite name rather than a per-run UUID: `removePersistentDomain`
    /// empties the domain but leaves the backing plist behind, so a unique name
    /// per run would litter the container's Preferences folder indefinitely.
    /// Same reasoning as `PreferenceIsolationTests`.
    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.spotLabelSize"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    @MainActor
    func testAnEmptyStoreDefaultsToSmall() throws {
        XCTAssertEqual(AppSettings(defaults: try scratchStore()).spotLabelSize, .small)
    }

    @MainActor
    func testTheChosenSizePersistsUnderItsOwnKey() throws {
        let scratch = try scratchStore()
        AppSettings(defaults: scratch).spotLabelSize = .large
        XCTAssertEqual(scratch.string(forKey: "spotLabelSize"), SpotLabelSize.large.rawValue)
    }

    @MainActor
    func testAStoredSizeIsReadBackOnTheNextLaunch() throws {
        let scratch = try scratchStore()
        AppSettings(defaults: scratch).spotLabelSize = .huge
        XCTAssertEqual(AppSettings(defaults: scratch).spotLabelSize, .huge)
    }

    /// A hand-edited or downgraded preference file must not leave the map with
    /// no size — it falls back to the default rather than to nothing.
    @MainActor
    func testAnUnrecognisedStoredTokenFallsBackToSmall() throws {
        let scratch = try scratchStore(seeding: ["spotLabelSize": "enormous"])
        XCTAssertEqual(AppSettings(defaults: scratch).spotLabelSize, .small)
    }

    @MainActor
    func testTheSizeDoesNotLeakIntoTheAppWideStore() throws {
        let scratch = try scratchStore()
        AppSettings(defaults: scratch).spotLabelSize = .medium
        XCTAssertNil(Preferences.store.object(forKey: "spotLabelSize"),
                     "an injected store must not write through to the app-wide one")
    }
}

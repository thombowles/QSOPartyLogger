import XCTest
@testable import QSOPartyLogger

/// The test bundle is hosted inside the real app executable (`TEST_HOST` in
/// `project.yml`), so `UserDefaults.standard` inside a test *is* the operator's
/// live `org.b5n.QSOPartyLogger` domain — not an ephemeral store. Every
/// preference the app persists therefore has to route through
/// `Preferences.store`, which the test bundle redirects to a throwaway suite
/// before the first test runs.
///
/// Without that, `LogDocumentTests` — which calls `updateStation` with a blank
/// `StationProfile()` a dozen times over — silently blanks the developer's
/// saved callsign, and a new log opens empty after every test run.
final class PreferenceIsolationTests: XCTestCase {

    /// The whole point: the suite must not be running against the real domain.
    func testTheSuiteRunsAgainstARedirectedStore() {
        XCTAssertFalse(
            Preferences.store === UserDefaults.standard,
            "tests must never persist into the operator's real preference domain"
        )
    }

    /// The redirect only helps if `AppSettings.shared` was built *after* it.
    /// Anything the app touches at launch — a menu item's state, a scene's
    /// binding — builds `shared` on `.standard` first, and then every write
    /// through it lands in the operator's live prefs (2026-08-15: a Help-menu
    /// Toggle did exactly that, and a full run rewrote the saved station
    /// profile). Read-only: this proves the binding without writing a byte.
    @MainActor
    func testSharedSettingsWereBuiltOnTheRedirectedStore() {
        XCTAssertTrue(
            AppSettings.shared.isBacked(by: Preferences.store),
            "AppSettings.shared was built before TestBundleSetup redirected the store — "
                + "something touches it at app launch; every shared write is going to the real domain"
        )
        XCTAssertFalse(AppSettings.shared.isBacked(by: UserDefaults.standard))
    }

    /// The regression, stated behaviourally: a setup change writes the profile
    /// somewhere, and that somewhere is not the operator's real preferences.
    @MainActor
    func testUpdatingTheStationLeavesTheRealProfileAlone() throws {
        var sentinel = StationProfile()
        sentinel.callsign = "KE5CW"
        let seed = try JSONEncoder().encode(sentinel)

        let original = UserDefaults.standard.data(forKey: "lastStationProfile")
        UserDefaults.standard.set(seed, forKey: "lastStationProfile")
        defer {
            // A complete restore: `lastStationProfile`'s didSet only writes when
            // non-nil, so putting back `nil` would not clear a value written
            // over the top of it.
            if let original {
                UserDefaults.standard.set(original, forKey: "lastStationProfile")
            } else {
                UserDefaults.standard.removeObject(forKey: "lastStationProfile")
            }
        }

        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: nil
        )

        let survivor = try XCTUnwrap(UserDefaults.standard.data(forKey: "lastStationProfile"))
        XCTAssertEqual(
            try JSONDecoder().decode(StationProfile.self, from: survivor).callsign, "KE5CW",
            "a test writing a blank profile must not blank the real saved callsign"
        )
    }

    /// …and the write still lands somewhere, so the redirect isn't just
    /// swallowing persistence wholesale.
    @MainActor
    func testUpdatingTheStationStillPersistsIntoTheRedirectedStore() throws {
        var profile = StationProfile()
        profile.callsign = "W1AW"

        let doc = LogDocument()
        doc.updateStation(
            profile, location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: nil
        )

        let saved = try XCTUnwrap(Preferences.store.data(forKey: "lastStationProfile"))
        XCTAssertEqual(
            try JSONDecoder().decode(StationProfile.self, from: saved).callsign, "W1AW"
        )
        XCTAssertEqual(LogDocument.savedStationProfile()?.callsign, "W1AW",
                       "the read path must come from the same store as the write path")
    }

    /// `AppSettings` takes its store by injection, so a settings object can be
    /// exercised against a scratch suite with no globals involved at all.
    @MainActor
    func testAppSettingsReadsAndWritesTheStoreItWasGiven() throws {
        // A fixed name, not a per-run UUID: `removePersistentDomain` empties the
        // domain but leaves the backing plist behind, so a unique name per run
        // would litter the container's Preferences folder indefinitely.
        let suiteName = "org.b5n.QSOPartyLogger.tests.scratch"
        UserDefaults().removePersistentDomain(forName: suiteName)
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        let settings = AppSettings(defaults: scratch)
        settings.wpm = 31
        XCTAssertEqual(scratch.object(forKey: "wpm") as? Int, 31)

        // A second instance over the same suite sees it; the shared one does not.
        XCTAssertEqual(AppSettings(defaults: scratch).wpm, 31)
        XCTAssertNil(Preferences.store.object(forKey: "wpm"),
                     "an injected store must not leak into the app-wide one")
    }

    /// `CloudMirror` persists its folder bookmark the same way, so
    /// `CloudMirrorTests`' teardown cannot delete a real iCloud folder setting.
    func testCloudMirrorConfigurationIsNotReadFromTheRealDomain() {
        let realBookmark = UserDefaults.standard.data(forKey: "iCloudFolderBookmark")
        UserDefaults.standard.removeObject(forKey: "iCloudFolderBookmark")
        defer {
            if let realBookmark {
                UserDefaults.standard.set(realBookmark, forKey: "iCloudFolderBookmark")
            }
        }

        Preferences.store.set(Data("not-a-real-bookmark".utf8), forKey: "iCloudFolderBookmark")
        defer { Preferences.store.removeObject(forKey: "iCloudFolderBookmark") }

        XCTAssertTrue(CloudMirror.isConfigured,
                      "CloudMirror must read the redirected store, not the real domain")
    }
}

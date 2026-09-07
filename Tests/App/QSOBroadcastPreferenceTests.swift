import XCTest
@testable import QSOPartyLogger

/// The three preferences behind the RUMlog pane — off by default, RUMlogNG
/// on this Mac at N1MM's port, each under its own key, a bad port healed.
final class QSOBroadcastPreferenceTests: XCTestCase {

    /// A fixed suite name — `removePersistentDomain` leaves the plist behind,
    /// so a per-run UUID would litter Preferences (see PreferenceIsolationTests).
    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.qsobroadcast"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    @MainActor
    func testAnEmptyStoreIsOffAndAimedAtRUMlogOnThisMac() throws {
        let settings = AppSettings(defaults: try scratchStore())
        XCTAssertFalse(settings.qsoBroadcastEnabled)
        XCTAssertEqual(settings.qsoBroadcastHost, "127.0.0.1")
        XCTAssertEqual(settings.qsoBroadcastPort, 12060)
        XCTAssertEqual(settings.qsoBroadcast, QSOBroadcaster.Config(enabled: false, host: "127.0.0.1", port: 12060))
    }

    @MainActor
    func testTheValuesPersistUnderTheirOwnKeys() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.qsoBroadcastEnabled = true
        settings.qsoBroadcastHost = "192.168.1.255"
        settings.qsoBroadcastPort = 12061
        XCTAssertEqual(scratch.object(forKey: "qsoBroadcastEnabled") as? Bool, true)
        XCTAssertEqual(scratch.string(forKey: "qsoBroadcastHost"), "192.168.1.255")
        XCTAssertEqual(scratch.object(forKey: "qsoBroadcastPort") as? Int, 12061)
        let reread = AppSettings(defaults: scratch)
        XCTAssertEqual(reread.qsoBroadcast, QSOBroadcaster.Config(enabled: true, host: "192.168.1.255", port: 12061))
    }

    @MainActor
    func testAStoredPortOutsideTheRangeFallsBackToN1MMs() throws {
        XCTAssertEqual(AppSettings(defaults: try scratchStore(seeding: ["qsoBroadcastPort": 0])).qsoBroadcastPort, 12060)
        XCTAssertEqual(AppSettings(defaults: try scratchStore(seeding: ["qsoBroadcastPort": 70000])).qsoBroadcastPort, 12060)
    }
}

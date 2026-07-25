import XCTest
@testable import QSOPartyLogger

/// Principal class of the test bundle (`INFOPLIST_KEY_NSPrincipalClass` in
/// `project.yml`). XCTest instantiates it as the bundle loads — before any test
/// runs, and before anything can touch the lazily-built `AppSettings.shared`.
/// That is the only point where the redirect is guaranteed to beat every suite
/// regardless of the order they run in.
///
/// It matters because the bundle is hosted inside the real app executable
/// (`TEST_HOST`/`BUNDLE_LOADER`), so an unredirected `UserDefaults.standard`
/// here is the operator's live `org.b5n.QSOPartyLogger` domain: the setup tests
/// in `LogDocumentTests` call `updateStation` with a blank `StationProfile()`,
/// which used to blank the real saved callsign and leave the next new log empty.
@objc(TestBundleSetup)
final class TestBundleSetup: NSObject, XCTestObservation {

    /// Wiped at both ends of the run, so no test inherits state from the last
    /// run and nothing is left behind on disk afterwards.
    private static let suiteName = "org.b5n.QSOPartyLogger.tests"

    override init() {
        super.init()
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
        guard let suite = UserDefaults(suiteName: Self.suiteName) else {
            // Never fall through to `.standard`: that is the operator's real
            // preferences, and the damage is silent.
            fatalError("could not open the \(Self.suiteName) preference suite")
        }
        Preferences.redirect(to: suite)
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    func testBundleDidFinish(_ testBundle: Bundle) {
        UserDefaults().removePersistentDomain(forName: Self.suiteName)
    }
}

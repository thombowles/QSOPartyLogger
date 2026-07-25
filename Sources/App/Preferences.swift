import Foundation

/// The `UserDefaults` this app persists preferences into.
///
/// Production is always `.standard`. The unit-test bundle, though, is hosted
/// inside the real app executable (`TEST_HOST`/`BUNDLE_LOADER` in
/// `project.yml`), so `.standard` inside a test is the operator's live
/// `org.b5n.QSOPartyLogger` domain and not an ephemeral store: a test that
/// saved a blank `StationProfile` would blank their real callsign, and the next
/// new log would open empty.
///
/// So every preference read and write goes through `store` rather than naming
/// `.standard` directly, and the test bundle redirects it to a throwaway suite
/// before the first test runs (`TestBundleSetup`). Doing it once, globally,
/// rather than per-suite is deliberate: a redirect that each test has to
/// remember is one a future test will forget, and the damage is silent.
enum Preferences {

    nonisolated(unsafe) private(set) static var store: UserDefaults = .standard

    /// Point every preference read and write at `defaults`. Called once by the
    /// test bundle's principal class before any test runs; never by app code.
    nonisolated static func redirect(to defaults: UserDefaults) {
        store = defaults
    }
}

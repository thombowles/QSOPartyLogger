import XCTest
@testable import QSOPartyLogger

/// The caching store's contract — what makes a mid-contest keychain prompt
/// impossible: the backing keychain is read at most once per credential per
/// run (misses and denials included), a first hit heals the item's
/// ownership exactly once, and writes keep the cache honest.
final class CachingCredentialStoreTests: XCTestCase {

    /// Counts every touch of the backing store.
    final class SpyStore: CredentialStore {
        var reads = 0
        var writes = 0
        var deletes = 0
        var values: [String: String] = [:]
        func password(service: String, account: String) -> String? {
            reads += 1
            return values["\(service)|\(account)"]
        }
        func set(_ password: String, service: String, account: String) {
            writes += 1
            values["\(service)|\(account)"] = password
        }
        func delete(service: String, account: String) {
            deletes += 1
            values.removeValue(forKey: "\(service)|\(account)")
        }
    }

    func testReadsTheBackingStoreOncePerCredential() {
        let spy = SpyStore()
        spy.values["S|a"] = "hunter2"
        let store = CachingCredentialStore(backend: spy)
        XCTAssertEqual(store.password(service: "S", account: "a"), "hunter2")
        XCTAssertEqual(store.password(service: "S", account: "a"), "hunter2")
        XCTAssertEqual(store.password(service: "S", account: "a"), "hunter2")
        XCTAssertEqual(spy.reads, 1, "an hourly session renewal must never reach the keychain")
    }

    func testFirstHitHealsTheItemOwnershipExactlyOnce() {
        let spy = SpyStore()
        spy.values["S|a"] = "hunter2"
        let store = CachingCredentialStore(backend: spy)
        _ = store.password(service: "S", account: "a")
        _ = store.password(service: "S", account: "a")
        XCTAssertEqual(spy.writes, 1, "one rewrite makes this binary the item's owner")
        XCTAssertEqual(spy.values["S|a"], "hunter2", "the heal writes the same value back")
    }

    func testAMissIsCachedForTheRun() {
        let spy = SpyStore()
        let store = CachingCredentialStore(backend: spy)
        XCTAssertNil(store.password(service: "S", account: "a"))
        XCTAssertNil(store.password(service: "S", account: "a"))
        XCTAssertEqual(spy.reads, 1, "a denied or absent item must not ask again this run")
        XCTAssertEqual(spy.writes, 0, "nothing to heal on a miss")
    }

    func testSetWritesThroughAndFeedsTheCache() {
        let spy = SpyStore()
        let store = CachingCredentialStore(backend: spy)
        XCTAssertNil(store.password(service: "S", account: "a"))
        store.set("fresh", service: "S", account: "a")
        XCTAssertEqual(store.password(service: "S", account: "a"), "fresh")
        XCTAssertEqual(spy.reads, 1, "the set fed the cache; no re-read, no stale negative")
    }

    func testDeleteClearsBothStores() {
        let spy = SpyStore()
        let store = CachingCredentialStore(backend: spy)
        store.set("gone", service: "S", account: "a")
        store.delete(service: "S", account: "a")
        XCTAssertNil(store.password(service: "S", account: "a"))
        XCTAssertNil(spy.values["S|a"])
    }

    func testInvalidateForcesOneFreshRead() {
        let spy = SpyStore()
        let store = CachingCredentialStore(backend: spy)
        XCTAssertNil(store.password(service: "S", account: "a"))
        spy.values["S|a"] = "fixed-in-keychain-access"
        store.invalidate(service: "S", account: "a")
        XCTAssertEqual(store.password(service: "S", account: "a"), "fixed-in-keychain-access",
                       "the settings pane's Check must see the world as it is now")
    }

    func testAccountsAndServicesAreDistinct() {
        let spy = SpyStore()
        spy.values["S|a"] = "one"
        spy.values["S|b"] = "two"
        spy.values["T|a"] = "three"
        let store = CachingCredentialStore(backend: spy)
        XCTAssertEqual(store.password(service: "S", account: "a"), "one")
        XCTAssertEqual(store.password(service: "S", account: "b"), "two")
        XCTAssertEqual(store.password(service: "T", account: "a"), "three")
        XCTAssertEqual(spy.reads, 3)
    }
}

/// The window's deliberate first touch: any prompt a new binary will ever
/// raise happens at window-open, never mid-pileup.
final class CallbookPrewarmTests: XCTestCase {

    @MainActor
    func testPrewarmReadsExactlyTheEnabledServices() {
        let spy = CachingCredentialStoreTests.SpyStore()
        let client = CallbookClient(credentials: spy, configuration: {
            .init(qrzEnabled: true, qrzUsername: "KE5CW",
                  hamqthEnabled: false, hamqthUsername: "", primary: nil)
        })
        client.prewarmCredentials()
        XCTAssertEqual(spy.reads, 1, "QRZ only — HamQTH is off")
    }

    @MainActor
    func testPrewarmIsSilentWithNothingEnabled() {
        let spy = CachingCredentialStoreTests.SpyStore()
        let client = CallbookClient(credentials: spy, configuration: {
            .init(qrzEnabled: false, qrzUsername: "",
                  hamqthEnabled: false, hamqthUsername: "", primary: nil)
        })
        client.prewarmCredentials()
        XCTAssertEqual(spy.reads, 0)
    }
}

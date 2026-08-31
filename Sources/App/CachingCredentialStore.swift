import Foundation
import os

/// A per-run cache over the keychain, and the reason a mid-contest keychain
/// prompt cannot recur (KSQP operator report, 2026-08-31): each credential
/// is read from the backing store at most once per run — misses and denials
/// included — so HamQTH's hourly session renewals and QRZ's idle re-logins
/// reuse the in-memory copy and never touch the keychain again.
///
/// On the first successful read the item is rewritten once, making the
/// running binary its owner. Under ad-hoc signing every rebuilt copy is a
/// new identity that an old "Always Allow" cannot cover, but an item this
/// binary created reads silently — so a given build asks at most once,
/// ever, and `CallbookClient.prewarmCredentials` places that one ask at
/// window-open rather than mid-pileup.
final class CachingCredentialStore: CredentialStore, @unchecked Sendable {
    /// One cache for the app: the settings pane's writes and the lookup
    /// client's reads must see each other, or a freshly saved password
    /// would sit behind a stale miss until relaunch.
    static let shared = CachingCredentialStore(backend: KeychainStore())

    private let backend: CredentialStore

    /// Cached answers, misses included — `.some(nil)` is "asked, nothing
    /// there (or access denied)", which must not ask again this run.
    private let state = OSAllocatedUnfairLock<[String: String?]>(initialState: [:])

    init(backend: CredentialStore) {
        self.backend = backend
    }

    func password(service: String, account: String) -> String? {
        let key = "\(service)|\(account)"
        if let cached = state.withLock({ $0[key] }) { return cached }
        // Deliberately outside the lock: this read can block on the user's
        // answer to a keychain prompt.
        let read = backend.password(service: service, account: account)
        if let value = read {
            // The one self-heal — this binary becomes the item's owner, so
            // the next launch of this same build reads without asking.
            backend.set(value, service: service, account: account)
        }
        state.withLock { $0[key] = .some(read) }
        return read
    }

    func set(_ password: String, service: String, account: String) {
        backend.set(password, service: service, account: account)
        state.withLock { $0["\(service)|\(account)"] = .some(password) }
    }

    func delete(service: String, account: String) {
        backend.delete(service: service, account: account)
        state.withLock { $0["\(service)|\(account)"] = .some(nil) }
    }

    func invalidate(service: String, account: String) {
        state.withLock { $0.removeValue(forKey: "\(service)|\(account)") }
    }
}

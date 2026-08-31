import Foundation
import Security

/// Where lookup credentials live — behind a protocol so no test ever
/// touches the login keychain (the test host would prompt, and pollute).
protocol CredentialStore: AnyObject {
    func password(service: String, account: String) -> String?
    func set(_ password: String, service: String, account: String)
    func delete(service: String, account: String)
    /// Forget any cached answer for this credential, so the next read asks
    /// the backing store again — the settings pane's Check button, after
    /// the operator fixed things outside the app. A requirement (with the
    /// no-op default below) so it dispatches through the existential.
    func invalidate(service: String, account: String)
}

extension CredentialStore {
    /// A plain store has no cache to forget.
    func invalidate(service: String, account: String) {}
}

/// The real store: one generic-password item per lookup service in the
/// login keychain. Reached through `CachingCredentialStore.shared` in the
/// app, which is what keeps the ad-hoc signing churn (a rebuilt binary is a
/// new identity to the keychain) down to at most one ask per build, at
/// window-open. Spec 2026-08-25 decision 7; KSQP operator report 2026-08-31.
final class KeychainStore: CredentialStore {
    func password(service: String, account: String) -> String? {
        var query = base(service: service, account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    func set(_ password: String, service: String, account: String) {
        delete(service: service, account: account)
        var attributes = base(service: service, account: account)
        attributes[kSecValueData as String] = Data(password.utf8)
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func delete(service: String, account: String) {
        SecItemDelete(base(service: service, account: account) as CFDictionary)
    }

    private func base(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}

/// Test double — what the client tests inject.
final class InMemoryCredentialStore: CredentialStore {
    private var values: [String: String] = [:]
    func password(service: String, account: String) -> String? {
        values["\(service)|\(account)"]
    }
    func set(_ password: String, service: String, account: String) {
        values["\(service)|\(account)"] = password
    }
    func delete(service: String, account: String) {
        values.removeValue(forKey: "\(service)|\(account)")
    }
}

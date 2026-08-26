import Foundation
import Observation

enum CallbookService: String, CaseIterable, Sendable {
    case qrz, hamqth
    var label: String { self == .qrz ? "QRZ" : "HamQTH" }
    var keychainService: String { "QSOPartyLogger \(label)" }
}

protocol CallbookFetching: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct URLSessionCallbookFetcher: CallbookFetching {
    private let session: URLSession
    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpAdditionalHeaders = [
            "User-Agent": "QSOPartyLogger/1.5 (+https://github.com/KE5CW) macOS"
        ]
        session = URLSession(configuration: config)
    }
    func get(_ url: URL) async throws -> Data {
        try await session.data(from: url).0
    }
}

/// Callbook lookups (spec 2026-08-25 decisions 6 and 8): cache first, then
/// the primary service, then the other on miss or error; sessions per each
/// service's own contract — QRZ's key cached and reused with a single
/// re-login on `Session Timeout` (per-lookup logins earn their 24-hour
/// refusal, which backs the service off for a day), HamQTH's id renewed on
/// its documented one-hour clock. A lookup failure is a caption that does
/// not appear — never a modal, never a block on the entry path.
@MainActor
@Observable
final class CallbookClient {
    struct Configuration {
        var qrzEnabled: Bool
        var qrzUsername: String
        var hamqthEnabled: Bool
        var hamqthUsername: String
        var primary: CallbookService?
    }

    /// The record for the call most recently looked up — what the caption
    /// renders. Cleared when the call in the field stops matching it.
    private(set) var record: CallbookRecord?
    private(set) var console: [String] = []

    static let agent = "QSOPartyLogger/1.5"
    static let program = "QSOPartyLogger"

    private let fetcher: CallbookFetching
    private let credentials: CredentialStore
    private let cache: CallbookCache
    private let configuration: () -> Configuration

    private var qrzSessionKey: String?
    private var qrzRefusedUntil: Date?
    private var hamqthSession: (id: String, obtainedAt: Date)?
    private var debounceTask: Task<Void, Never>?

    init(fetcher: CallbookFetching = URLSessionCallbookFetcher(),
         credentials: CredentialStore = KeychainStore(),
         cache: CallbookCache = CallbookCache(),
         configuration: @escaping () -> Configuration) {
        self.fetcher = fetcher
        self.credentials = credentials
        self.cache = cache
        self.configuration = configuration
    }

    /// A call is worth a request once it could be someone: three or more
    /// characters including a digit. Cheap enough to be wrong about — a
    /// miss is silence, and the cache eats repeats.
    static func isPlausibleCall(_ call: String) -> Bool {
        let c = call.trimmingCharacters(in: .whitespaces)
        return c.count >= 3 && c.contains(where: \.isNumber)
    }

    /// The entry path's entry point: debounced 600 ms, cancelled by the
    /// next keystroke, silent for implausible calls.
    func noteCallChanged(_ call: String) {
        debounceTask?.cancel()
        let wanted = call.trimmingCharacters(in: .whitespaces).uppercased()
        if record?.call != wanted { record = nil }
        guard Self.isPlausibleCall(wanted) else { return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            await self?.lookup(call: wanted)
        }
    }

    /// Cache, then primary, then the other. Publishes the answer for the
    /// caption and returns it.
    @discardableResult
    func lookup(call rawCall: String) async -> CallbookRecord? {
        let call = rawCall.trimmingCharacters(in: .whitespaces).uppercased()
        guard !call.isEmpty else { return nil }
        if let hit = cache.record(for: call) {
            record = hit
            return hit
        }
        let config = configuration()
        for service in order(config) {
            if let found = await lookup(call: call, via: service, config: config) {
                cache.store(found)
                record = found
                return found
            }
        }
        return nil
    }

    /// One live session request — the settings pane's Check button.
    /// Returns a short human sentence for the inline status.
    func checkCredentials(_ service: CallbookService) async -> String {
        let config = configuration()
        switch service {
        case .qrz:
            qrzSessionKey = nil
            qrzRefusedUntil = nil
            let ok = await qrzLogin(config: config)
            return ok ? "QRZ accepted the login."
                      : (console.last ?? "QRZ did not accept the login.")
        case .hamqth:
            hamqthSession = nil
            let ok = await hamqthLogin(config: config)
            return ok ? "HamQTH accepted the login."
                      : (console.last ?? "HamQTH did not accept the login.")
        }
    }

    // MARK: Internals

    /// The services to try, in order: the enabled ones, the chosen primary
    /// first — HamQTH by default when both are on (spec decision 6: the
    /// free QRZ tier is name-only, HamQTH is free and full).
    private func order(_ config: Configuration) -> [CallbookService] {
        let enabled = CallbookService.allCases.filter {
            switch $0 {
            case .qrz: config.qrzEnabled && !config.qrzUsername.isEmpty
            case .hamqth: config.hamqthEnabled && !config.hamqthUsername.isEmpty
            }
        }
        guard enabled.count > 1 else { return enabled }
        let first = config.primary ?? .hamqth
        return [first] + enabled.filter { $0 != first }
    }

    private func log(_ line: String) {
        console.append(line)
        if console.count > 200 { console.removeFirst(console.count - 200) }
    }

    private func lookup(call: String, via service: CallbookService,
                        config: Configuration) async -> CallbookRecord? {
        switch service {
        case .qrz: return await qrzLookup(call: call, config: config, retried: false)
        case .hamqth: return await hamqthLookup(call: call, config: config, retried: false)
        }
    }

    private func qrzLogin(config: Configuration) async -> Bool {
        if let until = qrzRefusedUntil, until > Date() { return false }
        guard let password = credentials.password(
            service: CallbookService.qrz.keychainService,
            account: config.qrzUsername) else {
            log("QRZ: no stored password")
            return false
        }
        do {
            let data = try await fetcher.get(QRZXML.loginURL(
                username: config.qrzUsername, password: password, agent: Self.agent))
            let session = try QRZXML.session(from: data)
            if QRZXML.isRefusal(session.error) {
                qrzRefusedUntil = Date().addingTimeInterval(86_400)
                log("QRZ: connection refused — backing off for 24 h")
                return false
            }
            guard let key = session.key else {
                log("QRZ: \(session.error ?? "no session key")")
                return false
            }
            qrzSessionKey = key
            if let message = session.message { log("QRZ: \(message)") }
            return true
        } catch {
            log("QRZ: \(error.localizedDescription)")
            return false
        }
    }

    private func qrzLookup(call: String, config: Configuration,
                           retried: Bool) async -> CallbookRecord? {
        if qrzSessionKey == nil {
            guard await qrzLogin(config: config) else { return nil }
        }
        guard let key = qrzSessionKey else { return nil }
        do {
            let data = try await fetcher.get(QRZXML.lookupURL(sessionKey: key, call: call))
            let result = try QRZXML.lookup(from: data)
            if let found = result.record { return found }
            if QRZXML.isSessionExpiry(result.error), !retried {
                // The one documented re-login: the key expired, not us.
                qrzSessionKey = nil
                return await qrzLookup(call: call, config: config, retried: true)
            }
            if QRZXML.isRefusal(result.error) {
                qrzRefusedUntil = Date().addingTimeInterval(86_400)
                log("QRZ: connection refused — backing off for 24 h")
            } else if let error = result.error, !QRZXML.isNotFound(error) {
                log("QRZ: \(error)")
            }
            return nil
        } catch {
            log("QRZ: \(error.localizedDescription)")
            return nil
        }
    }

    private func hamqthLogin(config: Configuration) async -> Bool {
        guard let password = credentials.password(
            service: CallbookService.hamqth.keychainService,
            account: config.hamqthUsername) else {
            log("HamQTH: no stored password")
            return false
        }
        do {
            let data = try await fetcher.get(HamQTHXML.loginURL(
                username: config.hamqthUsername, password: password))
            let session = try HamQTHXML.session(from: data)
            guard let id = session.id else {
                log("HamQTH: \(session.error ?? "no session id")")
                return false
            }
            hamqthSession = (id, Date())
            return true
        } catch {
            log("HamQTH: \(error.localizedDescription)")
            return false
        }
    }

    private func hamqthLookup(call: String, config: Configuration,
                              retried: Bool) async -> CallbookRecord? {
        // The documented one-hour clock, renewed a minute early.
        if let session = hamqthSession,
           Date().timeIntervalSince(session.obtainedAt) > HamQTHXML.sessionLifetime - 60 {
            hamqthSession = nil
        }
        if hamqthSession == nil {
            guard await hamqthLogin(config: config) else { return nil }
        }
        guard let session = hamqthSession else { return nil }
        do {
            let data = try await fetcher.get(HamQTHXML.lookupURL(
                sessionID: session.id, call: call, program: Self.program))
            let result = try HamQTHXML.lookup(from: data)
            if let found = result.record { return found }
            if HamQTHXML.isSessionExpiry(result.error), !retried {
                hamqthSession = nil
                return await hamqthLookup(call: call, config: config, retried: true)
            }
            if let error = result.error, !HamQTHXML.isNotFound(error) {
                log("HamQTH: \(error)")
            }
            return nil
        } catch {
            log("HamQTH: \(error.localizedDescription)")
            return nil
        }
    }
}

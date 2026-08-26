import Foundation

/// QRZ.com XML interface — spec v1.34 (live servers stamp 1.36; the version
/// is data, never a gate). Contract banked in
/// docs/research/callbook/SOURCES.md: session keys have no guaranteed
/// lifetime and are cached and reused ("clients should cache all session
/// keys … and reuse them until they expire"); errors and the non-subscriber
/// Message ride inside `<Session>` beside valid data, so every response is
/// checked; `land`/`dxcc` is the entity, `country` the QSL mailing address.
enum QRZXML {
    struct Session: Equatable {
        let key: String?
        let error: String?
        let message: String?
    }

    struct LookupResult: Equatable {
        let record: CallbookRecord?
        let error: String?
        let message: String?
    }

    static func session(from data: Data) throws -> Session {
        let scan = try CallbookXMLScanner.scan(data)
        return Session(key: scan.values["key"],
                       error: scan.values["error"],
                       message: scan.values["message"])
    }

    static func lookup(from data: Data, now: Date = Date()) throws -> LookupResult {
        let scan = try CallbookXMLScanner.scan(data)
        guard scan.wrappers.contains("callsign"), let call = scan.values["call"] else {
            return LookupResult(record: nil, error: scan.values["error"],
                                message: scan.values["message"])
        }
        let assembled = [scan.values["fname"], scan.values["name"]]
            .compactMap { $0 }.joined(separator: " ")
        let record = CallbookRecord(
            call: call.uppercased(),
            name: scan.values["name_fmt"] ?? (assembled.isEmpty ? nil : assembled),
            qth: scan.values["addr2"],
            state: scan.values["state"],
            county: scan.values["county"],
            grid: scan.values["grid"],
            country: scan.values["land"],
            dxccID: scan.values["dxcc"].flatMap(Int.init),
            source: .qrz,
            fetchedAt: now
        )
        return LookupResult(record: record, error: scan.values["error"],
                            message: scan.values["message"])
    }

    /// "Should a session expire or become invalidated, the Key field will
    /// not be sent" — the one condition worth a single re-login.
    static func isSessionExpiry(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("session timeout") ?? false
    }

    static func isNotFound(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("not found") ?? false
    }

    /// "Connection refused … indicates that successful login will not be
    /// possible for at least 24 hours" — the client backs off for a day.
    static func isRefusal(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("connection refused") ?? false
    }

    static func loginURL(username: String, password: String, agent: String) -> URL {
        CallbookQuery.url(base: "https://xmldata.qrz.com/xml/current/", items: [
            ("username", username), ("password", password), ("agent", agent),
        ])
    }

    static func lookupURL(sessionKey: String, call: String) -> URL {
        CallbookQuery.url(base: "https://xmldata.qrz.com/xml/current/", items: [
            ("s", sessionKey), ("callsign", call),
        ])
    }
}

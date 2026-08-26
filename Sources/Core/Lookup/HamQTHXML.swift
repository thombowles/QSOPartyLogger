import Foundation

/// HamQTH.com XML callbook — docs at hamqth.com/developers.php, banked in
/// docs/research/callbook/SOURCES.md: "Session ID is valid for one hour";
/// `prg` names this program on every lookup; elements are lowercase; https
/// only ("http … is only for backward compatibility").
enum HamQTHXML {
    struct Session: Equatable {
        let id: String?
        let error: String?
    }

    struct LookupResult: Equatable {
        let record: CallbookRecord?
        let error: String?
    }

    /// The documented lifetime, verbatim: "Session ID is valid for one hour."
    static let sessionLifetime: TimeInterval = 3600

    static func session(from data: Data) throws -> Session {
        let scan = try CallbookXMLScanner.scan(data)
        return Session(id: scan.values["session_id"], error: scan.values["error"])
    }

    static func lookup(from data: Data, now: Date = Date()) throws -> LookupResult {
        let scan = try CallbookXMLScanner.scan(data)
        guard scan.wrappers.contains("search"), let call = scan.values["callsign"] else {
            return LookupResult(record: nil, error: scan.values["error"])
        }
        let record = CallbookRecord(
            call: call.uppercased(),
            name: scan.values["nick"] ?? scan.values["adr_name"],
            qth: scan.values["qth"],
            state: scan.values["us_state"],
            county: scan.values["us_county"],
            grid: scan.values["grid"],
            country: scan.values["country"],
            dxccID: scan.values["adif"].flatMap(Int.init),
            source: .hamqth,
            fetchedAt: now
        )
        return LookupResult(record: record, error: scan.values["error"])
    }

    static func isSessionExpiry(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("session does not exist") ?? false
    }

    static func isNotFound(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("callsign not found") ?? false
    }

    static func loginURL(username: String, password: String) -> URL {
        CallbookQuery.url(base: "https://www.hamqth.com/xml.php", items: [
            ("u", username), ("p", password),
        ])
    }

    static func lookupURL(sessionID: String, call: String, program: String) -> URL {
        CallbookQuery.url(base: "https://www.hamqth.com/xml.php", items: [
            ("id", sessionID), ("callsign", call), ("prg", program),
        ])
    }
}

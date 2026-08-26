# Callbook Lookup Implementation Plan (phase 2 of the 2026-08-25 spec)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Status (2026-08-25):** executed through Task 6 on branch `callbook`,
inline. Suite: 3190 tests, 2 skipped (the opt-in recorders), 0 failures.
Deviations: (1) the URL builders use a strict manual query encoder
(`CallbookQuery`, unreserved characters only) rather than `URLComponents`,
which leaves `/` and `;` query-legal while QRZ's separators are exactly
those — the plan anticipated this fork and the tests pin it; (2) Task 2's
cache was written test-and-implementation together (its red would have been
a compile failure; noted for honesty); (3) the settings pane gained a
footer sentence about keychain saves and the monthly cache — copy, not
behavior. Everything else landed as written.

**Goal:** QRZ.com and HamQTH.com callsign lookup — an advisory info line by
the call field in every log, and name/state/grid/QTH stamped into POTA-log
QSOs — with credentials in the Keychain and both services driven by their
own documented session contracts.

**Architecture:** Pure XML parsers and URL builders in `Sources/Core/Lookup/`
(Foundation `XMLParser`, no network); a disk cache with a 30-day TTL; an
`@MainActor @Observable CallbookClient` in `Sources/App/` owning sessions,
debounce/cancel, primary-then-fallback order and a 24-hour QRZ refusal
backoff, behind the repo's standard injected-fetcher seam; a `KeychainStore`
behind a `CredentialStore` protocol (first Keychain use in the app);
UI = a toolbar popover for credentials (the cluster popover's pattern) and a
quiet caption line under the call field (the park caption's pattern).
Spec decisions 4–8 govern; nothing ever writes a received exchange field.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Security.framework (SecItem),
XcodeGen. Base: master `721f955` (phase 1 merged).

**Verification command:**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tail -25
```

**Standing rules:** worktree first (`git worktree add .claude/worktrees/callbook -b callbook master`
+ EnterWorktree by path, xcodegen inside); `xcodegen generate` after every
new file before building; golden corpus and export fixtures untouched —
existing logs carry no `callbook` sidecar, so every existing export is
byte-identical by construction; tests never open the network or the real
Keychain.

**Facts the implementation is built on** (research fetched 2026-08-24, to be
re-fetched and banked in Task 0; the client MUST honor these):
- QRZ: login `https://xmldata.qrz.com/xml/current/?username=U;password=P;agent=A`,
  lookup `?s=KEY;callsign=C`. Session keys have **no guaranteed lifetime** —
  cache and reuse, re-login only on the `Session Timeout` error; a
  per-lookup login pattern triggers `Connection refused`, their 24-hour
  refusal. Errors AND the non-subscriber `Message` ride inside `<Session>`
  beside valid data — check every response. `land`/`dxcc` is the DXCC
  entity; `country` is the QSL mailing address. Elements Capitalized; live
  `version="1.36"` vs spec doc 1.34 — version is data, never a gate.
- HamQTH: login `https://www.hamqth.com/xml.php?u=U&p=P`, lookup
  `?id=SESSION&callsign=C&prg=PROGRAM`. Session id valid **one hour**;
  `prg` required; errors as `<session><error>…`; elements lowercase; free.
- Both XML-only; passwords must be percent-encoded into the query.

---

### Task 0: Provenance — `docs/research/callbook/SOURCES.md`

- [ ] **Step 1: Fetch the two official documents**

WebFetch `https://www.qrz.com/docs/xml/current_spec.html` and
`https://www.hamqth.com/developers.php`. Extract verbatim: QRZ's login/lookup
URL examples, the "no guaranteed lifetime" and cache-and-reuse sentences, the
`Session Timeout` / `Connection refused` error semantics and the 24-hour
sentence, the non-subscriber wording ("limits the data fields … testing and
troubleshooting purposes only"), the `agent=` recommendation, and the
callsign field list; HamQTH's session request example, the exact "Session ID
is valid for one hour" sentence, the `prg` parameter description, the error
strings (`Wrong user name or password`, `Session does not exist or expired`,
`Callsign not found`), and the "free of charge and doesn't have any limits"
sentence. **STOP** if the session semantics differ from the facts above.

- [ ] **Step 2: Write `docs/research/callbook/SOURCES.md`**

Follow `docs/research/pota/SOURCES.md`'s structure: one section per service —
official URL, fetch date 2026-08-25, the verbatim quotes, a field table
flagging what matters for logging (QRZ: `fname`/`name`/`name_fmt`, `grid`,
`state`, `county`, `addr2` (city), `land`+`dxcc`, `email`; HamQTH: `nick`,
`grid`, `us_state`, `us_county`, `qth`, `country`+`adif`), the parsing notes
(root elements `QRZDatabase` xmlns `http://xmldata.qrz.com` / `HamQTH` xmlns
`https://www.hamqth.com`, both live-verified 2026-08-24; case conventions;
version drift), and a "What this bakes into the app" list. Record the one
**OPEN QUESTION**: QRZ does not enumerate the free tier's field set — the
operator's account (free) will show whatever it shows; nothing in the app
assumes a specific reduced set.

- [ ] **Step 3: Commit**

```bash
git add docs/research/callbook/SOURCES.md
git commit -m "docs: bank the QRZ and HamQTH interface contracts"
```

---

### Task 1: `CallbookRecord`, the two parsers, and the URL builders

**Files:**
- Create: `Sources/Core/Lookup/CallbookRecord.swift`
- Create: `Sources/Core/Lookup/QRZXML.swift`
- Create: `Sources/Core/Lookup/HamQTHXML.swift`
- Create: `Sources/Core/Lookup/CallbookXMLScanner.swift`
- Create: `Tests/Core/CallbookParserTests.swift`

- [ ] **Step 1: Write the failing tests**

`Tests/Core/CallbookParserTests.swift`, with fixture XML inline — shaped
exactly per the banked contracts (root elements, namespaces, case):

```swift
import XCTest
@testable import QSOPartyLogger

/// The two services' XML, parsed per their banked contracts
/// (docs/research/callbook/SOURCES.md). Fixtures are shaped verbatim on the
/// documented/live-probed responses.
final class CallbookParserTests: XCTestCase {

    // MARK: QRZ

    private let qrzLogin = """
        <?xml version="1.0" encoding="utf-8" ?>
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Key>2331uf894c4bd29f3923f3bacf02c532d7bd9</Key>\
        <Count>123</Count><SubExp>non-subscriber</SubExp>\
        <GMTime>Mon Aug 25 00:00:00 2026</GMTime></Session>
        </QRZDatabase>
        """

    private let qrzLookup = """
        <?xml version="1.0" encoding="utf-8" ?>
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Callsign><call>W1AW</call><fname>ARRL HQ</fname><name>OPERATORS CLUB</name>\
        <addr2>Newington</addr2><state>CT</state><county>Hartford</county>\
        <grid>FN31pr</grid><country>United States</country><land>United States</land>\
        <dxcc>291</dxcc></Callsign>
        <Session><Key>2331uf894c4bd29f3923f3bacf02c532d7bd9</Key>\
        <Message>A subscription is required to obtain the complete data.</Message>\
        </Session>
        </QRZDatabase>
        """

    private let qrzTimeout = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Error>Session Timeout</Error></Session>
        </QRZDatabase>
        """

    private let qrzNotFound = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Key>2331uf894c4bd29f3923f3bacf02c532d7bd9</Key>\
        <Error>Not found: XX9XXX</Error></Session>
        </QRZDatabase>
        """

    func testQRZLoginParsesKey() throws {
        let session = try QRZXML.session(from: Data(qrzLogin.utf8))
        XCTAssertEqual(session.key, "2331uf894c4bd29f3923f3bacf02c532d7bd9")
        XCTAssertNil(session.error)
    }

    func testQRZLookupParsesRecordAndKeepsTheMessage() throws {
        let result = try QRZXML.lookup(from: Data(qrzLookup.utf8))
        let record = try XCTUnwrap(result.record)
        XCTAssertEqual(record.call, "W1AW")
        XCTAssertEqual(record.name, "ARRL HQ OPERATORS CLUB")
        XCTAssertEqual(record.qth, "Newington")
        XCTAssertEqual(record.state, "CT")
        XCTAssertEqual(record.county, "Hartford")
        XCTAssertEqual(record.grid, "FN31pr")
        // land, never the QSL-address country — here they agree, and the
        // parser must be reading the right one regardless.
        XCTAssertEqual(record.country, "United States")
        XCTAssertEqual(record.dxccID, 291)
        XCTAssertEqual(record.source, .qrz)
        XCTAssertEqual(result.message,
                       "A subscription is required to obtain the complete data.")
    }

    func testQRZSessionTimeoutSurfacesAsRetriableError() throws {
        let result = try QRZXML.lookup(from: Data(qrzTimeout.utf8))
        XCTAssertNil(result.record)
        XCTAssertEqual(result.error, "Session Timeout")
        XCTAssertTrue(QRZXML.isSessionExpiry(result.error))
        XCTAssertFalse(QRZXML.isRefusal(result.error))
    }

    func testQRZNotFoundIsAMissNotAFailure() throws {
        let result = try QRZXML.lookup(from: Data(qrzNotFound.utf8))
        XCTAssertNil(result.record)
        XCTAssertEqual(result.error, "Not found: XX9XXX")
        XCTAssertFalse(QRZXML.isSessionExpiry(result.error))
        XCTAssertTrue(QRZXML.isNotFound(result.error))
    }

    func testQRZRefusalIsRecognised() {
        XCTAssertTrue(QRZXML.isRefusal("Connection refused"))
        XCTAssertFalse(QRZXML.isRefusal("Not found: W1AW"))
    }

    func testQRZURLsEncodeCredentials() {
        let login = QRZXML.loginURL(username: "ke5cw",
                                    password: "p&ss;word",
                                    agent: "QSOPartyLogger/1.5")
        let s = login.absoluteString
        XCTAssertTrue(s.hasPrefix("https://xmldata.qrz.com/xml/current/?"))
        XCTAssertFalse(s.contains("p&ss;word"), "reserved characters must be encoded")
        XCTAssertTrue(s.contains("agent=QSOPartyLogger/1.5"))
        let lookup = QRZXML.lookupURL(sessionKey: "abc123", call: "W1AW/P")
        XCTAssertTrue(lookup.absoluteString.contains("s=abc123"))
        XCTAssertFalse(lookup.absoluteString.contains("W1AW/P"),
                       "the slash in a portable call must be encoded")
    }

    // MARK: HamQTH

    private let hamqthLogin = """
        <?xml version="1.0"?>
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><session_id>09b0ae90050be03c452ad235a1f2915ad684393c</session_id></session>
        </HamQTH>
        """

    private let hamqthLookup = """
        <?xml version="1.0"?>
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <search><callsign>ok2cqr</callsign><nick>Petr</nick>\
        <qth>Neratovice</qth><country>Czech Republic</country><adif>503</adif>\
        <grid>JO70GG</grid><us_state></us_state><us_county></us_county></search>
        </HamQTH>
        """

    private let hamqthExpired = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><error>Session does not exist or expired</error></session>
        </HamQTH>
        """

    private let hamqthNotFound = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><error>Callsign not found</error></session>
        </HamQTH>
        """

    func testHamQTHLoginParsesSessionID() throws {
        let session = try HamQTHXML.session(from: Data(hamqthLogin.utf8))
        XCTAssertEqual(session.id, "09b0ae90050be03c452ad235a1f2915ad684393c")
        XCTAssertNil(session.error)
    }

    func testHamQTHLookupParsesRecord() throws {
        let result = try HamQTHXML.lookup(from: Data(hamqthLookup.utf8))
        let record = try XCTUnwrap(result.record)
        XCTAssertEqual(record.call, "OK2CQR")
        XCTAssertEqual(record.name, "Petr")
        XCTAssertEqual(record.qth, "Neratovice")
        XCTAssertEqual(record.grid, "JO70GG")
        XCTAssertNil(record.state, "an empty us_state is absent, not \"\"")
        XCTAssertEqual(record.country, "Czech Republic")
        XCTAssertEqual(record.dxccID, 503)
        XCTAssertEqual(record.source, .hamqth)
    }

    func testHamQTHExpiryAndMissAreDistinguished() throws {
        let expired = try HamQTHXML.lookup(from: Data(hamqthExpired.utf8))
        XCTAssertTrue(HamQTHXML.isSessionExpiry(expired.error))
        let miss = try HamQTHXML.lookup(from: Data(hamqthNotFound.utf8))
        XCTAssertTrue(HamQTHXML.isNotFound(miss.error))
        XCTAssertFalse(HamQTHXML.isSessionExpiry(miss.error))
    }

    func testHamQTHURLsCarryPrgAndEncode() {
        let login = HamQTHXML.loginURL(username: "ke5cw", password: "a b&c")
        XCTAssertTrue(login.absoluteString.hasPrefix("https://www.hamqth.com/xml.php?"))
        XCTAssertFalse(login.absoluteString.contains("a b&c"))
        let lookup = HamQTHXML.lookupURL(sessionID: "s1", call: "W1AW",
                                         program: "QSOPartyLogger")
        XCTAssertTrue(lookup.absoluteString.contains("prg=QSOPartyLogger"))
        XCTAssertTrue(lookup.absoluteString.contains("callsign=W1AW"))
    }
}
```

- [ ] **Step 2: Run to verify it fails** (types missing), via the usual
`-only-testing:QSOPartyLoggerTests/CallbookParserTests` after `xcodegen generate`.

- [ ] **Step 3: Implement**

`Sources/Core/Lookup/CallbookRecord.swift`:

```swift
import Foundation

/// One callbook answer — advisory data about a station, from exactly one
/// service (spec 2026-08-25 decision 6: no merging; a record's provenance is
/// one service). Never scored, never written into a received exchange field.
struct CallbookRecord: Codable, Equatable, Sendable {
    enum Source: String, Codable, Sendable {
        case qrz, hamqth
        var label: String {
            switch self {
            case .qrz: "QRZ"
            case .hamqth: "HamQTH"
            }
        }
    }

    let call: String
    let name: String?
    /// City — QRZ `addr2`, HamQTH `qth`.
    let qth: String?
    let state: String?
    let county: String?
    let grid: String?
    /// The DXCC entity name — QRZ `land` (its `country` is the QSL mailing
    /// address, a banked gotcha), HamQTH `country`.
    let country: String?
    let dxccID: Int?
    let source: Source
    let fetchedAt: Date
}
```

`Sources/Core/Lookup/CallbookXMLScanner.swift` — one small delegate both
parsers share:

```swift
import Foundation

/// Flattens a callbook response into leaf-element text keyed by lowercased
/// element name — both services are one level of leaves inside wrapper
/// elements (`Session`/`Callsign`, `session`/`search`), and neither nests
/// leaves, so a flat map loses nothing. Namespace-tolerant by construction:
/// names are matched without prefixes and case-insensitively, because the
/// live servers already run ahead of both published specs.
final class CallbookXMLScanner: NSObject, XMLParserDelegate {
    private(set) var values: [String: String] = [:]
    /// Wrapper elements seen, lowercased — how a caller tells a response
    /// with a `<Callsign>`/`<search>` block from one without.
    private(set) var wrappers: Set<String> = []
    private var text = ""
    private var depth = 0

    func parser(_ parser: XMLParser, didStartElement name: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        depth += 1
        if depth == 2 { wrappers.insert(name.lowercased()) }
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement name: String,
                namespaceURI: String?, qualifiedName: String?) {
        // Leaves live at depth 3 (root > wrapper > leaf). Both services'
        // leaf names are unique across wrappers except none that matter;
        // last-writer-wins is fine for a flat advisory record.
        if depth == 3 {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { values[name.lowercased()] = trimmed }
        }
        text = ""
        depth -= 1
    }

    static func scan(_ data: Data) throws -> CallbookXMLScanner {
        let scanner = CallbookXMLScanner()
        let parser = XMLParser(data: data)
        parser.delegate = scanner
        guard parser.parse() else {
            throw CallbookParseError.malformed(parser.parserError?.localizedDescription ?? "unparseable XML")
        }
        return scanner
    }
}

enum CallbookParseError: Error, Equatable {
    case malformed(String)
}
```

`Sources/Core/Lookup/QRZXML.swift`:

```swift
import Foundation

/// QRZ.com XML interface — spec v1.34 (live servers stamp 1.36; the version
/// is data, never a gate). Contract banked in
/// docs/research/callbook/SOURCES.md: session keys have no guaranteed
/// lifetime and are cached and reused; errors and the non-subscriber
/// Message ride inside <Session> beside valid data, so every response is
/// checked; `land`/`dxcc` is the entity, `country` the QSL address.
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
        let name = [scan.values["fname"], scan.values["name"]]
            .compactMap { $0 }.joined(separator: " ")
        let record = CallbookRecord(
            call: call.uppercased(),
            name: scan.values["name_fmt"] ?? (name.isEmpty ? nil : name),
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

    static func isSessionExpiry(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("session timeout") ?? false
    }

    static func isNotFound(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("not found") ?? false
    }

    /// "Connection refused" — QRZ's abuse response; the spec says a login
    /// will not succeed for at least 24 hours, so the client backs off.
    static func isRefusal(_ error: String?) -> Bool {
        error?.localizedCaseInsensitiveContains("connection refused") ?? false
    }

    static func loginURL(username: String, password: String, agent: String) -> URL {
        var c = URLComponents(string: "https://xmldata.qrz.com/xml/current/")!
        c.queryItems = [
            URLQueryItem(name: "username", value: username),
            URLQueryItem(name: "password", value: password),
            URLQueryItem(name: "agent", value: agent),
        ]
        return c.url!
    }

    static func lookupURL(sessionKey: String, call: String) -> URL {
        var c = URLComponents(string: "https://xmldata.qrz.com/xml/current/")!
        c.queryItems = [
            URLQueryItem(name: "s", value: sessionKey),
            URLQueryItem(name: "callsign", value: call),
        ]
        return c.url!
    }
}
```

Note: `URLComponents.queryItems` percent-encodes values but leaves `/` and
`;` legal in a query. The URL-builder test asserts the *reserved* characters
(`&`, space) are encoded and that a portable call's `/` does not survive
raw; if `URLComponents` leaves `/` in place (it is query-legal), tighten the
builders with an explicit `.addingPercentEncoding(withAllowedCharacters:
.alphanumerics)` on the password and call values and keep the assertions —
services parse strictly and the doc'd examples use plain calls. Adjust
builder or test so both agree, and note which way it landed in the commit.

`Sources/Core/Lookup/HamQTHXML.swift`:

```swift
import Foundation

/// HamQTH.com XML callbook — docs at hamqth.com/developers.php, banked in
/// docs/research/callbook/SOURCES.md: the session id is valid for one hour;
/// `prg` names this program on every lookup; elements are lowercase.
enum HamQTHXML {
    struct Session: Equatable {
        let id: String?
        let error: String?
    }

    struct LookupResult: Equatable {
        let record: CallbookRecord?
        let error: String?
    }

    /// The documented lifetime: "Session ID is valid for one hour."
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
        var c = URLComponents(string: "https://www.hamqth.com/xml.php")!
        c.queryItems = [
            URLQueryItem(name: "u", value: username),
            URLQueryItem(name: "p", value: password),
        ]
        return c.url!
    }

    static func lookupURL(sessionID: String, call: String, program: String) -> URL {
        var c = URLComponents(string: "https://www.hamqth.com/xml.php")!
        c.queryItems = [
            URLQueryItem(name: "id", value: sessionID),
            URLQueryItem(name: "callsign", value: call),
            URLQueryItem(name: "prg", value: program),
        ]
        return c.url!
    }
}
```

- [ ] **Step 4: xcodegen, run the class, then the full suite**
- [ ] **Step 5: Commit** — `lookup: CallbookRecord and the QRZ/HamQTH parsers and URL builders`

---

### Task 2: The disk cache

**Files:**
- Create: `Sources/Core/Lookup/CallbookCache.swift`
- Create: `Tests/Core/CallbookCacheTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The lookup cache (spec 2026-08-25 decision 8): 30-day TTL, capped, so a
/// day's service allowance is never spent twice on one call.
final class CallbookCacheTests: XCTestCase {

    private func makeCache(cap: Int = 5000) -> CallbookCache {
        CallbookCache(
            directory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true),
            cap: cap
        )
    }

    private func record(_ call: String, at t: TimeInterval) -> CallbookRecord {
        CallbookRecord(call: call, name: "Bob", qth: nil, state: "MO",
                       county: nil, grid: "EM48", country: nil, dxccID: nil,
                       source: .hamqth, fetchedAt: Date(timeIntervalSince1970: t))
    }

    func testRoundTripAndCaseInsensitiveKey() {
        let cache = makeCache()
        cache.store(record("W1AW", at: 0))
        XCTAssertEqual(cache.record(for: "w1aw",
                                    now: Date(timeIntervalSince1970: 60))?.state, "MO")
    }

    func testExpiredEntriesAreNotReturned() {
        let cache = makeCache()
        cache.store(record("W1AW", at: 0))
        let after31Days = Date(timeIntervalSince1970: 31 * 86_400)
        XCTAssertNil(cache.record(for: "W1AW", now: after31Days))
        let within = Date(timeIntervalSince1970: 29 * 86_400)
        XCTAssertNotNil(cache.record(for: "W1AW", now: within))
    }

    func testCapEvictsTheOldest() {
        let cache = makeCache(cap: 3)
        for (i, call) in ["A1A", "B2B", "C3C", "D4D"].enumerated() {
            cache.store(record(call, at: TimeInterval(i)))
        }
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertNil(cache.record(for: "A1A", now: now), "oldest evicted at the cap")
        XCTAssertNotNil(cache.record(for: "D4D", now: now))
    }

    func testSurvivesReload() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        CallbookCache(directory: dir, cap: 100).store(record("W1AW", at: 0))
        let reloaded = CallbookCache(directory: dir, cap: 100)
        XCTAssertEqual(reloaded.record(for: "W1AW",
                                       now: Date(timeIntervalSince1970: 60))?.grid, "EM48")
    }
}
```

- [ ] **Step 2: Red; implement**

```swift
import Foundation

/// On-disk lookup cache — one JSON file of records keyed by call, 30-day
/// TTL, LRU-by-fetch-date cap (spec 2026-08-25 decision 8). Best-effort on
/// purpose: a cache that cannot read or write behaves as empty and costs
/// one fresh lookup, never an error in the entry path.
final class CallbookCache {
    static let defaultDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("QSOPartyLogger/Callbook", isDirectory: true)

    static let ttl: TimeInterval = 30 * 86_400

    private let fileURL: URL
    private let cap: Int
    private var records: [String: CallbookRecord]

    init(directory: URL = CallbookCache.defaultDirectory, cap: Int = 5000) {
        self.fileURL = directory.appendingPathComponent("cache.json")
        self.cap = cap
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.records = (try? decoder.decode(
            [String: CallbookRecord].self,
            from: Data(contentsOf: fileURL))) ?? [:]
    }

    func record(for call: String, now: Date = Date()) -> CallbookRecord? {
        guard let hit = records[call.uppercased()],
              now.timeIntervalSince(hit.fetchedAt) < Self.ttl else { return nil }
        return hit
    }

    func store(_ record: CallbookRecord) {
        records[record.call.uppercased()] = record
        while records.count > cap,
              let oldest = records.min(by: { $0.value.fetchedAt < $1.value.fetchedAt }) {
            records.removeValue(forKey: oldest.key)
        }
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(records) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }
}
```

- [ ] **Step 3: Green; full suite; commit** — `lookup: the 30-day disk cache`

---

### Task 3: The `QSO.callbook` sidecar and its ADIF fields

**Files:**
- Modify: `Sources/Core/Models/QSO.swift` (sidecar after `theirPotaRefs`)
- Modify: `Sources/Core/Export/AdifExporter.swift` (emit before the POTA tail)
- Create: `Tests/Core/CallbookStampTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The lookup enrichment sidecar (spec 2026-08-25 decision 5): additive on
/// QSO, structurally invisible to ScoreEngine, emitted as plain ADIF fields.
final class CallbookStampTests: XCTestCase {

    private func stamped() -> QSO {
        var q = QSO(call: "W1AW", band: .m20, modeClass: .cw, rawMode: "CW",
                    sent: ["rst": "599"], rcvd: ["rst": "599"],
                    myPotaRefs: ["US-1111"])
        q.callbook = QSO.CallbookStamp(name: "Bob", qth: "Newington",
                                       state: "CT", grid: "FN31pr",
                                       source: "QRZ")
        return q
    }

    func testSidecarRoundTripsAndOldRowsDecodeNil() throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let reread = try decoder.decode(QSO.self, from: encoder.encode(stamped()))
        XCTAssertEqual(reread.callbook?.name, "Bob")

        var plain = stamped(); plain.callbook = nil
        let rereadPlain = try decoder.decode(QSO.self, from: encoder.encode(plain))
        XCTAssertNil(rereadPlain.callbook)
        XCTAssertFalse(String(decoding: try encoder.encode(plain), as: UTF8.self)
            .contains("callbook"), "absent writes no key — old builds unaffected")
    }

    func testAdifEmitsTheStampInAPotaLog() throws {
        let contest = try XCTUnwrap(ContestCatalog.contest(id: "pota"))
        var log = ContestLog(partyID: "pota")
        log.station.callsign = "KE5CW"
        log.qsos = [stamped()]
        let text = AdifExporter.export(log: log, contest: contest)
        XCTAssertTrue(text.contains("<name:3>BOB"))
        XCTAssertTrue(text.contains("<qth:9>Newington"))
        XCTAssertTrue(text.contains("<state:2>CT"))
        XCTAssertTrue(text.contains("<gridsquare:6>FN31pr"))
    }

    func testStampNeverOverridesOnAirData() throws {
        // A name party's copied name outranks the callbook's.
        let naqp = try XCTUnwrap(PartyCatalog.party(id: "naqpcw"))
        var log = ContestLog(partyID: "naqpcw")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        var q = QSO(timestampUTC: Date(timeIntervalSince1970: 0), call: "W1AW",
                    band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "599",
                    nameRcvd: "MARK", myLoc: "TX", theirLoc: "CT")
        q.callbook = QSO.CallbookStamp(name: "Bob", qth: nil, state: "VT",
                                       grid: nil, source: "QRZ")
        log.qsos = [q]
        let text = AdifExporter.export(log: log, party: naqp)
        XCTAssertTrue(text.contains("<name:4>MARK"), "copied on the air, wins")
        XCTAssertFalse(text.contains("BOB"))
        XCTAssertTrue(text.contains("<state:2>CT"), "the exchange's state wins")
        XCTAssertFalse(text.contains("<state:2>VT"))
    }
}
```

(Adjust the NAQP fixture to that party's real exchange shape if `nameRcvd`
alone does not satisfy it — the assertion pair is what matters.)

- [ ] **Step 2: Red; implement**

`QSO.swift` — after `theirPotaRefs`:

```swift
    /// What a callbook lookup knew about the station at logging time —
    /// stamped only where the contest sets `enrichFromCallbook` (POTA), and
    /// advisory everywhere: never read by `ScoreEngine`, never a received
    /// exchange value, exported as plain ADIF station data. `nil` — the
    /// overwhelmingly common case — writes no key, so every existing log
    /// encodes byte-identically.
    struct CallbookStamp: Codable, Hashable, Sendable {
        var name: String?
        var qth: String?
        var state: String?
        var grid: String?
        /// The service's short label ("QRZ", "HamQTH") — provenance.
        var source: String?
    }
    var callbook: CallbookStamp?
```

Add `callbook` to `CodingKeys`, decode with `decodeIfPresent` in
`init(from:)`, and give both memberwise inits a trailing
`callbook: CallbookStamp? = nil` parameter assigned as the others are.
(`encode(to:)` is synthesized over `CodingKeys` and writes optionals only
when present — the round-trip test pins it.)

`AdifExporter.record(...)` — insert immediately before the POTA tail block
(`// POTA: one emitted record per…`):

```swift
        // The callbook stamp — advisory station data recorded at logging
        // (spec 2026-08-25 decision 5). On-air data always wins: each field
        // is written only where nothing upstream already wrote it.
        if let cb = q.callbook {
            if (q.nameRcvd ?? "").isEmpty, let name = cb.name {
                r += field("name", name.uppercased())
            }
            if let qth = cb.qth { r += field("qth", qth) }
            if q.theirLoc.isEmpty, let state = cb.state {
                r += field("state", state.uppercased())
            }
            if !contest.exchange.contains(where: { $0.kind == .grid }),
               let grid = cb.grid {
                r += field("gridsquare", grid)
            }
        }
```

- [ ] **Step 3: Green; full suite (export fixtures untouched — no existing
log carries the sidecar); commit** — `lookup: the QSO callbook stamp and its ADIF fields`

---

### Task 4: Credentials, settings keys, and the client

**Files:**
- Create: `Sources/App/KeychainStore.swift`
- Create: `Sources/App/CallbookClient.swift`
- Modify: `Sources/App/AppSettings.swift` (five stored keys)
- Create: `Tests/App/CallbookClientTests.swift`

- [ ] **Step 1: Failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The lookup client: sessions per each service's banked contract, primary
/// then fallback, cache first, debounce owned by the caller of `lookup`.
/// Tests inject a scripted fetcher and an in-memory credential store —
/// never the network, never the real Keychain.
@MainActor
final class CallbookClientTests: XCTestCase {

    final class ScriptedFetcher: CallbookFetching, @unchecked Sendable {
        var responses: [String]
        private(set) var requested: [URL] = []
        init(_ responses: [String]) { self.responses = responses }
        func get(_ url: URL) async throws -> Data {
            requested.append(url)
            guard !responses.isEmpty else { throw URLError(.badServerResponse) }
            return Data(responses.removeFirst().utf8)
        }
    }

    private let qrzLoginOK = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Session><Key>KEY1</Key></Session></QRZDatabase>
        """
    private let qrzW1AW = """
        <QRZDatabase version="1.36" xmlns="http://xmldata.qrz.com">
        <Callsign><call>W1AW</call><fname>ARRL</fname><state>CT</state>\
        <grid>FN31pr</grid></Callsign>
        <Session><Key>KEY1</Key></Session></QRZDatabase>
        """
    private let qrzTimeout = """
        <QRZDatabase xmlns="http://xmldata.qrz.com">
        <Session><Error>Session Timeout</Error></Session></QRZDatabase>
        """
    private let hamqthLoginOK = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <session><session_id>SID1</session_id></session></HamQTH>
        """
    private let hamqthW1AW = """
        <HamQTH version="2.8" xmlns="https://www.hamqth.com">
        <search><callsign>W1AW</callsign><nick>Al</nick><grid>FN31</grid></search></HamQTH>
        """

    private func makeClient(
        fetcher: ScriptedFetcher,
        primary: CallbookService = .qrz,
        qrz: Bool = true, hamqth: Bool = false
    ) -> CallbookClient {
        let credentials = InMemoryCredentialStore()
        credentials.set("pw", service: CallbookService.qrz.keychainService, account: "ke5cw")
        credentials.set("pw", service: CallbookService.hamqth.keychainService, account: "ke5cw")
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return CallbookClient(
            fetcher: fetcher,
            credentials: credentials,
            cache: CallbookCache(directory: cacheDir),
            configuration: { .init(qrzEnabled: qrz, qrzUsername: "ke5cw",
                                   hamqthEnabled: hamqth, hamqthUsername: "ke5cw",
                                   primary: primary) }
        )
    }

    func testLoginOncePerSessionThenLookups() async {
        let fetcher = ScriptedFetcher([qrzLoginOK, qrzW1AW, qrzW1AW])
        let client = makeClient(fetcher: fetcher)
        _ = await client.lookup(call: "W1AW")
        let record = await client.lookup(call: "W1AW2")  // distinct call, same session
        XCTAssertEqual(fetcher.requested.count, 3, "one login, two lookups — never per-lookup logins")
        XCTAssertNotNil(record ?? client.record)
    }

    func testCacheHitFetchesNothing() async {
        let fetcher = ScriptedFetcher([qrzLoginOK, qrzW1AW])
        let client = makeClient(fetcher: fetcher)
        let first = await client.lookup(call: "W1AW")
        XCTAssertEqual(first?.state, "CT")
        let requestsAfterFirst = fetcher.requested.count
        let second = await client.lookup(call: "W1AW")
        XCTAssertEqual(second?.state, "CT")
        XCTAssertEqual(fetcher.requested.count, requestsAfterFirst,
                       "a cached call costs no request")
    }

    func testSessionTimeoutRelogsInExactlyOnce() async {
        let fetcher = ScriptedFetcher([qrzLoginOK, qrzTimeout, qrzLoginOK, qrzW1AW])
        let client = makeClient(fetcher: fetcher)
        let record = await client.lookup(call: "W1AW")
        XCTAssertEqual(record?.call, "W1AW")
        XCTAssertEqual(fetcher.requested.count, 4, "login, expired lookup, re-login, retry")
    }

    func testFallbackToSecondaryOnPrimaryFailure() async {
        // QRZ login fails outright; HamQTH answers.
        let fetcher = ScriptedFetcher(["not xml at all", hamqthLoginOK, hamqthW1AW])
        let client = makeClient(fetcher: fetcher, primary: .qrz, qrz: true, hamqth: true)
        let record = await client.lookup(call: "W1AW")
        XCTAssertEqual(record?.source, .hamqth)
        XCTAssertEqual(record?.name, "Al")
    }

    func testNothingConfiguredLooksUpNothing() async {
        let fetcher = ScriptedFetcher([])
        let client = makeClient(fetcher: fetcher, qrz: false, hamqth: false)
        let record = await client.lookup(call: "W1AW")
        XCTAssertNil(record)
        XCTAssertTrue(fetcher.requested.isEmpty)
    }

    func testPlausibleCallGate() {
        XCTAssertFalse(CallbookClient.isPlausibleCall("W"))
        XCTAssertFalse(CallbookClient.isPlausibleCall("QRZ"))
        XCTAssertTrue(CallbookClient.isPlausibleCall("W1A"))
        XCTAssertTrue(CallbookClient.isPlausibleCall("KE5CW"))
        XCTAssertTrue(CallbookClient.isPlausibleCall("EA8/W1AW"))
    }
}
```

- [ ] **Step 2: Red; implement**

`Sources/App/KeychainStore.swift`:

```swift
import Foundation
import Security

/// Where lookup credentials live — behind a protocol so no test ever
/// touches the login keychain (the test host would prompt, and pollute).
protocol CredentialStore: AnyObject {
    func password(service: String, account: String) -> String?
    func set(_ password: String, service: String, account: String)
    func delete(service: String, account: String)
}

/// The real store: one generic-password item per lookup service in the
/// login keychain. First Keychain use in this app — with ad-hoc signing a
/// rebuilt dev binary may re-prompt for access (the same churn class as the
/// TCC resets); a release identity is stable. Spec 2026-08-25 decision 7.
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

/// Test double — also what the client tests inject.
final class InMemoryCredentialStore: CredentialStore {
    private var values: [String: String] = [:]
    func password(service: String, account: String) -> String? { values["\(service)|\(account)"] }
    func set(_ password: String, service: String, account: String) { values["\(service)|\(account)"] = password }
    func delete(service: String, account: String) { values.removeValue(forKey: "\(service)|\(account)") }
}
```

`AppSettings` — five keys in the established `didSet`/restore pattern
(usernames and toggles in defaults; passwords only ever in the store):
`qrzEnabled = false`, `qrzUsername = ""`, `hamqthEnabled = false`,
`hamqthUsername = ""`, `callbookPrimaryRaw = ""` with a computed
`callbookPrimary: CallbookService?` (nil = whichever single service is
enabled; both enabled and nothing chosen = `.hamqth`, decision 6 — the
operator's QRZ is the free tier).

`Sources/App/CallbookClient.swift`:

```swift
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
    /// renders. Cleared when a new lookup starts for a different call.
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

    /// A call is worth a network request once it could be someone: three or
    /// more characters including a digit — the same floor the SCP strip
    /// uses for usefulness, and cheap enough to be wrong about.
    static func isPlausibleCall(_ call: String) -> Bool {
        let c = call.trimmingCharacters(in: .whitespaces)
        return c.count >= 3 && c.contains(where: \.isNumber)
    }

    /// The entry path's entry point: debounced, cancelled by the next
    /// keystroke, silent for implausible calls.
    func noteCallChanged(_ call: String) {
        debounceTask?.cancel()
        let wanted = call.trimmingCharacters(in: .whitespaces).uppercased()
        if record?.call != wanted { record = nil }
        guard Self.isPlausibleCall(wanted) else { return }
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            _ = await self?.lookup(call: wanted)
        }
    }

    /// Cache, then primary, then the other. Returns the record and also
    /// publishes it for the caption.
    @discardableResult
    func lookup(call rawCall: String) async -> CallbookRecord? {
        let call = rawCall.trimmingCharacters(in: .whitespaces).uppercased()
        guard !call.isEmpty else { return nil }
        if let hit = cache.record(for: call) {
            publish(hit, for: call)
            return hit
        }
        let config = configuration()
        for service in order(config) {
            if let found = await lookup(call: call, via: service, config: config) {
                cache.store(found)
                publish(found, for: call)
                return found
            }
        }
        return nil
    }

    /// One live session request per service — the settings pane's
    /// "Check credentials" button. Returns a short human sentence.
    func checkCredentials(_ service: CallbookService) async -> String {
        let config = configuration()
        switch service {
        case .qrz:
            qrzSessionKey = nil
            let ok = await qrzLogin(config: config)
            return ok ? "QRZ accepted the login."
                      : (consoleTail ?? "QRZ did not accept the login.")
        case .hamqth:
            hamqthSession = nil
            let ok = await hamqthLogin(config: config)
            return ok ? "HamQTH accepted the login."
                      : (consoleTail ?? "HamQTH did not accept the login.")
        }
    }

    // MARK: Internals

    private var consoleTail: String? { console.last }

    private func publish(_ found: CallbookRecord, for call: String) {
        record = found
    }

    private func order(_ config: Configuration) -> [CallbookService] {
        let enabled = CallbookService.allCases.filter {
            switch $0 {
            case .qrz: config.qrzEnabled && !config.qrzUsername.isEmpty
            case .hamqth: config.hamqthEnabled && !config.hamqthUsername.isEmpty
            }
        }
        guard enabled.count > 1 else { return enabled }
        let first = config.primary ?? .hamqth
        return enabled.sorted { a, _ in a == first }
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
            guard let key = session.key, session.error == nil || session.key != nil else {
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
            if let record = result.record { return record }
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
            if let record = result.record { return record }
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
```

Note on the ordering test: `enabled.sorted { a, _ in a == first }` is a
stable put-first; if the strict-weak-ordering assertion in debug Swift
objects, replace with an explicit partition:
`([first] + enabled.filter { $0 != first }).filter(enabled.contains)`.

- [ ] **Step 3: Green (`CallbookClientTests`); full suite; commit** —
`lookup: the callbook client — sessions, cache-first, primary then fallback`

---

### Task 5: UI — the toolbar pane, the caption, and the POTA stamp

**Files:**
- Create: `Sources/UI/CallbookSettingsPane.swift`
- Create: `Sources/Core/Lookup/CallbookCaption.swift`
- Modify: `Sources/UI/MainView.swift` (client, toolbar item, caption wiring, `.onChange` hook)
- Modify: `Sources/UI/EntryBar.swift` (one caption line)
- Modify: `Sources/App/EntryFlow.swift` (`callbookRecord` + the stamp at logging)
- Create: `Tests/Core/CallbookCaptionTests.swift`
- Modify: `Tests/App/EntryFlowTests.swift` (stamp tests)

- [ ] **Step 1: Failing tests — the caption formatter (pure) and the stamp**

`Tests/Core/CallbookCaptionTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// The info line by the call field: name · state · grid · distance/bearing,
/// from the record and the station grid. Pure, so the line's shape is
/// testable without a view.
final class CallbookCaptionTests: XCTestCase {

    private func record(name: String? = "Bob", state: String? = "MO",
                        grid: String? = "EM48ss") -> CallbookRecord {
        CallbookRecord(call: "W0ABC", name: name, qth: "Rolla", state: state,
                       county: nil, grid: grid, country: "United States",
                       dxccID: 291, source: .hamqth,
                       fetchedAt: Date(timeIntervalSince1970: 0))
    }

    func testFullLine() {
        let line = CallbookCaption.line(for: record(), stationGrid: "EM13qc")
        let text = try! XCTUnwrap(line)
        XCTAssertTrue(text.hasPrefix("Bob · MO · EM48ss · "))
        XCTAssertTrue(text.contains("mi"), "distance in miles, the README's unit")
    }

    func testDegradesFieldByField() {
        XCTAssertEqual(CallbookCaption.line(for: record(grid: nil), stationGrid: "EM13qc"),
                       "Bob · MO")
        XCTAssertEqual(CallbookCaption.line(for: record(name: nil, state: nil, grid: nil),
                                            stationGrid: ""),
                       nil, "nothing to say, no line")
        // No station grid: the record's grid still shows, without a distance.
        XCTAssertEqual(CallbookCaption.line(for: record(), stationGrid: ""),
                       "Bob · MO · EM48ss")
    }

    func testBearingArrowPointsRoughlyNortheastFromTexasToMissouri() throws {
        let line = try XCTUnwrap(CallbookCaption.line(for: record(), stationGrid: "EM13qc"))
        XCTAssertTrue(line.contains("↗") || line.contains("↑"),
                      "Dallas to Rolla is up and to the right: \(line)")
    }
}
```

Flow-stamp tests, appended to the POTA section of `EntryFlowTests`:

```swift
    func testPotaLogStampsTheCallbookRecord() throws {
        let (flow, doc) = try potaFlow()
        flow.callbookRecord = CallbookRecord(
            call: "W1AW", name: "Bob", qth: "Newington", state: "CT",
            county: nil, grid: "FN31pr", country: nil, dxccID: nil,
            source: .qrz, fetchedAt: Date())
        flow.entry.callTyped = "W1AW"
        guard case .logged = flow.logContact(context(esm: false, connected: false),
                                             undoManager: nil) else {
            return XCTFail("must log")
        }
        let stamp = try XCTUnwrap(doc.log.qsos.first?.callbook)
        XCTAssertEqual(stamp.name, "Bob")
        XCTAssertEqual(stamp.state, "CT")
        XCTAssertEqual(stamp.source, "QRZ")
    }

    func testStampSkipsAMismatchedRecordAndPartyLogs() throws {
        // A stale record for another call must not stamp.
        let (flow, doc) = try potaFlow()
        flow.callbookRecord = CallbookRecord(
            call: "K9ZZZ", name: "Ann", qth: nil, state: nil, county: nil,
            grid: nil, country: nil, dxccID: nil, source: .hamqth, fetchedAt: Date())
        flow.entry.callTyped = "W1AW"
        _ = flow.logContact(context(esm: false, connected: false), undoManager: nil)
        XCTAssertNil(doc.log.qsos.first?.callbook)

        // A party log never stamps — enrichFromCallbook is POTA-only
        // (spec decision 4; Tom's answer).
        let partyDoc = cqpDocument()
        let partyFlow = EntryFlow(document: partyDoc)
        partyFlow.callbookRecord = CallbookRecord(
            call: "W6ABC", name: "Cy", qth: nil, state: "CA", county: nil,
            grid: nil, country: nil, dxccID: nil, source: .qrz, fetchedAt: Date())
        readyToLog(partyFlow)
        _ = partyFlow.logContact(context(esm: false), undoManager: nil)
        XCTAssertNil(partyDoc.log.qsos.first?.callbook)
    }
```

(`readyToLog` is the file's existing helper; match its signature.)

- [ ] **Step 2: Red; implement**

`Sources/Core/Lookup/CallbookCaption.swift`:

```swift
import Foundation

/// The one-line advisory the entry row shows for a looked-up station.
/// Pure — the view renders whatever this says, and the tests read it here.
enum CallbookCaption {
    /// "Bob · MO · EM48ss · 412 mi ↗" — each piece only when known; nil
    /// when nothing is known at all. Distance and bearing need both grids.
    static func line(for record: CallbookRecord, stationGrid: String) -> String? {
        var parts: [String] = []
        if let name = record.name, !name.isEmpty { parts.append(name) }
        if let state = record.state, !state.isEmpty { parts.append(state) }
        if let grid = record.grid, !grid.isEmpty {
            parts.append(grid)
            if let here = Maidenhead.center(of: stationGrid),
               let there = Maidenhead.center(of: grid) {
                let km = PotaParkDirectory.distanceKm(
                    from: (here.latitude, here.longitude),
                    to: (there.latitude, there.longitude))
                let miles = Int((km * 0.621371).rounded())
                let arrow = Self.arrow(bearingDegrees(
                    fromLat: here.latitude, lon: here.longitude,
                    toLat: there.latitude, lon: there.longitude))
                parts.append("\(miles) mi \(arrow)")
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Initial great-circle bearing, degrees clockwise from north.
    static func bearingDegrees(fromLat: Double, lon fromLon: Double,
                               toLat: Double, lon toLon: Double) -> Double {
        let φ1 = fromLat * .pi / 180, φ2 = toLat * .pi / 180
        let Δλ = (toLon - fromLon) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x) * 180 / .pi
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    /// The eight-point arrow for a bearing — ↑ is north.
    static func arrow(_ degrees: Double) -> String {
        let arrows = ["↑", "↗", "→", "↘", "↓", "↙", "←", "↖"]
        let index = Int(((degrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return arrows[index]
    }
}
```

(`PotaParkDirectory.distanceKm` — confirm it is internal/static and
callable here; it is used cross-type by tests already. If it is private,
promote it to internal in the same commit with a note.)

`EntryFlow` — add near `voiceRecordings`:

```swift
    /// The callbook's current answer, pushed by the window (the client is
    /// the window's; the flow only reads). Read at logging for the POTA
    /// stamp, and only when it matches the call being logged.
    var callbookRecord: CallbookRecord?
```

In `logStandaloneContact`, after `let myParks = document.log.myPotaRefs`:

```swift
        // The callbook stamp (spec 2026-08-25 decisions 4–5): only where
        // the contest asks, and only the record for this very call — a
        // stale answer for the last station must never mark this one.
        var stamp: QSO.CallbookStamp?
        if standaloneContest?.enrichFromCallbook == true,
           let record = callbookRecord, record.call == entry.callNormalized {
            stamp = QSO.CallbookStamp(name: record.name, qth: record.qth,
                                      state: record.state, grid: record.grid,
                                      source: record.source.label)
        }
```

and pass `callbook: stamp` in the `QSO(...)` construction.

`EntryBar` — one more quiet line after the park caption, same pattern:

```swift
    /// The callbook's line for the call in the field — advisory garnish,
    /// nil-hidden. It never fills any field (spec decision 4's hard rule).
    var callbookCaption: String? = nil
```

rendered after the `parkCaption` label:

```swift
            if let callbookCaption {
                Label(callbookCaption, systemImage: "person.text.rectangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
```

`MainView`:
1. `@State private var callbookClient = CallbookClient(configuration: { … })`
   — built with a configuration closure reading `AppSettings.shared`
   (construct it the way the other clients on the view are constructed —
   match whichever pattern `potaParkClient` uses there: check its
   declaration and mirror it, including any environment/init threading).
2. In the `EntryBar` construction: `callbookCaption: callbookCaption`, with:

```swift
    private var callbookCaption: String? {
        guard let record = callbookClient.record,
              record.call == entry.callNormalized, !entry.call.isEmpty else { return nil }
        let line = CallbookCaption.line(for: record,
                                        stationGrid: document.log.station.gridLocator)
        guard let line else { return nil }
        return "\(line) — \(record.source.label)"
    }
```

3. The trigger, beside the existing call hook:
`.onChange(of: entry.call) { flow.callChanged(operatingContext); callbookClient.noteCallChanged(entry.call) }`
(extend the existing `.onChange(of: entry.call)` closure — do not add a
second one), and push the record into the flow with
`.onChange(of: callbookClient.record) { flow.callbookRecord = callbookClient.record }`.
4. Toolbar: a Lookup button + popover next to the cluster's, presenting
`CallbookSettingsPane(client: callbookClient)` — mirror exactly how the
cluster popover is attached (find `clusterPopover`'s presenting button in
`toolbarContent` and copy its shape).

`Sources/UI/CallbookSettingsPane.swift`:

```swift
import SwiftUI

/// Lookup credentials — QRZ and HamQTH, each with a Check button that makes
/// one live session request and reports inline by the control (never a
/// modal, and the button claims nothing before it has been pressed).
/// Passwords go to the login keychain; usernames and toggles to defaults.
struct CallbookSettingsPane: View {
    let client: CallbookClient
    @State private var settings = AppSettings.shared
    @State private var qrzPassword = ""
    @State private var hamqthPassword = ""
    @State private var qrzStatus: String?
    @State private var hamqthStatus: String?
    private let credentials: CredentialStore = KeychainStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Callsign Lookup").font(.headline)
            Text("Advisory only — a lookup never fills an exchange field. "
                 + "In a POTA log the record is also saved into the QSO for "
                 + "richer ADIF.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            servicePane(.qrz, enabled: $settings.qrzEnabled,
                        username: $settings.qrzUsername,
                        password: $qrzPassword, status: qrzStatus,
                        note: "Free accounts return limited fields; the XML "
                            + "subscription returns the full record.")
            servicePane(.hamqth, enabled: $settings.hamqthEnabled,
                        username: $settings.hamqthUsername,
                        password: $hamqthPassword, status: hamqthStatus,
                        note: "Free — register at hamqth.com.")

            if settings.qrzEnabled && settings.hamqthEnabled {
                Picker("Try first", selection: primaryBinding) {
                    ForEach(CallbookService.allCases, id: \.self) {
                        Text($0.label).tag($0)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear {
            qrzPassword = credentials.password(
                service: CallbookService.qrz.keychainService,
                account: settings.qrzUsername) ?? ""
            hamqthPassword = credentials.password(
                service: CallbookService.hamqth.keychainService,
                account: settings.hamqthUsername) ?? ""
        }
    }

    private var primaryBinding: Binding<CallbookService> {
        Binding(
            get: { settings.callbookPrimary ?? .hamqth },
            set: { settings.callbookPrimaryRaw = $0.rawValue }
        )
    }

    @ViewBuilder
    private func servicePane(_ service: CallbookService, enabled: Binding<Bool>,
                             username: Binding<String>, password: Binding<String>,
                             status: String?, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("\(service.label)", isOn: enabled)
            if enabled.wrappedValue {
                HStack(spacing: 6) {
                    TextField("Username", text: username)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    SecureField("Password", text: password)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)
                    Button("Check") {
                        credentials.set(password.wrappedValue,
                                        service: service.keychainService,
                                        account: username.wrappedValue)
                        Task {
                            let verdict = await client.checkCredentials(service)
                            switch service {
                            case .qrz: qrzStatus = verdict
                            case .hamqth: hamqthStatus = verdict
                            }
                        }
                    }
                    .disabled(username.wrappedValue.isEmpty
                              || password.wrappedValue.isEmpty)
                }
                if let status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(status.contains("accepted")
                                         ? AnyShapeStyle(Color.green)
                                         : AnyShapeStyle(Color.orange))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(note).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
```

(Save-on-Check keeps the password write explicit; also persist the field on
popover dismiss if the house pattern for the cluster fields suggests it —
the cluster popover binds settings directly, but a password must not land
in defaults, so Check doubles as Save and the caption under the button says
so if you add one. Keep it minimal.)

- [ ] **Step 3: Green; full suite; commit** —
`lookup: the info line, the Lookup pane, and the POTA callbook stamp`

---

### Task 6: Docs and the final gate

**Files:** `README.md`, `docs/PROVENANCE.md`, this plan's status block.

- [ ] **Step 1: README**

- A **Callsign lookup** section (near the POTA mode section): what it shows
  (the quiet line — name · state · grid · miles and arrow — for any log),
  the hard rule (never fills an exchange field), setup (the Lookup toolbar
  popover; QRZ free vs XML subscription; HamQTH free), the first-use
  keychain prompt sentence, the POTA-log stamp and its ADIF fields, and the
  cache ("looked up once per month per call, so free tiers last").
- Test count updated from the final run's `Executed N tests` line.

- [ ] **Step 2: PROVENANCE.md** — two rows: the QRZ XML spec (v1.34 doc,
live 1.36 noted) and HamQTH developers page, both fetched 2026-08-25,
pointing at `research/callbook/SOURCES.md`, with the free-tier open
question named.

- [ ] **Step 3: Status block on this plan; final full suite; commit** —
`docs: callsign lookup — README, provenance, test count`

Then `superpowers:finishing-a-development-branch` (ExitWorktree first; the
merge runs from the main checkout — the harness refuses cross-checkout git
from inside the worktree).

## Coverage map (spec → tasks)

| Spec item | Task |
| --- | --- |
| Decision 6 (two services, order, no merge) | 1, 4 |
| Decision 7 (Keychain) | 4, 5 |
| Decision 8 (cache, debounce, sessions) | 2, 4 |
| Decision 4 (info line everywhere; hard no-fill rule) | 5 |
| Decision 5 (sidecar + ADIF) | 3, 5 |
| §Provenance (callbook SOURCES, README, PROVENANCE) | 0, 6 |

Deferred (phase 3 and beyond, per the spec): the POTA spot feed into the
band map; HamDB; cross-log worked-before.

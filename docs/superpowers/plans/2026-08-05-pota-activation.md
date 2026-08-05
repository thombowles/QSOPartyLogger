# POTA Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any contest log can double as a POTA activation — parks picked from a searchable, nearest-first directory in Contest Setup and stamped per row, their park(s) captured per contact, the grid square filled from the Mac's location, and the one ADIF export emitting POTA-creditable records — while every non-POTA log's scoring, Cabrillo, and ADIF stay byte-identical.

**Architecture:** Additive schema (`ContestLog.myPotaRefs: [String]`, `QSO.myPotaRefs/theirPotaRefs: [String]?`, all defaulted) on the `exchangeName` → `nameSent` stamp-at-logging idiom; a `PotaRef` grammar type; `AdifExporter` duplicating each row's record per (my park × their park) pair the way POTA's park-to-park reference documents; a cached park directory from POTA's own API on the `SCPClient`/`SCPStore` pattern; pure `Maidenhead` grid math plus a `LocationProviding` seam over Core Location; universal UI seams with zero party branching.

**Tech Stack:** Swift 6 / SwiftUI / XCTest, XcodeGen, CoreLocation. Design + verbatim source quotes: `docs/superpowers/specs/2026-08-05-pota-activation-design.md`.

**Repo execution notes (from standing project practice):**
- Build/test **always** with `set -o pipefail` in front of piped `xcodebuild` (a `| tee | grep` once masked a failed build as exit 0). Keep the **full** log file for any failure; never judge from a `tail`.
- `project.yml` globs `Sources/` and `Tests/`, but the tracked `QSOPartyLogger.xcodeproj/project.pbxproj` is generated — any task that **adds files or edits project.yml** must run `xcodegen generate` and stage the pbxproj (and, for Task 9, the regenerated `Resources/Info.plist` and `Resources/QSOPartyLogger.entitlements`) in that task's commit. That is Tasks 2, 7, 8, 9, and 10.
- SwiftUI Form rows: one labelled field per row; label placement bugs pass every test, so UI tasks end with a **build** and Tom eyeballs the sheet himself — never claim the layout is right from code.
- `MainView.swift` is at its type-checker budget: touch it only at existing callsites, adding arguments whose values are simple stored-property expressions.
- Run the narrow `-only-testing` suite while iterating a task; the **full suite** runs in Task 12 (and any earlier time you suspect fallout).
- Tests never touch the network or Core Location — every client goes through its scripted seam (constitution Article 5's spirit).

---

### Task 1: Bank the official sources

**Files:**
- Create: `docs/research/pota/SOURCES.md`

- [ ] **Step 1: Write the sources file**

```markdown
# POTA support — banked official sources

All sources fetched/verified 2026-08-05. N1MM and other loggers were not
consulted; the ADIF specification and POTA's own documentation and API are
the only sources of the field names, grammar, upload semantics, and park
data below.

## ADIF 3.1.4 specification
`https://adif.org/314/ADIF_314.htm` (fetched 2026-08-05)

- `MY_POTA_REF` — data type **POTARefList** — "a comma-delimited list of one
  or more of the logging station's POTA (Parks on the Air) reference(s)."
  Spec examples: `<MY_POTA_REF:6>K-0059`, `<MY_POTA_REF:7>K-10000`,
  `<MY_POTA_REF:40>K-0817,K-4566,K-4576,K-4573,K-4578@US-WY`.
- `POTA_REF` — data type **POTARefList** — the same for the contacted
  station. Examples: `<POTA_REF:6>K-5033`, `<POTA_REF:13>VE-5082@CA-AB`.
- **POTARef** — "a sequence of case-insensitive Characters representing a
  Parks on the Air park reference in the form `xxxx-nnnnn[@yyyyyy]`":
  program 1–4 characters, park number 4–5 digits (`K-10000` example row
  notes 5-digit numbers are reserved for future use), optional `@` + ISO
  3166-2 secondary subdivision of 4–6 characters for a park spanning
  subdivisions. Data-type examples: `K-5033`, `K-10000`, `VE-5082@CA-AB`,
  `8P-0012`, `VK-0556`, `K-4562@US-CA`.
- **POTARefList** — "a comma-delimited list of one or more POTARef items."
- `MY_SIG` / `MY_SIG_INFO` / `SIG` / `SIG_INFO` — String; `SIG_INFO` is "a
  description of the SIG for the contacted station", `MY_SIG_INFO` the same
  for the logging station.
- The changelog adds all of `MY_POTA_REF`, `POTA_REF`, `POTARef`,
  `POTARefList` in 3.1.4.

## POTA ADIF technical reference
`https://docs.pota.app/docs/activator_reference/ADIF_for_POTA_reference.html`
(fetched 2026-08-05)

- Required activator fields: `STATION_CALLSIGN` or `OPERATOR`, `CALL`,
  `QSO_DATE`, `TIME_ON`, `BAND`, `MODE` (submode takes precedence when both
  appear). `AdifExporter` already emits every one of these.
- POTA processes `MY_SIG=POTA` + `MY_SIG_INFO=<park>` for the activator's
  park and `SIG=POTA` + `SIG_INFO=<park>` for park-to-park. The reference
  does not document reading `POTA_REF`/`MY_POTA_REF` at all — the SIG
  family is what earns credit. When `MY_SIG`/`MY_SIG_INFO` are missing or
  invalid, the uploader prompts during upload.
- The park fields matter "primarily when an activator is located at
  multiple parks during the same UTC day" — per-QSO values in one file.
- P2P example, one park per record: `<SIG:4>POTA` `<SIG_INFO:7>CA-0008`.

## POTA park-to-park reference
`https://docs.pota.app/docs/activator_reference/park_2_park.html`
(fetched 2026-08-05)

- "Both activators are strongly recommended (although not required) to
  record the park number of the other activator in the ADIF log file's
  SIG_INFO ADIF field."
- Working a three-fer: "list the same QSO three times in the ADIF log
  file, each with one of the three park references in SIG_INFO, with the
  rest unchanged." Otherwise "you will only get one P2P credit."
- One's own multi-park lines survive the duplicate check only with unique
  park references per line.
- P2P matching: both logs' times within 15 minutes, exact callsigns.

## POTA park data API
Verified live 2026-08-05:

- `GET https://api.pota.app/program/parks/US` — unauthenticated, JSON
  array of **12,938** parks (~2.7 MB). Entry shape, verbatim first entry:
  `{"reference": "US-0001", "name": "Acadia National Park",
  "latitude": 44.31, "longitude": -68.2034, "grid": "FN54vh",
  "locationDesc": "US-ME", "attempts": 636, "activations": 568,
  "qsos": 18900}`. Every entry carried coordinates on the verification
  date; the app decodes them optionally anyway.
- `HEAD` on the same URL → **403 MissingAuthenticationTokenException**
  (API Gateway routes GET only). Consequence: no cheap freshness probe
  exists — the client re-downloads on a weekly throttle or the operator's
  Refresh, and the first download is an explicit button.
- `Tests/Fixtures/pota_parks_sample.json` holds six entries copied
  verbatim from this payload (Acadia plus five DFW-area parks), so the
  tests exercise the real shape.

## What this bakes into the app

- Park references are validated against the POTARef grammar, verbatim above.
- The ADIF export duplicates each row's record per (my park × their park)
  pair with singular `MY_SIG_INFO`/`SIG_INFO` — POTA's documented shape —
  and stamps the matching singular `MY_POTA_REF`/`POTA_REF` on each record
  so no record contradicts itself. A single record carrying the spec's
  comma-list form would be valid ADIF but lose n-fer credit at POTA.
- The park picker searches a cached copy of the US program list and sorts
  by distance from the operator's Core Location fix or grid square — so it
  works offline at the park.
```

- [ ] **Step 2: Commit**

```bash
git add docs/research/pota/SOURCES.md
git commit -m "docs(research): bank ADIF 3.1.4, POTA docs, and api.pota.app evidence for POTA support"
```

---

### Task 2: `PotaRef` — grammar, normalize, list parse

**Files:**
- Create: `Sources/Core/Models/PotaRef.swift`
- Create: `Tests/Core/PotaRefTests.swift`
- Modify: `QSOPartyLogger.xcodeproj/project.pbxproj` (via `xcodegen generate` — never by hand)

- [ ] **Step 1: Write the failing tests**

Create `Tests/Core/PotaRefTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

final class PotaRefTests: XCTestCase {

    // Every accept case is an example row from the ADIF 3.1.4 POTARef data
    // type (docs/research/pota/SOURCES.md), plus the current-era US prefix.
    func testSpecExamplesNormalize() {
        for ref in ["K-5033", "K-10000", "VE-5082@CA-AB", "8P-0012",
                    "VK-0556", "K-4562@US-CA", "US-0817"] {
            XCTAssertEqual(PotaRef.normalize(ref), ref, "spec example \(ref)")
        }
    }

    func testNormalizeTrimsAndUppercases() {
        XCTAssertEqual(PotaRef.normalize(" us-3315 "), "US-3315")
        XCTAssertEqual(PotaRef.normalize("ve-5082@ca-ab"), "VE-5082@CA-AB")
    }

    func testMalformedReferencesAreRejected() {
        for bad in ["US3315",        // no hyphen
                    "US-331",        // 3-digit number
                    "US-123456",     // 6-digit number
                    "US 3315",       // interior space
                    "K-4562@US-CALIF", // suffix over 6 characters
                    "TOOLONG-1234",  // program over 4 characters
                    "-1234", "US-", ""] {
            XCTAssertNil(PotaRef.normalize(bad), "should reject \(bad)")
        }
    }

    func testParseListSplitsNormalizesAndDedupes() throws {
        let refs = try PotaRef.parseList("us-0088, US-4571,US-0088").get()
        XCTAssertEqual(refs, ["US-0088", "US-4571"])
    }

    func testParseListEmptyIsAValidEmptyList() throws {
        XCTAssertEqual(try PotaRef.parseList("").get(), [])
        XCTAssertEqual(try PotaRef.parseList("  ").get(), [])
        XCTAssertEqual(try PotaRef.parseList(" , ").get(), [])
    }

    func testParseListNamesTheBadToken() {
        guard case .failure(let failure) = PotaRef.parseList("US-3315,USA-331") else {
            return XCTFail("expected failure")
        }
        XCTAssertTrue(failure.message.contains("USA-331"), failure.message)
    }
}
```

- [ ] **Step 2: Regenerate the project and verify the tests fail**

```bash
xcodegen generate
```

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/PotaRefTests 2>&1 | tee /tmp/pota-task2-red.log | grep -E "error:|Test Suite|BUILD"
```

Expected: **build failure** — `cannot find 'PotaRef' in scope`. (Compile-error red is the red step for a new type.)

- [ ] **Step 3: Implement `PotaRef`**

Create `Sources/Core/Models/PotaRef.swift`:

```swift
import Foundation

/// Parks on the Air reference grammar.
///
/// ADIF 3.1.4's POTARef data type (adif.org/314/ADIF_314.htm, fetched
/// 2026-08-05): "a sequence of case-insensitive Characters representing a
/// Parks on the Air park reference in the form xxxx-nnnnn[@yyyyyy]" —
/// program 1–4 characters, park number 4–5 digits, optional ISO 3166-2
/// secondary subdivision of 4–6 characters for a park spanning
/// subdivisions (K-4562@US-CA). Quotes banked in
/// docs/research/pota/SOURCES.md.
enum PotaRef {

    struct Failure: Error, Equatable {
        var message: String
    }

    private static let grammar = /[A-Z0-9]{1,4}-[0-9]{4,5}(@[A-Z0-9\-]{4,6})?/

    /// One reference: trimmed, uppercased, grammar-checked. `nil` when the
    /// token is not a POTA reference.
    static func normalize(_ raw: String) -> String? {
        let token = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !token.isEmpty, token.wholeMatch(of: grammar) != nil else { return nil }
        return token
    }

    /// A comma-separated list in the operator's order, exact duplicates
    /// dropped. Empty input is a valid empty list — no parks is a state,
    /// not an error. A bad token names itself, in the same inline voice as
    /// the rest of the app's validation.
    static func parseList(_ raw: String) -> Result<[String], Failure> {
        var refs: [String] = []
        for piece in raw.split(separator: ",") {
            let shown = piece.trimmingCharacters(in: .whitespaces)
            guard !shown.isEmpty else { continue }
            guard let ref = normalize(shown) else {
                return .failure(Failure(
                    message: "'\(shown)' is not a POTA reference — they look "
                        + "like US-3315 or K-4562@US-CA."))
            }
            if !refs.contains(ref) { refs.append(ref) }
        }
        return .success(refs)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/PotaRefTests 2>&1 | tee /tmp/pota-task2-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: `Test Suite 'PotaRefTests' passed` — 6 tests, 0 failures.

- [ ] **Step 5: Commit (pbxproj included — it tracks the two new files)**

```bash
git add Sources/Core/Models/PotaRef.swift Tests/Core/PotaRefTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "feat(pota): PotaRef grammar — normalize and parse park reference lists"
```

---

### Task 3: Additive schema — `QSO`, `ContestLog`, `CountyLineExpander`

**Files:**
- Modify: `Sources/Core/Models/QSO.swift`
- Modify: `Sources/Core/Models/ContestLog.swift`
- Modify: `Sources/Core/Engine/CountyLineExpander.swift`
- Test: `Tests/Core/ModelTests.swift`, `Tests/Core/CountyLineExpanderTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the test class in `Tests/Core/ModelTests.swift`:

```swift
    func testLogsWrittenBeforePotaSupportDecodeUnchanged() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.qsos = [QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                        rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN")]
        // A pre-POTA .qplog is today's encoding minus the new keys.
        let data = try log.encoded()
        var json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "myPotaRefs")
        var qsos = try XCTUnwrap(json["qsos"] as? [[String: Any]])
        qsos[0].removeValue(forKey: "myPotaRefs")
        qsos[0].removeValue(forKey: "theirPotaRefs")
        json["qsos"] = qsos
        let legacy = try JSONSerialization.data(withJSONObject: json)

        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertEqual(decoded.myPotaRefs, [])
        XCTAssertNil(decoded.qsos[0].myPotaRefs)
        XCTAssertNil(decoded.qsos[0].theirPotaRefs)
    }

    func testParksRoundTripThroughTheDocumentEncoding() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myPotaRefs = ["US-3315", "US-4571"]
        log.qsos = [QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                        rstSent: "599", rstRcvd: "599",
                        myPotaRefs: ["US-3315", "US-4571"],
                        theirPotaRefs: ["US-0088"],
                        myLoc: "TX", theirLoc: "MRN")]
        let decoded = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(decoded.myPotaRefs, ["US-3315", "US-4571"])
        XCTAssertEqual(decoded.qsos[0].myPotaRefs, ["US-3315", "US-4571"])
        XCTAssertEqual(decoded.qsos[0].theirPotaRefs, ["US-0088"])
    }

    func testEmptyParkArraysNormalizeToNilOnConstruction() {
        let q = QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "599",
                    myPotaRefs: [], theirPotaRefs: [],
                    myLoc: "TX", theirLoc: "MRN")
        XCTAssertNil(q.myPotaRefs)
        XCTAssertNil(q.theirPotaRefs)
    }
```

Append to the test class in `Tests/Core/CountyLineExpanderTests.swift`:

```swift
    func testParksRideEveryExpandedRow() {
        let rows = CountyLineExpander.expand(
            entry: .init(call: "W0BH", rstSent: "599", rstRcvd: "599",
                         myPotaRefs: ["US-3315", "US-4571"],
                         theirPotaRefs: ["US-0088"],
                         band: .m20, modeClass: .cw, rawMode: "CW",
                         freqKHz: nil, timestampUTC: Date()),
            myLocs: ["CHA", "MOR"], theirLocs: ["TX"])
        XCTAssertEqual(rows.count, 2)
        for row in rows {
            XCTAssertEqual(row.myPotaRefs, ["US-3315", "US-4571"],
                           "one contact, one park set — every row carries it")
            XCTAssertEqual(row.theirPotaRefs, ["US-0088"])
        }
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ModelTests -only-testing:QSOPartyLoggerTests/CountyLineExpanderTests 2>&1 | tee /tmp/pota-task3-red.log | grep -E "error:|Test Suite|BUILD"
```

Expected: **build failure** — `extra arguments 'myPotaRefs', 'theirPotaRefs' in call` / `value of type 'ContestLog' has no member 'myPotaRefs'`.

- [ ] **Step 3: Add the fields**

In `Sources/Core/Models/QSO.swift`, after the `memberSent`/`memberRcvd` declarations and **before** `myLoc`:

```swift
    /// POTA park references each way, for contests run from a park. Mine are
    /// stamped at logging from Contest Setup's current value
    /// (`ContestLog.myPotaRefs`); theirs is what a park-to-park station
    /// gave. `nil` — never an empty array — when a side has no parks, so
    /// logs written before POTA support decode unchanged and export
    /// byte-identically.
    var myPotaRefs: [String]?
    var theirPotaRefs: [String]?
```

In the memberwise `init`, add parameters between `memberRcvd` and `myLoc` (order matters — callers pass labels in declaration order):

```swift
        memberRcvd: String? = nil,
        myPotaRefs: [String]? = nil,
        theirPotaRefs: [String]? = nil,
        myLoc: String,
```

and in the body, next to the other assignments:

```swift
        self.myPotaRefs = (myPotaRefs?.isEmpty ?? true) ? nil : myPotaRefs
        self.theirPotaRefs = (theirPotaRefs?.isEmpty ?? true) ? nil : theirPotaRefs
```

(`QSO` uses synthesized `Codable`; optionals decode as `nil` when the key is absent, so no decoder changes.)

In `Sources/Core/Models/ContestLog.swift`:

1. After the `entryClassID` property:

```swift
    /// POTA park reference(s) this contest is being operated from — the
    /// *current* Contest Setup value, normalized park references. Stamped
    /// into each row's `myPotaRefs` at logging (the `exchangeName` idiom),
    /// so a mid-contest park change affects later rows only. Empty for
    /// every log that is not an activation — and for documents written
    /// before the setting existed.
    var myPotaRefs: [String] = []
```

2. Memberwise `init`: add parameter `myPotaRefs: [String] = []` after `entryClassID: String = ""`, and `self.myPotaRefs = myPotaRefs` in the body.

3. `CodingKeys`: append `myPotaRefs` to the second case line:

```swift
        case exchangeName, exchangeMember, entryClassID, usedSpots, myPotaRefs
```

4. `init(from:)`, beside the other `decodeIfPresent` lines:

```swift
        // Documents written before POTA support carry no parks.
        myPotaRefs = try c.decodeIfPresent([String].self, forKey: .myPotaRefs) ?? []
```

In `Sources/Core/Engine/CountyLineExpander.swift`, in `QSOEntry` after `memberRcvd` and before `band`:

```swift
        /// One contact, one park set each way, for the same reason.
        var myPotaRefs: [String]? = nil
        var theirPotaRefs: [String]? = nil
```

and pass both through in the `QSO(...)` construction inside `expand`, between `memberRcvd:` and `myLoc:`:

```swift
                    memberRcvd: entry.memberRcvd,
                    myPotaRefs: entry.myPotaRefs,
                    theirPotaRefs: entry.theirPotaRefs,
                    myLoc: mine,
```

- [ ] **Step 4: Run to verify they pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ModelTests -only-testing:QSOPartyLoggerTests/CountyLineExpanderTests 2>&1 | tee /tmp/pota-task3-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: both suites `passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/QSO.swift Sources/Core/Models/ContestLog.swift Sources/Core/Engine/CountyLineExpander.swift Tests/Core/ModelTests.swift Tests/Core/CountyLineExpanderTests.swift
git commit -m "feat(pota): additive park fields on ContestLog, QSO, and the expander"
```

---

### Task 4: ADIF export — one record per park pair

**Files:**
- Modify: `Sources/Core/Export/AdifExporter.swift` (the `record` function)
- Test: `Tests/Core/AdifExporterTests.swift`, `Tests/Core/ScoreEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `AdifExporterTests` in `Tests/Core/AdifExporterTests.swift` (the class already has `makeLog()`, `ksqp`, and `t`):

```swift
    // MARK: POTA

    /// The whole existing suite is the byte-identity guarantee for non-POTA
    /// logs; this pins the absence of the six new fields. "<sig" would also
    /// match nothing else: "station_callsign" contains "sig" but not "<sig".
    func testNoParksEmitsNoPotaFieldsAndOneRecord() {
        let text = AdifExporter.export(log: makeLog(), party: ksqp)
        XCTAssertFalse(text.contains("<my_sig"))
        XCTAssertFalse(text.contains("<sig"))
        XCTAssertFalse(text.contains("pota_ref"))
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 1)
    }

    func testActivationStampsTheMySigTripletOnTheRecord() {
        var log = makeLog()
        log.qsos[0].myPotaRefs = ["US-3315"]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertTrue(text.contains("<my_sig:4>POTA"))
        XCTAssertTrue(text.contains("<my_sig_info:7>US-3315"))
        XCTAssertTrue(text.contains("<my_pota_ref:7>US-3315"))
        XCTAssertFalse(text.contains("<sig:"), "no P2P side on this row")
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 1)
    }

    /// POTA's park-to-park reference: "list the same QSO three times in the
    /// ADIF log file, each with one of the three park references in
    /// SIG_INFO, with the rest unchanged."
    func testWorkingAThreeFerDuplicatesTheRecordPerPark() {
        var log = makeLog()
        log.qsos[0].myPotaRefs = ["US-3315"]
        log.qsos[0].theirPotaRefs = ["US-0088", "US-0119", "US-0705"]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: "<sig:4>POTA").count - 1, 3)
        for park in ["US-0088", "US-0119", "US-0705"] {
            XCTAssertTrue(text.contains("<sig_info:7>\(park)"))
            XCTAssertTrue(text.contains("<pota_ref:7>\(park)"))
        }
        // "with the rest unchanged" — every copy repeats the QSO's facts.
        XCTAssertEqual(text.components(separatedBy: "<call:4>W0BH").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: "<time_on:6>143200").count - 1, 3)
        XCTAssertEqual(text.components(separatedBy: "<my_sig_info:7>US-3315").count - 1, 3)
    }

    /// My two-fer working their two-fer: the cross product, each record
    /// naming exactly one (mine, theirs) pair — no record contradicts
    /// itself. `field()` writes a trailing space, so adjacency is testable.
    func testTwoFerWorkingATwoFerEmitsTheCrossProduct() {
        var log = makeLog()
        log.qsos[0].myPotaRefs = ["US-3315", "US-4571"]
        log.qsos[0].theirPotaRefs = ["US-0088", "US-0119"]
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 4)
        for (mine, theirs) in [("US-3315", "US-0088"), ("US-3315", "US-0119"),
                               ("US-4571", "US-0088"), ("US-4571", "US-0119")] {
            XCTAssertTrue(text.contains(
                "<my_sig:4>POTA <my_sig_info:7>\(mine) <my_pota_ref:7>\(mine) "
                + "<sig:4>POTA <sig_info:7>\(theirs) <pota_ref:7>\(theirs) "),
                "missing pair \(mine) × \(theirs)")
        }
    }

    /// County-line rows each carry the parks (the expander stamps every row
    /// of the contact), and each emits its own park-stamped record.
    func testCountyLineRowsEachCarryThePark() {
        var log = makeLog()
        let counties = ksqp.counties.prefix(2).map(\.abbr)
        log.myLocation = .inState(counties: Array(counties))
        log.qsos = CountyLineExpander.expand(
            entry: .init(call: "W0BH", rstSent: "599", rstRcvd: "599",
                         myPotaRefs: ["US-3315"],
                         band: .m20, modeClass: .cw, rawMode: "CW",
                         freqKHz: nil, timestampUTC: t),
            myLocs: Array(counties), theirLocs: ["TX"])
        let text = AdifExporter.export(log: log, party: ksqp)
        XCTAssertEqual(text.components(separatedBy: "<eor>").count - 1, 2)
        XCTAssertEqual(text.components(separatedBy: "<my_sig_info:7>US-3315").count - 1, 2)
    }
```

Append to the test class in `Tests/Core/ScoreEngineTests.swift`:

```swift
    /// POTA is orthogonal to every party: stamping parks moves nothing in
    /// the score.
    func testPotaParksDoNotChangeTheScore() throws {
        let party = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let abbrs = party.counties.prefix(2).map(\.abbr)
        log.qsos = abbrs.map { county in
            QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: county)
        }
        let bare = ScoreEngine.score(log: log, party: party)

        log.myPotaRefs = ["US-3315"]
        for i in log.qsos.indices {
            log.qsos[i].myPotaRefs = ["US-3315"]
            log.qsos[i].theirPotaRefs = ["US-0088"]
        }
        let parked = ScoreEngine.score(log: log, party: party)
        XCTAssertEqual(parked.total, bare.total)
        XCTAssertEqual(parked.dupeRowIDs, bare.dupeRowIDs)
    }
```

- [ ] **Step 2: Run to verify the new export tests fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/AdifExporterTests -only-testing:QSOPartyLoggerTests/ScoreEngineTests 2>&1 | tee /tmp/pota-task4-red.log | grep -E "error:|Test Suite|failed|BUILD"
```

Expected: `testActivationStamps…`, `testWorkingAThreeFer…`, `testTwoFer…`, `testCountyLine…` **fail** on the missing fields / record counts (real red — the schema exists, the exporter doesn't emit yet). `testNoParks…` and the score test pass already.

- [ ] **Step 3: Implement the pair expansion**

In `Sources/Core/Export/AdifExporter.swift`, replace the whole tail of `record(...)` — everything from `r += field("station_callsign", myCall)` through `return r` — with:

```swift
        // POTA: one emitted record per (my park × their park) pair. POTA's
        // park-to-park reference is explicit — "list the same QSO three
        // times in the ADIF log file, each with one of the three park
        // references in SIG_INFO, with the rest unchanged" — and its
        // uploader reads a single park per record from MY_SIG_INFO /
        // SIG_INFO, deduping by park reference. The ADIF 3.1.4 list form
        // (POTARefList) would be valid spec but lose n-fer credit, so each
        // record carries the singular MY_POTA_REF / POTA_REF that matches
        // its SIG fields instead (docs/research/pota/SOURCES.md). A row
        // with no parks takes each loop once and emits zero new fields —
        // byte-identical to every log before POTA support.
        let myParks: [String?] = (q.myPotaRefs?.isEmpty ?? true)
            ? [nil] : q.myPotaRefs!.map(Optional.some)
        let theirParks: [String?] = (q.theirPotaRefs?.isEmpty ?? true)
            ? [nil] : q.theirPotaRefs!.map(Optional.some)
        var records = ""
        for myPark in myParks {
            for theirPark in theirParks {
                var rec = r
                if let myPark {
                    rec += field("my_sig", "POTA")
                    rec += field("my_sig_info", myPark)
                    rec += field("my_pota_ref", myPark)
                }
                if let theirPark {
                    rec += field("sig", "POTA")
                    rec += field("sig_info", theirPark)
                    rec += field("pota_ref", theirPark)
                }
                rec += field("station_callsign", myCall)
                rec += field("operator", myCall)
                rec += field("app_qsopartylogger_groupid", q.groupID.uuidString)
                rec += "<eor>\n"
                records += rec
            }
        }
        return records
```

- [ ] **Step 4: Run to verify everything passes**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/AdifExporterTests -only-testing:QSOPartyLoggerTests/ScoreEngineTests -only-testing:QSOPartyLoggerTests/ArchivedLogExportTests 2>&1 | tee /tmp/pota-task4-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: all three suites `passed` (`ArchivedLogExportTests` proves the dashboard's re-export path is untouched — it re-runs this exporter).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Export/AdifExporter.swift Tests/Core/AdifExporterTests.swift Tests/Core/ScoreEngineTests.swift
git commit -m "feat(pota): ADIF export emits one record per park pair, POTA-style"
```

---

### Task 5: Stamp at logging; capture and validate the P2P park

**Files:**
- Modify: `Sources/App/EntryState.swift`
- Modify: `Sources/App/EntryFlow.swift` (`logContact`)
- Modify: `Sources/App/LogDocument.swift` (`updateStation`)
- Test: `Tests/App/EntryFlowTests.swift`, `Tests/App/LogDocumentTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the test class in `Tests/App/EntryFlowTests.swift` (fixtures `cqpDocument(mode:)` and `context()` already exist there; CQP out-of-state completes a row with `entry.exchange = "TX"`):

```swift
    // MARK: POTA

    func testActivationStampsMyParksOnEveryLoggedRow() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315", "US-4571"]
        let flow = EntryFlow(document: doc)
        flow.entry.call = "W6ABC"
        flow.entry.exchange = "TX"
        flow.revalidate(context())
        guard case .logged(let rows, _) = flow.returnPressed(context(), undoManager: nil) else {
            return XCTFail("should log")
        }
        XCTAssertEqual(rows.map(\.myPotaRefs), [["US-3315", "US-4571"]])
        XCTAssertNil(rows[0].theirPotaRefs)
    }

    func testNoActivationStampsNil() throws {
        let flow = EntryFlow(document: cqpDocument(mode: .searchPounce))
        flow.entry.call = "W6ABC"
        flow.entry.exchange = "TX"
        flow.revalidate(context())
        guard case .logged(let rows, _) = flow.returnPressed(context(), undoManager: nil) else {
            return XCTFail("should log")
        }
        XCTAssertNil(rows[0].myPotaRefs)
    }

    func testTheirParkIsParsedNormalizedAndCleared() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315"]
        let flow = EntryFlow(document: doc)
        flow.entry.call = "W6ABC"
        flow.entry.exchange = "TX"
        flow.entry.theirParkTyped = "us-0088, us-0119"
        flow.revalidate(context())
        guard case .logged(let rows, _) = flow.returnPressed(context(), undoManager: nil) else {
            return XCTFail("should log")
        }
        XCTAssertEqual(rows[0].theirPotaRefs, ["US-0088", "US-0119"])
        XCTAssertEqual(flow.entry.theirParkTyped, "", "cleared for the next contact")
    }

    /// An unparseable park refuses to log, exactly as an unreadable member
    /// element does — the reference decides P2P credit, and a mis-keyed one
    /// must not be logged in silence.
    func testMalformedTheirParkRefusesToLog() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315"]
        let flow = EntryFlow(document: doc)
        flow.entry.call = "W6ABC"
        flow.entry.exchange = "TX"
        flow.entry.theirParkTyped = "USA-331"
        flow.revalidate(context())
        guard case .nothing = flow.returnPressed(context(), undoManager: nil) else {
            return XCTFail("must not log a garbled park reference")
        }
        XCTAssertTrue(doc.log.qsos.isEmpty)
        XCTAssertTrue(flow.entry.invalidTheirPark())
    }
```

Append to the test class in `Tests/App/LogDocumentTests.swift`:

```swift
    @MainActor
    func testUpdateStationPersistsAndUndoesMyParks() {
        let doc = LogDocument()
        let undo = UndoManager()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            myPotaRefs: ["US-3315"],
            undoManager: undo
        )
        XCTAssertEqual(doc.log.myPotaRefs, ["US-3315"])
        undo.undo()
        XCTAssertEqual(doc.log.myPotaRefs, [])
    }
```

(If the class already carries `@MainActor`, drop the attribute from the method.)

- [ ] **Step 2: Run to verify they fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests -only-testing:QSOPartyLoggerTests/LogDocumentTests 2>&1 | tee /tmp/pota-task5-red.log | grep -E "error:|Test Suite|BUILD"
```

Expected: **build failure** — `no member 'theirParkTyped'`, `no member 'invalidTheirPark'`, `extra argument 'myPotaRefs' in call`.

- [ ] **Step 3: Implement**

`Sources/App/EntryState.swift` — beside the other received-element state (near `memberRcvd`, line ~96):

```swift
    /// Park-to-park: the other station's POTA reference(s) as typed, comma
    /// separated. Empty for the overwhelming majority of contest contacts.
    var theirParkTyped = ""
```

Beside `invalidMember(party:)` (line ~231):

```swift
    /// An unparseable P2P park blocks logging the way an unreadable member
    /// element does: the reference decides park-to-park credit. Empty is
    /// always fine.
    func invalidTheirPark() -> Bool {
        if case .failure = PotaRef.parseList(theirParkTyped) { return true }
        return false
    }
```

In `clearForNextContact(modeClass:)` (line ~304), beside `memberRcvd = ""`:

```swift
        theirParkTyped = ""
```

`Sources/App/EntryFlow.swift`, in `logContact` — after the `invalidMember` guard (line ~341) add:

```swift
        // One contact, one park set each way. An unparseable P2P park is
        // refused like an unreadable member element — it decides credit.
        guard case .success(let theirParks) = PotaRef.parseList(entry.theirParkTyped) else {
            return .nothing
        }
        // Mine is the log's current Setup value, stamped per row so the
        // record shows where the contact was actually made from — a
        // mid-contest park change affects later rows only.
        let myParks = document.log.myPotaRefs
```

and in the `CountyLineExpander.expand(entry: .init(...))` call, between `memberRcvd:` and `band:`:

```swift
                memberRcvd: rcvdMember,
                myPotaRefs: myParks.isEmpty ? nil : myParks,
                theirPotaRefs: theirParks.isEmpty ? nil : theirParks,
                band: context.band,
```

`Sources/App/LogDocument.swift`, in `updateStation`:

1. Parameter list — after `entryClassID: String? = nil,`:

```swift
        myPotaRefs: [String]? = nil,
```

2. Old-value capture — beside `let oldEntryClassID`:

```swift
        let oldMyPotaRefs = log.myPotaRefs
```

3. Assignment — beside the other `if let` blocks (values arrive already
   normalized by the callers — the picker adds only grammar-checked refs):

```swift
        if let myPotaRefs {
            log.myPotaRefs = myPotaRefs
        }
```

4. Undo closure — add the argument to the nested `doc.updateStation(...)` call:

```swift
                    entryClassID: oldEntryClassID, myPotaRefs: oldMyPotaRefs,
                    undoManager: undoManager
```

- [ ] **Step 4: Run to verify they pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests -only-testing:QSOPartyLoggerTests/LogDocumentTests 2>&1 | tee /tmp/pota-task5-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: both suites `passed` — including every pre-existing EntryFlow test (`theirParkTyped` defaults empty, which parses to `[]`, so nothing else moves).

- [ ] **Step 5: Commit**

```bash
git add Sources/App/EntryState.swift Sources/App/EntryFlow.swift Sources/App/LogDocument.swift Tests/App/EntryFlowTests.swift Tests/App/LogDocumentTests.swift
git commit -m "feat(pota): stamp my parks at logging; parse, validate, and clear the P2P park"
```

---

### Task 6: Bulk edit — my parks across selected rows

**Files:**
- Modify: `Sources/Core/Engine/BulkEdit.swift`
- Modify: `Sources/UI/BulkEditSheet.swift`
- Test: `Tests/Core/BulkEditTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the test class in `Tests/Core/BulkEditTests.swift`:

```swift
    // MARK: POTA

    func testMyParksIsOfferedForEveryParty() {
        XCTAssertTrue(BulkEdit.fields(for: nil).contains(.myPotaRefs))
        XCTAssertEqual(BulkEdit.label(.myPotaRefs, party: nil), "My POTA park(s)")
    }

    func testApplyMyParksNormalizesAcrossRows() throws {
        let rows = [
            QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"),
            QSO(call: "K5XYZ", band: .m40, modeClass: .cw, rawMode: "CW",
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN"),
        ]
        let changed = try BulkEdit.apply(
            .text("us-3315, us-4571"), field: .myPotaRefs, to: rows,
            party: nil, isInState: false).get()
        XCTAssertEqual(changed.map(\.myPotaRefs),
                       [["US-3315", "US-4571"], ["US-3315", "US-4571"]])
    }

    /// Unlike a sent name, an empty park list is a legitimate state — the
    /// stretch of the log worked from home clears to nil, not to [].
    func testApplyEmptyMyParksClearsToNil() throws {
        var row = QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                      rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN")
        row.myPotaRefs = ["US-3315"]
        let changed = try BulkEdit.apply(
            .text("  "), field: .myPotaRefs, to: [row],
            party: nil, isInState: false).get()
        XCTAssertNil(changed[0].myPotaRefs)
    }

    func testApplyMalformedMyParksRefusesTheWholeChange() {
        let row = QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                      rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "MRN")
        guard case .failure(let failure) = BulkEdit.apply(
            .text("USA-331"), field: .myPotaRefs, to: [row],
            party: nil, isInState: false) else {
            return XCTFail("expected refusal")
        }
        XCTAssertTrue(failure.message.contains("USA-331"), failure.message)
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/BulkEditTests 2>&1 | tee /tmp/pota-task6-red.log | grep -E "error:|Test Suite|BUILD"
```

Expected: **build failure** — `type 'BulkEdit.Field' has no member 'myPotaRefs'`.

- [ ] **Step 3: Implement**

`Sources/Core/Engine/BulkEdit.swift`:

1. `Field` enum — add a case after `memberSent`:

```swift
        case myPotaRefs
```

2. `fields(for:)` — after the `memberExchange` line, before `return`:

```swift
        // Party-independent: POTA rides any contest. My parks are a
        // station-side fact in exactly the rover's sense — wrong across a
        // stretch of rows, right to fix in one action. Their parks stay
        // per-row (a received fact), per this type's own line.
        fields.append(.myPotaRefs)
```

3. `label(_:party:)` — add to the switch:

```swift
        case .myPotaRefs: "My POTA park(s)"
```

4. `apply(_:field:to:party:isInState:)` — add before the `default:` case:

```swift
        case (.myPotaRefs, .text(let raw)):
            switch PotaRef.parseList(raw) {
            case .failure(let failure):
                return .failure(Failure(message: failure.message))
            case .success(let refs):
                // Empty clears: a park-less stretch is a legitimate state,
                // unlike a nameless one.
                return .success(rows.map { row in
                    var row = row
                    row.myPotaRefs = refs.isEmpty ? nil : refs
                    return row
                })
            }
```

`Sources/UI/BulkEditSheet.swift` — the sheet switches over `BulkEdit.Field` in three places; extend each (find them with `rg -n "case .myLoc, .nameSent, .memberSent" Sources/UI/BulkEditSheet.swift`):

1. Value construction (~line 49): `.myPotaRefs` joins the `.text(text)` list:

```swift
        case .myLoc, .nameSent, .memberSent, .myPotaRefs: .text(text)
```

2. Control choice (~line 131): `.myPotaRefs` joins the text-field list:

```swift
        case .myLoc, .nameSent, .memberSent, .myPotaRefs:
```

3. Seed value (~line 168), beside the other seeds:

```swift
        case .myPotaRefs: return (first.myPotaRefs ?? []).joined(separator: ",")
```

- [ ] **Step 4: Run to verify they pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/BulkEditTests 2>&1 | tee /tmp/pota-task6-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: `Test Suite 'BulkEditTests' passed`, including all pre-existing cases.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Engine/BulkEdit.swift Sources/UI/BulkEditSheet.swift Tests/Core/BulkEditTests.swift
git commit -m "feat(pota): bulk-edit my parks across selected rows"
```

---

### Task 7: `Maidenhead` — grid ↔ coordinates, both directions

**Files:**
- Create: `Sources/Core/Models/Maidenhead.swift`
- Create: `Tests/Core/MaidenheadTests.swift`
- Modify: `QSOPartyLogger.xcodeproj/project.pbxproj` (via `xcodegen generate`)

- [ ] **Step 1: Write the failing tests**

Create `Tests/Core/MaidenheadTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

final class MaidenheadTests: XCTestCase {

    func testKnownAnchors() {
        // W1AW, Newington CT — the canonical FN31PR.
        XCTAssertEqual(Maidenhead.locator(latitude: 41.714775, longitude: -72.727260),
                       "FN31PR")
        // Ray Roberts Lake State Park — POTA's own payload says EM13li.
        XCTAssertEqual(Maidenhead.locator(latitude: 33.3688, longitude: -97.0094),
                       "EM13LI")
        // Southern hemisphere, east longitude: Sydney Opera House.
        XCTAssertEqual(Maidenhead.locator(latitude: -33.8568, longitude: 151.2153),
                       "QF56OD")
        XCTAssertEqual(Maidenhead.locator(latitude: 0, longitude: 0), "JJ00AA")
    }

    func testFarEdgesClampIntoTheLastCell() {
        XCTAssertEqual(Maidenhead.locator(latitude: 90, longitude: 180), "RR99XX")
        XCTAssertEqual(Maidenhead.locator(latitude: -90, longitude: -180), "AA00AA")
    }

    func testOutOfRangeCoordinatesAreRejected() {
        XCTAssertNil(Maidenhead.locator(latitude: 91, longitude: 0))
        XCTAssertNil(Maidenhead.locator(latitude: 0, longitude: 181))
    }

    func testCenterOfSixCharacterGrid() throws {
        let c = try XCTUnwrap(Maidenhead.center(of: "FN31PR"))
        XCTAssertEqual(c.latitude, 41.72917, accuracy: 0.001)
        XCTAssertEqual(c.longitude, -72.70833, accuracy: 0.001)
    }

    func testCenterOfFourCharacterGrid() throws {
        // EM13's center: north Texas.
        let c = try XCTUnwrap(Maidenhead.center(of: "em13"))
        XCTAssertEqual(c.latitude, 33.5, accuracy: 0.0001)
        XCTAssertEqual(c.longitude, -97.0, accuracy: 0.0001)
    }

    func testCenterRejectsNonLocators() {
        for bad in ["", "EM1", "EM13L", "XX99XX", "12AB", "EM1A", "EMAB"] {
            XCTAssertNil(Maidenhead.center(of: bad), "should reject \(bad)")
        }
    }

    func testRoundTripStaysInsideTheSubsquare() throws {
        let grid = try XCTUnwrap(Maidenhead.locator(latitude: 41.714775,
                                                    longitude: -72.727260))
        let c = try XCTUnwrap(Maidenhead.center(of: grid))
        // A subsquare is 2.5' of latitude; the center is within half that.
        XCTAssertEqual(c.latitude, 41.714775, accuracy: 2.5 / 60)
        XCTAssertEqual(c.longitude, -72.727260, accuracy: 5.0 / 60)
    }
}
```

- [ ] **Step 2: Regenerate and verify they fail**

```bash
xcodegen generate
```

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MaidenheadTests 2>&1 | tee /tmp/pota-task7-red.log | grep -E "error:|Test Suite|BUILD"
```

Expected: **build failure** — `cannot find 'Maidenhead' in scope`.

- [ ] **Step 3: Implement**

Create `Sources/Core/Models/Maidenhead.swift`:

```swift
import Foundation

/// Maidenhead grid locator conversions, 6-character field–square–subsquare
/// form (EM13LE). Fills Contest Setup's grid square from Core Location and
/// places the operator for the nearest-parks sort. Cell sizes per the IARU
/// locator system: 18×18 fields of 20°×10°, 10×10 squares of 2°×1°, 24×24
/// subsquares of 5'×2.5'.
enum Maidenhead {

    private static let fields = Array("ABCDEFGHIJKLMNOPQR")
    private static let subsquares = Array("ABCDEFGHIJKLMNOPQRSTUVWX")

    /// The 6-character locator containing a coordinate, uppercased the way
    /// the rest of the app stores grids. `nil` off the globe.
    static func locator(latitude: Double, longitude: Double) -> String? {
        guard latitude >= -90, latitude <= 90,
              longitude >= -180, longitude <= 180 else { return nil }
        // The north pole and the antimeridian sit on the far edge of the
        // last cell; nudge them in so indexing stays in range.
        let lon = min(longitude + 180, 359.999999)
        let lat = min(latitude + 90, 179.999999)
        let f1 = fields[Int(lon / 20)]
        let f2 = fields[Int(lat / 10)]
        let s1 = Int(lon.truncatingRemainder(dividingBy: 20) / 2)
        let s2 = Int(lat.truncatingRemainder(dividingBy: 10))
        let ss1 = subsquares[Int(lon.truncatingRemainder(dividingBy: 2) * 12)]
        let ss2 = subsquares[Int(lat.truncatingRemainder(dividingBy: 1) * 24)]
        return "\(f1)\(f2)\(s1)\(s2)\(ss1)\(ss2)"
    }

    /// The center of a 4- or 6-character locator — the operator's position
    /// when it comes from the typed grid rather than Core Location. `nil`
    /// for anything that is not a locator.
    static func center(of locator: String) -> (latitude: Double, longitude: Double)? {
        let grid = Array(locator.trimmingCharacters(in: .whitespaces).uppercased())
        guard grid.count == 4 || grid.count == 6 else { return nil }
        guard let f1 = fields.firstIndex(of: grid[0]),
              let f2 = fields.firstIndex(of: grid[1]),
              grid[2].isNumber, grid[3].isNumber,
              let s1 = grid[2].wholeNumberValue,
              let s2 = grid[3].wholeNumberValue else { return nil }
        var lon = Double(f1) * 20 + Double(s1) * 2
        var lat = Double(f2) * 10 + Double(s2)
        if grid.count == 6 {
            guard let ss1 = subsquares.firstIndex(of: grid[4]),
                  let ss2 = subsquares.firstIndex(of: grid[5]) else { return nil }
            lon += Double(ss1) * (2.0 / 24) + (2.0 / 48)
            lat += Double(ss2) * (1.0 / 24) + (1.0 / 48)
        } else {
            lon += 1
            lat += 0.5
        }
        return (lat - 90, lon - 180)
    }
}
```

- [ ] **Step 4: Run to verify they pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MaidenheadTests 2>&1 | tee /tmp/pota-task7-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: `Test Suite 'MaidenheadTests' passed` — 7 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/Maidenhead.swift Tests/Core/MaidenheadTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "feat(pota): Maidenhead grid conversions, both directions"
```

---

### Task 8: The park directory — model, search, nearest, disk cache

**Files:**
- Create: `Sources/Core/Pota/PotaPark.swift`
- Create: `Sources/Core/Pota/PotaParkDirectory.swift`
- Create: `Sources/Core/Pota/PotaParkStore.swift`
- Create: `Tests/Fixtures/pota_parks_sample.json`
- Create: `Tests/Core/PotaParkDirectoryTests.swift`
- Create: `Tests/Core/PotaParkStoreTests.swift`
- Modify: `QSOPartyLogger.xcodeproj/project.pbxproj` (via `xcodegen generate`)

- [ ] **Step 1: Write the fixture — real entries, copied verbatim from the payload verified 2026-08-05**

Create `Tests/Fixtures/pota_parks_sample.json`:

```json
[
  {"reference": "US-0001", "name": "Acadia National Park", "latitude": 44.31, "longitude": -68.2034, "grid": "FN54vh", "locationDesc": "US-ME", "attempts": 636, "activations": 568, "qsos": 18900},
  {"reference": "US-2996", "name": "Cedar Hill State Park", "latitude": 32.6195, "longitude": -96.9837, "grid": "EM12mo", "locationDesc": "US-TX", "attempts": 2997, "activations": 2917, "qsos": 181771},
  {"reference": "US-3031", "name": "Lake Tawakoni State Park", "latitude": 32.8482, "longitude": -95.995, "grid": "EM22au", "locationDesc": "US-TX", "attempts": 655, "activations": 634, "qsos": 35533},
  {"reference": "US-3051", "name": "Ray Roberts Lake State Park", "latitude": 33.3688, "longitude": -97.0094, "grid": "EM13li", "locationDesc": "US-TX", "attempts": 2027, "activations": 1914, "qsos": 99281},
  {"reference": "US-4423", "name": "Spring Creek Forest State Preserve", "latitude": 32.9642, "longitude": -96.6572, "grid": "EM12qx", "locationDesc": "US-TX", "attempts": 1985, "activations": 1905, "qsos": 90108},
  {"reference": "US-6605", "name": "Tawakoni Wildlife Management Area", "latitude": 33.0055, "longitude": -95.9912, "grid": "EM23aa", "locationDesc": "US-TX", "attempts": 169, "activations": 167, "qsos": 10399}
]
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/Core/PotaParkDirectoryTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

final class PotaParkDirectoryTests: XCTestCase {

    func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_parks_sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testParsesTheProgramPayloadShape() throws {
        let directory = try XCTUnwrap(PotaParkDirectory.parse(data: fixtureData()))
        XCTAssertEqual(directory.parks.count, 6)
        let acadia = try XCTUnwrap(directory.parks.first { $0.reference == "US-0001" })
        XCTAssertEqual(acadia.name, "Acadia National Park")
        XCTAssertEqual(acadia.locationDesc, "US-ME")
        XCTAssertEqual(acadia.grid, "FN54vh")
        XCTAssertNil(PotaParkDirectory.parse(data: Data("not json".utf8)))
        XCTAssertNil(PotaParkDirectory.parse(data: Data("[]".utf8)),
                     "an empty list would silently disable search — refuse it")
    }

    func testSearchByNameNumberAndState() throws {
        let d = try XCTUnwrap(PotaParkDirectory.parse(data: fixtureData()))
        XCTAssertEqual(d.search("cedar").map(\.reference), ["US-2996"])
        XCTAssertEqual(d.search("3051").map(\.reference), ["US-3051"])
        // Every term must match: two Texas lakes, and never Acadia.
        XCTAssertEqual(Set(d.search("lake tx").map(\.reference)),
                       Set(["US-3051", "US-3031"]))
        XCTAssertEqual(d.search("tawakoni").count, 2)
        XCTAssertEqual(d.search("").count, 0)
        XCTAssertEqual(d.search("zzzz").count, 0)
        XCTAssertEqual(d.search("us-", limit: 3).count, 3, "limit respected")
    }

    func testNearestSortsByGreatCircle() throws {
        let d = try XCTUnwrap(PotaParkDirectory.parse(data: fixtureData()))
        // From Ray Roberts itself: Ray Roberts (~0 km), Spring Creek
        // (~56 km), Cedar Hill (~83 km) — margins wide enough that the
        // order cannot flap.
        let ranked = d.nearest(latitude: 33.3688, longitude: -97.0094, limit: 3)
        XCTAssertEqual(ranked.map(\.park.reference), ["US-3051", "US-4423", "US-2996"])
        XCTAssertEqual(ranked[0].km, 0, accuracy: 0.5)
    }

    func testHaversineSanity() {
        // Dallas to Austin is about 290 km great-circle.
        let km = PotaParkDirectory.distanceKm(from: (32.78, -96.80),
                                              to: (30.27, -97.74))
        XCTAssertEqual(km, 290, accuracy: 15)
    }
}
```

Create `Tests/Core/PotaParkStoreTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

final class PotaParkStoreTests: XCTestCase {

    func tempStore() throws -> PotaParkStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PotaParkStoreTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PotaParkStore(folder: dir)
    }

    func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_parks_sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = try tempStore()
        let fetched = Date(timeIntervalSince1970: 1_754_400_000)
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: fetched, lastCheckedAt: fetched))
        let cached = try XCTUnwrap(store.loadCached())
        XCTAssertEqual(cached.directory.parks.count, 6)
        XCTAssertEqual(store.loadMeta()?.fetchedAt, fetched)
    }

    func testMissingSidecarNeverHidesAReadableFile() throws {
        let store = try tempStore()
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: Date(), lastCheckedAt: Date()))
        try FileManager.default.removeItem(at: store.metaURL)
        XCTAssertEqual(store.loadCached()?.directory.parks.count, 6)
        XCTAssertNil(store.loadCached()?.meta)
    }

    func testEmptyFolderLoadsNothing() throws {
        XCTAssertNil(try tempStore().loadCached())
        XCTAssertNil(try tempStore().loadMeta())
    }
}
```

- [ ] **Step 3: Regenerate and verify they fail**

```bash
xcodegen generate
```

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/PotaParkDirectoryTests -only-testing:QSOPartyLoggerTests/PotaParkStoreTests 2>&1 | tee /tmp/pota-task8-red.log | grep -E "error:|Test Suite|BUILD"
```

Expected: **build failure** — `cannot find 'PotaParkDirectory' in scope`.

- [ ] **Step 4: Implement**

Create `Sources/Core/Pota/PotaPark.swift`:

```swift
import Foundation

/// One park from POTA's program list — the subset of api.pota.app's
/// per-program payload the app uses (verified 2026-08-05; entry shape
/// banked in docs/research/pota/SOURCES.md). Upstream's extra keys
/// (attempts, activations, qsos) decode to nothing by not being declared.
struct PotaPark: Codable, Equatable, Hashable, Sendable, Identifiable {
    let reference: String
    let name: String
    /// Every entry carried coordinates on the verification date; optional
    /// anyway, so an upstream null tomorrow degrades one park's sorting
    /// rather than the whole file's parse.
    let latitude: Double?
    let longitude: Double?
    let grid: String?
    /// Upstream's location tag, e.g. "US-TX" — keeps two same-named parks
    /// in different states tellable apart, and makes "lake tx" work.
    let locationDesc: String?

    var id: String { reference }
}
```

Create `Sources/Core/Pota/PotaParkDirectory.swift`:

```swift
import Foundation

/// The searchable park list: parse, name/number search, nearest sort.
/// Pure — no disk, no network; `PotaParkStore` and `PotaParkClient` own
/// those.
struct PotaParkDirectory: Equatable, Sendable {
    let parks: [PotaPark]

    /// A park and how far away it is, for the nearest list.
    struct Ranked: Equatable, Sendable {
        let park: PotaPark
        let km: Double
    }

    /// `nil` for anything that is not a non-empty park array — an empty
    /// list would silently disable search, which must read as a failed
    /// download, not a successful empty one.
    static func parse(data: Data) -> PotaParkDirectory? {
        guard let parks = try? JSONDecoder().decode([PotaPark].self, from: data),
              !parks.isEmpty else { return nil }
        return PotaParkDirectory(parks: parks)
    }

    /// Name-or-number search: every whitespace-separated term must match
    /// the name, the reference, or the location tag — "lake tx" finds
    /// Texas lakes, "0088" finds US-0088, "cedar hill" finds the park.
    /// Case-insensitive, capped so the sheet never lays out thousands of
    /// rows.
    func search(_ query: String, limit: Int = 30) -> [PotaPark] {
        let terms = query.uppercased()
            .split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return [] }
        var out: [PotaPark] = []
        for park in parks {
            let name = park.name.uppercased()
            let location = (park.locationDesc ?? "").uppercased()
            let matches = terms.allSatisfy { term in
                name.contains(term) || park.reference.contains(term)
                    || location.contains(term)
            }
            if matches {
                out.append(park)
                if out.count == limit { break }
            }
        }
        return out
    }

    /// The parks nearest a coordinate — the "you are here" pre-listing.
    /// Parks without coordinates simply never rank.
    func nearest(latitude: Double, longitude: Double, limit: Int = 12) -> [Ranked] {
        parks
            .compactMap { park -> Ranked? in
                guard let plat = park.latitude, let plon = park.longitude
                else { return nil }
                return Ranked(park: park,
                              km: Self.distanceKm(from: (latitude, longitude),
                                                  to: (plat, plon)))
            }
            .sorted { $0.km < $1.km }
            .prefix(limit)
            .map { $0 }
    }

    /// Haversine on a spherical Earth — sorting accuracy, not survey
    /// accuracy.
    static func distanceKm(from a: (Double, Double), to b: (Double, Double)) -> Double {
        let radius = 6371.0
        let dLat = (b.0 - a.0) * .pi / 180
        let dLon = (b.1 - a.1) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.0 * .pi / 180) * cos(b.0 * .pi / 180)
            * sin(dLon / 2) * sin(dLon / 2)
        return 2 * radius * asin(min(1, sqrt(h)))
    }
}
```

Create `Sources/Core/Pota/PotaParkStore.swift`:

```swift
import Foundation

/// The on-disk cache of the downloaded park list: the bytes exactly as the
/// server sent them plus a meta sidecar, in the app's own Application
/// Support folder — a temp dir in tests. `SCPStore`'s shape and failure
/// posture: the cache is a convenience, and a missing or unreadable
/// sidecar never hides a readable file.
struct PotaParkStore: Sendable {
    let folder: URL

    /// `~/Library/Application Support/QSOPartyLogger/POTA`
    /// (container-relative when sandboxed), beside the SCP cache.
    static var defaultFolder: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/POTA", isDirectory: true)
    }

    /// `SCPStore.Meta` minus the release token: api.pota.app rejects HEAD
    /// (403 — docs/research/pota/SOURCES.md), so there is no freshness
    /// header to hold and the dates are the whole bookkeeping.
    struct Meta: Codable, Equatable, Sendable {
        let fetchedAt: Date
        var lastCheckedAt: Date
    }

    struct Cached: Equatable, Sendable {
        let directory: PotaParkDirectory
        let meta: Meta?
    }

    var fileURL: URL { folder.appendingPathComponent("parks-US.json") }
    var metaURL: URL { folder.appendingPathComponent("parks-US.meta.json") }

    func loadCached() -> Cached? {
        guard let data = try? Data(contentsOf: fileURL),
              let directory = PotaParkDirectory.parse(data: data)
        else { return nil }
        return Cached(directory: directory, meta: loadMeta())
    }

    func loadMeta() -> Meta? {
        guard let data = try? Data(contentsOf: metaURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Meta.self, from: data)
    }

    /// Install a download: bytes exactly as served, sidecar alongside,
    /// both atomic. The caller has already parsed and verified the bytes.
    func save(data: Data, meta: Meta) throws {
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(meta).write(to: metaURL, options: .atomic)
    }
}
```

- [ ] **Step 5: Run to verify they pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/PotaParkDirectoryTests -only-testing:QSOPartyLoggerTests/PotaParkStoreTests 2>&1 | tee /tmp/pota-task8-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: both suites `passed`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Pota Tests/Core/PotaParkDirectoryTests.swift Tests/Core/PotaParkStoreTests.swift Tests/Fixtures/pota_parks_sample.json QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "feat(pota): park directory — model, search, nearest sort, disk cache"
```

---

### Task 9: `PotaParkClient`, the location seam, and the sandbox plumbing

**Files:**
- Create: `Sources/App/PotaParkClient.swift`
- Create: `Sources/App/LocationProvider.swift`
- Create: `Tests/App/PotaParkClientTests.swift`
- Modify: `project.yml` (location entitlement + usage string)
- Modify (regenerated): `QSOPartyLogger.xcodeproj/project.pbxproj`, `Resources/Info.plist`, `Resources/QSOPartyLogger.entitlements`

- [ ] **Step 1: Write the failing client tests**

Create `Tests/App/PotaParkClientTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

@MainActor
final class PotaParkClientTests: XCTestCase {

    final class ScriptedFetcher: PotaParkFetching, @unchecked Sendable {
        var result: Result<Data, Error> = .failure(URLError(.notConnectedToInternet))
        private(set) var gets = 0
        func get(_ url: URL) async throws -> Data {
            gets += 1
            return try result.get()
        }
    }

    func tempStore() throws -> PotaParkStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PotaParkClientTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return PotaParkStore(folder: dir)
    }

    func fixtureData() throws -> Data {
        let url = try XCTUnwrap(Bundle(for: Self.self)
            .url(forResource: "pota_parks_sample", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    func testExplicitDownloadInstallsAndPublishes() async throws {
        let store = try tempStore()
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: store, fetcher: fetcher)
        await client.download()
        XCTAssertEqual(client.status, .ready(parks: 6))
        XCTAssertEqual(client.directory?.parks.count, 6)
        XCTAssertNotNil(store.loadMeta())
    }

    func testRefreshIfStaleNeverStartsTheFirstDownload() async throws {
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: try tempStore(), fetcher: fetcher)
        await client.refreshIfStale()
        XCTAssertEqual(fetcher.gets, 0, "the first download is the explicit button")
        XCTAssertEqual(client.status, .idle)
    }

    func testFreshCacheIsNotReDownloadedButForceIs() async throws {
        let store = try tempStore()
        let now = Date()
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: now, lastCheckedAt: now))
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: store, fetcher: fetcher)
        await client.refreshIfStale(now: now.addingTimeInterval(60))
        XCTAssertEqual(fetcher.gets, 0, "well inside the weekly throttle")
        await client.refreshIfStale(now: now.addingTimeInterval(60), force: true)
        XCTAssertEqual(fetcher.gets, 1, "Refresh is the operator's override")
    }

    func testStaleCacheReDownloads() async throws {
        let store = try tempStore()
        let old = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: old, lastCheckedAt: old))
        let fetcher = ScriptedFetcher()
        fetcher.result = .success(try fixtureData())
        let client = PotaParkClient(store: store, fetcher: fetcher)
        await client.refreshIfStale()
        XCTAssertEqual(fetcher.gets, 1)
        XCTAssertEqual(client.status, .ready(parks: 6))
    }

    func testFailedRefreshKeepsTheCachedDirectory() async throws {
        let store = try tempStore()
        let old = Date().addingTimeInterval(-8 * 24 * 60 * 60)
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: old, lastCheckedAt: old))
        let client = PotaParkClient(store: store, fetcher: ScriptedFetcher())
        await client.refreshIfStale()
        XCTAssertEqual(client.directory?.parks.count, 6,
                       "whatever is cached stays in service")
        guard case .failed = client.status else {
            return XCTFail("failure belongs in the status line")
        }
    }

    func testPublishCachedTouchesNoNetwork() async throws {
        let store = try tempStore()
        try store.save(data: fixtureData(),
                       meta: .init(fetchedAt: Date(), lastCheckedAt: Date()))
        let fetcher = ScriptedFetcher()
        let client = PotaParkClient(store: store, fetcher: fetcher)
        client.publishCached()
        XCTAssertEqual(client.status, .ready(parks: 6))
        XCTAssertEqual(fetcher.gets, 0)
    }
}
```

- [ ] **Step 2: Regenerate and verify they fail**

```bash
xcodegen generate
```

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/PotaParkClientTests 2>&1 | tee /tmp/pota-task9-red.log | grep -E "error:|Test Suite|BUILD"
```

Expected: **build failure** — `cannot find 'PotaParkClient' in scope`.

- [ ] **Step 3: Implement the client**

Create `Sources/App/PotaParkClient.swift`:

```swift
import Foundation
import Observation

/// How the client reaches api.pota.app — a seam, so tests script the
/// server's answers and never touch the network.
protocol PotaParkFetching: Sendable {
    func get(_ url: URL) async throws -> Data
}

struct LivePotaParkFetcher: PotaParkFetching {
    func get(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

/// Keeps the POTA park directory current from POTA's own API.
///
/// `SCPClient`'s posture — quiet by construction, cached copy published
/// before any network, failures inline and never modal — with one forced
/// difference: api.pota.app rejects HEAD (403, API Gateway routes GET only
/// — docs/research/pota/SOURCES.md), so there is no cheap freshness probe.
/// The client re-downloads after `checkInterval` or on the operator's
/// Refresh, and the ~2.7 MB body is why the interval is a week and the
/// first download is an explicit button, never a launch side effect.
@MainActor
@Observable
final class PotaParkClient {

    enum Status: Equatable {
        case idle
        case downloading
        case ready(parks: Int)
        case failed(String)
    }

    private(set) var status: Status = .idle
    private(set) var directory: PotaParkDirectory?

    private let store: PotaParkStore
    private let fetcher: PotaParkFetching

    /// Parks churn slowly — a week-old list still locates you.
    static let checkInterval: TimeInterval = 7 * 24 * 60 * 60

    static let parksURL = URL(string: "https://api.pota.app/program/parks/US")!

    init(store: PotaParkStore = PotaParkStore(folder: PotaParkStore.defaultFolder),
         fetcher: PotaParkFetching = LivePotaParkFetcher()) {
        self.store = store
        self.fetcher = fetcher
    }

    func cachedMeta() -> PotaParkStore.Meta? {
        store.loadMeta()
    }

    /// The cached directory, published immediately — what the picker calls
    /// on appear, before any network is considered.
    func publishCached() {
        guard directory == nil, let cached = store.loadCached() else { return }
        directory = cached.directory
        status = .ready(parks: cached.directory.parks.count)
    }

    /// Re-download when the cache has aged out. With no cache at all this
    /// does nothing: the first download is the explicit button, and a
    /// non-POTA operator must never pay 2.7 MB for opening Setup. `force`
    /// is the Refresh button.
    func refreshIfStale(now: Date = Date(), force: Bool = false) async {
        guard let meta = store.loadMeta() else { return }
        if !force, now.timeIntervalSince(meta.lastCheckedAt) < Self.checkInterval {
            return
        }
        await download(now: now)
    }

    func download(now: Date = Date()) async {
        status = .downloading
        do {
            let data = try await fetcher.get(Self.parksURL)
            guard let parsed = PotaParkDirectory.parse(data: data) else {
                throw URLError(.cannotParseResponse)
            }
            try store.save(data: data, meta: .init(fetchedAt: now, lastCheckedAt: now))
            directory = parsed
            status = .ready(parks: parsed.parks.count)
        } catch {
            // Whatever is cached stays in service; the failure is a status
            // line, never an interruption.
            if let cached = store.loadCached() {
                directory = cached.directory
                let held = cached.meta?.fetchedAt
                    .formatted(date: .abbreviated, time: .omitted)
                status = .failed("Park list refresh failed — using the copy from "
                                 + (held ?? "an earlier download") + ".")
            } else {
                status = .failed("Park list download failed — check the "
                                 + "connection and try again.")
            }
        }
    }
}
```

- [ ] **Step 4: Implement the location seam**

Create `Sources/App/LocationProvider.swift`:

```swift
import CoreLocation

/// One-shot position for Contest Setup: fill the grid square, anchor the
/// nearest-parks sort. A seam in the keying-path sense — tests and
/// previews script positions; only the live implementation touches Core
/// Location, and nothing here is unit-tested (it is glue, verified in the
/// running app).
protocol LocationProviding {
    /// Already granted — a silent fill will not raise the permission
    /// dialog.
    @MainActor var isAuthorized: Bool { get }
    /// One position, or nil when denied, unavailable, or timed out.
    @MainActor func currentLocation() async -> (latitude: Double, longitude: Double)?
}

/// The live Core Location wrapper: one `requestLocation()` per ask, the
/// permission prompt only ever from an explicit button press (the silent
/// path checks `isAuthorized` first), and a timeout so a hung fix returns
/// nil instead of pinning the sheet.
@MainActor
final class MacLocationProvider: NSObject, LocationProviding, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<(latitude: Double, longitude: Double)?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isAuthorized: Bool {
        manager.authorizationStatus == .authorized
            || manager.authorizationStatus == .authorizedAlways
    }

    func currentLocation() async -> (latitude: Double, longitude: Double)? {
        // A second ask while one is in flight would trap on the stored
        // continuation; answer the older one with nothing first.
        continuation?.resume(returning: nil)
        continuation = nil
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        return await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(12))
                self?.continuation?.resume(returning: nil)
                self?.continuation = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            let fix = locations.last?.coordinate
            continuation?.resume(returning: fix.map { ($0.latitude, $0.longitude) })
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(returning: nil)
            continuation = nil
        }
    }
}
```

- [ ] **Step 5: Sandbox plumbing in `project.yml`**

In the `QSOPartyLogger` target's `entitlements: properties:` block, after `com.apple.security.network.client: true`:

```yaml
        # Fills the grid square and sorts the park picker by distance.
        com.apple.security.personal-information.location: true
```

In the same target's `info: properties:` block, beside `NSLocalNetworkUsageDescription`:

```yaml
        NSLocationUsageDescription: "Your location fills in your Maidenhead grid square and finds the POTA parks nearest you."
```

Then regenerate (the plists and pbxproj are generated, never hand-edited):

```bash
xcodegen generate
```

- [ ] **Step 6: Run to verify the tests pass**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/PotaParkClientTests 2>&1 | tee /tmp/pota-task9-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: `Test Suite 'PotaParkClientTests' passed` — 7 tests.

- [ ] **Step 7: Commit (regenerated plists ride along — the release-process lesson: generated but tracked)**

```bash
git add Sources/App/PotaParkClient.swift Sources/App/LocationProvider.swift Tests/App/PotaParkClientTests.swift project.yml QSOPartyLogger.xcodeproj/project.pbxproj Resources/Info.plist Resources/QSOPartyLogger.entitlements
git commit -m "feat(pota): park directory client, location seam, sandbox plumbing"
```

---

### Task 10: UI — park picker, locate button, entry-bar P2P field, editor rows, log tag, README

No unit tests exist for these SwiftUI views; the verification is a clean build plus the full suite, and Tom's own eyes on the sheet (Form label placement passes every test while being wrong on screen — standing lesson). README ships in this commit with the behavior.

**Files:**
- Create: `Sources/UI/PotaParkPicker.swift`
- Modify: `Sources/UI/SetupSheet.swift`
- Modify: `Sources/UI/EntryBar.swift`
- Modify: `Sources/UI/MainView.swift` (existing callsites only, simple arguments)
- Modify: `Sources/UI/EditQSOSheet.swift`
- Modify: `Sources/UI/LogTable.swift`
- Modify: `README.md`
- Modify: `QSOPartyLogger.xcodeproj/project.pbxproj` (via `xcodegen generate`)

- [ ] **Step 1: Create the picker**

Create `Sources/UI/PotaParkPicker.swift`:

```swift
import SwiftUI

/// Contest Setup's park chooser: removable chips for what is selected, one
/// search field over the cached directory (name, number, or state), the
/// nearest parks when the field is empty, and Return-to-add for a typed
/// reference. Its own view so `SetupSheet` stays inside its type-checker
/// budget and the directory never leaks past this seam.
struct PotaParkPicker: View {
    @Binding var selected: [String]
    /// Where "nearest" measures from: the locate button's fix, else the
    /// typed grid square's center. `nil` hides the nearest list; search
    /// and typed references still work.
    let origin: (latitude: Double, longitude: Double)?
    /// Names the origin in the caption: "your location" or "grid EM13".
    let originLabel: String
    var client: PotaParkClient?

    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            selectedChips
            TextField("Search by park name or number — or type a reference and press Return",
                      text: $query)
                .font(.body.monospaced())
                .onSubmit(addTypedReference)
            results
            statusRow
        }
        .onAppear {
            client?.publishCached()
            // Weekly staleness only ever re-downloads an existing cache —
            // the first download stays behind the explicit button below.
            if let client {
                Task { await client.refreshIfStale() }
            }
        }
    }

    @ViewBuilder
    private var selectedChips: some View {
        if !selected.isEmpty {
            HStack(spacing: 6) {
                ForEach(selected, id: \.self) { ref in
                    HStack(spacing: 4) {
                        Text(ref).font(.caption.monospaced().weight(.bold))
                        Button {
                            selected.removeAll { $0 == ref }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .help("Remove \(ref)")
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.3),
                                in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
            }
        }
    }

    /// Search results for a query; the nearest parks for none.
    @ViewBuilder
    private var results: some View {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if let directory = client?.directory {
            if trimmed.isEmpty {
                if let origin {
                    Text("Nearest \(originLabel):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    parkList(directory.nearest(latitude: origin.latitude,
                                               longitude: origin.longitude)
                        .map { (park: $0.park,
                                detail: String(format: "%.0f mi", $0.km * 0.621371)) })
                }
            } else {
                parkList(directory.search(trimmed).map { (park: $0, detail: "") })
            }
        } else if !trimmed.isEmpty {
            Text("No park list downloaded — press Return to add a full reference like US-3315.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func parkList(_ rows: [(park: PotaPark, detail: String)]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(rows, id: \.park.id) { row in
                    let isSelected = selected.contains(row.park.reference)
                    Button {
                        toggle(row.park.reference)
                    } label: {
                        HStack(spacing: 6) {
                            Text(row.park.reference)
                                .font(.caption.monospaced().weight(.bold))
                            Text(row.park.name)
                                .font(.caption)
                                .lineLimit(1)
                            if let location = row.park.locationDesc {
                                Text(location)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(row.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(isSelected ? Color.accentColor.opacity(0.3)
                                               : Color.gray.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(height: 150)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let client {
            HStack(spacing: 8) {
                switch client.status {
                case .idle where client.cachedMeta() == nil:
                    Button("Download the park list (≈3 MB)") {
                        Task { await client.download() }
                    }
                    .font(.caption)
                    Text("Cached once, it searches offline — no signal needed at the park.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .idle:
                    EmptyView()
                case .downloading:
                    Text("Downloading the park list…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .ready(let parks):
                    Text("\(parks) parks — fetched "
                         + (client.cachedMeta()?.fetchedAt
                                .formatted(date: .abbreviated, time: .omitted) ?? ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Refresh") {
                        Task { await client.refreshIfStale(force: true) }
                    }
                    .font(.caption)
                case .failed(let message):
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func toggle(_ ref: String) {
        if let index = selected.firstIndex(of: ref) {
            selected.remove(at: index)
        } else {
            selected.append(ref)
        }
    }

    /// Return in the search field: a string the grammar accepts is added
    /// directly — the keyboard-only path, and the whole path for a park
    /// the directory does not carry (another program, a brand-new park,
    /// or no download yet).
    private func addTypedReference() {
        guard let ref = PotaRef.normalize(query) else { return }
        if !selected.contains(ref) { selected.append(ref) }
        query = ""
    }
}
```

- [ ] **Step 2: SetupSheet — picker section, grid locate, plumbing**

1. New parameters after `var scp: SCPClient? = nil`:

```swift
    /// The park directory client, for the POTA section's picker. `nil` in
    /// previews; the picker still takes typed references.
    var parks: PotaParkClient? = nil
    /// One-shot location for the grid square and the nearest-parks sort.
    /// `nil` in previews; the Locate button simply hides. Named to stay
    /// clear of `save()`'s local `location: MyLocation`.
    var locationProvider: (any LocationProviding)? = nil
```

2. State, beside `@State private var entryClassID`:

```swift
    @State private var selectedParks: [String] = []
    @State private var locating = false
    @State private var locationNote: String?
    @State private var locatedFix: (latitude: Double, longitude: Double)?
```

3. In the Station section, replace the single line
   `TextField("Grid square", text: $station.gridLocator.uppercasing)` (and its
   `.font(.body.monospaced())` modifier) with a labelled row plus button —
   the field stays free text, always:

```swift
                    LabeledContent("Grid square") {
                        HStack(spacing: 6) {
                            TextField("", text: $station.gridLocator.uppercasing)
                                .textFieldStyle(.roundedBorder)
                                .font(.body.monospaced())
                                .frame(width: 100)
                            if locationProvider != nil {
                                Button {
                                    Task { await locate() }
                                } label: {
                                    if locating {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Label("Locate", systemImage: "location.fill")
                                    }
                                }
                                .disabled(locating)
                                .help("Fill the grid square from this Mac's location")
                            }
                        }
                    }
                    if let locationNote {
                        Text(locationNote)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
```

4. New section between `Section("Category") { … }` and `Section("My Location") { … }`:

```swift
                // Universal, party-agnostic: POTA rides any contest. The
                // selection is the *current* activation; each contact is
                // stamped as it is logged, so a mid-contest park change
                // (or a rove) affects later rows only.
                Section("POTA Activation") {
                    Text("Operating from a park? Pick it and every contact is "
                         + "stamped for the POTA upload. Leave empty otherwise.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    PotaParkPicker(selected: $selectedParks,
                                   origin: parkOrigin,
                                   originLabel: parkOriginLabel,
                                   client: parks)
                }
```

5. Computed origin, near the other private helpers:

```swift
    /// The locate button's fix wins; the typed grid square is the offline
    /// answer; neither means no nearest list.
    private var parkOrigin: (latitude: Double, longitude: Double)? {
        locatedFix ?? Maidenhead.center(of: station.gridLocator)
    }

    private var parkOriginLabel: String {
        if locatedFix != nil { return "your location" }
        let grid = station.gridLocator.trimmingCharacters(in: .whitespaces).uppercased()
        return grid.isEmpty ? "" : "grid \(grid)"
    }
```

6. Locate + silent fill, near `save()`:

```swift
    private func locate() async {
        guard let locationProvider else { return }
        locating = true
        defer { locating = false }
        guard let fix = await locationProvider.currentLocation(),
              let grid = Maidenhead.locator(latitude: fix.latitude,
                                            longitude: fix.longitude) else {
            // The field stays free text — per direction, no GPS means the
            // operator just types it.
            locationNote = "Couldn't get a location — type the grid square instead."
            return
        }
        station.gridLocator = grid
        locatedFix = fix
        locationNote = nil
    }

    /// Silent only when nothing will be asked: the permission dialog is
    /// reserved for the button press.
    private func autoFillGrid() async {
        guard let locationProvider, locationProvider.isAuthorized,
              station.gridLocator.trimmingCharacters(in: .whitespaces).isEmpty,
              let fix = await locationProvider.currentLocation(),
              let grid = Maidenhead.locator(latitude: fix.latitude,
                                            longitude: fix.longitude)
        else { return }
        station.gridLocator = grid
        locatedFix = fix
    }
```

and add to the view, beside the existing `.onAppear { load() … }` modifiers:

```swift
        .task { await autoFillGrid() }
```

7. `load()` — beside `exchangeMember = document.log.exchangeMember`:

```swift
        selectedParks = document.log.myPotaRefs
```

8. `save()` — add the argument to `document.updateStation`:

```swift
        document.updateStation(
            station, location: location, partyID: partyID,
            exchangeName: exchangeName, exchangeMember: exchangeMember,
            entryClassID: entryClassID, myPotaRefs: selectedParks,
            undoManager: undoManager
        )
```

(`canSave` needs no park gate — nothing invalid can enter `selectedParks`. The provider is deliberately named `locationProvider`, not `location`, because `save()` already has a `let location: MyLocation` local.)

- [ ] **Step 3: EntryBar — the P2P field**

1. New stored property after `let party: PartyDefinition?`:

```swift
    /// Whether this log is a POTA activation (Setup has parks). The P2P
    /// field only exists then — park-to-park credit does not exist for a
    /// home station, and the bar stays exactly as it is for every
    /// non-POTA contest.
    let showsP2P: Bool
```

2. `Field` enum — add `case theirPark`, and in `next(...)`'s switch:

```swift
            case .theirPark: .call
```

(No case routes *to* `.theirPark` — Space never lands there; Tab reaches it in layout order. From it, Space closes the cycle back to Call.)

3. In `body`, after the member-element `if let member = party?.memberExchange { … }` block and before `statusBadge`:

```swift
                if showsP2P {
                    // Park-to-park capture. Outside the Space cycle on
                    // purpose: most contest contacts are not P2P, and the
                    // fast path must not grow a stop. Tab lands here.
                    field("P2P park(s)", text: $entry.theirParkTyped.uppercasing,
                          width: 110, focusTag: .theirPark)
                        .help("The other station's POTA reference(s) when they "
                              + "are in a park too — US-3315, comma-separated "
                              + "for an n-fer. Leave empty otherwise.")
                }
```

4. `canLog` — extend the returned condition:

```swift
            return !entry.missingName(party: party)
                && !entry.invalidMember(party: party)
                && !entry.invalidTheirPark()
```

5. Inline message — in the message stack at the bottom of `body`, after the existing `else if` branches:

```swift
            } else if entry.invalidTheirPark() {
                Label("P2P park doesn't parse — they look like US-3315; "
                      + "comma-separate an n-fer", systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
```

6. `Sources/UI/MainView.swift` line ~281 — one argument, a simple stored-property expression (type-checker budget):

```swift
            EntryBar(entry: entry, party: party, showsP2P: !document.log.myPotaRefs.isEmpty,
                     onLog: returnPressed, focus: $focusedField)
```

(If the enclosing builder reaches the log through a different local than `document`, use that local — the expression must stay this simple.)

- [ ] **Step 4: Wire the two new clients to the SetupSheet callsite**

Find where the sheet is constructed and where `SCPClient` is created:

```bash
rg -n "SetupSheet\(|SCPClient\(" /Users/tom/AppDev/Apple/QSOPartyLogger/Sources --glob '!*Tests*'
```

Beside the `SCPClient()` creation, create the two new singletons with the same ownership and lifetime:

```swift
    let potaParks = PotaParkClient()
    let locationProvider = MacLocationProvider()
```

and extend the `SetupSheet(...)` construction with:

```swift
    parks: potaParks, locationProvider: locationProvider,
```

(Exact property routing follows however `scp` reaches the sheet — mirror it; both new values are simple stored properties, safe for the MainView budget.)

- [ ] **Step 5: EditQSOSheet — park rows**

1. State:

```swift
    @State private var myParks = ""
    @State private var theirParks = ""
```

2. Two `GridRow`s after the "Their exchange" row — always shown: tagging a
park after the fact is legitimate even for a home log (personal record):

```swift
                GridRow {
                    Text("My park(s)")
                    TextField("", text: $myParks.uppercasing)
                        .font(.body.monospaced())
                        .frame(width: 160)
                }
                GridRow {
                    Text("Their park(s)")
                    TextField("", text: $theirParks.uppercasing)
                        .font(.body.monospaced())
                        .frame(width: 160)
                }
```

3. `onAppear` — beside the other seeds:

```swift
            myParks = (original.myPotaRefs ?? []).joined(separator: ",")
            theirParks = (original.theirPotaRefs ?? []).joined(separator: ",")
```

4. `save()` — before `var updated = original`:

```swift
        let parsedMine: [String]
        switch PotaRef.parseList(myParks) {
        case .failure(let failure):
            validationMessage = failure.message
            return
        case .success(let refs):
            parsedMine = refs
        }
        let parsedTheirs: [String]
        switch PotaRef.parseList(theirParks) {
        case .failure(let failure):
            validationMessage = failure.message
            return
        case .success(let refs):
            parsedTheirs = refs
        }
```

and beside the other assignments:

```swift
        updated.myPotaRefs = parsedMine.isEmpty ? nil : parsedMine
        updated.theirPotaRefs = parsedTheirs.isEmpty ? nil : parsedTheirs
```

- [ ] **Step 6: LogTable — the P2P tag in Flags**

In the `TableColumn("Flags")` `HStack`, after the `newMultRowIDs` label:

```swift
                    if let parks = q.theirPotaRefs {
                        Label("P2P \(parks.joined(separator: ","))", systemImage: "tree")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                            .help("Park-to-park — their POTA reference(s)")
                    }
```

- [ ] **Step 7: README**

1. Features: add one bullet where the operating features are listed:

```markdown
- **POTA activations on any contest** — pick your park(s) in Contest Setup:
  search 12,938 US parks by name or number (cached from POTA's own API, so
  it works offline at the park), or pick from the parks nearest your
  location or grid square — and the grid square itself fills from the
  Mac's location with one click. Every contact is stamped as logged;
  capture the other station's park in the entry bar's P2P field or
  afterwards in the row editor. The ADIF export emits POTA-ready records —
  `MY_SIG`/`MY_SIG_INFO`, `SIG`/`SIG_INFO`, and ADIF 3.1.4's
  `MY_POTA_REF`/`POTA_REF` — duplicated per park pair exactly as POTA's
  park-to-park reference asks, so activation, P2P, and n-fer credit all
  survive the upload. Logs without parks export byte-identically.
```

2. Keyboard reference table: add a row after the `Tab` row:

```markdown
| `Tab` to **P2P park(s)** | During an activation, the other station's park reference(s) — outside the `Space` cycle on purpose; `Space` from it returns to Call |
```

- [ ] **Step 8: Regenerate, build, full suite**

```bash
xcodegen generate
```

```bash
set -o pipefail && xcodebuild build -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger 2>&1 | tee /tmp/pota-task10-build.log | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`, no new warnings.

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/pota-task10-test.log | grep -E "error:|Test Suite 'All tests'|failed|BUILD"
```

Expected: `Test Suite 'All tests' passed`. On any failure, read the full `/tmp/pota-task10-test.log` — never re-run hoping (one unexplained flake is on record; capture the log first).

- [ ] **Step 9: Commit**

```bash
git add Sources/UI/PotaParkPicker.swift Sources/UI/SetupSheet.swift Sources/UI/EntryBar.swift Sources/UI/MainView.swift Sources/UI/EditQSOSheet.swift Sources/UI/LogTable.swift README.md QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "feat(pota): park picker with search and nearest, grid locate, P2P capture, editor rows, log tag"
```

(Also `git add` whatever file Step 4 touched to create the clients.)

Then tell Tom the Setup sheet — picker, locate button, permission prompt — and the entry bar are ready to eyeball in a build; the first park-list download and the location dialog are the two flows only a human at the screen can judge.

---

### Task 11 (cuttable): P2P prefill from this log's earlier rows

Working the same park station on a second band should offer the park back. **Cut this task rather than fight it** — it is a convenience, not credit.

**Files:**
- Modify: `Sources/App/EntryFlow.swift` (`refreshPrefill`, line ~473)
- Test: `Tests/App/EntryFlowTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
    func testSecondBandP2PContactPrefillsTheirPark() throws {
        let doc = cqpDocument(mode: .searchPounce)
        doc.log.myPotaRefs = ["US-3315"]
        let flow = EntryFlow(document: doc)
        flow.entry.call = "W6ABC"
        flow.entry.exchange = "TX"
        flow.entry.theirParkTyped = "US-0088"
        flow.revalidate(context())
        guard case .logged = flow.returnPressed(context(), undoManager: nil) else {
            return XCTFail("should log")
        }
        flow.entry.call = "W6ABC"
        flow.callChanged(context(band: .m40))
        XCTAssertEqual(flow.entry.theirParkTyped, "US-0088",
                       "the park he gave an hour ago comes back offered")
    }
```

(`context()` — the file's helper takes parameters; pass a different band the way the worked-before tests there do. If its signature differs, match it.)

- [ ] **Step 2: Run to verify it fails**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | tee /tmp/pota-task11-red.log | grep -E "error:|Test Suite|failed|BUILD"
```

Expected: the new test **fails** — `theirParkTyped` is `""` after `callChanged`.

- [ ] **Step 3: Implement**

In `EntryFlow.refreshPrefill(_:)` — where the name/exchange prefills are seeded from what the log already knows about the typed call — add park seeding from this log's most recent row for the call:

```swift
        // The park a P2P station gave earlier in this log comes back
        // offered on the next band. This log only — a park is a same-day
        // fact, unlike a home county.
        if entry.theirParkTyped.isEmpty,
           let previous = document.log.qsos.sortedChronologically().last(where: {
               $0.call == entry.callNormalized && $0.theirPotaRefs != nil
           }) {
            entry.theirParkTyped = (previous.theirPotaRefs ?? []).joined(separator: ",")
        }
```

Place it after the existing prefill seeding so it never overrides typed text (the `isEmpty` guard is the rule). If `refreshPrefill` clears provisional values when the call empties, do **not** clear `theirParkTyped` there — it may hold a half-typed park for the contact being entered; `clearForNextContact` from Task 5 already resets it between contacts.

- [ ] **Step 4: Run to verify it passes (whole EntryFlow suite)**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | tee /tmp/pota-task11-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: `Test Suite 'EntryFlowTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/EntryFlow.swift Tests/App/EntryFlowTests.swift
git commit -m "feat(pota): offer a P2P station's park back on the next band"
```

---

### Task 12: Final verification and the README test count

- [ ] **Step 1: Full build and test, pipefail discipline**

```bash
set -o pipefail && xcodebuild build -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger 2>&1 | tee /tmp/pota-final-build.log | grep -E "error:|BUILD"
```

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/pota-final-test.log | grep -E "Test Suite 'All tests'|Executed|failed"
```

Expected: `BUILD SUCCEEDED`; `Test Suite 'All tests' passed`, with the `Executed N tests` line reporting the new total. Keep both full logs.

- [ ] **Step 2: README test count**

README states the test count (search for the current number near "tests"). Update it to the `Executed N tests` figure from the final log.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs(readme): current test count with POTA coverage"
```

- [ ] **Step 4: Report**

Report to Tom with: the commands run and their summary lines verbatim, the final test count, which tasks (if any) were cut or adapted and why, and the reminder that the Setup sheet (picker, download button, Locate and its permission dialog), entry bar, and log-table tag await his eyes in a running build.

---

## Self-review against the spec

- **§2 schema** → Task 3. **§3 PotaRef** → Task 2. **§4 export** → Task 4
  (byte-identity, triplet, three-fer, cross product, county-line, score
  identity). **§5 picker** → Tasks 8 + 10; **§5a directory** → Tasks 8 + 9;
  **§5b grid/location** → Tasks 7 + 9 + 10. **§6 entry** → Tasks 5 + 10,
  prefill → Task 11. **§7 repair** → Tasks 6 (bulk) + 10 (editor rows, log
  tag). **§8 tests/docs** → each task + Tasks 10/12. Sources banking → Task 1.
- **Type names used consistently:** `PotaRef.normalize` / `PotaRef.parseList`
  / `PotaRef.Failure.message`; `myPotaRefs` / `theirPotaRefs`;
  `theirParkTyped` / `invalidTheirPark()`; `showsP2P`;
  `BulkEdit.Field.myPotaRefs`; `Maidenhead.locator` / `Maidenhead.center`;
  `PotaPark` / `PotaParkDirectory.parse/search/nearest/Ranked/distanceKm`;
  `PotaParkStore.Meta/Cached/save/loadCached/loadMeta`;
  `PotaParkClient.status/directory/download/refreshIfStale/publishCached/cachedMeta`;
  `LocationProviding.isAuthorized/currentLocation`; `MacLocationProvider`;
  `PotaParkPicker(selected:origin:originLabel:client:)`.
- **Open calls** (spec §9) are implemented at their defaults: P2P field
  gated on activation, Flags-column tag, malformed park blocks logging,
  bulk-edit field always offered, US-program directory with typed-reference
  escape, weekly re-download with explicit first download. Tom can veto any
  before execution.

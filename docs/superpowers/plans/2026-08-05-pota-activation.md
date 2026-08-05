# POTA Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Any contest log can double as a POTA activation — my park(s) set in Contest Setup and stamped per row, their park(s) captured per contact, and the one ADIF export emitting POTA-creditable records — while every non-POTA log's scoring, Cabrillo, and ADIF stay byte-identical.

**Architecture:** Additive schema (`ContestLog.myPotaRefs: [String]`, `QSO.myPotaRefs/theirPotaRefs: [String]?`, all defaulted) following the `exchangeName` → `nameSent` stamp-at-logging idiom; a new `PotaRef` grammar type; `AdifExporter` duplicating each row's record per (my park × their park) pair the way POTA's park-to-park reference documents; universal UI seams (Setup section, entry-bar field, edit-sheet rows, bulk edit, log-table tag) with zero party branching.

**Tech Stack:** Swift 6 / SwiftUI / XCTest, XcodeGen. Design + verbatim source quotes: `docs/superpowers/specs/2026-08-05-pota-activation-design.md`.

**Repo execution notes (from standing project practice):**
- Build/test **always** with `set -o pipefail` in front of piped `xcodebuild` (a `| tee | grep` once masked a failed build as exit 0). Keep the **full** log file for any failure; never judge from a `tail`.
- `project.yml` globs `Sources/` and `Tests/`, but the tracked `QSOPartyLogger.xcodeproj/project.pbxproj` is generated — any task that **adds files** must run `xcodegen generate` and stage the pbxproj in that task's commit. Only Task 2 adds files.
- SwiftUI Form rows: one labelled field per row; label placement bugs pass every test, so UI tasks end with a **build** and Tom eyeballs the sheet himself — never claim the layout is right from code.
- `MainView.swift` is at its type-checker budget: touch it only at the `EntryBar(...)` callsite, adding one argument whose value is a simple stored-property expression.
- Run the narrow `-only-testing` suite while iterating a task; the **full suite** runs in Task 9 (and any earlier time you suspect fallout).

---

### Task 1: Bank the official sources

**Files:**
- Create: `docs/research/pota/SOURCES.md`

- [ ] **Step 1: Write the sources file**

```markdown
# POTA support — banked official sources

Both authorities fetched 2026-08-05. N1MM and other loggers were not
consulted; the ADIF specification and POTA's own documentation are the only
sources of the field names, grammar, and upload semantics below.

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

## What this bakes into the app

- Park references are validated against the POTARef grammar, verbatim above.
- The ADIF export duplicates each row's record per (my park × their park)
  pair with singular `MY_SIG_INFO`/`SIG_INFO` — POTA's documented shape —
  and stamps the matching singular `MY_POTA_REF`/`POTA_REF` on each record
  so no record contradicts itself. A single record carrying the spec's
  comma-list form would be valid ADIF but lose n-fer credit at POTA.
```

- [ ] **Step 2: Commit**

```bash
git add docs/research/pota/SOURCES.md
git commit -m "docs(research): bank ADIF 3.1.4 and POTA official sources for POTA support"
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
    /// *current* Contest Setup value, normalized through
    /// `PotaRef.parseList`. Stamped into each row's `myPotaRefs` at logging
    /// (the `exchangeName` idiom), so a mid-contest park change affects
    /// later rows only. Empty for every log that is not an activation — and
    /// for documents written before the setting existed.
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
- Modify: `Sources/App/EntryFlow.swift` (`logContact`, plus `clearForNextContact` call-through already exists)
- Modify: `Sources/App/LogDocument.swift` (`updateStation`)
- Test: `Tests/App/EntryFlowTests.swift`, `Tests/App/LogDocumentTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to the test class in `Tests/App/EntryFlowTests.swift` (fixtures `cqpDocument(mode:)` and `context()` already exist there; CQP's exchange is a serial + location, so `entry.exchange = "TX"` completes a row):

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

(If the class is not already `@MainActor`, keep the attribute on the method as shown; drop it if the class carries it.)

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
   normalized through `PotaRef.parseList` by the callers):

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

Expected: both suites `passed` — including every pre-existing EntryFlow test (the new guard must not disturb ESM/serial behavior; `theirParkTyped` defaults empty, which parses to `[]`).

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

Append to the test class in `Tests/Core/BulkEditTests.swift` (it has a `qso(...)` row helper near the top — reuse it; the calls below show explicit constructors so they compile regardless):

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
        let result = BulkEdit.apply(
            .text("us-3315, us-4571"), field: .myPotaRefs, to: rows,
            party: nil, isInState: false)
        let changed = try result.get()
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

1. Value construction (~line 49): add `.myPotaRefs` to the match list so it produces `.text(text)`:

```swift
        case .myLoc, .nameSent, .memberSent, .myPotaRefs: .text(text)
```

2. Control choice (~line 131): add `.myPotaRefs` to the same-shaped list so it draws the text field:

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

### Task 7: UI — Setup section, entry-bar P2P field, editor rows, log tag, README

No unit tests exist for these SwiftUI views; the verification is a clean build plus Tom's own eyes on the sheet (Form label placement passes every test while being wrong on screen — standing lesson). README ships in this commit with the behavior.

**Files:**
- Modify: `Sources/UI/SetupSheet.swift`
- Modify: `Sources/UI/EntryBar.swift`
- Modify: `Sources/UI/MainView.swift` (one argument at the `EntryBar(` callsite, line ~281)
- Modify: `Sources/UI/EditQSOSheet.swift`
- Modify: `Sources/UI/LogTable.swift`
- Modify: `README.md`

- [ ] **Step 1: SetupSheet — the "POTA Activation" section**

1. State (beside `@State private var entryClassID`):

```swift
    @State private var potaParks = ""
```

2. `Field` enum — add `case potaParks` to the existing case list.

3. New section between `Section("Category") { … }` and `Section("My Location") { … }` — one labelled field per row, the form-repair way:

```swift
                // Universal, party-agnostic: POTA rides any contest. The
                // field holds the *current* activation; each contact is
                // stamped as it is logged, so a mid-contest park change
                // (or a rove) affects later rows only.
                Section("POTA Activation") {
                    LabeledContent("My park(s)") {
                        TextField("", text: $potaParks.uppercasing)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .focused($focused, equals: .potaParks)
                            .frame(width: 200)
                    }
                    if case .failure(let failure) = PotaRef.parseList(potaParks) {
                        Text(failure.message)
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Comma-separated POTA references — US-3315, or "
                             + "US-0088,US-4571 for a two-fer. Leave empty unless "
                             + "operating from a park. Contacts logged after a "
                             + "change carry the new value; fix earlier rows by "
                             + "selecting them and editing.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
```

4. `canSave` — **after the member-element check and before the
   `isInState` branch** (that branch returns early, and the park gate must
   hold for an in-state entrant too):

```swift
        // A malformed park list would stamp garbage into every contact.
        // Empty always saves — most contests are not activations.
        if case .failure = PotaRef.parseList(potaParks) { return false }
```

5. `load()` — beside `exchangeMember = document.log.exchangeMember`:

```swift
        potaParks = document.log.myPotaRefs.joined(separator: ",")
```

6. `save()` — parse and pass through (before the `document.updateStation` call, then add the argument):

```swift
        guard case .success(let parks) = PotaRef.parseList(potaParks) else { return }
```

```swift
        document.updateStation(
            station, location: location, partyID: partyID,
            exchangeName: exchangeName, exchangeMember: exchangeMember,
            entryClassID: entryClassID, myPotaRefs: parks, undoManager: undoManager
        )
```

- [ ] **Step 2: EntryBar — the P2P field**

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

6. `Sources/UI/MainView.swift` line ~281 — the one MainView touch, a simple stored-property argument (type-checker budget):

```swift
            EntryBar(entry: entry, party: party, showsP2P: !document.log.myPotaRefs.isEmpty,
                     onLog: returnPressed, focus: $focusedField)
```

(If the enclosing builder reaches the log through a different local than `document`, use that local — the expression must stay this simple.)

- [ ] **Step 3: EditQSOSheet — park rows**

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

- [ ] **Step 4: LogTable — the P2P tag in Flags**

In the `TableColumn("Flags")` `HStack`, after the `newMultRowIDs` label:

```swift
                    if let parks = q.theirPotaRefs {
                        Label("P2P \(parks.joined(separator: ","))", systemImage: "tree")
                            .font(.caption2)
                            .foregroundStyle(.teal)
                            .help("Park-to-park — their POTA reference(s)")
                    }
```

- [ ] **Step 5: README**

1. Features: add one bullet where the operating features are listed:

```markdown
- **POTA activations on any contest** — set your park(s) in Contest Setup
  (comma-separated for an n-fer) and every contact is stamped as logged;
  capture the other station's park in the entry bar's P2P field or after
  the fact in the row editor. The ADIF export emits POTA-ready records —
  `MY_SIG`/`MY_SIG_INFO`, `SIG`/`SIG_INFO`, and ADIF 3.1.4's
  `MY_POTA_REF`/`POTA_REF` — duplicated per park pair exactly as POTA's
  park-to-park reference asks, so activation, P2P, and n-fer credit all
  survive the upload. Logs without parks export byte-identically.
```

2. Keyboard reference table: add a row after the `Tab` row:

```markdown
| `Tab` to **P2P park(s)** | During an activation, the other station's park reference(s) — outside the `Space` cycle on purpose; `Space` from it returns to Call |
```

- [ ] **Step 6: Build and run the full suite**

```bash
set -o pipefail && xcodebuild build -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger 2>&1 | tee /tmp/pota-task7-build.log | grep -E "error:|warning:|BUILD"
```

Expected: `BUILD SUCCEEDED`, no new warnings.

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/pota-task7-test.log | grep -E "error:|Test Suite 'All tests'|failed|BUILD"
```

Expected: `Test Suite 'All tests' passed`. On any failure, read the full `/tmp/pota-task7-test.log` — never re-run hoping (one unexplained flake is on record; capture the log first).

- [ ] **Step 7: Commit**

```bash
git add Sources/UI/SetupSheet.swift Sources/UI/EntryBar.swift Sources/UI/MainView.swift Sources/UI/EditQSOSheet.swift Sources/UI/LogTable.swift README.md
git commit -m "feat(pota): Setup parks field, entry-bar P2P capture, editor rows, log tag"
```

Then tell Tom the Setup sheet and entry bar are ready to eyeball in a build — the Form row layout is exactly the class of thing tests cannot see.

---

### Task 8 (cuttable): P2P prefill from this log's earlier rows

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

(`context(band:)` — the file's `context()` helper takes parameters; pass a different band the way the worked-before tests there do. If its signature differs, match it.)

- [ ] **Step 2: Run to verify it fails**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | tee /tmp/pota-task8-red.log | grep -E "error:|Test Suite|failed|BUILD"
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

Place it after the existing prefill seeding so it never overrides typed text (the `isEmpty` guard is the rule). If `refreshPrefill` clears provisional values when the call empties, clearing `theirParkTyped` there is **not** wanted — it may hold a half-typed park for the contact being entered; the `clearForNextContact` path from Task 5 already resets it between contacts.

- [ ] **Step 4: Run to verify it passes (whole EntryFlow suite)**

```bash
set -o pipefail && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | tee /tmp/pota-task8-green.log | grep -E "error:|Test Suite|BUILD"
```

Expected: `Test Suite 'EntryFlowTests' passed`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/EntryFlow.swift Tests/App/EntryFlowTests.swift
git commit -m "feat(pota): offer a P2P station's park back on the next band"
```

---

### Task 9: Final verification and the README test count

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

Report to Tom with: the commands run and their summary lines verbatim, the final test count, which tasks (if any) were cut or adapted and why, and the reminder that the Setup sheet, entry bar, and log-table tag await his eyes in a running build.

---

## Self-review against the spec

- **§2 schema** → Task 3. **§3 PotaRef** → Task 2. **§4 export** → Task 4
  (byte-identity, triplet, three-fer, cross product, county-line, score
  identity). **§5 Setup** → Tasks 5 (updateStation) + 7. **§6 entry** →
  Tasks 5 + 7, prefill → Task 8. **§7 repair** → Tasks 6 (bulk) + 7
  (editor rows, log tag). **§8 tests/docs** → each task + Tasks 7/9.
  Sources banking (spec "Sources" note) → Task 1.
- **Type names used consistently:** `PotaRef.normalize` / `PotaRef.parseList`
  / `PotaRef.Failure.message`; `myPotaRefs` / `theirPotaRefs`;
  `theirParkTyped` / `invalidTheirPark()`; `showsP2P`; `BulkEdit.Field.myPotaRefs`.
- **Open calls** (spec §9) are implemented at their defaults: P2P field
  gated on activation, Flags-column tag, malformed park blocks logging,
  bulk-edit field always offered. Tom can veto any before execution.

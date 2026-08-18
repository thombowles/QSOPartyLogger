# General Contest Logger — The Engine Switch (Phase 1b) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Score, dupe, export and snapshot every log against `ContestDefinition` — the general model built in Plan 1 — through `ContestCatalog`; move `QSO` and `ContestLog` to the v2 row shape; delete the `PartyDefinition`-driven engine body; prove it with an equivalence corpus over all 50 bundled parties and byte-identity export fixtures. **Zero visible change:** every party scores, exports and saves the same figures it does today.

**Architecture:** The engine becomes `ScoreEngine.score(log:contest:)` in `Sources/Core/Engine/ScoreEngine+Contest.swift`, driven entirely by `ContestDefinition` (sides + pairing, dupe rule, point rules, multiplier classes with ordered resolvers, side rules, bonuses, score factors, operating time). Two model gaps found while building the foundations are closed **first**, in the model, before any scoring moves: (1) *one received token has one owning set* — the engine classifies a token exactly as `ExchangeValidator` does (first accepting set in the element's declared order), so a location can credit at most one location class; and (2) *the state-code-vs-DXCC-prefix collision is decided by the worked callsign* only where a class says so — a new `Resolver.callsignOverrides: [String]?` on the `dxccEntity` resolver names the sets whose token it takes over when the worked call resolves to that prefix's entity, and `PartyLowering` emits it exactly where today's `dxCountsEntities` gate is. The `PartyDefinition` overloads (`score(log:party:)`, `wouldAddMultiplier(theirLocs:…party:)`, `CabrilloExporter.export(log:party:score:)`, `AdifExporter.export(log:party:)`, `ScoreSnapshot.make(log:party:)`) remain as thin bridges that lower (cached) and delegate, so the 2,971 existing tests are the permanent oracle without edits. `QSO` carries `sent`/`rcvd` maps with the typed accessors kept as computed views; `ContestLog` carries `sideID` + `sentExchange` with `myLocation`/`exchangeName`/`exchangeMember` kept as computed views; new saves are v2, old files decode unchanged. `ExchangeParser`, `MyLocation`, `MultClass` and every UI file are untouched — they are phase 2 (UI generalisation).

**Tech Stack:** Swift 6 / SwiftUI, XCTest, XcodeGen (`project.yml` is the source of truth), `os` (`OSAllocatedUnfairLock`, `Logger`).

**Spec:** [`docs/superpowers/specs/2026-08-17-general-contest-logger-design.md`](../specs/2026-08-17-general-contest-logger-design.md) — §1.4, §1.5, §1.6, §2.4–2.6, "Testing", "Carried into the engine-switch plan". Plan 1 (done): [`2026-08-17-general-contest-logger-foundations.md`](2026-08-17-general-contest-logger-foundations.md).

---

## Decisions this plan settles (the "carried" list, resolved)

| Carried item | Resolution in this plan |
| --- | --- |
| `locationContributions` credits one location class per row and resolves a state-code-that-is-also-a-DXCC-prefix by the worked callsign; the model evaluates classes independently | **Token ownership.** For a `token` element value the engine asks `ExchangeValidator.owningSet(of:element:contest:side:)` — the first of the element's sets (in `sentBy` order over the workable sides) that accepts it; the dynamic `dxccPrefix` accepts a known ARRL prefix no enumerated set claims. A `receivedToken` resolver fires only when the token's owner is its `set`, so a token feeds at most one enumerated class (plus `mapTo: "group"` derivations of the same token). **The callsign override:** a `dxccEntity` resolver with `from: receivedTokenOrCallsign` may carry `callsignOverrides: [setID]`; when the token's owner is one of those sets, the worked callsign is not US/Canadian, and `DXCCTable` resolves the callsign to the very entity the token names as a prefix, the owner becomes `dxccPrefix`. `PartyLowering` emits `callsignOverrides: ["states", "provinces"]` on the entity-counting `dx` resolver of every side with `dxCountsEntities` — exactly today's `collidesWithDXCC` gate (`SalmonRunTests` pins it; Task 9 proves it over all 50 parties). Validated: only that resolver kind/`from`, only sets the element accepts. |
| `ExchangeValidator` returns tokens as typed; aliases fold at count time | The `receivedToken` resolver's value is `set.canonical(raw)` (`DC` → `MD` where a party says so); the row keeps what was sent. |
| A no-home-region party's single side is scored with `outState` | Lowering already gives the single `all` side `outState`; a legacy log's `.outOfState` decodes to `sideID = "outside"`, and `ContestDefinition.resolvedSideID(_:)` maps an id the contest does not declare to its only side (else its last-listed, catch-all side). |
| `family` on the four non-state parties; bonus `sides` | **Deferred, deliberately.** `family` is picker grouping (phase 2, where the picker is generalised — the generators for naqp/skeeter/fobb are touched then). VTQP's W1AW/1 bonus today pays both sides (`VermontQSOPartyTests` documents it); a `sides` filter changes VTQP's score and is its own VTQP commit after this plan (Article 6), not part of an engine switch that must keep every party identical. |
| `OperatingTime.compute` takes pre-filtered rows and does not check `appliesTo` | The engine passes the in-mode, in-scope rows (dupes included — a dupe is still time on the air) and checks `rule.applies(to: log.categoryValues)` first. `OperatingTime.Result` gains `offPeriods` for Cabrillo `OFFTIME:` lines. |
| `ContestCatalog.contest(id:)` reloads per call and swallows bundled failures | Bundled load memoised per bundle; each bundled failure logged once (`os.Logger`, category `catalog`); user folders still read per call. `PartyCatalog.loadBundled` memoised the same way, and `PartyCatalog.decode` lowers-and-validates so a party file that cannot lower is refused at load with the model's error, never at scoring time. |
| `validate()` does not check `bonuses`/`scoreFactors` references | Added: county-keyed bonuses need a `county` class with a roster; `designatedCountySweep` tokens must be in it; entry-class / objective / declared-bonus ids unique; an activated rule's class must list a roster; `callsignOverrides` shape. |
| Zone resolvers name their element | Engine reads `resolver.element`. |
| `receivedElements(for:)` omits the call echo | `receivedElements(for:includingCallEcho:)`; the Cabrillo QSO line writes a `callEcho` element as the side's callsign padded to 13. |
| Rosters must add `mapTo: "group"` groups | Phase 2 (`MultiplierRoster` is UI-facing and stays party-shaped here). |
| Cabrillo lines for parties without a report, number or name in the exchange (MDC, IDQP, NCQP, WIQP) | Today's exporter always writes an ex1 column (name → number → report), so those four write the row's report. **`CabrilloSpec.reportColumn: Bool`** (default false; lowering sets it exactly for those four) writes the row's report — or the mode's default report when the row has none — where the exchange declares no `rst`/`serial`/`name`. Field Day (class + section, no report column) leaves it false. Provenance: today's behaviour, pinned byte-for-byte; a party commit may change it with sponsor evidence. |
| Cabrillo `LOCATION:` | `CabrilloExporter.location(log:contest:)`: `.state` → `homeLocation` for the first-listed side, else the entrant's sent `location` token (a token with a group — a county — resolves to it), else `exchangeDefaults["state"]`, else `DX`; `.entrantToken` → the sent token verbatim, else `DX`; `.section` → the sent `section`, else `exchangeDefaults["section"]`, else `DX`. Byte-identical to `MyLocation.entrantToken` for every party. |

**Kept until phase 2 (UI generalisation), on purpose:** `ExchangeParser` (the entry row still parses through it; `ExchangeValidator` is proven equal), `MyLocation` (a computed view over `sideID`/`sentExchange`), `MultClass` (still names the six well-known class ids; `MultKey.multClass` is a computed view over `classID`), `MultiplierRoster`, `NeededMult`, `ScoreSummaryText`, `CombinedLogSplit`, every `Sources/UI` file, `PartyCatalog.party(id:)` in the app layer.

---

## Conventions for every task

- Work in the worktree `/Users/tom/AppDev/Apple/QSOPartyLogger/.claude/worktrees/general-contest-engine` (branch `worktree-general-contest-engine`). Never run git or xcodebuild against the main checkout.
- After **adding or moving any Swift or fixture file**, run `xcodegen generate` (XcodeGen enumerates files at generation time — fixtures under `Tests/Fixtures/**` are copied flat into the test bundle, so fixture file names must be unique across subfolders and are looked up without a `subdirectory:`).
- Build: `xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | tail -5`
- One test class: `set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/<ClassName> 2>&1 | grep -E "Test Case|Executed|error:|BUILD" | tail -40`
- Full suite (end of every task that touches shared code): `set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|error:|failed" | tail -5` — expected `Executed N tests, with 0 failures` where N ≥ 2971 (the measured baseline) and grows with each task. Record the exact N in the commit message.
- Tests never touch the network or hardware (Article 5). Bundled resources are read through `Bundle.main` (the test bundle is hosted inside the app); test fixtures through `Bundle(for: Self.self)`.
- Recording steps (fixtures, golden) run one test with an environment variable: `xcodebuild test … -only-testing:QSOPartyLoggerTests/<Class>/<test> TEST_RUNNER_<VAR>=1` (xcodebuild forwards `TEST_RUNNER_`-prefixed variables to the test process). **The test host is sandboxed** (`com.apple.security.app-sandbox` in `project.yml`), so a test cannot write into the source tree: a recording test writes into `FileManager.default.temporaryDirectory` — under the sandbox that is `~/Library/Containers/org.b5n.QSOPartyLogger/Data/tmp/` — in a `QPLRecord/<what>` folder, and the shell copies the files into `Tests/Fixtures/…` afterwards. A recording test is skipped when the variable is absent.
- Commit after every green step with the message shown; every commit message ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Constitution Article 4: this plan adds no party and changes no score, no export byte and no saved figure for any bundled party. Article 6: one commit per task (a task that changes both a model type and its lowering is one structural refactor). Article 8: the README test count is updated in the last task.
- **Do not touch** `ScoreEngine.score(log:party:)`'s body, `CabrilloExporter.export(log:party:score:)` or `AdifExporter.export(log:party:)` until Task 10/12 says so — Tasks 2 and 9 need today's implementations alive to record and compare against.

## File structure

Create:
- `Sources/Core/Engine/ScoreEngine+Contest.swift` — the engine on the model: `classify`, `score(log:contest:)`, token ownership, resolvers, points context, bonuses, activated multipliers, `wouldAddMultiplier(received:…)`, `bandModeCounts`, `designatedCountiesWorked`, `callAreaSumAchieved` (Tasks 7–8).
- `Tests/Core/ExportFixtures.swift`, `Tests/Core/ExportByteIdentityTests.swift`, `Tests/Fixtures/Exports/*.log`, `*.adi` (Task 2).
- `Tests/Core/QSOExchangeShapeTests.swift` (Task 3), `Tests/Core/ContestLogShapeTests.swift` (Task 4).
- `Tests/Core/ContestScoreEngineTests.swift` (Tasks 7–8).
- `Tests/Core/EngineEquivalenceTests.swift` + `Tests/Fixtures/Equivalence/engine-golden.json` (Tasks 9, 12).
- `Tests/Core/ContestExportTests.swift` (Task 10).

Modify:
- `Sources/Core/Models/QSO.swift` (v2 maps), `Sources/Core/Models/ContestLog.swift` (`sideID`, `sentExchange`, `selectedObjectives`, `declaredBonuses`, `categoryValues`), `Sources/Core/Models/StationProfile.swift` (`categoryBand`, `categoryOverlay`, `categoryTime`, `exchangeDefaults`).
- `Sources/Core/Contests/MultiplierClass.swift` (`Resolver.callsignOverrides`), `ContestRules.swift` (`CabrilloSpec.reportColumn`), `ContestDefinition.swift` (`resolvedSideID`, `countyRoster`, `receivedElements(for:includingCallEcho:)`, validation), `OperatingTime.swift` (`offPeriods`), `ExchangeValidator.swift` (`owningSet`), `PartyLowering.swift` (overrides, `reportColumn`, `lowered` cache), `ContestCatalog.swift` (cache + logging).
- `Sources/Core/Parties/PartyCatalog.swift` (bundled cache, lower-on-decode).
- `Sources/Core/Engine/ScoreEngine.swift` (Task 12: types + party bridges + shared arithmetic only).
- `Sources/Core/Export/CabrilloExporter.swift`, `AdifExporter.swift`, `ArchivedLogExport.swift`; `Sources/Core/History/ScoreSnapshot.swift`, `LogFolder.swift`.
- `README.md`, `CLAUDE.md`, the spec's Progress section, this plan's status block.

---

### Task 1: Baseline

- [ ] **Step 1: Generate the project and record the baseline count**

```bash
xcodegen generate && set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
```
Expected: `Executed 2971 tests, with 0 failures` (measured 2026-08-17 on master `1a07949`, the worktree's base, in ~65 s).

- [ ] **Step 2: Nothing to commit** (if `git status` shows the tracked `.xcodeproj` modified, commit it alone as `build: regenerate project`).

---

### Task 2: Export byte-identity fixtures, recorded from today's exporters

Cabrillo and ADIF for nine fixture logs — one per party shape the spec names (county line + POTA, serial, name, member, section, multi-state, prefix DX with colliding tokens, no-RST, out-of-state and DX entrants) — recorded **now** with the exporters as they are, checked in, and asserted equal from here on. Every token in a fixture comes from the party's own data (`party.counties`, `party.sections`), never typed by hand (Article 2).

**Files:**
- Create: `Tests/Core/ExportFixtures.swift`, `Tests/Core/ExportByteIdentityTests.swift`
- Create (recorded): `Tests/Fixtures/Exports/<name>.log`, `Tests/Fixtures/Exports/<name>.adi` for the nine names below

- [ ] **Step 1: The fixture logs**

```swift
// Tests/Core/ExportFixtures.swift
import Foundation
@testable import QSOPartyLogger

/// Deterministic logs, one per party shape, for the export byte-identity
/// fixtures (`Tests/Fixtures/Exports`). Every id, timestamp and token is
/// fixed, and every token comes from the party's own data.
enum ExportFixtures {
    struct Fixture {
        let name: String
        let party: PartyDefinition
        let log: ContestLog
    }

    /// 2026-08-29 14:32:00 UTC, then +90 s per row.
    static let t0 = Date(timeIntervalSince1970: 1_788_013_920)

    static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-4000-8000-%012X", n))!
    }

    static func station(_ configure: (inout StationProfile) -> Void = { _ in }) -> StationProfile {
        var s = StationProfile()
        s.callsign = "KE5CW"; s.name = "Tom Bowles"; s.city = "Amarillo"; s.stateProvince = "TX"
        s.categoryPower = .low
        configure(&s)
        return s
    }

    /// One row; `n` fixes its id (unique per row). Rows expanded from one
    /// on-air contact share a `group` — the same group id and the same time.
    static func row(_ n: Int, call: String, band: Band = .m20, mode: ModeClass = .cw,
                    freq: Int? = 14042, rstSent: String? = nil, rstRcvd: String? = nil,
                    serialSent: Int? = nil, serialRcvd: Int? = nil,
                    nameSent: String? = nil, nameRcvd: String? = nil,
                    memberSent: String? = nil, memberRcvd: String? = nil,
                    myPotaRefs: [String]? = nil, theirPotaRefs: [String]? = nil,
                    my: String, their: String, group: Int? = nil) -> QSO {
        let raw = mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY"
        let rst = mode == .phone ? "59" : "599"
        let contact = group ?? n
        return QSO(id: uuid(n), groupID: uuid(1000 + contact), timestampUTC: t0.addingTimeInterval(Double(contact) * 90),
                   call: call, band: band, modeClass: mode, rawMode: raw, freqKHz: freq,
                   rstSent: rstSent ?? rst, rstRcvd: rstRcvd ?? rst,
                   serialSent: serialSent, serialRcvd: serialRcvd, nameSent: nameSent, nameRcvd: nameRcvd,
                   memberSent: memberSent, memberRcvd: memberRcvd,
                   myPotaRefs: myPotaRefs, theirPotaRefs: theirPotaRefs, myLoc: my, theirLoc: their)
    }

    static func party(_ id: String) throws -> PartyDefinition {
        guard let p = PartyCatalog.party(id: id) else { throw NSError(domain: "ExportFixtures", code: 1, userInfo: [NSLocalizedDescriptionKey: "no bundled party \(id)"]) }
        return p
    }

    static func all() throws -> [Fixture] {
        var out: [Fixture] = []

        // 1. KSQP, inside on a county line, an activation, a park-to-park row, a dupe.
        do {
            let p = try party("ksqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station { $0.categoryStation = .mobile }, myLocation: .inState(counties: [c[0], c[1]]))
            log.myPotaRefs = ["US-3315"]
            log.qsos = [
                row(1, call: "W0BH", my: c[0], their: c[5], group: 1),
                row(2, call: "W0BH", my: c[1], their: c[5], group: 1),
                row(3, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[0], their: c[7], group: 2),
                row(4, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[0], their: c[8], group: 2),
                row(5, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[1], their: c[7], group: 2),
                row(6, call: "N0XYZ", band: .m40, mode: .cw, freq: 7040, my: c[1], their: c[8], group: 2),
                row(7, call: "K5TR", mode: .phone, freq: 14250, my: c[0], their: "TX"),
                row(8, call: "VE3ABC", band: .m40, freq: nil, my: c[0], their: "ON"),
                row(9, call: "DL1AA", my: c[0], their: "DX"),
                row(10, call: "W0BH", my: c[0], their: c[5]),                                 // dupe
                row(11, call: "K0AA", myPotaRefs: ["US-3315"], theirPotaRefs: ["US-0088"], my: c[0], their: c[9]),
            ]
            out.append(Fixture(name: "ksqp-inside-county-line", party: p, log: log))
        }
        // 2. KSQP, outside (TX): counties, an out-of-scope state, a dupe.
        do {
            let p = try party("ksqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .outOfState(location: "TX"))
            log.qsos = [row(1, call: "W0BH", my: "TX", their: c[5]), row(2, call: "N0XYZ", band: .m40, freq: 7040, my: "TX", their: c[7]),
                        row(3, call: "K5TR", my: "TX", their: "OK"), row(4, call: "W0BH", my: "TX", their: c[5])]
            out.append(Fixture(name: "ksqp-outside", party: p, log: log))
        }
        // 3. KSQP, an entrant outside the US and Canada who typed a prefix as their location.
        do {
            let p = try party("ksqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station { $0.callsign = "DL1QPL"; $0.stateProvince = ""; $0.country = "GERMANY" },
                                 myLocation: .outOfState(location: "DL"))
            log.qsos = [row(1, call: "W0BH", my: "DL", their: c[5]), row(2, call: "K0AA", my: "DL", their: c[6])]
            out.append(Fixture(name: "ksqp-outside-dx", party: p, log: log))
        }
        // 4. CQP, inside: serial numbers, a county line received.
        do {
            let p = try party("cqp"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "W0BH", serialSent: 1, serialRcvd: 12, my: c[0], their: "KS"),
                        row(2, call: "N6XYZ", serialSent: 2, serialRcvd: 7, my: c[0], their: c[3], group: 2),
                        row(3, call: "N6XYZ", serialSent: 2, serialRcvd: 7, my: c[0], their: c[4], group: 2),
                        row(4, call: "VE7ABC", mode: .phone, freq: 14250, serialSent: 3, serialRcvd: 130, my: c[0], their: "BC")]
            out.append(Fixture(name: "cqp-inside-serials", party: p, log: log))
        }
        // 5. NAQP CW: a name, one side, the entrant's own token.
        do {
            let p = try party("naqpcw"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .outOfState(location: "TX"), exchangeName: "TOM")
            log.qsos = [row(1, call: "W0BH", nameSent: "TOM", nameRcvd: "BOB", my: "TX", their: "CA"),
                        row(2, call: "VE3ABC", band: .m40, freq: 7040, nameSent: "TOM", nameRcvd: "MARY-ANN", my: "TX", their: "ON"),
                        row(3, call: "XE1AAA", nameSent: "TOM", nameRcvd: "JOSE", my: "TX", their: c[0])]
            out.append(Fixture(name: "naqpcw-name", party: p, log: log))
        }
        // 6. Skeeter Hunt: the member-or-power element, blank for a QRO station.
        do {
            let p = try party("skeeter")
            var log = ContestLog(partyID: p.id, station: station { $0.categoryStation = .portable }, myLocation: .outOfState(location: "TX"),
                                 exchangeMember: "13", entryClassID: p.entryClasses.first?.id ?? "")
            log.qsos = [row(1, call: "W2LJ", memberSent: "13", memberRcvd: "1", my: "TX", their: "NJ"),
                        row(2, call: "K3WWP", memberSent: "13", memberRcvd: "5W", my: "TX", their: "PA"),
                        row(3, call: "VE3ABC", memberSent: "13", memberRcvd: nil, my: "TX", their: "ON"),
                        row(4, call: "DL1AA", memberSent: "13", memberRcvd: "100W", my: "TX", their: "DL")]
            out.append(Fixture(name: "skeeter-member", party: p, log: log))
        }
        // 7. PAQP, inside: sections, serials, granted EPA/WPA, the DX token.
        do {
            let p = try party("paqp"); let c = p.counties.map(\.abbr); let s = p.sections.sorted()
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "W0BH", serialSent: 1, serialRcvd: 3, my: c[0], their: s[0]),
                        row(2, call: "K3LR", serialSent: 2, serialRcvd: 44, my: c[0], their: c[2]),
                        row(3, call: "DL1AA", serialSent: 3, serialRcvd: 9, my: c[0], their: "DX"),
                        row(4, call: "VE3ABC", serialSent: 4, serialRcvd: 21, my: c[0], their: s[1])]
            out.append(Fixture(name: "paqp-inside-sections", party: p, log: log))
        }
        // 8. 7QP, inside: eight member states, LOCATION headers the primary state.
        do {
            let p = try party("sevenqp"); let c = p.counties.map(\.abbr)
            let last = c[c.count - 1]
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [last]))
            log.qsos = [row(1, call: "W0BH", my: last, their: c[0]), row(2, call: "K7ABC", my: last, their: c[10]),
                        row(3, call: "K5TR", my: last, their: "TX"), row(4, call: "VE7ABC", my: last, their: "BC")]
            out.append(Fixture(name: "sevenqp-inside-multistate", party: p, log: log))
        }
        // 9. Salmon Run, inside: DX prefixes, the colliding tokens both ways, a province.
        do {
            let p = try party("warun"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "PA0AAA", my: c[0], their: "PA"), row(2, call: "W3XYZ", my: c[0], their: "PA"),
                        row(3, call: "DL1EEE", my: c[0], their: "DL"), row(4, call: "VE5ABC", my: c[0], their: "SK"),
                        row(5, call: "W7ABC", band: .m40, freq: 7040, my: c[0], their: c[3])]
            out.append(Fixture(name: "warun-inside-prefix-dx", party: p, log: log))
        }
        // 10. MDC, inside: no report in the exchange — the line still carries one today.
        do {
            let p = try party("mdc"); let c = p.counties.map(\.abbr)
            var log = ContestLog(partyID: p.id, station: station(), myLocation: .inState(counties: [c[0]]))
            log.qsos = [row(1, call: "W3XYZ", my: c[0], their: "PA"), row(2, call: "K3LR", my: c[0], their: c[1]),
                        row(3, call: "VE3ABC", mode: .phone, freq: 14250, my: c[0], their: "ON")]
            out.append(Fixture(name: "mdc-inside-no-rst", party: p, log: log))
        }
        return out
    }
}
```

- [ ] **Step 2: The test — record on request, assert always**

```swift
// Tests/Core/ExportByteIdentityTests.swift
import XCTest
@testable import QSOPartyLogger

/// Cabrillo and ADIF for the fixture logs are pinned byte-for-byte in
/// `Tests/Fixtures/Exports`, recorded from the exporters as they were before
/// the engine switch. Re-record only with `TEST_RUNNER_QPL_RECORD_EXPORTS=1`,
/// and only when a sponsor's own template says the bytes should change.
final class ExportByteIdentityTests: XCTestCase {
    /// Where the recording test writes: the sandboxed test host cannot touch
    /// the source tree, so the files land in its container's temp folder
    /// (`~/Library/Containers/org.b5n.QSOPartyLogger/Data/tmp/QPLRecord/Exports`)
    /// and the shell copies them into `Tests/Fixtures/Exports`.
    static let recordDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("QPLRecord/Exports", isDirectory: true)

    private func fixtureText(_ name: String, _ ext: String) throws -> String {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: name, withExtension: ext),
                                "missing fixture \(name).\(ext) — record with TEST_RUNNER_QPL_RECORD_EXPORTS=1")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Writes every fixture's Cabrillo and ADIF into `recordDirectory`.
    func testRecordFixturesWhenAsked() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QPL_RECORD_EXPORTS"] == "1", "recording is opt-in")
        try? FileManager.default.removeItem(at: Self.recordDirectory)
        try FileManager.default.createDirectory(at: Self.recordDirectory, withIntermediateDirectories: true)
        for f in try ExportFixtures.all() {
            let score = ScoreEngine.score(log: f.log, party: f.party)
            try CabrilloExporter.export(log: f.log, party: f.party, score: score)
                .write(to: Self.recordDirectory.appendingPathComponent("\(f.name).log"), atomically: true, encoding: .utf8)
            try AdifExporter.export(log: f.log, party: f.party)
                .write(to: Self.recordDirectory.appendingPathComponent("\(f.name).adi"), atomically: true, encoding: .utf8)
        }
        print("QPL_RECORD_DIR=\(Self.recordDirectory.path)")
    }

    func testCabrilloIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            let score = ScoreEngine.score(log: f.log, party: f.party)
            XCTAssertEqual(CabrilloExporter.export(log: f.log, party: f.party, score: score), try fixtureText(f.name, "log"), f.name)
        }
    }

    func testAdifIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            XCTAssertEqual(AdifExporter.export(log: f.log, party: f.party), try fixtureText(f.name, "adi"), f.name)
        }
    }

    func testFixturesCoverEveryShape() throws {
        XCTAssertEqual(try ExportFixtures.all().map(\.name), [
            "ksqp-inside-county-line", "ksqp-outside", "ksqp-outside-dx", "cqp-inside-serials", "naqpcw-name",
            "skeeter-member", "paqp-inside-sections", "sevenqp-inside-multistate", "warun-inside-prefix-dx", "mdc-inside-no-rst",
        ])
    }
}
```

- [ ] **Step 3: Record, then copy out of the sandbox container**

```bash
xcodegen generate && set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ExportByteIdentityTests/testRecordFixturesWhenAsked TEST_RUNNER_QPL_RECORD_EXPORTS=1 2>&1 | grep -E "Test Case|Executed|error:|QPL_RECORD_DIR" | tail -6
```
Expected: the test passes (not skipped) and prints `QPL_RECORD_DIR=…/Containers/org.b5n.QSOPartyLogger/Data/tmp/QPLRecord/Exports`. Then:
```bash
mkdir -p Tests/Fixtures/Exports && cp ~/Library/Containers/org.b5n.QSOPartyLogger/Data/tmp/QPLRecord/Exports/* Tests/Fixtures/Exports/ && ls Tests/Fixtures/Exports | wc -l && ls Tests/Fixtures/Exports
```
Expected: 20 files (`<name>.log` and `<name>.adi` for the ten names). Open one `.log` and one `.adi` and check they read as a real Cabrillo header + QSO lines and a real ADIF (Article 8: look at the artefact you recorded). If the recording test is *skipped*, the environment variable did not reach the test process — try `env TEST_RUNNER_QPL_RECORD_EXPORTS=1 xcodebuild …` and, failing that, report it rather than editing the skip. If the printed directory differs from the container path above, copy from the printed one.

- [ ] **Step 4: Regenerate (new fixture files) and run the class**

```bash
xcodegen generate && set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ExportByteIdentityTests 2>&1 | grep -E "Test Case|Executed|error:" | tail -8
```
Expected: 3 passed, 1 skipped (`testRecordFixturesWhenAsked`).

- [ ] **Step 5: Commit**

```bash
git add Tests/Core/ExportFixtures.swift Tests/Core/ExportByteIdentityTests.swift Tests/Fixtures/Exports QSOPartyLogger.xcodeproj
git commit -m "tests: export byte-identity fixtures — Cabrillo and ADIF for ten party shapes, recorded from today's exporters

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `QSO` — the v2 row shape (`sent`/`rcvd` maps, typed views kept)

**Files:**
- Modify: `Sources/Core/Models/QSO.swift` (whole file replaced below)
- Test: `Tests/Core/QSOExchangeShapeTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/Core/QSOExchangeShapeTests.swift
import XCTest
@testable import QSOPartyLogger

/// The v2 row: two maps, element id → value, with the typed v1 accessors as
/// views over them. New saves write the maps only; v1 rows decode unchanged.
final class QSOExchangeShapeTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1_788_013_920)

    func testTypedInitFillsTheMapsAndTheViewsReadThemBack() {
        let q = QSO(timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "579", serialSent: 12, serialRcvd: 7,
                    nameSent: "TOM", nameRcvd: "BOB", memberSent: "13", memberRcvd: "5W",
                    myLoc: "TX", theirLoc: "MRN")
        XCTAssertEqual(q.sent, ["rst": "599", "serial": "12", "name": "TOM", "member": "13", "location": "TX"])
        XCTAssertEqual(q.rcvd, ["rst": "579", "serial": "7", "name": "BOB", "member": "5W", "location": "MRN"])
        XCTAssertEqual(q.rstSent, "599"); XCTAssertEqual(q.rstRcvd, "579")
        XCTAssertEqual(q.serialSent, 12); XCTAssertEqual(q.serialRcvd, 7)
        XCTAssertEqual(q.nameSent, "TOM"); XCTAssertEqual(q.nameRcvd, "BOB")
        XCTAssertEqual(q.memberSent, "13"); XCTAssertEqual(q.memberRcvd, "5W")
        XCTAssertEqual(q.myLoc, "TX"); XCTAssertEqual(q.theirLoc, "MRN")
    }

    func testAbsentElementsHaveOneRepresentation() {
        let q = QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                    rstSent: "", rstRcvd: "599", nameSent: "", memberRcvd: nil, myLoc: "TX", theirLoc: "MRN")
        XCTAssertNil(q.sent["rst"], "an empty value is not stored")
        XCTAssertNil(q.sent["name"])
        XCTAssertEqual(q.rstSent, "", "the typed view reads an absent report as empty")
        XCTAssertNil(q.nameSent)
        XCTAssertNil(q.serialSent)
        var edited = q
        edited.theirLoc = "LIN"; edited.nameRcvd = "SUE"; edited.serialRcvd = 44
        XCTAssertEqual(edited.rcvd, ["rst": "599", "location": "LIN", "name": "SUE", "serial": "44"])
        edited.nameRcvd = nil; edited.rstRcvd = ""; edited.rcvd["zone"] = ""
        XCTAssertEqual(edited.rcvd, ["location": "LIN", "serial": "44"], "setters and direct writes both drop empties")
    }

    func testMapInitAndAnyElementId() {
        let q = QSO(call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW",
                    sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14", "": "x"])
        XCTAssertEqual(q.sent["zone"], "4")
        XCTAssertEqual(q.rcvd, ["rst": "599", "zone": "14"], "an empty id is not an element")
        XCTAssertEqual(q.myLoc, "", "no location element — the view is empty, not a crash")
    }

    func testEncodesTheMapsOnlyAndRoundTrips() throws {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.qsos = [QSO(timestampUTC: t, call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW",
                        rstSent: "599", rstRcvd: "599", serialSent: 3, myLoc: "TX", theirLoc: "MRN")]
        let data = try log.encoded()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let row = try XCTUnwrap((json["qsos"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["sent"] as? [String: String], ["rst": "599", "serial": "3", "location": "TX"])
        XCTAssertEqual(row["rcvd"] as? [String: String], ["rst": "599", "location": "MRN"])
        for legacy in ["rstSent", "rstRcvd", "serialSent", "serialRcvd", "nameSent", "nameRcvd", "memberSent", "memberRcvd", "myLoc", "theirLoc"] {
            XCTAssertNil(row[legacy], "\(legacy) is a v1 key and is no longer written")
        }
        XCTAssertEqual(try ContestLog.decode(from: data), log)
    }

    /// A row exactly as every build before this one wrote it.
    func testDecodesAV1Row() throws {
        let v1 = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},
         "operatingMode":"searchPounce","setupCompleted":true,"exchangeName":"","exchangeMember":"","entryClassID":"","usedSpots":false,"myPotaRefs":[],
         "messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW","freqKHz":14042,
                  "rstSent":"599","rstRcvd":"579","serialSent":2,"nameRcvd":"BOB","memberSent":"","myLoc":"TX","theirLoc":"MRN"}]}
        """
        let log = try ContestLog.decode(from: Data(v1.utf8))
        let q = try XCTUnwrap(log.qsos.first)
        XCTAssertEqual(q.sent, ["rst": "599", "serial": "2", "location": "TX"], "an empty v1 member is absent")
        XCTAssertEqual(q.rcvd, ["rst": "579", "name": "BOB", "location": "MRN"])
        XCTAssertEqual(q.rstRcvd, "579"); XCTAssertEqual(q.serialSent, 2); XCTAssertNil(q.serialRcvd)
        XCTAssertEqual(q.theirLoc, "MRN"); XCTAssertEqual(q.freqKHz, 14042)
    }

    func testAV1RowMissingARequiredKeyStillFails() {
        let broken = """
        {"schemaVersion":1,"partyID":"ksqp","station":{"callsign":"KE5CW"},"myLocation":{"outOfState":{"location":"TX"}},
         "operatingMode":"searchPounce","setupCompleted":true,"messages":{"run":[],"searchPounce":[]},
         "qsos":[{"id":"00000000-0000-4000-8000-000000000001","groupID":"00000000-0000-4000-8000-000000000001",
                  "timestampUTC":"2026-08-29T14:32:00Z","call":"W0BH","band":"20m","modeClass":"cw","rawMode":"CW",
                  "rstSent":"599","myLoc":"TX","theirLoc":"MRN"}]}
        """
        XCTAssertThrowsError(try ContestLog.decode(from: Data(broken.utf8)), "rstRcvd was required in v1 and stays required for a v1 row")
    }
}
```
If `MessageSets` does not decode from `{"run":[],"searchPounce":[]}`, look at `Sources/Core/Models/MessageSets.swift` and use the smallest literal it accepts (or omit the key — `ContestLog` defaults it) — but keep the row literal exactly as written.

- [ ] **Step 2: Run to verify it fails**

Run: the `QSOExchangeShapeTests` class command. Expected: build errors (`sent`, `rcvd`, the map init do not exist).

- [ ] **Step 3: Replace `Sources/Core/Models/QSO.swift`**

```swift
import Foundation

/// The well-known exchange element ids the parties use — the keys of
/// `QSO.sent` / `QSO.rcvd` and of `ContestLog.sentExchange`, and the ids
/// `PartyLowering` gives its elements. A general contest names its own.
enum ExchangeElementID {
    static let rst = "rst"
    static let serial = "serial"
    static let name = "name"
    static let member = "member"
    static let location = "location"
}

/// One logged line. County-line contacts produce multiple `QSO` rows sharing a `groupID`
/// (N1MM-style: a separate line per county, per KSQP rule 11).
///
/// The exchange is two maps, element id → value (`sent`, `rcvd`) — the v2 row
/// shape (spec §1.5). The typed accessors below (`rstSent`, `theirLoc`,
/// `serialRcvd`…) are views over the maps, so call sites written for the v1
/// fields read unchanged. The maps never hold an empty value: an absent
/// element has exactly one representation, so equality, encoding and export
/// cannot tell "" from nil. Rows written by earlier builds decode through
/// `LegacyKeys`; this build writes `sent`/`rcvd` only.
struct QSO: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    /// Shared by all rows created from a single on-air contact.
    var groupID: UUID
    var timestampUTC: Date
    var call: String
    var band: Band
    var modeClass: ModeClass
    /// Concrete ADIF mode: CW, SSB, RTTY, FT8…
    var rawMode: String
    /// From CAT when connected; nil when logged manually.
    var freqKHz: Int?
    /// My exchange for this row, element id → value: `rst`, `serial`, `name`,
    /// `member`, `location` for the parties; `zone`, `section`, `check`… for
    /// other contests. A county-line entrant's rows each carry one county.
    var sent: [String: String] { didSet { sent = Self.compact(sent) } }
    /// Their exchange for this row, the same keys.
    var rcvd: [String: String] { didSet { rcvd = Self.compact(rcvd) } }
    /// POTA park references each way, for contests run from a park. Mine are
    /// stamped at logging from Contest Setup's current value
    /// (`ContestLog.myPotaRefs`); theirs is what a park-to-park station
    /// gave. `nil` — never an empty array — when a side has no parks, so
    /// logs written before POTA support decode unchanged and export
    /// byte-identically.
    var myPotaRefs: [String]?
    var theirPotaRefs: [String]?
    /// Whether this contact was made running or searching, stamped at logging
    /// from the same Run/S&P flag that already picks the message set and
    /// decides what ⇧⌘S means.
    ///
    /// **Nothing scores on it, and no export carries it.** It exists so the
    /// advisor can answer "what has running on 40 m actually paid you tonight"
    /// from the operator's own log rather than from a rule of thumb — see
    /// `Advisor`. `nil` on every row logged before this field existed, and on
    /// rows imported from anywhere else; those simply contribute nothing to
    /// that strand, which is the same evidence-or-silence law the rate column
    /// obeys.
    var posture: OperatingMode?

    // MARK: Typed views over the maps (the v1 fields)

    var rstSent: String {
        get { sent[ExchangeElementID.rst] ?? "" }
        set { sent[ExchangeElementID.rst] = newValue }
    }
    var rstRcvd: String {
        get { rcvd[ExchangeElementID.rst] ?? "" }
        set { rcvd[ExchangeElementID.rst] = newValue }
    }
    /// QSO numbers sent and received, for parties whose exchange carries one
    /// (CQP). A county-line contact is **one** contact and carries **one**
    /// number, shared by every row it expands into (see `CountyLineExpander`).
    var serialSent: Int? {
        get { sent[ExchangeElementID.serial].flatMap { Int($0) } }
        set { sent[ExchangeElementID.serial] = newValue.map(String.init) }
    }
    var serialRcvd: Int? {
        get { rcvd[ExchangeElementID.serial].flatMap { Int($0) } }
        set { rcvd[ExchangeElementID.serial] = newValue.map(String.init) }
    }
    /// Operator names sent and received (NAQP, MNQP). The sent name is the
    /// log's single contest-long name, stamped per row so the record shows
    /// what went out.
    var nameSent: String? {
        get { sent[ExchangeElementID.name] }
        set { sent[ExchangeElementID.name] = newValue }
    }
    var nameRcvd: String? {
        get { rcvd[ExchangeElementID.name] }
        set { rcvd[ExchangeElementID.name] = newValue }
    }
    /// Member-number-or-power elements sent and received (Skeeter Hunt, FOBB)
    /// — a number for members and "5W" for the rest, see `MemberExchange.parse`.
    var memberSent: String? {
        get { sent[ExchangeElementID.member] }
        set { sent[ExchangeElementID.member] = newValue }
    }
    var memberRcvd: String? {
        get { rcvd[ExchangeElementID.member] }
        set { rcvd[ExchangeElementID.member] = newValue }
    }
    /// My sent location for this row: county abbreviation (in-state) or state/province.
    var myLoc: String {
        get { sent[ExchangeElementID.location] ?? "" }
        set { sent[ExchangeElementID.location] = newValue }
    }
    /// Their location for this row: county abbreviation, state, province, or "DX".
    var theirLoc: String {
        get { rcvd[ExchangeElementID.location] ?? "" }
        set { rcvd[ExchangeElementID.location] = newValue }
    }

    // MARK: Inits

    /// The v1 shape: typed fields, mapped into `sent`/`rcvd`.
    init(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        timestampUTC: Date = Date(),
        call: String,
        band: Band,
        modeClass: ModeClass,
        rawMode: String,
        freqKHz: Int? = nil,
        rstSent: String,
        rstRcvd: String,
        serialSent: Int? = nil,
        serialRcvd: Int? = nil,
        nameSent: String? = nil,
        nameRcvd: String? = nil,
        memberSent: String? = nil,
        memberRcvd: String? = nil,
        myPotaRefs: [String]? = nil,
        theirPotaRefs: [String]? = nil,
        myLoc: String,
        theirLoc: String,
        posture: OperatingMode? = nil
    ) {
        self.init(
            id: id, groupID: groupID, timestampUTC: timestampUTC, call: call, band: band,
            modeClass: modeClass, rawMode: rawMode, freqKHz: freqKHz,
            sent: [ExchangeElementID.rst: rstSent, ExchangeElementID.serial: serialSent.map(String.init) ?? "",
                   ExchangeElementID.name: nameSent ?? "", ExchangeElementID.member: memberSent ?? "",
                   ExchangeElementID.location: myLoc],
            rcvd: [ExchangeElementID.rst: rstRcvd, ExchangeElementID.serial: serialRcvd.map(String.init) ?? "",
                   ExchangeElementID.name: nameRcvd ?? "", ExchangeElementID.member: memberRcvd ?? "",
                   ExchangeElementID.location: theirLoc],
            myPotaRefs: myPotaRefs, theirPotaRefs: theirPotaRefs, posture: posture
        )
    }

    /// The v2 shape: the maps themselves.
    init(
        id: UUID = UUID(),
        groupID: UUID = UUID(),
        timestampUTC: Date = Date(),
        call: String,
        band: Band,
        modeClass: ModeClass,
        rawMode: String,
        freqKHz: Int? = nil,
        sent: [String: String],
        rcvd: [String: String],
        myPotaRefs: [String]? = nil,
        theirPotaRefs: [String]? = nil,
        posture: OperatingMode? = nil
    ) {
        self.id = id
        self.groupID = groupID
        self.timestampUTC = timestampUTC
        self.call = call
        self.band = band
        self.modeClass = modeClass
        self.rawMode = rawMode
        self.freqKHz = freqKHz
        self.sent = Self.compact(sent)
        self.rcvd = Self.compact(rcvd)
        // Empty is stored as absent, so "no parks" has exactly one
        // representation and an ADIF export cannot iterate an empty list.
        self.myPotaRefs = (myPotaRefs?.isEmpty ?? true) ? nil : myPotaRefs
        self.theirPotaRefs = (theirPotaRefs?.isEmpty ?? true) ? nil : theirPotaRefs
        self.posture = posture
    }

    /// Drops empty ids and empty values — the maps' one invariant.
    static func compact(_ map: [String: String]) -> [String: String] {
        map.filter { !$0.key.isEmpty && !$0.value.isEmpty }
    }

    // MARK: Codable — v2 written, v1 read

    private enum CodingKeys: String, CodingKey {
        case id, groupID, timestampUTC, call, band, modeClass, rawMode, freqKHz, sent, rcvd, myPotaRefs, theirPotaRefs, posture
    }

    /// The v1 row's own keys. `rstSent`, `rstRcvd`, `myLoc`, `theirLoc` were
    /// required; the rest optional.
    private enum LegacyKeys: String, CodingKey {
        case rstSent, rstRcvd, serialSent, serialRcvd, nameSent, nameRcvd, memberSent, memberRcvd, myLoc, theirLoc
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        groupID = try c.decode(UUID.self, forKey: .groupID)
        timestampUTC = try c.decode(Date.self, forKey: .timestampUTC)
        call = try c.decode(String.self, forKey: .call)
        band = try c.decode(Band.self, forKey: .band)
        modeClass = try c.decode(ModeClass.self, forKey: .modeClass)
        rawMode = try c.decode(String.self, forKey: .rawMode)
        freqKHz = try c.decodeIfPresent(Int.self, forKey: .freqKHz)
        myPotaRefs = try c.decodeIfPresent([String].self, forKey: .myPotaRefs)
        theirPotaRefs = try c.decodeIfPresent([String].self, forKey: .theirPotaRefs)
        posture = try c.decodeIfPresent(OperatingMode.self, forKey: .posture)
        if c.contains(.sent) || c.contains(.rcvd) {
            sent = Self.compact(try c.decodeIfPresent([String: String].self, forKey: .sent) ?? [:])
            rcvd = Self.compact(try c.decodeIfPresent([String: String].self, forKey: .rcvd) ?? [:])
        } else {
            let l = try decoder.container(keyedBy: LegacyKeys.self)
            sent = Self.compact([
                ExchangeElementID.rst: try l.decode(String.self, forKey: .rstSent),
                ExchangeElementID.serial: try l.decodeIfPresent(Int.self, forKey: .serialSent).map(String.init) ?? "",
                ExchangeElementID.name: try l.decodeIfPresent(String.self, forKey: .nameSent) ?? "",
                ExchangeElementID.member: try l.decodeIfPresent(String.self, forKey: .memberSent) ?? "",
                ExchangeElementID.location: try l.decode(String.self, forKey: .myLoc),
            ])
            rcvd = Self.compact([
                ExchangeElementID.rst: try l.decode(String.self, forKey: .rstRcvd),
                ExchangeElementID.serial: try l.decodeIfPresent(Int.self, forKey: .serialRcvd).map(String.init) ?? "",
                ExchangeElementID.name: try l.decodeIfPresent(String.self, forKey: .nameRcvd) ?? "",
                ExchangeElementID.member: try l.decodeIfPresent(String.self, forKey: .memberRcvd) ?? "",
                ExchangeElementID.location: try l.decode(String.self, forKey: .theirLoc),
            ])
        }
    }
    // `encode(to:)` stays synthesized over `CodingKeys`: the maps, and every
    // optional only when present — a nil `freqKHz`, parks or `posture` writes
    // no key, exactly as before.
}
```

- [ ] **Step 4: Build and run the class, then the full suite**

Run: build; the `QSOExchangeShapeTests` class; then the full suite. Expected: the class passes; full suite `Executed 2977 tests, with 0 failures` (2971 + 6). Any failure elsewhere means a call site depended on nil-vs-empty for a typed field — read it, and fix the caller only if it is genuinely reading a distinction the export/score never made (both exporters and both engines treat nil and "" alike); otherwise report it.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Models/QSO.swift Tests/Core/QSOExchangeShapeTests.swift QSOPartyLogger.xcodeproj
git commit -m "log: QSO carries the v2 row shape — sent/rcvd element maps, typed v1 accessors as views, v1 rows decode unchanged

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `ContestLog` v2 (`sideID`, `sentExchange`, objectives, declared bonuses, `categoryValues`) and the `StationProfile` additions

**Files:**
- Modify: `Sources/Core/Models/ContestLog.swift` (whole file replaced below), `Sources/Core/Models/StationProfile.swift`
- Test: `Tests/Core/ContestLogShapeTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/Core/ContestLogShapeTests.swift
import XCTest
@testable import QSOPartyLogger

final class ContestLogShapeTests: XCTestCase {

    func testMyLocationIsAViewOverSideAndSentExchange() {
        var log = ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["MRN", "CHS"]), exchangeName: "TOM", exchangeMember: "13")
        XCTAssertEqual(log.sideID, "inside")
        XCTAssertEqual(log.sentExchange, ["location": ["MRN", "CHS"], "name": ["TOM"], "member": ["13"]])
        XCTAssertEqual(log.myLocation, .inState(counties: ["MRN", "CHS"]))
        XCTAssertEqual(log.exchangeName, "TOM"); XCTAssertEqual(log.exchangeMember, "13")
        log.myLocation = .outOfState(location: "TX")
        XCTAssertEqual(log.sideID, "outside")
        XCTAssertEqual(log.sentExchange["location"], ["TX"])
        log.exchangeName = ""; log.exchangeMember = ""
        XCTAssertNil(log.sentExchange["name"]); XCTAssertNil(log.sentExchange["member"])
        log.myLocation = .outOfState(location: "")
        XCTAssertNil(log.sentExchange["location"], "an empty location is absent")
        XCTAssertEqual(log.myLocation, .outOfState(location: ""), "and reads back as the empty out-of-state it was")
        log.sideID = "all"; log.sentExchange = ["zone": ["4"], "rst": [""]]
        XCTAssertEqual(log.sentExchange, ["zone": ["4"]], "empties are dropped on direct writes too")
        XCTAssertEqual(log.myLocation, .outOfState(location: ""), "a side that is not `inside` reads as out-of-state")
    }

    func testDerivedOperatingModeFollowsTheSide() {
        XCTAssertEqual(ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["MRN"])).derivedOperatingMode, .run)
        XCTAssertEqual(ContestLog(partyID: "ksqp", myLocation: .outOfState(location: "TX")).derivedOperatingMode, .searchPounce)
    }

    func testEncodesV2KeysOnlyAndRoundTrips() throws {
        var log = ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["MRN"]), exchangeName: "TOM")
        log.station.callsign = "KE5CW"
        log.selectedObjectives = ["1o", "3o"]
        log.declaredBonuses = ["emergencyPower": 3]
        let data = try log.encoded()
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["schemaVersion"] as? Int, 2)
        XCTAssertEqual(json["sideID"] as? String, "inside")
        XCTAssertEqual(json["sentExchange"] as? [String: [String]], ["location": ["MRN"], "name": ["TOM"]])
        XCTAssertEqual(json["selectedObjectives"] as? [String], ["1o", "3o"])
        XCTAssertEqual(json["declaredBonuses"] as? [String: Int], ["emergencyPower": 3])
        for legacy in ["myLocation", "exchangeName", "exchangeMember"] { XCTAssertNil(json[legacy], "\(legacy) is a v1 key") }
        XCTAssertEqual(try ContestLog.decode(from: data), log)
        // Empty objective/bonus collections write no key at all.
        var plain = log; plain.selectedObjectives = []; plain.declaredBonuses = [:]
        let plainJSON = try XCTUnwrap(try JSONSerialization.jsonObject(with: try plain.encoded()) as? [String: Any])
        XCTAssertNil(plainJSON["selectedObjectives"]); XCTAssertNil(plainJSON["declaredBonuses"])
    }

    func testDecodesAV1Document() throws {
        let v1 = """
        {"schemaVersion":1,"partyID":"naqpcw","station":{"callsign":"KE5CW","categoryPower":"LOW"},
         "myLocation":{"outOfState":{"location":"TX"}},"exchangeName":"TOM","exchangeMember":"",
         "operatingMode":"run","setupCompleted":true,"entryClassID":"","usedSpots":true,"myPotaRefs":["US-3315"],
         "qsos":[]}
        """
        let log = try ContestLog.decode(from: Data(v1.utf8))
        XCTAssertEqual(log.schemaVersion, 2, "the in-memory log is always the current shape")
        XCTAssertEqual(log.sideID, "outside")
        XCTAssertEqual(log.sentExchange, ["location": ["TX"], "name": ["TOM"]])
        XCTAssertEqual(log.myLocation, .outOfState(location: "TX"))
        XCTAssertEqual(log.exchangeName, "TOM"); XCTAssertEqual(log.exchangeMember, "")
        XCTAssertEqual(log.operatingMode, .run); XCTAssertTrue(log.usedSpots); XCTAssertEqual(log.myPotaRefs, ["US-3315"])
        XCTAssertEqual(log.selectedObjectives, []); XCTAssertEqual(log.declaredBonuses, [:])
        let inside = try ContestLog.decode(from: Data("""
        {"schemaVersion":1,"partyID":"ksqp","station":{},"myLocation":{"inState":{"counties":["MRN","CHS"]}},"qsos":[]}
        """.utf8))
        XCTAssertEqual(inside.sideID, "inside"); XCTAssertEqual(inside.sentExchange["location"], ["MRN", "CHS"])
        XCTAssertEqual(inside.operatingMode, .run, "derived from the side, as before from the location")
    }

    func testADocumentWithNeitherSideNorLocationIsRefused() {
        XCTAssertThrowsError(try ContestLog.decode(from: Data("""
        {"schemaVersion":2,"partyID":"ksqp","station":{},"qsos":[]}
        """.utf8)))
    }

    func testCategoryValues() {
        var log = ContestLog(partyID: "cqwwcw")
        log.station.categoryOperator = .singleOp; log.station.categoryPower = .high
        log.station.categoryOverlay = "CLASSIC"; log.station.categoryBand = "20M"
        log.qsos = [QSO(call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW", sent: [:], rcvd: [:])]
        XCTAssertEqual(log.categoryValues, ["operator": "SINGLE-OP", "assisted": "NON-ASSISTED", "power": "HIGH", "station": "FIXED",
                                            "transmitter": "ONE", "band": "20M", "mode": "CW", "overlay": "CLASSIC", "time": ""])
        XCTAssertTrue(OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 60, appliesTo: ["overlay": "CLASSIC"]).applies(to: log.categoryValues))
        XCTAssertFalse(OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 60, appliesTo: ["overlay": "ROOKIE"]).applies(to: log.categoryValues))
    }

    func testStationProfileAdditionsDecodeWithDefaultsAndEncodeOnlyWhenSet() throws {
        let old = try JSONDecoder().decode(StationProfile.self, from: Data(#"{"callsign":"KE5CW"}"#.utf8))
        XCTAssertNil(old.categoryBand); XCTAssertNil(old.categoryOverlay); XCTAssertNil(old.categoryTime)
        XCTAssertEqual(old.exchangeDefaults, [:])
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(old)) as? [String: Any])
        for key in ["categoryBand", "categoryOverlay", "categoryTime", "exchangeDefaults"] { XCTAssertNil(json[key], "\(key) is written only when set") }
        var s = old
        s.categoryOverlay = "classic"; s.exchangeDefaults = ["section": "ntx", "zone": "4"]
        let n = s.normalized()
        XCTAssertEqual(n.categoryOverlay, "CLASSIC"); XCTAssertEqual(n.exchangeDefaults, ["section": "NTX", "zone": "4"])
        let back = try JSONDecoder().decode(StationProfile.self, from: try JSONEncoder().encode(n))
        XCTAssertEqual(back, n)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: the `ContestLogShapeTests` class command. Expected: build errors (`sideID`, `sentExchange`, `categoryValues`, `categoryBand`… do not exist).

- [ ] **Step 3: `StationProfile` additions**

In `Sources/Core/Models/StationProfile.swift` add the four stored properties after `gridLocator`, extend `CodingKeys`, decode with defaults, fold in `normalized()`, and add a custom `encode(to:)` (the struct has none today) so unset values write no key:

```swift
    /// Maidenhead grid square (Cabrillo `GRID-LOCATOR:`), e.g. EM13LE. Optional.
    var gridLocator: String = ""
    /// Cabrillo `CATEGORY-BAND:` where a contest admits single-band entries
    /// (`Categories.band`); nil = `ALL`, which is what every party writes.
    var categoryBand: String? = nil
    /// Cabrillo `CATEGORY-OVERLAY:` (CQ WW CLASSIC/ROOKIE/YOUTH, WPX TB-WIRES…);
    /// nil = no overlay line. Nothing bundled sets it yet.
    var categoryOverlay: String? = nil
    /// Cabrillo `CATEGORY-TIME:`; nil = no line. Nothing bundled sets it yet.
    var categoryTime: String? = nil
    /// The entrant's own fixed exchange values remembered across contests —
    /// `section`, `zone`, `check`, `state`, `name`, `power`, `grid`… keyed by
    /// exchange element id (spec §1.5). Setup seeds a contest's sent elements
    /// from here; the Cabrillo `LOCATION:` header falls back to `state` /
    /// `section` when a contest has no location element.
    var exchangeDefaults: [String: String] = [:]

    private enum CodingKeys: String, CodingKey {
        case callsign, name, email, address, city, stateProvince, postalCode
        case country, club, operators
        case categoryOperator, categoryAssisted, categoryPower, categoryStation, categoryTransmitter
        case gridLocator, categoryBand, categoryOverlay, categoryTime, exchangeDefaults
    }
```
In `normalized()` add, after `copy.gridLocator = …`:
```swift
        copy.categoryBand = categoryBand.map(Self.folded)
        copy.categoryOverlay = categoryOverlay.map(Self.folded)
        copy.categoryTime = categoryTime.map(Self.folded)
        copy.exchangeDefaults = exchangeDefaults.mapValues(Self.folded)
```
In `init(from:)` add, after `gridLocator`:
```swift
        categoryBand = try c.decodeIfPresent(String.self, forKey: .categoryBand)
        categoryOverlay = try c.decodeIfPresent(String.self, forKey: .categoryOverlay)
        categoryTime = try c.decodeIfPresent(String.self, forKey: .categoryTime)
        exchangeDefaults = try c.decodeIfPresent([String: String].self, forKey: .exchangeDefaults) ?? [:]
```
And add to the same extension:
```swift
    /// Every long-standing key is always written (as the synthesized encoder
    /// did); the four additions only when set, so a profile that never used
    /// them encodes byte-for-byte as before.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(callsign, forKey: .callsign)
        try c.encode(name, forKey: .name)
        try c.encode(email, forKey: .email)
        try c.encode(address, forKey: .address)
        try c.encode(city, forKey: .city)
        try c.encode(stateProvince, forKey: .stateProvince)
        try c.encode(postalCode, forKey: .postalCode)
        try c.encode(country, forKey: .country)
        try c.encode(club, forKey: .club)
        try c.encode(operators, forKey: .operators)
        try c.encode(categoryOperator, forKey: .categoryOperator)
        try c.encode(categoryAssisted, forKey: .categoryAssisted)
        try c.encode(categoryPower, forKey: .categoryPower)
        try c.encode(categoryStation, forKey: .categoryStation)
        try c.encode(categoryTransmitter, forKey: .categoryTransmitter)
        try c.encode(gridLocator, forKey: .gridLocator)
        try c.encodeIfPresent(categoryBand, forKey: .categoryBand)
        try c.encodeIfPresent(categoryOverlay, forKey: .categoryOverlay)
        try c.encodeIfPresent(categoryTime, forKey: .categoryTime)
        if !exchangeDefaults.isEmpty { try c.encode(exchangeDefaults, forKey: .exchangeDefaults) }
    }
```

- [ ] **Step 4: Replace `Sources/Core/Models/ContestLog.swift`**

```swift
import Foundation

/// The persisted document payload (`.qplog` = JSON of this).
///
/// **Schema 2** (spec §1.5): the entrant's side (`sideID`) and fixed sent
/// exchange (`sentExchange`) replace the party-shaped `myLocation` /
/// `exchangeName` / `exchangeMember`, which remain as computed views so the
/// party UI and every existing test read unchanged. Documents written by
/// earlier builds decode through `LegacyKeys`; this build writes schema 2 only,
/// so a log saved here needs this build or later (Decision 10).
struct ContestLog: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    /// Always `currentSchemaVersion` in memory: a legacy document is migrated
    /// on decode and written back in today's shape.
    var schemaVersion: Int = ContestLog.currentSchemaVersion
    /// The contest id — `PartyDefinition.id` / `ContestDefinition.id`, e.g.
    /// "ksqp". The JSON key and the Swift name are the persisted contract.
    var partyID: String
    var station: StationProfile
    /// The side of the contest this entrant is on: a lowered party's `inside`
    /// or `outside`, a v2 contest's own side ids. A stored id the contest does
    /// not declare — a legacy `outside` on a single-side party — is resolved
    /// at score time by `ContestDefinition.resolvedSideID(_:)`.
    var sideID: String
    /// My fixed sent exchange, element id → values: one value per element,
    /// several for a county-line `location`. Per-row values (`rst`, `serial`)
    /// never live here. Never holds an empty value or an empty list.
    var sentExchange: [String: [String]] { didSet { sentExchange = Self.compact(sentExchange) } }
    var qsos: [QSO]
    /// Per-contest CW macros (Run + S&P sets).
    var messages: MessageSets
    /// Run vs Search & Pounce. Persisted so reopening a log mid-contest
    /// restores the mode the operator was actually in, rather than snapping
    /// back to Run.
    var operatingMode: OperatingMode
    /// Whether the operator has been through Contest Setup for this log —
    /// new documents prompt for setup immediately.
    var setupCompleted: Bool
    /// The self-declared entry class (`ScoreFactors.entryClasses`) this log
    /// claims — the Skeeter Hunt's X1–X4. Stored as the class `id`; an empty
    /// or stale id resolves to the contest's first (lowest-factor) class, so a
    /// log that never chose cannot claim a multiplier the operator did not.
    var entryClassID: String = ""
    /// Winter Field Day objectives claimed (`ScoreFactors.objectives` ids);
    /// the score factor is 1 + the sum of their `om`s. Empty everywhere else.
    var selectedObjectives: [String] = []
    /// Field Day checklist bonuses claimed, id → count (1 for a plain bonus,
    /// the transmitter count for a per-count one). Empty everywhere else.
    var declaredBonuses: [String: Int] = [:]
    /// POTA park reference(s) this contest is being operated from — the
    /// *current* Contest Setup value, normalized park references. Stamped
    /// into each row's `myPotaRefs` at logging, so a mid-contest park change
    /// affects later rows only. Empty for every log that is not an activation.
    var myPotaRefs: [String] = []
    /// Whether spotting-network information — cluster or hub — was ever
    /// delivered into this contest's session. Set once and never cleared:
    /// reception is access (NAQP rule 5A(ii)'s word), access is what the
    /// Cabrillo ASSISTED/NON-ASSISTED split turns on everywhere, and a
    /// restart mid-contest must not launder it.
    var usedSpots: Bool = false
    /// The score as computed when this log was last saved, with the rules
    /// installed then — the frozen "what I claimed" figure the Contest
    /// Dashboard shows for past seasons. Stamped by the save path
    /// (`stampingScoreSnapshot`) and read back from the *file* by the
    /// dashboard; the running document never reads it. Nil for a draft.
    var scoreSnapshot: ScoreSnapshot? = nil

    // MARK: Views over sideID / sentExchange (the party shape)

    /// The party reading of the side and sent location: `inside` with the sent
    /// counties, anything else as out-of-state with the first sent token.
    /// A view: the stored state is `sideID` + `sentExchange`.
    var myLocation: MyLocation {
        get {
            sideID == PartyLowering.insideID
                ? .inState(counties: sentExchange[ExchangeElementID.location] ?? [])
                : .outOfState(location: sentExchange[ExchangeElementID.location]?.first ?? "")
        }
        set {
            sideID = Self.sideID(for: newValue)
            sentExchange[ExchangeElementID.location] = newValue.sentExchanges
        }
    }
    /// The operator name sent in every exchange (NAQP rule 10). Empty where none.
    var exchangeName: String {
        get { sentExchange[ExchangeElementID.name]?.first ?? "" }
        set { sentExchange[ExchangeElementID.name] = [newValue] }
    }
    /// The member-number-or-power element sent in every exchange (Skeeter Hunt).
    var exchangeMember: String {
        get { sentExchange[ExchangeElementID.member]?.first ?? "" }
        set { sentExchange[ExchangeElementID.member] = [newValue] }
    }

    /// The side a party location puts an entrant on. A no-home-region party's
    /// forced out-of-state reads `outside`, which `resolvedSideID` maps to its
    /// single `all` side.
    static func sideID(for location: MyLocation) -> String {
        location.isInState ? PartyLowering.insideID : PartyLowering.outsideID
    }

    /// The assisted-category warning's one predicate: spotting information
    /// reached this log while Contest Setup claims NON-ASSISTED.
    var spotsContradictNonAssistedClaim: Bool {
        usedSpots && station.categoryAssisted == .nonAssisted
    }

    /// The QSO number to send for the next contact, for contests whose
    /// exchange carries one. Derived from the highest number already sent
    /// rather than from the row count, because a county-line contact expands
    /// into several rows that all share one number. Deleting a QSO deliberately
    /// does *not* renumber the rest: those numbers went out on the air.
    var nextSerial: Int {
        (qsos.compactMap(\.serialSent).max() ?? 0) + 1
    }

    /// The category axes as an `OperatingTimeRule.appliesTo` /
    /// `Categories` reads them — Cabrillo raw values, keyed by axis. `mode` is
    /// derived from the rows exactly as the Cabrillo header derives it.
    var categoryValues: [String: String] {
        [
            "operator": station.categoryOperator.rawValue,
            "assisted": station.categoryAssisted.rawValue,
            "power": station.categoryPower.rawValue,
            "station": station.categoryStation.rawValue,
            "transmitter": station.categoryTransmitter.rawValue,
            "band": station.categoryBand ?? "ALL",
            "mode": CabrilloExporter.categoryMode(qsos),
            "overlay": station.categoryOverlay ?? "",
            "time": station.categoryTime ?? "",
        ]
    }

    /// The rule for a log with no stored mode: the first-listed side of a
    /// party — inside, the multiplier everyone is chasing — runs; every other
    /// side searches. Static so both inits can call it before `self` exists.
    private static func deriveOperatingMode(sideID: String) -> OperatingMode {
        sideID == PartyLowering.insideID ? .run : .searchPounce
    }

    /// The mode this log should start in when none is stored.
    var derivedOperatingMode: OperatingMode {
        Self.deriveOperatingMode(sideID: sideID)
    }

    init(
        partyID: String,
        station: StationProfile = StationProfile(),
        myLocation: MyLocation = .outOfState(location: ""),
        qsos: [QSO] = [],
        messages: MessageSets = .standard,
        operatingMode: OperatingMode? = nil,
        setupCompleted: Bool = false,
        exchangeName: String = "",
        exchangeMember: String = "",
        entryClassID: String = "",
        myPotaRefs: [String] = []
    ) {
        self.partyID = partyID
        self.station = station
        self.sideID = Self.sideID(for: myLocation)
        self.sentExchange = Self.compact([
            ExchangeElementID.location: myLocation.sentExchanges,
            ExchangeElementID.name: [exchangeName],
            ExchangeElementID.member: [exchangeMember],
        ])
        self.qsos = qsos
        self.messages = messages
        self.operatingMode = operatingMode ?? Self.deriveOperatingMode(sideID: Self.sideID(for: myLocation))
        self.setupCompleted = setupCompleted
        self.entryClassID = entryClassID
        self.myPotaRefs = myPotaRefs
    }

    /// Drops empty values and then empty lists — the map's one invariant.
    static func compact(_ map: [String: [String]]) -> [String: [String]] {
        map.compactMapValues { values in
            let kept = values.filter { !$0.isEmpty }
            return kept.isEmpty ? nil : kept
        }.filter { !$0.key.isEmpty }
    }

    // MARK: Codable — schema 2 written, schema 1 read

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partyID, station, sideID, sentExchange, qsos, messages, operatingMode, setupCompleted
        case entryClassID, selectedObjectives, declaredBonuses, usedSpots, myPotaRefs, scoreSnapshot
    }

    private enum LegacyKeys: String, CodingKey { case myLocation, exchangeName, exchangeMember }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        _ = try c.decode(Int.self, forKey: .schemaVersion)   // present in every document; the shape is read from the keys
        schemaVersion = Self.currentSchemaVersion
        partyID = try c.decode(String.self, forKey: .partyID)
        station = try c.decode(StationProfile.self, forKey: .station)
        qsos = try c.decode([QSO].self, forKey: .qsos)
        if c.contains(.sideID) {
            sideID = try c.decode(String.self, forKey: .sideID)
            sentExchange = Self.compact(try c.decodeIfPresent([String: [String]].self, forKey: .sentExchange) ?? [:])
        } else {
            // Schema 1: the party location, name and member element.
            let l = try decoder.container(keyedBy: LegacyKeys.self)
            let location = try l.decode(MyLocation.self, forKey: .myLocation)
            sideID = Self.sideID(for: location)
            sentExchange = Self.compact([
                ExchangeElementID.location: location.sentExchanges,
                ExchangeElementID.name: [try l.decodeIfPresent(String.self, forKey: .exchangeName) ?? ""],
                ExchangeElementID.member: [try l.decodeIfPresent(String.self, forKey: .exchangeMember) ?? ""],
            ])
        }
        // Documents written before per-contest macros existed get the defaults.
        messages = try c.decodeIfPresent(MessageSets.self, forKey: .messages) ?? .standard
        // Logs written before the mode was persisted derive one from the side
        // rather than defaulting an out-of-state operator into Run.
        operatingMode = try c.decodeIfPresent(OperatingMode.self, forKey: .operatingMode)
            ?? Self.deriveOperatingMode(sideID: sideID)
        // Legacy docs in active use (callsign set) count as already set up.
        setupCompleted = try c.decodeIfPresent(Bool.self, forKey: .setupCompleted)
            ?? !station.callsign.isEmpty
        entryClassID = try c.decodeIfPresent(String.self, forKey: .entryClassID) ?? ""
        selectedObjectives = try c.decodeIfPresent([String].self, forKey: .selectedObjectives) ?? []
        declaredBonuses = try c.decodeIfPresent([String: Int].self, forKey: .declaredBonuses) ?? [:]
        // Documents written before the fact was recorded used no spots.
        usedSpots = try c.decodeIfPresent(Bool.self, forKey: .usedSpots) ?? false
        myPotaRefs = try c.decodeIfPresent([String].self, forKey: .myPotaRefs) ?? []
        scoreSnapshot = try c.decodeIfPresent(ScoreSnapshot.self, forKey: .scoreSnapshot)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.currentSchemaVersion, forKey: .schemaVersion)
        try c.encode(partyID, forKey: .partyID)
        try c.encode(station, forKey: .station)
        try c.encode(sideID, forKey: .sideID)
        try c.encode(sentExchange, forKey: .sentExchange)
        try c.encode(qsos, forKey: .qsos)
        try c.encode(messages, forKey: .messages)
        try c.encode(operatingMode, forKey: .operatingMode)
        try c.encode(setupCompleted, forKey: .setupCompleted)
        try c.encode(entryClassID, forKey: .entryClassID)
        if !selectedObjectives.isEmpty { try c.encode(selectedObjectives, forKey: .selectedObjectives) }
        if !declaredBonuses.isEmpty { try c.encode(declaredBonuses, forKey: .declaredBonuses) }
        try c.encode(usedSpots, forKey: .usedSpots)
        try c.encode(myPotaRefs, forKey: .myPotaRefs)
        try c.encodeIfPresent(scoreSnapshot, forKey: .scoreSnapshot)
    }

    /// The copy the save path writes: `scoreSnapshot` set to this log's
    /// score as of now — the engine's figures when the party's rules are
    /// installed (`rules`), counts only when they are not — or nil for a
    /// draft (Contest Setup unfinished, or nothing logged yet). Everything
    /// else is untouched. (Task 11 moves this onto `ContestCatalog`.)
    func stampingScoreSnapshot(
        rules: (String) -> PartyDefinition? = { PartyCatalog.party(id: $0) }
    ) -> ContestLog {
        var stamped = self
        stamped.scoreSnapshot = setupCompleted && !qsos.isEmpty
            ? ScoreSnapshot.best(for: self, rules: rules)
            : nil
        return stamped
    }

    static func decode(from data: Data) throws -> ContestLog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ContestLog.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
```

- [ ] **Step 5: Build, run the class, then the full suite**

Run: build; `ContestLogShapeTests`; full suite. Expected: `Executed 2984 tests, with 0 failures` (2977 + 7). Watch `LogDocumentTests`, `ModelTests`, `ContestLogScoreSnapshotTests`, `LogFolderTests`, `DashboardModelTests`, `QSOPostureTests` in particular — they round-trip documents. A failure there is a shape regression: read it before touching anything.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Models/ContestLog.swift Sources/Core/Models/StationProfile.swift Tests/Core/ContestLogShapeTests.swift QSOPartyLogger.xcodeproj
git commit -m "log: ContestLog schema 2 — sideID and sentExchange with the party views kept, objectives and declared bonuses, categoryValues; StationProfile band/overlay/time axes and exchangeDefaults

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: The model gaps — `Resolver.callsignOverrides`, `CabrilloSpec.reportColumn`, `ContestDefinition` helpers and validation, `OperatingTime.offPeriods`, `ExchangeValidator.owningSet`

**Files:**
- Modify: `Sources/Core/Contests/MultiplierClass.swift`, `Sources/Core/Contests/ContestRules.swift`, `Sources/Core/Contests/ContestDefinition.swift`, `Sources/Core/Contests/OperatingTime.swift`, `Sources/Core/Contests/ExchangeValidator.swift`
- Test: additions to `Tests/Core/ContestDefinitionTests.swift`, `Tests/Core/ExchangeValidatorTests.swift`, `Tests/Core/OperatingTimeTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/Core/ContestDefinitionTests.swift` (inside the class; `fixture()` there returns the decoded `cqwwcw` fixture — reuse it):

```swift
    // MARK: Engine-switch additions

    func testResolvedSideID() throws {
        let c = try fixture()                                   // one side: all
        XCTAssertEqual(c.resolvedSideID("all"), "all")
        XCTAssertEqual(c.resolvedSideID("outside"), "all", "a legacy party side maps to the only side")
        let ks = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "ksqp")))
        XCTAssertEqual(ks.resolvedSideID("inside"), "inside")
        XCTAssertEqual(ks.resolvedSideID("nope"), "outside", "an unknown side on a two-sided contest is the catch-all last side")
    }

    func testCountyRosterAndReceivedElementsWithCallEcho() throws {
        let ks = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "ksqp")))
        XCTAssertEqual(ks.countyRoster()?.id, "counties")
        XCTAssertEqual(ks.countyRoster()?.tokens.count, 105)
        XCTAssertNil(try fixture().countyRoster())
        let f = try fixture()
        let withEcho = ContestDefinition(
            id: "ss", name: "SS", family: .domestic, bands: f.bands, modeClasses: [.cw], sides: f.sides,
            exchange: [ExchangeElement(id: "serial", kind: .serial, sentBy: ["all": .init()]),
                       ExchangeElement(id: "call", kind: .callEcho, sentBy: ["all": .init()]),
                       ExchangeElement(id: "check", kind: .check, sentBy: ["all": .init()])],
            multipliers: [], points: [PointRule(points: 2)], dupe: DupeRule(scope: .contest), cabrillo: CabrilloSpec(contest: "ARRL-SS-CW", location: .section))
        XCTAssertEqual(withEcho.receivedElements(for: "all").map(\.id), ["serial", "check"])
        XCTAssertEqual(withEcho.receivedElements(for: "all", includingCallEcho: true).map(\.id), ["serial", "call", "check"])
    }

    func testCallsignOverridesDecodeAndValidate() throws {
        var json = try fixtureJSON()
        var mults = json["multipliers"] as! [[String: Any]]
        // A dxccEntity resolver reading a received token may name the sets it takes tokens over from.
        json["tokenSets"] = [["id": "states", "term": "state", "termPlural": "states", "tokens": [["abbr": "PA"], ["abbr": "TX"]]]]
        // Keep the fixture's own elements (the zone resolver names `zone`), add a location token element.
        json["exchange"] = (json["exchange"] as! [[String: Any]])
            + [["id": "location", "kind": "token", "sentBy": ["all": ["sets": ["states", "dxccPrefix"]]]]]
        mults[1]["resolvers"] = [["kind": "dxccEntity", "from": "receivedTokenOrCallsign", "element": "location", "list": "arrl",
                                  "callsignOverrides": ["states"]]]
        json["multipliers"] = mults
        let c = try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(c.multipliers[1].resolvers[0].callsignOverrides, ["states"])
        XCTAssertEqual(try ContestDefinition.decode(try c.encoded()), c)
        // Only that resolver shape may carry it, and only for sets the element accepts.
        mults[1]["resolvers"] = [["kind": "dxccEntity", "from": "callsign", "list": "arrl", "callsignOverrides": ["states"]]]
        json["multipliers"] = mults
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json)))
        mults[1]["resolvers"] = [["kind": "dxccEntity", "from": "receivedTokenOrCallsign", "element": "location", "list": "arrl",
                                  "callsignOverrides": ["provinces"]]]
        json["multipliers"] = mults
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .unknownTokenSet("provinces"))
        }
    }

    func testReportColumnDecodesWithDefaultFalse() throws {
        XCTAssertFalse(try fixture().cabrillo.reportColumn)
        var json = try fixtureJSON()
        var cab = json["cabrillo"] as! [String: Any]; cab["reportColumn"] = true; json["cabrillo"] = cab
        XCTAssertTrue(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json)).cabrillo.reportColumn)
    }

    func testCountyKeyedBonusesNeedACountyRoster() throws {
        var json = try fixtureJSON()
        json["bonuses"] = [["type": "sweepTiers", "tiers": [["count": 10, "points": 100]]]]
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .bonusNeedsCountyClass)
        }
        // A designated sweep must name tokens of that roster.
        let ks = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "ksqp")))
        let bad = ContestDefinition(id: ks.id, name: ks.name, family: ks.family, bands: ks.bands, modeClasses: ks.modeClasses,
                                    tokenSets: ks.tokenSets, sides: ks.sides, exchange: ks.exchange, multipliers: ks.multipliers,
                                    points: ks.points, dupe: ks.dupe, pairing: ks.pairing, sideRules: ks.sideRules,
                                    bonuses: [.designatedCountySweep(counties: ["MRN", "ZZZ"], need: 1, points: 500)],
                                    cabrillo: ks.cabrillo)
        XCTAssertThrowsError(try bad.validate()) { error in
            XCTAssertEqual(error as? ContestValidationError, .unknownBonusToken("ZZZ"))
        }
    }

    func testScoreFactorIdsMustBeUnique() throws {
        var json = try fixtureJSON()
        json["scoreFactors"] = ["objectives": [["id": "1o", "label": "a", "om": 1], ["id": "1o", "label": "b", "om": 2]]]
        XCTAssertThrowsError(try ContestDefinition.decode(try JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .duplicateID("objective", "1o"))
        }
    }
```
If `ContestDefinitionTests` has no `fixtureJSON()` helper, add one beside `fixture()`:
```swift
    private func fixtureJSON() throws -> [String: Any] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
```
(Look at how the existing test that sets `json["schemaVersion"] = 1` builds its dictionary and reuse that helper's name instead if one exists.) The `sweepTiers` JSON shape (`tiers: [{count, points}]`) — confirm against `BonusRule.init(from:)` in `PartyDefinition.swift` and adjust the literal to its keys.

Append to `Tests/Core/ExchangeValidatorTests.swift`:

```swift
    // MARK: Ownership — the one classification validation and scoring share

    func testOwningSetIsTheFirstAcceptingSetInSendOrder() throws {
        let ks = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "ksqp")))
        let loc = try XCTUnwrap(ks.exchange.first { $0.id == "location" })
        XCTAssertEqual(ExchangeValidator.owningSet(of: "MRN", element: loc, contest: ks, side: "inside"), "counties")
        XCTAssertEqual(ExchangeValidator.owningSet(of: "tx", element: loc, contest: ks, side: "inside"), "states")
        XCTAssertEqual(ExchangeValidator.owningSet(of: "ON", element: loc, contest: ks, side: "inside"), "provinces")
        XCTAssertEqual(ExchangeValidator.owningSet(of: "DX", element: loc, contest: ks, side: "inside"), "dxToken")
        XCTAssertNil(ExchangeValidator.owningSet(of: "KS", element: loc, contest: ks, side: "inside"), "the excluded home state token belongs to no set")
        XCTAssertNil(ExchangeValidator.owningSet(of: "DL", element: loc, contest: ks, side: "inside"), "Kansas takes the DX token, not prefixes")
        // An outside entrant may only receive counties (pairing) — nothing else has an owner.
        XCTAssertEqual(ExchangeValidator.owningSet(of: "MRN", element: loc, contest: ks, side: "outside"), "counties")
        XCTAssertNil(ExchangeValidator.owningSet(of: "TX", element: loc, contest: ks, side: "outside"))
    }

    func testOwningSetKnowsPrefixesAliasesAndDXAliases() throws {
        let wa = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "warun")))
        let loc = try XCTUnwrap(wa.exchange.first { $0.id == "location" })
        XCTAssertEqual(ExchangeValidator.owningSet(of: "DL", element: loc, contest: wa, side: "inside"), "dxccPrefix")
        XCTAssertEqual(ExchangeValidator.owningSet(of: "PA", element: loc, contest: wa, side: "inside"), "states", "a state code stays a state here; the callsign override lives in the engine")
        XCTAssertNil(ExchangeValidator.owningSet(of: "ZZZ", element: loc, contest: wa, side: "inside"))
        let al = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "alqp")))
        let alLoc = try XCTUnwrap(al.exchange.first { $0.id == "location" })
        XCTAssertEqual(ExchangeValidator.owningSet(of: "DC", element: alLoc, contest: al, side: "inside"), "states", "an alias key belongs to the set that aliases it")
        let fl = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "fqp")))
        let flLoc = try XCTUnwrap(fl.exchange.first { $0.id == "location" })
        XCTAssertEqual(ExchangeValidator.owningSet(of: "R2", element: flLoc, contest: fl, side: "inside"), "dxAliases")
    }
```

Append to `Tests/Core/OperatingTimeTests.swift` (use the class's existing row-building helper; if it has none, build rows with `QSO(call:band:modeClass:rawMode:rstSent:rstRcvd:myLoc:theirLoc:)` and explicit `timestampUTC`):

```swift
    func testOffPeriodsAreTheEmptyMinutesBetweenTwoRows() {
        // SS package: rows at 0114 and 0145 → 0115–0144 is 30 empty minutes and counts as off time.
        let day = Date(timeIntervalSince1970: 1_793_491_200)   // 2026-11-01 00:00:00Z
        func at(_ hhmm: Int) -> Date { day.addingTimeInterval(TimeInterval((hhmm / 100) * 3600 + (hhmm % 100) * 60)) }
        let rows = [QSO(timestampUTC: at(0114), call: "A", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "KS"),
                    QSO(timestampUTC: at(0145), call: "B", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "KS"),
                    QSO(timestampUTC: at(0200), call: "C", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: "KS")]
        let r = OperatingTime.compute(rows: rows, rule: OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 30))
        XCTAssertEqual(r.offMinutes, 30)
        XCTAssertEqual(r.offPeriods, [OperatingTime.OffPeriod(start: at(0115), end: at(0144))])
        let short = OperatingTime.compute(rows: rows, rule: OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 31))
        XCTAssertEqual(short.offPeriods, [], "0115–0144 is 30 minutes; a 31-minute rule does not count it")
    }
```

- [ ] **Step 2: Run to verify they fail**

Run the three classes. Expected: build errors (`resolvedSideID`, `countyRoster`, `includingCallEcho`, `callsignOverrides`, `reportColumn`, `owningSet`, `OffPeriod`, the new error cases).

- [ ] **Step 3: `Resolver.callsignOverrides`** — in `Sources/Core/Contests/MultiplierClass.swift`, add the stored property after `unlessSuffix`, thread it through the init, `CodingKeys` and `init(from:)`:

```swift
    /// `dxccEntity` with `from: receivedTokenOrCallsign` only: the ids of the
    /// enumerated sets whose token this resolver takes over when the worked
    /// callsign decides the token is a DXCC prefix — a state or province code
    /// that is also a prefix (`PA` is Pennsylvania and the Netherlands, `ON`
    /// Ontario and Belgium, `SK` Saskatchewan and Sweden). The engine moves
    /// the token's ownership to `dxccPrefix` when its owner is one of these
    /// sets, the callsign is not US/Canadian, and `DXCCTable` resolves the
    /// callsign to the very entity the token names — N1MM's split: the
    /// exchange says which location was sent, the callsign which entity sent
    /// it. `PartyLowering` emits `["states", "provinces"]` on every side that
    /// counts DXCC entities separately, which is exactly today's
    /// `dxCountsEntities` gate; nil = the token's owner is never questioned.
    let callsignOverrides: [String]?
```
Init signature becomes `…, sides: [String]? = nil, unlessSuffix: [String]? = nil, callsignOverrides: [String]? = nil)`; add `case callsignOverrides` to `CodingKeys` and `callsignOverrides: try c.decodeIfPresent([String].self, forKey: .callsignOverrides)` to `init(from:)`.

- [ ] **Step 4: `CabrilloSpec.reportColumn`** — in `Sources/Core/Contests/ContestRules.swift`, add after `homeLocation`:

```swift
    /// Write a report column in the QSO line even where the exchange declares
    /// no `rst`, `serial` or `name` element — the generic Cabrillo template's
    /// slot, filled with the row's report or the mode's default (599 / 59).
    /// `PartyLowering` sets it for the four parties whose exchange has none of
    /// the three (MDC, IDQP, NCQP, WIQP), which is what their logs have always
    /// carried; Field Day (class + section) leaves it false. Default false.
    let reportColumn: Bool
```
Init: `…, homeLocation: String? = nil, reportColumn: Bool = false)`; `CodingKeys` add `reportColumn`; decode `reportColumn: try c.decodeIfPresent(Bool.self, forKey: .reportColumn) ?? false`.

- [ ] **Step 5: `ContestDefinition` helpers and validation** — in `Sources/Core/Contests/ContestDefinition.swift`:

Replace `receivedElements(for:)` with:
```swift
    /// The elements an entrant on `side` receives, in spec order: those sent
    /// by any side it may work. The call echo is the call field itself and is
    /// excluded unless `includingCallEcho` — the Cabrillo QSO line, which
    /// writes the echoed call inside the received columns, asks for it.
    func receivedElements(for side: String, includingCallEcho: Bool = false) -> [ExchangeElement] {
        let workable = Set(workableSides(for: side))
        return exchange.filter { e in
            (includingCallEcho || e.kind != .callEcho) && e.sentBy.keys.contains(where: workable.contains)
        }
    }
```
Add after `workableSides(for:)`:
```swift
    /// The side a log's `sideID` names; for an id this contest does not
    /// declare — a document written before it declared sides, or a lowered
    /// party whose single side is `all` while the log says `outside` — the
    /// contest's only side, else its last-listed side (the catch-all: sides
    /// are evaluated first-match, so the last is the one that takes everyone
    /// else).
    func resolvedSideID(_ id: String) -> String {
        if sides.contains(where: { $0.id == id }) { return id }
        return sides.count == 1 ? sides[0].id : (sides.last?.id ?? id)
    }

    /// The token set the `county` class lists — what the county-keyed bonuses
    /// (`mobileCountyCount`, `activatedCountyCount`, `sweepTiers`,
    /// `designatedCountySweep`) and the ADIF `cnty` fields read. Nil for a
    /// contest with no `county` class.
    func countyRoster(bundle: Bundle = .main) -> TokenSet? {
        guard let id = multipliers.first(where: { $0.id == MultClass.county.rawValue })?.roster else { return nil }
        return tokenSet(id: id, bundle: bundle)
    }
```
In `validate(bundle:)`, inside the `for m in multipliers { … for r in m.resolvers { … } }` loop, after the per-kind `switch r.kind`, add:
```swift
                if let overrides = r.callsignOverrides {
                    guard r.kind == .dxccEntity, r.from == .receivedTokenOrCallsign, let element = r.element,
                          let el = exchange.first(where: { $0.id == element }) else { throw bad }
                    let accepted = Set(el.sentBy.values.flatMap { $0.sets ?? [] })
                    for set in overrides where !accepted.contains(set) { throw ContestValidationError.unknownTokenSet(set) }
                }
```
At the end of `validate`, before its closing brace, add:
```swift
        // County-keyed bonuses read the county class's roster.
        let countyKeyed = bonuses.contains { bonus in
            switch bonus {
            case .mobileCountyCount, .activatedCountyCount, .sweepTiers, .designatedCountySweep: true
            case .workStation, .callAreaSum: false
            }
        }
        if countyKeyed {
            guard let roster = countyRoster(bundle: bundle) else { throw ContestValidationError.bonusNeedsCountyClass }
            for case .designatedCountySweep(let counties, _, _) in bonuses {
                for token in counties where !roster.abbrs.contains(token.uppercased()) {
                    throw ContestValidationError.unknownBonusToken(token)
                }
            }
        }
        // Self-declared ids are keys the log stores; each must be unique.
        if let f = scoreFactors {
            for (what, ids) in [("entry class", f.entryClasses.map(\.id)), ("objective", f.objectives.map(\.id)),
                                ("declared bonus", f.declaredBonuses.map(\.id))] {
                var seen = Set<String>()
                for id in ids where !seen.insert(id).inserted { throw ContestValidationError.duplicateID(what, id) }
            }
        }
        // An activated multiplier is earned by operating from a token of the
        // class's roster; a class with no roster has nothing to operate from.
        for (_, rules) in sideRules {
            if let a = rules.activated, let cls = multipliers.first(where: { $0.id == a.classID }), cls.roster == nil {
                throw ContestValidationError.activatedNeedsRoster(a.classID)
            }
        }
```
(The `switch bonus` must be exhaustive over `BonusRule`'s six cases — check the enum in `PartyDefinition.swift` and list every case.) Add to `ContestValidationError`: `case bonusNeedsCountyClass, unknownBonusToken(String), activatedNeedsRoster(String)` with descriptions `"A county-keyed bonus needs a 'county' multiplier class with a roster."`, `"Bonus names '\(t)', which is not in the county roster."`, `"Activated multiplier class '\(id)' lists no roster."`.

- [ ] **Step 6: `OperatingTime.offPeriods`** — in `Sources/Core/Contests/OperatingTime.swift`:

```swift
    /// One credited off period: the empty clock minutes strictly between two
    /// rows, first and last minute inclusive — the SS package's 0115–0144.
    struct OffPeriod: Equatable, Sendable {
        let start: Date
        let end: Date
    }
```
Add `var offPeriods: [OffPeriod] = []` to `Result`; in `compute`, inside `if empty >= rule.minOffMinutes {`, after `result.offMinutes += empty`, add:
```swift
                result.offPeriods.append(OffPeriod(start: date(minute: previous + 1), end: date(minute: now - 1)))
```
and add the helper:
```swift
    /// The first second of a whole minute since the epoch.
    static func date(minute: Int) -> Date { Date(timeIntervalSince1970: TimeInterval(minute * 60)) }
```

- [ ] **Step 7: `ExchangeValidator.owningSet`** — in `Sources/Core/Contests/ExchangeValidator.swift`, add above `validateToken`:

```swift
    /// The set a received token belongs to, for an entrant on `side`: the
    /// first of the element's sets — in the order the element sends them,
    /// over the sides the entrant may work — that accepts it, the dynamic
    /// `dxccPrefix` accepting a known DXCC prefix that no enumerated set
    /// claims. Nil when nothing accepts it.
    ///
    /// **Validation and scoring classify through this one function**, so a
    /// token cannot be valid under one reading and counted under another:
    /// `validateToken` classifies with it, and `ScoreEngine`'s `receivedToken`
    /// resolver fires only when the token's owner is its set (with the
    /// callsign override the engine layers on top — `Resolver.callsignOverrides`).
    static func owningSet(of token: String, element: ExchangeElement, contest: ContestDefinition,
                          side: String, bundle: Bundle = .main) -> String? {
        let sets: [(id: String, set: TokenSet?)] = element.setsSent(by: contest.workableSides(for: side)).map {
            ($0, contest.tokenSet(id: $0, bundle: bundle))
        }
        return owningSet(of: token, among: sets)
    }

    /// The classification itself, over sets already resolved once.
    static func owningSet(of token: String, among sets: [(id: String, set: TokenSet?)]) -> String? {
        let t = token.trimmingCharacters(in: .whitespaces).uppercased()
        let accepted = sets.reduce(into: Set<String>()) { $0.formUnion($1.set?.acceptedTokens ?? []) }
        for entry in sets {
            if entry.id == "dxccPrefix" {
                if isDXPrefix(t, excluding: accepted) { return entry.id }
            } else if let set = entry.set, set.accepts(t) {
                return entry.id
            }
        }
        return nil
    }
```
Then in `validateToken`, replace the local `func classify(_ token:)` and its `allAccepted` with a call to the shared classifier:
```swift
        func classify(_ token: String) -> (set: String, value: String)? {
            owningSet(of: token, among: sets).map { ($0, token) }
        }
```
(delete the now-unused `let allAccepted = …` line). `ExchangeValidatorTests`' parity test over all 50 parties keeps this refactor honest.

- [ ] **Step 8: Build, run the three classes, then the full suite**

Expected: the three classes pass; full suite `Executed 2995 tests, with 0 failures` (2984 + 11: 6 definition, 2 validator, 1 op-time… count what you added and record the exact N).

- [ ] **Step 9: Commit**

```bash
git add Sources/Core/Contests Tests/Core/ContestDefinitionTests.swift Tests/Core/ExchangeValidatorTests.swift Tests/Core/OperatingTimeTests.swift
git commit -m "contests: token ownership shared by validator and engine, Resolver.callsignOverrides, CabrilloSpec.reportColumn, resolvedSideID/countyRoster, bonus and score-factor validation, off periods

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `PartyLowering` emits the overrides and `reportColumn`; a lowering cache; catalogues that lower on decode and memoise the bundle

**Files:**
- Modify: `Sources/Core/Contests/PartyLowering.swift`, `Sources/Core/Parties/PartyCatalog.swift`
- Test: additions to `Tests/Core/PartyLoweringTests.swift`, `Tests/Core/PartyCatalogTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/Core/PartyLoweringTests.swift`:

```swift
    // MARK: Engine-switch additions

    /// Today's `collidesWithDXCC` gate is `rule.dxCountsEntities`; the model
    /// carries it as `callsignOverrides` on the entity-counting dx resolver.
    func testCallsignOverridesFollowDXCountsEntitiesPerSide() throws {
        for p in PartyCatalog.loadBundled() {
            let c = try PartyLowering.lower(p)
            let dx = c.multipliers.first { $0.id == "dx" }
            for side in c.sides.map(\.id) {
                // The v1 rule that governs the side (`PartyLowering.rule`): only `inside` takes `inState`.
                let rule = side == "inside" ? p.multipliers.inState : p.multipliers.outState
                let entityResolvers = (dx?.resolvers ?? []).filter {
                    $0.kind == .dxccEntity && $0.countEntities && $0.applies(side: side, call: "X")
                }
                if rule.dxCountsEntities && !p.usesSections {
                    XCTAssertEqual(entityResolvers.first?.callsignOverrides, ["states", "provinces"], "\(p.id) \(side)")
                } else {
                    XCTAssertTrue(entityResolvers.allSatisfy { $0.callsignOverrides == nil }, "\(p.id) \(side)")
                }
            }
        }
    }

    func testReportColumnIsSetExactlyForThePartiesWithNoReportNumberOrName() throws {
        var flagged: [String] = []
        for p in PartyCatalog.loadBundled() where try PartyLowering.lower(p).cabrillo.reportColumn { flagged.append(p.id) }
        XCTAssertEqual(flagged.sorted(), ["idqp", "mdc", "ncqp", "wiqp"])
        for p in PartyCatalog.loadBundled() {
            XCTAssertEqual(try PartyLowering.lower(p).cabrillo.reportColumn,
                           !p.exchangeIncludesRST && !p.exchangeIncludesSerial && !p.exchangeIncludesName, p.id)
        }
    }

    func testLoweredIsCachedByValue() throws {
        let p = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        let a = PartyLowering.lowered(p), b = PartyLowering.lowered(p)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, try PartyLowering.lower(p))
        // A different value under the same id is not served from the cache.
        let url = try XCTUnwrap(Bundle.main.url(forResource: "ksqp", withExtension: "json", subdirectory: "Parties"))
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["name"] = "Kansas, renamed"
        let renamed = try PartyCatalog.decode(try JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(PartyLowering.lowered(renamed).name, "Kansas, renamed")
        XCTAssertEqual(PartyLowering.lowered(p).name, p.name)
    }
```

Append to `Tests/Core/PartyCatalogTests.swift`:

```swift
    /// A party file that passes the v1 checks but cannot lower into the model
    /// is refused at load with the model's own error, not scored silently.
    func testDecodeRefusesAPartyThatDoesNotLower() throws {
        // An alias that targets a state the party excludes: the v1 schema
        // allows it, the model's token set cannot express it.
        let json = """
        {"schemaVersion":1,"id":"nl","name":"No Lower","cabrilloContest":"NL","homeState":"KS","countyAbbrLength":3,
         "counties":[{"abbr":"MRN","name":"Marion"}],"excludedStateTokens":["MD"],"stateAliases":{"DC":"MD"},
         "validBands":["20m"],"allowedModes":["cw"],"points":{"phone":1,"cw":1,"digital":1},"dupeScope":"bandMode",
         "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
                        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
         "bonuses":[]}
        """
        XCTAssertThrowsError(try PartyCatalog.decode(Data(json.utf8))) { error in
            XCTAssertTrue(error is ContestValidationError, "\(error)")
        }
    }

    func testBundledLoadIsMemoised() {
        let a = PartyCatalog.loadBundled(), b = PartyCatalog.loadBundled()
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.count, 50)
    }
```
(If the literal above happens to decode — because `PartyDefinition` requires other keys — read `PartyDefinition`'s `CodingKeys`/required fields and add the smallest set of keys that makes the file *valid v1* while keeping the alias-to-excluded-target conflict; the point of the test is the second stage failing.)

- [ ] **Step 2: Run to verify they fail**

Run `PartyLoweringTests` and `PartyCatalogTests`. Expected: build errors (`lowered`), and the override/reportColumn assertions fail.

- [ ] **Step 3: `PartyLowering`** — in `Sources/Core/Contests/PartyLowering.swift`:

Add `import os` at the top. In `multipliers(for:sideIDs:)`, `case .dx`, give the entity-counting resolver the overrides where the party is not a sections party:
```swift
                if !entitySides.isEmpty {
                    resolvers.append(Resolver(kind: .dxccEntity, element: "location", from: .receivedTokenOrCallsign, list: .arrl,
                                              countEntities: true, sides: entitySides.count == sideIDs.count ? nil : entitySides,
                                              // Today's `collidesWithDXCC`: only where entities are told apart, and
                                              // never in a sections party, whose state/province tables are not consulted.
                                              callsignOverrides: p.usesSections ? nil : ["states", "provinces"]))
                }
```
In `lower(_:)`, the `CabrilloSpec`:
```swift
            cabrillo: CabrilloSpec(contest: p.cabrilloContest, location: p.hasHomeRegion ? .state : .entrantToken,
                                   homeLocation: p.hasHomeRegion ? p.homeState : nil,
                                   // The generic Cabrillo template's ex1 slot: today's exporter always writes
                                   // one (name → number → report), so a party with none of the three writes the report.
                                   reportColumn: !p.exchangeIncludesRST && !p.exchangeIncludesSerial && !p.exchangeIncludesName),
```
Add the cache, after `lower(_:)`:
```swift
    // MARK: Cache

    private static let log = Logger(subsystem: "org.b5n.QSOPartyLogger", category: "contests")
    private static let cache = OSAllocatedUnfairLock<[String: (party: PartyDefinition, contest: ContestDefinition)]>(initialState: [:])

    /// `lower(_:)`, memoised by party id and checked by value — the score
    /// sidebar and the NEW MULT badge lower on every keystroke through the
    /// party overloads, and lowering builds and validates every token set.
    ///
    /// Non-throwing on purpose: every `PartyDefinition` the app holds came
    /// through `PartyCatalog.decode`, which lowers and validates, so a value
    /// that does not lower here is a programming error, not a data error.
    static func lowered(_ p: PartyDefinition) -> ContestDefinition {
        if let hit = cache.withLock({ $0[p.id] }), hit.party == p { return hit.contest }
        do {
            let contest = try lower(p)
            cache.withLock { $0[p.id] = (p, contest) }
            return contest
        } catch {
            log.fault("party \(p.id, privacy: .public) does not lower: \(error.localizedDescription, privacy: .public)")
            preconditionFailure("party \(p.id) does not lower — PartyCatalog.decode admits only parties that do: \(error)")
        }
    }
```

- [ ] **Step 4: `PartyCatalog`** — in `Sources/Core/Parties/PartyCatalog.swift`:

Add `import os`. `decode(_:)` lowers as its last check:
```swift
    /// Decodes, validates the v1 shape, and proves the party lowers into the
    /// general model — a file that cannot lower is refused here with the
    /// model's error, never at scoring time.
    static func decode(_ data: Data) throws -> PartyDefinition {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let party = try decoder.decode(PartyDefinition.self, from: data)
        try party.validate()
        _ = try PartyLowering.lower(party)
        return party
    }
```
`loadBundled(bundle:)` memoised per bundle and logging every failure once:
```swift
    private static let log = Logger(subsystem: "org.b5n.QSOPartyLogger", category: "catalog")
    private static let bundledCache = OSAllocatedUnfairLock<[URL: [PartyDefinition]]>(initialState: [:])

    /// The bundle's parties, decoded once per bundle (its files never change
    /// while the app runs). A file that fails is logged — it used to vanish
    /// from the picker without a word — and skipped.
    static func loadBundled(bundle: Bundle = .main) -> [PartyDefinition] {
        if let cached = bundledCache.withLock({ $0[bundle.bundleURL] }) { return cached }
        guard let urls = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Parties") else { return [] }
        let parties = urls
            .compactMap { url -> PartyDefinition? in
                do { return try decode(try Data(contentsOf: url)) } catch {
                    log.error("bundled party \(url.lastPathComponent, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)")
                    return nil
                }
            }
            .sorted { $0.name < $1.name }
        bundledCache.withLock { $0[bundle.bundleURL] = parties }
        return parties
    }
```

- [ ] **Step 5: Build, run the two classes, then the full suite**

Expected: both classes pass; full suite `Executed 3000 tests, with 0 failures` (2995 + 5) — and noticeably faster than before (bundled parties decode once). **If any existing test's JSON-literal party now fails to decode**, it describes a party the model cannot express (the lowering's `ContestValidationError` says which rule): decide per case whether the *lowering* is too strict for a legal v1 party (fix the lowering, Article 4) or the *literal* was never a real party shape (fix the literal, and say so in the commit). Report every such case in the task summary.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Contests/PartyLowering.swift Sources/Core/Parties/PartyCatalog.swift Tests/Core/PartyLoweringTests.swift Tests/Core/PartyCatalogTests.swift
git commit -m "contests: lowering emits callsignOverrides and reportColumn, lowered() cache; PartyCatalog lowers on decode and memoises the bundle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: `ScoreEngine.score(log:contest:)` — the engine on the model

The old `score(log:party:)` stays exactly as it is (Task 9 compares against it). `MultKey` gains `classID` (with `multClass` as a computed view and the `multClass:` init kept), `ScoreBreakdown` gains the operating-time fields and class-id readers, and the whole model engine lands in a new file.

**Files:**
- Modify: `Sources/Core/Engine/ScoreEngine.swift` (only `MultKey`, `ScoreBreakdown`, two `private` → internal, `gains`)
- Create: `Sources/Core/Engine/ScoreEngine+Contest.swift`
- Test: `Tests/Core/ContestScoreEngineTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/Core/ContestScoreEngineTests.swift
import XCTest
@testable import QSOPartyLogger

/// The engine on `ContestDefinition`. The lowered parties are checked against
/// the old engine over a corpus in `EngineEquivalenceTests`; here the model's
/// own semantics are pinned: sides and pairing, token ownership and the
/// callsign override, resolvers, points context, caps, granted, factors,
/// bonuses, activated multipliers, operating time.
final class ContestScoreEngineTests: XCTestCase {
    let t0 = Date(timeIntervalSince1970: 1_795_824_000)   // 2026-11-28 00:00:00Z
    var seq = 0

    override func setUp() { seq = 0 }

    // MARK: Builders

    func cqww() throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try ContestDefinition.decode(try Data(contentsOf: url))
    }

    func lowered(_ id: String) throws -> ContestDefinition {
        try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: id)))
    }

    /// One row; every call advances the clock a minute (or `minutes`).
    func row(_ call: String, band: Band = .m20, mode: ModeClass = .cw, raw: String? = nil,
             rcvd: [String: String] = ["rst": "599"], sent: [String: String] = ["rst": "599"], minutes: Int? = nil) -> QSO {
        seq += minutes ?? 1
        return QSO(timestampUTC: t0.addingTimeInterval(Double(seq) * 60), call: call, band: band, modeClass: mode,
                   rawMode: raw ?? (mode == .phone ? "SSB" : mode == .cw ? "CW" : "RTTY"), sent: sent, rcvd: rcvd)
    }

    func log(_ contest: ContestDefinition, call: String = "KE5CW", side: String = "all",
             sent: [String: [String]] = ["rst": ["599"]], rows: [QSO],
             configure: (inout ContestLog) -> Void = { _ in }) -> ContestLog {
        var log = ContestLog(partyID: contest.id)
        log.station.callsign = call
        log.sideID = side
        log.sentExchange = sent
        log.qsos = rows
        configure(&log)
        return log
    }

    /// A small contest for one rule at a time.
    func contest(sides: [Side] = [Side(id: "all", label: "Everyone", predicate: .always, workedPredicate: .always)],
                 exchange: [ExchangeElement] = [ExchangeElement(id: "rst", kind: .rst, sentBy: ["all": .init()])],
                 multipliers: [MultiplierClass] = [], points: [PointRule] = [PointRule(points: 1)],
                 dupe: DupeRule = DupeRule(scope: .band), pairing: [String: [String]]? = nil,
                 sideRules: [String: SideRules] = [:], bonuses: [BonusRule] = [], scoreFactors: ScoreFactors? = nil,
                 operatingTime: OperatingTimeRule? = nil, modeClasses: [ModeClass] = [.cw],
                 allowedRawModes: [String]? = nil, tokenSets: [TokenSet] = []) throws -> ContestDefinition {
        let c = ContestDefinition(
            id: "t", name: "T", family: .dx, bands: [.m20, .m40], modeClasses: modeClasses, allowedRawModes: allowedRawModes,
            tokenSets: tokenSets, sides: sides, exchange: exchange, multipliers: multipliers, points: points, dupe: dupe,
            pairing: pairing, sideRules: sideRules, bonuses: bonuses, scoreFactors: scoreFactors, operatingTime: operatingTime,
            cabrillo: CabrilloSpec(contest: "T", location: .state))
        try c.validate()
        return c
    }

    func keys(_ s: ScoreEngine.ScoreBreakdown, _ classID: String) -> Set<String> {
        Set(s.multiplierKeys.filter { $0.classID == classID }.map { "\($0.value)|\($0.scope)" })
    }

    // MARK: CQ WW (the fixture): points by relation, zone and country per band, /MM

    func testCQWWPointsFollowTheSponsorsFourCases() throws {
        let c = try cqww()
        // A US entrant: same country 0 (still a multiplier), another NA country 2, another continent 3.
        let us = ScoreEngine.score(log: log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("W1AW", rcvd: ["rst": "599", "zone": "5"]),
            row("VE3ABC", rcvd: ["rst": "599", "zone": "4"]),
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("PY1AA", band: .m40, rcvd: ["rst": "599", "zone": "11"]),
        ]), contest: c)
        XCTAssertEqual(us.validQSOs, 4)
        XCTAssertEqual(us.qsoPoints, 0 + 2 + 3 + 3)
        XCTAssertEqual(keys(us, "zone"), ["5|20m", "4|20m", "14|20m", "11|40m"])
        XCTAssertEqual(keys(us, "country"), ["K|20m", "VE|20m", "DL|20m", "PY|40m"], "the primary prefix names the country")
        XCTAssertEqual(us.multiplierCount, 8)
        XCTAssertEqual(us.total, 8 * 8)
        // A German entrant: same continent 1.
        let de = ScoreEngine.score(log: log(c, call: "DL1QPL", sent: ["rst": ["599"], "zone": ["14"]], rows: [
            row("DL2AA", rcvd: ["rst": "599", "zone": "14"]),
            row("F5ABC", rcvd: ["rst": "599", "zone": "14"]),
            row("W1AW", rcvd: ["rst": "599", "zone": "5"]),
        ]), contest: c)
        XCTAssertEqual(de.qsoPoints, 0 + 1 + 3)
        XCTAssertEqual(de.pointsByRowID.values.sorted(), [0, 1, 3])
    }

    func testMaritimeMobileCountsForAZoneOnly() throws {
        let c = try cqww()
        let s = ScoreEngine.score(log: log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("DL1AA/MM", rcvd: ["rst": "599", "zone": "33"]),
        ]), contest: c)
        XCTAssertEqual(keys(s, "zone"), ["33|20m"])
        XCTAssertEqual(keys(s, "country"), [], "unlessSuffix MM: no country for a maritime mobile")
        XCTAssertEqual(s.qsoPoints, 3)
    }

    func testDupesOncePerBandAndZoneLeadingZeroFolds() throws {
        let c = try cqww()
        let s = ScoreEngine.score(log: log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("DL1AA", band: .m40, rcvd: ["rst": "599", "zone": "014"]),
        ]), contest: c)
        XCTAssertEqual(s.validQSOs, 2); XCTAssertEqual(s.dupeCount, 1)
        XCTAssertEqual(keys(s, "zone"), ["14|20m", "14|40m"])
    }

    // MARK: Operating time

    func testRowsPastTheOperatingLimitAreLoggedButNotScored() throws {
        let c = try contest(operatingTime: OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30))
        let rows = [row("W1AW", minutes: 0), row("W2AA", minutes: 20), row("W3AA", minutes: 20), row("W4AA", minutes: 20),
                    row("W5AA", minutes: 1), row("W5AA", band: .m40, minutes: 1)]
        let s = ScoreEngine.score(log: log(c, rows: rows), contest: c)
        XCTAssertEqual(s.validQSOs, 4, "0, 20, 40, 60 minutes are within the hour")
        XCTAssertEqual(s.outOfTimeRowIDs, Set(rows.suffix(2).map(\.id)))
        XCTAssertEqual(s.outOfTimeCount, 2)
        XCTAssertEqual(s.dupeCount, 0, "an out-of-time row is not a dupe either — it is out of time")
        XCTAssertNil(s.pointsByRowID[rows[4].id])
        XCTAssertEqual(s.operatedMinutes, 60)
        // A 49-minute gap is off time (≥ 30): the clock does not run through it.
        let spaced = [row("W1AW", minutes: 0), row("W2AA", minutes: 50), row("W3AA", minutes: 50)]
        let sp = ScoreEngine.score(log: log(c, rows: spaced), contest: c)
        XCTAssertEqual(sp.validQSOs, 3); XCTAssertEqual(sp.offMinutes, 98); XCTAssertEqual(sp.operatedMinutes, 0)
        // A rule that applies to a category this log is not in does nothing.
        let classic = try contest(operatingTime: OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30, appliesTo: ["overlay": "CLASSIC"]))
        XCTAssertEqual(ScoreEngine.score(log: log(classic, rows: rows), contest: classic).validQSOs, 6)
    }

    // MARK: Modes, pairing, sides

    func testRawModesRefineAClass() throws {
        let c = try contest(modeClasses: [.digital], allowedRawModes: ["RTTY"])
        let s = ScoreEngine.score(log: log(c, rows: [row("W1AW", mode: .digital, raw: "RTTY"), row("W2AA", mode: .digital, raw: "FT8")]), contest: c)
        XCTAssertEqual(s.validQSOs, 1); XCTAssertEqual(s.invalidModeCount, 1)
    }

    func testPairingByCallsignSides() throws {
        // ARRL DX shape: W/VE (USA 291, Canada 1) work DX and vice versa.
        let wve = Side(id: "wve", label: "W/VE", predicate: SidePredicate(kind: .dxccIn, codes: [291, 1]),
                       workedPredicate: SidePredicate(kind: .dxccIn, codes: [291, 1]))
        let dx = Side(id: "dx", label: "DX", predicate: .always, workedPredicate: .always)
        let c = try contest(sides: [wve, dx],
                            exchange: [ExchangeElement(id: "rst", kind: .rst, sentBy: ["wve": .init(), "dx": .init()])],
                            points: [PointRule(points: 3)], pairing: ["wve": ["dx"], "dx": ["wve"]])
        let s = ScoreEngine.score(log: log(c, side: "wve", rows: [row("W1AW"), row("VE3ABC"), row("DL1AA"), row("KH6ABC")]), contest: c)
        XCTAssertEqual(s.validQSOs, 2, "DL and KH6 (Hawaii, its own entity) are DX; W1AW and VE3 are out of scope")
        XCTAssertEqual(s.outOfScopeCount, 2)
        XCTAssertEqual(s.qsoPoints, 6)
    }

    func testAnUndeclaredSideResolvesToTheOnlySide() throws {
        // A legacy NAQP log says `outside`; the lowered party has one side, `all`.
        let c = try lowered("naqpcw")
        var legacy = ContestLog(partyID: c.id, myLocation: .outOfState(location: "TX"), exchangeName: "TOM")
        legacy.station.callsign = "KE5CW"
        legacy.qsos = [QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "", rstRcvd: "",
                           nameSent: "TOM", nameRcvd: "BOB", myLoc: "TX", theirLoc: "CA")]
        XCTAssertEqual(legacy.sideID, "outside")
        var v2 = legacy; v2.sideID = "all"
        XCTAssertEqual(ScoreEngine.score(log: legacy, contest: c), ScoreEngine.score(log: v2, contest: c))
        XCTAssertEqual(ScoreEngine.score(log: legacy, contest: c).validQSOs, 1)
    }

    // MARK: Token ownership and the callsign override (the parties, through the model)

    func testTheCallsignDecidesAPrefixThatEqualsAStateCode() throws {
        let wa = try lowered("warun"), c = try XCTUnwrap(PartyCatalog.party(id: "warun")).counties[0].abbr
        func inLog(_ rows: [(String, String)]) -> ContestLog {
            var log = ContestLog(partyID: wa.id, myLocation: .inState(counties: [c]))
            log.station.callsign = "W7QPL"
            log.qsos = rows.map { call, their in
                seq += 1
                return QSO(timestampUTC: t0.addingTimeInterval(Double(seq) * 60), call: call, band: .m40, modeClass: .cw, rawMode: "CW",
                           rstSent: "599", rstRcvd: "599", myLoc: c, theirLoc: their)
            }
            return log
        }
        let dx = ScoreEngine.score(log: inLog([("PA0AAA", "PA"), ("OK1BBB", "OK"), ("LA1CCC", "LA"), ("ON4DDD", "ON"), ("DL1EEE", "DL")]), contest: wa)
        XCTAssertEqual(dx.workedValues(classID: "state"), [])
        XCTAssertEqual(dx.workedValues(classID: "province"), [])
        XCTAssertEqual(dx.workedValues(classID: "dx"), ["PA", "OK", "LA", "ON", "DL"])
        let home = ScoreEngine.score(log: inLog([("W3XYZ", "PA"), ("W5ABC", "OK"), ("W5DEF", "LA"), ("VE3GHI", "ON")]), contest: wa)
        XCTAssertEqual(home.workedValues(classID: "state"), ["PA", "OK", "LA"])
        XCTAssertEqual(home.workedValues(classID: "province"), ["ON"])
        XCTAssertEqual(home.workedValues(classID: "dx"), [])
        // The tie breaks only when the callsign names the very entity the token would.
        let near = ScoreEngine.score(log: inLog([("VE5ABC", "SK"), ("VE6DEF", "AB")]), contest: wa)
        XCTAssertEqual(near.workedValues(classID: "province"), ["SK", "AB"])
        XCTAssertEqual(near.workedValues(classID: "dx"), [])
        // A county is owned by the counties set whatever the callsign; the excluded home state credits nothing.
        let county = ScoreEngine.score(log: inLog([("PA0AAA", c), ("W7ABC", "WA")]), contest: wa)
        XCTAssertEqual(county.workedValues(classID: "county"), [c])
        XCTAssertEqual(county.workedValues(classID: "state"), [])
        XCTAssertEqual(county.multiplierCount, 1)
    }

    func testOneTokenOneClassAndAliasesFoldAtCountTime() throws {
        // ALQP: DC is credited as MD; a county credits county and (via group) the home state; a section party takes DX as a literal.
        let al = try lowered("alqp"), alCounties = try XCTUnwrap(PartyCatalog.party(id: "alqp")).counties.map(\.abbr)
        var log = ContestLog(partyID: al.id, myLocation: .inState(counties: [alCounties[0]]))
        log.station.callsign = "W4QPL"
        log.qsos = [row("W3DC", rcvd: ["rst": "599", "location": "DC"], sent: ["rst": "599", "location": alCounties[0]]),
                    row("W4AA", rcvd: ["rst": "599", "location": alCounties[1]], sent: ["rst": "599", "location": alCounties[0]])]
        let s = ScoreEngine.score(log: log, contest: al)
        XCTAssertEqual(s.workedValues(classID: "state"), ["MD", "AL"], "DC folds to MD; the county's group is AL")
        XCTAssertEqual(s.workedValues(classID: "county"), [alCounties[1]])
        let pa = try lowered("paqp"), paCounties = try XCTUnwrap(PartyCatalog.party(id: "paqp")).counties.map(\.abbr)
        var plog = ContestLog(partyID: pa.id, myLocation: .inState(counties: [paCounties[0]]))
        plog.station.callsign = "W3QPL"
        plog.qsos = [row("DL1AA", rcvd: ["serial": "1", "location": "DX"], sent: ["serial": "1", "location": paCounties[0]]),
                     row("K5TR", rcvd: ["serial": "2", "location": "TX"], sent: ["serial": "2", "location": paCounties[0]]),
                     row("W5ABC", rcvd: ["serial": "3", "location": "NTX"], sent: ["serial": "3", "location": paCounties[0]])]
        let ps = ScoreEngine.score(log: plog, contest: pa)
        XCTAssertEqual(ps.workedValues(classID: "dx"), ["DX"])
        XCTAssertEqual(ps.workedValues(classID: "section"), ["NTX", "EPA", "WPA"], "the granted sections ride along")
        XCTAssertEqual(ps.multiplierKeys.filter { $0.value == "EPA" }.first?.scope, "", "granted: once, unscoped")
        XCTAssertEqual(ps.validQSOs, 3, "TX is a valid QSO worth points and no multiplier in a section party")
    }

    // MARK: Caps, floors, member kinds, factors, declared bonuses

    func testDistinctValueCapAndFloor() throws {
        let wa = try lowered("warun"), c = try XCTUnwrap(PartyCatalog.party(id: "warun")).counties[0].abbr
        var log = ContestLog(partyID: wa.id, myLocation: .inState(counties: [c]))
        log.station.callsign = "W7QPL"
        let prefixes = ["DL", "G", "JA", "F", "I", "EA", "SM", "OZ", "HB", "LZ", "YU", "SP"]
        log.qsos = prefixes.enumerated().map { i, p in row("X\(i)", rcvd: ["rst": "599", "location": p], sent: ["rst": "599", "location": c]) }
        let s = ScoreEngine.score(log: log, contest: wa)
        XCTAssertEqual(s.validQSOs, 12)
        XCTAssertEqual(s.workedValues(classID: "dx").count, 10, "caps.inside = 10 distinct entities")
        let fobb = try lowered("fobb")
        var f = ContestLog(partyID: fobb.id, myLocation: .outOfState(location: "TX"), exchangeMember: "5W")
        f.station.callsign = "KE5CW"
        f.qsos = [row("W1AW", rcvd: ["rst": "599", "location": "CT", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "5W"])]
        let fs = ScoreEngine.score(log: f, contest: fobb)
        XCTAssertEqual(fs.multiplierFloor, 1); XCTAssertEqual(fs.multiplierCount, 1); XCTAssertEqual(fs.total, fs.qsoPoints)
    }

    func testMemberKindsDecidePointsAndCounts() throws {
        let sk = try lowered("skeeter"), p = try XCTUnwrap(PartyCatalog.party(id: "skeeter")), m = try XCTUnwrap(p.memberExchange)
        var log = ContestLog(partyID: sk.id, myLocation: .outOfState(location: "TX"), exchangeMember: "13")
        log.station.callsign = "KE5CW"
        log.qsos = [row("W2LJ", rcvd: ["rst": "599", "location": "NJ", "member": "1"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                    row("K3WWP", rcvd: ["rst": "599", "location": "PA", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                    row("VE3ABC", rcvd: ["rst": "599", "location": "ON"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                    row("K1ABC", mode: .phone, rcvd: ["rst": "59", "location": "CT", "member": "8W"], sent: ["rst": "59", "location": "TX", "member": "13"])]
        let s = ScoreEngine.score(log: log, contest: sk)
        XCTAssertEqual(s.memberQSOs, 1)
        XCTAssertEqual(s.qrpQSOs, 2, "8 W on phone is QRP (10 W ceiling)")
        XCTAssertEqual(s.otherQSOs, 1, "a blank element is QRO")
        XCTAssertEqual(s.qsoPoints, m.memberPoints + 2 * m.qrpPoints + m.otherPoints)
    }

    func testFactorsObjectivesEntryClassAndDeclaredBonuses() throws {
        let f = ScoreFactors(power: ["QRP": ScoreFactor(2)], station: ["PORTABLE": ScoreFactor(3)],
                             entryClasses: [.init(id: "X1", label: "One", factor: .one), .init(id: "X2", label: "Two", factor: ScoreFactor(2))],
                             objectives: [.init(id: "1o", label: "a", om: 1), .init(id: "2o", label: "b", om: 2)],
                             declaredBonuses: [.init(id: "emergency", label: "Emergency power", points: 100, perCount: .init(label: "transmitters", max: 20)),
                                               .init(id: "media", label: "Media publicity", points: 100, perCount: nil)])
        let c = try contest(scoreFactors: f)
        let s = ScoreEngine.score(log: log(c, rows: [row("W1AW")]) { log in
            log.station.categoryPower = .qrp; log.station.categoryStation = .portable
            log.entryClassID = "X2"; log.selectedObjectives = ["1o", "2o", "nope"]
            log.declaredBonuses = ["emergency": 25, "media": 1, "unknown": 4]
        }, contest: c)
        XCTAssertEqual(s.categoryFactor, ScoreFactor(2 * 3 * 2 * (1 + 3)))
        XCTAssertEqual(s.bonusPoints, 100 * 20 + 100)
        XCTAssertEqual(s.total, s.categoryFactor.applied(to: s.qsoPoints * s.multiplierCount) + s.bonusPoints)
        let none = ScoreEngine.score(log: log(c, rows: [row("W1AW")]), contest: c)
        XCTAssertEqual(none.categoryFactor, .one, "a log that never chose takes the first (lowest) class")
    }

    // MARK: Bonuses and activated multipliers through the lowered parties

    func testActivatedMultiplierIsForfeitedWhereTheCountyIsAlsoWorked() throws {
        let tn = try lowered("tnqp"), p = try XCTUnwrap(PartyCatalog.party(id: "tnqp"))
        let act = try XCTUnwrap(p.multipliers.inState.activatedCountyMultiplier), c = p.counties.map(\.abbr)
        func mobile(_ rows: [QSO]) -> ContestLog {
            var log = ContestLog(partyID: tn.id, myLocation: .inState(counties: [c[0]]))
            log.station.callsign = "W4QPL"; log.station.categoryStation = .mobile
            log.qsos = rows
            return log
        }
        let enough = (0..<act.minCount).map { i in row("W\(i)AA", rcvd: ["rst": "599", "location": "TX"], sent: ["rst": "599", "location": c[0]]) }
        let s = ScoreEngine.score(log: mobile(enough), contest: tn)
        XCTAssertEqual(s.selfActivatedCounties, [c[0]])
        XCTAssertTrue(s.multiplierKeys.contains(ScoreEngine.MultKey(classID: "county", value: c[0], scope: "", activated: true)))
        let worked = ScoreEngine.score(log: mobile(enough + [row("W4XYZ", rcvd: ["rst": "599", "location": c[0]], sent: ["rst": "599", "location": c[0]])]), contest: tn)
        XCTAssertEqual(worked.selfActivatedCounties, [], "TnQP: not if the county is earned otherwise")
        XCTAssertEqual(ScoreEngine.score(log: mobile(Array(enough.dropLast())), contest: tn).selfActivatedCounties, [], "one short of the threshold")
    }

    func testWorkStationAndSweepBonuses() throws {
        let vt = try lowered("vtqp"), c = try XCTUnwrap(PartyCatalog.party(id: "vtqp")).counties.map(\.abbr)
        var log = ContestLog(partyID: vt.id, myLocation: .outOfState(location: "TX"))
        log.station.callsign = "KE5CW"
        log.qsos = [row("W1AW/1", rcvd: ["rst": "599", "location": c[0]], sent: ["rst": "599", "location": "TX"]),
                    row("W1AW/1", band: .m40, rcvd: ["rst": "599", "location": c[0]], sent: ["rst": "599", "location": "TX"])]
        XCTAssertEqual(ScoreEngine.score(log: log, contest: vt).bonusPoints, 4, "2 per QSO")
        let md = try lowered("mdc"), mdp = try XCTUnwrap(PartyCatalog.party(id: "mdc")), mc = mdp.counties.map(\.abbr)
        guard case .sweepTiers(let tiers)? = mdp.bonuses.first(where: { if case .sweepTiers = $0 { return true } else { return false } }),
              let lowest = tiers.min(by: { $0.count < $1.count }) else { return XCTFail("MDC has sweep tiers") }
        var mlog = ContestLog(partyID: md.id, myLocation: .outOfState(location: "TX"))
        mlog.station.callsign = "KE5CW"
        mlog.qsos = (0..<lowest.count).map { i in row("W3X\(i)", rcvd: ["rst": "599", "location": mc[i]], sent: ["rst": "599", "location": "TX"]) }
        XCTAssertEqual(ScoreEngine.score(log: mlog, contest: md).bonusPoints, lowest.points)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: the `ContestScoreEngineTests` class. Expected: build errors (`score(log:contest:)`, `classID`, `workedValues(classID:)`, `outOfTimeRowIDs`…).

- [ ] **Step 3: `MultKey`, `ScoreBreakdown` and two visibility changes in `ScoreEngine.swift`**

Replace the `MultKey` struct with:

```swift
    /// One counted multiplier. `scope` is "" (once), a mode raw value
    /// (perMode), a band raw value (perBand), or "band/mode" (perBandMode).
    struct MultKey: Hashable, Sendable {
        /// The multiplier class — `MultiplierClass.id`. The six party classes
        /// keep `MultClass`'s raw values (`county`, `state`, `province`, `dx`,
        /// `section`, `member`), so persisted snapshots and sidebar keys read
        /// unchanged; a general contest adds `zone`, `country`, `prefix`…
        let classID: String
        let value: String
        let scope: String
        /// Earned by **operating from** the token rather than by working it
        /// (`SideRules.activated`). Defaults false, so every key built before
        /// this existed is unchanged.
        ///
        /// It is part of the key because SCQP 9.2.2 lists "Each South Carolina
        /// county" and "Each SC county activated" as separate numbered
        /// multipliers with no ceiling, so the two must be able to coexist at
        /// the same scope. Where a sponsor forfeits one for the other,
        /// `notOtherwiseWorked` suppresses the activated key instead.
        let activated: Bool

        init(classID: String, value: String, scope: String, activated: Bool = false) {
            self.classID = classID
            self.value = value
            self.scope = scope
            self.activated = activated
        }

        /// The party classes, by enum.
        init(multClass: MultClass, value: String, scope: String, activated: Bool = false) {
            self.init(classID: multClass.rawValue, value: value, scope: scope, activated: activated)
        }

        /// The class as a `MultClass`, for the party-shaped readers (sidebar,
        /// roster); nil for a class the parties do not have.
        var multClass: MultClass? { MultClass(rawValue: classID) }
    }
```
In `ScoreBreakdown`, add after `pointsByRowID`:
```swift
        /// Rows past the contest's operating-time limit — logged and exported,
        /// unscored (SS 1.2, WPX FAQ). Empty for every contest without a rule.
        var outOfTimeRowIDs: Set<UUID> = []
        var outOfTimeCount: Int { outOfTimeRowIDs.count }
        /// Operating and credited off minutes under the contest's rule; 0 without one.
        var operatedMinutes = 0
        var offMinutes = 0
```
Replace `workedValues(_:)` and `classCounts` with:
```swift
        /// Unique values worked for a class, regardless of scope — for the
        /// sidebar county grid and per-class chips.
        func workedValues(_ multClass: MultClass) -> Set<String> {
            workedValues(classID: multClass.rawValue)
        }

        func workedValues(classID: String) -> Set<String> {
            Set(multiplierKeys.filter { $0.classID == classID }.map(\.value))
        }

        /// Per-class scoped counts for the party classes, for the sidebar breakdown.
        var classCounts: [MultClass: Int] {
            var out: [MultClass: Int] = [:]
            for key in multiplierKeys { if let c = key.multClass { out[c, default: 0] += 1 } }
            return out
        }

        /// Per-class scoped counts by class id — every class, party or not.
        var countsByClassID: [String: Int] {
            Dictionary(grouping: multiplierKeys, by: \.classID).mapValues(\.count)
        }
```
Change `private static func isRovingCategory` → `static func isRovingCategory` and `private static func designatedCounties` → `static func designatedCounties` (the new file needs both). Replace `countyGains` with the general form plus its county wrapper:
```swift
    /// Would working `value` of `classID` at `scope` raise this log's
    /// multiplier total? Only asked where the entrant's rule forfeits the
    /// activation multiplier on a worked token — everywhere else a key that
    /// is absent is a gain.
    static func gains(classID: String, value: String, addingScope scope: String, to current: Set<MultKey>) -> Bool {
        let keys = current.filter { $0.classID == classID && $0.value == value }
        let worked = Set(keys.filter { !$0.activated }.map(\.scope))
        let activated = keys.filter(\.activated).count
        let before = worked.count + activated
        let after = worked.union([scope]).count      // the forfeited activation goes to zero
        return after > before
    }

    /// `gains` for the county class — what `NeededMult` asks.
    static func countyGains(_ county: String, addingScope scope: String, to current: Set<MultKey>) -> Bool {
        gains(classID: MultClass.county.rawValue, value: county, addingScope: scope, to: current)
    }
```
Everything else in the file — the old `score(log:party:)` and its helpers — stays byte-for-byte (`$0.multClass == .dx` still compiles against the optional). Build now: `xcodebuild … build 2>&1 | grep -E "error:|BUILD"` — expected `BUILD SUCCEEDED`.

- [ ] **Step 4: Create `Sources/Core/Engine/ScoreEngine+Contest.swift`**

```swift
import Foundation

/// The scoring engine on the general model (spec §1.4): fold a log against a
/// `ContestDefinition`. `score(log:party:)` and the other `PartyDefinition`
/// overloads in `ScoreEngine.swift` lower first and come here.
///
/// Every row lands in exactly one bucket, in this order of precedence:
/// invalid mode → out of scope (pairing) → out of time → dupe → valid. Only
/// valid rows earn points and multipliers.
extension ScoreEngine {

    // MARK: Classification

    struct Classified {
        /// The entrant's side, resolved against the contest.
        let side: String
        /// Allowed-mode, in-scope rows, chronological — what operating time is measured over.
        let contestRows: [QSO]
        /// `contestRows` less the out-of-time rows — what dupes, points and multipliers are computed over.
        let scoredRows: [QSO]
        let firstIDs: Set<UUID>
        let invalidRowIDs: Set<UUID>
        let outOfScopeRowIDs: Set<UUID>
        let operatingTime: OperatingTime.Result

        /// The rows that count: first occurrences among the scored rows.
        var validRows: [QSO] { scoredRows.filter { firstIDs.contains($0.id) } }
    }

    static func classify(log: ContestLog, contest: ContestDefinition) -> Classified {
        let rows = log.qsos.sortedChronologically()
        let side = contest.resolvedSideID(log.sideID)
        // Invalid-mode rows are not contest QSOs at all (WA: "we cannot
        // accept" digital) — they never enter dupe/point/mult accounting.
        let allowedModes = Set(contest.modeClasses)
        let rawModes = contest.allowedRawModes.map { Set($0.map { $0.uppercased() }) }
        let inAllowedMode = rows.filter {
            allowedModes.contains($0.modeClass) && (rawModes?.contains($0.rawMode.uppercased()) ?? true)
        }
        let invalid = Set(rows.map(\.id)).subtracting(inAllowedMode.map(\.id))
        // Neither are contacts the rules give this entrant no credit for (MDC
        // 10b: non-MDC stations may only work MD/DC) — rows whose worked side
        // is not one this side is paired with.
        let workable = Set(contest.workableSides(for: side))
        let contestRows = inAllowedMode.filter { row in
            workedSideID(of: row, contest: contest).map(workable.contains) ?? false
        }
        let outOfScope = Set(inAllowedMode.map(\.id)).subtracting(contestRows.map(\.id))
        // Rows past the operating-time limit are logged and exported but earn
        // nothing (SS 1.2, WPX FAQ). Measured over every contest row, dupes
        // included — a dupe is still time on the air.
        var operatingTime = OperatingTime.Result.zero
        var scored = contestRows
        if let rule = contest.operatingTime, rule.applies(to: log.categoryValues) {
            operatingTime = OperatingTime.compute(rows: contestRows, rule: rule)
            scored = contestRows.filter { !operatingTime.outOfTimeRowIDs.contains($0.id) }
        }
        return Classified(
            side: side, contestRows: contestRows, scoredRows: scored,
            firstIDs: DupeChecker.firstOccurrenceIDs(scored, rule: contest.dupe),
            invalidRowIDs: invalid, outOfScopeRowIDs: outOfScope, operatingTime: operatingTime
        )
    }

    /// The first side whose `workedPredicate` accepts the row's received
    /// exchange and callsign; nil when none does (a callsign no side claims).
    static func workedSideID(of row: QSO, contest: ContestDefinition) -> String? {
        let needsGeo = contest.sides.contains {
            $0.workedPredicate.kind == .dxccIn || $0.workedPredicate.kind == .continentIn
        }
        let geo = needsGeo ? CTYTable.shared?.match(callsign: row.call) : nil
        let ctx = SidePredicate.Context(
            exchange: row.rcvd.mapValues { [$0] },
            entityCode: geo?.entity.entityCode, continent: geo?.continent,
            sets: { contest.tokenSet(id: $0) }
        )
        return contest.sides.first { $0.workedPredicate.matches(ctx) }?.id
    }

    // MARK: Score

    static func score(log: ContestLog, contest: ContestDefinition) -> ScoreBreakdown {
        var result = ScoreBreakdown()
        let c = classify(log: log, contest: contest)
        result.invalidRowIDs = c.invalidRowIDs
        result.invalidModeCount = c.invalidRowIDs.count
        result.outOfScopeRowIDs = c.outOfScopeRowIDs
        result.outOfScopeCount = c.outOfScopeRowIDs.count
        result.outOfTimeRowIDs = c.operatingTime.outOfTimeRowIDs
        result.operatedMinutes = c.operatingTime.operatedMinutes
        result.offMinutes = c.operatingTime.offMinutes

        let side = c.side
        let sideRules = contest.rules(for: side)
        result.multiplierCap = sideRules.maxScoredMultipliers
        result.multiplierFloor = sideRules.multiplierFloor
        let classes = contest.multipliers.filter { $0.counting[side] != nil }

        // Multipliers the contest hands over without them being worked (PAQP's
        // EPA and WPA). Scoped once, since the sponsor adds them to the tally
        // rather than to a QSO. Only for a class this side counts.
        var distinctValues: [String: Set<String>] = [:]
        for granted in sideRules.granted where classes.contains(where: { $0.id == granted.classID }) {
            result.multiplierKeys.insert(MultKey(classID: granted.classID, value: granted.value, scope: ""))
            distinctValues[granted.classID, default: []].insert(granted.value)
        }

        let memberElement = contest.exchange.first { $0.kind == .memberOrPower }
        let geoNeeded = contest.points.contains { $0.when.contains { $0.relation != nil || $0.bothInContinent != nil } }
        let myGeo = geoNeeded ? CTYTable.shared?.match(callsign: log.station.callsign) : nil

        for row in c.scoredRows {
            guard c.firstIDs.contains(row.id) else {
                result.dupeCount += 1
                result.dupeRowIDs.insert(row.id)
                continue
            }
            result.validQSOs += 1
            let kind = workedStationKind(row: row, memberElement: memberElement)
            switch kind {
            case "member": result.memberQSOs += 1
            case "qrp": result.qrpQSOs += 1
            case "other": result.otherQSOs += 1
            default: break
            }
            let points = PointRule.points(contest.points, pointsContext(
                row: row, side: side, contest: contest, workedStationKind: kind, myGeo: myGeo, geoNeeded: geoNeeded))
            result.qsoPoints += points
            result.pointsByRowID[row.id] = points

            for (cls, value) in multiplierValues(rcvd: row.rcvd, call: row.call, side: side, classes: classes, contest: contest) {
                guard let scope = cls.counting[side] else { continue }
                // A per-side cap on distinct values (WA in-state: 10 DX): a
                // value already held may still add a new scope key; a new
                // value past the cap does not.
                if let cap = cls.cap(for: side), let seen = distinctValues[cls.id], seen.count >= cap, !seen.contains(value) {
                    continue
                }
                let key = MultKey(classID: cls.id, value: value, scope: scope.component(band: row.band, modeClass: row.modeClass))
                if result.multiplierKeys.insert(key).inserted {
                    result.newMultRowIDs.insert(row.id)
                    distinctValues[cls.id, default: []].insert(value)
                }
            }
        }

        result.categoryFactor = categoryFactor(contest: contest, log: log)
        result.bonusPoints = bonusPoints(valid: c.validRows, log: log, contest: contest, breakdown: result)
            + declaredBonusPoints(contest: contest, log: log)
        // Deliberately last: after the worked loop, so a forfeiting rule can
        // see which tokens were worked; after the bonuses, so `sweepTiers`
        // keeps counting tokens **worked** rather than one the operator sat in.
        addActivatedMultipliers(to: &result, valid: c.validRows, log: log, contest: contest, side: side)
        return result
    }

    // MARK: Points

    /// `member` / `qrp` / `other` from the received member-or-power element,
    /// or nil where the contest has no such element. A blank element is a QRO
    /// station, not a gap (`MemberExchange.workedClass`).
    static func workedStationKind(row: QSO, memberElement: ExchangeElement?) -> String? {
        guard let element = memberElement, let spec = element.member else { return nil }
        guard let raw = row.rcvd[element.id], let value = MemberExchange.parse(raw) else { return "other" }
        switch value {
        case .member: return "member"
        case .power(let watts): return watts <= spec.qrpMaxWatts.limit(for: row.modeClass) ? "qrp" : "other"
        }
    }

    static func pointsContext(row: QSO, side: String, contest: ContestDefinition, workedStationKind: String?,
                              myGeo: CTYTable.Match?, geoNeeded: Bool) -> PointCondition.Context {
        var relation: PointCondition.Relation?
        var shared: String?
        if geoNeeded, let mine = myGeo, let theirs = CTYTable.shared?.match(callsign: row.call) {
            // The same cty record is the same country (CQ WW's 0-point rule);
            // the continent columns decide the rest.
            if mine.entity.primaryPrefix == theirs.entity.primaryPrefix { relation = .sameEntity }
            else if mine.continent == theirs.continent { relation = .sameContinent }
            else { relation = .differentContinent }
            if mine.continent == theirs.continent { shared = mine.continent }
        }
        return PointCondition.Context(
            modeClass: row.modeClass, band: row.band, relation: relation, sharedContinent: shared,
            side: side, workedSide: workedSideID(of: row, contest: contest) ?? "",
            received: row.rcvd.mapValues { $0.uppercased() }, workedStationKind: workedStationKind,
            call: row.call, sets: { contest.tokenSet(id: $0) }
        )
    }

    // MARK: Multipliers

    private static let dxTokenSet = "dxToken"
    private static let dxccPrefixSet = "dxccPrefix"

    /// Every (class, value) a row contributes for an entrant on `side`: for
    /// each class the side counts, the first resolver — in order, among those
    /// that apply to the side and callsign — that yields a value.
    static func multiplierValues(rcvd: [String: String], call: String, side: String,
                                 classes: [MultiplierClass], contest: ContestDefinition) -> [(MultiplierClass, String)] {
        let owners = tokenOwners(rcvd: rcvd, call: call, side: side, classes: classes, contest: contest)
        var out: [(MultiplierClass, String)] = []
        for cls in classes {
            for r in cls.resolvers where r.applies(side: side, call: call) {
                if let value = resolve(r, rcvd: rcvd, call: call, owners: owners, contest: contest) {
                    out.append((cls, value))
                    break
                }
            }
        }
        return out
    }

    /// Element id → the set that owns the row's received token, for every
    /// token element the side receives: `ExchangeValidator.owningSet` — the
    /// classification validation itself uses — plus the callsign override.
    static func tokenOwners(rcvd: [String: String], call: String, side: String,
                            classes: [MultiplierClass], contest: ContestDefinition) -> [String: String] {
        var owners: [String: String] = [:]
        for element in contest.receivedElements(for: side) where element.kind == .token {
            guard let raw = rcvd[element.id],
                  var owner = ExchangeValidator.owningSet(of: raw, element: element, contest: contest, side: side)
            else { continue }
            // A token that is BOTH an enumerated set's token and a real DXCC
            // prefix — PA is Pennsylvania and the Netherlands, ON is Ontario
            // and Belgium — is decided by the worked callsign where a class
            // counting entities says so (`callsignOverrides`), and only when
            // the call names the very same entity the token would: PA0AAA
            // sending "PA" is the Netherlands, W3XYZ sending it is
            // Pennsylvania, and a VE5 sending "SK" stays Saskatchewan even
            // though SK is Sweden's. A US or Canadian callsign never triggers
            // it (the ARRL US row is "K, W, N, AA-AK", so Alberta's "AB" falls
            // inside it). N1MM's split: the exchange says which location was
            // sent, the callsign which entity sent it.
            let overrides = classes.flatMap { cls in
                cls.resolvers
                    .filter { $0.kind == .dxccEntity && $0.element == element.id && $0.applies(side: side, call: call) }
                    .flatMap { $0.callsignOverrides ?? [] }
            }
            if overrides.contains(owner),
               let prefixEntity = DXCCTable.shared.entity(forPrefix: raw),
               !DXCCTable.shared.isDomestic(callsign: call),
               DXCCTable.shared.entity(forCallsign: call)?.code == prefixEntity.code {
                owner = dxccPrefixSet
            }
            owners[element.id] = owner
        }
        return owners
    }

    /// The value one resolver yields for a row, or nil.
    static func resolve(_ r: Resolver, rcvd: [String: String], call: String,
                        owners: [String: String], contest: ContestDefinition) -> String? {
        switch r.kind {
        case .receivedToken:
            // Fires only when the token belongs to this resolver's set; the
            // value is the set's canonical token (aliases fold here, not in
            // the log), or the token's group where `mapTo: "group"` (a
            // county's state).
            guard let element = r.element, let setID = r.set, let raw = rcvd[element], owners[element] == setID,
                  let set = contest.tokenSet(id: setID), let canonical = set.canonical(raw) else { return nil }
            return r.mapTo == "group" ? set.token(for: canonical)?.group : canonical
        case .dxccEntity:
            switch r.from {
            case .callsign:
                return entityValue(callsign: call, resolver: r)
            case .receivedToken:
                // The received token read as a prefix; a token the roster does
                // not know is credited as itself.
                guard let element = r.element, let raw = rcvd[element] else { return nil }
                guard r.countEntities, let m = DXCCTable.shared.match(prefix: raw) else { return raw.uppercased() }
                return m.label
            case .receivedTokenOrCallsign:
                // The parties: the literal `DX` names the country by the
                // callsign; a prefix names it itself, and the sponsor's own
                // received datum outranks a prefix match on the call. Where the
                // class does not tell entities apart, `DX` is one multiplier
                // and a prefix token is credited as typed.
                guard let element = r.element, let raw = rcvd[element] else { return nil }
                switch owners[element] {
                case dxTokenSet:
                    guard r.countEntities, let m = DXCCTable.shared.match(callsign: call) else { return MultClass.dxToken }
                    return m.label
                case dxccPrefixSet:
                    guard r.countEntities, let m = DXCCTable.shared.match(prefix: raw) else { return raw.uppercased() }
                    return m.label
                default:
                    return nil
                }
            case .received, nil:
                return nil
            }
        case .cqZone, .ituZone:
            guard let element = r.element, let raw = rcvd[element] else { return nil }
            return (r.kind == .cqZone ? TokenSet.cqZones : TokenSet.ituZones).canonical(raw)
        case .wpxPrefix:
            return WPXPrefix.of(call)
        case .grid:
            guard let element = r.element, let raw = rcvd[element] else { return nil }
            let grid = raw.uppercased()
            return r.precision.map { String(grid.prefix($0)) } ?? grid
        case .workedStation:
            // FOBB: the worked call is the multiplier when the received member
            // element parses as a member number; a power or a blank is not a
            // member. The empty-call guard keeps a locations-only caller (the
            // band map) from minting a valueless key.
            guard !call.isEmpty, let element = r.element, let raw = rcvd[element],
                  case .member = MemberExchange.parse(raw) else { return nil }
            return call.uppercased()
        }
    }

    /// The entity of the worked callsign as a multiplier value: its primary
    /// prefix (`DL` for every German call) where the class tells entities
    /// apart, else the literal `DX`; nil for a call no list resolves or an
    /// excluded entity. `arrl` reads the ARRL roster (`DXCCTable`);
    /// `arrlPlusWAE` reads cty (`CTYTable`), whose WAE-only records count as
    /// their own multipliers (CQ WW).
    static func entityValue(callsign call: String, resolver r: Resolver) -> String? {
        switch r.list ?? .arrl {
        case .arrl:
            guard let m = DXCCTable.shared.match(callsign: call) else { return nil }
            if let code = Int(m.entity.code), r.exclude.contains(code) { return nil }
            return r.countEntities ? m.label : MultClass.dxToken
        case .arrlPlusWAE:
            guard let m = CTYTable.shared?.match(callsign: call) else { return nil }
            if let code = m.entity.entityCode, r.exclude.contains(code), !m.entity.waeOnly { return nil }
            return r.countEntities ? m.entity.primaryPrefix : MultClass.dxToken
        }
    }

    // MARK: Factors and bonuses

    /// power × station × entry class × (1 + Σ selected objectives), exact.
    static func categoryFactor(contest: ContestDefinition, log: ContestLog) -> ScoreFactor {
        guard let f = contest.scoreFactors else { return .one }
        var factor = (f.power?[log.station.categoryPower.rawValue] ?? .one)
            * (f.station?[log.station.categoryStation.rawValue] ?? .one)
        // The match, or the **first** listed class where the id is empty or
        // stale — parties list classes lowest-factor first, and a log that
        // never chose must not claim a multiplier the operator did not.
        if let cls = f.entryClasses.first(where: { $0.id == log.entryClassID }) ?? f.entryClasses.first {
            factor = factor * cls.factor
        }
        let om = f.objectives.filter { log.selectedObjectives.contains($0.id) }.reduce(0) { $0 + $1.om }
        if om > 0 { factor = factor * ScoreFactor(1 + om) }
        return factor
    }

    /// Field Day's checklist: `points × min(count, max)` per claimed bonus,
    /// added after the multiplier and never scaled.
    static func declaredBonusPoints(contest: ContestDefinition, log: ContestLog) -> Int {
        (contest.scoreFactors?.declaredBonuses ?? []).reduce(0) { total, bonus in
            let count = log.declaredBonuses[bonus.id] ?? 0
            guard count > 0 else { return total }
            return total + (bonus.perCount.map { bonus.points * min(count, $0.max) } ?? bonus.points)
        }
    }

    /// The party bonus rules on the model. The county-keyed cases read the
    /// `location` element and the `county` class's roster (spec §1.2).
    static func bonusPoints(valid: [QSO], log: ContestLog, contest: ContestDefinition, breakdown: ScoreBreakdown) -> Int {
        let counties = contest.countyRoster()?.abbrs ?? []
        func isCounty(_ token: String) -> Bool { counties.contains(token.uppercased()) }
        var total = 0
        for bonus in contest.bonuses {
            switch bonus {
            case .workStation(let call, let points, let scope):
                let matches = valid.filter { $0.call.uppercased() == call.uppercased() }
                guard !matches.isEmpty else { break }
                switch scope {
                case .once: total += points
                case .perMode: total += Set(matches.map(\.modeClass)).count * points
                case .perBandMode: total += Set(matches.map { "\($0.band.rawValue)/\($0.modeClass.rawValue)" }).count * points
                case .perQSO: total += matches.count * points
                }
            case .mobileCountyCount(let per, let points):
                // One contact per county per station; every `per` distinct
                // counties a (mobile) station is worked in earns the bonus.
                var countiesByCall: [String: Set<String>] = [:]
                for row in valid where isCounty(row.theirLoc) {
                    countiesByCall[row.call.uppercased(), default: []].insert(row.theirLoc.uppercased())
                }
                for (_, worked) in countiesByCall { total += (worked.count / per) * points }
            case .activatedCountyCount(let minQSOs, let points):
                // My own activation bonus: mobile/rover/portable earning per
                // county operated from with ≥ minQSOs valid QSOs made from it.
                // Only a county-valued sent location qualifies, so an entrant
                // sending a state earns nothing here.
                guard isRovingCategory(log.station.categoryStation) else { break }
                for (county, rows) in Dictionary(grouping: valid, by: { $0.myLoc.uppercased() })
                where isCounty(county) && rows.count >= minQSOs {
                    total += points
                }
            case .sweepTiers(let tiers):
                let worked = breakdown.workedValues(classID: MultClass.county.rawValue).count
                if let best = tiers.filter({ worked >= $0.count }).max(by: { $0.count < $1.count }) { total += best.points }
            case .designatedCountySweep(let designated, let need, let points):
                // "If at least one QSO is made with a station in five of the
                // 'Rarest of NC' counties, 500 additional bonus points" — once,
                // at the threshold or past it.
                if designatedCounties(designated, workedIn: valid).count >= need { total += points }
            case .callAreaSum(let target, let points):
                // Skeeter Hunt Blackjack: each DISTINCT worked callsign
                // contributes its call-area digit once, 0 counts as 10, and
                // the bonus pays once when any subset lands on the target.
                let values = Set(valid.map { $0.call.uppercased() }).compactMap(callAreaValue)
                if subsetSumsExactly(values, target: target) { total += points }
            }
        }
        return total
    }

    // MARK: Activated multipliers

    /// The multiplier a side gives an entrant for each roster token they
    /// **operate from** (`SideRules.activated`) — five parties, no two alike.
    static func addActivatedMultipliers(to result: inout ScoreBreakdown, valid: [QSO], log: ContestLog,
                                        contest: ContestDefinition, side: String) {
        guard let act = contest.rules(for: side).activated,
              act.categories.contains(log.station.categoryStation),
              let cls = contest.multipliers.first(where: { $0.id == act.classID }),
              cls.counting[side] != nil,
              let rosterID = cls.roster, let roster = contest.tokenSet(id: rosterID)
        else { return }
        // The sent element the class reads — a party's `location`.
        let element = cls.resolvers.first { $0.kind == .receivedToken }?.element ?? ExchangeElementID.location
        for (token, rows) in Dictionary(grouping: valid, by: { ($0.sent[element] ?? "").uppercased() })
        where roster.abbrs.contains(token) {
            // The threshold reads all of that token's valid rows, not one
            // scope's worth: every sponsor words it that way ("50 or more
            // valid contacts from a county").
            let count = switch act.countUnit {
            case .qsos: rows.count
            case .stations: Set(rows.map { $0.call.uppercased() }).count
            }
            guard count >= act.minCount else { continue }
            // "…if they do not earn a multiplier for that county otherwise"
            // (TnQP) / "if not otherwise worked" (VAQP) — checked at **any**
            // scope, which set semantics alone cannot handle.
            if act.notOtherwiseWorked, worked(classID: cls.id, value: token, in: result) { continue }
            // One key per scope component present among that token's own rows,
            // which collapses to a single key under `once` and gives SCQP the
            // "ONCE PER MODE PER BAND" it asks for.
            for scope in Set(rows.map { act.countScope.component(band: $0.band, modeClass: $0.modeClass) }) {
                let key = MultKey(classID: cls.id, value: token, scope: scope, activated: true)
                if result.multiplierKeys.insert(key).inserted { result.selfActivatedCounties.insert(token) }
            }
        }
    }

    /// Was this value earned by working somebody, at any scope?
    static func worked(classID: String, value: String, in result: ScoreBreakdown) -> Bool {
        result.multiplierKeys.contains { !$0.activated && $0.classID == classID && $0.value == value }
    }
}
```

- [ ] **Step 5: Build, run the class, then the full suite**

Run: build; `ContestScoreEngineTests`; full suite. Expected: the class passes; full suite `Executed 3015 tests, with 0 failures` (3000 + 15) — nothing else changed behaviour (the old engine is untouched, `MultKey`'s bridge init keeps every existing key equal). If a test in this class fails on a **cty/DXCC fact** (a call resolving to an unexpected entity or continent), check `Resources/CTY/cty.csv` and `Resources/DXCC/dxcc_entities.json` for that prefix before changing the engine — the tables are the authority.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Engine/ScoreEngine.swift Sources/Core/Engine/ScoreEngine+Contest.swift Tests/Core/ContestScoreEngineTests.swift QSOPartyLogger.xcodeproj
git commit -m "engine: ScoreEngine.score(log:contest:) — the general engine on ContestDefinition (sides, pairing, token ownership with the callsign override, resolvers, points context, caps, granted, factors, bonuses, activated, operating time); MultKey.classID

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: The derived queries on the model — `wouldAddMultiplier(received:…)`, `bandModeCounts`, `designatedCountiesWorked`, `callAreaSumAchieved`

**Files:**
- Modify: `Sources/Core/Engine/ScoreEngine+Contest.swift` (append), `Tests/Core/ContestScoreEngineTests.swift` (append)

- [ ] **Step 1: Write the failing tests** — append inside the class:

```swift
    // MARK: Derived queries

    func testWouldAddMultiplierOnTheModel() throws {
        let c = try cqww()
        let held = log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [row("DL1AA", rcvd: ["rst": "599", "zone": "14"])])
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "DL2BB", band: .m20, modeClass: .cw, log: held, contest: c),
                       "zone 14 and DL are both held on 20 m")
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "DL2BB", band: .m40, modeClass: .cw, log: held, contest: c),
                      "per band: 40 m is new")
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "F5ABC", band: .m20, modeClass: .cw, log: held, contest: c),
                      "a new country on a held zone")
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["rst": "599", "zone": "14"]], call: "F5ABC", band: .m20, modeClass: .phone, log: held, contest: c),
                       "a mode the contest does not run")
        // A county line: any of the received values may be the new one.
        let ks = try lowered("ksqp"), kc = try XCTUnwrap(PartyCatalog.party(id: "ksqp")).counties.map(\.abbr)
        var klog = ContestLog(partyID: ks.id, myLocation: .outOfState(location: "TX"))
        klog.station.callsign = "KE5CW"
        klog.qsos = [row("W0BH", rcvd: ["rst": "599", "location": kc[0]], sent: ["rst": "599", "location": "TX"])]
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["location": kc[0]], ["location": kc[1]]], call: "N0XYZ", band: .m20, modeClass: .cw, log: klog, contest: ks))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["location": kc[0]]], call: "N0XYZ", band: .m20, modeClass: .cw, log: klog, contest: ks))
        // Past CQP's scored ceiling nothing pays.
        let cq = try lowered("cqp"), cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let cap = try XCTUnwrap(cqp.multipliers.inState.maxScoredMultipliers)
        var clog = ContestLog(partyID: cq.id, myLocation: .inState(counties: [cqp.counties[0].abbr]))
        clog.station.callsign = "W6QPL"
        let tokens = MultClass.acceptedStateTokens.subtracting(cqp.excludedStateTokens).subtracting(cqp.stateAliases.keys).sorted()
            + cqp.provinces.sorted()                                   // 49 states + DC-less list + 13 provinces > 58
        clog.qsos = tokens.prefix(cap).enumerated().map { i, s in
            row("W\(i % 10)A\(i)", rcvd: ["serial": "\(i + 1)", "location": s], sent: ["serial": "\(i + 1)", "location": cqp.counties[0].abbr])
        }
        XCTAssertGreaterThanOrEqual(ScoreEngine.score(log: clog, contest: cq).multiplierKeys.count, cap)
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["location": "ON"]], call: "VE3ABC", band: .m20, modeClass: .cw, log: clog, contest: cq))
    }

    func testWouldAddMultiplierRespectsAForfeitedActivation() throws {
        let tn = try lowered("tnqp"), p = try XCTUnwrap(PartyCatalog.party(id: "tnqp"))
        let act = try XCTUnwrap(p.multipliers.inState.activatedCountyMultiplier), c = p.counties.map(\.abbr)
        var log = ContestLog(partyID: tn.id, myLocation: .inState(counties: [c[0]]))
        log.station.callsign = "W4QPL"; log.station.categoryStation = .mobile
        log.qsos = (0..<act.minCount).map { i in row("W\(i)AA", rcvd: ["rst": "599", "location": "TX"], sent: ["rst": "599", "location": c[0]]) }
        XCTAssertEqual(ScoreEngine.score(log: log, contest: tn).selfActivatedCounties, [c[0]])
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(received: [["location": c[0]]], call: "W4XYZ", band: .m20, modeClass: .cw, log: log, contest: tn),
                       "working the activated county trades one key for another")
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(received: [["location": c[1]]], call: "W4XYZ", band: .m20, modeClass: .cw, log: log, contest: tn))
    }

    func testBandModeCountsDesignatedCountiesAndCallAreaSum() throws {
        let c = try cqww()
        let l = log(c, sent: ["rst": ["599"], "zone": ["4"]], rows: [
            row("DL1AA", rcvd: ["rst": "599", "zone": "14"]), row("DL1AA", rcvd: ["rst": "599", "zone": "14"]),
            row("F5ABC", band: .m40, rcvd: ["rst": "599", "zone": "14"]), row("G3XYZ", mode: .phone, rcvd: ["rst": "59", "zone": "14"]),
        ])
        XCTAssertEqual(ScoreEngine.bandModeCounts(log: l, contest: c), [.m20: [.cw: 1], .m40: [.cw: 1]], "the dupe and the phone row do not count")
        let nc = try lowered("ncqp"), ncp = try XCTUnwrap(PartyCatalog.party(id: "ncqp"))
        guard case .designatedCountySweep(let designated, _, _)? = ncp.bonuses.first(where: { if case .designatedCountySweep = $0 { return true } else { return false } })
        else { return XCTFail("NCQP has a designated sweep") }
        var nlog = ContestLog(partyID: nc.id, myLocation: .outOfState(location: "TX"))
        nlog.station.callsign = "KE5CW"
        nlog.qsos = [row("W4AA", rcvd: ["rst": "599", "location": designated[0]], sent: ["rst": "599", "location": "TX"]),
                     row("W4BB", rcvd: ["rst": "599", "location": designated[1]], sent: ["rst": "599", "location": "TX"])]
        XCTAssertEqual(ScoreEngine.designatedCountiesWorked(designated, log: nlog, contest: nc), Set(designated.prefix(2).map { $0.uppercased() }))
        let sk = try lowered("skeeter")
        var slog = ContestLog(partyID: sk.id, myLocation: .outOfState(location: "TX"), exchangeMember: "13")
        slog.station.callsign = "KE5CW"
        slog.qsos = [row("W1AA", rcvd: ["rst": "599", "location": "CT", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "13"]),
                     row("K0BB", rcvd: ["rst": "599", "location": "CO", "member": "5W"], sent: ["rst": "599", "location": "TX", "member": "13"])]
        XCTAssertTrue(ScoreEngine.callAreaSumAchieved(target: 11, log: slog, contest: sk), "1 + 10")
        XCTAssertFalse(ScoreEngine.callAreaSumAchieved(target: 12, log: slog, contest: sk))
    }
```

- [ ] **Step 2: Run to verify it fails** — build errors on the four functions.

- [ ] **Step 3: Append to `ScoreEngine+Contest.swift`** (inside the extension, after `worked(classID:value:in:)`):

```swift
    // MARK: Derived queries

    /// Would logging a contact whose received exchange is one of `received`
    /// (several for a county line) add a multiplier this log does not hold?
    /// The NEW MULT badge. Past the side's scored ceiling nothing pays; a
    /// token whose activation multiplier would merely be traded for the worked
    /// one does not count as new either. Per-class caps are deliberately not
    /// consulted, as today.
    static func wouldAddMultiplier(received: [[String: String]], call: String, band: Band, modeClass: ModeClass,
                                   log: ContestLog, contest: ContestDefinition) -> Bool {
        guard contest.modeClasses.contains(modeClass) else { return false }
        let side = contest.resolvedSideID(log.sideID)
        let current = score(log: log, contest: contest).multiplierKeys
        let rules = contest.rules(for: side)
        // Past the contest's scored ceiling, a further multiplier pays nothing,
        // so the badge must not send the operator chasing it (CQP: 58 of 63).
        if let cap = rules.maxScoredMultipliers, current.count >= cap { return false }
        let classes = contest.multipliers.filter { $0.counting[side] != nil }
        for rcvd in received {
            for (cls, value) in multiplierValues(rcvd: QSO.compact(rcvd), call: call, side: side, classes: classes, contest: contest) {
                guard let scope = cls.counting[side]?.component(band: band, modeClass: modeClass) else { continue }
                let key = MultKey(classID: cls.id, value: value, scope: scope)
                guard !current.contains(key) else { continue }
                // A token the operator has already self-activated under a
                // forfeiting rule trades one key for another rather than
                // adding one — the same failure the cap guard exists to prevent.
                if let act = rules.activated, act.classID == cls.id, act.notOtherwiseWorked,
                   !gains(classID: cls.id, value: value, addingScope: scope, to: current) {
                    continue
                }
                return true
            }
        }
        return false
    }

    /// Valid (non-dupe, allowed-mode, in-scope, in-time) QSO counts per band
    /// and mode class — the sidebar's "QSOs by band" matrix.
    static func bandModeCounts(log: ContestLog, contest: ContestDefinition) -> [Band: [ModeClass: Int]] {
        var out: [Band: [ModeClass: Int]] = [:]
        for row in classify(log: log, contest: contest).validRows {
            out[row.band, default: [:]][row.modeClass, default: 0] += 1
        }
        return out
    }

    /// Which of a designated county list this log has credit for — the
    /// predicate behind `.designatedCountySweep`, exposed so the sidebar's
    /// progress readout is the same set the score pays on.
    static func designatedCountiesWorked(_ designated: [String], log: ContestLog, contest: ContestDefinition) -> Set<String> {
        designatedCounties(designated, workedIn: classify(log: log, contest: contest).scoredRows)
    }

    /// Whether the call-area blackjack target is met by this log's valid rows
    /// — the predicate behind `.callAreaSum`, exposed for the sidebar's badge.
    static func callAreaSumAchieved(target: Int, log: ContestLog, contest: ContestDefinition) -> Bool {
        let values = Set(classify(log: log, contest: contest).validRows.map { $0.call.uppercased() }).compactMap(callAreaValue)
        return subsetSumsExactly(values, target: target)
    }
```

- [ ] **Step 4: Build, run the class, then the full suite**

Expected: the class passes; full suite `Executed 3018 tests, with 0 failures` (3015 + 3).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Engine/ScoreEngine+Contest.swift Tests/Core/ContestScoreEngineTests.swift
git commit -m "engine: wouldAddMultiplier, bandModeCounts, designatedCountiesWorked and callAreaSumAchieved on the model

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: The equivalence corpus — every party, old engine versus model engine, field by field

A seeded, deterministic log corpus per party (counties, county lines both ways, states, alias keys, provinces, the DX token, DX prefixes including the colliding ones, sections, serials, names, member elements including blanks, dupes, an invalid mode, both sides, several station categories, entry classes, POTA rows, the party's own bonus callsigns) — scored by `score(log:party:)` (the old engine, untouched) and by `score(log:contest:)` on the lowered party. The `ScoreBreakdown`s must be equal, and so must `bandModeCounts` and `wouldAddMultiplier` for a set of probes. **This task ends only when every party is equal.** A divergence is a bug in the model engine or the lowering (or, rarely, a documented non-equivalence — see the list at the end of the step); the old engine is the oracle and is not touched.

**Files:**
- Create: `Tests/Core/EngineEquivalenceTests.swift`

- [ ] **Step 1: The corpus and the test**

```swift
// Tests/Core/EngineEquivalenceTests.swift
import XCTest
@testable import QSOPartyLogger

/// SplitMix64: a tiny deterministic generator, so the corpus is the same on
/// every machine and every run.
struct SplitMix64 {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
    mutating func pick<T>(_ a: [T]) -> T { a[int(a.count)] }
    mutating func chance(_ percent: Int) -> Bool { int(100) < percent }
}

/// The equivalence corpus: for each party and seed, one log per side, ~60
/// rows drawn from the party's own data plus a fixed pool of callsigns and
/// prefixes. Every id and timestamp is a function of the seed.
enum EquivalenceCorpus {
    static let seeds: [UInt64] = [11, 23, 37]
    static let entrantCall = "KE5CW"
    static let calls = ["W0BH", "K5TR", "N5NA", "VE3ABC", "VE5ABC", "VE6DEF", "PA0AAA", "OK1BBB", "LA1CCC", "ON4DDD",
                        "DL1EEE", "G3XYZ", "JA1AAA", "W3XYZ", "W5ABC", "N0XYZ/M", "KH6ABC", "KL7XYZ", "XE1AAA", "VP9ABC",
                        "F5ABC", "EA3ABC", "SM0ABC", "OZ1ABC", "HB9ABC", "VK2ABC", "ZL1ABC", "AA0AA", "K0AA", "W1AW/1", "W7DX"]
    static let prefixes = ["DL", "G", "JA", "F", "EA", "SM", "OZ", "HB", "VK", "ZL", "PA", "OK", "LA", "ON", "SK", "I", "LZ", "YU", "SP", "XE", "VP9", "KP4", "KH6", "KL7"]
    static let names = ["TOM", "BOB", "MARY-ANN", "O'NEIL", "SUE"]
    static let members = ["13", "5W", "100W", "", "2.5W", "1KW", "027", "500MW"]
    static let stations: [StationProfile.CategoryStation] = [.fixed, .mobile, .rover, .portable, .expedition]
    static let powers: [StationProfile.CategoryPower] = [.low, .high, .qrp]

    static func uuid(_ n: UInt64) -> UUID {
        UUID(uuidString: String(format: "%08llX-0000-4000-8000-%012llX", n >> 32, n & 0xFFFF_FFFF_FFFF))!
    }

    /// Every received token a party can produce, from its own data — plus the
    /// home state token and a plain typo, both of which the engines must
    /// ignore rather than credit.
    static func receivedPool(_ p: PartyDefinition) -> [String] {
        var pool: [String] = p.counties.map(\.abbr)
        if p.usesSections {
            pool += p.sections.sorted()
        } else {
            pool += MultClass.acceptedStateTokens.subtracting(p.excludedStateTokens).sorted()
            pool += p.stateAliases.keys.sorted()
            pool += p.provinces.sorted()
        }
        if p.acceptsDXToken { pool.append(MultClass.dxToken) }
        if p.dxStyle == .prefix { pool += prefixes }
        pool += p.dxTokenAliases.sorted()
        pool += [p.homeState, "ZZZ"]
        return pool
    }

    /// The entrant's own token(s) per side: counties (one or two, a county
    /// line) for `inside`; a state, a province, DX or a prefix for `outside`;
    /// for a party with no home region, whatever the single side may be.
    static func entrantLocations(_ p: PartyDefinition, seed: UInt64) -> [MyLocation] {
        var rng = SplitMix64(state: seed &* 7919)
        let counties = p.counties.map(\.abbr)
        let states = MultClass.acceptedStateTokens.subtracting(p.excludedStateTokens).sorted()
        var out: [MyLocation] = []
        if p.hasHomeRegion {
            let mine = counties.isEmpty ? [] : (rng.chance(50) && counties.count > 1
                ? [rng.pick(counties), rng.pick(counties)].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                : [rng.pick(counties)])
            out.append(.inState(counties: mine))
            let outside = [rng.pick(states), rng.pick(p.provinces.sorted().isEmpty ? states : p.provinces.sorted()),
                           p.acceptsDXToken ? MultClass.dxToken : rng.pick(states),
                           p.dxStyle == .prefix ? "DL" : rng.pick(states)]
            out.append(.outOfState(location: rng.pick(outside)))
        } else {
            let own = (counties + states).isEmpty ? ["TX"] : counties + states
            out.append(.outOfState(location: rng.pick(own)))
        }
        return out
    }

    static func logs(for p: PartyDefinition, seed: UInt64) -> [ContestLog] {
        entrantLocations(p, seed: seed).enumerated().map { index, location in
            log(for: p, seed: seed, location: location, index: index)
        }
    }

    static func log(for p: PartyDefinition, seed: UInt64, location: MyLocation, index: Int) -> ContestLog {
        var rng = SplitMix64(state: seed &* 104_729 &+ UInt64(index) &* 31)
        var log = ContestLog(partyID: p.id, myLocation: location,
                             exchangeName: p.exchangeIncludesName ? "TOM" : "",
                             exchangeMember: p.memberExchange == nil ? "" : rng.pick(["13", "5W"]),
                             entryClassID: p.entryClasses.isEmpty ? "" : rng.pick(p.entryClasses.map(\.id) + [""]))
        log.station.callsign = entrantCall
        log.station.categoryStation = rng.pick(stations)
        log.station.categoryPower = rng.pick(powers)
        log.setupCompleted = true
        if rng.chance(30) { log.myPotaRefs = ["US-3315"] }

        let bonusCalls = p.bonuses.compactMap { bonus -> String? in
            if case .workStation(let call, _, _) = bonus { return call } else { return nil }
        }
        let callPool = calls + bonusCalls + bonusCalls   // bonus calls twice as likely
        let pool = receivedPool(p)
        let counties = p.counties.map(\.abbr)
        let bands = p.validBands.isEmpty ? [Band.m20] : p.validBands
        let modes = p.allowedModeClasses.isEmpty ? [ModeClass.cw] : p.allowedModeClasses
        let base = 1_789_900_000.0 + Double(seed) * 3600 + Double(index) * 90_000
        var clock = 0.0
        var rows: [QSO] = []
        var contacts: [(call: String, band: Band, mode: ModeClass, theirs: [String])] = []
        var n: UInt64 = seed << 20 | UInt64(index) << 16
        var serial = 0
        while rows.count < 60 {
            clock += Double(20 + rng.int(380))
            let call: String, band: Band, mode: ModeClass, theirs: [String]
            if !contacts.isEmpty, rng.chance(15) {
                let again = rng.pick(contacts)                            // a dupe candidate
                call = again.call; band = again.band; mode = again.mode; theirs = again.theirs
            } else {
                call = rng.pick(callPool)
                band = rng.chance(90) ? rng.pick(bands) : rng.pick(Band.allCases)
                mode = rng.chance(88) ? rng.pick(modes) : rng.pick(ModeClass.allCases)
                theirs = rng.chance(10) && counties.count > 1
                    ? [rng.pick(counties), rng.pick(counties)].reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                    : [rng.pick(pool)]
                contacts.append((call, band, mode, theirs))
            }
            serial += 1
            let raw = mode == .phone ? rng.pick(["SSB", "USB", "LSB", "FM"]) : mode == .cw ? "CW" : rng.pick(["RTTY", "FT8"])
            let rst = mode == .phone ? "59" : "599"
            let name = p.exchangeIncludesName ? rng.pick(names) : nil
            let member = p.memberExchange == nil ? nil : rng.pick(members)
            let theirParks: [String]? = rng.chance(5) ? ["US-0088"] : nil
            let group = uuid(n); n += 1
            let stamp = Date(timeIntervalSince1970: base + clock)
            for mine in location.sentExchanges {
                for their in theirs {
                    rows.append(QSO(
                        id: uuid(n), groupID: group, timestampUTC: stamp, call: call, band: band, modeClass: mode, rawMode: raw,
                        freqKHz: nil, rstSent: rst, rstRcvd: rst,
                        serialSent: p.exchangeIncludesSerial ? serial : nil,
                        serialRcvd: p.exchangeIncludesSerial ? 1 + rng.int(500) : nil,
                        nameSent: p.exchangeIncludesName ? "TOM" : nil, nameRcvd: name,
                        memberSent: p.memberExchange == nil ? nil : log.exchangeMember, memberRcvd: member.flatMap { $0.isEmpty ? nil : $0 },
                        myPotaRefs: log.myPotaRefs.isEmpty ? nil : log.myPotaRefs, theirPotaRefs: theirParks,
                        myLoc: mine, theirLoc: their))
                    n += 1
                }
            }
        }
        log.qsos = rows
        return log
    }
}

final class EngineEquivalenceTests: XCTestCase {

    /// The whole corpus, every party, old engine == model engine.
    func testEveryPartyScoresIdenticallyThroughTheModel() throws {
        var compared = 0
        for p in PartyCatalog.loadBundled() {
            let contest = try PartyLowering.lower(p)
            for seed in EquivalenceCorpus.seeds {
                for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                    let label = "\(p.id) seed \(seed) side \(log.sideID) (\(log.myLocation.displayText))"
                    let old = ScoreEngine.score(log: log, party: p)
                    let new = ScoreEngine.score(log: log, contest: contest)
                    XCTAssertEqual(old, new, label)
                    if old != new {   // one readable diff per divergence, then stop the flood
                        XCTFail("\(label): keys only in old \(old.multiplierKeys.subtracting(new.multiplierKeys)); only in new \(new.multiplierKeys.subtracting(old.multiplierKeys)); points \(old.qsoPoints) vs \(new.qsoPoints); bonus \(old.bonusPoints) vs \(new.bonusPoints); valid \(old.validQSOs) vs \(new.validQSOs); scope \(old.outOfScopeCount) vs \(new.outOfScopeCount)")
                    }
                    XCTAssertEqual(ScoreEngine.bandModeCounts(log: log, party: p), ScoreEngine.bandModeCounts(log: log, contest: contest), label)
                    compared += 1
                }
            }
        }
        XCTAssertGreaterThanOrEqual(compared, 250, "50 parties × 3 seeds × 1–2 sides")
    }

    /// The NEW MULT question, asked of every probe token on the first band in every mode.
    func testWouldAddMultiplierAgreesOnEveryProbe() throws {
        for p in PartyCatalog.loadBundled() {
            let contest = try PartyLowering.lower(p)
            let seed = EquivalenceCorpus.seeds[0]
            for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                for token in EquivalenceCorpus.receivedPool(p).prefix(8) {
                    for mode in p.allowedModeClasses {
                        for (call, member) in [("W0BH", nil), ("PA0AAA", "13"), ("DL1EEE", "5W")] as [(String, String?)] {
                            let old = ScoreEngine.wouldAddMultiplier(theirLocs: [token], band: p.validBands[0], modeClass: mode,
                                                                     log: log, party: p, call: call, memberRcvd: member)
                            var rcvd = ["location": token]
                            if let member { rcvd["member"] = member }
                            let new = ScoreEngine.wouldAddMultiplier(received: [rcvd], call: call, band: p.validBands[0], modeClass: mode,
                                                                     log: log, contest: contest)
                            XCTAssertEqual(old, new, "\(p.id) \(log.sideID) probe \(token) \(mode) \(call)")
                        }
                    }
                }
            }
        }
    }

    /// The two sidebar predicates the score also pays on.
    func testDesignatedSweepAndCallAreaSumAgree() throws {
        for p in PartyCatalog.loadBundled() {
            let contest = try PartyLowering.lower(p)
            for bonus in p.bonuses {
                for seed in EquivalenceCorpus.seeds {
                    for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                        switch bonus {
                        case .designatedCountySweep(let counties, _, _):
                            XCTAssertEqual(ScoreEngine.designatedCountiesWorked(counties, log: log, party: p),
                                           ScoreEngine.designatedCountiesWorked(counties, log: log, contest: contest), p.id)
                        case .callAreaSum(let target, _):
                            XCTAssertEqual(ScoreEngine.callAreaSumAchieved(target: target, log: log, party: p),
                                           ScoreEngine.callAreaSumAchieved(target: target, log: log, contest: contest), p.id)
                        default: break
                        }
                    }
                }
            }
        }
    }

    func testTheCorpusIsDeterministic() throws {
        let p = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        XCTAssertEqual(EquivalenceCorpus.logs(for: p, seed: 11), EquivalenceCorpus.logs(for: p, seed: 11))
        XCTAssertNotEqual(EquivalenceCorpus.logs(for: p, seed: 11), EquivalenceCorpus.logs(for: p, seed: 23))
        XCTAssertGreaterThanOrEqual(EquivalenceCorpus.logs(for: p, seed: 11).map(\.qsos.count).reduce(0, +), 120)
    }
}
```
(`entrantLocations` should build the county-line pair without a duplicate; the `reduce(into:)` dedupes. `MyLocation.displayText` exists.)

- [ ] **Step 2: Run the class**

Run: `xcodegen generate` (new file), then the `EngineEquivalenceTests` class. Expected first run: **probably red** — read every divergence message. Known places a difference can hide, in likely order:

1. **Ownership vs the old branch order** — the old engine checks counties → sections → (collision) → aliases → states → provinces → `DX` → prefix; the model classifies by the element's `sentBy` set order (`counties`, then `sections` or `states`+`provinces`, `dxToken`, `dxccPrefix`, `dxAliases`) with the callsign override applied to `states`/`provinces` owners. They agree by construction; if a token disagrees, print `ExchangeValidator.owningSet` for it and compare with `PartyDefinition.isDXPrefix` / `validOutStateTokens`.
2. **`dxTokenAliases` (FQP `R1 R2 R3`)** — old: `isDXPrefix` accepts them, then `match(prefix:)` on the ARRL table; if the table has such a key the old value is the entity label, the model's `dxAliases` resolver yields the literal. Check `DXCCTable.shared.entity(forPrefix: "R1")`; if it resolves, the lowering must route these through the `dxccEntity` resolver instead (and say so in the commit).
3. **Caps** — the old `dxCount` counts distinct dx *values*; the model's `distinctValues` must be seeded with granted values and updated on every inserted key.
4. **`activatedCountyCount` bonus** — old guards `myLocation.isInState`; the model relies on the sent location being a county. Equal for every generated log; if not, the log's sent token is a county for an outside entrant — a corpus bug, fix the generator.
5. **Points for a designated county that is not a home county** — the lowering scales `homeStationPoints ?? points`; the old engine scales whichever table applied. Equal while every designated county is a county (NCQP); the validation added in Task 5 enforces exactly that.
6. **Empty `theirLoc` / typo tokens** — both engines: points yes, multipliers none.

Fix the model engine or the lowering; never the old engine, never a party file, never the corpus to dodge a real difference. Re-run until green.

- [ ] **Step 3: Full suite**

Expected: `Executed 3022 tests, with 0 failures` (3018 + 4), and the equivalence class runs in well under a minute (if it does not, reduce `receivedPool(p).prefix(8)` to 6 — not the seeds).

- [ ] **Step 4: Commit**

```bash
git add Tests/Core/EngineEquivalenceTests.swift Sources QSOPartyLogger.xcodeproj
git commit -m "tests: engine equivalence corpus — every bundled party, three seeds, both sides: old engine == model engine, field by field; NEW MULT and sidebar predicates agree

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
(If the fixes touched `ScoreEngine+Contest.swift` or `PartyLowering.swift`, they are in this commit and the message names them: `… ; fixed: <what>`.)

---

### Task 10: Cabrillo and ADIF on the model — byte-identical for the parties, spec-driven for everyone

**Files:**
- Modify: `Sources/Core/Export/CabrilloExporter.swift`, `Sources/Core/Export/AdifExporter.swift` (both replaced below)
- Test: `Tests/Core/ContestExportTests.swift`; `Tests/Core/ExportByteIdentityTests.swift` (two assertions added); `Tests/Core/CabrilloExporterTests.swift` (`testGoldenQSOLine` moves to the contest API)

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/Core/ContestExportTests.swift
import XCTest
@testable import QSOPartyLogger

/// The exporters on `ContestDefinition`: the QSO line derived from the
/// exchange spec, `LOCATION:` from `CabrilloSpec`, the new header lines and
/// ADIF fields for a general contest, and `OFFTIME:` from the operating-time
/// rule. Party bytes are pinned by `ExportByteIdentityTests`.
final class ContestExportTests: XCTestCase {
    let t = Date(timeIntervalSince1970: 1_795_824_120)   // 2026-11-28 00:02:00Z

    func cqww() throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json"))
        return try ContestDefinition.decode(try Data(contentsOf: url))
    }

    func cqwwLog(_ c: ContestDefinition) -> ContestLog {
        var log = ContestLog(partyID: c.id)
        log.station.callsign = "KE5CW"; log.station.name = "Tom Bowles"; log.station.exchangeDefaults = ["state": "TX"]
        log.station.categoryOverlay = "CLASSIC"; log.station.categoryBand = "20M"
        log.sideID = "all"; log.sentExchange = ["rst": ["599"], "zone": ["4"]]
        log.qsos = [QSO(timestampUTC: t, call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                        sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14"])]
        return log
    }

    func testCQWWQSOLineHeaderAndLocation() throws {
        let c = try cqww(), log = cqwwLog(c)
        XCTAssertEqual(CabrilloExporter.qsoLine(log.qsos[0], myCall: "KE5CW", contest: c, side: "all"),
                       "QSO: 14042 CW 2026-11-28 0002 KE5CW         599 4      DL1AA         599 14     0")
        let text = CabrilloExporter.export(log: log, contest: c, score: ScoreEngine.score(log: log, contest: c))
        let lines = text.components(separatedBy: "\n")
        XCTAssertTrue(lines.contains("CONTEST: CQ-WW-CW"))
        XCTAssertTrue(lines.contains("LOCATION: TX"), "no location element: exchangeDefaults.state")
        XCTAssertTrue(lines.contains("CATEGORY-BAND: 20M"))
        XCTAssertTrue(lines.contains("CATEGORY-OVERLAY: CLASSIC"))
        XCTAssertFalse(text.contains("CATEGORY-TIME:"))
        XCTAssertTrue(lines.contains("CLAIMED-SCORE: 6"), "3 points × (zone + country)")
        var dx = log; dx.station.exchangeDefaults = [:]
        XCTAssertEqual(CabrilloExporter.location(log: dx, contest: c), "DX")
    }

    func testCallEchoAndSectionLocation() throws {
        // A Sweepstakes-shaped spec: nr prec call ck sect, no report column.
        let sections = try XCTUnwrap(TokenSet.sections())
        let ss = ContestDefinition(
            id: "ss", name: "SS", family: .domestic, bands: [.m20], modeClasses: [.cw],
            sides: [Side(id: "all", label: "Everyone", predicate: .always, workedPredicate: .always)],
            exchange: [ExchangeElement(id: "serial", kind: .serial, sentBy: ["all": .init()], cabrilloWidth: 4),
                       ExchangeElement(id: "precedence", kind: .precedence, sentBy: ["all": .init()], letters: ["Q", "A", "B", "U", "M", "S"]),
                       ExchangeElement(id: "call", kind: .callEcho, sentBy: ["all": .init()]),
                       ExchangeElement(id: "check", kind: .check, sentBy: ["all": .init()]),
                       ExchangeElement(id: "section", kind: .token, sentBy: ["all": .init(sets: ["sections"])], fixed: true, cabrilloWidth: 3)],
            multipliers: [MultiplierClass(id: "section", term: "section", resolvers: [Resolver(kind: .receivedToken, element: "section", set: "sections")],
                                          counting: ["all": .once], roster: "sections")],
            points: [PointRule(points: 2)], dupe: DupeRule(scope: .contest),
            cabrillo: CabrilloSpec(contest: "ARRL-SS-CW", location: .section))
        try ss.validate()
        _ = sections
        var log = ContestLog(partyID: ss.id)
        log.station.callsign = "KE5CW"; log.sideID = "all"; log.sentExchange = ["precedence": ["A"], "check": ["65"], "section": ["NTX"]]
        let q = QSO(timestampUTC: t, call: "K1ABC", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                    sent: ["serial": "1", "precedence": "A", "check": "65", "section": "NTX"],
                    rcvd: ["serial": "17", "precedence": "B", "check": "72", "section": "EMA"])
        log.qsos = [q]
        XCTAssertEqual(CabrilloExporter.qsoLine(q, myCall: "KE5CW", contest: ss, side: "all"),
                       "QSO: 14042 CW 2026-11-28 0002 KE5CW         1    A KE5CW         65 NTX K1ABC         17   B K1ABC         72 EMA")
        XCTAssertEqual(CabrilloExporter.location(log: log, contest: ss), "NTX")
    }

    func testReportColumnWritesTheRowsReportOrTheModeDefault() throws {
        let md = try PartyLowering.lower(XCTUnwrap(PartyCatalog.party(id: "mdc")))
        XCTAssertTrue(md.cabrillo.reportColumn)
        let c0 = try XCTUnwrap(PartyCatalog.party(id: "mdc")).counties[0].abbr
        let withReport = QSO(timestampUTC: t, call: "W3XYZ", band: .m20, modeClass: .cw, rawMode: "CW", freqKHz: 14042,
                             rstSent: "599", rstRcvd: "579", myLoc: c0, theirLoc: "PA")
        let without = QSO(timestampUTC: t, call: "W3XYZ", band: .m20, modeClass: .phone, rawMode: "SSB", freqKHz: 14250,
                          sent: ["location": c0], rcvd: ["location": "PA"])
        XCTAssertEqual(CabrilloExporter.qsoLine(withReport, myCall: "KE5CW", contest: md, side: "inside"),
                       "QSO: 14042 CW 2026-11-28 0002 KE5CW         599 \(c0.padded(to: 6)) W3XYZ         579 PA    ")
        XCTAssertEqual(CabrilloExporter.qsoLine(without, myCall: "KE5CW", contest: md, side: "inside"),
                       "QSO: 14250 PH 2026-11-28 0002 KE5CW         59  \(c0.padded(to: 6)) W3XYZ         59  PA    ")
    }

    func testOffTimeLinesFollowTheOperatingRule() throws {
        let c = try cqww()
        var log = cqwwLog(c)
        let day = Date(timeIntervalSince1970: 1_795_824_000)
        func at(_ hhmm: Int) -> Date { day.addingTimeInterval(TimeInterval((hhmm / 100) * 3600 + (hhmm % 100) * 60)) }
        log.qsos = [QSO(timestampUTC: at(0114), call: "DL1AA", band: .m20, modeClass: .cw, rawMode: "CW", sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14"]),
                    QSO(timestampUTC: at(0230), call: "F5ABC", band: .m20, modeClass: .cw, rawMode: "CW", sent: ["rst": "599", "zone": "4"], rcvd: ["rst": "599", "zone": "14"])]
        let text = CabrilloExporter.export(log: log, contest: c, score: ScoreEngine.score(log: log, contest: c))
        XCTAssertTrue(text.components(separatedBy: "\n").contains("OFFTIME: 2026-11-28 0115 2026-11-28 0229"), text)
        var rookie = log; rookie.station.categoryOverlay = "ROOKIE"
        XCTAssertFalse(CabrilloExporter.export(log: rookie, contest: c, score: .init()).contains("OFFTIME:"))
    }

    func testAdifCarriesZonesEntityAndContinentForAGeneralContest() throws {
        let c = try cqww(), log = cqwwLog(c)
        let adif = AdifExporter.export(log: log, contest: c)
        XCTAssertTrue(adif.hasPrefix("Generated by QSO Party Logger — CQ World Wide DX Contest, CW\n"))
        for field in ["<cqz:2>14", "<my_cq_zone:1>4", "<dxcc:3>230", "<cont:2>EU", "<contest_id:8>CQ-WW-CW", "<rst_sent:3>599", "<rst_rcvd:3>599"] {
            XCTAssertTrue(adif.contains(field), field)
        }
        XCTAssertFalse(adif.contains("stx_string"), "no location element")
        XCTAssertFalse(adif.contains("<state:"))
    }

    func testAdifSectionCheckPrecedenceClassGridPower() throws {
        let sides = [Side(id: "all", label: "Everyone", predicate: .always, workedPredicate: .always)]
        let c = ContestDefinition(
            id: "x", name: "X", family: .domestic, bands: [.m20], modeClasses: [.cw], sides: sides,
            exchange: [ExchangeElement(id: "precedence", kind: .precedence, sentBy: ["all": .init()], letters: ["A", "B"]),
                       ExchangeElement(id: "check", kind: .check, sentBy: ["all": .init()]),
                       ExchangeElement(id: "section", kind: .token, sentBy: ["all": .init(sets: ["sections"])]),
                       ExchangeElement(id: "class", kind: .classToken, sentBy: ["all": .init()], letters: ["A", "B"], minNumber: 1),
                       ExchangeElement(id: "grid", kind: .grid, sentBy: ["all": .init()]),
                       ExchangeElement(id: "power", kind: .power, sentBy: ["all": .init()])],
            multipliers: [], points: [PointRule(points: 1)], dupe: DupeRule(scope: .band),
            cabrillo: CabrilloSpec(contest: "X", location: .section))
        try c.validate()
        var log = ContestLog(partyID: c.id); log.station.callsign = "KE5CW"; log.sideID = "all"
        log.qsos = [QSO(timestampUTC: t, call: "K1ABC", band: .m20, modeClass: .cw, rawMode: "CW",
                        sent: ["precedence": "A", "check": "65", "section": "NTX", "class": "1B", "grid": "EM13", "power": "100"],
                        rcvd: ["precedence": "B", "check": "72", "section": "EMA", "class": "3A", "grid": "FN42AB", "power": "KW"])]
        let adif = AdifExporter.export(log: log, contest: c)
        for field in ["<precedence:1>B", "<check:2>72", "<arrl_sect:3>EMA", "<my_arrl_sect:3>NTX", "<class:2>3A",
                      "<gridsquare:6>FN42AB", "<my_gridsquare:4>EM13", "<tx_pwr:3>100"] {
            XCTAssertTrue(adif.contains(field), field)
        }
        XCTAssertFalse(adif.contains("rx_pwr"), "KW is not a number; ADIF RX_PWR is")
    }
}
```
Add to `ExportByteIdentityTests` two more tests:
```swift
    func testCabrilloOnTheModelIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            let contest = try PartyLowering.lower(f.party)
            let score = ScoreEngine.score(log: f.log, contest: contest)
            XCTAssertEqual(CabrilloExporter.export(log: f.log, contest: contest, score: score), try fixtureText(f.name, "log"), f.name)
        }
    }

    func testAdifOnTheModelIsByteIdenticalToTheFixtures() throws {
        for f in try ExportFixtures.all() {
            XCTAssertEqual(AdifExporter.export(log: f.log, contest: try PartyLowering.lower(f.party)), try fixtureText(f.name, "adi"), f.name)
        }
    }
```
And in `Tests/Core/CabrilloExporterTests.swift`, change `testGoldenQSOLine` to call the new line API, keeping the pinned bytes:
```swift
    func testGoldenQSOLine() throws {
        let q = makeLog().qsos[0]
        XCTAssertEqual(
            CabrilloExporter.qsoLine(q, myCall: "KE5CW", contest: try PartyLowering.lower(ksqp), side: "outside"),
            "QSO: 14042 CW 2026-08-29 1432 KE5CW         599 TX     W0BH          599 MRN   "
        )
    }
```

- [ ] **Step 2: Run to verify they fail** — build errors on the contest overloads.

- [ ] **Step 3: Replace `Sources/Core/Export/CabrilloExporter.swift`**

```swift
import Foundation

/// Cabrillo V3 export on `ContestDefinition`. The header comes from the
/// station profile and `CabrilloSpec`; the QSO line is derived from the
/// exchange spec — `QSO: freq mo date time mycall <sent elements> call
/// <received elements> [t]`, each element padded to its `cabrilloWidth`.
/// County-line contacts arrive pre-expanded as separate rows, so each emits
/// its own QSO line with its own sent county — the format QSO party sponsors
/// (and N1MM) expect. Sponsors state that spaces delimit and columns need not
/// align, so the widths matter only for our own byte-identity
/// (`ExportByteIdentityTests`).
enum CabrilloExporter {

    static let creator = "QSO Party Logger 1.0"

    static func export(log: ContestLog, contest: ContestDefinition, score: ScoreEngine.ScoreBreakdown) -> String {
        var lines: [String] = []
        let s = log.station
        let side = contest.resolvedSideID(log.sideID)

        lines.append("START-OF-LOG: 3.0")
        lines.append("CREATED-BY: \(creator)")
        lines.append("CONTEST: \(contest.cabrillo.contest)")
        lines.append("CALLSIGN: \(s.callsign.uppercased())")
        lines.append("LOCATION: \(location(log: log, contest: contest))")
        lines.append("CATEGORY-OPERATOR: \(s.categoryOperator.rawValue)")
        lines.append("CATEGORY-ASSISTED: \(s.categoryAssisted.rawValue)")
        lines.append("CATEGORY-BAND: \(s.categoryBand ?? "ALL")")
        lines.append("CATEGORY-MODE: \(contest.cabrillo.categoryMode ?? categoryMode(log.qsos))")
        lines.append("CATEGORY-POWER: \(s.categoryPower.rawValue)")
        lines.append("CATEGORY-STATION: \(s.categoryStation.rawValue)")
        lines.append("CATEGORY-TRANSMITTER: \(s.categoryTransmitter.rawValue)")
        if let overlay = s.categoryOverlay, !overlay.isEmpty { lines.append("CATEGORY-OVERLAY: \(overlay)") }
        if let time = s.categoryTime, !time.isEmpty { lines.append("CATEGORY-TIME: \(time)") }
        lines.append("CLAIMED-SCORE: \(score.total)")
        lines.append("OPERATORS: \(s.operators.isEmpty ? s.callsign.uppercased() : s.operators.uppercased())")
        if !s.club.isEmpty { lines.append("CLUB: \(s.club)") }
        lines.append("NAME: \(s.name)")
        if !s.address.isEmpty { lines.append("ADDRESS: \(s.address)") }
        if !s.city.isEmpty { lines.append("ADDRESS-CITY: \(s.city)") }
        if !s.stateProvince.isEmpty { lines.append("ADDRESS-STATE-PROVINCE: \(s.stateProvince)") }
        if !s.postalCode.isEmpty { lines.append("ADDRESS-POSTALCODE: \(s.postalCode)") }
        if !s.country.isEmpty { lines.append("ADDRESS-COUNTRY: \(s.country)") }
        if !s.gridLocator.isEmpty { lines.append("GRID-LOCATOR: \(s.gridLocator.uppercased())") }
        if !s.email.isEmpty { lines.append("EMAIL: \(s.email)") }
        lines.append("SOAPBOX: ")
        // The credited off periods, where the contest has an operating-time
        // rule that applies to this entry (SS, WPX single-op, CQ WW Classic).
        if let rule = contest.operatingTime, rule.applies(to: log.categoryValues) {
            for period in ScoreEngine.classify(log: log, contest: contest).operatingTime.offPeriods {
                lines.append("OFFTIME: \(dateFormatter.string(from: period.start)) \(dateFormatter.string(from: period.end))")
            }
        }

        let myCall = s.callsign.uppercased()
        for q in log.qsos.sortedChronologically() {
            lines.append(qsoLine(q, myCall: myCall, contest: contest, side: side))
        }
        lines.append("END-OF-LOG:")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The `PartyDefinition` overload: lower, then export on the model.
    static func export(log: ContestLog, party: PartyDefinition, score: ScoreEngine.ScoreBreakdown) -> String {
        export(log: log, contest: PartyLowering.lowered(party), score: score)
    }

    /// `LOCATION:` per `CabrilloSpec.location`. `.state`: `homeLocation` for
    /// an entrant on the first-listed side (a party's primary state, however
    /// many counties they sit on), else the entrant's sent location token —
    /// resolved to its group where the token has one (a county to its state)
    /// — else `exchangeDefaults["state"]`, else `DX`. `.entrantToken`: the
    /// sent token verbatim, else `DX`. `.section`: the sent section, else
    /// `exchangeDefaults["section"]`, else `DX`. Byte-identical to
    /// `MyLocation.entrantToken` for every party.
    static func location(log: ContestLog, contest: ContestDefinition) -> String {
        let side = contest.resolvedSideID(log.sideID)
        let sentLocation = log.sentExchange[ExchangeElementID.location]?.first?.uppercased()
        switch contest.cabrillo.location {
        case .entrantToken:
            return sentLocation ?? "DX"
        case .state:
            if let home = contest.cabrillo.homeLocation, side == contest.sides.first?.id { return home }
            if let token = sentLocation { return group(of: token, contest: contest, side: side) ?? token }
            if let state = log.station.exchangeDefaults["state"], !state.isEmpty { return state.uppercased() }
            return "DX"
        case .section:
            if let section = log.sentExchange["section"]?.first, !section.isEmpty { return section.uppercased() }
            if let section = log.station.exchangeDefaults["section"], !section.isEmpty { return section.uppercased() }
            return "DX"
        }
    }

    /// The group of a sent location token — a county's state — if the set that
    /// owns it carries groups; nil for a state, province, DX or unknown token.
    private static func group(of token: String, contest: ContestDefinition, side: String) -> String? {
        guard let element = contest.exchange.first(where: { $0.id == ExchangeElementID.location }) else { return nil }
        for setID in element.setsSent(by: [side]) {
            if let set = contest.tokenSet(id: setID), let t = set.token(for: token) { return t.group }
        }
        return nil
    }

    static func categoryMode(_ qsos: [QSO]) -> String {
        let classes = Set(qsos.map(\.modeClass))
        if classes.count > 1 { return "MIXED" }
        switch classes.first {
        case .cw: return "CW"
        case .phone: return "SSB"
        case .digital: return "RTTY"
        case nil: return "MIXED"
        }
    }

    static func cabrilloMode(_ rawMode: String) -> String {
        switch rawMode.uppercased() {
        case "CW": "CW"
        case "SSB", "USB", "LSB", "AM": "PH"
        case "FM": "FM"
        case "RTTY": "RY"
        default: "DG"
        }
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HHmm"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// One QSO line: the fixed columns, my sent elements, the worked call, the
    /// received elements (the call echo among them, padded to the call
    /// column's 13), and the transmitter column where the contest has one
    /// (always `0` — one transmitter).
    static func qsoLine(_ q: QSO, myCall: String, contest: ContestDefinition, side: String) -> String {
        let freq = String(q.freqKHz ?? q.band.defaultFreqKHz)
        let mode = cabrilloMode(q.rawMode)
        let when = dateFormatter.string(from: q.timestampUTC)
        let mine = myCall.uppercased(), theirs = q.call.uppercased()
        var line = "QSO: " + freq.leftPadded(to: 5) + " " + mode.padded(to: 2) + " " + when + " " + mine.padded(to: 13)
        line += columns(for: contest.sentElements(for: side), values: q.sent, call: mine, modeClass: q.modeClass, contest: contest)
        line += " " + theirs.padded(to: 13)
        line += columns(for: contest.receivedElements(for: side, includingCallEcho: true), values: q.rcvd, call: theirs,
                        modeClass: q.modeClass, contest: contest)
        if contest.cabrillo.transmitterColumn { line += " 0" }
        return line
    }

    /// The columns for one side of the line: `" " + value.padded(to: width)`
    /// per element in spec order. A `callEcho` writes the side's call, padded
    /// to 13. An element that is not `required` writes nothing at all when its
    /// value is empty (the member-or-power element, absent for a QRO
    /// station). Where the spec has no `rst`/`serial`/`name` element and
    /// `reportColumn` is set, the row's report — or the mode's default report
    /// — leads, in the generic template's ex1 slot.
    private static func columns(for elements: [ExchangeElement], values: [String: String], call: String,
                                modeClass: ModeClass, contest: ContestDefinition) -> String {
        var out = ""
        if contest.cabrillo.reportColumn,
           !elements.contains(where: { $0.kind == .rst || $0.kind == .serial || $0.kind == .name }) {
            out += " " + (values[ExchangeElementID.rst] ?? modeClass.defaultRST).uppercased().padded(to: 3)
        }
        for element in elements {
            if element.kind == .callEcho {
                out += " " + call.padded(to: 13)
                continue
            }
            let value = (values[element.id] ?? "").uppercased()
            if value.isEmpty && !element.required { continue }
            out += " " + value.padded(to: element.cabrilloWidth)
        }
        return out
    }
}

extension String {
    func padded(to width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }

    func leftPadded(to width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }
}
```
(`ModeClass.defaultRST` exists — `EntryState` uses it. If it does not, add `var defaultRST: String { self == .phone ? "59" : "599" }` to `ModeClass`.)

- [ ] **Step 4: Replace `Sources/Core/Export/AdifExporter.swift`**

```swift
import Foundation

/// ADIF 3.1.4 export on `ContestDefinition`. Each logged row (including each
/// county-line row) becomes one ADIF record; the shared group id rides along
/// in an APP_ field so other tools can reassociate county-line pairs. Fields
/// follow the exchange elements by kind: `rst` → `rst_sent`/`rst_rcvd`,
/// `serial` → `stx`/`srx`, `name` → `my_name`/`name`, `memberOrPower` → the
/// APP_ member fields, the `location` token → `stx_string`/`srx_string` (and
/// `cnty`/`state` where it names a county or state), `section` → `arrl_sect`,
/// `cqZone` → `cqz`, `ituZone` → `ituz`, `precedence`/`check`/`classToken`
/// → their ADIF names, `grid` → `gridsquare`, a numeric `power` → `tx_pwr` /
/// `rx_pwr`; `dxcc`/`cont` from cty where the contest resolves the worked
/// call's entity or zone. Every party's ADIF is byte-identical to before.
enum AdifExporter {

    static func export(log: ContestLog, contest: ContestDefinition) -> String {
        var out = "Generated by QSO Party Logger — \(contest.name)\n"
        out += field("adif_ver", "3.1.4")
        out += field("programid", "QSOPartyLogger")
        out += "<eoh>\n\n"

        let side = contest.resolvedSideID(log.sideID)
        let myCall = log.station.callsign.uppercased()
        let counties = contest.countyRoster()
        let myState = adifState(for: log, contest: contest, side: side)
        // The worked call's entity and continent are written where the contest
        // reads them — a country class from the callsign, or a zone element.
        let writesEntity = contest.multipliers.contains { $0.resolvers.contains { $0.kind == .dxccEntity && $0.from == .callsign } }
            || contest.exchange.contains { $0.kind == .cqZone || $0.kind == .ituZone }

        for q in log.qsos.sortedChronologically() {
            out += record(q, myCall: myCall, contest: contest, side: side, counties: counties, myState: myState, writesEntity: writesEntity)
        }
        return out
    }

    /// The `PartyDefinition` overload: lower, then export on the model.
    static func export(log: ContestLog, party: PartyDefinition) -> String {
        export(log: log, contest: PartyLowering.lowered(party))
    }

    /// The entrant's own state for `my_state`: a first-listed-side entrant's
    /// `homeLocation` (a party's own state, including the province codes the
    /// Canadian parties use); otherwise the sent location token only when it
    /// really is a US state, so an NAQP entrant in Mexico leaves the field
    /// empty rather than claiming `XE` is a state; otherwise
    /// `exchangeDefaults["state"]` when that is one.
    private static func adifState(for log: ContestLog, contest: ContestDefinition, side: String) -> String {
        if contest.cabrillo.location == .state, let home = contest.cabrillo.homeLocation, side == contest.sides.first?.id { return home }
        let token = (log.sentExchange[ExchangeElementID.location]?.first ?? log.station.exchangeDefaults["state"] ?? "").uppercased()
        return TokenSet.usStates.abbrs.contains(token) ? token : ""
    }

    private static let dateF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let timeF: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmmss"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func field(_ name: String, _ value: String) -> String {
        value.isEmpty ? "" : "<\(name):\(value.utf8.count)>\(value) "
    }

    static func record(_ q: QSO, myCall: String, contest: ContestDefinition, side: String,
                       counties: TokenSet?, myState: String, writesEntity: Bool) -> String {
        var r = ""
        r += field("qso_date", dateF.string(from: q.timestampUTC))
        r += field("time_on", timeF.string(from: q.timestampUTC))
        r += field("call", q.call.uppercased())
        r += field("band", q.band.adif)
        if let kHz = q.freqKHz {
            r += field("freq", String(format: "%.6f", Double(kHz) / 1000.0))
        }
        r += field("mode", adifMode(q.rawMode))
        r += field("rst_sent", q.rstSent)
        r += field("rst_rcvd", q.rstRcvd)
        // ADIF 3.1.4 keeps serials separate from reports: STX/SRX are the
        // transmitted/received serial numbers.
        if let stx = q.serialSent { r += field("stx", String(stx)) }
        if let srx = q.serialRcvd { r += field("srx", String(srx)) }
        r += field("my_name", (q.nameSent ?? "").uppercased())
        r += field("name", (q.nameRcvd ?? "").uppercased())
        // The member-number-or-power element (Skeeter Hunt). ADIF 3.1.4 has
        // no field for a club number, and stx_string/srx_string are already
        // the locations, so it rides APP_ fields.
        r += field("app_qsopartylogger_member_sent", (q.memberSent ?? "").uppercased())
        r += field("app_qsopartylogger_member_rcvd", (q.memberRcvd ?? "").uppercased())
        r += field("stx_string", q.myLoc.uppercased())
        r += field("srx_string", q.theirLoc.uppercased())
        r += field("contest_id", contest.cabrillo.contest)

        // The location token: a county names its state and county, a bare
        // state token names the state.
        let theirLoc = q.theirLoc.uppercased()
        if let county = counties?.token(for: theirLoc), let state = county.group, let name = county.name {
            r += field("cnty", "\(state),\(name)")
            r += field("state", state)
        } else if TokenSet.usStates.abbrs.contains(theirLoc) {
            r += field("state", theirLoc)
        }
        let myLoc = q.myLoc.uppercased()
        if let county = counties?.token(for: myLoc), let state = county.group, let name = county.name {
            r += field("my_cnty", "\(state),\(name)")
            r += field("my_state", state)
        } else if !myState.isEmpty {
            r += field("my_state", myState)
        }

        // The general contests' elements, by kind.
        for element in contest.exchange where element.kind != .token && element.kind != .rst
            && element.kind != .serial && element.kind != .name && element.kind != .memberOrPower && element.kind != .callEcho {
            let sent = (q.sent[element.id] ?? "").uppercased(), rcvd = (q.rcvd[element.id] ?? "").uppercased()
            switch element.kind {
            case .cqZone: r += field("my_cq_zone", sent); r += field("cqz", rcvd)
            case .ituZone: r += field("my_itu_zone", sent); r += field("ituz", rcvd)
            case .precedence: r += field("precedence", rcvd)
            case .check: r += field("check", rcvd)
            case .classToken: r += field("class", rcvd)
            case .grid: r += field("my_gridsquare", sent); r += field("gridsquare", rcvd)
            case .power:
                if !sent.isEmpty, sent.allSatisfy(\.isNumber) { r += field("tx_pwr", sent) }
                if !rcvd.isEmpty, rcvd.allSatisfy(\.isNumber) { r += field("rx_pwr", rcvd) }
            case .report:
                // A digital report stands in for the RST where the contest has no rst element.
                if !contest.exchange.contains(where: { $0.kind == .rst }) { r += field("rst_rcvd", rcvd) }
            default: break
            }
        }
        // A section token element (Sweepstakes, Field Day): the ARRL section
        // fields — a party's `location` never comes here (its kind is token
        // and its id is `location`).
        for element in contest.exchange where element.kind == .token && element.id == "section" {
            r += field("my_arrl_sect", (q.sent[element.id] ?? "").uppercased())
            r += field("arrl_sect", (q.rcvd[element.id] ?? "").uppercased())
        }
        if writesEntity, let m = CTYTable.shared?.match(callsign: q.call), let code = m.entity.entityCode {
            r += field("dxcc", String(code))
            r += field("cont", m.continent)
        }

        // POTA: one emitted record per (my park × their park) pair — POTA's
        // uploader reads a single park per record from MY_SIG_INFO / SIG_INFO
        // (docs/research/pota/SOURCES.md). A row with no parks takes each loop
        // once and emits zero new fields.
        let myParks: [String?] = (q.myPotaRefs?.isEmpty ?? true) ? [nil] : q.myPotaRefs!.map(Optional.some)
        let theirParks: [String?] = (q.theirPotaRefs?.isEmpty ?? true) ? [nil] : q.theirPotaRefs!.map(Optional.some)
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
    }

    static func adifMode(_ rawMode: String) -> String {
        switch rawMode.uppercased() {
        case "USB", "LSB", "SSB": "SSB"
        default: rawMode.uppercased()
        }
    }
}
```
- [ ] **Step 5: Build, run `ContestExportTests`, `ExportByteIdentityTests`, `CabrilloExporterTests`, `AdifExporterTests`, then the full suite**

Expected: all four classes pass — the byte-identity fixtures through **both** the party overloads and the model — and the full suite `Executed 3030 tests, with 0 failures` (3022 + 8). A byte-identity failure names the fixture; diff the two texts (write both to the scratch folder and `diff`) — the usual culprits are a trailing-space difference on a not-required element, the report column, or `LOCATION:` for the DX entrant.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Export/CabrilloExporter.swift Sources/Core/Export/AdifExporter.swift Tests/Core/ContestExportTests.swift Tests/Core/ExportByteIdentityTests.swift Tests/Core/CabrilloExporterTests.swift QSOPartyLogger.xcodeproj
git commit -m "export: Cabrillo and ADIF derived from the exchange spec on ContestDefinition — party bytes identical, call echo, report column, LOCATION rules, OFFTIME, overlay/time/band headers, zone/entity/section/check/precedence/class/grid/power fields

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: `ContestCatalog` memoised and logging; snapshots, history and the archive export score through it

**Files:**
- Modify: `Sources/Core/Contests/ContestCatalog.swift`, `Sources/Core/History/ScoreSnapshot.swift`, `Sources/Core/History/LogFolder.swift`, `Sources/Core/Models/ContestLog.swift` (`stampingScoreSnapshot`), `Sources/Core/Export/ArchivedLogExport.swift`
- Test: additions to `Tests/Core/ContestCatalogTests.swift`, `Tests/Core/ContestLogScoreSnapshotTests.swift`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/Core/ContestCatalogTests.swift`:
```swift
    func testBundledLoadIsMemoisedAndComplete() {
        let a = ContestCatalog.loadBundled(), b = ContestCatalog.loadBundled()
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.count, 50)
        XCTAssertEqual(ContestCatalog.contest(id: "ksqp")?.id, "ksqp")
        XCTAssertEqual(ContestCatalog.contest(id: "ksqp")?.cabrillo.contest, "KS-QSO-PARTY")
    }
```
Append to `Tests/Core/ContestLogScoreSnapshotTests.swift` (build a log the way that class already does):
```swift
    func testSnapshotIsScoredThroughTheContestCatalogue() throws {
        var log = ContestLog(partyID: "ksqp", myLocation: .outOfState(location: "TX"))
        log.station.callsign = "KE5CW"; log.setupCompleted = true
        log.qsos = [QSO(call: "W0BH", band: .m20, modeClass: .cw, rawMode: "CW", rstSent: "599", rstRcvd: "599",
                        myLoc: "TX", theirLoc: try XCTUnwrap(PartyCatalog.party(id: "ksqp")).counties[0].abbr)]
        let stamped = try XCTUnwrap(log.stampingScoreSnapshot().scoreSnapshot)
        XCTAssertEqual(stamped.figures?.multsByClass, ["county": 1])
        XCTAssertEqual(stamped, ScoreSnapshot.make(log: log, contest: try XCTUnwrap(ContestCatalog.contest(id: "ksqp"))))
        XCTAssertEqual(stamped, ScoreSnapshot.make(log: log, party: try XCTUnwrap(PartyCatalog.party(id: "ksqp"))))
        // A contest this Mac does not know: counts only.
        XCTAssertNil(ScoreSnapshot.best(for: log, contests: { _ in nil }).figures)
        XCTAssertNil(log.stampingScoreSnapshot(contests: { _ in nil }).scoreSnapshot?.figures)
    }
```

- [ ] **Step 2: Run to verify they fail** — build errors on `make(log:contest:)`, `best(for:contests:)`, `stampingScoreSnapshot(contests:)`.

- [ ] **Step 3: `ContestCatalog`** — replace `loadBundled(bundle:)` and add the cache and logger:

```swift
import Foundation
import os

/// Every contest the app knows: the bundled parties, lowered, plus bundled v2
/// files under `Resources/Contests/`, with user files overriding by id from
/// `~/Library/Application Support/QSOPartyLogger/{Parties,Contests}`.
enum ContestCatalog {
    private static let log = Logger(subsystem: "org.b5n.QSOPartyLogger", category: "catalog")
    private static let bundledCache = OSAllocatedUnfairLock<[URL: [ContestDefinition]]>(initialState: [:])

    static var userContestsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/Contests", isDirectory: true)
    }

    /// Bundled parties (lowered) and bundled v2 contests, by name — decoded
    /// once per bundle (its files never change while the app runs). A bundled
    /// file that fails is logged, once, and skipped: it used to vanish from
    /// the catalogue without a word.
    static func loadBundled(bundle: Bundle = .main) -> [ContestDefinition] {
        if let cached = bundledCache.withLock({ $0[bundle.bundleURL] }) { return cached }
        var byID: [String: ContestDefinition] = [:]
        for party in PartyCatalog.loadBundled(bundle: bundle) {
            do { let lowered = try PartyLowering.lower(party); byID[lowered.id] = lowered }
            catch { log.error("bundled party \(party.id, privacy: .public) does not lower: \(error.localizedDescription, privacy: .public)") }
        }
        for url in bundle.urls(forResourcesWithExtension: "json", subdirectory: "Contests") ?? [] {
            do { let contest = try ContestDefinition.decode(try Data(contentsOf: url), bundle: bundle); byID[contest.id] = contest }
            catch { log.error("bundled contest \(url.lastPathComponent, privacy: .public) failed to load: \(error.localizedDescription, privacy: .public)") }
        }
        let contests = byID.values.sorted { $0.name < $1.name }
        bundledCache.withLock { $0[bundle.bundleURL] = contests }
        return contests
    }
```
`loadUserContests`, `all` and `contest(id:bundle:)` stay as they are (user folders are read per call, as `PartyCatalog.party(id:)` always has).

- [ ] **Step 4: `ScoreSnapshot` on the model**

Replace `make(log:party:)` and `best(for:rules:)`:
```swift
    /// Full snapshot via the scoring engine — the same fold the score
    /// sidebar shows, so the dashboard can never disagree with it.
    static func make(log: ContestLog, contest: ContestDefinition) -> ScoreSnapshot {
        let breakdown = ScoreEngine.score(log: log, contest: contest)
        var byMode: [String: Int] = [:]
        var byBand: [String: Int] = [:]
        for (band, modes) in ScoreEngine.bandModeCounts(log: log, contest: contest) {
            for (mode, count) in modes {
                byMode[mode.rawValue, default: 0] += count
                byBand[band.rawValue, default: 0] += count
            }
        }
        return ScoreSnapshot(
            validQSOs: breakdown.validQSOs,
            dupeCount: breakdown.dupeCount,
            invalidModeCount: breakdown.invalidModeCount,
            outOfScopeCount: breakdown.outOfScopeCount,
            qsosByMode: byMode,
            qsosByBand: byBand,
            countiesWorked: breakdown.workedValues(classID: MultClass.county.rawValue).count,
            operatingMinutes: operatingMinutes(timestamps: log.qsos.map(\.timestampUTC)),
            figures: Figures(
                qsoPoints: breakdown.qsoPoints,
                multiplierCount: breakdown.multiplierCount,
                multiplierCap: breakdown.multiplierCap,
                bonusPoints: breakdown.bonusPoints,
                categoryFactor: breakdown.categoryFactor,
                total: breakdown.total,
                multsByClass: breakdown.countsByClassID
            )
        )
    }

    /// The `PartyDefinition` overload: lower, then snapshot on the model.
    static func make(log: ContestLog, party: PartyDefinition) -> ScoreSnapshot {
        make(log: log, contest: PartyLowering.lowered(party))
    }

    /// The best snapshot this Mac can make of a log right now: the engine's
    /// when the contest's rules are installed (`contests`), counts only otherwise.
    static func best(
        for log: ContestLog,
        contests: (String) -> ContestDefinition? = { ContestCatalog.contest(id: $0) }
    ) -> ScoreSnapshot {
        if let contest = contests(log.partyID) {
            make(log: log, contest: contest)
        } else {
            countsOnly(log: log)
        }
    }
```
Update the `Figures.multsByClass` doc comment to `/// Scoped multiplier counts keyed by multiplier class id (\`county\`, \`state\`, …, \`zone\`).`

`ContestLog.stampingScoreSnapshot`:
```swift
    /// The copy the save path writes: `scoreSnapshot` set to this log's
    /// score as of now — the engine's figures when the contest's rules are
    /// installed (`contests`), counts only when they are not — or nil for a
    /// draft (Contest Setup unfinished, or nothing logged yet). Everything
    /// else is untouched.
    func stampingScoreSnapshot(
        contests: (String) -> ContestDefinition? = { ContestCatalog.contest(id: $0) }
    ) -> ContestLog {
        var stamped = self
        stamped.scoreSnapshot = setupCompleted && !qsos.isEmpty
            ? ScoreSnapshot.best(for: self, contests: contests)
            : nil
        return stamped
    }
```
`LogFolder.score(for:)`:
```swift
    static func score(
        for log: ContestLog,
        contests: (String) -> ContestDefinition? = { ContestCatalog.contest(id: $0) }
    ) -> (ScoreSnapshot, ContestRecord.ScoreOrigin) {
        if let saved = log.scoreSnapshot, saved.figures != nil {
            return (saved, .savedWithLog)
        }
        return (ScoreSnapshot.best(for: log, contests: contests), .computedNow)
    }
```
(and its doc: "…one computed now with the rules installed here (a log from an older build, or one saved on a Mac without this contest)"). Grep `rules:` across `Sources` and `Tests` for any remaining caller of the old label and update it.

`ArchivedLogExport`:
```swift
    static func adif(record: ContestRecord, folder: URL?) throws -> Export {
        let loaded = try load(record: record, folder: folder)
        return Export(fileName: loaded.baseName + ".adi", text: AdifExporter.export(log: loaded.log, contest: loaded.contest))
    }

    static func cabrillo(record: ContestRecord, folder: URL?) throws -> Export {
        let loaded = try load(record: record, folder: folder)
        return Export(
            fileName: loaded.baseName + ".log",
            text: CabrilloExporter.export(log: loaded.log, contest: loaded.contest,
                                          score: ScoreEngine.score(log: loaded.log, contest: loaded.contest))
        )
    }

    private static func load(
        record: ContestRecord, folder: URL?
    ) throws -> (log: ContestLog, contest: ContestDefinition, baseName: String) {
        guard let name = record.sourceFileName, let folder,
              let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else {
            throw Failure.logFileMissing
        }
        guard let contest = ContestCatalog.contest(id: record.partyID) else {
            throw Failure.partyNotInstalled
        }
        guard let log = try? ContestLog.decode(from: data) else {
            throw Failure.logUnreadable
        }
        return (log, contest, (name as NSString).deletingPathExtension)
    }
```
(`Failure.partyNotInstalled` keeps its name — `DashboardModel` and its tests read it; its doc becomes "`ContestCatalog` has no rules for the record's contest id.")

- [ ] **Step 5: Build, run the two classes and `ArchivedLogExportTests`, `LogFolderTests`, `DashboardModelExportTests`, then the full suite**

Expected: `Executed 3032 tests, with 0 failures` (3030 + 2).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Contests/ContestCatalog.swift Sources/Core/History/ScoreSnapshot.swift Sources/Core/History/LogFolder.swift Sources/Core/Models/ContestLog.swift Sources/Core/Export/ArchivedLogExport.swift Tests/Core/ContestCatalogTests.swift Tests/Core/ContestLogScoreSnapshotTests.swift
git commit -m "contests: ContestCatalog memoises the bundle and logs failures; score snapshots, the logs-folder history and the archive export score through ContestCatalog

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: Delete the old engine — the party overloads become bridges; the corpus becomes a golden oracle

Order matters: **record the golden file from the old engine first**, then delete it, then prove the bridges reproduce the golden bytes.

**Files:**
- Modify: `Tests/Core/EngineEquivalenceTests.swift` (golden projection, recording test, golden test), `Sources/Core/Engine/ScoreEngine.swift` (replaced below)
- Create (recorded): `Tests/Fixtures/Equivalence/engine-golden.json`

- [ ] **Step 1: The golden projection and the two tests** — append to `Tests/Core/EngineEquivalenceTests.swift` (top level, after `EquivalenceCorpus`):

```swift
/// A `ScoreBreakdown` as a stable, diffable record: row ids become indices
/// into the log, keys become sorted strings.
struct GoldenBreakdown: Codable, Equatable {
    var validQSOs: Int, dupeCount: Int, invalidModeCount: Int, outOfScopeCount: Int, outOfTimeCount: Int
    var qsoPoints: Int, bonusPoints: Int, memberQSOs: Int, qrpQSOs: Int, otherQSOs: Int
    var multiplierCount: Int, multiplierCap: Int?, multiplierFloor: Int, total: Int
    var categoryFactor: ScoreFactor
    var multiplierKeys: [String]
    var dupeRows: [Int], invalidRows: [Int], outOfScopeRows: [Int], newMultRows: [Int]
    var points: [Int]
    var selfActivated: [String]

    init(_ s: ScoreEngine.ScoreBreakdown, rows: [QSO]) {
        let index = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($1.id, $0) })
        func indices(_ ids: Set<UUID>) -> [Int] { ids.compactMap { index[$0] }.sorted() }
        validQSOs = s.validQSOs; dupeCount = s.dupeCount; invalidModeCount = s.invalidModeCount
        outOfScopeCount = s.outOfScopeCount; outOfTimeCount = s.outOfTimeCount
        qsoPoints = s.qsoPoints; bonusPoints = s.bonusPoints
        memberQSOs = s.memberQSOs; qrpQSOs = s.qrpQSOs; otherQSOs = s.otherQSOs
        multiplierCount = s.multiplierCount; multiplierCap = s.multiplierCap; multiplierFloor = s.multiplierFloor; total = s.total
        categoryFactor = s.categoryFactor
        multiplierKeys = s.multiplierKeys.map { "\($0.classID)|\($0.value)|\($0.scope)|\($0.activated ? "A" : "")" }.sorted()
        dupeRows = indices(s.dupeRowIDs); invalidRows = indices(s.invalidRowIDs)
        outOfScopeRows = indices(s.outOfScopeRowIDs); newMultRows = indices(s.newMultRowIDs)
        points = rows.map { s.pointsByRowID[$0.id] ?? -1 }
        selfActivated = s.selfActivatedCounties.sorted()
    }
}

struct GoldenCase: Codable, Equatable {
    let party: String
    let seed: UInt64
    let side: String
    let breakdown: GoldenBreakdown
}
```
And inside `EngineEquivalenceTests`:
```swift
    /// Where the recording test writes (the sandboxed test host cannot touch
    /// the source tree); the shell copies it to `Tests/Fixtures/Equivalence/`.
    static let goldenURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("QPLRecord/Equivalence/engine-golden.json")

    /// Every corpus log scored through the party overload, in a fixed order.
    static func corpusCases() throws -> [GoldenCase] {
        var out: [GoldenCase] = []
        for p in PartyCatalog.loadBundled() {
            for seed in EquivalenceCorpus.seeds {
                for log in EquivalenceCorpus.logs(for: p, seed: seed) {
                    out.append(GoldenCase(party: p.id, seed: seed, side: log.sideID,
                                          breakdown: GoldenBreakdown(ScoreEngine.score(log: log, party: p), rows: log.qsos)))
                }
            }
        }
        return out
    }

    /// Writes the golden file. Recorded once from the engine as it was before
    /// the switch (`TEST_RUNNER_QPL_RECORD_GOLDEN=1`); re-record only for a
    /// deliberate, party-by-party scoring change, never to make a red run green.
    func testRecordGoldenWhenAsked() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QPL_RECORD_GOLDEN"] == "1", "recording is opt-in")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try FileManager.default.createDirectory(at: Self.goldenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(try Self.corpusCases()).write(to: Self.goldenURL, options: .atomic)
        print("QPL_RECORD_GOLDEN_PATH=\(Self.goldenURL.path)")
    }

    /// The permanent oracle: the corpus, scored by the engine that shipped
    /// before the switch, reproduced field by field.
    func testEveryPartyMatchesTheGoldenBreakdowns() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "engine-golden", withExtension: "json"),
                                "missing engine-golden.json — record with TEST_RUNNER_QPL_RECORD_GOLDEN=1")
        let golden = try JSONDecoder().decode([GoldenCase].self, from: Data(contentsOf: url))
        let now = try Self.corpusCases()
        XCTAssertEqual(now.count, golden.count)
        for (g, n) in zip(golden, now) {
            XCTAssertEqual(n.party, g.party); XCTAssertEqual(n.seed, g.seed); XCTAssertEqual(n.side, g.side)
            if n.breakdown != g.breakdown {
                XCTFail("\(g.party) seed \(g.seed) side \(g.side): keys only golden \(Set(g.breakdown.multiplierKeys).subtracting(n.breakdown.multiplierKeys)); only now \(Set(n.breakdown.multiplierKeys).subtracting(g.breakdown.multiplierKeys)); points \(g.breakdown.qsoPoints)/\(n.breakdown.qsoPoints) bonus \(g.breakdown.bonusPoints)/\(n.breakdown.bonusPoints) valid \(g.breakdown.validQSOs)/\(n.breakdown.validQSOs) total \(g.breakdown.total)/\(n.breakdown.total)")
            }
        }
    }
```
(`ScoreFactor` is `Codable`; if `JSONEncoder` cannot encode it at the top level of a struct field, encode `"\(categoryFactor.numerator)/\(categoryFactor.denominator)"` as a `String` instead — check `ScoreFactor.swift` for how it encodes.)

- [ ] **Step 2: Record the golden file from the OLD engine, before touching it**

```bash
xcodegen generate && set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EngineEquivalenceTests/testRecordGoldenWhenAsked TEST_RUNNER_QPL_RECORD_GOLDEN=1 2>&1 | grep -E "Test Case|Executed|error:|QPL_RECORD_GOLDEN_PATH" | tail -5
```
Expected: the recording test passes (not skipped) and prints `QPL_RECORD_GOLDEN_PATH=…/Containers/org.b5n.QSOPartyLogger/Data/tmp/QPLRecord/Equivalence/engine-golden.json`. Then copy it out of the sandbox container and look at it:
```bash
mkdir -p Tests/Fixtures/Equivalence && cp ~/Library/Containers/org.b5n.QSOPartyLogger/Data/tmp/QPLRecord/Equivalence/engine-golden.json Tests/Fixtures/Equivalence/ && ls -la Tests/Fixtures/Equivalence && python3 -c "import json;d=json.load(open('Tests/Fixtures/Equivalence/engine-golden.json'));print(len(d),'cases;',len({c['party'] for c in d}),'parties; first',d[0]['party'],d[0]['breakdown']['total'])"
```
Expected: the file exists (a few hundred KB), ≥ 250 cases over 50 parties. Then `xcodegen generate` again (a new fixture file) and run `EngineEquivalenceTests` in full — the golden test must pass against the old engine it was recorded from (a sanity check that the projection round-trips).

- [ ] **Step 3: Commit the golden file alone**

```bash
git add Tests/Core/EngineEquivalenceTests.swift Tests/Fixtures/Equivalence/engine-golden.json QSOPartyLogger.xcodeproj
git commit -m "tests: engine golden breakdowns — the equivalence corpus scored by the pre-switch engine, recorded as the permanent oracle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Replace `Sources/Core/Engine/ScoreEngine.swift`**

```swift
import Foundation

/// Pure rules-driven scoring: fold the log against a contest definition.
/// Score = QSO points × multipliers × category factors + bonuses.
///
/// The engine itself lives in `ScoreEngine+Contest.swift`, on
/// `ContestDefinition`. The `PartyDefinition` overloads here lower the party
/// (`PartyLowering.lowered`, cached) and delegate, so a QSO party is scored
/// by exactly the same fold as any other contest — every per-party test
/// exercises the general engine through them.
///
/// The category factor may be a fraction (VTQP and WIQP both pay ×1.5 for low
/// power), so it is applied to the `QSO points × multipliers` product and
/// resolved down to a whole number there — **before** bonuses, which the
/// sponsors add afterwards and never scale. Wisconsin states the order
/// outright: *"Then multiply by your multiplier count under MULTIPLIERS.
/// Finally, add your bonus points."*
enum ScoreEngine {

    /// One counted multiplier. `scope` is "" (once), a mode raw value
    /// (perMode), a band raw value (perBand), or "band/mode" (perBandMode).
    struct MultKey: Hashable, Sendable {
        /// The multiplier class — `MultiplierClass.id`. The six party classes
        /// keep `MultClass`'s raw values (`county`, `state`, `province`, `dx`,
        /// `section`, `member`), so persisted snapshots and sidebar keys read
        /// unchanged; a general contest adds `zone`, `country`, `prefix`…
        let classID: String
        let value: String
        let scope: String
        /// Earned by **operating from** the token rather than by working it
        /// (`SideRules.activated`). Defaults false, so every key built before
        /// this existed is unchanged.
        ///
        /// It is part of the key because SCQP 9.2.2 lists "Each South Carolina
        /// county" and "Each SC county activated" as separate numbered
        /// multipliers with no ceiling, so the two must be able to coexist at
        /// the same scope. Where a sponsor forfeits one for the other,
        /// `notOtherwiseWorked` suppresses the activated key instead.
        let activated: Bool

        init(classID: String, value: String, scope: String, activated: Bool = false) {
            self.classID = classID
            self.value = value
            self.scope = scope
            self.activated = activated
        }

        /// The party classes, by enum.
        init(multClass: MultClass, value: String, scope: String, activated: Bool = false) {
            self.init(classID: multClass.rawValue, value: value, scope: scope, activated: activated)
        }

        /// The class as a `MultClass`, for the party-shaped readers (sidebar,
        /// roster); nil for a class the parties do not have.
        var multClass: MultClass? { MultClass(rawValue: classID) }
    }

    struct ScoreBreakdown: Equatable {
        var validQSOs = 0
        var dupeCount = 0
        var invalidModeCount = 0
        var qsoPoints = 0
        var multiplierKeys: Set<MultKey> = []
        var bonusPoints = 0
        /// Valid-QSO counts by the received member element's class — the
        /// three lines the Skeeter Hunt's summary email asks for ("Skeeter
        /// QSOs - 23 / Non-Skeeter QRP QSOs - 5 / Non-Skeeter QRO QSOs").
        /// All zero for every contest without a member-or-power element.
        var memberQSOs = 0
        var qrpQSOs = 0
        var otherQSOs = 0
        var categoryFactor: ScoreFactor = .one
        var outOfScopeCount = 0
        var dupeRowIDs: Set<UUID> = []
        var invalidRowIDs: Set<UUID> = []
        /// Rows the contest gives this entrant no credit for at all — an
        /// out-of-state log's contacts with other out-of-state stations, where
        /// the rules restrict credit to home-state stations (`pairing`).
        var outOfScopeRowIDs: Set<UUID> = []
        /// Rows that added at least one new multiplier when first logged.
        var newMultRowIDs: Set<UUID> = []
        /// Tokens credited by `SideRules.activated` — earned by operating from
        /// them rather than by working them. Empty for every contest without
        /// that rule, which is every party but five and every out-of-state log.
        var selfActivatedCounties: Set<String> = []
        /// Set from the entrant's `SideRules.maxScoredMultipliers` where the
        /// contest pays for fewer multipliers than it recognises (CQP: 58 of 63).
        var multiplierCap: Int?
        /// Set from the entrant's `SideRules.multiplierFloor` — the count that
        /// reaches the score never drops below it (FOBB's printed "Defaults
        /// to … = 1"). 0 everywhere else, which is inert.
        var multiplierFloor = 0
        /// What each row was paid, for the log list's `Pts` column — set for
        /// every row that earned points; a dupe, an invalid-mode row, an
        /// out-of-scope or out-of-time row is absent. The list prints this and
        /// computes nothing of its own (the Skeeter Hunt lesson, 2026-08-16).
        var pointsByRowID: [UUID: Int] = [:]
        /// Rows past the contest's operating-time limit — logged and exported,
        /// unscored (SS 1.2, WPX FAQ). Empty for every contest without a rule.
        var outOfTimeRowIDs: Set<UUID> = []
        var outOfTimeCount: Int { outOfTimeRowIDs.count }
        /// Operating and credited off minutes under the contest's rule; 0 without one.
        var operatedMinutes = 0
        var offMinutes = 0

        /// Multipliers that reach the score. Every key is still tallied in
        /// `multiplierKeys` — the cap limits what is paid for and the floor
        /// holds the product up, neither changing what counts as worked,
        /// which is the sponsors' own distinction.
        var multiplierCount: Int {
            max(min(multiplierKeys.count, multiplierCap ?? .max), multiplierFloor)
        }

        var total: Int {
            categoryFactor.applied(to: qsoPoints * multiplierCount) + bonusPoints
        }

        /// Unique values worked for a class, regardless of scope — for the
        /// sidebar county grid and per-class chips.
        func workedValues(_ multClass: MultClass) -> Set<String> {
            workedValues(classID: multClass.rawValue)
        }

        func workedValues(classID: String) -> Set<String> {
            Set(multiplierKeys.filter { $0.classID == classID }.map(\.value))
        }

        /// Per-class scoped counts for the party classes, for the sidebar breakdown.
        var classCounts: [MultClass: Int] {
            var out: [MultClass: Int] = [:]
            for key in multiplierKeys { if let c = key.multClass { out[c, default: 0] += 1 } }
            return out
        }

        /// Per-class scoped counts by class id — every class, party or not.
        var countsByClassID: [String: Int] {
            Dictionary(grouping: multiplierKeys, by: \.classID).mapValues(\.count)
        }
    }

    // MARK: The party overloads — lower, then the model engine

    static func score(log: ContestLog, party: PartyDefinition) -> ScoreBreakdown {
        score(log: log, contest: PartyLowering.lowered(party))
    }

    /// Would logging this contact add a new multiplier? (Live "NEW MULT" badge.)
    /// A county line's several received locations are several candidate rows.
    static func wouldAddMultiplier(
        theirLocs: [String],
        band: Band,
        modeClass: ModeClass,
        log: ContestLog,
        party: PartyDefinition,
        call: String = "",
        memberRcvd: String? = nil
    ) -> Bool {
        let candidates: [[String: String]] = theirLocs.map { loc in
            var rcvd = [ExchangeElementID.location: loc]
            if let memberRcvd { rcvd[ExchangeElementID.member] = memberRcvd }
            return rcvd
        }
        return wouldAddMultiplier(received: candidates, call: call, band: band, modeClass: modeClass,
                                  log: log, contest: PartyLowering.lowered(party))
    }

    /// Valid (non-dupe, allowed-mode) QSO counts per band and mode class —
    /// the sidebar's "QSOs by band" matrix.
    static func bandModeCounts(log: ContestLog, party: PartyDefinition) -> [Band: [ModeClass: Int]] {
        bandModeCounts(log: log, contest: PartyLowering.lowered(party))
    }

    /// Which of a designated county list this log has valid-QSO credit for —
    /// the predicate behind `.designatedCountySweep`, exposed so the sidebar's
    /// progress readout is the same set the score pays on.
    static func designatedCountiesWorked(
        _ designated: [String], log: ContestLog, party: PartyDefinition
    ) -> Set<String> {
        designatedCountiesWorked(designated, log: log, contest: PartyLowering.lowered(party))
    }

    /// Whether the call-area blackjack target is met by this log's valid rows
    /// — the predicate behind `.callAreaSum`, exposed so the sidebar's badge
    /// is the same computation the score pays on.
    static func callAreaSumAchieved(
        target: Int, log: ContestLog, party: PartyDefinition
    ) -> Bool {
        callAreaSumAchieved(target: target, log: log, contest: PartyLowering.lowered(party))
    }

    // MARK: Shared arithmetic

    /// Internal rather than private so `NeededMult` can ask the same question
    /// the scorer answers. Two implementations of "what does *worked on 20 m*
    /// mean" is a scoring bug factory.
    static func scopeComponent(
        _ scope: PartyDefinition.CountScope, band: Band, modeClass: ModeClass
    ) -> String {
        scope.component(band: band, modeClass: modeClass)
    }

    /// The call-area value of a callsign: its first decimal digit, with 0
    /// worth 10 — "Each call area number is worth that many points with the
    /// '0' area call signs being worth 10 points." A call with no digit
    /// contributes nothing. The first digit is an inference for non-US call
    /// shapes, recorded in the carrying party's notes.
    static func callAreaValue(_ call: String) -> Int? {
        guard let digit = call.first(where: \.isWholeNumber),
              let value = digit.wholeNumberValue
        else { return nil }
        return value == 0 ? 10 : value
    }

    /// Whether some subset of `values` (each usable once) sums to exactly
    /// `target`. Plain 0/1 subset-sum over a boolean table — values are
    /// call-area digits, so both axes stay tiny.
    static func subsetSumsExactly(_ values: [Int], target: Int) -> Bool {
        guard target >= 0 else { return false }
        var reachable = [Bool](repeating: false, count: target + 1)
        reachable[0] = true
        for value in values where value > 0 && value <= target {
            for sum in stride(from: target, through: value, by: -1)
            where reachable[sum - value] {
                reachable[sum] = true
            }
            if reachable[target] { return true }
        }
        return reachable[target]
    }

    /// The designated tokens among the rows' received locations.
    static func designatedCounties(_ designated: [String], workedIn rows: [QSO]) -> Set<String> {
        Set(rows.map { $0.theirLoc.uppercased() })
            .intersection(designated.map { $0.uppercased() })
    }

    static func isRovingCategory(_ category: StationProfile.CategoryStation) -> Bool {
        switch category {
        case .mobile, .rover, .portable, .expedition: true
        case .fixed, .school: false
        }
    }

    /// Would working `value` of `classID` at `scope` raise this log's
    /// multiplier total? Only asked where the entrant's rule forfeits the
    /// activation multiplier on a worked token — everywhere else a key that
    /// is absent is a gain.
    ///
    /// Internal for the same reason as `scopeComponent`: the NEW MULT badge,
    /// the advisor's needed-mult chips and the score itself must agree about
    /// which tokens still pay.
    static func gains(classID: String, value: String, addingScope scope: String, to current: Set<MultKey>) -> Bool {
        let keys = current.filter { $0.classID == classID && $0.value == value }
        let worked = Set(keys.filter { !$0.activated }.map(\.scope))
        let activated = keys.filter(\.activated).count
        let before = worked.count + activated
        let after = worked.union([scope]).count      // the forfeited activation goes to zero
        return after > before
    }

    /// `gains` for the county class — what `NeededMult` asks.
    static func countyGains(_ county: String, addingScope scope: String, to current: Set<MultKey>) -> Bool {
        gains(classID: MultClass.county.rawValue, value: county, addingScope: scope, to: current)
    }
}
```
Everything the old body used privately — `Contribution`, `multContributions`, `locationContributions`, `inScopeRows`, `isHomeStateViaCounty`, `addActivatedCountyMultipliers`, `workedCounty`, the party `bonusPoints`, `scopeComponent(_:row:)` — is gone. `grep -rn "locationContributions\|multContributions\|inScopeRows\|isHomeStateViaCounty" Sources Tests` must come back empty (a test that reached into one of them would have to be reported, not patched).

- [ ] **Step 5: Build, run `EngineEquivalenceTests` (golden green through the bridge), `SalmonRunTests`, `ContestScoreEngineTests`, then the full suite**

Expected: `EngineEquivalenceTests` all green — the golden recorded from the old engine reproduced by the model engine through the bridges; full suite `Executed 3034 tests, with 0 failures` (3032 + 2). The per-party files (70 of them calling `score(log:party:)`) are now the permanent oracle through the bridge. Note the suite time in the commit message.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Engine/ScoreEngine.swift Tests/Core/EngineEquivalenceTests.swift
git commit -m "engine: the PartyDefinition engine is gone — score(log:party:), wouldAddMultiplier, bandModeCounts and the sidebar predicates lower and delegate to the model engine; the golden corpus is the oracle

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: Docs and hand-off

**Files:**
- Modify: `README.md`, `CLAUDE.md`, `docs/superpowers/specs/2026-08-17-general-contest-logger-design.md`, this plan

- [ ] **Step 1: README** — three edits:

1. The `**2971 unit tests**` line: the final count from Task 12's full run.
2. After the paragraph that begins "The general contest model — token sets, sides, exchange elements…" (around line 1023), append a sentence: "Since the engine switch, `ScoreEngine`, the Cabrillo and ADIF exporters and the saved score snapshots run on that model for every log — the party files are lowered into it — and two oracles keep them honest: a golden equivalence corpus (every bundled party, seeded logs on both sides, scored by the pre-switch engine and reproduced field by field) and byte-identity export fixtures for ten party shapes."
3. In the Cabrillo/ADIF feature bullets (around lines 835–845), add to the Cabrillo bullet: "the QSO line is derived from the contest's exchange spec (a call echo, an operating-time `OFFTIME:` list, overlay/time/band headers where a contest has them)"; and to the ADIF bullet: "`CQZ`/`ITUZ`, `ARRL_SECT`, `PRECEDENCE`/`CHECK`/`CLASS`, `GRIDSQUARE`, `DXCC`/`CONT` where a contest carries them". Keep the existing wording of both bullets otherwise.

- [ ] **Step 2: CLAUDE.md** — the layout rows:

- `Sources/Core/Engine/`: "`ScoreEngine` (on `ContestDefinition`; the `PartyDefinition` overloads lower and delegate), `ScoreEngine+Contest`, `ExchangeParser` (entry-row parser, phase 2 retires it), `DupeChecker`, `CountyLineExpander`, `StationMemory`, ESM".
- `Sources/Core/Export/`: "Cabrillo V3, ADIF 3.1.4 — derived from the exchange spec; byte-identity fixtures under `Tests/Fixtures/Exports`".
- Add a bullet under **Read this first** point 4 or a new point 10: "**The engine is the model.** Scoring, exporting and snapshots read `ContestDefinition` only; a party's rules reach them through `PartyLowering`. A change to how any party scores must show up as a golden-corpus diff (`Tests/Fixtures/Equivalence/engine-golden.json`) or an export-fixture diff, re-recorded on purpose in that party's own commit — never to make a red run green."

- [ ] **Step 3: The spec** — in `docs/superpowers/specs/2026-08-17-general-contest-logger-design.md`:

- **Progress**: mark "Phase 1b (the engine switch) — DONE" with the plan link, the final test count, and the branch; note what stays for phase 2 (`ExchangeParser`, `MyLocation`, `MultClass` as ids, `MultiplierRoster`/`NeededMult` party-shaped, `family` on the four non-state parties, VTQP bonus `sides` as its own party commit).
- **Carried into the engine-switch plan**: retitle "Resolved in the engine-switch plan" and replace the bullets with a one-line resolution each (copy the "Decisions this plan settles" table's right column).
- §1.2 `MultiplierClass` resolver table: add `callsignOverrides` to the `dxccEntity` row; `CabrilloSpec`: add `reportColumn`. §1.4 item 8: `MultKey.classID` (with `multClass` as a view), `countsByClassID`, `outOfTimeRowIDs`/`operatedMinutes`/`offMinutes`. §1.5: `sideID` + `sentExchange` with the party views kept; `selectedObjectives`, `declaredBonuses`; `StationProfile.categoryBand`.

- [ ] **Step 4: This plan** — add a `> **Status: COMPLETE (date)**` block under the header in the style of Plan 1's: every task done, the final count, every deviation the reviews made from the code blocks above (the code is authoritative), and **Next:** phase 2 (UI generalisation), Plan 3, not yet written.

- [ ] **Step 5: Full suite one last time, then commit**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|error:|failed" | tail -3
git add README.md CLAUDE.md docs/superpowers/specs/2026-08-17-general-contest-logger-design.md docs/superpowers/plans/2026-08-17-general-contest-logger-engine-switch.md
git commit -m "docs: engine switch landed — README oracle note and test count, CLAUDE.md engine/export rows and the golden-corpus rule, spec progress and resolved carried items, plan status

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

## Self-review

- **Spec coverage.** §1.4 items 1–8: mode (Task 7 `classify`, incl. `allowedRawModes`), pairing (7), operating time (7 + 5's `offPeriods`), dupes on `DupeRule` (7), points by rule (7), multipliers per class with resolvers/caps/granted/activated (7), bonuses + factors + declared bonuses (7), breakdown fields (7 + 12). §1.5 `QSO` maps (3), `ContestLog` (4), `StationProfile` additions (4), `ScoreSnapshot.multsByClass` by class id (11). §2.6 Cabrillo/ADIF (10). "Testing": lowering equivalence corpus (9) → golden (12); byte-identity fixtures recorded before the switch and asserted after (2, 10); the 2,971 through `score(log:party:)` (bridges, 12); per-kind/unit tests for the new pieces (5, 7, 8, 10). "Carried" list: each row of the decisions table names its task. §2.4/2.5 (macros, call-history map) and §2.1–2.3 are UI — phase 2 by the spec's own delivery order — and §1.4's "`ExchangeParser` becomes `ExchangeValidator`" is the entry row's switch, also phase 2; both are stated as kept.
- **Placeholders.** None: every step carries its code; the two "if the literal does not decode" notes give the exact fallback.
- **Type consistency.** `MultKey(classID:value:scope:activated:)` and `MultKey(multClass:…)` (7, 12); `ScoreEngine.classify` / `Classified` (7, 8, 10); `wouldAddMultiplier(received:call:band:modeClass:log:contest:)` (8, 9, 12); `bandModeCounts(log:contest:)`, `designatedCountiesWorked(_:log:contest:)`, `callAreaSumAchieved(target:log:contest:)` (8, 9, 11, 12); `PartyLowering.lowered(_:)` non-throwing (6, 10, 11, 12); `ExchangeValidator.owningSet(of:element:contest:side:bundle:)` (5, 7); `ContestDefinition.resolvedSideID(_:)`, `countyRoster(bundle:)`, `receivedElements(for:includingCallEcho:)` (5, 7, 10, 11); `Resolver.callsignOverrides` (5, 6, 7); `CabrilloSpec.reportColumn` (5, 6, 10); `OperatingTime.OffPeriod` / `Result.offPeriods` (5, 10); `ContestLog.sideID` / `sentExchange` / `selectedObjectives` / `declaredBonuses` / `categoryValues` (4, 7, 10); `StationProfile.categoryBand/Overlay/Time/exchangeDefaults` (4, 10); `ExchangeElementID` (3, 4, 7, 10, 12); `ScoreSnapshot.make(log:contest:)`, `best(for:contests:)`, `stampingScoreSnapshot(contests:)`, `LogFolder.score(for:contests:)` (11); `CabrilloExporter.export(log:contest:score:)`, `qsoLine(_:myCall:contest:side:)`, `location(log:contest:)`, `AdifExporter.export(log:contest:)` (10, 11).


# Contest Score Caching & Entry Invalidation Fencing — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the entry row responsive at thousands of QSOs by folding the log once per change instead of ~4× per keystroke, and by fencing typing off from the rest of the window.

**Architecture:** Three additive layers. (1) The engine gains cheap overloads — `wouldAddMultiplier(current:)` and `existingDupePairs(logged:)` — that answer against a caller-supplied key set instead of rescoring; the existing overloads delegate to them, so behavior is equal by construction. (2) A new App-layer `LiveScore` (@MainActor @Observable) lazily folds once per `LogDocument.generation` bump and serves the breakdown, band/mode counts, dupe-key sets, and worked-call sets to every reader. (3) A new `EntrySection` child view absorbs every `EntryState` read that today sits in `MainView.body` (plus the per-keyDown readout, moved to a small `KeyReadout` object), so a keystroke invalidates only the entry cluster.

**Tech Stack:** Swift 6, SwiftUI + Observation macro, XCTest. Build/test via `xcodegen generate` + `xcodebuild test` (see CLAUDE.md). Perf harness: `Tests/Core/ContestScalePerfTests.swift`.

**Measured baseline (Release, 2026-08-30):** one fold 7.3 ms @2k QSOs; one exchange keystroke ≈ 37 ms; body pass ≈ 29.5 ms; per-commit ≈ 45 ms + band-map refolds. Target: keystroke engine work < 1 ms, one fold per log change.

**Constitution guardrails:** engine changes are additive; the golden corpus and export fixtures must not change; no party-specific branching enters `Sources/UI/`; every commit regenerates the pbxproj (`xcodegen generate`); README test count updates with the last commit.

---

### Task 0: Commit the baseline harness

**Files:**
- Already created: `Tests/Core/ContestScalePerfTests.swift`

- [ ] **Step 0.1:** `xcodegen generate`, run the harness once to confirm green in Debug:
  `xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ContestScalePerfTests` → `Executed 1 test, with 0 failures`.
- [ ] **Step 0.2:** Commit:
  ```bash
  git add Tests/Core/ContestScalePerfTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
  git commit -m "tests: contest-scale performance baselines for the entry and render hot paths"
  ```

### Task 1: Engine — answer NEW MULT and dupes against a supplied key set

**Files:**
- Modify: `Sources/Core/Engine/ScoreEngine+Contest.swift` (wouldAddMultiplier, ~:510)
- Modify: `Sources/Core/Engine/ScoreEngine.swift` (party overload, ~:149)
- Modify: `Sources/Core/Engine/DupeChecker.swift` (existingDupePairs, ~:38)
- Test: `Tests/Core/ScoreEngineCachedKeysTests.swift` (new)

- [ ] **Step 1.1: Write the failing test** (new file):

```swift
import XCTest
@testable import QSOPartyLogger

/// The cheap overloads — the NEW MULT badge and the dupe warning answered
/// against a caller-supplied key set — must agree exactly with the
/// re-scoring overloads they replace on the hot path.
final class ScoreEngineCachedKeysTests: XCTestCase {

    var ksqp: PartyDefinition!
    var counties: [String] = []

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"))
        counties = ksqp.counties.map(\.abbr)
    }

    func makeLog(rows: Int) -> ContestLog {
        var log = ContestLog(partyID: "ksqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let start = Date(timeIntervalSince1970: 1_788_000_000)
        let bands: [Band] = [.m20, .m40]
        log.qsos = (0..<rows).map { i in
            QSO(timestampUTC: start.addingTimeInterval(Double(i) * 60),
                call: "W0X\(String(format: "%03d", i % 97))",
                band: bands[i % 2], modeClass: .cw, rawMode: "CW", freqKHz: 14040,
                rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: counties[i % 40])
        }
        return log
    }

    func testCheapBadgeMatchesFullRescore() {
        let log = makeLog(rows: 300)
        let current = ScoreEngine.score(log: log, party: ksqp).multiplierKeys
        for county in [counties[0], counties[39], counties[80]] {
            for band in [Band.m20, .m15] {
                for mode in [ModeClass.cw, .phone] {
                    let slow = ScoreEngine.wouldAddMultiplier(
                        theirLocs: [county], band: band, modeClass: mode,
                        log: log, party: ksqp)
                    let fast = ScoreEngine.wouldAddMultiplier(
                        theirLocs: [county], band: band, modeClass: mode,
                        log: log, party: ksqp, current: current)
                    XCTAssertEqual(slow, fast, "\(county) \(band) \(mode)")
                }
            }
        }
    }

    func testCheapDupePairsMatchFullScan() {
        let log = makeLog(rows: 300)
        let logged = Set(log.qsos.map(DupeChecker.key))
        for (call, county) in [("W0X001", counties[1]), ("NOTINLOG", counties[2])] {
            let slow = DupeChecker.existingDupePairs(
                call: call, band: .m20, modeClass: .cw,
                myLocs: ["TX"], theirLocs: [county], log: log.qsos)
            let fast = DupeChecker.existingDupePairs(
                call: call, band: .m20, modeClass: .cw,
                myLocs: ["TX"], theirLocs: [county], logged: logged)
            XCTAssertEqual(slow.map { "\($0.myLoc)|\($0.theirLoc)" },
                           fast.map { "\($0.myLoc)|\($0.theirLoc)" })
        }
    }

    func testCheapBadgeHonorsScoredCeiling() throws {
        // A synthetic current set at the side's ceiling: nothing further is new.
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        let contest = PartyLowering.lowered(cqp)
        var log = ContestLog(partyID: "cqp")
        log.station.callsign = "KE5CW"
        log.myLocation = .outOfState(location: "TX")
        let side = contest.resolvedSideID(log.sideID)
        guard let cap = contest.rules(for: side).maxScoredMultipliers else {
            throw XCTSkip("CQP no longer declares a scored ceiling for this side")
        }
        let full = Set((0..<cap).map {
            ScoreEngine.MultKey(multClass: .county, value: "FAKE\($0)", scope: "")
        })
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["SBAR"], band: .m20, modeClass: .cw,
            log: log, party: cqp, current: full))
    }
}
```

- [ ] **Step 1.2: Run it — expect compile failure** (no `current:`/`logged:` overloads yet).
- [ ] **Step 1.3: Implement.** In `ScoreEngine+Contest.swift`, split `wouldAddMultiplier(received:...)`: the existing signature computes `current` via one fold and delegates; a new overload takes `current: Set<MultKey>` and contains the previous body unchanged from the cap-check down. In `ScoreEngine.swift`, add the party-level `current:` overload delegating through `PartyLowering.lowered`. In `DupeChecker.swift`, split `existingDupePairs`: existing signature builds `Set(log.map(key))` and delegates to a new `logged: Set<DupeKey>` overload holding the loop.
- [ ] **Step 1.4: Run** the new test class + the engine-adjacent suites (`NeededMultTests`, equivalence corpus) → PASS, corpus untouched.
- [ ] **Step 1.5: Commit** `engine: NEW MULT and dupe checks can answer against a supplied key set`.

### Task 2: EntryState.revalidate accepts cached keys

**Files:**
- Modify: `Sources/App/EntryState.swift` (`revalidate(party:...)` :337, `revalidate(contest:...)` :383, `updateDupeWarning` :411)
- Test: `Tests/App/EntryStateCachedKeysTests.swift` (new)

- [ ] **Step 2.1: Failing test:** badge + dupe warning identical with and without supplied keys, on a small KSQP log (worked county → dupe warning + no badge; fresh county → badge, no warning). Also the v2 path with `loggedRuleKeys` on the bundled `pota` contest.
- [ ] **Step 2.2:** Add trailing optional parameters, all defaulting to nil (every existing caller and test compiles unchanged):
  - `revalidate(party:log:band:modeClass:currentMultKeys: Set<ScoreEngine.MultKey>? = nil, loggedDupeKeys: Set<DupeChecker.DupeKey>? = nil)` — badge: `if let currentMultKeys` → cheap overload, else legacy; pass `loggedDupeKeys` through to `updateDupeWarning`.
  - `revalidate(contest:log:band:modeClass:now:loggedRuleKeys: Set<DupeChecker.RuleKey>? = nil)` — use supplied set instead of `Set(log.qsos.map { DupeChecker.key($0, rule:) })` when present.
- [ ] **Step 2.3:** Run new tests + `EntryFlowTests` → PASS.
- [ ] **Step 2.4: Commit** `entry: revalidation can reuse the log's current multiplier and dupe keys`.

### Task 3: LogDocument.generation + LiveScore

**Files:**
- Modify: `Sources/App/LogDocument.swift:37` (`var log` gains didSet; new `generation`)
- Create: `Sources/App/LiveScore.swift`
- Test: `Tests/App/LiveScoreTests.swift` (new)

- [ ] **Step 3.1: Failing tests:**

```swift
@MainActor func makeDocument(rows: Int) -> LogDocument { /* seeded KSQP log, as Task 1 */ }

// generation: bumps on any log mutation, not on reads
// breakdown/bandModeCounts/dupeKeys match the engine computed directly
// foldCount: three property reads → 1; append → next read → 2; read again → 2
// party change via log.partyID → refold reflects the new party
// v2 (pota): ruleDupeKeys present and correct; party logs: nil
// workedCalls(band:modeClass:)/workedCallCounties match hand-built sets, cached per generation
```

- [ ] **Step 3.2:** `LogDocument`: `private(set) var generation = 0`; `var log: ContestLog { didSet { generation &+= 1 } }` (the BandMapModel didSet-on-@Observable pattern).
- [ ] **Step 3.3:** `LiveScore.swift`:

```swift
import Foundation
import Observation

/// The one score fold per log change, shared by every reader.
///
/// Before this existed the sidebar, the log table's flags, the advisor, the
/// NEW MULT badge and the band map each folded the whole log themselves —
/// 7 ms a fold at 2,000 rows, roughly four folds per keystroke
/// (`Tests/Core/ContestScalePerfTests.swift`). Now the fold runs lazily, once,
/// on the first read after a change; every other read is a cache hit. A view
/// that reads these properties observes `document.generation`, so it renders
/// when the log changes — never per keystroke.
@MainActor
@Observable
final class LiveScore {
    private let document: LogDocument

    /// Catalog lookups, injectable so tests state definitions directly.
    @ObservationIgnored var partyResolver: (String) -> PartyDefinition? = { PartyCatalog.party(id: $0) }
    @ObservationIgnored var contestResolver: (String) -> ContestDefinition? = { ContestCatalog.contest(id: $0) }

    /// How many times the engine has folded — the cache's test seam.
    @ObservationIgnored private(set) var foldCount = 0

    init(document: LogDocument) { self.document = document }

    var breakdown: ScoreEngine.ScoreBreakdown { refreshed().breakdown }
    var multiplierKeys: Set<ScoreEngine.MultKey> { refreshed().breakdown.multiplierKeys }
    var bandModeCounts: [Band: [ModeClass: Int]] { refreshed().bandModeCounts }
    /// Party dupe keys (`DupeChecker.key(_:)`) for the live dupe warning.
    var dupeKeys: Set<DupeChecker.DupeKey> { refreshed().dupeKeys }
    /// Rule-keyed dupes for a v2-only contest (POTA); nil while a party is live.
    var ruleDupeKeys: Set<DupeChecker.RuleKey>? { refreshed().ruleDupeKeys }

    func workedCalls(band: Band, modeClass: ModeClass) -> Set<String>
    func workedCallCounties(band: Band, modeClass: ModeClass) -> Set<String>
    // both from one filtered pass, memoised per band|mode within a generation

    private struct Cache { … generation, partyID, breakdown, bandModeCounts, dupeKeys, ruleDupeKeys }
    @ObservationIgnored private var cache: Cache?
    @ObservationIgnored private var partyCache: (id: String, party: PartyDefinition?)?
    @ObservationIgnored private var contestCache: (id: String, contest: ContestDefinition?)?
    @ObservationIgnored private var workedCache: (generation: Int, sets: [String: (calls: Set<String>, counties: Set<String>)])?

    private func refreshed() -> Cache {
        let generation = document.generation          // observed → view dependency
        if let cache, cache.generation == generation, cache.partyID == document.log.partyID { return cache }
        // fold via party, else contest, else empty; build dupe sets; foldCount += 1
    }
}
```

  The cache stores are `@ObservationIgnored` (the BandMapModel rule: derived data written during body must not invalidate).
- [ ] **Step 3.4:** Run `LiveScoreTests` → PASS. `xcodegen generate` for the new file.
- [ ] **Step 3.5: Commit** `app: LiveScore — one score fold per log change, shared by every reader`.

### Task 4: Wire the readers

**Files:**
- Modify: `Sources/UI/MainView.swift` (`score` :255, worked-call helpers :465-492, sidebar call :368, onAppear wiring ~:1283, bandMapModel creation)
- Modify: `Sources/UI/ScoreSidebar.swift:57-58` (optional `bandModeCounts` param)
- Modify: `Sources/App/EntryFlow.swift` (`revalidate` :750; three `@ObservationIgnored` closures)
- Modify: `Sources/UI/BandMap.swift` (`verdict(for:)` :157; closure property)

- [ ] **Step 4.1:** MainView: `@State private var liveScore: LiveScore`, `_liveScore = State(initialValue: LiveScore(document: document))`; `private var score: … { liveScore.breakdown }`; `workedCalls(on:)`/`workedCallCounties(on:)` delegate to `liveScore` (passing `currentModeClass`); pass `bandModeCounts: liveScore.bandModeCounts` to `ScoreSidebar` (new optional param, `?? ScoreEngine.bandModeCounts(...)` inside for the dashboard's uses).
- [ ] **Step 4.2:** EntryFlow gains
  ```swift
  @ObservationIgnored var currentMultKeys: () -> Set<ScoreEngine.MultKey>? = { nil }
  @ObservationIgnored var loggedDupeKeys: () -> Set<DupeChecker.DupeKey>? = { nil }
  @ObservationIgnored var loggedRuleKeys: () -> Set<DupeChecker.RuleKey>? = { nil }
  ```
  passed into both `entry.revalidate` calls. MainView wires them in `onAppear` next to `flow.parkOnBoard` (:1326): `flow.currentMultKeys = { [weak liveScore] in liveScore?.multiplierKeys }` etc.
- [ ] **Step 4.3:** BandMapModel: `@ObservationIgnored var currentMultKeys: () -> Set<ScoreEngine.MultKey>? = { nil }`; `verdict(for:)` uses the cheap overload when the closure answers. Wire where MainView creates/configures the model.
- [ ] **Step 4.4:** Full suite → green. Re-run harness (numbers unchanged — it measures primitives — but the suite proves the wiring).
- [ ] **Step 4.5: Commit** `ui: every score reader shares LiveScore's one fold per change`.

### Task 5: EntrySection + KeyReadout — fence typing off

**Files:**
- Create: `Sources/UI/EntrySection.swift`
- Modify: `Sources/UI/KeyDiagnostics.swift` (add `KeyReadout` @MainActor @Observable: `var lastKeyReadout: String?`, `var fRowNotice: String?`)
- Modify: `Sources/UI/MainView.swift` (leftPaneContent :525-603, keyNoticeStrip :609-676, entry computeds :141-179, messageKeys :228, workedBefore cluster :433-462, monitor writes :2366-2412, logTable frame :826)

- [ ] **Step 5.1:** `KeyReadout` object; MainView holds `@State private var keyReadout = KeyReadout()`; `noteKeyDown`/media monitor write it; delete the two `@State` vars.
- [ ] **Step 5.2:** `EntrySection` view owning, verbatim from MainView: EntryBar + its five `.onChange` wires, `parkCaption`, `callbookCaption`, `callFrameColor`, superCheckStrip, MessagesRow + `messageKeys` + `pendingMessageIndex` + `phoneKeysSilentNotice`, keyNoticeStrip (reading `keyReadout`, `exportNotice` binding), the WorkedBeforeTable block, and `workedBefore`/`workedBeforeArchiveLine`/`workedBeforeHeight` — the height reported up through `@Binding var workedBeforeHeight: CGFloat` via `.onChange(of:initial:)`. Dependencies in: `document`, `flow`, `settings`, `radio`, `callbookClient`, `potaParkClient`, `keyReadout`, `context: () -> EntryFlow.Context`, focus binding, repeat/cq bindings + handlers. `party`/`layout` computed inside from `flow`/`document`.
- [ ] **Step 5.3:** MainView's `leftPaneContent` shrinks to radioBar / stationStrip+onChange / `EntrySection(...)` / Divider / logTable; `logTable`'s `.frame(minHeight:)` reads the new `@State workedBeforeHeight`. Remove the now-moved computeds from MainView. **MainView.body must end with zero reads of `entry.*` — verify by grep.**
- [ ] **Step 5.4:** `xcodegen generate`; full suite → green (EntryLayout/caret/shortcut/key tests especially). Window-minimum tests (`WindowSizeTests`) guard the layout contract.
- [ ] **Step 5.5: Commit** `ui: typing invalidates the entry section, not the window`.

### Task 6: After-numbers and docs

**Files:**
- Modify: `Tests/Core/ContestScalePerfTests.swift` (add `revalidateCached` + cached-body-pass columns)
- Modify: `README.md` (test count; a line under performance/features if the README has a natural home for it)

- [ ] **Step 6.1:** Harness: measure `entry.revalidate(... currentMultKeys: keys, loggedDupeKeys: dupes)` and a cached body pass (2 breakdown reads + counts read + 1 workedContacts + table sort) → print `PERF` columns.
- [ ] **Step 6.2:** Run harness Debug + Release; record numbers in the commit message.
- [ ] **Step 6.3:** README test count + docs. **Commit** `perf: keystroke engine work reads the cached fold — measured before/after`.

## Addendum 2026-08-31 — the deferred fixes (4-6), approved after the on-air look

Tasks 1-6 shipped and merged (master b2f3aed). These four tasks finish the
per-contact and background costs the first phase deliberately left.

### Task 7: Log table rows and group sizes once per change

- LiveScore gains `displayRows: [QSO]` (newest-first) + `groupSizes: [UUID: Int]`,
  memoised per generation in their own cache slot (no fold). Tests in
  LiveScoreTests: order (newest first, stable ties), counts, generation refresh.
- LogTable's `qsos` param becomes `rows: [QSO]` + `groupSizes: [UUID: Int]`;
  `selectedRows` = `rows.reversed().filter…` (identical order to today);
  the computed properties go. One caller (MainView:600) updated.
- Commit: `ui: the log table's rows and group sizes are computed once per change`.

### Task 8: Catalog user folders re-read only when they change

- `PartyCatalog.loadUserParties()` / `ContestCatalog.loadUserContests(in:)` get a
  stat-stamp memo: `[URL: (stamp: [Entry(name, size, mtime)], results)]` behind
  an `OSAllocatedUnfairLock`, keyed by directory. Same stamp → cached results;
  any add/remove/edit (size or mtime moves) → full reload. Content edits in
  place are caught by per-file mtime, which a directory-mtime key would miss.
- Tests: temp-dir — same contents twice returns identical results without
  re-decoding (observable via a decode-count hook? No — assert correctness +
  a mutated file IS picked up; the cache is an optimisation, correctness is
  the contract), and an edited file's new definition is returned.
- Commit: `catalog: user party and contest folders re-read only when they change`.

### Task 9: The stamped snapshot reuses the window's fold

- `ScoreSnapshot.make(breakdown:bandModeCounts:log:)` — the parts form; the
  existing `make(log:contest:)` computes the parts and delegates (byte-identical
  by construction).
- `ContestLog.stampingScoreSnapshot(using:)` — stamps a caller-supplied
  snapshot under the same draft rule (unfinished setup / empty log → nil).
- `LogDocument`: `typealias Snapshot = SaveSnapshot` (`{ log, score:
  ScoreSnapshot? }`); `snapshot(contentType:)` captures
  `scoreSnapshotProvider?()` (a window-wired closure; guarded
  `Thread.isMainThread` + `MainActor.assumeIsolated`, returns nil off-main or
  when LiveScore has no rules — nil falls back to the legacy compute).
  `dataForSaving(_:score:)` uses the supplied snapshot when present.
- MainView wires the provider in `onAppear` next to the flow closures.
- Tests: bytes of `dataForSaving(log, score: parts-built)` == legacy bytes on a
  seeded KSQP log; draft logs stamp nil either way; nil provider = legacy.
- Commit: `save: the stamped snapshot reuses the window's fold`.

### Task 10: The SCP scan comes off the main actor in the window

- `EntryFlow.scpScanMode: .immediate` (default — every existing test and the
  synchronous contract unchanged) `/ .background` (the window): the scan runs
  in `Task.detached`, the result applies on the main actor only if the
  fragment still stands (stale scans drop; newest fragment wins).
- MainView sets `.background` in `onAppear`.
- Test: background mode eventually publishes matches for the final fragment
  (poll with timeout); immediate mode covered by the existing 11 assertions.
- Commit: `scp: the strip's scan leaves the main actor in the window`.

README test count updates in the last commit; full suite before each commit's
push of responsibility. Same guardrails as Tasks 1-6.

## Self-Review

- Spec coverage: fix 1 → Tasks 3-4; fix 2 → Tasks 1-2 + 4.3; fix 3 → Task 5; evidence → Tasks 0, 6. ✓
- Placeholders: Task 3.3 elides two function bodies and the Cache struct fields to their named contents — acceptable inline elisions, resolved by the surrounding contract; no TBDs. ✓
- Type consistency: `Set<ScoreEngine.MultKey>`, `Set<DupeChecker.DupeKey>`, `Set<DupeChecker.RuleKey>`, `[Band: [ModeClass: Int]]` used uniformly across Tasks 1-5. ✓

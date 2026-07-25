# Sending the QSO Number, Cut Numbers, and the Operating-Mode Default — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the already-generated QSO number actually go out on the air, add an opt-in `1→A` cut number, and default the operating mode from the operator's in-state/out-of-state location.

**Architecture:** Three independent changes, three commits. (1) `MessageSets.defaults(for:)` derives the F1–F8 macros from the two exchange flags a party already carries, replacing two fixed constants; `LogDocument` re-derives untouched macro sets when the party changes or a log is opened, and the messages editor warns rather than rewrites when they were customised. (2) `AppSettings.applyCutNumbers` gains a `cutOne` parameter behind a new `cwCutNumberOne` default. (3) `operatingMode` moves from `MainView`'s `@State` into `ContestLog`, decoding to a location-derived default when absent.

**Tech Stack:** Swift 6, SwiftUI, macOS 15+, XCTest. XcodeGen owns the project file — `project.yml` globs `Tests/`, so **any new test file requires `xcodegen generate` before it will build.**

**Spec:** [`docs/superpowers/specs/2026-07-25-serial-macros-cut-numbers-mode-default-design.md`](../specs/2026-07-25-serial-macros-cut-numbers-mode-default-design.md)

**Baseline:** 586 tests, 0 failures, `** TEST SUCCEEDED **` at commit `caaec73`.

---

## File Structure

| File | Responsibility | Commit |
| --- | --- | --- |
| `Sources/Core/Models/ContestLog.swift` | `MessageSets.defaults(for:)`, `mentions(_:)`, `contradicts(_:)`; later `ContestLog.operatingMode` | 1, 3 |
| `Sources/App/LogDocument.swift` | untouched-set upgrade on party change and on open; flip-only mode re-derivation | 1, 3 |
| `Sources/UI/MessagesEditor.swift` | `{SERIAL}` in the macro list, party-aware Restore Defaults, mismatch warning, cut-number controls | 1, 2 |
| `Sources/App/AppSettings.swift` | `cwCutNumberOne`, `applyCutNumbers(_:cutOne:)`, corrected doc comments | 2 |
| `Sources/UI/MainView.swift` | pass `cutOne` to macro expansion; bind `$document.log.operatingMode` | 2, 3 |
| `Tests/Core/MessageDefaultsTests.swift` | **new** — the defaults table, the 16-party byte-identity proof, `contradicts` | 1 |
| `Tests/App/LogDocumentTests.swift` | upgrade-on-change, upgrade-on-open, undo, mode re-derivation | 1, 3 |
| `Tests/Core/SerialExchangeTests.swift` | cut-number expansion | 2 |
| `Tests/Core/ModelTests.swift` | `operatingMode` decode / derive / round-trip | 3 |
| `README.md` | features, macro table, cut numbers, mode default, test count | 1, 2, 3 |

Nothing else changes. No party JSON, no `ScoreEngine`, no exporter, no radio driver.

---

# Commit 1 — Party-aware CW message defaults

### Task 1: `MessageSets.defaults(for:)`, `mentions(_:)`, `contradicts(_:)`

> **Amended during execution, 2026-07-25.** Code review found that a `Bool`
> return forces the consumer in Task 3 to re-derive *which* condition fired,
> duplicating both clauses and silently mis-wording the warning if a third is
> added. `contradicts(_:) -> Bool` therefore shipped as
> `exchangeMismatch(with:) -> ExchangeMismatch?`, with cases `.missingSerial`,
> `.extraneousRST`, and a third the review identified as reachable —
> `.missingRST`, a report party whose macros send no report, which happens when
> an operator types `{SERIAL}` into a report party's macros and it expands to
> nothing. Task 3's `mismatchWarning` below switches exhaustively over it.
> The `contradicts` signature in Step 4 and the five `testContradicts*` methods
> in Step 1 are superseded; everything else in this task shipped as written.

**Files:**
- Modify: `Sources/Core/Models/ContestLog.swift:10-40`
- Create: `Tests/Core/MessageDefaultsTests.swift`

- [ ] **Step 1: Write the failing test**

Create `Tests/Core/MessageDefaultsTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// Default F1–F8 macros follow the party's exchange shape. Three bundled
/// parties send no signal report: CQP and PAQP send a QSO number instead
/// ("QSO number and 4-letter county abbreviation"), and MDC sends call and
/// location only ("You give your Call Sign and Location to each contacted
/// station"). A fixed {RST} default keys a report their sponsors do not want.
/// See docs/superpowers/specs/2026-07-25-serial-macros-cut-numbers-mode-default-design.md
final class MessageDefaultsTests: XCTestCase {

    /// The sixteen parties whose exchange carries a report and no number,
    /// named so a party cannot change shape unnoticed.
    static let rstPartyIDs = [
        "alqp", "azqp", "coqp", "hqp", "iaqp", "ilqp", "ksqp", "meqp",
        "nhqp", "njqp", "nyqp", "ohqp", "sdqp", "tnqp", "tqp", "warun",
    ]

    /// A synthetic party, so the both-flags shape can be pinned without
    /// waiting for a sponsor to publish one.
    func party(_ extra: String) throws -> PartyDefinition {
        let json = """
        {"schemaVersion":1,"id":"n","name":"N","cabrilloContest":"N","homeState":"KS",
        "countyAbbrLength":3,"validBands":["40m"],"points":{"phone":1,"cw":1,"digital":1},
        "dupeScope":"bandMode",
        "multipliers":{"inState":{"classes":["state"],"homeStateCountsViaCounty":false,"countScope":"once"},
        "outState":{"classes":["county"],"homeStateCountsViaCounty":false,"countScope":"once"}},
        "bonuses":[],"counties":[{"abbr":"ALL","name":"Allen"}]\(extra)}
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    // MARK: The table

    /// The Article 4 proof: every party that was correct before this change
    /// resolves to the exact macros it shipped with.
    func testTheSixteenReportPartiesKeepTheShippedDefaults() throws {
        XCTAssertEqual(Self.rstPartyIDs.count, 16)
        for id in Self.rstPartyIDs {
            let p = try XCTUnwrap(PartyCatalog.party(id: id), id)
            XCTAssertEqual(MessageSets.defaults(for: p), MessageSets.standard,
                           "\(id) must keep the macros it shipped with")
        }
    }

    func testSerialPartiesSendTheNumberInsteadOfAReport() throws {
        for id in ["cqp", "paqp"] {
            let sets = MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: id)))
            XCTAssertEqual(sets.run[1], "{CALL} {SERIAL} {EXCH}", id)
            XCTAssertEqual(sets.searchPounce[1], "{SERIAL} {EXCH}", id)
            XCTAssertEqual(sets.searchPounce[6], "R {SERIAL} {EXCH}", id)
            XCTAssertFalse(sets.mentions("{RST}"), "\(id) exchanges no report")
        }
    }

    func testMDCSendsCallAndLocationOnly() throws {
        let sets = MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "mdc")))
        XCTAssertEqual(sets.run[1], "{CALL} {EXCH}")
        XCTAssertEqual(sets.searchPounce[1], "{EXCH}")
        XCTAssertEqual(sets.searchPounce[6], "R {EXCH}")
        XCTAssertFalse(sets.mentions("{RST}"), "MDC's exchange is call + location")
        XCTAssertFalse(sets.mentions("{SERIAL}"), "and carries no number either")
    }

    /// No bundled party sends both. The order is pinned here so a future one
    /// cannot silently pick a different one.
    func testBothShapeSendsTheReportBeforeTheNumber() throws {
        let both = try party(",\"exchangeIncludesRST\":true,\"exchangeIncludesSerial\":true")
        let sets = MessageSets.defaults(for: both)
        XCTAssertEqual(sets.run[1], "{CALL} {RST} {SERIAL} {EXCH}")
        XCTAssertEqual(sets.searchPounce[1], "{RST} {SERIAL} {EXCH}")
        XCTAssertEqual(sets.searchPounce[6], "R {RST} {SERIAL} {EXCH}")
    }

    /// An unrecognised partyID must not hand the operator empty function keys.
    func testNilPartyTakesTheReportForm() {
        XCTAssertEqual(MessageSets.defaults(for: nil), MessageSets.standard)
    }

    /// Only the exchange-bearing slots vary; CQ, TU, AGN and 73 never do.
    func testTheNonExchangeSlotsAreIdenticalInEveryShape() throws {
        let shapes = [
            MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "ksqp"))),
            MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "cqp"))),
            MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: "mdc"))),
        ]
        for slot in [0, 2, 3, 4, 5, 6, 7] {
            XCTAssertEqual(Set(shapes.map { $0.run[slot] }).count, 1,
                           "run F\(slot + 1) must not vary by exchange shape")
        }
        for slot in [0, 2, 3, 4, 5, 7] {
            XCTAssertEqual(Set(shapes.map { $0.searchPounce[slot] }).count, 1,
                           "S&P F\(slot + 1) must not vary by exchange shape")
        }
        XCTAssertEqual(shapes[0].run[0], "CQ TEST {MYCALL}")
        XCTAssertEqual(shapes[0].run[7], "73 TU {MYCALL}")
    }

    func testEveryShapeFillsAllEightKeys() throws {
        for id in ["ksqp", "cqp", "mdc"] {
            let sets = MessageSets.defaults(for: try XCTUnwrap(PartyCatalog.party(id: id)))
            XCTAssertEqual(sets.run.count, 8, id)
            XCTAssertEqual(sets.searchPounce.count, 8, id)
            XCTAssertFalse(sets.run.contains(""), id)
            XCTAssertFalse(sets.searchPounce.contains(""), id)
        }
    }

    // MARK: mentions

    func testMentionsScansBothSets() {
        XCTAssertTrue(MessageSets.standard.mentions("{RST}"))
        XCTAssertTrue(MessageSets.standard.mentions("{MYCALL}"))
        XCTAssertFalse(MessageSets.standard.mentions("{SERIAL}"))
        // S&P-only reference still counts.
        let sp = MessageSets(run: ["CQ"], searchPounce: ["{SERIAL} {EXCH}"])
        XCTAssertTrue(sp.mentions("{SERIAL}"))
    }

    // MARK: contradicts — what the editor warns about

    func testContradictsFlagsASerialPartySendingAReport() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        XCTAssertTrue(MessageSets.standard.contradicts(cqp),
                      "keys 5NN and no QSO number — the bug this closes")
        XCTAssertFalse(MessageSets.defaults(for: cqp).contradicts(cqp))
    }

    /// The clause MDC is the reason for: no number is missing, but the report
    /// being sent is not part of the exchange.
    func testContradictsFlagsMDCStillSendingAReport() throws {
        let mdc = try XCTUnwrap(PartyCatalog.party(id: "mdc"))
        XCTAssertTrue(MessageSets.standard.contradicts(mdc))
        XCTAssertFalse(MessageSets.defaults(for: mdc).contradicts(mdc))
    }

    func testContradictsIsSilentForEveryReportParty() throws {
        for id in Self.rstPartyIDs {
            let p = try XCTUnwrap(PartyCatalog.party(id: id), id)
            XCTAssertFalse(MessageSets.standard.contradicts(p),
                           "\(id) sends a report and no number — nothing to warn about")
        }
    }

    func testContradictsIsSilentOnceTheOperatorHasFixedItByHand() throws {
        let cqp = try XCTUnwrap(PartyCatalog.party(id: "cqp"))
        var custom = MessageSets.standard
        custom.run[1] = "{CALL} {SERIAL} {EXCH} GL"
        custom.searchPounce = custom.searchPounce.map {
            $0.replacingOccurrences(of: "{RST}", with: "{SERIAL}")
        }
        XCTAssertFalse(custom.contradicts(cqp), "hand-fixed macros are not a warning")
    }

    func testContradictsIgnoresAnUnknownParty() {
        XCTAssertFalse(MessageSets.standard.contradicts(nil))
    }
}
```

- [ ] **Step 2: Regenerate the project so the new test file is compiled**

`project.yml` globs `Tests/`, so a new file is invisible until this runs.

```bash
xcodegen generate
```

Expected: `Loaded project`, then `Created project at .../QSOPartyLogger.xcodeproj`.

- [ ] **Step 3: Run the new tests to verify they fail**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MessageDefaultsTests 2>&1 | tail -20
```

Expected: **compile failure**, not a test failure — `type 'MessageSets' has no member 'defaults'`, plus `value of type 'MessageSets' has no member 'mentions'` and `'contradicts'`. That is the correct red state for a method that does not exist yet.

- [ ] **Step 4: Write the implementation**

In `Sources/Core/Models/ContestLog.swift`, keep `defaultRun`, `defaultSearchPounce` and `standard` **exactly as they are** — `standard` is now doing double duty as the report-shape answer and as the baseline for "did the operator edit these?" — and add to `MessageSets`, after `static let standard`:

```swift
    /// The default macros for a party's exchange shape. Derived rather than
    /// fixed because three bundled parties send no signal report: CQP and PAQP
    /// send a QSO number instead, and MDC sends call and location only. A fixed
    /// `{RST}` default keys a report those sponsors' exchanges do not contain.
    ///
    /// A nil party — an unrecognised `partyID` — takes the report form. It is
    /// the common shape, and better than handing an operator empty F-keys.
    static func defaults(for party: PartyDefinition?) -> MessageSets {
        let includesRST = party?.exchangeIncludesRST ?? true
        let includesSerial = party?.exchangeIncludesSerial ?? false
        // Report, then number, then location — the order they are sent in.
        let exchange = [
            includesRST ? "{RST}" : nil,
            includesSerial ? "{SERIAL}" : nil,
            "{EXCH}",
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return MessageSets(
            run: [
                "CQ TEST {MYCALL}",
                "{CALL} \(exchange)",
                "TU {MYCALL}",
                "{MYCALL}",
                "AGN?",
                "?",
                "B4",
                "73 TU {MYCALL}",
            ],
            searchPounce: [
                "{MYCALL}",
                exchange,
                "TU",
                "{MYCALL}",
                "AGN?",
                "?",
                "R \(exchange)",
                "73",
            ]
        )
    }

    /// Whether any message in either set references a macro.
    func mentions(_ macro: String) -> Bool {
        (run + searchPounce).contains { $0.contains(macro) }
    }

    /// True when these macros contradict the party's exchange — what the
    /// messages editor warns about. Two ways to get it wrong, and MDC is why
    /// the second clause exists: a party that sends a QSO number with no
    /// message referencing `{SERIAL}`, or a party whose exchange carries no
    /// report with a message still sending `{RST}`.
    func contradicts(_ party: PartyDefinition?) -> Bool {
        guard let party else { return false }
        if party.exchangeIncludesSerial, !mentions("{SERIAL}") { return true }
        if !party.exchangeIncludesRST, mentions("{RST}") { return true }
        return false
    }
```

- [ ] **Step 5: Run the new tests to verify they pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MessageDefaultsTests 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)"
```

Expected: `Executed 13 tests, with 0 failures` and `** TEST SUCCEEDED **`.

If `testTheSixteenReportPartiesKeepTheShippedDefaults` fails, `defaults(for:)` does not reproduce `standard` byte-for-byte — diff the failing slot against `defaultRun`/`defaultSearchPounce` rather than changing the assertion. That test is the Article 4 guarantee.

**On the running totals in this plan:** each task states the total it expects, arithmetic from the 586 baseline. They are a cross-check, not a contract — if a figure disagrees with what the run prints, trust the run and carry its number forward, including into the README.

- [ ] **Step 6: Run the full suite — nothing else may move**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
```

Expected: `Executed 599 tests, with 0 failures` (586 + 13) and `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Sources/Core/Models/ContestLog.swift Tests/Core/MessageDefaultsTests.swift QSOPartyLogger.xcodeproj
git commit -m "feat: derive default CW macros from the party's exchange shape

MessageSets.defaults(for:) reads exchangeIncludesRST and
exchangeIncludesSerial rather than hardcoding {RST}. The sixteen report
parties resolve byte-identically to the shipped defaults, asserted
per-party; CQP and PAQP get {SERIAL}, MDC gets call + location only.

Nothing calls it yet — wiring is the next commit.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 2: Wire it into `LogDocument` — upgrade untouched sets, never rewrite edited ones

**Files:**
- Modify: `Sources/App/LogDocument.swift:42-47` (open path), `:149-163` (`updateStation`)
- Test: `Tests/App/LogDocumentTests.swift`

- [ ] **Step 1: Write the failing tests**

Append inside `final class LogDocumentTests: XCTestCase` in `Tests/App/LogDocumentTests.swift`, before the closing brace:

```swift
    // MARK: Message defaults follow the party (2026-07-25)

    /// A new document starts at ksqp and the operator picks the real party in
    /// Contest Setup, so the macros have to follow that choice — deriving them
    /// at init alone would give a CQP operator Kansas's macros.
    @MainActor
    func testUntouchedMacrosFollowThePartyChosenInSetup() throws {
        let doc = LogDocument()
        XCTAssertEqual(doc.log.partyID, "ksqp")
        XCTAssertEqual(doc.log.messages, MessageSets.standard, "precondition")

        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.messages.run[1], "{CALL} {SERIAL} {EXCH}")
        XCTAssertEqual(
            doc.log.messages,
            MessageSets.defaults(for: PartyCatalog.party(id: "cqp"))
        )
    }

    @MainActor
    func testCustomisedMacrosSurviveAPartyChange() throws {
        let doc = LogDocument()
        var custom = MessageSets.standard
        custom.run[0] = "CQ CQP {MYCALL} {MYCALL}"
        doc.log.messages = custom

        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.messages, custom,
                       "an edited set encodes an on-air habit; it is not ours to rewrite")
    }

    /// Undo must be an exact inverse: a Kansas log must not keep California
    /// macros after the party change is undone.
    @MainActor
    func testUndoRestoresBothPartyAndMacros() throws {
        let doc = LogDocument()
        let undo = UndoManager()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "cqp", undoManager: undo
        )
        XCTAssertEqual(doc.log.messages.run[1], "{CALL} {SERIAL} {EXCH}", "precondition")

        undo.undo()
        XCTAssertEqual(doc.log.partyID, "ksqp")
        XCTAssertEqual(doc.log.messages, MessageSets.standard)
    }

    /// The open path: a CQP log saved before this change carries the old fixed
    /// report macros, and gets upgraded.
    func testOpeningACQPLogUpgradesUntouchedMacros() {
        var saved = ContestLog(partyID: "cqp")
        saved.messages = MessageSets.standard
        let opened = LogDocument.upgradingUntouchedMessages(saved)
        XCTAssertEqual(opened.messages.run[1], "{CALL} {SERIAL} {EXCH}")
    }

    func testOpeningACQPLogLeavesEditedMacrosAlone() {
        var saved = ContestLog(partyID: "cqp")
        var custom = MessageSets.standard
        custom.run[1] = "{CALL} 5NN {EXCH} HI HI"
        saved.messages = custom
        XCTAssertEqual(LogDocument.upgradingUntouchedMessages(saved).messages, custom)
    }

    func testOpeningAReportPartyLogChangesNothing() {
        var saved = ContestLog(partyID: "ksqp")
        saved.messages = MessageSets.standard
        XCTAssertEqual(
            LogDocument.upgradingUntouchedMessages(saved).messages, MessageSets.standard
        )
    }

    /// Re-opening an already-upgraded log is a no-op, not a second rewrite.
    func testOpeningAnAlreadyUpgradedLogIsIdempotent() {
        var saved = ContestLog(partyID: "cqp")
        saved.messages = MessageSets.defaults(for: PartyCatalog.party(id: "cqp"))
        let once = LogDocument.upgradingUntouchedMessages(saved)
        XCTAssertEqual(once.messages, saved.messages)
        XCTAssertEqual(LogDocument.upgradingUntouchedMessages(once).messages, saved.messages)
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/LogDocumentTests 2>&1 | tail -20
```

Expected: compile failure — `type 'LogDocument' has no member 'upgradingUntouchedMessages'`.

- [ ] **Step 3: Add the open-path upgrade**

In `Sources/App/LogDocument.swift`, replace `init(configuration:)` (lines 42–47):

```swift
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.log = LogDocument.upgradingUntouchedMessages(try ContestLog.decode(from: data))
    }

    /// A log saved before default macros followed the party's exchange shape
    /// carries the old fixed `{RST}` set. An untouched set — byte-identical to
    /// what shipped — carries no operator intent, so it is upgraded to the
    /// party's shape. An edited set is left alone for `MessagesEditor` to warn
    /// about; rewriting a customised message set behind the operator's back is
    /// worse than the bug.
    ///
    /// Separate from `ContestLog.init(from:)` on purpose: a `Codable` init must
    /// not touch the filesystem, and `PartyCatalog.party(id:)` re-reads the
    /// bundle and the user parties folder on every call.
    nonisolated static func upgradingUntouchedMessages(_ log: ContestLog) -> ContestLog {
        guard log.messages == MessageSets.standard else { return log }
        var upgraded = log
        upgraded.messages = MessageSets.defaults(for: PartyCatalog.party(id: log.partyID))
        return upgraded
    }
```

- [ ] **Step 4: Add the party-change upgrade**

In the same file, replace `updateStation` (lines 149–163):

```swift
    @MainActor
    func updateStation(_ station: StationProfile, location: MyLocation, partyID: String, undoManager: UndoManager?) {
        let (oldStation, oldLoc, oldParty) = (log.station, log.myLocation, log.partyID)
        let oldMessages = log.messages
        log.station = station
        log.myLocation = location
        log.partyID = partyID
        log.setupCompleted = true
        // Macros the operator never edited follow the new party's exchange
        // shape — this is what gives a CQP log {SERIAL} instead of Kansas's
        // {RST}. Anything customised is theirs and is left alone.
        if oldMessages == MessageSets.defaults(for: PartyCatalog.party(id: oldParty)) {
            log.messages = MessageSets.defaults(for: PartyCatalog.party(id: partyID))
        }
        AppSettings.shared.lastStationProfile = station
        undoManager?.registerUndo(withTarget: self) { doc in
            MainActor.assumeIsolated {
                doc.updateStation(oldStation, location: oldLoc, partyID: oldParty, undoManager: undoManager)
                // Restore the exact macros afterwards, whatever the
                // re-derivation inside that call decided: undo is an exact
                // inverse, not a second guess.
                doc.log.messages = oldMessages
            }
        }
        undoManager?.setActionName("Change Station Setup")
    }
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/LogDocumentTests 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)"
```

Expected: `Executed 9 tests, with 0 failures` (2 existing + 7 new), `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/LogDocument.swift Tests/App/LogDocumentTests.swift
git commit -m "feat: untouched macros follow the party on setup and on open

A new document starts at ksqp and learns its real party in Contest Setup,
so updateStation re-derives macro sets that are byte-identical to the
shipped defaults. init(configuration:) does the same on open, which
upgrades a CQP log saved before this change. Edited sets are never
rewritten. Undo restores party and macros together.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 3: Messages editor — surface `{SERIAL}`, warn on a mismatch, party-aware defaults

**Files:**
- Modify: `Sources/UI/MessagesEditor.swift`

No new unit tests: the predicate (`contradicts`) and the defaults are already covered in Task 1, and this task only binds them to controls. Verification is the build plus the assertions from Task 1.

- [ ] **Step 1: Cache the party and replace the fixed defaults**

In `Sources/UI/MessagesEditor.swift`, replace the state block (lines 11–13):

```swift
    @State private var editMode: OperatingMode = .run
    @State private var run: [String] = []
    @State private var searchPounce: [String] = []
    /// Resolved once on appear — `document.party` re-reads the bundle and the
    /// user parties folder on every call, which a view body must not do.
    @State private var party: PartyDefinition?
```

Then replace `.onAppear` (lines 65–68):

```swift
        .onAppear {
            party = document.party
            run = pad(document.log.messages.run)
            searchPounce = pad(document.log.messages.searchPounce)
        }
```

- [ ] **Step 2: Add the derived helpers**

Add these below `body`, before `private func binding(_:)`:

```swift
    /// What this party's macros should be, for Restore Defaults and the fix
    /// button.
    private var partyDefaults: MessageSets {
        MessageSets.defaults(for: party)
    }

    /// What is currently in the fields — not what is saved — so the warning
    /// clears the moment the operator types a fix.
    private var edited: MessageSets {
        MessageSets(run: normalized(run), searchPounce: normalized(searchPounce))
    }

    private var mismatchWarning: String? {
        guard let party, let mismatch = edited.exchangeMismatch(with: party) else { return nil }
        // Exhaustive on purpose: a new mismatch case must force its own copy
        // here rather than falling through to another case's wording.
        switch mismatch {
        case .missingSerial:
            return "\(party.name) sends a QSO number, but no message uses {SERIAL}."
        case .extraneousRST:
            return "\(party.name)'s exchange carries no signal report, "
                + "but a message still sends {RST}."
        case .missingRST:
            return "\(party.name) sends a signal report, but no message uses {RST}."
        }
    }

    private func applyPartyDefaults() {
        run = pad(partyDefaults.run)
        searchPounce = pad(partyDefaults.searchPounce)
    }
```

- [ ] **Step 3: Show `{SERIAL}` in the macro list**

Replace line 19:

```swift
            Text("Stored in this log file, so each contest keeps its own macros. Macros: {MYCALL} {CALL} {RST} {SERIAL} {EXCH} — prosigns: ( KN + AR = BT * SK")
```

- [ ] **Step 4: Add the warning banner**

Insert immediately after the closing `}` of the `Grid { … }` block (after line 41) and before the cut-numbers `Toggle`:

```swift
            if let mismatchWarning {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(mismatchWarning)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Use \(party?.name ?? "Party") Defaults", action: applyPartyDefaults)
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                }
                .padding(8)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
```

⌘⇧D is unused elsewhere in the app — the only existing shortcuts are ⌘E, ⌘⇧E, Return and Escape — so Article 7 is satisfied without a collision.

- [ ] **Step 5: Make Restore Defaults party-aware**

Replace the `Restore Defaults` button (lines 47–50). Without this, pressing it in a CQP log reintroduces the exact bug this commit fixes:

```swift
                Button("Restore Defaults", action: applyPartyDefaults)
```

- [ ] **Step 6: Build and confirm the whole suite is still green**

```bash
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** BUILD SUCCEEDED **`, no `error:` lines.

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
```

Expected: `Executed 606 tests, with 0 failures` (586 + 13 + 7), `** TEST SUCCEEDED **`.

- [ ] **Step 7: Update the README for commit 1**

In `README.md`, replace the `{MYCALL} {CALL} {RST} {SERIAL} {EXCH}` sentence around line 204 with:

```markdown
  radio's internal keyer (K3 `KY` / Flex CWX). F1–F8 messages with
  `{MYCALL} {CALL} {RST} {SERIAL} {EXCH}` macros, **defaulting to the party's
  own exchange shape** — CQP and PAQP send `{SERIAL}` where the report would
  go, MDC sends call and location only, and the messages editor warns (with a
  one-key fix, ⌘⇧D) when a log's macros contradict its party. **Esc aborts
  instantly.** Optional cut numbers for RST and QSO numbers (599 → 5NN) in the
  CW Messages editor.
```

Then set the test count on line 389 to the number printed by Step 6:

```bash
sed -i '' 's/586 unit tests cover/606 unit tests cover/' README.md
grep -n "unit tests cover" README.md
```

- [ ] **Step 8: Commit**

```bash
git add Sources/UI/MessagesEditor.swift README.md
git commit -m "feat: surface {SERIAL} and warn when macros contradict the party

The macro list in the messages editor never mentioned {SERIAL}, so the
one place an operator would look for it did not have it. Adds it, makes
Restore Defaults party-aware (it previously reintroduced the bug), and
warns with a one-key fix (⌘⇧D) when a party sends a number no message
carries, or sends a report its exchange has no room for.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

# Commit 2 — Optional `1→A` cut number

### Task 4: `applyCutNumbers(_:cutOne:)` and `cwCutNumberOne`

**Files:**
- Modify: `Sources/App/AppSettings.swift:156-159` (doc comment + new property), `:199` (init), `:205-237` (cut numbers + `expandMacros`)
- Test: `Tests/Core/SerialExchangeTests.swift`

- [ ] **Step 1: Write the failing tests**

Append inside `final class SerialExchangeTests: XCTestCase` in `Tests/Core/SerialExchangeTests.swift`, before the closing brace:

```swift
    // MARK: Cut numbers (2026-07-25)

    /// 0→T and 9→N are near-universal in contest CW and are unconditional.
    func testStandardCutsAreAlwaysApplied() {
        XCTAssertEqual(AppSettings.applyCutNumbers("599"), "5NN")
        XCTAssertEqual(AppSettings.applyCutNumbers("40"), "4T")
        XCTAssertEqual(AppSettings.applyCutNumbers("100"), "1TT")
        XCTAssertEqual(AppSettings.applyCutNumbers("1780"), "178T")
    }

    /// 1→A has real currency but is not universal — a number cut in a way the
    /// receiving operator does not expect costs a repeat, so it is opt-in.
    func testCutOneIsOptIn() {
        XCTAssertEqual(AppSettings.applyCutNumbers("199", cutOne: false), "1NN")
        XCTAssertEqual(AppSettings.applyCutNumbers("199", cutOne: true), "ANN")
        XCTAssertEqual(AppSettings.applyCutNumbers("1780", cutOne: true), "A78T")
        XCTAssertEqual(AppSettings.applyCutNumbers("11", cutOne: true), "AA")
    }

    /// The digits nobody agreed to cut stay digits.
    func testOtherDigitsAreNeverCut() {
        XCTAssertEqual(AppSettings.applyCutNumbers("2345678", cutOne: true), "2345678")
    }

    func testCutNumbersReachBothTheReportAndTheNumber() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{RST} {SERIAL} {EXCH}",
                myCall: "KE5CW", call: "W6A", rst: "599", exchange: "SCLA",
                serial: "109", cutNumbers: true, cutOne: true
            ),
            "5NN ATN SCLA"
        )
    }

    /// Callsigns and county codes carry digits that are not numbers to be cut.
    func testCutNumbersNeverTouchCallsignsOrExchanges() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{CALL} {RST} {EXCH}",
                myCall: "KE5CW", call: "W0BH", rst: "599", exchange: "MRN90",
                cutNumbers: true, cutOne: true
            ),
            "W0BH 5NN MRN90"
        )
    }

    func testCutOneDefaultsOffSoExistingBehaviourIsUnchanged() {
        XCTAssertEqual(
            AppSettings.expandMacros(
                "{SERIAL}", myCall: "K", call: "C", rst: "599", exchange: "X",
                serial: "1", cutNumbers: true
            ),
            "1", "an operator who never asked for 1→A keeps sending 1"
        )
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/SerialExchangeTests 2>&1 | tail -20
```

Expected: compile failure — `extra argument 'cutOne' in call`.

- [ ] **Step 3: Implement the setting and the mapping**

In `Sources/App/AppSettings.swift`, replace the `cwCutNumbers` property and its stale doc comment (lines 156–159):

```swift
    /// Send cut numbers when keying CW: 0→T and 9→N, in both the {RST} and
    /// {SERIAL} macros (599 → 5NN, 40 → 4T).
    var cwCutNumbers: Bool {
        didSet { defaults.set(cwCutNumbers, forKey: "cwCutNumbers") }
    }

    /// Also cut 1→A. Opt-in and off by default: 1→A has real currency in
    /// contest CW but is not universal, and a number cut in a way the
    /// receiving operator does not expect costs a repeat. A second Bool
    /// rather than folding both into an enum, because `cwCutNumbers` is a live
    /// UserDefaults token — migrating it would silently reset the choice of
    /// anyone who had already turned cut numbers on.
    var cwCutNumberOne: Bool {
        didSet { defaults.set(cwCutNumberOne, forKey: "cwCutNumberOne") }
    }
```

Add to `init()`, immediately after the `cwCutNumbers` line (line 199):

```swift
        cwCutNumberOne = defaults.object(forKey: "cwCutNumberOne") as? Bool ?? false
```

Replace `applyCutNumbers` (lines 205–215):

```swift
    /// CW cut numbers: 0→T and 9→N always, 1→A when `cutOne` is set
    /// (599 → 5NN, 199 → ANN). Applied to the {RST} and {SERIAL} values only —
    /// callsigns and exchanges are never altered.
    static func applyCutNumbers(_ value: String, cutOne: Bool = false) -> String {
        String(value.map { c -> Character in
            switch c {
            case "9": "N"
            case "0": "T"
            case "1": cutOne ? "A" : c
            default: c
            }
        })
    }
```

Replace `expandMacros` (lines 217–237):

```swift
    /// Expand message macros against current entry state.
    static func expandMacros(
        _ template: String,
        myCall: String,
        call: String,
        rst: String,
        exchange: String,
        serial: String = "",
        cutNumbers: Bool = false,
        cutOne: Bool = false
    ) -> String {
        func cut(_ value: String) -> String {
            cutNumbers ? applyCutNumbers(value, cutOne: cutOne) : value
        }
        return template
            .replacingOccurrences(of: "{MYCALL}", with: myCall)
            .replacingOccurrences(of: "{CALL}", with: call)
            .replacingOccurrences(of: "{RST}", with: cut(rst))
            // The QSO number, for parties that exchange one instead of a report
            // (CQP). Defaults to empty, so message sets that never mention it
            // expand exactly as before.
            .replacingOccurrences(of: "{SERIAL}", with: cut(serial))
            .replacingOccurrences(of: "{EXCH}", with: exchange)
            .trimmingCharacters(in: .whitespaces)
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/SerialExchangeTests 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)"
```

Expected: `Executed 28 tests, with 0 failures` (22 existing + 6 new), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppSettings.swift Tests/Core/SerialExchangeTests.swift
git commit -m "feat: optional 1→A cut number

0→T and 9→N stay unconditional. 1→A is a second Bool rather than an enum
because cwCutNumbers is a live UserDefaults token and migrating it would
reset the choice of anyone who had already enabled cut numbers.

Also corrects two doc comments that still claimed cut numbers applied to
{RST} only — they have covered {SERIAL} since it shipped.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 5: Wire `cutOne` to the sender and the editor

**Files:**
- Modify: `Sources/UI/MainView.swift:875-885`, `Sources/UI/MessagesEditor.swift` (the toggle), `README.md`

- [ ] **Step 1: Pass the flag when expanding**

In `Sources/UI/MainView.swift`, replace `expandMacros` (lines 875–885):

```swift
    private func expandMacros(_ template: String) -> String {
        AppSettings.expandMacros(
            template,
            myCall: document.log.station.callsign.uppercased(),
            call: entry.callNormalized,
            rst: entry.rstSent.isEmpty ? currentModeClass.defaultRST : entry.rstSent,
            exchange: document.log.myLocation.displayText,
            serial: entry.serialSent,
            cutNumbers: settings.cwCutNumbers && currentModeClass == .cw,
            cutOne: settings.cwCutNumberOne
        )
    }
```

`cutNumbers` already gates on CW, so `cutOne` needs no separate mode check.

- [ ] **Step 2: Replace the misleading toggle with honest controls**

In `Sources/UI/MessagesEditor.swift`, replace the cut-numbers `Toggle` (lines 43–44 as shipped; now sitting just after the warning banner from Task 3):

```swift
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Send cut numbers (599 → 5NN, 40 → 4T)", isOn: $settings.cwCutNumbers)
                    .help("Replaces 0→T and 9→N in the {RST} and {SERIAL} macros when keying CW. Callsigns and county codes are never altered.")
                Toggle("Also cut 1 → A (199 → ANN)", isOn: $settings.cwCutNumberOne)
                    .help("Less universal than 0→T and 9→N — leave off if stations ask for repeats.")
                    .disabled(!settings.cwCutNumbers)
                    .padding(.leading, 20)
            }
```

The old label said "for RST" while the code had applied it to `{SERIAL}` since the day that macro shipped.

- [ ] **Step 3: Build and run the full suite**

```bash
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** BUILD SUCCEEDED **`.

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
```

Expected: `Executed 612 tests, with 0 failures` (606 + 6), `** TEST SUCCEEDED **`.

- [ ] **Step 4: Update the README**

Replace the cut-numbers sentence added in Task 3 Step 7 with:

```markdown
  instantly.** Optional cut numbers for RST and QSO numbers (0→T, 9→N: 599 →
  5NN, 40 → 4T) in the CW Messages editor, with 1→A available separately for
  operators who cut harder.
```

Then set the test count to the number printed by Step 3:

```bash
sed -i '' 's/606 unit tests cover/612 unit tests cover/' README.md
grep -n "unit tests cover" README.md
```

- [ ] **Step 5: Commit**

```bash
git add Sources/UI/MainView.swift Sources/UI/MessagesEditor.swift README.md
git commit -m "feat: wire 1→A cut number to the keyer and the editor

The toggle no longer claims to cover RST only, and the 1→A checkbox
under it is disabled unless cut numbers are on.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

# Commit 3 — Operating mode persisted, defaulted from location

### Task 6: `ContestLog.operatingMode`

**Files:**
- Modify: `Sources/Core/Models/ContestLog.swift` (`ContestLog` properties, `init`, `CodingKeys`, `init(from:)`)
- Test: `Tests/Core/ModelTests.swift`

- [ ] **Step 1: Write the failing tests**

Append inside `final class ModelTests: XCTestCase` in `Tests/Core/ModelTests.swift`, before the closing brace:

```swift
    // MARK: Operating mode (2026-07-25)

    /// The in-state station is the multiplier everyone is chasing, so it runs.
    /// The out-of-state station is doing the chasing, so it searches.
    func testOperatingModeDefaultsFromLocation() {
        var inState = ContestLog(partyID: "ksqp")
        inState.myLocation = .inState(counties: ["SED"])
        XCTAssertEqual(inState.derivedOperatingMode, .run)

        var outOfState = ContestLog(partyID: "ksqp")
        outOfState.myLocation = .outOfState(location: "TX")
        XCTAssertEqual(outOfState.derivedOperatingMode, .searchPounce)
    }

    /// A log written before the mode was persisted derives one rather than
    /// falling back to Run for an operator who will never call CQ.
    ///
    /// The fixture is built by encoding a real log and deleting the key, not
    /// hand-typed: `StationProfile` has eighteen fields and a hand-written
    /// stand-in would drift from the model the first time one is added
    /// (Article 2 — never hand-type data that exists in a file).
    func testLogWithoutAStoredModeDerivesItFromLocation() throws {
        var log = ContestLog(partyID: "ksqp")
        log.myLocation = .outOfState(location: "TX")
        log.operatingMode = .run
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: log.encoded()) as? [String: Any]
        )
        XCTAssertNotNil(
            object.removeValue(forKey: "operatingMode"),
            "the key must exist before removing it, or this proves nothing"
        )
        let legacy = try JSONSerialization.data(withJSONObject: object)

        let decoded = try ContestLog.decode(from: legacy)
        XCTAssertEqual(decoded.operatingMode, .searchPounce,
                       "out of state, so S&P — not the old unconditional Run")
    }

    /// A stored mode wins, so reopening a log mid-contest restores the mode
    /// the operator was actually in.
    func testStoredModeSurvivesARoundTrip() throws {
        var log = ContestLog(partyID: "ksqp")
        log.myLocation = .outOfState(location: "TX")
        log.operatingMode = .run
        let reloaded = try ContestLog.decode(from: log.encoded())
        XCTAssertEqual(reloaded.operatingMode, .run,
                       "an out-of-state op who moved to Run stays in Run")
    }

    func testNewLogTakesTheDerivedModeAtInit() {
        XCTAssertEqual(
            ContestLog(partyID: "ksqp", myLocation: .inState(counties: ["SED"])).operatingMode,
            .run
        )
        XCTAssertEqual(
            ContestLog(partyID: "ksqp", myLocation: .outOfState(location: "TX")).operatingMode,
            .searchPounce
        )
    }
```

`ContestLog.encoded()` and `ContestLog.decode(from:)` both use `.iso8601` dates, so the round trip through `JSONSerialization` is lossless — and `qsos` is empty here regardless.

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ModelTests 2>&1 | tail -20
```

Expected: compile failure — `value of type 'ContestLog' has no member 'operatingMode'` and no member `derivedOperatingMode`.

- [ ] **Step 3: Implement**

In `Sources/Core/Models/ContestLog.swift`, add to `ContestLog` after the `messages` property:

```swift
    /// Run vs Search & Pounce. Persisted so reopening a log mid-contest
    /// restores the mode the operator was actually in, rather than snapping
    /// back to Run.
    var operatingMode: OperatingMode
```

Add the derivation as a computed property on `ContestLog`, next to `nextSerial`:

```swift
    /// The mode this log should start in when none is stored: the in-state
    /// station is the multiplier being chased and runs, the out-of-state
    /// station is doing the chasing and searches.
    var derivedOperatingMode: OperatingMode {
        myLocation.isInState ? .run : .searchPounce
    }
```

Add the parameter to `init`, after `messages`:

```swift
    init(
        partyID: String,
        station: StationProfile = StationProfile(),
        myLocation: MyLocation = .outOfState(location: ""),
        qsos: [QSO] = [],
        messages: MessageSets = .standard,
        operatingMode: OperatingMode? = nil,
        setupCompleted: Bool = false
    ) {
        self.partyID = partyID
        self.station = station
        self.myLocation = myLocation
        self.qsos = qsos
        self.messages = messages
        self.operatingMode = operatingMode ?? (myLocation.isInState ? .run : .searchPounce)
        self.setupCompleted = setupCompleted
    }
```

Add `operatingMode` to `CodingKeys`:

```swift
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, partyID, station, myLocation, qsos, messages, operatingMode, setupCompleted
    }
```

And in `init(from:)`, after the `messages` line:

```swift
        // Logs written before the mode was persisted derive one from location
        // rather than defaulting an out-of-state operator into Run.
        operatingMode = try c.decodeIfPresent(OperatingMode.self, forKey: .operatingMode)
            ?? (myLocation.isInState ? .run : .searchPounce)
```

`derivedOperatingMode` cannot be used in either place: in `init` the stored properties are not all assigned yet, and in `init(from:)` `self` is not yet usable. The expression is duplicated deliberately and both are covered by Step 1's tests.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ModelTests 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)"
```

Expected: `Executed 12 tests, with 0 failures` (8 existing + 4 new), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run the full suite — `LogDocumentTests` and `SmokeTests` construct `ContestLog`**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
```

Expected: `Executed 616 tests, with 0 failures` (612 + 4), `** TEST SUCCEEDED **`. The new `init` parameter is defaulted, so no existing call site changes.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Models/ContestLog.swift Tests/Core/ModelTests.swift
git commit -m "feat: persist operating mode, derived from in/out of state

Additive: a log with no stored mode derives one — in-state runs, because
it is the multiplier being chased; out-of-state searches. A stored mode
wins, so reopening mid-contest restores the mode the operator was in.

Nothing reads it yet — MainView still holds its own @State.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

### Task 7: Bind `MainView` to the stored mode, and re-derive only on a flip

**Files:**
- Modify: `Sources/UI/MainView.swift:25` (remove `@State`), `:158-169` (binding), and every `operatingMode` reference
- Modify: `Sources/App/LogDocument.swift` (`updateStation`)
- Test: `Tests/App/LogDocumentTests.swift`

- [ ] **Step 1: Write the failing tests for the flip rule**

Append inside `final class LogDocumentTests: XCTestCase`, before the closing brace:

```swift
    // MARK: Operating mode re-derivation (2026-07-25)

    @MainActor
    func testSetupPicksTheModeForAnOutOfStateOperator() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .searchPounce)
    }

    @MainActor
    func testSetupPicksTheModeForAnInStateOperator() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .inState(counties: ["SED"]),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run)
    }

    /// Reopening Contest Setup to fix a callsign typo must not undo a
    /// deliberate mid-contest switch to Run.
    @MainActor
    func testAnEditOnTheSameSideOfTheLineKeepsADeliberateSwitch() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        doc.log.operatingMode = .run  // the operator switches by hand

        var fixed = StationProfile()
        fixed.callsign = "KE5CW"
        doc.updateStation(
            fixed, location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run, "still out of state — nothing flipped")

        // Still out of state, different state: also not a flip.
        doc.updateStation(
            fixed, location: .outOfState(location: "OK"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run)
    }

    /// Crossing the state line is the one location change that implies a
    /// different operating style.
    @MainActor
    func testCrossingTheStateLineReDerivesTheMode() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .outOfState(location: "TX"),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .searchPounce, "precondition")

        doc.updateStation(
            StationProfile(), location: .inState(counties: ["SED"]),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .run)
    }

    /// A county change within the state is not a flip.
    @MainActor
    func testChangingCountyWithinTheStateKeepsTheMode() throws {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(), location: .inState(counties: ["SED"]),
            partyID: "ksqp", undoManager: nil
        )
        doc.log.operatingMode = .searchPounce  // deliberate

        doc.updateStation(
            StationProfile(), location: .inState(counties: ["BUT"]),
            partyID: "ksqp", undoManager: nil
        )
        XCTAssertEqual(doc.log.operatingMode, .searchPounce)
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/LogDocumentTests 2>&1 | grep -E "XCTAssert|Executed|TEST (SUCCEEDED|FAILED)" | head -20
```

Expected: `testSetupPicksTheModeForAnOutOfStateOperator` and `testCrossingTheStateLineReDerivesTheMode` **fail** — `updateStation` does not touch the mode yet, so a document created at `.outOfState(location: "")` keeps `.searchPounce` from init and the in-state cases stay wrong. The three "keeps the mode" tests may pass vacuously; that is fine, they are guarding the next step.

- [ ] **Step 3: Add the flip-only re-derivation**

In `Sources/App/LogDocument.swift`, inside `updateStation`, immediately after the existing macro-upgrade block and before `AppSettings.shared.lastStationProfile = station`:

```swift
        // Crossing the state line is the one location change that implies a
        // different operating style — the in-state station is the multiplier
        // being chased and runs, the out-of-state station chases. Any other
        // edit (a callsign typo, a different county, a different state) must
        // not overwrite a deliberate mid-contest switch.
        if oldLoc.isInState != location.isInState {
            log.operatingMode = log.derivedOperatingMode
        }
```

The undo closure needs no change: it calls `updateStation` with `oldLoc`, which flips in-state-ness back and re-derives symmetrically.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/LogDocumentTests 2>&1 | grep -E "Executed|TEST (SUCCEEDED|FAILED)"
```

Expected: `Executed 14 tests, with 0 failures` (9 from Task 2 + 5 new), `** TEST SUCCEEDED **`.

- [ ] **Step 5: Bind `MainView` to the stored mode**

In `Sources/UI/MainView.swift`, delete line 25 entirely:

```swift
    @State private var operatingMode: OperatingMode = .run
```

Add a computed binding among the other private computed properties, just after `private var party: PartyDefinition?` (line 43–45):

```swift
    /// The document owns the mode so it survives a reopen. Writes go straight
    /// to `log` without registering undo — ⌘Z belongs to log edits, and an
    /// operator who toggles Run/S&P four times should not have to press it
    /// four times to reach a deleted QSO. The change rides along with the next
    /// save, which the QSO-append autosave triggers on the next contact.
    private var operatingMode: Binding<OperatingMode> {
        Binding(
            get: { document.log.operatingMode },
            set: { document.log.operatingMode = $0 }
        )
    }
```

- [ ] **Step 6: Update every reader to go through the binding**

Four call sites. Replace line 159 (`MessagesRow`):

```swift
                operatingMode: operatingMode,
```

Line 501 (`activeMessages`):

```swift
        document.log.messages.messages(for: operatingMode.wrappedValue)
```

Line 589 (`ESM.nextAction`):

```swift
            mode: operatingMode.wrappedValue,
```

Line 622 (`sendMessageAt`):

```swift
        if operatingMode.wrappedValue == .run, index == 0 {
```

Line 699 (`jumpToCQFrequency` — jumping to your own CQ frequency still means you are running):

```swift
        operatingMode.wrappedValue = .run
```

- [ ] **Step 7: Build and run the full suite**

```bash
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)|error:"
```

Expected: `** BUILD SUCCEEDED **`. If any `error:` mentions `operatingMode`, a reader was missed — `grep -n "operatingMode" Sources/UI/MainView.swift` and confirm every use is either the `Binding` itself (passed to `MessagesRow`) or `.wrappedValue`.

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
```

Expected: `Executed 621 tests, with 0 failures` (616 + 5), `** TEST SUCCEEDED **`.

- [ ] **Step 8: Update the README**

Add a feature bullet immediately after the "Serial-number exchanges" bullet (which ends `Deleting a QSO never renumbers the others.` around line 181):

```markdown
- **Run vs Search & Pounce follows your location.** An in-state log opens in
  Run — in-state stations are the multiplier everyone is chasing — and an
  out-of-state log opens in S&P. The mode is stored in the log, so reopening
  mid-contest restores the mode you were actually in, and it is only
  re-derived if you cross the state line.
```

Then set the test count to the number printed by Step 7:

```bash
sed -i '' 's/612 unit tests cover/621 unit tests cover/' README.md
grep -n "unit tests cover" README.md
```

- [ ] **Step 9: Commit**

```bash
git add Sources/UI/MainView.swift Sources/App/LogDocument.swift Tests/App/LogDocumentTests.swift README.md
git commit -m "feat: operating mode follows in-state vs out-of-state

MainView no longer owns the mode; it binds the document's, which starts
from location and survives a reopen. Setup re-derives only when in-state-
ness flips, so a callsign fix or a county change never overwrites a
deliberate mid-contest switch.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] **Full suite green, and the README count matches**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | tail -3
grep -n "unit tests cover" README.md
```

Both numbers must agree. Expected end state: 621 tests, 0 failures — 35 above the 586 baseline (13 + 7 + 6 + 4 + 5).

- [ ] **Three commits on top of the spec, in order**

```bash
git log --oneline caaec73..HEAD
```

Expected, oldest first: derive default macros → untouched macros follow the party → surface `{SERIAL}` → optional 1→A → wire 1→A → persist operating mode → mode follows in/out of state. Seven commits across the three groups; each group's last commit carries its README change (Article 6).

- [ ] **No party JSON, exporter, or engine file moved**

```bash
git diff --stat caaec73..HEAD -- Resources/ Sources/Core/Engine/ Sources/Core/Export/ Sources/Hardware/
```

Expected: empty output. Any change here means the blast radius escaped the spec.

- [ ] **A mode toggle registers no undo**

The spec requires this, and it is structural rather than assertable — a test cannot easily observe the *absence* of a registration. Check it by grep instead: the mode path must write `log.operatingMode` directly and never call `registerUndo`.

```bash
grep -n "operatingMode" Sources/UI/MainView.swift Sources/App/LogDocument.swift
```

Expected: `MainView`'s binding get/set pair, four `.wrappedValue` readers, and the single `log.operatingMode = log.derivedOperatingMode` line in `updateStation`. No `updateOperatingMode` method, and no `registerUndo` on any line mentioning `operatingMode`. The consequence is intended: a mode change alone does not mark the document dirty, and persists with the next save.

- [ ] **Article 10 enforcement check still returns nothing**

```bash
grep -rniE "k3|kx3|kx2|flex|icom|yaesu|kenwood|ci-v" Sources/App Sources/UI
```

Expected: no output. (`MessagesEditor`'s old help text named no radio; keep it that way.)

# Keying-path seam — design

**Date:** 2026-07-25
**Status:** approved
**Kind:** structural refactor (Constitution Article 4) — no party, no radio

## Why

On 2026-07-25 a final review of `feat/serial-macros-cut-numbers-mode-default`
found two bugs in the code that decides what the radio keys, after eight prior
review rounds had missed them. Both were fixed in `7651adc`:

1. **ESM in Search & Pounce transmitted the next contact's QSO number.**
   `returnPressed`'s `.logAndSend` arm called `logContact()` before
   `sendMessageAt(index)`. Logging calls `entry.clearForNextContact`, which
   advances `entry.serialSent` to n+1, so the log recorded n while the radio
   sent n+1 — every contact, CQP and PAQP. Both stations would be removed from
   each other's logs.
2. **The first contact of a new CQP log transmitted no number at all.**
   `entry.syncSerial` ran in `onAppear` while the document was still the `ksqp`
   placeholder, and nothing re-seeded it when Contest Setup chose the real
   party.

The severity is not that these happened. It is that nothing could catch them.
Against the 643-test suite of the time:

- `serial: entry.serialSent` → `serial: ""` in `MainView.expandMacros` — deleting
  the entire feature the branch existed for — left all 643 tests green.
- `cutOne: settings.cwCutNumberOne` → `cutOne: settings.cwCutNumbers` — left all
  643 green.

`MainView.swift`'s keying path (`returnPressed`, `logContact`,
`expandedMessage(at:)`, `sendMessageAt`, `expandMacros`) is private to a SwiftUI
`View`, so no test can reach it. `MessagesEditor.swift` has no test at all.

Both bugs are ordering and lifecycle bugs, not logic bugs. A seam around
`AppSettings.applyCutNumbers` or `expandMacros` would not have caught either —
those pure functions are already well covered. What is needed is making **the
sequence observable**: what string does F2 key, given this document, this entry
state, and this settings state, at this point in the flow?

## What the seam has to satisfy

The two bugs impose different constraints, and both are load-bearing.

**Bug 1 is an ordering bug inside one function.** A seam that exposes
`expandedMessage(at:)` and `logContact()` as two separately-testable functions
does not catch it: a test would call them in the correct order and pass while
`returnPressed` called them in the wrong one. The seam must own the
`.logAndSend` arm and report, from a single call, both what it keyed and what it
logged.

**Bug 2 is a lifecycle bug across two functions.** Whether a test can reach it
depends on whether seeding the QSO number stays a *push* (the view calls
`syncSerial` at the right moments) or becomes a *pull* (expansion reads the live
document). A push keeps the bug reachable-but-not-preventable: a test could
prove `partyChanged()` reseeds without proving `MainView` remembered to wire it.

One further constraint on shape: `AppSettings` writes `UserDefaults.standard` in
every `didSet`. A test must never be handed a live `AppSettings` — flipping
`cwCutNumbers` in a test would rewrite the operator's real preferences. The
keying settings have to cross the seam as a value.

## Design

### New types, in `Sources/App/`

`EntryState.swift` moves from `Sources/UI/` to `Sources/App/`. CLAUDE.md's layout
table describes `Sources/UI/` as "SwiftUI views"; neither `EntryState` nor the
new `EntryFlow` is a view, and they are now a pair. Pure file move — same
module, no import changes, `project.yml` globs `path: Sources`.

```swift
/// The keying-relevant slice of AppSettings, as a value. A test is never handed
/// a live AppSettings: every `didSet` writes UserDefaults.standard, so flipping
/// `cwCutNumbers` in a test would rewrite the operator's real preferences.
struct KeyingSettings: Equatable, Sendable {
    var esmEnabled = false
    var cutNumbers = false
    var cutOne = false
}
```

`AppSettings` gains `var keying: KeyingSettings` so `MainView` has one place to
build it.

```swift
@MainActor @Observable
final class EntryFlow {
    let entry: EntryState
    let document: LogDocument

    /// Everything that changes between one Return and the next and is owned by
    /// the view — the radio's band and mode, where the cursor is, whether the
    /// radio is connected at all. Passed per call rather than mirrored into
    /// stored properties, so a test states the conditions instead of having to
    /// reproduce the wiring that keeps them current.
    struct Context { ... }

    /// What Return decided. Returned rather than performed: the string the
    /// radio would key is the thing under test, and a caller that has to be
    /// handed it cannot key a different one.
    enum Outcome: Equatable {
        case qsy(EntryCommand)
        case send(index: Int, text: String)
        /// `rows` were appended and `text` goes out after — expanded *before*
        /// the append, which is the whole point.
        case logged(rows: [QSO], text: String)
        case needsSetup
        case nothing
    }
}
```

### The QSO number becomes derived-with-override

```swift
// EntryState
/// What the operator typed into Ser S, or nil to follow the log. An override
/// rather than a seeded value because seeding needs a moment to happen at, and
/// on 2026-07-25 the moment was missed.
private var serialOverride: String?
@ObservationIgnored var nextSerial: () -> Int? = { nil }

var serialSent: String {
    get { serialOverride ?? nextSerial().map(String.init) ?? "" }
    set { serialOverride = newValue }
}
```

`syncSerial(next:)` goes away; `clearForNextContact` sets `serialOverride = nil`.
`EntryBar`'s `$entry.serialSent` keeps working unchanged, because `serialSent`
stays a settable `var`.

This is what makes bug 2 structurally impossible rather than merely tested:
there is no seeding moment left to miss.

`SerialExchangeTests`' two `syncSerial` tests are rewritten against the new
model rather than deleted — including
`testClearingForTheNextContactAdvancesTheNumberBeforeAnySend`, which `7651adc`
added to record bug 1.

### Party lookup is cached

`document.party` re-reads the bundle *and* the user-parties folder on every
call, and the entry bar would now read the QSO number on every keystroke.
`EntryFlow` caches the party keyed on `partyID`, so a party change invalidates
it with nobody having to remember to. `@ObservationIgnored`, because a getter
that notified would fire mid-body.

**Behaviour delta, accepted:** editing a user party JSON on disk mid-session is
now picked up when the party changes rather than on the next read. Everything
else gets faster — `revalidate()` runs on every keystroke and currently re-reads
the folder each time.

### What `MainView` keeps

Focus, `showSetup`, `captureCQFrequency`, `radio.sendCW`, the repeat-CQ task,
the key monitor. `returnPressed` becomes an adapter over the outcome. The
context is built by one computed property, so there is a single place the view
can get it wrong and the test builds the same struct.

## Testing

`Tests/App/EntryFlowTests.swift`. CQP is out-of-state TX, and CQP's exchange
carries no signal report, so `defaults(for: cqp).searchPounce[1]` is
`"{SERIAL} {EXCH}"`.

The two acceptance tests, which must fail against pre-`7651adc` behaviour:

```swift
// Bug 1 — pre-fix: rows carry 1, the air carries "2 TX"
guard case .logged(let rows, let keyed) = flow.returnPressed(ctx, undoManager: nil)
else { return XCTFail(...) }
XCTAssertEqual(rows.first?.serialSent, 1)
XCTAssertEqual(keyed, "1 TX")

// Bug 2 — pre-fix: "TX", the number never goes out
let doc = LogDocument()                       // ksqp placeholder
let flow = EntryFlow(document: doc)
doc.updateStation(..., partyID: "cqp", undoManager: nil)
flow.entry.call = "W6ABC"
XCTAssertEqual(flow.expandedMessage(at: 1, context: ctx), "1 TX")
```

Plus guards for the two mutants named above, an operator-typed-override test
(types 17 → log records 17 → air carries 17), `esmDrivesReturn` gating on CW and
a connected radio, QSY-command-in-call-field, and `needsSetup`.

Verification is by reverting each `7651adc` fix in turn and confirming the
corresponding test goes red, then restoring — the acceptance criterion is that
the seam can express both bugs, and a test that has never been seen to fail has
not demonstrated that.

## Commits

Per Article 4 a structural refactor is its own commit, and per Article 9 a
regression should bisect to one thing.

| | Contents |
| --- | --- |
| 1 | `EntryFlow` + `KeyingSettings` + `EntryState` move + `EntryFlowTests` + README |
| 2 | `MessagesDraft` value lifted out of `MessagesEditor` + tests + README |

Neither adds a party or a radio. Full suite green before and after; baseline is
749 tests, 0 failures. README test count updated per Article 6.

## Known gaps, not closed

- That `MainView` builds its context correctly is still untestable without a
  view-inspection harness. The seam removes the *ordering* class of bug, not the
  *wiring* class.
- `MessagesEditor`'s `.disabled(!settings.cwCutNumbers)` on the cut-one toggle
  stays untested as a modifier, though its consequence is covered.
- `MainView.swift`'s operating-mode binding writes `document.log.operatingMode`
  without registering undo (deliberate), so a mode change with no subsequent QSO
  is lost on close with no prompt. The refactor does not make a fix natural:
  SwiftUI's `ReferenceFileDocument` dirty-tracking runs through undo
  registration, so "mark dirty without registering undo" has no clean path. Left
  as-is.

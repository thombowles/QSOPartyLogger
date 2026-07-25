# Sending the QSO number, cut numbers, and the operating-mode default

Design, 2026-07-25. Follows
[`2026-07-24-serial-number-exchanges-design.md`](2026-07-24-serial-number-exchanges-design.md),
which added serial numbers to the model, both exporters, and the entry bar, and
deliberately left one thing undone.

## Problem

Three unrelated defects, found while checking a report that "no serial is
generated."

### 1. The number is generated but never transmitted

Serial support is complete everywhere except the air. `ContestLog.nextSerial`
assigns it, the entry bar pre-fills it, `CountyLineExpander` shares one number
across a contact's rows, Cabrillo writes it in the exchange slot, ADIF writes
`STX`/`SRX`, and the `{SERIAL}` macro expands it. But `MessageSets.defaultRun`
sends `{CALL} {RST} {EXCH}` and nothing references `{SERIAL}`, so a fresh CQP log
keys `W6ABC 5NN SCLA` — a signal report CQP does not use, and no QSO number at
all.

The prior design said so explicitly:

> "Shipping a party-specific default message set is a separate question and is
> not attempted here."

That question is now due. CQP's exchange is the number:

> "1. California stations send **QSO number and 4-letter county abbreviation**.
> 2. Stations outside of California send **QSO number** and 2-letter State,
> Canadian province/territory, or "DX"."
>
> — [`cqp_rules_2026.txt`](../../research/cqp_rules_2026.txt), NCCC, Last Update
> 19-July-2026

PAQP's likewise:

> "5.a. **Sequential serial number plus PA county, ARRL section, Canadian
> section, or "DX"**."
>
> — [`paqp_rules.md`](../../research/paqp_rules.md) §3

And MDC's is neither:

> "S1 §7: You give your Call Sign and Location to each contacted station." (No
> RST, no serial number.)
>
> — [`mdcqp_rules.md`](../../research/mdcqp_rules.md)

So **three** of the nineteen bundled parties currently key a report their sponsor's
exchange does not contain — CQP and PAQP, which additionally fail to send a
required number, and MDC, which has no number to send but should not be sending
`5NN` either. The remaining **sixteen** are correct today and must stay
byte-identical.

### 2. `{SERIAL}` is undiscoverable, and the cut-number toggle lies

[`MessagesEditor`](../../../Sources/UI/MessagesEditor.swift) lists the available
macros as `{MYCALL} {CALL} {RST} {EXCH}`. `{SERIAL}` is absent from the one place
an operator would look for it, so even an operator who knows the number should be
going out has no way to find the macro that sends it.

Separately, the cut-number toggle reads "Send cut numbers for RST (599 → 5NN)"
and its help text says "in the {RST} macro", while
[`AppSettings.applyCutNumbers`](../../../Sources/App/AppSettings.swift) has been
applied to `{SERIAL}` since the day it shipped. The setting is more capable than
its label, which is the failure mode where an operator turns off a feature they
wanted.

### 3. Operating mode always starts in Run

`MainView` holds `operatingMode` as `@State ... = .run` and never persists it. An
out-of-state operator — who spends the contest searching and pouncing, because
the in-state stations are the multiplier being chased — starts every session in
the wrong mode, and gets put back there every time the log is reopened.

## Scope

One spec, three commits, full suite green at each:

1. party-aware CW message defaults, plus `{SERIAL}` discoverability
2. optional `1→A` cut number, plus the label and doc-comment corrections
3. operating-mode persistence and its in-state/out-of-state default

Split because the three are independent, and a keying or scoring regression
should bisect to one of them rather than to all three. No party JSON changes: CQP
and PAQP already carry `exchangeIncludesSerial: true`, and all seventeen other
research docs record "no serial" in the sponsor's own terms.

Baseline before any change: **586 tests, 0 failures, `** TEST SUCCEEDED **`.**

## Decisions

### Message defaults are derived from the party, not fixed

`MessageSets.defaults(for: PartyDefinition?)` replaces the two constants at their
call sites. It is a pure function over the two flags the party already carries —
no catalog lookup, no I/O — so it is testable as a table:

| `exchangeIncludesSerial` | `exchangeIncludesRST` | F2 (Run) | S&P F2 | S&P F7 | Parties |
| --- | --- | --- | --- | --- | --- |
| true | false | `{CALL} {SERIAL} {EXCH}` | `{SERIAL} {EXCH}` | `R {SERIAL} {EXCH}` | CQP, PAQP |
| false | true | `{CALL} {RST} {EXCH}` | `{RST} {EXCH}` | `R {RST} {EXCH}` | 16 others |
| false | false | `{CALL} {EXCH}` | `{EXCH}` | `R {EXCH}` | MDC |
| true | true | `{CALL} {RST} {SERIAL} {EXCH}` | `{RST} {SERIAL} {EXCH}` | `R {RST} {SERIAL} {EXCH}` | none bundled |

F1 and F3–F6/F8 (`CQ TEST {MYCALL}`, `TU {MYCALL}`, `{MYCALL}`, `AGN?`, `?`,
`B4`, `73 TU {MYCALL}`) do not vary by exchange shape and are identical in every
row.

The `nil` party case returns the RST row: an unrecognised `partyID` is not a
reason to hand an operator empty function keys.

**The fourth row is defined but not exercised.** No bundled party sends both, and
`CabrilloExporter.qsoLine` still emits `serialSent ?? rstSent` — one or the
other. The macro shape is settled here so a future both-party does not have to
guess at message order; the exporter's column order remains the open decision the
prior design flagged, and this commit does not pretend to have made it.

**`MessageSets.standard` stays exactly as it is.** It is now two things: the
answer for the RST row, and the baseline for deciding whether an operator has
edited their macros. Keeping the old constant verbatim is what makes the
sixteen unaffected parties provably unchanged.

### The party arrives after the log, so the hook is where the party changes

`LogDocument.init()` creates every new document at `partyID: "ksqp"` and the
operator picks the real party in Contest Setup, which lands in `updateStation`.
Deriving defaults in `ContestLog.init` alone would therefore give a CQP operator
Kansas's macros. Three touch points instead:

- **`updateStation`** — after `log.partyID` changes, if
  `log.messages == MessageSets.defaults(for: oldParty)` the operator never edited
  them, so re-derive for the new party. Anything else is deliberate and is left
  alone. `messages` joins the existing undo snapshot, so one Undo restores party
  and macros together rather than leaving a Kansas log with California macros.
- **`init(configuration:)`** — the same untouched test on open. This is what
  upgrades a CQP log saved before this change.
- **`ContestLog.init(from:)`** — keeps its `?? .standard` fallback, unchanged. A
  `Codable` init must not touch the filesystem, and `PartyCatalog.party(id:)`
  re-reads the bundle and the user parties folder on every call. The App layer
  legitimately knows the party; the model layer does not need to.

### Untouched macros upgrade silently; edited ones get a warning, not a rewrite

Byte-equality against `defaults(for: oldParty)` is the whole test. It is exact,
needs no extra stored flag, and cannot misfire: a set that equals the shipped
default carries no operator intent to preserve.

Where the macros *were* edited, the log is left alone and `MessagesEditor` shows
a warning — the party sends a QSO number, no message references `{SERIAL}` —
with a **Use CQP Defaults** button beside it. Rewriting a customised message set
behind the operator's back is the one outcome worse than the bug: those macros
may encode a hard-won on-air habit.

**The predicate is the party's exchange shape, not just the serial flag.** Two
ways a customised set can contradict the sponsor, and MDC is the reason the second
one matters:

```swift
(party.exchangeIncludesSerial && !mentions("{SERIAL}"))
    || (!party.exchangeIncludesRST && mentions("{RST}"))
```

evaluated across the Run and S&P sets together. The first clause catches a CQP or
PAQP set that sends no number; the second catches an MDC or CQP set still sending
a report the exchange has no room for. It stays silent for the sixteen RST parties,
and for a CQP operator who has already fixed their macros by hand.

### Cut numbers: `0→T` and `9→N` always, `1→A` by choice

`0→T` and `9→N` are near-universal in contest CW and stay unconditional. `1→A`
has real currency but is not universal, and a number cut in a way the receiving
operator does not expect costs a repeat — which is why it is opt-in rather than
part of a single "aggressive" mode that would also cut `2→U`, `3→V`, `7→G` and
`8→D`.

A second `Bool` (`cwCutNumberOne`, default `false`) rather than an enum: the
existing `cwCutNumbers` key is a live `UserDefaults` token, and migrating it to an
enum would silently reset the choice of anyone who had already turned cut numbers
on. Additive, per Article 4.

`applyCutNumbers(_:cutOne:)` takes the flag as a parameter and stays a pure
static function, so the mapping is testable without a settings object.

### Operating mode is persisted, and defaults from location

```swift
operatingMode = try c.decodeIfPresent(OperatingMode.self, forKey: .operatingMode)
    ?? (myLocation.isInState ? .run : .searchPounce)
```

The stored value wins where there is one, so the mode survives a reopen
mid-contest. Absent — every log written before this change — it is derived, which
is both the requested default and a better guess than the current unconditional
`.run`.

`MainView` drops its `@State` and binds `$document.log.operatingMode`.
**Toggling Run/S&P deliberately does not register undo:** Undo belongs to log
edits, and an operator who switches modes four times in a minute should not have
to press ⌘Z four times to get back to a deleted QSO. The consequence is that a
mode change alone does not mark the document dirty and rides along with the next
save — which `onChange(of: document.log.qsos)` already triggers on the next
logged contact, seconds later in any real contest.

**Re-derivation is limited to a flip in in-state-ness.** Reopening Contest Setup
to fix a callsign typo, or to change county within the state, must not overwrite a
deliberate mid-contest mode switch. Crossing the state line is the one location
change that genuinely implies a different operating style, so that is the only one
that re-derives. `jumpToCQFrequency()` continues to force `.run` — jumping to your
own CQ frequency means you are running — and is unaffected.

## Blast radius

| File | Change |
| --- | --- |
| `Core/Models/ContestLog.swift` | `MessageSets.defaults(for:)`; `mentions(_:)`; `operatingMode` stored + derived default |
| `App/LogDocument.swift` | untouched-upgrade in `updateStation` and `init(configuration:)`; `messages` in the undo snapshot; flip-only mode re-derivation |
| `App/AppSettings.swift` | `cwCutNumberOne`; `applyCutNumbers(_:cutOne:)`; corrected doc comments |
| `UI/MessagesEditor.swift` | `{SERIAL}` in the macro list; honest toggle label; `1→A` checkbox; party-aware Restore Defaults; missing-`{SERIAL}` warning + button |
| `UI/MainView.swift` | bind `$document.log.operatingMode` in place of `@State`; pass `cutOne` to macro expansion |
| `README.md` | features, macro table, cut numbers, operating-mode default, test count |

No party JSON, no `ScoreEngine`, no exporter, no radio driver.

## Verification

`xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'`,
green at each of the three commits, with the count recorded in the README.

New assertions, extending `SerialExchangeTests`, `LogDocumentTests` and
`ModelTests`:

- `defaults(for:)` across all four rows, and the `nil`-party case
- **every one of the sixteen RST parties resolves byte-identically to
  `MessageSets.standard`** — the Article 4 proof that this changes nothing for
  them; CQP and PAQP resolve to the serial row, MDC to the bare row
- untouched macros upgrade on a party change and on open; edited macros survive
  both untouched
- undoing a party change restores the previous party *and* its macros
- the mismatch predicate fires for CQP with RST macros **and for MDC with RST
  macros**, and is silent for all sixteen RST parties and for CQP with corrected
  macros
- `applyCutNumbers` with `cutOne` off and on (`199` → `1NN` → `ANN`), and that
  callsigns and county codes are never altered
- `operatingMode` decodes from a stored value; derives `.run` in-state and
  `.searchPounce` out-of-state when the key is absent; round-trips through encode
- the flip-only rule: an out-of-state log switched to Run keeps Run across a
  same-side location edit, and re-derives when it flips to in-state

Existing exporter and per-party tests are unchanged and must stay green — they are
the evidence that no party's Cabrillo or ADIF output moved.

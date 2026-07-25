# N1MM entry workflow: sequence-driven ESM, space cycling, uppercase fields

Design, 2026-07-25.

## Problem

Three faults in the entry row, all found while operating.

### 1. ESM logs stations that were never worked

[`ESM.nextAction`](../../../Sources/Core/Engine/ESM.swift) is a pure function of
`(mode, callEmpty, exchangeValid)`. In S&P, a non-empty call plus a valid
exchange is `logAndSend` — unconditionally.

So the normal S&P move breaks it. Tune to a spot, and the county is already
known; type it into the exchange before calling. Now the entry row holds a call
*and* a valid exchange, and the very first Return logs a QSO that never
happened and keys your report at a station that has not answered you.

Run has the same hole from the other side: prefill the exchange, type the call,
and Return logs the contact and sends TU without ever having sent their report.

The state that distinguishes "I have called him" from "he has answered me" is
simply absent from the model.

### 2. Every ESM send moves the cursor

[`MainView.swift:597`](../../../Sources/UI/MainView.swift) advances the focus one
field after *every* `sendMessage`. That is already wrong for the CQ case — Run
with an empty call sends F1 and drops the cursor into the Exchange field, so the
answering station's callsign gets typed into the wrong box. And it defeats any
fix for fault 1 that leaves it standing: sending your call would move you onto a
prefilled exchange, so calling a second time would log the phantom QSO instead.

### 3. Space dead-ends, and the fields are not uppercase

Space advances Call → Exchange but is ignored inside the Exchange field, where
it types a literal space that `ExchangeParser.tokenize` treats as a county-line
separator. The cycle never closes.

Separately, `.textCase(.uppercase)` on the Call field only restyles what is
drawn. `entry.call` keeps whatever case was typed, and the Exchange field is not
even styled — lowercase text sits in the row until export normalises it.

## What N1MM does

Behaviour taken from the N1MM Logger+ manual, fetched 2026-07-25. Paraphrased
rather than quoted; each claim traces to its page.

| Claim | Source |
| --- | --- |
| ESM steps through a QSO on repeated Enter presses; the program anticipates the next step, **moves the cursor**, and **highlights** the message Enter will send next | [Function Keys](https://n1mmwp.hamdocs.com/setup/function-keys/) |
| A setting named "ESM sends your call once in S&P, then ready to copy received exchange" — the Big Gun / Little Pistol switch. Checked, the cursor advances to Exchange after the first Enter; unchecked, it stays in Callsign so repeat Enters keep calling. Checked, you call again with F4 regardless of cursor position | [The Configurer](https://n1mmwp.hamdocs.com/setup/the-configurer/) |
| Space jumps field to field filling in defaults, and **skips over the signal report fields** | [Key Assignments](https://n1mmwp.hamdocs.com/setup/keyboard-shortcuts/) |
| Space moves between the Callsign and Exchange boxes, restoring the caret to where it last was in that box | [The Entry Window](https://n1mmwp.hamdocs.com/manual-windows/entry-window/) |
| Tab walks every field **including** the signal reports, with the "S" digit selected for overtyping (599 → 579) | [Key Assignments](https://n1mmwp.hamdocs.com/setup/keyboard-shortcuts/) |
| Enter logs when ESM is off, and sends a message when ESM is on | [Key Assignments](https://n1mmwp.hamdocs.com/setup/keyboard-shortcuts/) |

Two conclusions drive the design.

**ESM is a sequence, not a predicate.** "Sends your call *once*" is only
meaningful if the program remembers that it already went out. Field contents
alone cannot express it — a prefilled exchange looks identical before and after
you have called.

**The cursor is an output of that sequence, not an input to it.** N1MM moves the
cursor as a consequence of the step it just performed, and the Big Gun switch
chooses how far. Nothing in the manual makes the cursor decide *which* message
is sent; the F-keys work from any field.

This supersedes the first sketch of this feature, which read the focused field
to pick the message. Cursor-driven selection produces the right result in the
common case by accident, and diverges as soon as the operator moves the cursor
for any other reason.

## Design

### A two-step sequence per contact

`EntryState` gains one property:

```swift
/// The station the in-progress ESM sequence belongs to — set when the
/// middle message of a contact goes out, cleared on log and on F12.
var esmSentTo: String?
```

and one derived flag:

```swift
/// True once this contact's middle message (S&P: my call; Run: their
/// report) has been sent to the callsign currently in the field.
var esmMiddleSent: Bool {
    guard let esmSentTo, !esmSentTo.isEmpty else { return false }
    return esmSentTo == callNormalized
}
```

Storing the callsign rather than a bare `Bool` makes the reset automatic:
retype the call and the flag stops matching, so the sequence restarts for the
new station without any explicit invalidation. `clearForNextContact` nils it,
which covers both logging and F12.

`ESM.nextAction` takes the flag instead of reading focus. No default value —
every call site updates deliberately, and the existing tests are rewritten
rather than silently passing.

```swift
static func nextAction(
    mode: OperatingMode,
    callEmpty: Bool,
    exchangeValid: Bool,
    middleSent: Bool
) -> Action
```

| Mode | State | Enter sends | Marks sent | Cursor after |
| --- | --- | --- | --- | --- |
| Run | call empty | F1 — CQ | no | stays in Call |
| Run | middle not sent | F2 — their report | yes | → Exchange |
| Run | middle sent, exchange invalid | F2 — repeat | yes | → Exchange |
| Run | middle sent, exchange valid | log + F3 — TU | cleared | → Call |
| S&P | call empty | F1 — my call | no | stays in Call |
| S&P | middle not sent | F1 — my call | yes | stays in Call |
| S&P | middle sent, exchange invalid | F1 — call again | yes | stays in Call |
| S&P | middle sent, exchange valid | log + F2 — my report | cleared | → Call |

Both modes collapse to one shape: **log only when the middle message has
already gone out and the exchange is valid; otherwise send the middle message**
(or CQ, when Run has no call yet).

The prefill case now reads correctly. S&P with the county already typed: first
Return sends your call and marks the contact; he answers; Return sends your
report and logs. Two presses, and no press before the first one can log
anything.

### Cursor: little pistol, hard-coded

The Big Gun switch is deliberately not built. ESM moves the cursor in exactly
one case — Run, after their report — because that is the only moment where the
next thing the operator types is the other station's data. Everywhere else the
cursor stays and Space moves it.

In S&P this is the manual's unchecked default: repeat Enters keep calling,
which is the behaviour a hundred-watt station wants. If it ever wants to become
a setting, this is the value the checkbox would toggle.

### The pending message is visible

`MessagesRow` gains `pendingIndex: Int?` and outlines that F-key. `MainView`
derives it from the *same* `ESM.nextAction` call that Return uses, mapping the
action to its message index, so the highlight cannot disagree with what the key
does. Nil whenever ESM is inactive (off, radio disconnected, or not CW), which
is the same guard Return already applies.

This is what makes sequence state safe rather than hidden — the operator can
see that the next Return sends the call, not the report.

### Space cycles; comma and slash separate

The guard in `onKeyPress(.space)` that exempts the Exchange field is removed.
`Field.next()` already returns `.call` from `.exchange`, so the cycle closes
with no change to the order: Call → (Ser R) → Exchange → Call, stepping over
the pre-filled reports exactly as the manual describes. Tab continues to walk
every field.

With Space no longer able to type one, a literal space stops being a mult
separator. `ExchangeParser.tokenize` splits on `/` and `,` only, and trims each
token so a comma typed with a following space still parses:

| Typed | Before | After |
| --- | --- | --- |
| `LIN/AND` | county line | county line |
| `LIN,AND` | county line | county line |
| `lin, and` | county line | county line |
| `LIN AND` | county line | unknown abbreviation |

Nothing already logged is affected: `parse` is reached only from live entry
validation and the Edit QSO sheet, and that sheet already rejects more than one
location per row.

### Tab pre-selects the S digit

Entering an RST field selects the middle character so 599 → 579 is a single
overtype.

Correcting an earlier estimate: this is not small. SwiftUI's `TextField`
exposes no selection API, so the implementation reaches the window's field
editor on focus change and sets the selected range. It is the one item here
with real framework risk; if that proves unreliable the fallback is an
`NSViewRepresentable` used by the two RST fields only. It ships as its own
commit so it can be reverted without touching anything else.

### Uppercase as typed

A shared `Binding<String>.uppercasing` wraps the bindings for Call and Exchange
in the entry bar, and Call, their-location and my-location in the Edit QSO
sheet. The redundant `.textCase(.uppercase)` on Call is removed.

Known caveat: writing the binding back on every keystroke can move the caret to
the end of the field during a mid-string edit. Appending — ordinary typing — is
unaffected. N1MM's caret restoration on Space was offered and declined, so no
AppKit-backed field is introduced for this.

## Testing

Everything except the two AppKit-touching items is pure and testable.

| Test | File |
| --- | --- |
| The full ESM table above — both modes × `middleSent` × `exchangeValid` × `callEmpty` | `Tests/Core/OperatingFeatureTests.swift` |
| `esmMiddleSent` resets when the callsign is retyped, and after `clearForNextContact` | `Tests/Core/OperatingFeatureTests.swift` |
| Action → message index mapping, so the highlight tracks the key | `Tests/Core/OperatingFeatureTests.swift` |
| Space no longer separates; `/`, `,` and `, ` still do | `Tests/Core/ExchangeParserTests.swift` |
| `"LIN AND"` now fails; the other three forms still expand | `Tests/Core/CountyLineExpanderTests.swift` |
| `Field.next()` closes the cycle Exchange → Call | `Tests/Core/SerialExchangeTests.swift` |

Two known test edits, both consequences of the separator change:
`CountyLineExpanderTests.swift:57` drops `"LIN AND"` from its accepted forms,
and `ExchangeParserTests.swift:59` changes `"TX MO"` to `"TX/MO"` to keep
testing `.mixedTypes` rather than becoming an unknown-abbreviation case. The
party test files get swept for other space-separated exchange strings.

Hand verification, reported honestly as such: the S-digit selection and the
caret behaviour under forced uppercase cannot be asserted from XCTest.

## Commits

One concern each, in dependency order.

1. **Sequence-driven ESM** — `ESM.swift`, `EntryState.esmSentTo`, the cursor
   rule in `MainView`, the pending highlight in `MessagesRow`, tests, README.
2. **Space cycles, separators shrink** — `EntryBar`, `ExchangeParser`, tests,
   README keyboard table.
3. **Uppercase entry fields** — the shared binding, `EntryBar`, `EditQSOSheet`.
4. **Tab pre-selects the S digit** — isolated, the riskiest, trivially
   revertable.

## Docs

README changes ship with the commit that causes them: the ESM feature bullet
(sequence, not field contents; visible pending message), the `Space` row of the
keyboard table (cycles and wraps; reports skipped), the county-line separator,
the `Tab` row, and the test count.

## Verification to perform during implementation

- Confirm F1–F8 fire regardless of which field has focus — the sequence design
  assumes the operator can always re-send a message by its own key, which is
  how the manual describes calling again under the Big Gun setting. If the key
  monitor gates on focus, that is a defect to fix in commit 1.
- `xcodegen generate` before building if any test file is added.

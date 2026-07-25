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

One conclusion drives the design: **field contents alone cannot express where
a contact has got to.** A prefilled exchange looks identical before and after
you have called. "Sends your call *once*" is only meaningful against some state
outside the row.

### Correction, same day

The first implementation took that state to be a sequence flag — *has this
contact's middle message gone out* — and let a valid exchange log as soon as it
had. That is wrong, and operating found it within minutes:

> "here's a case where I'm hunting N4RT, I prefilled his county based on what
> he already shared with another operator. I hit space to go back to the call
> field and hit enter to send my call but he picked someone else. I want to hit
> enter again to keep sending my call but it wants to now send my exchange."

Calling a station is not a step you take once. He answers someone else, you
call again, he answers someone else again. The flag latched on the first call
and never unlatched, so the second Return tried to log a QSO that had not
happened — the very fault the flag was added to prevent, moved one keypress
later.

The state that actually distinguishes the two is **where the operator is
looking**. The call field means *I am still trying to raise him*; the exchange
field means *I have him*. So:

**The call field never logs.** While the cursor is in it, Return only ever
calls — your call in S&P, his call and report in Run. Logging happens once the
cursor has moved off it and the exchange is valid.

**ESM never moves the cursor.** Space does. A Return that called once calls
again, in both modes, for as long as the operator leaves the cursor where it
is. This is also the effect of N1MM's Big Gun switch left unchecked, which is
its default.

## Design

### The cursor decides

`ESM.nextAction` takes where the cursor is. No new state is stored anywhere —
`EntryState` is untouched, because the entry row already knows everything the
decision needs.

```swift
static func nextAction(
    mode: OperatingMode,
    callEmpty: Bool,
    exchangeValid: Bool,
    cursorInCall: Bool
) -> Action
```

| Mode | State | Enter sends |
| --- | --- | --- |
| both | call empty | F1 — CQ / my call |
| both | cursor in the exchange, exchange matches nothing | F5 — AGN? |
| Run | cursor in the call field | F2 — his call and report |
| Run | exchange not valid | F2 — his call and report |
| Run | cursor elsewhere, exchange valid | log + F3 — TU |
| S&P | cursor in the call field | F1 — my call |
| S&P | exchange not valid | F1 — my call |
| S&P | cursor elsewhere, exchange valid | log + F2 — my report |

Both modes collapse to one shape: **the call field sends, everywhere else logs
once the exchange is valid.** Run's CQ outranks the rule, since an empty call
field can neither log nor report to anybody.

### A bad copy asks him to repeat

Sitting in the exchange field with text that matches no county, state or
prefix is its own case. He is already talking to you — calling him again is
the wrong thing on the air; asking him to repeat is the right one. So that
combination sends F5, AGN?.

The exchange field carries three states, not two, and the third matters:

| Exchange | From the exchange field |
| --- | --- |
| `valid` | log and send my report |
| `unmatched` | F5 — AGN? |
| `empty` | keep calling — nothing has been heard, so there is nothing to repeat |

`empty` is deliberately not AGN?. Landing in the field before he has sent
anything is not a bad copy. Only the call and exchange fields change what
Return does; QSO-number and signal-report fields count as neither, so an
unmatched exchange there keeps calling rather than asking.

`ESM.againIndex` names the F5 slot in the one place that decides, and a test
pins it to the `AGN?` entry in both default message sets — so the constant and
the message cannot drift apart. If the operator has blanked F5, `sendMessageAt`
already declines to key an empty message and Return does nothing.

"Cursor elsewhere" is deliberately every field except the call — not the
exchange specifically — so parties that exchange a QSO number can log from the
received-number field without a detour.

### ESM never moves the cursor

Space moves it; ESM does not. This follows from the rule above: any automatic
advance out of the call field would end the operator's ability to keep calling,
which is the whole point. It also fixes a fault that predates this work — Run's
CQ used to drop the cursor into the exchange field, so the answering station's
callsign got typed into the wrong box.

The cost is one Space per run QSO, after his report goes out and before his
exchange is typed. That press is the operator saying the contact happened,
which is exactly the signal the log needs.

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
| The full ESM table above — both modes × `cursorInCall` × `exchangeValid` × `callEmpty` | `Tests/Core/OperatingFeatureTests.swift` |
| The N4RT case: a prefilled exchange plus the cursor in the call field keeps calling, three Returns running | `Tests/Core/OperatingFeatureTests.swift` |
| No state of the row makes the call field log, in either mode | `Tests/Core/OperatingFeatureTests.swift` |
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

1. **ESM follows the cursor** — `ESM.swift`, the cursor rule in `MainView`,
   the pending highlight in `MessagesRow`, tests, README. Shipped first as a
   sequence flag; corrected in a fifth commit once operating showed the flag
   latched on the first call and never unlatched.
2. **Space cycles, separators shrink** — `EntryBar`, `ExchangeParser`, tests,
   README keyboard table.
3. **Uppercase entry fields** — the shared binding, `EntryBar`, `EditQSOSheet`.
4. **Tab pre-selects the S digit** — isolated, the riskiest, trivially
   revertable.

## Docs

README changes ship with the commit that causes them: the ESM feature bullet
(the call field never logs; visible pending message), the `Space` row of the
keyboard table (cycles and wraps; reports skipped), the county-line separator,
the `Tab` row, and the test count.

## Verification to perform during implementation

- Confirm F1–F8 fire regardless of which field has focus, so a message can
  always be re-sent by its own key. **Verified**: the F-keys are handled by a
  window-level `NSEvent` monitor that does not consult focus.
- `xcodegen generate` before building if any test file is added.

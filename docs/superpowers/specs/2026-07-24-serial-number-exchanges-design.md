# Serial-number exchanges

Design, 2026-07-24. Closes the "SERIAL NUMBERS" deferred engine gap in
[`docs/parties/WORKLIST-2026.md`](../../parties/WORKLIST-2026.md).

## Problem

CQP's exchange carries a **QSO number** and no signal report:

> "1. California stations send **QSO number** and 4-letter county abbreviation.
> 2. Stations outside of California send **QSO number** and 2-letter State,
> Canadian province/territory, or "DX".
> **QSO number = contact serial number starting with 1 for the first contact,
> progressing to 2 for the next contact, and so on.** It is unnecessary to send
> leading zeros in the QSO number."
>
> — [`cqp_rules_2026.txt`](../../research/cqp_rules_2026.txt), NCCC, Last Update
> 19-July-2026

`QSO` has `rstSent`/`rstRcvd` and nothing else, so the app has nowhere to put the
number. Scoring never depended on it — points and multipliers are computed from
band, mode and received location — which is why CQP could ship correct scoring
with the gap noted under
[Article 17](../CONSTITUTION.md#article-17--mapping-rules-to-the-schema).

What it cannot do is produce a submittable log:

- `CabrilloExporter.qsoLine` writes `rstSent`/`rstRcvd` into the two exchange
  slots. For CQP those are empty, so every QSO line exports with a **blank**
  QSO-number element.
- CQP accepts **Cabrillo only** — "paper, Excel, and ADIF logs are NOT
  acceptable" — so there is no fallback format.
- On the air, the CW/phone macros send `{RST}`, i.e. `5NN`, which is not part of
  the CQP exchange at all.

This is the first gap in the repo that blocks a submission rather than shading a
score, which is why it is being closed before more parties are added.

## Scope

This commit adds the **capability** and no party uses it yet — the pattern the
222 MHz band followed (`feat: 222 MHz (1.25 m) band`, then one commit per party
that gained the band). Turning it on for CQP is the next commit, so that a
scoring change still bisects to a single sponsor's rules (Article 9).

## Decisions

**Serials are their own fields, not an overload of RST.** `QSO.serialSent` and
`serialRcvd` are `Int?`. The tempting shortcut — put the number in `rstSent`,
since Cabrillo happens to put both in the same column — was rejected: a reader of
a saved log could not tell a report from a serial, and ADIF distinguishes them
(`RST_SENT` vs `STX`), so the overload would export wrong ADIF. Optionals mean
logs written before this change decode unchanged (`decodeIfPresent` yields nil).

**`Int?`, not `String?`.** The next number has to be computed from the last one,
and ADIF's `STX`/`SRX` are Number-typed. Formatting (leading zeros or not) is a
presentation choice, made once at export.

**RST and serial are independent party flags.** `exchangeIncludesSerial` joins
the existing `exchangeIncludesRST`, both defaulting so every bundled party keeps
its current behaviour. The four combinations are all real: RST only (most
parties), serial only (CQP), neither (MDC), and both (no bundled party yet, but
several DX-style contests do it and the entry bar handles it for free).

**One contact, one serial — shared by every county-line row.** This is the
question the worklist said to answer first. CQP defines the number as a "contact
serial number", and its county-line rule sends the counties "in a single
exchange":

> "A California County-line station is an expedition or mobile operating with all
> radios and antennas within 150 meters of more than one county and **sending all
> such counties in a single exchange**."

The sponsor's own logging guide shows one exchange producing one entry with
several counties (`DELN/SISK/HUMB`). This app expands that into one row per
county for multiplier bookkeeping (KSQP rule 11), and **those rows must not each
burn a number** — the operator sent one number on the air. `CountyLineExpander`
already stamps a shared `groupID` and copies `rstSent`/`rstRcvd` to every row;
the serials ride along identically, so this falls out of the existing design
rather than needing new machinery.

**The next serial is `max(serialSent) + 1`, assigned when the contact is
logged.** Not the row count — county-line contacts produce several rows per
number, so counting rows would skip. Deleting a QSO does **not** renumber the
others: the numbers were sent on the air and the other station logged them, so
the log must keep saying what was actually sent. A gap in the sequence is
correct and is what every other logger does.

**Cabrillo writes the serial where the report would go, and only one of them.**
`qsoLine` emits `serialSent ?? rstSent` — driven by the QSO's own data, so the
exporter needs no party parameter and cannot disagree with the log. No bundled
party sends both a report and a serial; if one ever does, the exporter needs a
deliberate decision about column order at that point, and the code says so
rather than guessing now.

**Leading zeros are not added.** CQP: "It is unnecessary to send leading zeros in
the QSO number." The existing column padding keeps the alignment.

**ADIF gains `STX`/`SRX` and keeps `RST_SENT`/`RST_RCVD` untouched.** Purely
additive, so every existing party's ADIF output is byte-identical (Article 4).

**`{SERIAL}` joins the CW macros.** Article 7 is keyboard-first: an operator who
cannot send the number cannot work the contest. `{RST}` is left alone, so
existing message sets are unaffected; a CQP operator edits their messages to use
`{SERIAL} {EXCH}`. Shipping a party-specific default message set is a separate
question and is not attempted here.

## Blast radius

| File | Change |
| --- | --- |
| `Core/Models/QSO.swift` | `serialSent`/`serialRcvd` as `Int?` |
| `Core/Models/ContestLog.swift` | `nextSerial` |
| `Core/Parties/PartyDefinition.swift` | `exchangeIncludesSerial` |
| `Core/Engine/CountyLineExpander.swift` | carry the pair onto every row of a contact |
| `Core/Export/CabrilloExporter.swift` | serial in the exchange slot when present |
| `Core/Export/AdifExporter.swift` | `stx`/`srx` when present |
| `App/AppSettings.swift` | `{SERIAL}` macro |
| `UI/EntryState.swift`, `UI/EntryBar.swift`, `UI/MainView.swift` | entry fields, focus order, next-number sync |
| `UI/EditQSOSheet.swift` | edit a mistyped number |

No party JSON changes here.

## Verification

`Tests/Core/SerialExchangeTests.swift` covers the model default, the party flag
default, one-number-per-contact across a county line, the next-number sequence
including the delete case, both exporters, and the macro. Every existing party's
export must stay byte-identical — the existing exporter tests are that proof.

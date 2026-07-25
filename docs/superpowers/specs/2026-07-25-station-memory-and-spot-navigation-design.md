# Station memory and spot navigation — design

**Date:** 2026-07-25
**Status:** approved, ready to plan

Five search-and-pounce niggles from KE5CW, reported after operating with the
band map open beside SmartSDR. Four are new behavior; one is an AppKit default
that has always been wrong.

| # | Symptom | Root cause |
| --- | --- | --- |
| 1 | Band map vanishes when another app takes focus | `NSPanel` defaults `hidesOnDeactivate` to `true` for `.utilityWindow` |
| 2 | No keyboard path to step spots on the vertical axis | Only ⌘← / ⌘→ are bound |
| 3 | A callsign already worked tells you nothing until you type an exchange | The worked/dupe check lives inside the exchange-parsed branch of `EntryState.revalidate` |
| 4 | Re-working a station on a new band means re-copying his county | Nothing reads the log (or the archive) by callsign |
| 5 | An exchange copied for a station who never came back stays in the field on the next spot | The exchange only clears on log or F12 |

A sixth report — typing `20M` in the call field keying CW instead of tuning —
was **not reproducible on current master** and is out of scope. Note for the
record: the entry row still has two Return paths, `.onSubmit(onLog)` on every
field and `Button("Log").keyboardShortcut(.defaultAction)`, and the Log button
is enabled exactly when the exchange is valid — which is the stale-prefill state
niggle 5 describes. Collapsing those to one path is cheap hardening if the
symptom ever returns.

## 1. Band map stays visible when another app takes focus

`BandMapPanel.make` sets `panel.hidesOnDeactivate = false`, with a comment
naming the AppKit default it is overriding. With the existing `.floating` level
the map then sits over SmartSDR permanently, which is the point — a panadapter
on one side, the spots on the other.

No unit test: this is a single AppKit window property with no seam worth
inventing. Verified by build; behavior confirmed by the operator.

## 2. ⌘↑ / ⌘↓ step spots

`KeyMonitorGate.commandAction` gains two rows:

| Key code | Key | Action |
| --- | --- | --- |
| 126 | ↑ | `.nextSpot` |
| 125 | ↓ | `.previousSpot` |

`BandMapScale` draws high frequency at the top, so ⌘↑ means "up the map", which
is the higher frequency, which is what ⌘→ already does. Both pairs stay bound;
this is an addition, not a replacement.

The monitor consumes the key inside the document window, so ⌘↑ / ⌘↓ no longer
reach a text field as move-to-start/end-of-document. That trade is already made
for ⌘← / ⌘→ and is unchanged in kind.

## 3. Worked-before table

A history table between the messages row and the log table, listing every prior
contact with the call in the entry field:

```
Worked K5NA
Band  Mode  Time    Loc
20m   SSB   1531Z   JO
40m   CW    1402Z   JO
80m   CW    2210Z   JO
15m   CW    1846Z   JO
KSQP 2025 — JO
```

- It exists only while there is history to show. An unworked call costs no
  vertical space at all; the log table takes the room back.
- One entry per on-air contact, not per logged row: a county-line group collapses
  to a single entry whose locations join with `/`.
- Most recent first. Entries on the **current band and mode** render bold and
  orange. Weight as well as colour, so the cue is not colour-alone.
- One trailing grey line when the archive knows the station but this log does
  not: `KSQP 2025 — JO`. This is the same lookup that feeds §4, so it doubles
  as the prefill's provenance caption.
- Rows are not interactive. There is nothing useful to click, and a clickable
  row directly above the log table invites mis-clicks during a run.

### The window never resizes

The table takes its space from the log table, not from the window. Row height is
a layout constant, so the table's height is arithmetic on the entry count rather
than a measurement:

```
tableHeight(entries) = header + rowHeight × min(entries, 6)   [+ archive line]
```

and `logTable`'s `minHeight` is reduced by exactly that. The left pane's minimum
content height is therefore identical whether the table is present or not, which
is what stops macOS growing the window when a match appears. Past six entries
the table scrolls — a station can only be worked bands × modes times, and six
covers any realistic weekend.

### No animation

The table appears and disappears as calls come and go, including on a spot jump.
Animating that would put motion under the operator's eye on every contact, so
the transition is instant. Matching is on the whole callsign, not a prefix, so a
station costs one appearance and one disappearance rather than flickering
through the letters as they are typed.

This replaces the "annoying dupe message" for the call-only case. **The existing
hard `dupeWarning` stays exactly as it is**: it fires on a different and much
rarer condition — the exchange has parsed and this specific contact, same call,
band, mode, my location and theirs, is already in the log. That one is worth
interrupting for, it is already built and tested, and removing it would be a
safety regression.

Logging is never blocked. A rover who has moved county is a new contact under
KSQP rule 10, and `DupeChecker` already keys on both locations.

## 4. Exchange prefill from station memory

When the call field names a station we know something about and the exchange
field is empty (or holds a previous auto-fill), fill the exchange with the best
candidate.

### Candidate order

1. **This log** — the most recent contact with that call, any band or mode.
   County-line groups join with `/`, which is the form the parser accepts.
2. **Archive, same `partyID`** — most recent year first.
3. **Archive, any party** — but only where the archived value was *not* a county
   of that record's party, so a Kansas county never lands in an Alabama log. A
   state, province or `DX` is stable across sponsors; a county abbreviation is
   meaningful only inside the party that defines it.

### Guard

Every candidate is run through `ExchangeParser.parse(_:party:role:)` for the
**current** party and role before it is offered. A candidate that does not parse
is discarded and the next one tried. This is belt-and-braces against a county
abbreviation that collides across two sponsors' county sets.

### Auto-filled vs typed

`EntryState` tracks whether the exchange field holds app-written or
operator-written text:

- The app writes through `autoFill(_:source:)`, which sets the flag.
- The view binds to an `exchangeTyped` accessor that clears the flag on every
  keystroke.

Auto-fill only ever writes into an empty or already-auto-filled field, so it can
never destroy something typed, and it withdraws its own text when the call stops
matching. That property is what makes it safe to run on every keystroke of the
call field.

### Where the archive comes from

Built off the main actor at window open, using the `Task.detached(priority:
.userInitiated)` pattern `DashboardModel` already uses for the dashboard. The
result is an immutable index — `[call: [entry]]`, newest first, each entry
carrying its locations, `partyID`, year, and whether the value was a county of
that party. Until it loads, prefill falls back to the open log. A load failure
is logged and otherwise ignored: this is a convenience, not a correctness path.

### ESM interaction

Unchanged, and already anticipated by `ESM.swift`'s own contract: the call field
never logs, precisely so that a row holding a call *and* a valid exchange keeps
calling. Landing on a spot with both fields filled, Return still calls; Space to
the exchange field, Return logs. No ESM change is part of this work.

## 5. Pending-exchange stash across spot moves

`EntryState` gains `pendingExchanges: [String: Pending]` — call → what the
operator typed but never logged, where `Pending` carries both the exchange text
and the received QSO number, because both are copied in the same breath and both
go stale together.

`MainView.tune(to:)` is the single funnel for spot clicks and ⌘← / ⌘→ / ⌘↑ /
⌘↓. Moving to another station now:

1. Stashes the **typed** exchange (and received QSO number, for serial parties)
   under the outgoing call, when the outgoing call is non-empty and the text was
   not auto-filled.
2. Blanks both fields.
3. Sets the new call.
4. Restores `pendingExchanges[newCall]` as *typed* text if present; otherwise
   runs the §4 prefill.

Typing a call back by hand restores its stash too — the restore hangs off the
call, not off the navigation. Logging a contact drops that call's stash;
auto-filled text is never stashed, because it regenerates.

The received QSO number rides with the exchange deliberately: for CQP a stale
`Ser R` is exactly as wrong as a stale county, and they are copied in the same
breath.

## Files

| File | Change |
| --- | --- |
| `Sources/UI/BandMap.swift` | `hidesOnDeactivate = false` |
| `Sources/UI/KeyMonitorGate.swift` | ⌘↑ / ⌘↓ rows |
| `Sources/Core/Engine/DupeChecker.swift` | `workedContacts(call:log:)` — prior contacts with a call, one entry per `groupID`, most recent first |
| `Sources/Core/Engine/StationMemory.swift` | **new** — archive index, candidate order, parse guard |
| `Sources/App/EntryState.swift` | auto-filled flag, `pendingExchanges`, worked-before list |
| `Sources/App/EntryFlow.swift` | `callChanged(_:)`, `stationChanged(to:_:)` |
| `Sources/UI/EntryBar.swift` | `exchangeTyped` binding |
| `Sources/UI/WorkedBeforeTable.swift` | **new** — the history table and its height arithmetic |
| `Sources/UI/MainView.swift` | table between messages and log, compensating `logTable` min height, archive index load, `tune(to:)` funnel, ⌘↑/⌘↓ dispatch |

Nothing party-specific and nothing radio-specific enters `Sources/UI/`.

## Testing

Everything except the two AppKit lines is a pure function over values and is
tested without hardware, network, or a screen.

- `KeyMonitorGateTests` — ⌘↑ / ⌘↓ map to the same actions as ⌘→ / ⌘←, and the
  existing bindings are unchanged.
- `DupeCheckerTests` — prior contacts for a call, ordering, county-line groups
  collapsing to one entry, band/mode marking; the existing hard-dupe behavior is
  untouched and its tests must stay green.
- `WorkedBeforeTableTests` — **new**: the height arithmetic, including that
  table height plus the reduced log-table minimum equals the unreduced minimum
  for every entry count from zero to past the six-row cap. That equality is what
  keeps the window from resizing, so it is asserted rather than eyeballed.
- `StationMemoryTests` — **new**: candidate order across log and archive; a
  county from another party is rejected; a state from another party is accepted;
  a candidate that fails the current party's parser is skipped; an empty archive
  degrades to the log alone.
- `EntryFlowTests` — auto-fill writes only into an empty or auto-filled field;
  typed text is never overwritten; auto-fill withdraws when the call stops
  matching; stash on station change; restore on return; stash dropped after
  logging; auto-filled text never stashed.

Per Article 7, each regression test is proved red against the current code
before its fix lands.

## Docs

Same commit as the behavior it describes:

- README keyboard table — ⌘↑ / ⌘↓ row.
- README features — the four help strings that currently name only ⌘← / ⌘→
  (toolbar, cluster popover, band map filter popover, hide-worked toggle), plus
  new prose for the worked-before strip, prefill and stash.
- README test count.

## Commit sequence

One niggle per commit, in this order — each independently revertable, and the
first two carry no risk to scoring:

1. `fix:` band map panel survives app deactivation
2. `feat:` ⌘↑ / ⌘↓ step spots
3. `feat:` worked-before table above the log
4. `feat:` exchange prefill from log and archive
5. `feat:` pending exchange stashed per station across spot moves

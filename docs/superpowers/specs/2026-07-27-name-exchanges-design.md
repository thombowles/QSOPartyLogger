# Name exchanges

Design, 2026-07-27. Closes the "THE EXCHANGE CANNOT CARRY A NAME" deferred
engine gap in [`docs/parties/WORKLIST-2026.md`](../../parties/WORKLIST-2026.md),
whose sketch this follows and whose two-user bar is now met: MNQP banked the
gap, and the North American QSO Parties (CW and SSB) are users two and three.

## Problem

NAQP's exchange is a **name and a location, and nothing else** (NCJ rule 10):

> "Exchange: Operator name and station location (state, province, or country)
> for North American stations; operator name only for non-North American
> stations. Each entrant is required to use a single name throughout the
> entire contest period, including multi-operator entries."
>
> — [`naqp_rules_2026.txt`](../../research/naqp_rules_2026.txt), NCJ, fetched
> 2026-07-27

MNQP is the same shape ("MN Stations: First name & county…"). `QSO` has no
name field, so the name is not captured, and `CabrilloExporter.qsoLine` writes
the report/serial slot into the ex1 column the sponsors reserve for the name —
for a party with neither, the **empty string**. Cabrillo is the only accepted
submission format for both sponsors, so the gap blocks submission outright;
it is MNQP's `exportBlocking` caveat today, and NAQP cannot ship without
recreating it. Scoring is untouched throughout — names are not points, mults,
or dupe-key material.

## Scope

This commit adds the **capability and no party uses it** — the serial-number
pattern (`2026-07-24-serial-number-exchanges-design.md`). NAQP CW, NAQP SSB,
and the MNQP fix each turn the flag on in their own later commits (Article 9).

## Decisions

**Names are their own optional fields, not an overload of anything.**
`QSO.nameSent`/`nameRcvd` are `String?`; logs written before this change
decode unchanged (`decodeIfPresent`), and every existing party's exports stay
byte-identical because the fields are nil there (Article 4).

**The sent name is a per-log setting, stamped onto every row.** Both sponsors
require one name for the whole contest, so the operator types it once in
Contest Setup (`ContestLog.exchangeName`, empty for every current log) and
`EntryFlow.logContact` stamps it into `QSO.nameSent` — the row records what
actually went out, and the edit sheet can correct a row where something else
did. Setup prefills it from the first word of the station profile's name and
gates Save on it for a name party, exactly as the location token is gated: a
name party without a name cannot produce one submittable line. Contrast the
serial design, where the *sent* value advances per contact and lives in the
entry row — a name does neither, so it earns a setup field instead.

**The entry row gains one field: the received name.** Focus order for a name
party is call → name → exchange — the name arrives first on the air ("TOM
TX"), and Space walks the row in that order (Article 7). Where a party
exchanged both a serial and a name (none does), the serial keeps its place
ahead of the name; the chain stays total. What was copied for a station that
was never logged stashes and restores with the exchange
(`EntryState.Pending`), so hunting a station costs nothing.

**A name party will not log a contact without a received name.** Rule 12
counts only "a complete, correctly copied and logged two-way exchange", and a
row without the name is the blank-ex1 export this design exists to end. The
gate lives in `EntryFlow.logContact` beside the location gate (and mirrors
into the entry bar's Log button), so the ESM path cannot key a report for a
contact that did not happen.

**Cabrillo's exchange element becomes name → serial → report, driven by the
row.** `exchangeElement(name:serial:rst:)` replaces `exchangeNumber` — same
principle: the exporter reads the QSO's own data and cannot disagree with the
log. A name party's line is `… <call> <name> <loc> …`, the sponsors' own
template (`AC0W BILL MOW N2CU TOM NY`). No bundled party carries two of the
three; the preference order is a decision made now so the code stops saying
"decide later" — a name is the ex1 slot's owner wherever it exists, because
that is what both name-party sponsors print.

**ADIF gains `name`/`my_name` and nothing else moves.** ADIF 3.1.4's fields
for exactly this; `stx_string`/`srx_string` keep carrying locations only, so
every existing party's ADIF stays byte-identical.

**`{NAME}` joins the CW macros** (Article 7): the sent name, from the log's
setting, so an NAQP CW exchange message is `{NAME} {EXCH}`. `MacroToken` is
the single definition; the editor's help list updates itself. Party-specific
default message sets remain out of scope, as they were for serials.

**Not in this change:** name prefill from `StationMemory` (the archive rows
gain names only once a name party has been operated; offer it later), a name
column in the log table (serials set the precedent: the edit sheet is the
correction surface), and any party flag flip.

## Blast radius

| File | Change |
| --- | --- |
| `Core/Models/QSO.swift` | `nameSent`/`nameRcvd` as `String?` |
| `Core/Models/ContestLog.swift` | `exchangeName`, decoded with a default |
| `Core/Models/MacroToken.swift` | `{NAME}` |
| `Core/Parties/PartyDefinition.swift` | `exchangeIncludesName` |
| `Core/Engine/CountyLineExpander.swift` | carry the pair onto every row |
| `Core/Export/CabrilloExporter.swift` | `exchangeElement(name:serial:rst:)` |
| `Core/Export/AdifExporter.swift` | `name`/`my_name` when present |
| `App/AppSettings.swift` | expand `{NAME}` |
| `App/EntryState.swift`, `App/EntryFlow.swift` | received-name field state, stash/restore, the log gate, stamping |
| `UI/EntryBar.swift` | the Name field and the Space chain |
| `UI/SetupSheet.swift` | the exchange-name field, prefill, Save gate |
| `UI/EditQSOSheet.swift` | edit both names on a row |

No party JSON changes here.

## Verification

`Tests/Core/NameExchangeTests.swift`, red first: model and flag defaults
(nil/false everywhere today), the per-log setting's decode default, one name
per contact across a county-line expansion, both exporters (a name party's
line shape, and an existing party's byte-identical output), the `{NAME}`
macro, the logContact gate, and the stash/restore round-trip. The existing
exporter and party suites are the Article 4 proof that nothing moved.

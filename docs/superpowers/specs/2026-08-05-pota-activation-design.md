# POTA activation on any contest — design

**Date:** 2026-08-05 · **Status:** approved for implementation (open calls in §9
default as stated; veto before executing)

KE5CW often runs QSO parties from a POTA park. Any contest log should be able
to double as a POTA activation log: set my park(s) in Contest Setup, capture
the other station's park(s) when they are in one too, and have the one ADIF
export come out in the shape POTA's uploader credits — activation, park-to-park,
n-fers — while scoring, Cabrillo, and every non-POTA log's ADIF stay
byte-identical.

POTA is orthogonal to every party: no party JSON changes, no `Sources/UI`
party branching, no scoring interaction. The whole feature is additive schema +
export + a handful of universal UI seams.

## Sources

- **ADIF 3.1.4 specification** (`https://adif.org/314/ADIF_314.htm`, fetched
  2026-08-05):
  - `MY_POTA_REF`, data type **POTARefList** — "a comma-delimited list of one
    or more of the logging station's POTA (Parks on the Air) reference(s)."
    Spec examples: `<MY_POTA_REF:6>K-0059`,
    `<MY_POTA_REF:40>K-0817,K-4566,K-4576,K-4573,K-4578@US-WY`.
  - `POTA_REF`, data type **POTARefList** — the same for the contacted
    station. Examples: `<POTA_REF:6>K-5033`, `<POTA_REF:13>VE-5082@CA-AB`.
  - **POTARef** grammar — "a sequence of case-insensitive Characters
    representing a Parks on the Air park reference in the form
    `xxxx-nnnnn[@yyyyyy]`": program 1–4 characters, park number 4–5 digits
    (the spec's `K-10000` example notes 5-digit numbers are reserved for
    future use), optional `@` + ISO 3166-2 secondary subdivision of 4–6
    characters for a park spanning subdivisions (`K-4562@US-CA`).
  - `MY_SIG` / `MY_SIG_INFO` / `SIG` / `SIG_INFO`, data type String — the
    special-activity fields; `SIG_INFO` is "a description of the SIG for the
    contacted station."
  - Both POTA fields and both data types were **added in 3.1.4** (changelog).
- **POTA ADIF technical reference**
  (`https://docs.pota.app/docs/activator_reference/ADIF_for_POTA_reference.html`,
  fetched 2026-08-05):
  - Required activator fields: `STATION_CALLSIGN` or `OPERATOR`, `CALL`,
    `QSO_DATE`, `TIME_ON`, `BAND`, `MODE` (submode takes precedence when both
    present). `AdifExporter` already emits every one.
  - POTA processes `MY_SIG=POTA` + `MY_SIG_INFO=<park>` and `SIG=POTA` +
    `SIG_INFO=<park>`. The reference **does not document reading `POTA_REF` /
    `MY_POTA_REF` at all** — the SIG family is what earns credit. When
    `MY_SIG`/`MY_SIG_INFO` are missing or invalid the uploader prompts.
  - The P2P example is a single park per record:
    `<SIG:4>POTA <SIG_INFO:7>CA-0008`.
- **POTA park-to-park reference**
  (`https://docs.pota.app/docs/activator_reference/park_2_park.html`, fetched
  2026-08-05):
  - "Both activators are strongly recommended (although not required) to
    record the park number of the other activator in the ADIF log file's
    `SIG_INFO` ADIF field."
  - Working a three-fer: "list the same QSO three times in the ADIF log file,
    each with one of the three park references in `SIG_INFO`, with the rest
    unchanged." Otherwise "you will only get one P2P credit."
  - Your own multi-park activation dedupes by park reference per line; P2P
    matching wants both logs' times within 15 minutes and exact callsigns.

These quotes are banked as `docs/research/pota/SOURCES.md` in the same commit
as the schema, per the provenance rule. N1MM and other loggers were not
consulted; the two sponsors here are the ADIF spec and POTA's own docs.

---

## 1. Approaches considered

1. **Log-level parks only** — one `[String]` on `ContestLog`, exporter reads
   it. Simplest, but a mid-contest park change (arrive late, leave early,
   drive from park A to park B during a rove-friendly party) silently rewrites
   the whole log's history at export time, and there is no repair story.
   Rejected.
2. **Per-row stamping** *(chosen)* — my parks live on the log as the current
   Setup value and are **stamped into each row at logging**, exactly the
   `exchangeName` → `nameSent` idiom. The export is a pure function of the
   rows; mid-contest changes affect later rows only; `BulkEdit` repairs
   stretches. Their parks are a per-row received fact, like `nameRcvd`.
3. **A separate "Export for POTA…" command** with one file per park —
   rejected: POTA's own reference takes per-QSO `MY_SIG_INFO` in a single
   file ("primarily when an activator is located at multiple parks during the
   same UTC day"), so the one ADIF export can serve the sponsor upload, POTA,
   and LoTW alike. A second exporter is surface with no requirement behind it.

**Export shape sub-decision.** The ADIF spec allows one record carrying a
comma list (`POTARefList`); POTA's uploader documents the opposite — one park
per record, the record **duplicated** per park for credit. A single record
with lists would be spec-pure and lose n-fer credit; duplication is what
POTA's dupe checker is built around. Chosen: **expand records per (my park ×
their park) pair**, each record carrying singular `MY_SIG_INFO`/`SIG_INFO`
*and* singular `MY_POTA_REF`/`POTA_REF`, so no record contradicts itself.
County-line rows already set the duplicated-record precedent in this file.

## 2. Schema (additive, defaults preserve every existing log)

| Type | Field | Default | Meaning |
| --- | --- | --- | --- |
| `ContestLog` | `myPotaRefs: [String]` | `[]` | Normalized park refs from Contest Setup — the *current* value, stamped at logging |
| `QSO` | `myPotaRefs: [String]?` | `nil` | Parks I was in when this row was logged |
| `QSO` | `theirPotaRefs: [String]?` | `nil` | Parks the other station gave (park-to-park) |

- `decodeIfPresent … ?? []` / `?? nil` in the custom decoders, matching
  `exchangeMember`: every `.qplog` written before this feature decodes
  unchanged, and a log with no parks encodes and exports byte-identically.
- Empty array never stored on `QSO`: constructors normalize `[]` → `nil`.
- `CountyLineExpander.QSOEntry` gains both fields (`nil` defaults): one
  contact, one park set each way — every row of a county-line contact carries
  the same parks, same as the serial and the name.
- `ContestRecord` / the archive change **nothing**: the dashboard's ADIF
  re-export loads the saved `.qplog` and re-runs `AdifExporter`, so parks flow
  through it for free.

## 3. `PotaRef` — the one new Core type

`Sources/Core/Models/PotaRef.swift`, an enum namespace like `MemberExchange`:

- `normalize(_ raw: String) -> String?` — trim, uppercase, accept exactly the
  spec grammar `^[A-Z0-9]{1,4}-[0-9]{4,5}(@[A-Z0-9-]{4,6})?$`, else `nil`.
  The grammar comment cites the POTARef definition verbatim with the fetch
  date.
- `parseList(_ raw: String) -> Result<[String], Failure>` — split on commas,
  normalize each token, drop exact duplicates preserving order. Empty input →
  `.success([])`. A bad token names itself in the failure, in the app's
  inline-status voice: `"'USA-331' is not a POTA reference — they look like
  US-3315 or K-4562@US-CA."`
- Spec examples are the acceptance tests: `K-5033`, `K-10000`,
  `VE-5082@CA-AB`, `8P-0012`, `VK-0556`, `K-4562@US-CA`, plus current-era
  `US-0817`; rejects for a missing hyphen (`US3315`), a 3-digit number
  (`US-331`), a 6-digit number (`US-123456`), an interior space (`US 3315`),
  and an over-long suffix (`K-4562@US-CALIF`).

## 4. Export

`AdifExporter.record(…)` gains the pair expansion:

```
mine   = q.myPotaRefs ?? []      → [nil] when empty
theirs = q.theirPotaRefs ?? []   → [nil] when empty
for my in mine × for their in theirs → one ADIF record
```

Per record, grouped immediately before `station_callsign`:

| Condition | Fields |
| --- | --- |
| `my != nil` | `my_sig=POTA`, `my_sig_info=<my>`, `my_pota_ref=<my>` |
| `their != nil` | `sig=POTA`, `sig_info=<their>`, `pota_ref=<their>` |

- No parks → the loops run once, zero new fields, **byte-identical output**
  (asserted against a golden no-parks export).
- My two-fer, their three-fer → 6 records per row, "the rest unchanged" per
  the P2P reference; the shared `app_qsopartylogger_groupid` rides along so
  the copies remain reassociable.
- Both `MY_SIG` values are the literal `POTA` (`<my_sig:4>POTA`).
- Cabrillo is untouched. `ScoreEngine`, `DupeChecker`, `ExchangeParser` never
  read the new fields — a scoring-identity test pins that.

## 5. Contest Setup

New Form section **"POTA Activation"** after Category (universal — every
party shows it):

- One labelled row, the form-repair way: `LabeledContent("My park(s)")` with a
  monospaced, uppercasing text field (~200 pt).
- Caption: comma-separated refs, two-fer example, "leave empty unless
  operating from a park", and that later contacts stamp the *new* value after
  a mid-contest change.
- Malformed list → the caption goes orange with `PotaRef`'s message and
  **Save is gated** (empty always saves). Inline, never a modal.
- `LogDocument.updateStation` gains `myPotaRefs: [String]? = nil` following
  the `exchangeName` parameter pattern, captured in the same undo
  registration.

## 6. Entry bar — park-to-park capture (keyboard-first)

- `EntryState.theirParkTyped: String`, cleared by `clearForNextContact`, plus
  an `invalidTheirPark` check beside `invalidMember`.
- `EntryBar` grows a trailing **"P2P park(s)"** field (~110 pt, monospaced,
  uppercasing), shown **only when the log is an activation**
  (`myPotaRefs` non-empty, passed in as a Bool) — the bar stays exactly as
  it is today for every non-POTA contest.
- **Space never lands there**: `Field.next()` keeps its existing cycle, and a
  new `.theirPark` case routes Space back to `.call`. **Tab reaches it** in
  layout order — the walk-every-field key is the path, the fast cycle is
  undisturbed. Enter logs from it like any field.
- `EntryFlow` refuses to log an unparseable park with the inline red message
  (the member-element precedent: the element decides credit, so it must not
  be mis-keyed in silence); a parsed empty field logs `nil`. My parks stamp
  from `log.myPotaRefs` at the same site as `nameSent`.
- Working the same P2P station again on another band: a provisional grey
  prefill from this log's earlier rows of that call, through the existing
  prefill machinery — last task, cuttable if it fights.

Hunting parks from home (no activation): no bar field — P2P credit does not
exist and hunters submit nothing to POTA — but the row can still be tagged
post-hoc in the editor for the personal record.

## 7. Log repair

- **`BulkEdit.Field.myPotaRefs`** ("My POTA park(s)") — a station-side fact
  in the type's own N1MM sense, same as the rover's `myLoc`. Text value,
  `PotaRef.parseList` validated, **empty clears to `nil`** (unlike
  `nameSent`, where empty is refused — a park-less stretch is a legitimate
  state). Offered for every party, listed last.
- **`theirPotaRefs` stays out of `BulkEdit`** — a received, per-station fact;
  the type's doc comment already draws that line and this feature respects
  it.
- **`EditQSOSheet`**: two new rows, always shown — "My park(s)" and "Their
  park(s)", comma text, validated on Save with the inline message.
- **`LogTable`**: the Flags column gains a small teal `P2P <refs>` label when
  a row carries `theirPotaRefs` — the post-contest scan for park rows without
  a new column.

## 8. Tests and docs

| Area | File | What pins it |
| --- | --- | --- |
| Grammar | `Tests/Core/PotaRefTests.swift` (new) | spec examples accept/reject, list parse, dedupe, message text |
| Schema | `Tests/Core/ModelTests.swift` | legacy JSON decodes to `[]`/`nil`; round-trip with parks |
| Expander | `Tests/Core/CountyLineExpanderTests.swift` | parks ride every expanded row |
| Export | `Tests/Core/AdifExporterTests.swift` | byte-identical without parks; activation triplet; three-fer ×3 records "rest unchanged"; 2×2 cross; county-line × parks; `<my_sig:4>POTA` byte counts |
| Scoring | `Tests/Core/ScoreEngineTests.swift` | identical score with and without parks |
| Flow | `Tests/App/EntryFlowTests.swift` | stamping, refusal, clearing, no-activation nil |
| Document | `Tests/App/LogDocumentTests.swift` | `updateStation` persists + undoes parks |
| Bulk | `Tests/Core/BulkEditTests.swift` | apply, clear-to-nil, validation, label |

README ships in the behavior commit: a POTA feature bullet, the keyboard
table's P2P-field row (Tab reaches it, Space deliberately skips it), the test
count. UI verification is by build + Tom's own eyes, per standing practice —
the Setup row especially (Form label placement passes every test while being
wrong on screen).

## 9. Open calls — defaults chosen, veto before executing

1. **P2P field only while activating** (default) — or always visible?
2. **Flags-column `P2P` tag** (default) — or a dedicated table column?
3. **Malformed P2P park blocks logging** (default, member-element precedent)
   — or log anyway and flag?
4. **`myPotaRefs` offered in bulk edit for every party** (default) — or
   somehow gated?

## Out of scope

POTA spot feeds and self-spotting; a hunter-mode bar field; per-park file
splitting; archive schema changes; SOTA/WWFF references (the schema idiom
would extend, but nothing is added until asked).

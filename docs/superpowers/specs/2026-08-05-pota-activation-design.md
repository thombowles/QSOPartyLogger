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

- **POTA park data API** (verified live 2026-08-05):
  - `GET https://api.pota.app/program/parks/US` — unauthenticated JSON array,
    **12,938 parks** (~2.7 MB), each entry
    `{"reference": "US-0001", "name": "Acadia National Park",
    "latitude": 44.31, "longitude": -68.2034, "grid": "FN54vh",
    "locationDesc": "US-ME", "attempts": 636, "activations": 568,
    "qsos": 18900}`. Every entry carried coordinates on the verification
    date.
  - `HEAD` on the same URL returns **403 MissingAuthenticationTokenException**
    (API Gateway routes GET only) — so freshness cannot be checked the
    SCP way (HEAD + `Last-Modified`); the client re-downloads on a weekly
    throttle instead.

These quotes are banked as `docs/research/pota/SOURCES.md` in the same commit
as the schema, per the provenance rule. N1MM and other loggers were not
consulted; the sponsors here are the ADIF spec and POTA's own docs and API.

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

## 5. Contest Setup — the park picker

*(Revised 2026-08-05 on Tom's direction: a searchable picker with
nearest-parks, not a bare text field; grid square filled from the Mac's
location.)*

New Form section **"POTA Activation"** after Category (universal — every
party shows it), built around a new `PotaParkPicker` view — its own file, so
`SetupSheet` stays inside its type-checker budget and the park directory
never leaks past that seam. The `countyPicker` interaction pattern, already
accepted in this sheet:

- **Selected parks** render as removable chips (reference, monospaced),
  order preserved — this is the list that stamps into rows.
- **One search field**, searching the cached directory by **name or
  number**: every whitespace-separated term must match name, reference, or
  `locationDesc` — so "lake tx" finds Texas lakes, "0088" finds US-0088,
  "cedar hill" finds the park. Results are buttons that toggle selection,
  capped at 30 rows.
- **Query empty → the nearest parks** (12, with miles), measured from the
  Core Location fix when the operator has used the locate button, else from
  the typed grid square's center — so it works fully offline at the park.
  No fix and no grid → the nearest list simply hides.
- **Typed-reference escape hatch:** Return in the search field with a
  string `PotaRef.normalize` accepts adds it directly — the keyboard-only
  path, and the path for a park the directory does not carry (non-US
  programs, brand-new parks, no directory downloaded yet). Nothing invalid
  can enter the selection, so Save needs no park gate.
- `LogDocument.updateStation` gains `myPotaRefs: [String]? = nil` following
  the `exchangeName` parameter pattern, captured in the same undo
  registration.

## 5a. The park directory — download, cache, search

Data source is POTA's own API (see Sources): `GET
https://api.pota.app/program/parks/US`, 12,938 parks with names,
references, and coordinates. Split on the `SCPClient`/`SCPStore` pattern:

- **`PotaPark`** (Core) — `reference`, `name`, `latitude?`, `longitude?`,
  `grid?`, `locationDesc?`; extra upstream keys ignored. Coordinates decode
  optionally so an upstream null tomorrow degrades one park's sorting, not
  the file.
- **`PotaParkDirectory`** (Core, pure) — `parse(data:)`,
  `search(_:limit:)` as above, `nearest(latitude:longitude:limit:)` by
  haversine (sorting accuracy, not survey accuracy). No disk, no network.
- **`PotaParkStore`** (Core) — `SCPStore`'s shape: bytes as served plus a
  meta sidecar (`fetchedAt`, `lastCheckedAt`) under
  `Application Support/QSOPartyLogger/POTA/`.
- **`PotaParkClient`** (App, `@MainActor @Observable`) — `SCPClient`'s
  posture: quiet by construction, cached copy published before any network,
  errors inline in the status row, never a modal. One difference, forced by
  the API: **no HEAD freshness check** (HEAD returns 403 there — Sources),
  so `refreshIfStale` re-downloads after **7 days** (parks churn slowly; a
  week-old list still locates you) or on the operator's Refresh.
- **First download is explicit.** The status row offers "Download the park
  list (≈3 MB)" when no cache exists — every party's Setup shows this
  section, and a non-POTA operator should never pay the download silently.
  With a cache: status text (park count, fetched date) + Refresh, the
  `callHistoryRow` shape.
- **Scope: the US program list.** Tom activates US parks; the typed-
  reference path covers everything else. Adding programs later is a second
  URL through the same store, keyed by program.

## 5b. Grid square from the Mac's location

- **`Maidenhead`** (Core, pure): `locator(latitude:longitude:)` → 6-char
  grid (EM13LE form), `center(of:)` → coordinates for a 4- or 6-char grid.
  Both directions tested against known anchors (W1AW → FN31PR).
- **`LocationProviding`** (App seam): `isAuthorized`, `canRequest`,
  `currentLocation() async -> (latitude, longitude)?`. Live
  implementation `MacLocationProvider` wraps one-shot
  `CLLocationManager.requestLocation()` with a timeout; tests script
  positions and never touch Core Location (the keying-seam lesson).
- **Setup behavior:** the grid square stays a free-text field, always.
  Beside it, a **Locate** button fills it from the Mac's location (and
  remembers the fix as the nearest-parks origin). On sheet open, if the
  grid is empty **and authorization is already granted**, it fills
  silently — the permission dialog only ever appears from the button press.
  A failed fix sets an inline caption ("Couldn't get a location — type the
  grid square instead") and the field remains free text, per direction.
- **Sandbox:** the app is sandboxed, so this adds the
  `com.apple.security.personal-information.location` entitlement and an
  `NSLocationUsageDescription` string to `project.yml` (the pbxproj and
  plists are generated — never edited by hand).

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
| Grid math | `Tests/Core/MaidenheadTests.swift` (new) | W1AW → FN31PR and other anchors both directions, edge clamps, rejects |
| Directory | `Tests/Core/PotaParkDirectoryTests.swift` (new) | parse of a real-entry fixture, name/number/state search, nearest ordering, haversine sanity |
| Park cache | `Tests/Core/PotaParkStoreTests.swift` (new) | save/load round trip, meta sidecar, missing-sidecar posture |
| Park client | `Tests/App/PotaParkClientTests.swift` (new) | scripted fetcher — download, publish-cached-first, 7-day throttle, forced refresh, failure keeps cache |
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
5. **Directory scope: the US program only**, with typed references covering
   the rest (default) — or download further programs?
6. **Weekly re-download, explicit first download** (default) — or a
   different staleness / auto-download posture?

## Out of scope

POTA spot feeds and self-spotting; a hunter-mode bar field; per-park file
splitting; archive schema changes; SOTA/WWFF references (the schema idiom
would extend, but nothing is added until asked); non-US program downloads
(typed references cover them); live per-keystroke queries against
api.pota.app (the cached directory searches offline, which is what a park
without cell coverage needs).

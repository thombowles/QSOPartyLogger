# Call history file support — design

**Date:** 2026-07-28
**Status:** approved for implementation (autonomous session; decisions recorded
here for Tom's review)

## What this is

N1MM-style call history: when the operator types a call, the app offers what a
curated per-contest file says that station sends — county, name — before the
first contact is ever made. The files are the N1MM Logger+ community's call
history files (maintained mostly by VE2FK, per-party), downloaded automatically
for the active party, cached locally, and refreshed when the site lists a newer
revision.

What it is **not**: authority for anything. Constitution Article 1 stands —
N1MM files are never authority for a rule. A call history value is an operating
*hint*: it is parse-checked through the party's own `ExchangeParser` before it
is offered, it never reaches `ScoreEngine`, and what the operator actually
copies always wins. The files themselves say it: "This is helping file, LOG
what you copy."

## Provenance

- **File format:** N1MM Logger+ documentation, "Call History Lookup"
  (`n1mmwp.hamdocs.com/setup/call-history/`, fetched 2026-07-28): comma- or
  semicolon-delimited; default field order `Call, Name, Loc1, Loc2, Sect,
  State, CK, BirthDate, Exch1, Misc, Power, CqZone, ItuZone, UserText`;
  `!!Order!!` directive re-declares the order; `#` starts a comment; field
  name case is not important; other `!!…!!` directives exist and are ignored
  here.
- **File inventory:** `n1mmwp.hamdocs.com/mmfiles/categories/callhistory/`
  (504 files, 11 pages, scraped 2026-07-28, banked at
  `docs/research/n1mm_callhistory_inventory.json`).
- **Download mechanics:** observed 2026-07-28 (see research doc): each file
  has a page at `/mmfiles/<slug>/` whose CM Download Manager form POSTs
  `cmdm_nonce` + `id` to `/mmfile/get/file/<FILENAME>`; the listing supports
  server-side search (`CMDsearch=`) and `sort=newest`.
- Per-file observations (headers, field orders, party tokens) are in
  `docs/research/n1mm_callhistory.md` with fetch dates.

## Decisions (with the alternatives they beat)

1. **Discovery is at runtime, by listing search; the party JSON carries only a
   stable prefix.** Filenames embed revisions (`QSOP_AL-2026-002.txt`) and
   every revision gets a new page slug, so a bundled URL goes stale mid-season.
   The alternative — bundling the newest URL and regenerating per revision —
   loses exactly when it matters, the week VE2FK refreshes files before a
   party. Runtime search on the stable prefix (`CMDsearch=QSOP_AL`,
   `sort=newest`) always resolves the current revision, at the cost of parsing
   listing HTML (a cost this codebase already accepts for the hub, with the
   same drift stance: parse strictly, stop loudly on mismatch, never guess).
2. **Filename match is prefix + separator.** A file belongs to a party when
   its name starts with the prefix followed by `-`, `_` or `.` — so Nebraska's
   `QSOP_NE` cannot claim `QSOP_NEWE-…` (New England) and Indiana's `QSOP_IN`
   cannot claim `QSOP_IN7QPNE_DE-…`.
3. **Files verify themselves by token.** The files declare who they serve in
   comments (`# QSOPARTY AL`, `# NAQPCW`). After download, if the party's
   expected token is not among the file's comment lines, the file is rejected
   and the previous cached copy kept. Belt and braces against the search
   returning a lookalike.
4. **The combined May file is cached per party.** `QSOP_IN7QPNE_DE` serves
   five bundled parties (inqp, sevenqp, newenglandqp, deqp, in7qpne), each of
   which carries the same prefix and its own token. Five ~60 KB copies beat a
   shared-cache coupling.
5. **Prefill priority: this log → archive → call history → spot.** Own copies
   outrank third-party data of the same vintage; the curated file outranks a
   stranger's live spot claim (matching the existing archive-over-spot
   ordering). Call history text is provisional grey like every auto-fill, but
   does **not** get the orange unconfirmed treatment — that stays reserved for
   spots, the weakest evidence. A caption line names the source instead.
6. **Names auto-fill with the same ownership rules as the exchange.** NAQP and
   MNQP exchange names; the files carry them. Auto-filled names must clear
   when their call leaves the field, so `EntryState` grows the same
   auto-fill/typed distinction for `nameRcvd` that `exchange` already has.
   (Without it, a station change would carry TOM to the next station's row.)
7. **Auto-download defaults on, like `hubSpotsEnabled`; one toggle in
   Preferences.** Refresh checks run on party selection and at most every 24 h
   per party, off the entry path, failing quietly (`lastError` + console, old
   file kept). Never during Return handling; never blocking.
8. **Parties with no file carry no field.** azqp, mdc, vtqp have no N1MM call
   history file today (verified against the full inventory). A roster test
   pins the split, so a future party addition has to decide explicitly.

## Components

| Unit | Purpose | Depends on |
| --- | --- | --- |
| `CallHistorySource` (Core/Parties) | JSON schema: `filePrefix`, `token`; filename match rule | — |
| `CallHistoryFile` (Core/CallHistory) | Parse file text → `CallHistoryIndex` (call → name/locations/tokens); candidate lookup, parse-checked per party | ExchangeParser |
| `CallHistoryPageParser` (Core/CallHistory) | Listing HTML → `[Listing]` (title, pageURL, date); file page HTML → form (action, nonce, id) | — |
| `CallHistoryStore` (Core/CallHistory) | Disk cache: `<partyID>.txt` + `<partyID>.meta.json` in Application Support/CallHistory; atomic writes; injectable folder | — |
| `CallHistoryClient` (App) | Orchestration: stale check → search → page → POST → verify token → store → publish index; status/console; `CallHistoryFetching` protocol seam | all above |
| `EntryFlow`/`EntryState` | Third origin `.callHistory`; name auto-fill ownership; priority chain | CallHistoryIndex |
| UI | Setup-sheet status + Refresh button (keyboard-reachable), Preferences toggle, worked-before hint line | client |

### Parser rules (from observed files)

- `!!Order!!` may appear after comments (PA), with spaces around names (WA),
  with a trailing comma (AL), and omitting `Name` (TX, NE, PA). Unknown field
  names are honored positionally and ignored; recognised: Call, Name, Exch1,
  Sect, State, UserText (Loc1/Loc2/CK/… parsed past, not stored).
- No `!!Order!!` → the documented default order.
- `#` comment lines collected; comment text (stripped, uppercased) is the
  token set for verification (`QSOPARTY AL`, `NAQPCW`).
- Other `!!…!!` directive lines ignored.
- Comma **or semicolon** delimited (docs); CRLF and blank lines tolerated;
  UTF-8 with Windows-1252 fallback.
- Duplicate call: later rows win **per field**, never blanking an earlier
  one — the real Alabama file lists WA1FCN once with his county
  (`WA1FCN,,WLKR,WALKER`) and once with his name (`WA1FCN,BOB,`) in a
  separate roster section, and both halves must survive. (Found by running
  the full downloaded file through the parser; whole-row last-wins lost the
  county.)
- Lookup: exact normalized call; on miss, the *typed* call is retried with
  portable suffixes stripped (`AA2IL/6` → `AA2IL`). Exchange candidate = first
  of Exch1, Sect, State that the party's parser accepts for the operator's
  role (this is how NAQP's `State` column, PA's sections, county-line values
  like `NSHRM/NSCOL`, and DX prefixes like `8P` all resolve without
  special-casing). Name candidate = Name, only for name parties.

### Client flow (`refreshIfStale(party:)`)

1. Skip unless enabled, party has `callHistory`, and last listing check for
   this party is >24 h old (or forced by the Refresh button).
2. GET category listing with `CMDsearch=<prefix>&sort=newest&view=list`; parse
   entries; take the first whose filename matches prefix+separator.
3. If it matches the cached meta (same source filename **and** listed date):
   record the check, done.
4. GET the file page; parse form action + nonce + id (cookies kept in the
   session).
5. POST; reject non-200 or HTML-shaped bodies; decode; parse; verify token;
   require ≥1 record.
6. Atomic write file + meta; publish the new index to `EntryFlow`.
7. Any failure: `lastError` + console line, cached file stays in service.

## Testing (Article 5 — no network)

- Parser: every rule above, driven by fixture strings taken verbatim from the
  downloaded files (AL, TX, WA, NE, PA, NAQP, KS headers and rows).
- Page parsers: banked listing/file-page HTML fixtures; a reshaped page is an
  explicit error, not a silent zero.
- Store: temp-folder round-trips, atomicity, missing/corrupt meta.
- Client: `CallHistoryFetching` mock scripted per step — happy path, same-file
  short-circuit, token mismatch keeps old file, network failure keeps old
  file, HTML-instead-of-file rejected.
- EntryFlow: priority chain (log beats file; file beats spot), clearing on
  call change, name auto-fill ownership, no-file parties unaffected.
- Roster: exactly which bundled parties carry `callHistory` (45) and which do
  not (azqp, mdc, vtqp — no file exists upstream).

## Future work (out of scope, recorded)

- User-supplied local call history files overriding the download (the party
  JSON override path exists; a file drop-in does not yet).
- Reverse suffix matching (file has `AA2IL/6`, operator types `AA2IL`).
- A UserText surface (mobile/bonus notes are parsed and stored but shown only
  in the worked-before hint line).

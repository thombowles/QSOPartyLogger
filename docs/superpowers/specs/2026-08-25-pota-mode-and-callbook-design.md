# A dedicated POTA mode, and callbook lookup — design

**Date:** 2026-08-25
**Status:** approved by the operator in session (approach A; meter shown
wherever he is activating). The choices under *Decisions* are his to overturn,
and each names the alternative
**Kind:** three phased efforts — a v2 contest plus additive schema, a new
lookup subsystem, a spot-feed extension. Schema refactors quarantined from the
data commits; the golden corpus and export fixtures byte-identical throughout
**Origin:** the operator, 2026-08-24: "add a pota 'contest' mode, where it's a
dedicated pota logger. Add QRZ and hamqth look up support. check polo ham2k
for refinement ideas."

## Why

POTA in this app today is an *overlay*: every party's Setup carries the park
chips, the entry bar grows a P2P field while activating, and the ADIF export
writes the SIG family with per-(my park × their park) n-fer expansion. That
was built for "activating a park during a QSO party." What does not exist is
POTA *by itself* — open the app on a Tuesday at a park, log an activation, and
submit it. There is no POTA entry in the picker, no per-UTC-day dupe rule, no
count toward the ten QSOs that validate an activation, no per-park submission
file, no way to hunt from the POTA spot board, and no idea who anyone is.

Ham2K's PoLo is the reference logger for that job, and it was surveyed on the
operator's instruction (sources in §PoLo). Its two structural lessons: the
park is a property of the *outing*, not of any QSO; and lookup data is
advisory garnish around a fast entry row, never part of the exchange. Its one
structural gap: no radio. This app owns CAT, so "PoLo's flow with a radio
attached" — spot-click QSY, real band/mode from the rig — is the target.

## What already exists (and is not rebuilt)

- `PotaRef` grammar, park model, offline park directory with nearest-park
  search, the weekly-throttled `PotaParkClient`, and the park picker on every
  party's Setup (`docs/superpowers/specs/2026-08-05-pota-activation-design.md`).
- `QSO.myPotaRefs`/`theirPotaRefs` sidecars, P2P capture in the entry bar,
  bulk edit, county-line expansion carrying parks.
- `AdifExporter`'s SIG/SIG_INFO n-fer pair expansion — POTA's own documented
  shape, one record per (my park × their park).
- Self-spotting to `api.pota.app/spot` from the ⇧⌘S sheet, with board
  confirmation (`docs/research/pota/SOURCES.md`).
- The general contest model: `ContestDefinition` v2, `ScoreEngine` on it,
  exporters derived from the exchange spec, `ContestCatalog` with a user
  override folder (`2026-08-17-general-contest-logger-design.md`).

## Approaches considered

1. **POTA as the first bundled v2 `ContestDefinition`, through thin generic
   seams.** Author `Resources/Contests/pota.json` against the general model
   (zero-point rules, no multipliers); extend the schema additively where POTA
   genuinely does not fit (a per-UTC-day, per-my-park dupe dimension); teach
   the three party-shaped UI surfaces — picker, entry row, sidebar — to read
   the general model *just enough* for a contest that has no
   `PartyDefinition`. Everything POTA-specific stays data-driven; no
   `id == "pota"` branch in UI. Pulls forward two thin slices of the approved
   Plan 3 (picker entries from `ContestCatalog`; exchange-spec-driven layout
   for the nil-party path only) without changing how any party renders or
   scores. **Chosen.**
2. **POTA as a v1 `PartyDefinition`.** In the picker for free, but v1 is
   hard-wired to home state + counties, and the general-contest design
   explicitly stopped growing `PartyDefinition`. Fights the schema for zero
   long-term value.
3. **A bespoke POTA surface outside the contest model.** Own window, own log
   type — the highest UX ceiling, but it forks "the engine is the model,"
   duplicates entry/undo/export machinery, and its logs vanish from the
   logs-folder history and season stats.

## Decisions

1. **One log kind, park optional.** A POTA log with parks set is an
   activation — validity meter, per-park submission export. With no park it
   is a hunter log — the their-park field still captures every hunted ref.
   *Alternative:* separate activator and hunter log kinds — two picker
   entries for one behavior switch a chip already expresses.
2. **The activation panel is data-driven, and appears wherever he is
   activating.** Any log whose `myPotaRefs` is non-empty shows it — including
   a QSO party worked from a park, where the same log feeds both submissions.
   Matches how the park chips and P2P field already work on every party.
   *Alternative:* gate it to the POTA contest — hides the meter exactly when
   a party activation needs it.
3. **Hunting feeds the existing band map; no new spot pane.** `SpotSource`
   gains `.pota`, `Spot` an optional `park`, and the board poll fills the map
   the cluster already fills. Click/Return: QSY plus call + mode + their-park
   prefill. *Alternative:* a dedicated POTA spot board — a second spot UI to
   maintain, and the map already owns tune-to-spot, worked-dimming, and the
   `usedSpots` integrity stamp.
4. **Lookup shows everywhere; it writes only where the contest says so.** The
   info line (name · state · grid · distance/bearing) renders by the call
   field in every log, in the call-history caption's quiet style. A lookup
   never auto-fills a received exchange field anywhere — the exchange is what
   was sent on the air. Stamping name/state/grid/QTH into the QSO happens
   only when the contest definition sets `enrichFromCallbook` (POTA sets it;
   no party does). *Alternative:* prefill exchange fields from lookup — a
   logger that writes down what QRZ says instead of what the operator heard.
5. **Enrichment is a sidecar, not exchange data.** `QSO.callbook`
   (name/state/grid/qth + source), optional, additive, structurally invisible
   to `ScoreEngine` — the same shape and reasoning as the POTA sidecars.
   `AdifExporter` emits `NAME`/`STATE`/`GRIDSQUARE`/`QTH` from it when
   present. *Alternative:* write into `rcvd` — blurs on-air data with
   database data, the provenance line this repo does not cross.
6. **Two services, priority order, no merging.** QRZ XML and HamQTH each get
   a client; the primary is queried first and the other is the fallback on
   miss or error. Fields from different services are never combined into one
   record — a record's provenance is one service. Default primary when both
   are configured: **HamQTH**, because the operator's QRZ account is the free
   tier (name-only; QRZ does not officially enumerate the free field set —
   banked as an open question), while HamQTH is free and full.
   *Alternative:* merge best-of-both — richer rows, unattributable.
7. **Credentials live in the login Keychain.** First Keychain use in the app
   (`SecItem`, generic password, service per lookup provider). Named risk:
   with ad-hoc signing, a rebuilt dev binary may re-prompt for access — the
   same churn class as the existing TCC resets; release identities are
   stable. *Alternative:* a plaintext file in Application Support — honest
   about being readable, and worse in every other way.
8. **Lookups are cached on disk, debounced, and cancellable.** A 30-day TTL
   cache keyed by call (capped, LRU) sits in front of both services so a
   day's allowance — QRZ reports the 24-hour count but publishes no cap —
   is never spent twice on one call. A lookup fires only
   after the call field settles on a plausible call, is cancelled by the next
   keystroke, and never blocks entry. Sessions follow each service's own
   contract: QRZ's key is cached and reused, re-login only on
   `Session Timeout` (per-lookup login invites their 24-hour refusal);
   HamQTH re-authenticates on its documented one-hour clock.
9. **POTA's dupe scope arrives as two additive `DupeRule` flags.** `utcDay`
   (the UTC day joins the key) and `perMyPark` (the sorted own-park list
   joins the key), both defaulting false — every party keys exactly as
   today, proven by the untouched golden corpus. POTA sets both with scope
   `bandMode`: a new UTC day resets dupes, and a rove to a new park resets
   dupes, which is POTA's per-activation scoring. Dupes flag and count zero;
   they never block logging. *Alternative:* a new `Scope` case — the day and
   the park are orthogonal to band/mode scope, and a case product explodes.
10. **The validity meter counts unique (call, band, mode, UTC day) per own
    park.** Whether POTA's checker also dedupes the ten is not in their
    published rules; the meter states the stricter convention (PoLo's), which
    can only under-promise. Banked as an open question in
    `docs/research/pota/SOURCES.md` — the meter is advisory UI, never a
    score. *Alternative:* count raw QSOs — a meter that can claim a valid
    activation the program then rejects.
11. **"Export for POTA…" writes one file per own park,** named
    `CALL@PARK-YYYYMMDD.adi` (a park logged with an `@subdivision` keeps it
    in the name, POTA's multi-state convention; the date is that park's
    first QSO's UTC date). Offered on any log with own parks. Records in each file
    carry that park's `MY_SIG_INFO` with the existing P2P pair expansion.
    The generic ADIF export is untouched, byte-identical. *Alternative:* one
    combined file — POTA's rules require a separate log per park, and the
    2026-08-05 decision not to split was made for party logs where POTA
    upload was secondary; a dedicated mode's whole point is submission.
12. **Their-park joins the Space cycle in POTA logs.** In parties, Space
    deliberately skips `.theirPark` (P2P is the exception there); in a POTA
    log it is the primary received datum and sits in the cycle after the RST
    fields. Tab reaches everything in both. Driven by `EntryLayout`, not by a
    contest id. *Alternative:* keep Space skipping it — the one field a POTA
    hunter fills every QSO would be the one field Space cannot reach.
13. **Park entry gets PoLo's smart expansion.** Digits alone (`2518`) expand
    against the cached park directory to the unique matching reference
    (`US-2518`) with the park's name echoed in the caption; the existing
    grammar validation and refuse-to-log behavior stay. Expansion is a
    convenience over the directory, never a guess: no directory, no match, or
    an ambiguous match leaves the text as typed. *Alternative:* prefix-guess
    from the station's DXCC like PoLo — inference where a bundled directory
    can answer exactly.
14. **Messages: an additive `cqLabel` and a `{MYPARK}` macro.**
    `ContestDefinition.cqLabel` (optional; POTA sets `"POTA"`) lets the
    default message composer produce `CQ POTA {MYCALL}` instead of a bare
    CQ; `MacroToken` gains `{MYPARK}` (own refs, space-joined), available in
    every message editor. Parties are unaffected — no party sets `cqLabel`,
    and `{MYPARK}` expands to nothing where no park is set.
15. **Phase order: POTA mode, then callbook lookup, then band-map hunting.**
    The mode is the headline and stands alone; lookups are the operator's
    listed second and enrich the mode when they land; hunting completes the
    story. Each phase is its own worktree, spec-discipline commits inside
    (schema refactor commits carry no data; `pota.json` arrives alone).
16. **Constitutional posture: POTA is neither a party nor a radio.** Parts
    II/III of the constitution do not bind it (no 14-section party research
    template, no per-party test floor as written) — but the common law does,
    and this spec adopts it explicitly: provenance with fetch dates for every
    rule and protocol fact (Article 1), additive schema with the corpus as
    proof (Article 4), tests without network (5), docs in the same commit
    (6), keyboard-first (7), verification by command output (8), one concern
    per commit (9). No constitutional amendment is needed; if a third
    recurring job ever grows its own articles, that is a later, separate
    decision.

## The POTA contest definition

`Resources/Contests/pota.json`, schema 2 — the first bundled v2 contest, so
`Resources/Contests/` joins `project.yml`'s resource folders and
`ContestCatalog.loadBundled` finds it where it already looks. User overrides
by id from `~/Library/Application Support/QSOPartyLogger/Contests/` work
unchanged.

- One side (`all`, predicate `always`); every entrant sends the same shape.
- Exchange: `rst` only, `required: false`, prefilled 59/599 as everywhere
  else. No location element — POTA has no exchange to validate, and the
  absence is what folds the location field out of the entry row.
- `points`: a single default rule of 0. `multipliers: []`. No bonuses, no
  score factors, no operating-time rule, no schedule (POTA is always on).
- Bands: all fourteen `Band` cases — WARC and 60 m are legal in POTA and
  already in the enum. Modes: phone, CW, digital.
- `dupe`: scope `bandMode`, `locationSensitive: false`, `utcDay: true`,
  `perMyPark: true` (decision 9).
- `cabrillo.contest: "POTA"` to satisfy validation, with additive
  `cabrillo.submittable: false` — no Cabrillo is offered for this contest
  (nothing else reads the flag; every party defaults true).
- `potaProgram: true` — one additive top-level flag, default false, meaning
  "this is a POTA program log": the their-park field is always visible and
  in the Space cycle (decision 12), and the band map's POTA feed defaults
  on. One declaration rather than a flag per symptom; parties never set it.
- `enrichFromCallbook: true` (decision 4), `cqLabel: "POTA"` (decision 14).
- `notes` carry provenance: rules URL, fetch date, and the open questions
  from decision 10.

Every new field is optional with a default that reproduces today's behavior;
the golden corpus (`Tests/Fixtures/Equivalence/engine-golden.json`) and export
fixtures are the proof, unre-recorded.

## Picker and setup

`SetupSheet`'s picker entries come from a catalog call that appends bundled
and user v2 contests after the party entries — parties keep their exact
current entries, order, and combined-entry nesting. The POTA row reads
"Parks on the Air (POTA)". `suggestedParty(on:)` is untouched: POTA has no
schedule and is never auto-suggested over a running party.

A POTA log's Setup is the existing sheet: the universal POTA section *is* the
activation setup (chips, search, nearest); category and location controls that
have no meaning for a contest without them stay hidden by the same
nil-party/absent-element logic the entry row uses. New-log defaulting is
unchanged (`ksqp`); POTA is picked, not guessed.

## The entry row: `EntryLayout`

A small pure struct — the row's shape, computed once per contest change:

```
EntryLayout { showsRST, showsSerial, showsName, showsMember,
              showsLocation, locationLabel, showsTheirPark,
              theirParkInSpaceCycle }
```

For a log with a `PartyDefinition`, it is derived from the same v1 flags the
row branches on today — provably identical rendering, asserted across all 50
parties. For a v2-only contest it derives from the exchange spec and
`sources`: POTA yields call + RST S/R + their-park, no location field,
their-park in the Space cycle. `EntryBar` consumes the struct through the
existing opaque seams; `MainView`'s pane gains no inline logic (its
type-checker budget is a standing constraint). Field validation on the
nil-party path goes through `ExchangeValidator` on the contest — the party
path keeps `ExchangeParser` untouched until Plan 3 retires it.

ESM is already shape-agnostic (`callEmpty`/`ExchangeState`/`Cursor`) and needs
no change; with RST prefilled, Return under ESM logs-and-sends exactly as in a
party. F-keys, Esc, ⌘= speed, Repeat CQ: unchanged.

## The activation panel

A new opaque section in `ScoreSidebar`, shown when the log's `myPotaRefs` is
non-empty (decision 2), above the party sections when both apply:

- **n/10 per park for the current UTC day** — unique (call, band, mode) count
  (decision 10), a meter that fills at ten and states the count plainly
  ("7 of 10 today at US-1234"). Multiple parks each show their own line —
  every QSO counts at every simultaneously-activated park.
- **P2P tally** — QSOs carrying a their-park, and the distinct parks hunted.
- **Band × mode split** for the day, the same table shape the party sections
  use.
- **UTC midnight countdown** once within two hours of rollover — the day
  boundary is the one clock an activator must not miss.

Computed by a pure `PotaStats` in Core from the log rows — never by
`ScoreEngine`, which continues to know nothing about parks. For a POTA log
the sidebar otherwise shows its contest-agnostic pieces (totals card with QSO
count, advisor); zero-point totals are correct, not a bug. The panel has no
collapsing state to remember beyond what sidebar sections already do.

## Export for POTA

A new export action (menu + keyboard, beside the existing Cabrillo/ADIF
items), enabled when the log has own parks. For each own park that appears on
any row: one `.adi` named per decision 11. Parks are stamped per row, so each
row lands in the file of each park it carries and a rove's rows split into
their parks' files naturally; each file's records carry that one park as
`MY_SIG_INFO`, with P2P pair expansion within the file as today. The filename
date is that park's first QSO's UTC date. A save panel picks the destination
folder once; the files land beside each other. The action reports what it
wrote — n files, n records each — inline, in the export UI's existing style.

`AdifExporter` grows a per-park filtered entry point; the unfiltered export
path and its fixtures do not change. New byte-identity fixtures pin the
per-park split, including a rove and an n-fer.

## Hunting: the POTA feed in the band map

- `SpotSource.pota`; `Spot.park: String?`. Identity stays call + band, so a
  respot replaces.
- A `PotaBoardClient` (App layer, `…Fetching` seam) polls
  `GET https://api.pota.app/spot/activator` — unauthenticated, shape banked
  in `docs/research/pota/SOURCES.md` — on a 60 s cadence while enabled,
  honoring each row's `expire`, mapping mode words and kHz strings
  defensively (both observed forms banked). `invalid`/`QRT` rows drop.
- Enablement is a band-map source toggle beside the cluster/hub sources,
  defaulted from the front log's contest `potaProgram`, overridable per
  log like the other feeds. A party log can turn it on (hunting P2P during a
  party is real); a POTA log can turn it off.
- Click/Return on a POTA spot: QSY (CAT), prefill call + mode + their-park
  through the existing spot-prefill path with its dashed-orange spot origin.
  Worked-dimming and `usedSpots` stamping apply exactly as for cluster spots.

## Callbook lookup

**Core (`Sources/Core/Lookup/`)** — pure, tested against captured XML:

- `CallbookRecord`: call, name, grid, state, county, qth, country + DXCC
  entity id, source, fetchedAt. QRZ mapping uses `land`/`dxcc` for the
  entity — `country` there is the QSL mailing address, a banked gotcha.
- `QRZXMLParser` / `HamQTHParser` on Foundation's `XMLParser`,
  namespace-tolerant, matching local names case-per-service (QRZ
  Capitalized, HamQTH lowercase), treating the version attributes as data
  (live servers already run ahead of both published specs). Error and
  message elements parsed on every response — QRZ's non-subscriber signal is
  a `Message` beside valid data, not an `Error`.
- Session state machines as pure types: QRZ (key cached, reused, re-login on
  `Session Timeout` only; `Connection refused` backs the client off a full
  day — their documented refusal), HamQTH (one-hour key, `prg` parameter
  mandatory, re-auth on expiry error).

**App (`Sources/App/`)** — `CallbookClient` (`@MainActor @Observable`) owning
service order (decision 6), the debounce/cancel discipline and the disk cache
(decision 8), a capped console like every other client, and inline status.
Credentials via a small `KeychainStore` (decision 7) — the only new
capability; no entitlement change is expected for the login keychain, and the
first run's access prompt is documented in the README.

**Settings** — a Lookup section: per-service username + password
(`SecureField`), enable toggles, primary picker (default per decision 6), and
a "Check credentials" button per service that performs one live session
request and reports inline by the control — never a modal, and the button
claims nothing before it has been pressed.

**Display** — the info line by the call field, quiet-caption style: name,
state, grid, distance and bearing (computed from the station grid, the same
math the park picker uses). Tooltip carries the full record and its source.
Renders in every log; absent silently when there is no record, no configured
service, or no network — a lookup failure is a caption that does not appear,
plus the client console for whoever goes looking.

**Enrichment** — on logging a QSO in a contest with `enrichFromCallbook`: the
current record for that call, if any, stamps `QSO.callbook` (decision 5).
Editing the call clears the pending record; the stamp is what the operator
saw at logging time. `AdifExporter` emits `NAME`/`STATE`/`GRIDSQUARE`/`QTH`
from the sidecar in every export where it is present.

## Testing

- No test opens the network: every client behind its injected fetcher;
  captured QRZ/HamQTH XML (success, error, non-subscriber message, session
  expiry) and POTA board rows as fixtures beside the existing samples.
- Schema additions proven by the untouched golden corpus and export
  fixtures; the dupe flags additionally proven red-first — a POTA-shaped log
  keyed with flags off must produce yesterday's dupe verdicts.
- `EntryLayout` equality across all 50 parties against the current flag
  branches; POTA's layout asserted field by field, including the Space
  cycle.
- `PotaStats` over crafted logs: UTC-day boundaries, roves, n-fers, dupes
  excluded from the meter, P2P tallies.
- Per-park export byte fixtures (rove, n-fer, hunter-only log producing no
  files); existing ADIF fixtures byte-identical.
- Session state machines driven through scripted responses: QRZ timeout →
  one re-login; refused → day-long backoff; HamQTH hour expiry → re-auth;
  cache hit produces no fetch at all.
- UI-adjacent behaviors (picker entries, park expansion, check-credentials
  status) through their behavior types, the `PotaPickerBehavior` pattern.

## Provenance and docs

Before each phase's code, in that phase's first commit:

- `docs/research/pota/SOURCES.md` gains the rules facts this design leans on,
  quoted verbatim with fetch dates: the 10-QSO UTC-day validity and required
  log fields (`docs.pota.app/docs/rules.html`), separate-log-per-park and
  file naming (`…/submitting_logs.html`), and the decision-10 open question
  stated as such. The P2P and ADIF pages are already banked.
- New `docs/research/callbook/SOURCES.md`: the QRZ XML spec (v1.34 document;
  live `version="1.36"` — parse as data), its session/error/refusal contract
  and the unenumerated free tier as an open question; the HamQTH developers
  page, its one-hour session and `prg` requirement. Fetched fresh, dated,
  quoted.
- README: a POTA Mode section (what it is, the meter, per-park export, the
  keychain prompt), lookup setup, new keyboard rows, updated test count.
  PROVENANCE.md rows for all three sources. PARTIES.md is for parties and
  gains nothing.

## PoLo survey — adopted and deferred

Adopted in this design: smart park-ref expansion (13), the validity meter
(10), per-park export naming (11), spot-to-pounce with CAT (3), the always-on
their-park field (12), program CQ defaults (14), lookup-as-garnish with a
worked-before line already covered by call-history/own-log surfaces.

Deferred, deliberately, each a clean later addition: the call-field command
grammar (`20m`, `14070`, `+15m` back-entry with auto-advance), auto-respot on
a timer, confirm-from-spots badging (matching hunters' spots of you against
the log after the fact), cross-log worked-before counts from the history
folder, callsign stacking for pileups, SOTA/WWFF programs, non-US park
programs (the directory client is US-only today), and HamDB as a third
lookup source.

## Non-goals

- No change to how any party renders, scores, dupes, or exports — the corpus
  and fixtures are the contract.
- No Plan 3 beyond the two thin slices named: parties stay on
  `ExchangeParser` and their v1 picker entries.
- No POTA account integration: log upload stays manual (the export files are
  made for pota.app's uploader), and the activation-posting API (which does
  require auth) stays out.
- No lookup writes into any received exchange field, anywhere, ever.
- No new window, no new document type, no per-QSO notes field.

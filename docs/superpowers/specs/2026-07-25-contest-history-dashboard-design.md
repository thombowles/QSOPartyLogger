# Contest History, Dashboard, and iCloud Sync — Design

**Date:** 2026-07-25 · **For:** KE5CW · **Status:** approved for implementation
(autonomous session: requirements taken from Tom's request verbatim; decisions
below record the reasoning he would otherwise have been asked about).

## What Tom asked for

1. Track progress for every QSO party logged with the app.
2. Retrieve scores for every contest, by year.
3. An overall dashboard with stats for each party; pick a year, see the summary.
4. Help with the State QSO Party Challenge: progress + upcoming contests.
5. Everything — logs and statistics — synchronized in **one file in iCloud**,
   so any Mac picks up where another left off.
6. World class.

## The shape of the solution

A **contest history archive**: one JSON file, `Contest History.qphistory`,
living in the same user-chosen iCloud Drive folder `CloudMirror` already
syncs (no new entitlements, no provisioning — the security-scoped bookmark
the app already holds). Every document save upserts that contest's full QSO
log plus a computed score snapshot into the archive. A new **Contest
Dashboard** window (⌘⇧D) reads it: per-year summaries, per-contest scores,
all-years party trends, State QSO Party Challenge progress, and the upcoming
contest calendar.

Why one archive file rather than scanning `.qplog` files on demand:

- It is exactly what Tom asked for ("all of the contest logs and statistics
  ... in one file in icloud").
- Scanning requires every historical `.qplog` to be present and downloaded;
  a single file is one iCloud object with one sync state.
- A single file gives merge semantics we control (below), instead of
  filename-collision semantics.
- The `.qplog` documents stay exactly what they are today — working files;
  the archive additionally *imports* them on demand, so history survives
  even if an individual log file is lost.

Alternatives considered:

- **iCloud ubiquity container + NSUbiquitousKeyValueStore / CloudKit** —
  rejected: needs entitlements/provisioning the project deliberately avoids
  (CloudMirror's bookmark approach is documented as the sandbox-safe path),
  KV store is capped at 1 MB, CloudKit is a service dependency that breaks
  the "tests run without network" law.
- **SQLite/GRDB store** — rejected: a second persistence technology for data
  that is small (a season of QSOs is a few MB of JSON), and opaque in iCloud
  conflict resolution. JSON matches every other artifact in this app.
- **Derive everything live from .qplog files each launch** — rejected: see
  above; also makes cross-Mac "one file" impossible.

## Core data model (`Sources/Core/History/`)

### ContestRecord

One archived contest entry. **Identity: `(partyID, year, callsign)`** —
the sponsor's own notion of an entry (one log per callsign per running).
Sponsors' multi-window weekends (NHQP, KSQP…) are naturally one record.

- `partyID: String`, `year: Int` (UTC year of earliest QSO),
  `callsign: String` (uppercased).
- `station: StationProfile`, `myLocation: MyLocation` — for category
  context and Cabrillo-faithful drill-down.
- `qsos: [QSO]` — the full rows. The archive is a true backup of the log.
- `snapshot: ScoreSnapshot` — computed **at save time with the rules
  bundled that season**. Historical scores must not drift when a party's
  JSON is updated for the next year (Article 19 makes schedules annual);
  the snapshot is the honest "what I claimed" record, like the log you
  submitted. Recomputed only when the QSO set actually changes (merge).
- `updatedAt: Date`, `sourceFileName: String?`.
- **Unknown JSON keys are preserved round-trip** (a captured
  `[String: JSONValue]` extras bag on both record and archive envelope):
  an older build must never silently strip fields a newer build wrote into
  the shared iCloud file. This is the additive-schema law (Article 4)
  applied to a file two app versions genuinely share.

### ScoreSnapshot

Pure value derived from `ScoreEngine.score(log:party:)` +
`bandModeCounts`: validQSOs, dupes, invalidMode, outOfScope, qsoPoints,
multiplierCount, multiplierCap, bonusPoints, categoryFactor, finalScore,
per-mode and per-band valid-QSO counts, per-mult-class counts, counties
worked, and `operatingMinutes` (span minus gaps ≥ 30 min — the contest
convention for off-time). A `countsOnly` variant covers logs whose party
definition is not installed (user-party logs on a Mac without the file):
QSO counts survive, score shows as unavailable rather than zero.

Parity is proven by test: snapshot fields equal engine output for the same
log, so the dashboard can never disagree with the score sidebar.

### ContestArchive

`{ schemaVersion: 1, records: [ContestRecord], extras… }` plus pure
functions:

- `upserting(record)` — replace-or-append by identity.
- `merging(other)` — union by identity; within one identity, **QSO union
  by UUID** (a QSO edited on both Macs resolves to the newer record's
  version; a QSO added on either Mac survives). Newer `updatedAt` wins for
  station/location/snapshot/source. This makes concurrent edits from two
  Macs *commutative* — which is what turns iCloud conflict copies from a
  data-loss hazard into a mechanical merge.

### ArchiveStore

File I/O against an **injectable folder URL** (tests use temp dirs):

- `load(folder:)` — coordinated read (`NSFileCoordinator`); missing file →
  empty archive; corrupt file → thrown error, never a silent reset.
- `upsert(record:folder:)` — coordinated read-merge-write, atomic. The
  on-disk archive is re-read inside the write coordination, so a sync
  landing between load and save is merged, not clobbered. Corrupt on-disk
  data aborts the write (the last good copy survives for the user to
  recover; the error surfaces in the dashboard).
- `merge(externalVersionsAt:)` — App layer resolves iCloud conflict
  versions (`NSFileVersion.unresolvedConflictVersionsOfItem`) by decoding
  each and folding through `merging(_:)` — possible *because* merge is
  commutative.

## Challenge + calendar (`Sources/Core/History/`)

`ChallengeCalendar` decodes the generated resource
`Resources/Challenge/sqp_challenge_2026.json` (47 approved contests, 61
windows, 18 mapped to bundled party ids; Maine deliberately unmapped —
see `docs/research/sqp_challenge_rules.md` for the sponsor's words and the
two independent checks). Nothing party-specific is hardcoded in Swift; the
UI stays generic over data (the repo's standing rule).

`ChallengeStanding.compute(records:, calendar:, year:)` implements the
sponsor's formula exactly as quoted in the research doc:

- QSO sum = Σ validQSOs over records of approved parties;
- multiplier = count of approved parties with **≥ 2 valid QSOs**;
- `points = sum × multiplier`;
- award level (Bronze 500 → Diamond 100,000) only once **two** parties
  qualify; progress percentages for the dashboard ring;
- per-party contribution rows, plus an explicit list of logged-but-not-
  approved parties (MEQP) so nothing silently disappears;
- labeled an **estimate** everywhere: the official score is what 3830scores
  computes from actual submissions.

`UpcomingContests.upcoming(now:, parties:, calendar:, records:)` merges the
two schedule sources — bundled parties use their sponsor-verified
`PartyDefinition.schedule`, calendar-only contests use calendar windows and
carry a `dateSource: .challengeCalendar` flag the UI must label (the
calendar has one known-wrong row, NJQP; the sponsor's date wins for every
bundled party by construction). Output: next-window instant, live/soon/
later phase, whether this year's record already exists ("entered ✓").

## SeasonStats (`Sources/Core/History/`)

Pure aggregation for the dashboard: available years; per-year totals
(contests, valid QSOs, combined score, mults, bonus, operating minutes,
mode/band splits); per-contest rows sorted by date; per-party all-years
history (year → snapshot) for trend charts and personal bests.

## App wiring (`Sources/App/ContestHistorian.swift`)

- `historyFolder` = `CloudMirror.activeFolder()` (the synced folder) or
  Application Support fallback when no folder is chosen — the dashboard
  still works, and choosing a folder later migrates by merge (local archive
  folded into the cloud one on first use — merge, never replace).
- `LogDocument.fileWrapper` (the existing save path, next to the mirror
  call) hands the snapshot to a **debounced actor** (2 s) so autosave-per-
  QSO becomes at most one read-merge-write per pause, not one per contact.
  Records are only written for set-up logs with ≥ 1 QSO and a callsign.
- Conflict-version sweep + full reload on demand.
- `importLogs(in folder:)` — decode every `.qplog` in the logs folder and
  upsert (identity + QSO-UUID union make re-imports idempotent). Surfaced
  in the dashboard; also runs automatically once when the archive file
  doesn't exist yet, so the dashboard is born populated from Tom's
  existing season.

## Dashboard UI (`Sources/UI/Dashboard/`)

A `Window("Contest Dashboard", id: "dashboard")` scene — opens via
**⌘⇧D** and the Window menu; independent of any document window.

Layout (single scrolling page, sidebar-free; sections in reading order):

1. **Header bar** — year picker (all archive years + current year), ⌘[ /
   ⌘] step years; Refresh (⌘R), Import Existing Logs…, Reveal History File.
2. **Season summary cards** — contests, valid QSOs, combined claimed
   score, on-air time, counties worked.
3. **State QSO Party Challenge panel** — estimated points with the formula
   shown (`QSOs × parties`), award-level meter (Bronze→Diamond) with the
   next-level delta, qualifying-party count including the ≥2-QSO rule
   applied visibly (a 1-QSO party shows "1 more QSO to qualify"), and the
   not-approved note for MEQP records. Estimate disclaimer, and the season
   window (Feb 1 – Nov 30) named.
4. **Contests table** — date, party, location, QSOs (with dupes/invalid
   split in a tooltip), mults, bonus, category factor, final score, and an
   Open action (opens the `.qplog` via the archived source filename when it
   still exists in the logs folder). Return opens; sortable columns.
5. **Charts** (Swift Charts): QSOs and score per party for the selected
   year; selecting a contest row swaps in that party's all-years trend with
   personal-best callout.
6. **Upcoming contests** — remaining windows this year from `now`,
   soonest first: live-now badge, countdown, "entered ✓", Bundled vs
   "date per SQP Challenge calendar" labeling, weekend grouping.
7. **Empty/degraded states** — no folder chosen (offer chooser), archive
   missing (offer import), decode error (named, with the file path, never
   auto-clobbered), iCloud file not downloaded yet.

Keyboard: ⌘⇧D open; ⌘[ / ⌘] year; ⌘R refresh; table Return opens log; all
controls tabbable. README keyboard table gains these rows (Article 6).

No radio- or party-specific branching: everything the dashboard shows is a
function of archive + catalog + challenge resource.

## Concurrency

Core types are `Sendable` values; `ArchiveStore` functions are synchronous
and thread-agnostic (coordination handles cross-process); the historian is
an actor owning debounce state; the dashboard reads on the main actor via
async load. Swift 6 strict concurrency, no `@unchecked` outside the
existing documented `LogDocument` pattern.

## Testing (all offline, temp-dir only)

- Round-trip + unknown-key preservation (record and envelope).
- Identity/merge: same-identity QSO union, edited-QSO conflict by
  `updatedAt`, cross-identity union, idempotent re-import, commutativity
  (`a.merging(b) == b.merging(a)` up to ordering).
- Store: missing file, corrupt file (load throws; upsert refuses to
  clobber), concurrent-ish sequential upserts from two "Macs" over one
  folder, atomicity.
- Snapshot parity with `ScoreEngine` on a real bundled party, counts-only
  fallback, operating-minutes gap rule.
- Challenge: formula on the sponsor's own semantics (≥2-QSO multiplier
  floor, 1-QSO party contributes QSOs but not multiplier), award levels +
  qualification gate, MEQP exclusion listed not dropped, resource loads
  with 47/61/18 asserted.
- Upcoming: fixed `now` fixtures — live window, next window, entered
  detection, bundled-schedule-wins-over-calendar (NJQP), calendar-only
  labeling.
- SeasonStats: years, totals, per-party trend, empty year.

## Commit plan

1. research + generated challenge resource (data only, no behavior).
2. spec + plan docs.
3. Core history models + store + tests (+ CLAUDE.md layout row).
4. Core stats + challenge + upcoming + tests.
5. App historian + LogDocument hook + import + tests.
6. Dashboard UI + project.yml resource + README (features, keyboard,
   test count, provenance) — docs in the same commit as the behavior.

Full suite green before and after each commit; commands + output recorded
in the session log (Article 8).

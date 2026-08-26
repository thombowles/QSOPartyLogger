# Dashboard: POTA split + per-widget visibility — design (2026-08-26)

Tom's request, in his words: in the State QSO Party Challenge don't include
activities that do not apply ("today they're greyed out, just don't show
them"); don't show POTA in the contests history list — a separate POTA history
list; include a POTA widget and individual POTA metrics at the top; make all
the widgets on the screen show/hide "so I can select how I want my dashboard
to appear". Session is autonomous; decisions below are made, not pending, per
Tom's standing "ship a build to try" feedback. Every one is his to overturn.

## Decisions

**D1 — Challenge card hides what the Challenge won't count.** The greyed
lines are `ChallengeStanding.notApproved` (MEQP in 2026, and now every POTA
outing). The view stops rendering them; Core still computes them (no scoring
change, tests untouched). The card's "shown, never silently dropped" display
rule is retired by Tom's instruction — the data still exists one widget down,
in the POTA section or the contests table.

**D2 — Program records are partitioned, not interleaved.** A record is POTA
when its contest's `family == .program` (`ContestCatalog`; pota.json is
bundled). `DashboardModel` splits the archive: season cards, contests table,
trend chart and Challenge feed see contest records only; the POTA cards and
POTA section see program records only. So "Contests: 12" means contests, and
POTA QSOs no longer inflate the season's QSO/time/score cards.

**D3 — One POTA outing, one record.** `ContestRecord.Identity` today is
partyID|year|callsign — correct for a party ("one log per entry"), wrong for
an always-on program: every activation of a year folded to the later-modified
file behind a bogus "two files for one contest" warning. `Identity` gains
`outing: String?` — nil for parties (identity and `id` byte-identical for
every existing record); for program logs, the UTC day of the earliest QSO
plus the sorted set of activated parks (union of each QSO's `myPotaRefs`;
empty for a hunter log). An iCloud "2" copy of the same outing still folds;
two outings never do. `record.id` appends the outing so table selection stays
unique.

**D4 — `PotaSeason` (Core/Pota), pure and tested.** Per-outing rows: sorted
parks, park-days (per park × UTC day: unique call-band-mode count, valid at
`PotaStats.validationTarget` = 10 — the same strict reading, open question
banked in docs/research/pota/SOURCES.md), valid QSOs, P2P contacts (distinct
`groupID`s carrying a their-park), distinct states (typed `theirState` ??
callbook state), DX entities (CTY entity ≠ each record's own callsign's),
operating minutes. Season aggregates: activations valid/total, unique parks
activated, POTA QSOs, P2P contacts + distinct parks hunted, states, DX.

**D5 — POTA metrics at the top.** A second `StatCard` row under the season
cards: Activations (valid · short detail), Parks activated, POTA QSOs (mode
split detail), Park-to-Park (distinct parks detail), States · DX.

**D6 — POTA section = the separate history list.** One row per outing: Date,
Park(s) ("hunting" when none), QSOs, Activation (✓ / n∕10 / "k of n valid",
park-day detail in the tooltip), P2P, States, DX, Time. Return / double-click
/ context menu opens the log — the POTA submission files stay where they are
made, ⌥⌘E in the open log (one file per park); a single-file ADIF here would
masquerade as a submission. No charts in v1.

**D7 — Six widgets, each show/hide.** season cards, POTA cards, Challenge,
contests, POTA, upcoming. A toolbar **Widgets** menu of check Toggles,
⌘1–⌘6 (keyboard-first; digits were unclaimed), persisted as
`dashboardHiddenWidgets` (comma-joined raw values, unknown names ignored so
a future widget list reads old prefs). Default all visible. Challenge still
also needs a standing (as today). All six hidden → a one-line hint naming
the menu and keys.

**D8 — Docs in the same change.** README: dashboard feature bullets, the
dashboard keyboard line, test count. This spec rides the branch.

## Non-goals

POTA per-park export from the dashboard; charts in the POTA section; any
change to scoring, exporters, or the golden corpus; delete UI (standing
decision); Challenge Core semantics.

## Tests

- LogFolder: two same-year POTA logs (different day or parks) → two records,
  no duplicate; same-outing copy → folds with the duplicate named; party
  identity unchanged (existing tests stay green untouched).
- ContestRecord: outing string for program logs (day, parks, hunter-empty);
  nil for parties; `id` uniqueness.
- PotaSeason: park-day grouping and the ten-unique rule, P2P group counting,
  typed-beats-callbook state, DX excludes own entity, hunter outing, year
  filter, season unions vs sums, ordering.
- DashboardModel: partition by family (stats exclude POTA; potaSeason
  excludes parties).
- Widget visibility: raw-string round-trip, unknown-name tolerance, toggle,
  default-visible.
- Activation cell label composition (UI static, DashboardExportRowTests
  precedent).

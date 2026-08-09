# The Advisor — in-contest strategy from the data already on hand

**Date:** 2026-08-09
**Status:** ready for execution — open calls default per §10 unless vetoed.
Amended same day after operator review: a goal switch (score vs Challenge
QSOs), move calls that recommend posture as well as band, tune chips that
carry the full band-map click, and live space weather feeding the solar
strand.
**Scope decided with the operator:** live advisor only, in the score sidebar.
Advisory classes: run health, move calls (band + Run/S&P), needed mults
spotted, bonus & schedule. **Prior-year archive comparisons were considered
and deliberately deferred** — the engine's input shape leaves the seam (§5.4),
but nothing in v1 reads `ContestArchive`.

## 1. Problem

The app now *measures* nearly everything a contest decision needs — four rate
windows (`RateMeter`), the exact worked-multiplier set
(`ScoreEngine.ScoreBreakdown.multiplierKeys`), live spots with counties
attached (`SpotStore`, hub spots), every bonus rule and operating window
(`PartyDefinition.bonuses` / `.schedule`) — and *interprets* none of it. The
operator is left to notice that the run died, that an unworked county has been
sitting spotted on 40 m for ten minutes, that the bonus station is workable on
a second mode, that sunset is closing 20 m under them.

And any interpretation has to know what it is optimizing. The same census
reads differently on a Challenge weekend — where
`ChallengeStanding.points = qsoSum × multiplier` and a new in-contest
multiplier is worth exactly nothing — than in a serious single-party entry
where mults multiply everything. N1MM does neither; it is the feature where a
logger that owns all its own data can lead rather than follow.

## 2. Voice — the rules every advisory obeys

1. **Facts, not orders.** The headline is a true sentence about the operator's
   own data ("18/hr last 10, down from 46 the past hour"). Any suggestion
   lives in the tooltip detail, phrased as what usually pays, never as an
   instruction.
2. **Quiet.** The section renders nothing when no advisory is live. No sound,
   no animation, no modal anything — the inline-status rule the rest of the
   app already follows.
3. **Read-only.** The advisor never logs, never keys, never moves the radio.
   A tune chip invokes the same path a band-map click does; nothing happens
   without the operator's own gesture.
4. **Evidence or silence.** Same law as `RateColumn`: a figure derived from
   too little data does not appear. Every advisory names its evidence in the
   tooltip.
5. **Category-honest by construction.** A `NON-ASSISTED` entry receives no
   spots at all (`SpottingPolicy` — they never reach the store), so every
   spot-derived advisory is silent for it with no advisor-side rule needed.
   One test pins this anyway (§9). The own-log and solar strands, which use
   no spotting information, keep working for every category.

## 3. The goal switch — score, or Challenge QSOs

A two-position control: **Score** (default) and **QSOs**.

- **Score** values a contact by what it does to *this party's* claimed score:
  points, and a heavy premium on anything that adds a `MultKey`.
- **QSOs** values every valid contact equally, because that is what the State
  QSO Party Challenge pays — the sponsor's formula
  (`ChallengeStanding.swift`, `docs/research/sqp_challenge_rules.md`) is
  Σ valid QSOs × qualifying parties, and a needed county is worth precisely
  one QSO there. In this position the mult premium in §4.2's weighting drops
  to zero; `neededMultsSpotted` still shows (the party's own award has not
  gone anywhere), it just stops outbidding raw activity.

The switch is a segmented control in the advisor section header, bound to
`⌥⌘A`, persisted globally in `AppSettings.advisorGoal` — sticky across
contests, because a Challenge season is a season, not a log (§10 call 5).
The active goal is always visible in the header, so advice is never read
against the wrong yardstick.

## 4. The four advisory classes

Priority order when several are live: `runFading`, `moveCall`,
`neededMultsSpotted`, `bonusStanding`, `scheduleEdge` (the last two are the
§4.4 pair).

### 4.1 `runFading` — the run is dying under you

- **Fires when** all of: operating mode is `.run`; `Reading.lastTen` is
  non-nil; `Reading.lastHour ≥ RATE_FLOOR` (default 20 — a trailing hour under
  20/hr was not much of a run, and halving it is noise); `lastTen ≤
  FADE_RATIO × lastHour` (default 0.5); and the condition has held for every
  evaluation across `SUSTAIN_MINUTES` (default 3) — one bad instantaneous
  reading must not fire it.
- **Clears when** `lastTen ≥ CLEAR_RATIO × lastHour` (default 0.75 — a
  hysteresis band, so it cannot flap), or the mode leaves Run, or the band
  changes, or the operator dismisses it.
- **Headline:** `Run fading: 18/hr last 10, down from 46 the past hour.`
- **Detail:** the two windows and thresholds spelled out, then: "Two moves
  that usually pay: an S&P sweep (⌘R), or a band change — ⌘J returns here."

### 4.2 `moveCall` — where the next hour is, and in which posture

The operator's request in full: *when/if to move to S&P or Run, on this band
or another — whatever yields the most QSOs or points per the goal switch.*
The advisory evaluates every candidate `(posture, band)` over
`party.validBands` and recommends a move only when the best candidate beats
the current one convincingly.

**Evidence per candidate, goal-weighted:**

- **S&P on band B:** workable-station census — the `SpotFilter`-filtered,
  unworked spots on B (the same list the band map shows, so the two can never
  disagree); needed-mult spots among them (§4.3's helper), weighted by
  `W_MULT` under the Score goal and by zero under QSOs; the operator's own
  recent S&P rate on B, from posture-stamped rows (§5.4).
- **Run on band B:** the operator's own run rate on B this contest
  (posture-stamped rows, trailing window); activity on B as an audience proxy
  (spot count); an in-state side factor — an in-state station *is* the
  multiplier every hunter needs, and running pays accordingly; the solar/
  space-weather band weight (§5.1–5.2).

**Fires when** the best candidate's evidence exceeds the current
`(posture, band)`'s by `BAND_MARGIN` (default 2.0×), sustained for
`SUSTAIN_MINUTES` — and never while the current Run is healthy: a working run
is not interrupted by arithmetic, so while mode is Run the advisory is
suppressed unless `runFading` is live. In S&P it may fire any time.
**Non-assisted entries** get the spot-free strands only: own-log posture/band
rates and solar transitions — `Sunset was 0112Z. 40 m and 80 m usually take
over from here. Your 40 m run earlier: 31/hr.` — fired once per transition.

- **Headline (Score):** `S&P 40 m: 9 workable spots, 4 needed mults — this
  20 m run: 12/hr last 10.`
- **Headline (QSOs):** `40 m: 14 workable spots. Your S&P here has given
  6/hr for 20 min.`
- **Detail:** the full candidate table, the solar/space-weather note with its
  observation time, and "⌘J returns to this run frequency."
- **Clears** on posture or band change, margin collapse, or dismissal. Never
  auto-QSYs.

### 4.3 `neededMultsSpotted` — unworked multipliers on the air right now

A pure helper answers, for one spot: *would a valid QSO with this county, on
this band, in this mode class, add a `MultKey` not already in
`ScoreBreakdown.multiplierKeys`?* It must reuse `ScoreEngine`'s own scope
computation (promote the private `scopeComponent` to internal) rather than
re-deriving it — per-band, per-mode, and once-only mult scopes all exist in
the catalog, and two implementations of that rule is a scoring bug factory.

v1 detects **county-class mults from hub spots' `county` field** — the one
location a spot actually carries. Cluster spots carry no location, so
state/province/DX-class needs stay undetected in v1; stated, not papered over
(§8).

- **Fires when** ≥1 filtered, unworked-on-that-band spot maps to a needed
  mult. Lists up to three as tune chips — `GRY 7040` — plus `+N more`.
- **Tune chip — the whole point is one gesture to the multiplier.** Each chip
  carries its `Spot`, and clicking it fires the exact `tune(to:)` path a
  band-map click fires: the radio moves (mode following the band plan per the
  existing setting), the call lands in the entry bar, and the county prefills
  the exchange when `prefillExchangeFromSpots` is on — one Return from
  working him. One tune rule, held in one place. The keyboard path is the QSY
  grammar the call field already has (`7040` ↵) plus ⌘↓/⌘↑ once on the band,
  the same parity the band map itself relies on.
- **Clears** as spots age out of the store or the mult gets worked; no
  per-chip dismissal — the list prunes itself.

### 4.4 `bonusStanding` and `scheduleEdge` — the party's own clock and prizes

- **Bonus:** for each `BonusRule.workStation` rule (the only call-specific
  kind): unworked → `Bonus KS0KS not yet worked (+500).` For `perMode` /
  `perBandMode` scopes, name what remains: `W7DX worked on CW — SSB bonus
  open.` If the station is in the spot store right now, append the frequency
  as a tune chip. The sidebar's existing `bonusSection` keeps the totals; the
  advisor carries only the actionable edge, and only while the bonus is still
  earnable.
- **Schedule:** from `party.schedule` windows: inside a window's final
  `WINDOW_WARN_HOURS` (default 2), `90 min left in this window.`; between
  windows, `Next window opens 1300Z (in 10 h 20 m).`; after the last window
  the advisor as a whole goes silent.

## 5. Architecture

Four new pure units plus one quiet client, in the established `ESM` /
`RateMeter` / `DXCCLabelClient` styles — engines take explicit `now`, own no
clock, touch no store; the client is protocol-seamed so tests script the
server (constitution Article 5).

### 5.1 `Sources/Core/Models/SolarGeometry.swift`

`static func elevation(latitude:longitude:date:) -> Double` plus
`sunriseSunset(latitude:longitude:date:)`, from the NOAA solar position
equations (NOAA Global Monitoring Laboratory solar calculator — bank the
reference with fetch date in `docs/research/` before coding, house rule).
Pinned-value tests at known dates/places. Lives beside `Maidenhead`, which
supplies its inputs. Drives a fixed band-daypart weight table — high bands
with the sun up, low bands after dark, 40 m transitional, gray-line
enhancement within ±45 minutes of sunrise/sunset — whose reference is banked
per §10 call 3.

### 5.2 `Sources/Core/Models/SpaceWeather.swift` + `Sources/App/SpaceWeatherClient.swift`

The operator's call: when the internet is there, current space weather joins
the solar strand.

- **The pure part:** `struct SpaceWeather { var sfi: Int?; var kp: Double?;
  var observedAt: Date }`, a parser for the NOAA SWPC JSON products, and a
  coarse modifier table over the §5.1 daypart weights — three buckets each
  for SFI and Kp, mapped per **NOAA's own space weather scales** (the G and R
  scales describe HF impact in NOAA's own words), banked with fetch date
  before the table is written. Elevated Kp dampens the high bands; elevated
  SFI lifts 15/10. Coarse on purpose: tendency, not measurement, same law as
  the daypart table.
- **The client:** `SpaceWeatherClient` on the `DXCCLabelClient` mold — a
  `SpaceWeatherFetching` protocol seam, GET the SWPC product(s), throttled to
  `SW_REFRESH` (default hourly), last good reading cached to disk with its
  timestamp, every failure quiet (`lastError`, console) and never reaching
  the entry path. Candidate endpoints to verify and bank
  (`docs/research/space_weather_sources.md`, with sample payloads as test
  fixtures): `services.swpc.noaa.gov/json/f107_cm_flux.json` (SFI) and
  `services.swpc.noaa.gov/products/noaa-planetary-k-index.json` (Kp).
- **Absence is fine by design:** no network, a failed fetch, or a reading
  older than `SW_STALE_HOURS` (default 6) → the modifier is identity and the
  advisor runs on geometry alone, exactly as before. The detail line always
  names the observation time (`Kp 4 as of 1800Z`) so stale never
  masquerades as current.

### 5.3 `Sources/Core/Engine/NeededMult.swift`

The §4.3 question as a static func over `(county, band, modeClass,
ScoreBreakdown, PartyDefinition, MyLocation)`. Reuses `ScoreEngine`'s scope
rules; its tests cover a per-band-scope party, a once-scope party, and both
in-state and out-of-state sides.

### 5.4 `Sources/Core/Engine/Advisor.swift`

```swift
enum Advisor {
    enum Goal: String, Codable { case score, qsos }
    struct Input {          // built by a factory, MainView stays one line
        var goal: Goal
        var reading: RateMeter.Reading
        var mode: OperatingMode
        var currentBand: Band?
        var recent: [PostureSample]      // (band, posture, timestamp) per valid QSO, trailing hour
        var score: ScoreEngine.ScoreBreakdown
        var party: PartyDefinition
        var myLocation: MyLocation
        var gridLocator: String?         // nil → solar strand silent
        var spaceWeather: SpaceWeather?  // nil/stale → identity modifier
        var spots: [Spot]                // post-SpotFilter; empty ⇒ non-assisted or none
        var mutedKinds: Set<Advisory.Kind>
    }
    struct State: Equatable { … }        // sustain timers, fired transitions, dismissals
    struct Advisory: Identifiable, Equatable {
        enum Kind: String { case runFading, moveCall, neededMultsSpotted, bonusStanding, scheduleEdge }
        var id: String                   // stable per condition, for dismissal
        var kind: Kind
        var headline: String
        var detail: String               // tooltip depth
        var chips: [TuneChip]            // label + the Spot itself; empty for most
    }
    struct TuneChip: Equatable { var label: String; var spot: Spot }
    static func evaluate(_ input: Input, state: State, now: Date) -> (advisories: [Advisory], state: State)
}
```

The engine owns the copy, like `RateColumn` — wording is testable, and the
view stays a layout. `State` threads through the caller; sustain windows and
once-per-transition flags are dates inside it compared against the `now`
argument, never a wall clock. Dismissals are per-sitting (the ⌘. spots-badge
convention) and live in `State`, which dies with the window.

**One additive log field.** §4.2's own-rate strands need to know which past
QSOs were made running, so `QSO` gains `posture: OperatingMode?` — stamped at
logging from the same flag that already picks the message set and the ⇧⌘S
meaning, `nil` on every existing row, decoded tolerantly like `nameRcvd` and
the POTA fields. Scoring, Cabrillo, and ADIF never read it. Rows without it
simply contribute nothing to the posture strands — evidence or silence.

The deferred archive strand bolts on here later as one more optional `Input`
field, touching no existing advisory — that is the whole reason `Input` is a
struct and not a parameter list.

## 6. Wiring

`MainView` already computes the breakdown (`ScoreEngine.score`, line ~104),
the filtered spot list, and the single `tune(to: Spot)` path. It builds
`Advisor.Input` via a factory (`Advisor.Input.make(…)` — one expression,
respecting the pane's type-checker budget) and passes it into `ScoreSidebar`,
which gains one seam line: `AdvisorSection(input:onTune:)` directly above
`totalsCard`, with `onTune` wired to the same `tune(to:)` the band map uses.
The section owns its own `@State` for `Advisor.State` and its own
`TimelineView(.periodic(by: 30))` tick — 30 s is finer than any sustain
window; nothing outside the section redraws on it.

`SpaceWeatherClient` is instantiated beside `DXCCLabelClient` in the app and
its latest reading rides into the factory.

Settings, in the `AppSettings` computed-var-over-`Preferences.store` pattern:
`advisorEnabled` (default **on**), `advisorCollapsed`, `advisorMutedKinds`,
`advisorGoal` (default `.score`). Mute/disable per kind via the section
header's context menu.

## 7. Keyboard

| Keys | Action |
| --- | --- |
| `⇧⌘A` | Collapse / expand the Advisor section |
| `⌥⌘A` | Toggle the advisor goal: Score ↔ QSOs |

Both chords are free (`⇧⌘` currently binds S R M D C E; `⌥⌘` binds nothing).
Acting on an advisory is already keyboard-complete: `⌘R` toggles Run/S&P, the
QSY grammar tunes anywhere a chip points, `⌘J` returns to the run. Rule 9
satisfied the same way the band map satisfies it.

## 8. Stated limits (v1)

- Needed-mult detection sees **county-class mults via hub spots only** —
  cluster spots carry no location. State/DX-class detection would need call
  history inference; deferred, and the section never claims completeness.
- Solar and space-weather weighting is **tendency, not measurement** — the
  copy always says "usually", observed spot evidence outranks it wherever
  both exist, and a missing or stale reading silently reduces to geometry
  alone.
- Posture evidence accrues only from rows logged by builds that stamp
  `QSO.posture` — the first stamped weekend is the first with run-rate
  strands.
- No archive comparisons, no debrief view, no auto-anything.

## 9. Testing

`Tests/Core/SolarGeometryTests.swift` — NOAA worked examples pinned to ±0.5°;
equinox and solstice cases; polar-adjacent grid does not trap.

`Tests/Core/SpaceWeatherTests.swift` — parser against banked SWPC fixture
payloads; malformed and empty bodies; the three-bucket modifier table pinned;
stale (> `SW_STALE_HOURS`) and absent readings reduce to identity. Client
tests script `SpaceWeatherFetching` like the DXCC tests script theirs — no
network anywhere.

`Tests/Core/NeededMultTests.swift` — per-band-scope vs once-scope parties,
both sides, worked and unworked, invalid band/mode for the party.

`Tests/Core/AdvisorTests.swift` — fixed `Date(timeIntervalSince1970:)`
throughout:

1. `runFading` worked example — fires at 0.5×, not at the floor, only after
   the sustain window; clears at 0.75× (hysteresis), on mode change, on band
   change, on dismissal.
2. `moveCall` — census-margin worked example; **the same census under Score
   and QSOs goals yields different recommendations** (the mult-heavy band
   wins Score, the activity-heavy band wins QSOs); suppressed during a
   healthy Run, permitted once `runFading` is live; fires freely in S&P;
   posture strands read stamped rows and ignore unstamped; solar transition
   fires exactly once; nil grid keeps the solar strand silent; space-weather
   modifier shifts a marginal case and its absence restores it; clears on
   QSY.
3. `neededMultsSpotted` — hub spot with unworked county fires; worked county
   silent; **empty spot store silent** (the NON-ASSISTED pin); chips capped
   at three with a correct `+N more`; each chip carries the exact `Spot` it
   describes.
4. `bonusStanding` — `once` scope disappears when worked; `perMode` names the
   open mode; spot enrichment appends a tune chip.
5. `scheduleEdge` — final-two-hours countdown; between-windows next-open;
   after the last window every kind is silent.
6. Priority order; muted kinds excluded; dismissal survives re-evaluation.

`Tests/Core/QSOPostureTests.swift` (or folded into the existing QSO coding
tests) — a pre-posture log decodes with `nil`, a stamped row round-trips, and
neither Cabrillo nor ADIF output changes by its presence.

Copy/wording asserted in the engine tests, since the engine owns it. Suite
count and README updated in the same commit as the behavior, as always.

## 10. Open calls — defaults stand unless vetoed before execution

1. **Thresholds** — `RATE_FLOOR 20/hr`, `FADE_RATIO 0.5`, `CLEAR_RATIO 0.75`,
   `SUSTAIN_MINUTES 3`, `WINDOW_WARN_HOURS 2`, `BAND_MARGIN 2.0×`,
   `SW_REFRESH 1 h`, `SW_STALE_HOURS 6`, the goal weight `W_MULT`, tick 30 s.
   Named constants in `Advisor` (and the client), one place to retune after a
   real contest weekend.
2. **`⇧⌘A`** collapse and **`⌥⌘A`** goal toggle.
3. **The band-daypart reference** to bank (ARRL operating guidance is the
   expected source) — research doc lands before the weight table is written,
   per house rule; the table cites it.
4. **SWPC endpoints** — the two candidates in §5.2, verified and banked with
   sample payloads before the parser is written. NOAA's G/R scales are the
   mapping authority for the modifier table.
5. **`advisorGoal` is global, not per-log** — a Challenge season is a season.
   Per-log would mean a `ContestLog` field; revisit only if the global
   setting proves wrong in practice.

## 11. Execution notes for the implementing session

- Work in a worktree; run `xcodegen generate` after each file-set lands.
- Commit sequence, each with the full suite green and the command + output
  recorded: **(1)** `SolarGeometry` + tests · **(2)** `SpaceWeather` parser,
  modifier table, and client + tests (research banked first) · **(3)**
  `NeededMult` + tests · **(4)** the additive `QSO.posture` stamp + coding
  tests · **(5)** `Advisor` engine + tests · **(6)** `AdvisorSection`,
  settings, seams, README (features + keyboard rows + test count) — docs ship
  with the behavior.
- No party JSON changes, no UI branching on any party id — every advisory
  reads the definition through existing types. The one schema change is the
  additive, optional `QSO.posture` field in commit 4.

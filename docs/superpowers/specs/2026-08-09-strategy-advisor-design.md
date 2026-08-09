# The Advisor — in-contest strategy from the data already on hand

**Date:** 2026-08-09
**Status:** ready for execution — open calls default per §9 unless vetoed
**Scope decided with the operator:** live advisor only, in the score sidebar.
Advisory classes: run health, needed mults spotted, bonus & schedule, band
change from spots + propagation. **Prior-year archive comparisons were
considered and deliberately deferred** — the engine's input shape leaves the
seam (§4), but nothing in v1 reads `ContestArchive`.

## 1. Problem

The app now *measures* nearly everything a contest decision needs — four rate
windows (`RateMeter`), the exact worked-multiplier set
(`ScoreEngine.ScoreBreakdown.multiplierKeys`), live spots with counties
attached (`SpotStore`, hub spots), every bonus rule and operating window
(`PartyDefinition.bonuses` / `.schedule`) — and *interprets* none of it. The
operator is left to notice that the run died, that an unworked county has been
sitting spotted on 40 m for ten minutes, that the bonus station is workable on
a second mode, that sunset is closing 20 m under them. N1MM does not do this
either; it is the feature where a logger that owns all its own data can lead
rather than follow.

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
   One test pins this anyway (§8).

## 3. The four advisory classes

Priority order when several are live: `runFading`, `bandCall`,
`neededMultsSpotted`, `bonusStanding`, `scheduleEdge` (the last two are the
§3.4 pair).

### 3.1 `runFading` — the run is dying under you

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

### 3.2 `bandCall` — when to change bands, from spots and propagation

The operator's addition to the catalog, and the one class that needs data the
app does not yet compute. Three evidence strands, combined:

- **Spot census** (assisted entries only, since only they have spots): per
  party-valid band — live spot count, and *needed-mult* spot count (§3.3's
  helper). Computed from the same `SpotFilter`-filtered list the band map
  shows, so the two can never disagree about what exists.
- **Own-log recency:** QSOs per band over the trailing 60 minutes — direct
  knowledge of what the current band is yielding.
- **Solar geometry** (works for every entry, offline): sun elevation at the
  station's grid (`Maidenhead.center(of:)` → a new pure `SolarGeometry`,
  §4.1) drives the classic band dayparts — high bands with the sun up, low
  bands after dark, 40 m transitional, gray-line enhancement within
  ±45 minutes of sunrise/sunset. Heuristic weights in a fixed table, sourced
  and banked before coding (§9 open call 3).

**Fires (assisted)** when another `party.validBands` band's evidence —
needed-mult spots weighted over plain spots, daypart-weighted — exceeds the
current band's by a margin sustained for `SUSTAIN_MINUTES`, **and** the run is
not healthy (suppressed while mode is Run unless `runFading` is live; in S&P
it may fire any time). **Fires (non-assisted)** only at daypart transitions,
once per transition per band pair: no spot numbers exist to cite, so the
advisory is the solar fact alone.

- **Headline (assisted):** `40 m: 11 spots, 5 needed mults — 20 m has 2, none
  needed.`
- **Headline (non-assisted):** `Sunset was 0112Z. 40 m and 80 m usually take
  over from here.`
- **Detail:** the full census table, the solar note, and "⌘J returns to this
  run frequency."
- **Clears** on band change, margin collapse, or dismissal. Never auto-QSYs.

### 3.3 `neededMultsSpotted` — unworked multipliers on the air right now

A pure helper answers, for one spot: *would a valid QSO with this county, on
this band, in this mode class, add a `MultKey` not already in
`ScoreBreakdown.multiplierKeys`?* It must reuse `ScoreEngine`'s own scope
computation (promote the private `scopeComponent` to internal) rather than
re-deriving it — per-band, per-mode, and once-only mult scopes all exist in
the catalog, and two implementations of that rule is a scoring bug factory.

v1 detects **county-class mults from hub spots' `county` field** — the one
location a spot actually carries. Cluster spots carry no location, so
state/province/DX-class needs stay undetected in v1; stated, not papered over
(§7).

- **Fires when** ≥1 filtered, unworked-on-that-band spot maps to a needed
  mult. Lists up to three as tune chips — `GRY 7040` — plus `+N more`.
- **Tune chip:** click QSYs there, exactly the band-map click path. The
  keyboard path is the QSY grammar the call field already has (`7040` ↵), the
  same parity the band map itself relies on.
- **Clears** as spots age out of the store or the mult gets worked; no
  per-chip dismissal — the list prunes itself.

### 3.4 `bonusStanding` and `scheduleEdge` — the party's own clock and prizes

- **Bonus:** for each `BonusRule.workStation` rule (the only call-specific
  kind): unworked → `Bonus KS0KS not yet worked (+500).` For `perMode` /
  `perBandMode` scopes, name what remains: `W7DX worked on CW — SSB bonus
  open.` If the station is in the spot store right now, append the frequency.
  The sidebar's existing `bonusSection` keeps the totals; the advisor carries
  only the actionable edge, and only while the bonus is still earnable.
- **Schedule:** from `party.schedule` windows: inside a window's final
  `WINDOW_WARN_HOURS` (default 2), `90 min left in this window.`; between
  windows, `Next window opens 1300Z (in 10 h 20 m).`; after the last window
  the advisor as a whole goes silent.

## 4. Architecture

Three new pure units, in the established `ESM` / `RateMeter` style — no clock
of their own, no store access, every figure a function of explicit arguments:

### 4.1 `Sources/Core/Models/SolarGeometry.swift`

`static func elevation(latitude:longitude:date:) -> Double` plus
`sunriseSunset(latitude:longitude:date:)`, from the NOAA solar position
equations (NOAA Global Monitoring Laboratory solar calculator — bank the
reference with fetch date in `docs/research/` before coding, house rule).
Pinned-value tests at known dates/places. Lives beside `Maidenhead`, which
supplies its inputs.

### 4.2 `Sources/Core/Engine/NeededMult.swift`

The §3.3 question as a static func over `(county, band, modeClass,
ScoreBreakdown, PartyDefinition, MyLocation)`. Reuses `ScoreEngine`'s scope
rules; its tests cover a per-band-scope party, a once-scope party, and both
in-state and out-of-state sides.

### 4.3 `Sources/Core/Engine/Advisor.swift`

```swift
enum Advisor {
    struct Input {         // built by a factory, MainView stays one line
        var reading: RateMeter.Reading
        var mode: OperatingMode
        var currentBand: Band?
        var bandRecency: [Band: Int]     // QSOs per band, trailing 60 min
        var score: ScoreEngine.ScoreBreakdown
        var party: PartyDefinition
        var myLocation: MyLocation
        var gridLocator: String?         // nil → solar strand silent
        var spots: [Spot]                // post-SpotFilter; empty ⇒ non-assisted or none
        var mutedKinds: Set<Advisory.Kind>
    }
    struct State: Equatable { … }        // sustain timers, fired transitions, dismissals
    struct Advisory: Identifiable, Equatable {
        enum Kind: String { case runFading, bandCall, neededMultsSpotted, bonusStanding, scheduleEdge }
        var id: String                   // stable per condition, for dismissal
        var kind: Kind
        var headline: String
        var detail: String               // tooltip depth
        var chips: [TuneChip]            // label + freqKHz; empty for most
    }
    static func evaluate(_ input: Input, state: State, now: Date) -> (advisories: [Advisory], state: State)
}
```

The engine owns the copy, like `RateColumn` — wording is testable, and the
view stays a layout. `State` threads through the caller; sustain windows and
once-per-transition flags are dates inside it compared against the `now`
argument, never a wall clock. Dismissals are per-sitting (the ⌘. spots-badge
convention) and live in `State`, which dies with the window.

The deferred archive strand bolts on here later as one more optional `Input`
field, touching no existing advisory — that is the whole reason `Input` is a
struct and not a parameter list.

## 5. Wiring

`MainView` already computes the breakdown (`ScoreEngine.score`, line ~104) and
the filtered spot list. It builds `Advisor.Input` via a factory
(`Advisor.Input.make(…)` — one expression, respecting the pane's type-checker
budget) and passes it into `ScoreSidebar`, which gains one seam line:
`AdvisorSection(input:onTune:)` directly above `totalsCard`. The section owns
its own `@State` for `Advisor.State` and its own
`TimelineView(.periodic(by: 30))` tick — 30 s is finer than any sustain
window; nothing outside the section redraws on it.

Settings, in the `AppSettings` computed-var-over-`Preferences.store` pattern:
`advisorEnabled` (default **on**), `advisorCollapsed`, `advisorMutedKinds`.
Mute/disable per kind via the section header's context menu.

## 6. Keyboard

| Keys | Action |
| --- | --- |
| `⇧⌘A` | Collapse / expand the Advisor section |

`⇧⌘A` is free (`⇧⌘` currently binds S R M D C E) and sits beside `⇧⌘M`, its
sibling gesture. Acting on an advisory is already keyboard-complete: `⌘R`
toggles Run/S&P, the QSY grammar tunes anywhere a chip points, `⌘J` returns to
the run. Rule 9 satisfied the same way the band map satisfies it.

## 7. Stated limits (v1)

- Needed-mult detection sees **county-class mults via hub spots only** —
  cluster spots carry no location. State/DX-class detection would need call
  history inference; deferred, and the section never claims completeness.
- Solar weighting is **tendency, not measurement** — the copy always says
  "usually", and observed spot evidence outranks it wherever both exist.
- No external space-weather feed (§9 call 4), no archive comparisons, no
  debrief view, no auto-anything.

## 8. Testing

`Tests/Core/SolarGeometryTests.swift` — NOAA worked examples pinned to ±0.5°;
equinox and solstice cases; polar-adjacent grid does not trap.

`Tests/Core/NeededMultTests.swift` — per-band-scope vs once-scope parties,
both sides, worked and unworked, invalid band/mode for the party.

`Tests/Core/AdvisorTests.swift` — fixed `Date(timeIntervalSince1970:)`
throughout:

1. `runFading` worked example — fires at 0.5×, not at the floor, only after
   the sustain window; clears at 0.75× (hysteresis), on mode change, on band
   change, on dismissal.
2. `neededMultsSpotted` — hub spot with unworked county fires; worked county
   silent; **empty spot store silent** (the NON-ASSISTED pin); chips capped
   at three with a correct `+N more`.
3. `bonusStanding` — `once` scope disappears when worked; `perMode` names the
   open mode; spot enrichment appends the frequency.
4. `scheduleEdge` — final-two-hours countdown; between-windows next-open;
   after the last window every kind is silent.
5. `bandCall` — census-margin worked example; suppressed during a healthy
   Run; fires in S&P; solar transition fires exactly once; nil grid keeps the
   solar strand silent; clears on QSY.
6. Priority order; muted kinds excluded; dismissal survives re-evaluation.

Copy/wording asserted in the engine tests, since the engine owns it. Suite
count and README updated in the same commit as the behavior, as always.

## 9. Open calls — defaults stand unless vetoed before execution

1. **Thresholds** — `RATE_FLOOR 20/hr`, `FADE_RATIO 0.5`, `CLEAR_RATIO 0.75`,
   `SUSTAIN_MINUTES 3`, `WINDOW_WARN_HOURS 2`, the §3.2 band-call evidence
   margin `BAND_MARGIN 2.0×`, tick 30 s. Named constants in `Advisor`, one
   place to retune after a real contest weekend.
2. **`⇧⌘A`** for the section toggle.
3. **The band-daypart reference** to bank (ARRL operating guidance is the
   expected source) — research doc lands before the weight table is written,
   per house rule; the table cites it.
4. **Space-weather feed (NOAA SWPC) stays out of v1** — offline solar
   geometry only. A live-K-index modifier is a clean phase-2 strand.

## 10. Execution notes for the implementing session

- Work in a worktree; run `xcodegen generate` after each file-set lands.
- Commit sequence, each with the full suite green and the command + output
  recorded: **(1)** `SolarGeometry` + tests · **(2)** `NeededMult` + tests ·
  **(3)** `Advisor` engine + tests · **(4)** `AdvisorSection`, settings,
  seams, README (features + keyboard row + test count) — docs ship with the
  behavior.
- No party JSON changes, no schema changes, no UI branching on any party id —
  every advisory reads the definition through existing types.

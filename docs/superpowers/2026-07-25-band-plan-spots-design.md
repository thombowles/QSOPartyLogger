# Band map spots: column stacking, worked-spot greying, band-plan mode switching

2026-07-25. Three independent changes to the band map, requested together.
Provenance for the band plan is banked in
[`docs/research/band_plan_sources.md`](../research/band_plan_sources.md).

## 1. Stack colliding spots into columns

**Today.** `BandMapView.spotRows` walks the visible spots top-down and pushes
each one at least 13 pt below the last: `y = max(trueY, lastY + 13)`. A dense
pile-up cascades — six spots inside 2 kHz drag the sixth label 60 pt below
where it belongs, and every label after it inherits the offset. Nothing on
screen says the label has moved.

**Change.** Spots keep their true `y`. A spot that would collide with one
already placed moves *sideways* into the next column instead of downward.

```
14050 ─────────────────
         ● K5CW   ● W5ZN   ● N5AW
14045 ─────────────────
         ● AA5B
14040 ─────────────────
         ● K0RF   ● NR5M
```

The placement is a pure function in `Sources/Core/Spotting/BandMapLayout.swift`
so it is testable without SwiftUI:

```swift
BandMapLayout.place(spots:scale:height:rowHeight:columnWidth:availableWidth:)
    -> [Placement]   // spot, y, column
```

Algorithm: sort descending by frequency (top of the map first); for each spot,
take the leftmost column whose last occupant sits at least `rowHeight` higher;
if every column within `availableWidth` is taken at that `y`, fall back to the
current push-down inside the last column. That fallback keeps today's guarantee
that **no spot ever disappears** — a 20-deep pile-up on one frequency still
shows all 20. The number of columns follows the panel width, so widening the
panel spreads a pile-up instead of stacking it.

## 2. Worked spots grey out and are skipped by ⌘← / ⌘→

**Today.** Two things are tangled. Worked spots are already drawn dimmed
(`BandMap.swift:297`) — but the comparison is `workedCalls.contains(row.spot.call)`
against a set that was built uppercased, so a cluster spot that arrives in mixed
case never matches and never dims. Separately, the "Hide stations already
worked" filter removes them outright, and because ⌘←/⌘→ reads the same filtered
list, navigation and the map agree by construction.

**Change.**

- Compare uppercased on both sides. This alone fixes the dimming.
- Dim harder and unambiguously: grey **and** struck through, so "worked" reads
  differently from "faint".
- `SpotStore.next(in:afterKHz:direction:workedCalls:)` skips worked calls. When
  every spot in the direction of travel is worked, it returns `nil` and the
  radio stays put — there is nothing new to work that way.
- The "Hide stations already worked" filter **stays**, default off, for the
  operator who wants a decluttered map late in a contest.

Worked means *worked on the current band and mode*, which is what
`workedCallsOnCurrentBandMode` already computes — a station worked on CW is not
worked when you switch to phone.

## 3. Band-plan-aware mode switching

**New** `Sources/Core/Models/BandPlan.swift`. One question, one answer:

```swift
BandPlan.radioMode(atKHz: Double) -> ModeClass?   // .cw or .phone, never .digital
```

Per-band CW→phone crossovers, from 47 CFR §97.305(c) with §97.301(a) for the
80/75 m boundary and the ARRL band plan for 160 m (where the CFR permits phone
band-wide and so supplies no crossover):

| Band | Phone from | Band | Phone from |
| --- | --- | --- | --- |
| 160 m | 1843 kHz (ARRL) | 17 m | 18110 kHz |
| 80 m | 3600 kHz | 15 m | 21200 kHz |
| 60 m | — no split | 12 m | 24930 kHz |
| 40 m | 7125 kHz | 10 m | 28300 kHz |
| 30 m | never — CW band | 6 m | 50100 kHz |
| 20 m | 14150 kHz | 2 m | 144100 kHz |
| | | 1.25 m, 70 cm | — no split |

`nil` on 60 m, 1.25 m and 70 cm, and outside any band edge: no defensible
CW/phone boundary exists there, so the app leaves the mode alone.

**This is a second, separate table from `SpotFilter.segments`, on purpose.**
They answer different questions. `SpotFilter` guesses what mode a *spot* is in
— a comment-first heuristic that wants the FT8 watering holes and is allowed to
be wrong. `BandPlan` decides what mode *your radio* should be in, from the
regulations, and must not be wrong. Neither should be rewritten in terms of the
other.

**When it fires.** App-initiated QSY only — clicking a spot, typing a frequency
or band, ⌘←/⌘→, ⌘J, clicking empty map. Turning the VFO knob never overrides
the operator's mode. Concretely, one `applyBandPlanMode(kHz:)` on the existing
`qsyTo`/`tune`/`jumpToCQFrequency` paths in `MainView`.

**What it does not do.** It never selects a digital mode — if the target
frequency is in a data segment the mode is left alone, matching N1MM, whose
manual says it *"does not switch the radio automatically to a digital mode."*
It also does nothing when the mode is already right, so it cannot thrash. USB
vs LSB is not its business: it asks for `SSB` and the driver resolves the
sideband it already resolves today (`ElecraftK3Driver.cmdSetMode`, USB at or
above 10 MHz).

**Disconnected radios** get the same treatment via `manualRawMode`, so the mode
recorded in the log is right whether or not CAT is running.

**Setting.** `followBandPlan`, default **on**, in the band map's popover under
its own BAND PLAN heading — the band map is where N1MM keeps band plan
configuration too.

## Testing

New tests: `BandMapLayout` placement (no collision, sideways fan-out, column
reuse after a gap, overflow fallback, nothing dropped), `SpotStore.next` worked
skipping in both directions and the all-worked case, and `BandPlan.radioMode`
crossovers on every band including the `nil` bands and the 30 m CW-only case.

Existing `SpotFilterTests` mode-inference assertions must not move — `BandPlan`
is additive and `SpotFilter.segments` is untouched.

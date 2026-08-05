# Run rate in the score sidebar

**Date:** 2026-08-01
**Status:** approved

## Problem

The score sidebar answers "what have I scored" and "what am I missing". It
cannot answer "how is it going *right now*" — the question that drives every
operating decision in a contest: keep calling CQ on this frequency, or move to
another band; stay in Run, or go Search & Pounce; take the break now, or push
another half hour.

Nothing in the tree computes a rate. `grep -rniE "\brate\b|per hour"` over
`Sources/` returns only serial-port baud rates and points-per-QSO prose.

The one adjacent thing that does exist is
[`ScoreSnapshot.operatingMinutes(timestamps:breakThreshold:)`](../../../Sources/Core/History/ScoreSnapshot.swift),
which already implements the contest off-time convention — gaps of 30 minutes
or more between consecutive QSOs are not on-air time. Any average-rate figure
must call it rather than reimplement the rule.

## Reference: how N1MM does it

Anchored to the N1MM Logger+ manual, *The Info Window*,
<https://n1mmwp.hamdocs.com/manual-windows/info-window/>, fetched 2026-08-01.

The near-term rate graph shows "the rate for the last 10 QSOs, the last 100
QSOs, the last hour, and the interval since the start of the current clock
hour." The hourly graph offers 20-, 30-, or 60-minute moving averages.

Two structural lessons carry over directly, and one figure does not.

**Carries over — mix count-based and time-based windows.** A count-based window
("last 10 QSOs") self-scales: it always holds data, and it silently widens when
things go quiet. A time-based window ("last 60 minutes") is the only kind that
*falls to zero when you stop*. Each covers the other's blind spot; either alone
misleads.

**Carries over — the clock hour is its own figure.** Sponsors tabulate by UTC
hour and operators talk that way ("48 in the 18Z hour"), so the partial current
hour is worth a row of its own.

**Does not carry over — the 100-QSO window.** In CQ WW at 170/hr, 100 QSOs is a
35-minute window, which is what makes it a *recent* figure. A state QSO party
runs 30–50/hr, where 100 QSOs spans two and a half hours — no longer "recently"
but "on average", duplicating a figure this design computes properly instead.
It is also blank for most of the contest for an out-of-state entry that finishes
with 180 QSOs. That row is spent on an off-time-corrected average.

## The four figures

| Row | Formula | Kind |
| --- | --- | --- |
| `Last 10` | `(n−1) × 3600 / (now − t_first)` over the last ≤10 QSOs | extrapolated |
| `60 min` | count of QSOs in `(now−3600, now]` | count |
| `Hour` | count since the top of the UTC clock hour, then `→ projected` | count + extrapolation |
| `On air` | `validQSOs × 60 / operatingMinutes` | extrapolated |

### Why `n−1` and not `n`

A QSO every 60 seconds is a rate of 60/hr. Ten such QSOs span **nine** minutes,
not ten — `n` timestamps bound `n−1` intervals. So:

- `10 × 3600 / 540` = 66.7/hr — wrong.
- `9 × 3600 / 540` = 60/hr — correct.

This is a correctness argument, not a convention preference, and it ships as a
test using exactly this worked example.

### Why the denominator ends at `now`, not at the last QSO

Define the window as `[t_first, now]` rather than `[t_first, t_last]`. The
figure then decays on its own while the operator sits idle, instead of
reporting a rate from twenty minutes ago as though it were current — which is
the entire failure mode of a rate meter. When `now == t_last` the formula
collapses to the plain `(n−1)/span` form, so the correctness above is
unaffected. One formula, no stale-window special case.

### Which QSOs count

Exactly the rows `ScoreEngine.ScoreBreakdown.validQSOs` counts: the caller
subtracts `dupeRowIDs ∪ invalidRowIDs ∪ outOfScopeRowIDs` before handing
timestamps to `RateMeter`.

A county-line contact contributes **all** of its rows, not one. The `QSOs`
figure an inch to the left in the same card counts them that way (each county
is a separate contact — KSQP rule 11), and two different denominators in one
card is a defect report waiting to happen.

Rows stamped in the future — clock skew, a hand-edited log — are filtered to
`t <= now` so they cannot inflate any window.

### When a figure refuses to answer

One rule, applied consistently: **counts show `0`; extrapolations show `—`.**

`60 min` reading 0 is true and useful: the run died. `Last 10` reading a number
derived from one QSO is not. Concretely:

- `Last 10` — `—` until there are ≥2 QSOs and `now > t_first`.
- `60 min` — always a number. Zero is an answer.
- `Hour` — the count is always shown; the `→ projected` half appears only once
  ≥5 minutes have elapsed in that hour *and* there is at least one contact in
  it, since 2 QSOs three minutes in projects to 40/hr on almost no evidence and
  "0 → 0" is noise.
- `On air` — `—` until there are ≥2 QSOs and ≥5 operating minutes.
  `operatingMinutes` floors at 1, so without the floor two QSOs ten seconds
  apart would claim 120/hr.

This is the sidebar's existing "never claim unproven state" rule applied to
numbers.

## Architecture

One new pure type, `Sources/Core/Engine/RateMeter.swift`, in the established
style of `ExchangeSummary` and `OneByOneTracker` — an enum of static funcs, no
party definition, no view, no clock of its own:

```swift
static func reading(timestamps: [Date], now: Date) -> Reading
```

Taking **timestamps and an explicit `now`** is the whole testability story:
every figure is a pure function of two arguments, so tests pin fixed dates and
never race a wall clock. It mirrors `ScoreSnapshot.operatingMinutes(timestamps:)`,
which it calls rather than duplicates.

## The view

`Sources/UI/RateColumn.swift` turns a `Reading` into four labels, values and
tooltips. It is a pure formatter, not a `View` — the same shape as
`SpottingPolicy` — because the cells have to live inside `ScoreSidebar`'s own
`Grid` to align, and because the wording of a `—` is worth a test.
`ScoreSidebar.totalsCard` grows a right-hand column beside the existing total
and breakdown:

```
┌──────────────────────────────────┐
│ SCORE               RATE   /hr   │
│ 12,480                           │
│ QSOs        312     Last 10   42 │
│ Points      624     60 min    38 │
│ Mults        20     Hour   15→39 │
│ Bonus        +0     On air    31 │
│ Dupes         2                  │
└──────────────────────────────────┘
```

**One `Grid`, not two `VStack`s in an `HStack`.** The rate rows line up
one-for-one with the score rows. Baseline-aligning two independent stacks means
hardcoding an offset for the 30pt total, which breaks the moment the system font
size changes; a single four-column `Grid` — label, value, label, value — aligns
rows natively and survives Dynamic Type. `SCORE` and `RATE` share the header
row; the total spans its two cells with the rate side of that row empty.

**The left column is 4, 5, or 6 rows; the rate column is always 4.**
`Category ×` and `Dupes` are conditional. QSOs / Points / Mults / Bonus are
always present and always in that order, so the four rate rows align against
them in every case and the conditional rows hang below — stable with no
special-casing.

**`Hour` carries no elapsed-minutes suffix.** A uniform label column is what
makes the alignment read, and `Hour :23` was the widest thing in it. The elapsed
minutes move to the tooltip: "15 QSOs so far this UTC clock hour, 23 minutes
in — on pace for 39."

**The sidebar's `minWidth` rises from 230 to 250.** Two columns of `.callout`
monospaced digits need about 195pt of card interior; 230 leaves roughly 186.
Shrinking digits or truncating them is not an option in a figure the operator
reads at a glance.

### The tick

`TimelineView(.periodic(from: .now, by: 15))` wraps the totals card. Not just
the rate cells — a single `Grid` is what makes the rows align, so the tick has
to own the grid — but nothing below it: the rosters, county chips and 1×1
trackers stay outside and never redraw on the tick.

Without a tick every time-based figure freezes between QSOs and quietly lies —
`60 min` would keep reporting an hour that ended, and `Last 10` would never
decay. 15 seconds is finer than any figure's resolution, and `TimelineView`
hands the view a date to pass as `now`, which is what keeps `RateMeter` a pure
function rather than something that reads the clock internally.

Each row gets a `.help()` naming its window, matching the tooltip density
already established by `chipHelp` and `CombinedBreakdownSection.helpText`.

## Keyboard path

No new shortcut. Rule 9 requires every feature to have a keyboard path; this is
a read-only indicator with no actuable state, permanently visible at the top of
a panel that is always on screen. There is nothing to actuate. If it later earns
a collapse toggle it takes a chord alongside `⇧⌘M`.

## Testing

`Tests/Core/RateMeterTests.swift`, XCTest, fixed `Date(timeIntervalSince1970:)`
fixtures throughout — no wall clock anywhere:

1. The 60/hr worked example above, pinning the `n−1` convention.
2. Idle decay — the same ten QSOs, `now` advanced, rate halves.
3. Empty log and single-QSO log — every extrapolation `—`, `60 min` = 0.
4. The `—` thresholds: `Last 10` at 2 QSOs, `On air` at 5 operating minutes,
   the `Hour` projection at 5 elapsed minutes.
5. A county-line burst sharing one timestamp — zero-span guard, no divide by
   zero, no infinite rate.
6. A UTC clock-hour boundary — the `Hour` count resets, `60 min` does not.
7. An overnight break — `On air` ignores it (30-minute off-time rule) while
   `60 min` reads 0.
8. Future-stamped rows are excluded.

`Tests/UI/RateColumnTests.swift` covers the display rule separately: which
figures render as `—`, that `60 min` shows `0` rather than blanking, that a
dash explains itself in its tooltip, and that the elapsed minutes dropped from
the `Hour` label survive there.

Shipped as 16 + 8 tests, taking the suite from 1886 to 1910.

## Docs

README gains the rate block in the Scoring section, and the test count moves to
1910. No keyboard-table row, since no shortcut is added.

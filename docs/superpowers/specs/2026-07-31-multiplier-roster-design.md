# Multiplier roster in the score sidebar

**Date:** 2026-07-31
**Status:** approved

## Problem

The score sidebar shows the county class as a full checklist grid — every county
drawn, worked ones green — but every other multiplier class renders as a flat
list of *worked tokens only*:

```swift
ForEach(nonCountyClasses(rule), id: \.self) { multClass in
    let values = score.workedValues(multClass)
    if !values.isEmpty {                                    // hidden until one is worked
        Text(values.sorted().joined(separator: " "))        // worked tokens only
```

In NAQP that means the operator sees the 46 NA entities as a roster and never
sees the 50 states + DC or the 13 provinces at all until they have worked one,
and even then only as a list of what is already done. The sidebar cannot answer
"what am I still missing", which is the question a multiplier tracker exists to
answer.

Scoring is correct and unchanged. This is a display gap.

## Reference: how N1MM does it

Anchored to the N1MM Logger+ manual, *The Multipliers Window*,
<https://n1mmwp.hamdocs.com/manual-windows/multipliers-window/>, fetched
2026-07-31.

1. **All possible multipliers are shown, worked or not.** Worked-only is an
   opt-in right-click toggle, "Show Only Worked & Expected to be Worked Mults";
   with it unchecked the window shows "all possible spots, worked or not."
2. **Per-multiplier band blocks.** Each multiplier carries a row of colored
   blocks, one per band. The legend: "blue for a band where the mult has already
   been worked", with red and green reserved for spot-driven states — "a station
   is available for a single multiplier on that band" and a double-mult QSO
   respectively.
3. **Mouse-over gives the detail** — country name, continent, bearings.
4. Displayed bands and modes are configurable ("Set Bands and Modes to be
   Displayed").

We adopt 1, 2 and 3. The red/green spot-driven states are **out of scope** for
this change (see below).

## Roster sources

Every roster is derived from the party definition, so all 47 bundled parties are
automatically correct with no per-party data:

| Class | Roster source | Rule-sides affected |
| --- | --- | --- |
| `.county` | `party.counties` | 88 |
| `.state` | `MultClass.acceptedStateTokens` − `party.excludedStateTokens`, plus `party.stateAliases` keys | 50 |
| `.province` | `party.provinces` (13, or OhQP's 11) | 50 |
| `.section` | `party.sections` | 1 (PAQP) |
| `.dx` | unbounded — no roster exists; stays a worked-only token list | 36 |

`.dx` is the one class that cannot be enumerated: under `dxStyle == .prefix` any
plausible prefix is a multiplier. It keeps today's behavior.

## Slots come from `CountScope`

The block strip for a multiplier is the set of scope values that multiplier can
be counted under — exactly the `scope` component `ScoreEngine` already stamps
into `MultKey`:

| `CountScope` | Slots | In-state / out-of-state sides |
| --- | --- | --- |
| `once` | 1 (renders as a plain chip, as today) | 28 / 26 |
| `perMode` | one per `party.allowedModeClasses` | 10 / 9 |
| `perBand` | one per `party.validBands` — NAQP: 6 | 6 / 8 |
| `perBandMode` | band × mode | 4 / 5 |

51 of 94 rule-sides have a real band or mode dimension, so this is not
NAQP-specific plumbing.

**`ScoreEngine.scopeComponent` becomes internal and is called by the roster**, so
a block is filled if and only if the engine holds the matching `MultKey`. The
display cannot drift from the score, and a future scope change updates both.

## Components

### `MultiplierRoster` (`Sources/Core/Parties/MultiplierRoster.swift`)

Pure, no SwiftUI, fully testable.

```
MultiplierRoster.classes(party:rule:) -> [RosterClass]
    RosterClass: multClass, label, entries [RosterEntry], slots [Slot]
    RosterEntry: token, name (tooltip), worked slots resolved against a breakdown
```

Ordering is alphabetical by token within a class. N1MM groups states by the ten
US call areas; a narrow sidebar scans better alphabetically and our chips are
labeled. Revisit if it reads poorly on the air.

### `ScoreSidebar` rendering

Each class becomes a collapsible section. The disclosure header carries both
counts — `States 12/51 · 34/306` — multipliers touched, then filled slots out of
possible slots. Under `once` scope the second figure is redundant and is
omitted.

The county grid keeps its existing `CountyGrouping` layout (by member contest,
then state) and gains the same slot strip.

### Collapse state

Persisted per party + class in `AppSettings` using the existing
`didSet` → `UserDefaults` pattern, stored as a `[String]` of `"<partyID>.<class>"`
keys. Everything starts expanded — nothing is hidden on first run.

Keyboard path required by the constitution: a command to expand/collapse all
roster sections in the sidebar.

## Testing

`Tests/Core/MultiplierRosterTests.swift`:

- roster contents per class — NAQP (states + provinces + 46 NA entities), a
  single-state party, PAQP sections
- home-state exclusion: a TX party's state roster has 50 entries, no TX
- NAQP's state roster has 51 — DC included, no exclusions
- OhQP's province roster is 11, not 13
- slot counts for all four `CountScope` cases
- `.dx` yields no roster
- **cross-party consistency over all 47 bundled parties**: for both rule sides,
  every token in a roster is credited by the engine to that same class, and
  every token the engine credits (excluding `.dx`) appears in a roster. This is
  the accuracy guard — it fails if a roster and the scorer ever disagree.

Verification is by `xcodebuild test`, reported with its output.

## Out of scope

**Spot-driven red/green blocks.** N1MM colors a block red when a spotted station
is available for that multiplier on that band. `Sources/Core/Spotting/` already
carries spots and band information, so this is buildable, but it is a distinct
feature from the roster and belongs in its own commit.

**Call-area grouping for states.** Alphabetical first; revisit with on-air
feedback.

# Adjustable spot text size on the band map

Date: 2026-07-25
Status: approved, ready for an implementation plan

## Problem

Spot labels on the band map are drawn at a fixed size: the callsign at 10 pt
monospaced semibold ([`BandMap.swift:393`](../../../Sources/UI/BandMap.swift)),
the county badge at 8 pt ([`BandMap.swift:399`](../../../Sources/UI/BandMap.swift)).
On a high-density display, or across the room from the operating position, that
is small. The operator needs to be able to make it bigger.

The size is not a free variable. Three other constants in `BandMapView` are
tuned to 10 pt text and must move with it, or bigger labels simply overlap:

| Constant | Value | Line |
| --- | --- | --- |
| `columnWidth` — horizontal pitch between label columns | 60 | `BandMap.swift:461` |
| `rowHeight` — vertical clearance one label needs | 13 | `BandMap.swift:463` |
| Y offset that centres the label on its frequency | 6 | `BandMap.swift:424` |

`columnWidth`'s own comment already states the coupling: "a six-character call
at 10 pt monospaced plus its dot, with room to breathe."

## Decisions taken

Three questions were settled before design:

1. **Scope: spot labels only.** The callsign and its county badge, plus the
   collision geometry above. The frequency ruler ticks (9 pt), the ruler gutter
   (46 pt), the CQ label and the VFO arrow are all unchanged.
2. **Granularity: four named presets**, not a free point size and not a
   percentage scale factor. Each preset carries its own geometry, so no
   intermediate value can land in a state that lays out badly.
3. **No keyboard chord.** The control lives in the band map's funnel popover
   only. This is a deliberate exception to CLAUDE.md rule 9 (keyboard-first),
   taken on the grounds that text size is set once and left alone, unlike CW
   speed or spot stepping. It is recorded here so it reads as a decision rather
   than an omission. The picker is Tab-reachable once the popover is open; what
   has no keyboard path is *opening* the popover, which is already true of every
   other control in it.

A fourth decision came from review: **today's rendering is the smallest
preset**, and the scale grows upward from it.

## The presets

| Preset | Call pt | County pt | Column pitch | Row clearance | Y offset | Panel min width |
| --- | --- | --- | --- | --- | --- | --- |
| **Small** (default) | **10** | **8** | **60** | **13** | **6** | **190** |
| Medium | 12 | 10 | 72 | 16 | 7.5 | 198 |
| Large | 14 | 11 | 84 | 18 | 8.5 | 222 |
| Huge | 16 | 13 | 96 | 21 | 10 | 246 |

Every row holds the same ratios — pitch = 6 × call, clearance ≈ 1.3 × call,
offset = clearance / 2 − 0.5, county ≈ 0.8 × call — but the numbers are stored
as a literal table, not computed by formula. A formula reproduces the Small row
only by coincidence of rounding; one change to it would silently re-render a map
the operator has already arranged around. The literal table makes "the default
is a no-op" an assertable fact rather than an arithmetic accident.

Small is exactly what `BandMap.swift` hardcodes today. An operator who never
opens the popover sees no pixel move.

### Why panel minimum width is part of the table

The band map panel is 230 pt wide by default
([`BandMap.swift:483`](../../../Sources/UI/BandMap.swift)). `placements` passes
`size.width - rulerWidth - labelInset` as the label area, so at the default
width that is 230 − 46 − 8 = 176 pt, and `BandMapLayout.place` derives the
column count as `availableWidth / columnWidth`:

| Preset | 176 / pitch | Columns |
| --- | --- | --- |
| Small | 176 / 60 | 2 |
| Medium | 176 / 72 | 2 |
| Large | 176 / 84 | 2 |
| Huge | 176 / 96 | **1** |

At one column every collision falls through to the overflow branch and pushes
*down* in column 0, dragging labels off their true frequency — the precise
failure `BandMapLayout`'s header comment says the sideways-stacking design
exists to prevent. Huge would quietly undo stacked spots on a default-sized
panel.

So the panel's minimum width scales with the preset:
`max(190, rulerWidth + labelInset + 2 × columnWidth)` = `max(190, 54 + 2 × pitch)`.
That guarantees at least two columns at every size. Small computes to 174, below
the existing 190 floor, so it stays at 190 and today's panel is untouched.

## Design

### `SpotLabelSize` — a Core enum carrying its own geometry

New file `Sources/Core/Spotting/SpotLabelSize.swift`, beside
`BandMapLayout.swift`. `String`-raw-valued, `CaseIterable`, `Identifiable`.

Each case exposes: `callPointSize`, `countyPointSize`, `columnWidth`,
`rowHeight`, `verticalOffset`, `minimumPanelWidth`, and `displayName`.

Sizes are `Double`, not `CGFloat`, matching `BandMapLayout`'s existing style and
keeping the file to `import Foundation` with no SwiftUI dependency.
`BandMapView` converts at the point of use, as it already does for
`Double(size.height)`.

The alternative — an enum in `AppSettings` with the geometry computed in
`BandMapView` — was rejected on two counts: it puts layout arithmetic in the UI
layer, which the `Sources/UI/` rule warns against, and it puts the geometry
somewhere `BandMapLayoutTests` cannot reach.

### Storage

A `spotLabelSize: SpotLabelSize` property on `AppSettings`, `didSet`-persisted
under a new `"spotLabelSize"` key, following the same shape as every other band
map preference in that file.

Initialisation falls back to `.small` when the key is absent **or** holds an
unrecognised token, so a hand-edited or downgraded preference file cannot leave
the map with no size at all.

Not `@AppStorage`. The popover already binds `@Bindable var settings`, and
`AppSettings` takes an injected `UserDefaults`, which is what lets
`PreferenceIsolationTests` exercise it against a scratch suite.
(`bandMapSpanKHz` at `BandMap.swift:121` is the one `@AppStorage` in the app; it
is not a precedent worth extending, and it is not touched here.)

### Layout

`BandMapLayout.place` **does not change**. It already takes `rowHeight` and
`columnWidth` as parameters. `BandMapView.placements` feeds it the values off
the current size instead of the two `private static let`s, which are deleted.

`BandMapView` reads the size from `model.settings.spotLabelSize` and uses it in
four places: the call font, the county font, the `.offset(y:)` centring, and the
`.frame(minWidth:)` on the body. The `private static let columnWidth`,
`private static let rowHeight` and the literal `- 6` all go away.

### UI

A `SPOT LABELS` section in the funnel popover, placed directly under the "Band
Map" headline and above `SPOT FILTERS`, holding a segmented picker bound to
`settings.spotLabelSize`.

Segment labels are `S` / `M` / `L` / `XL`, matching the terse style of the
existing span picker (`25` / `50` / `100` / `All`) and fitting the popover's
290 pt width. The full names go in a `.help()` tooltip on the picker.

**Reset All does not touch it.** That button resets spot filters, age-out and
band-plan following; wiping the operator's text size because they cleared a band
filter would be a surprise. This is stated explicitly because the button's
`.disabled` condition enumerates what it considers, and the new setting must be
left out of both the action and that condition.

## Testing

New `Tests/Core/SpotLabelSizeTests.swift`:

- Small's six numbers equal today's hardcoded constants exactly
  (10, 8, 60, 13, 6, 190) — the default-is-a-no-op guarantee.
- Call point size, column pitch and row clearance increase strictly across
  `allCases` in declaration order.
- `minimumPanelWidth` leaves room for at least two columns at every preset:
  `(minimumPanelWidth - 46 - 8) / columnWidth >= 2`.
- `rawValue` round-trips for every case.

New cases in `Tests/Core/BandMapLayoutTests.swift`, proving the geometry
actually threads through rather than only the font:

- Three spots 1 kHz apart in a 180 pt label area place into 3 columns at
  Small's 60 pt pitch and 2 at Huge's 96 pt pitch.
- The same spots at Huge's 21 pt clearance push down further than at Small's
  13 pt, and no spot is dropped at either size.

New case alongside the existing preference tests in `Tests/App/`:

- `spotLabelSize` persists to and reloads from an injected scratch
  `UserDefaults`, defaults to `.small` on an empty suite, and falls back to
  `.small` on a garbage stored token.

## Documentation, same commit

- README band map bullet (around line 285) gains the size control.
- The spot-filters paragraph (around line 323) names the new popover section.
- Test count at [README.md:632](../../../README.md) is currently 964. Replace it
  with the count `xcodebuild test` actually reports after the new tests land —
  read the number off the run, do not add up the expected cases by hand.
- No keyboard reference table change — there is no chord.

## Implementation risk to verify, not assume

Scaling `.frame(minWidth:)` on `BandMapView` relies on `NSHostingView`
propagating the new minimum up to the hosting `NSPanel`'s `contentMinSize`. The
panel carries an autosaved frame (`setFrameAutosaveName("BandMapPanel")`), so a
panel already saved at 230 pt may not widen on its own when the operator picks
Huge — it may only be prevented from shrinking further.

If the propagation does not hold, the fallback is for `BandMapPanel` /
`BandMapView` to set `contentMinSize` on the panel directly when the size
changes, and to widen the panel's current frame to the new minimum if it is
narrower. Whichever path is taken, the acceptance check is the same: pick Huge
on a default-width panel and confirm from a log of the placement results that
labels still land in two columns rather than one.

## Out of scope

- **County badge overflow.** A hub spot's badge already overruns the 60 pt
  column today (≈36 pt call + dot + spacing + ≈20 pt badge), so hub labels can
  bleed into the next column. Scaling makes this neither better nor worse, and
  fixing it is a separate change to how `columnWidth` is derived.
- Ruler tick size, ruler gutter width, CQ label and VFO arrow — all fixed, per
  decision 1.
- Any keyboard chord for the setting, per decision 3.
- `bandMapSpanKHz`'s `@AppStorage` — left exactly as it is.

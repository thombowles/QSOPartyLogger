# A log window that shrinks — design

**Date:** 2026-08-22
**Status:** built the same day from the operator's request; the choices under
*Decisions* are his to overturn, and each names the alternative
**Kind:** app-layer layout change — no party, no radio, no schema. Its own
commit, the full suite green before and after
**Origin:** the operator, 2026-08-22, the same sitting as
[`2026-08-22-bolted-band-map-design.md`](2026-08-22-bolted-band-map-design.md):
"Allow the main windows to be resized smaller. Today, it's hard to have
multiple open at the same time along with SmartSDR."

## Why

The log window will not go below 1040 × 640 points. Two of them beside a
panadapter do not fit on one display. The floor is `.frame(minWidth: 1040,
minHeight: 640)` on the window's content, with `minWidth: 760` on the
entry/log pane and `minWidth: 250` on the score sidebar — all three from the
first UI commit (`364b462`), never revisited.

Measured on 2026-08-22 with `NSHostingController.sizeThatFits(in: .zero)` —
the size SwiftUI hands a window as its minimum — and `fittingSize`, the ideal:

| View | Minimum | Ideal |
| --- | --- | --- |
| `MainView` | 1040 × 640 — the explicit floor | the same |
| `ScoreSidebar` | 250 wide | 270 |
| `RadioBar` | 24 wide — a `FlowLayout`, already wraps | 1011 × 42 |
| `MessagesRow` | **908 × 43** | 1352 × 43 |
| `EntryBar`, no party / NAQP / CQP | 498 / 468 / 498 wide | +37 |
| `EntryBar`, Skeeter Hunt with a P2P field | **708** wide | 745 |
| `LogTable` | 0 — flexes | — |

So lowering the floors alone is not enough: the messages row is an `HStack`
that cannot go below 908, and with the sidebar at its 250 floor the row is
already over-full at 1040 (790 for the pane, 884 of content) — the interval
stepper is the first thing off the right edge. The entry row is the next wall
at 708 for the widest party. And the sidebar's 250 is a quarter of a window
the operator wants at half a display.

## Approaches considered

1. **Rows that wrap only when narrower than they are today; a sidebar that
   hides; lower floors.** `ViewThatFits` tries today's single-row `HStack`
   first and falls back to a `FlowLayout` of the same items, so nothing
   changes at any width the window can reach now, and below that the row
   folds instead of clipping. The score sidebar gets a show/hide (⌃⌘S — the
   macOS sidebar chord). The floors drop to what the folded rows need.
   **Chosen.**
2. **Lower the floors and nothing else.** Rows overflow and clip — the
   stepper, then Repeat CQ, then ESM fall off the edge, all of them keyboard
   paths the operator cannot see. Already true at 1040 with the sidebar
   narrow; this would make it the normal state.
3. **A second, compact layout.** A "mini" mode with its own arrangement of
   the same views. Two layouts to keep correct, and a mode switch for the
   operator to find; approach 1 gives the same result with the one layout
   folding itself.

## Decisions

1. **Floors: the pane 760 → 560, the window 640 → 360 tall, and the
   window's explicit 1040 goes.** 560 holds the everyday entry row — call,
   two reports, the exchange and the Log button — on one line with its
   padding (535 + 24: `ViewThatFits` picks the line by its *ideal* width,
   which has the Log button's label in it, not by the 498 the row can be
   squeezed to). Only Skeeter-with-P2P folds above that, below ~770. The
   window's width is then the pane plus the sidebar, if shown: ~820 with
   it, ~560 without. 360 tall holds the radio bar, the strip, the entry
   row, the message row and five log rows. Two 820-wide logs fit side by
   side on a 1920-point display with room above for a panadapter.
   *Alternative:* no floors at all — a window crushed to a sliver by a
   stray drag, for no gain. *Alternative:* 520, the first number tried —
   at which the everyday row folds its Log button onto a second line.
2. **The log table's floor 240 → 120.** `logTableMinAlone` keeps its job —
   the log shrinks by exactly the history table's height so the window
   never grows when a match appears — at a lower number. *Alternative:*
   keep 240, which alone would hold the window at ~480 tall.
3. **A row wraps only below the width it has today.** `ViewThatFits(in:
   .horizontal)` picks the first child whose *ideal* width fits, so the
   single-row variant declares its ideal to be its minimum
   (`MessagesRow.singleRowWidth`, the 884 measured above, as a named
   constant a test pins) and the window sees exactly today's row at every
   width ≥ 908; narrower, the `FlowLayout` variant folds the F-keys and the
   controls onto more lines. The entry row needs no constant — its fields
   are fixed width, so its ideal is its minimum. *Alternative:* `FlowLayout`
   always — which, because a flow lays items at their natural width, would
   fold the controls onto a second line even at the default 1280 window.
4. **The score sidebar hides per window**, remembered by the window
   (`@SceneStorage`), from a toolbar button and **⌃⌘S**. While it is hidden
   the station strip shows the score total, so a squeezed log still says
   what it is worth. *Alternative:* one app-wide switch — but the point of
   two windows is that one may keep its sidebar while the other is pushed
   into a corner. *Alternative:* a View-menu item — the App's `.commands`
   cannot hold per-window state without `FocusedValue` plumbing, and the
   toolbar button with its key is the pattern every other window control
   follows.
5. **Nothing changes at today's sizes.** The default window stays 1280 ×
   800; every row is laid out exactly as before at any width the window can
   already reach. The sidebar's own 250 floor and 400 cap stay — the score
   card's two columns do not shrink.

## Design

### `MessagesRow`

```swift
var body: some View {
    ViewThatFits(in: .horizontal) {
        HStack(spacing: 6) { items }          // today, verbatim
            .frame(idealWidth: Self.singleRowWidth)
        FlowLayout(horizontalSpacing: 6, verticalSpacing: 4) { items }
    }
    .padding(...)                             // as today
}
/// The single row's minimum content width, measured 2026-08-22 — declared as
/// its ideal so `ViewThatFits` keeps it at every width it fits today.
static let singleRowWidth: CGFloat = 884
```

`items` is a `@ViewBuilder` property holding the picker, the eight keys, the
CQ chip, ESM, Repeat CQ and the stepper; the `Spacer` that right-aligned the
controls stays in the `HStack` variant only.

### `EntryBar`

The same shape: the field row as today inside `ViewThatFits`, the
`FlowLayout` of the same fields as the fallback. The second line (dupe
warning, exchange notices) is unchanged.

### `MainView`

- `splitContent.frame(minHeight: 360)` replaces `.frame(minWidth: 1040,
  minHeight: 640)`; `leftPaneSpotWired`'s `.frame(minWidth: 760)` becomes
  560.
- `@SceneStorage("scoreSidebarHidden") private var scoreSidebarHidden =
  false`; the `HSplitView` adds the sidebar only while it is shown.
- Toolbar: a *Score* button (`sidebar.trailing`), `⌃⌘S`, wearing the hint;
  it toggles the storage.
- The station strip, while the sidebar is hidden: the score total beside
  the band and mode.
- `WorkedBeforeTable.logTableMinAlone` 240 → 120.

### The gate

⌃⌘S is SwiftUI's, like ⌘R and ⇧⌘S: `KeyMonitorGate.action` returns nil for
it and `isShortcut` is true, so it passes through and leaves a repeating CQ
alone. No change — a test says so.

### What does not change

`RadioBar` (already a flow), `ScoreSidebar`, `LogTable`,
`WorkedBeforeTable`'s arithmetic, `BandMapPanel` and the bolt, the default
window size, and every keyboard path.

## Tests

- `Tests/UI/WindowSizeTests.swift` — the probe that produced the table
  above, kept with bounds: `MainView`'s minimum is at most 840 × 400 with
  the sidebar shown; the everyday entry row is one line at the pane's
  floor; `MessagesRow` is one line tall at `singleRowWidth` plus
  its padding and taller one point below it, and its minimum width is under
  200; `EntryBar` for Skeeter with P2P has a minimum width under 320;
  `ScoreSidebar`'s floor is still 250.
- `KeyMonitorGateTests` — ⌃⌘S is not the gate's, and leaves a repeating CQ
  alone.
- `FlowLayout.packRows` is already pinned.

## Docs

README: the keyboard row for ⌃⌘S; under *Scoring*, that the sidebar hides
and the strip shows the total; a short *Fitting two logs on one display*
note with the floors; the test count. This spec's as-built note.

## Commit sequence

1. `docs: design for a log window that shrinks` — this file.
2. `window: the log window shrinks to 560 × 360 — rows fold, the score
   sidebar hides (⌃⌘S)` — the rows, the view, the tests, README, and this
   spec's as-built note.

## Open questions

- The look of a folded row, and of the strip's score readout, is not
  verifiable without a screen; the bounds in the tests are the claim.
- `@SceneStorage` restores with the window; a log reopened from the
  dashboard or the Finder starts with the sidebar shown. Not pinned.

## As built — 2026-08-22

Landed on `claude/smaller-windows` in the two commits above, on top of
`dcf08b3`.

**Suite: 3105 → 3112, 0 failures** (2 skipped, as before). The tests went in
first — the probe that produced the table under *Why*, rewritten with bounds
— and the test target failed to build on `MessagesRow.singleRowWidth` alone.
Then the rows, the floors, the sidebar and the strip; on the first run five
of the six size tests passed and one did not: at the 520 floor the
*everyday* entry row folded, its Log button on a second line. The cause is
the rule in Decision 3 read the other way round — `ViewThatFits` chooses by
the single line's *ideal* width, 535 for that row, which has the Log
button's label in it; the 498 in the table is what the row can be squeezed
to, not what it asks for. The floor moved to 560 (535 + padding), the test
pins exactly that promise, and the whole suite then passed: `Executed 3112
tests, with 2 tests skipped and 0 failures`.

Worth recording:

1. **Measure, then decide.** The table under *Why* came from a hosted test
   before a line of layout changed; without it the messages row — 908 wide,
   unfoldable — would have been found by the operator, not the suite.
2. **`@SceneStorage` outside a scene is harmless.** `WindowSizeTests` builds
   `MainView` in a bare `NSHostingController`; the property falls back to
   its default and nothing is written.
3. **The folding variants re-create the fields.** Crossing the fold width
   while typing moves the row between two containers, and SwiftUI gives the
   text fields new identity — a call half-typed at the moment of a resize
   could lose focus. Not seen, not pinned; the window is not resized at 35
   WPM.

**Not yet seen on a screen.** The Release build is staged for the operator:
the folded rows, the strip's total, the Score button.

# A band map bolted to its log window — design

**Date:** 2026-08-22
**Status:** built the same day from the operator's request; the choices under
*Decisions* are his to overturn, and each names the alternative
**Kind:** app-layer window behaviour — no party, no radio, no schema. Its own
commit, the full suite green before and after
**Origin:** the operator, 2026-08-22: "Add an option to bolt the band map to
the side of the main window so that when I'm running multiple contests I can
keep the band maps straight." Two or more log windows is his normal
configuration — see
[`2026-08-22-shared-radio-connection-design.md`](2026-08-22-shared-radio-connection-design.md)

## Why

The band map is a floating utility panel, one per log window
(`BandMapPanel.make`). Three things about it make two of them impossible to
tell apart:

1. **Both open in the same place.** The panel's frame is autosaved under one
   name, `"BandMapPanel"`, shared by every window — so the second log's map
   restores exactly on top of the first's.
2. **Both float above both logs.** `level = .floating` was chosen so the map
   could sit over another app's panadapter; it also means bringing log B to
   the front leaves log A's map on top of it.
3. **Neither moves with its log**, and neither says which log it belongs to.

The operator's word is *bolt*: the map should be fastened to the side of its
own window, so that where the window goes, its map goes, and the two read as
one unit.

## Approaches considered

1. **A child window, pinned to one side of the log window.** AppKit's
   `addChildWindow(_:ordered:)` makes the panel move with its parent and be
   ordered with it; a pin keeps it flush against the chosen edge, the height of
   the window. The map stays a panel — resizable, hideable with ⌘B, free again
   with one click. **Chosen**: it is the native mechanism for exactly this
   relationship, the view code does not change, and the three problems above
   go away together — each map is beside its own log, at its log's level, and
   moves with it.
2. **A third pane inside the window.** The map as a column of the
   `HSplitView`, next to the score sidebar. Nothing could be more clearly
   "this log's map" — but it stops being a panel: it can no longer be put
   over a panadapter, resized on its own, or hidden without the layout
   shifting; `MainView` sits at the type-checker's budget; and the operator
   asked for the map *beside* the window, not in it.
3. **Follow the window by hand, still floating.** Observe the window's moves
   and re-place the panel, with no child relationship. It is the same observer
   code as 1 with the floating level kept — which leaves problem 2 exactly as
   it is. Nothing in it is better than 1.

## Decisions

1. **Off by default.** `bandMapBolted` is false: the map floats exactly as it
   does today until the operator bolts it. *Alternative:* bolted by default —
   a change under every existing operator's map for a request that asked for
   an option.
2. **Right side by default; left offered.** `bandMapBoltSide` is `.right`: the
   score sidebar is already the window's right-hand column, and the map
   continues it. Left exists for a window that lives against the right edge
   of its display. *Alternative:* pick the side with room automatically —
   which would flip the map from one side to the other as the window is
   dragged across the screen.
3. **Bolted means bolted.** The map sits `gap` (8 pt, the distance the
   first-open placement has always used) from the window's edge, its top and
   bottom aligned with the window's. Dragging the map by its title bar snaps
   it back; moving or resizing the window re-pins it. The *width* is the
   operator's — resize it from either edge and it keeps that width. No
   clamping to the screen: a window against the screen's edge puts a
   right-bolted map off-screen, which is what the left option is for.
   *Alternative:* let the map be dragged to any offset and keep that offset —
   then it is not bolted, it is following.
4. **A bolted map is at its window's level.** Raising the log raises its map;
   another window in front of the log is in front of its map too. The
   floating level — the map over SmartSDR's panadapter — is the *floating*
   map's property and comes back the moment the map is set free. *Alternative:*
   keep the child floating. AppKit may not allow it (a child can be held at
   its parent's level), and it would leave log A's map over log B.
5. **Setting the map free leaves it where it is.** No remembered floating
   position to restore; the map is simply no longer fastened. *Alternative:*
   restore the last free position — a second autosaved frame, and a map that
   jumps when the operator only wanted it loose.
6. **⇧⌘B bolts and unbolts** (Article 7). When bolting with the map closed
   or hidden, it opens the map too — a bolt with nothing on it is not a
   result. This changes one pinned fact: ⇧⌘B used to be ⌘B (the gate ignored
   ⇧ on the B chord), and `testShiftDoesNotDisturbOtherCommandChords` is
   amended to say so. *Alternative:* a menu item — but the App's `.commands`
   must not read `AppSettings.shared` at launch (2026-08-15), so a menu
   toggle with a checkmark is not available, and a menu button with no state
   is worse than the key.
7. **The option lives in the band map's own popover**, in a new **WINDOW**
   section beside the label size: a *Bolt to the log window* toggle wearing
   the ⇧⌘B hint, and a Left / Right segmented picker, enabled while bolted.
   Like the label size, it is outside **Reset All**, which is about filters.
8. **App-wide, not per log.** The operator is bolting *all* his maps. The
   side, too. *Alternative:* per-document in the `.qplog` — a window
   preference saved into a contest log that may be opened on another Mac.

## Design

### Core — the geometry

`Sources/Core/Spotting/BandMapBolt.swift`, Foundation only, beside
`BandMapScale` and `SpotLabelSize`:

```swift
enum BandMapBolt {
    enum Side: String, CaseIterable, Identifiable, Sendable { case left, right }
    /// Between the window's edge and the map's.
    static let gap: CGFloat = 8
    /// Where a map of `panelWidth` goes when bolted to `side` of a window
    /// whose frame is `host`: flush against that edge, top-aligned, the
    /// window's height — or `minimumHeight` if the window is shorter than
    /// the map may be.
    static func frame(host: CGRect, side: Side, panelWidth: CGFloat, minimumHeight: CGFloat) -> CGRect
}
```

Both rectangles are window *frames* in screen coordinates, title bars
included, so the two title bars line up.

### UI — the attachment

`Sources/UI/BandMapBoltAttachment.swift`: `BandMapBolt.Attachment`, a
`@MainActor final class` owning the panel's relationship to its host window.
One per open band map, created with the panel in `toggleBandMap`.

```swift
init(panel: NSPanel, host: NSWindow)
/// The setting, applied: attach and pin, or detach — idempotent.
func apply(bolted: Bool, side: BandMapBolt.Side)
func show()   // orderFront, then attach if bolted
func hide()   // detach, then orderOut
func close()  // detach, stop observing, close the panel
func pin()    // setFrame to BandMapBolt.frame — only if it differs
var isAttached: Bool { get }
```

- **Attach** = `host.addChildWindow(panel, ordered: .above)`, `panel.level =
  host.level`, `pin()`. Only while the panel is visible — a child window is
  ordered in with its parent, so a hidden map must not be a child.
- **Detach** = `host.removeChildWindow(panel)`, `panel.level = .floating`.
- **Observing**: `NSWindow.didMoveNotification` and `didResizeNotification`
  on the host, `didMoveNotification` on the panel — every one calls `pin()`
  while attached. `pin()` compares before it sets, so the notification the
  set itself posts finds nothing to do; there is no loop.
- The panel's own resize is not observed (Decision 3): during a live resize
  from the left edge, snapping the origin back on every event would fight the
  drag. The window's next move or resize re-pins the height.

### MainView

- `@State private var bandMapBolt: BandMapBolt.Attachment?`, created beside
  the panel in `toggleBandMap`; `toggleBandMap` shows and hides through it.
- `applyBandMapBolt()` reads the two settings into `apply(bolted:side:)`.
- A new opaque seam, `leftPaneBoltWired`, between `leftPaneSpotWired` and
  `leftPaneTuningWired`, carrying the two `.onChange`s — the pane's
  `onChange` chains are at the type-checker's budget
  (`mainview-leftpane-typechecker-budget`), and nothing is added inline.
- `perform(.toggleBandMapBolt)`: flip `settings.bandMapBolted`; when that
  bolts and the map is closed or hidden, show it.
- `onDisappear`: `bandMapBolt?.close()` where the panel was closed.

### The gate and the hints

`KeyMonitorGate.Action.toggleBandMapBolt`; `commandAction` maps key 11 with
⇧ to it, without ⇧ to `.toggleBandMap` as before. `isShortcut` is unchanged
— every ⌘ chord is a shortcut, so ⇧⌘B during a repeating CQ leaves the loop
alone. `KeyDiagnostics.describe` names it "band map bolt".
`ShortcutLegend.items` gains `⇧⌘B — bolt the band map`.

### Settings

```swift
/// Whether the band map is fastened to the side of its log window, or
/// floats free. Machine-level, like the label size: the operator is
/// bolting all of his maps, in every log.
var bandMapBolted: Bool              // key "bandMapBolted", default false
var bandMapBoltSide: BandMapBolt.Side  // key "bandMapBoltSide", default .right
```

An unrecognised stored side token falls back to `.right` rather than to
nothing — the `spotLabelSize` rule.

### What does not change

`BandMapPanel.make` — the first-open placement and the shared autosave name —
the `BandMapView` body, the `BandMapModel`, spot handling, the key gate's
focus rules (the panel keeps its window number, child or not), and
`hidesOnDeactivate = false`. Nothing under `Sources/Hardware/` or
`Sources/Core/` outside the new file.

## Tests

- `Tests/Core/BandMapBoltTests.swift` — the geometry: right and left
  placement, top alignment, height follows the window, the minimum height
  wins over a short window, the width is kept.
- `Tests/App/BandMapBoltPreferenceTests.swift` — the two settings: defaults,
  persistence under their keys, read back, an unrecognised side token, no
  leak into the app-wide store (the `SpotLabelSizePreferenceTests` shape).
- `Tests/UI/BandMapBoltAttachmentTests.swift` — the AppKit relationship, on
  real windows in the hosted test bundle, which needs no active app for
  window bookkeeping: bolting makes the panel a child at the host's level
  and at the computed frame; moving the host moves the map; dragging the
  map snaps it back; resizing the host re-pins the height; the width
  survives a pin; setting it free removes the child and restores the
  floating level, leaving the frame alone; hiding detaches, showing
  re-attaches; bolting a hidden map attaches nothing until it is shown.
- `KeyMonitorGateTests` — ⇧⌘B is `.toggleBandMapBolt`, ⌘B still
  `.toggleBandMap`, ⇧⌘B is a shortcut during a repeat; the "⇧ does not
  disturb" test amended. `ShortcutHintsTests` — the legend names ⇧⌘B;
  `describe` names the bolt.

## Docs

README: the keyboard table row for ⇧⌘B; *Spotting and the band map* — a
bullet for bolting, and the sentence promising the map stays on screen over
other apps qualified with "floating"; the test count. This spec's as-built
note.

## Commit sequence

1. `docs: design for a band map bolted to its log window` — this file.
2. `bandmap: bolt the map to the side of its log window (⇧⌘B)` — the
   geometry, the attachment, the settings, the gate, the view, the tests,
   README, and this spec's as-built note.

## Open questions

- Not exercised by the suite, and unverifiable without a screen: what the
  bolted pair does when the log window is minimised, sent to another Space,
  or taken full screen. AppKit's documented behaviour is that a child window
  follows its parent in each case; the full-screen case may leave the map
  off the edge of the full-screen window, and setting it free is the remedy.
- The shared autosave name `"BandMapPanel"` is left alone. A bolted map's
  frame is recorded under it like any other, which only matters to the
  first-open placement of a *floating* map — the problem this option exists
  to replace, not to fix in passing.

## As built — 2026-08-22

Landed on `claude/bolted-band-map` in the two commits above, on top of
`e7cc12b`.

**Suite: 3077 → 3105, 0 failures** (2 skipped, as before). The tests went in
first: the test target failed to build on `cannot find type 'BandMapBolt' in
scope` and on nothing else. Then the geometry, the attachment, the settings,
the gate and the view; the five suites the change touches passed on their
first run — 86 tests, the 14 on real windows among them — and then the whole
suite: `Executed 3105 tests, with 2 tests skipped and 0 failures`.

Worth recording:

1. **The AppKit the design rests on held on the first run.** `NSWindow` posts
   `didMove` and `didResize` synchronously from the call that moved it, so a
   host moved with `setFrameOrigin` has its map re-pinned before the call
   returns; a child's level can be set to its parent's; and `addChildWindow`
   on a visible parent orders the child in — which is why `hide()` detaches
   before it orders out.
2. **The view's diff is the attachment's API and one seam.** Nothing was added
   to an existing `onChange` chain; `leftPaneBoltWired` sits between the spot
   and tuning halves. `BandMapPanel.make` is untouched.
3. **⇧⌘B was ⌘B.** The gate ignored ⇧ on the B chord, and
   `testShiftDoesNotDisturbOtherCommandChords` said so; it now says otherwise,
   with the bolt's own test beside it.

**Not yet seen on a screen.** The Release build is staged for the operator:
the look of the bolted pair, the popover's Window section, ⇧⌘B from the
entry field, and the three cases under *Open questions*.

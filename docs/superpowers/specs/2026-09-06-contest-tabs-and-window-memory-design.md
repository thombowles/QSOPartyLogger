# Contests in tabs, and windows that remember themselves — design

**Date:** 2026-09-06
**Status:** built the same day from the operator's request; the choices under
*Decisions* are his to overturn, and each names the alternative
**Kind:** app-layer window behaviour — no party, no radio, no schema. One
commit, the full suite green before and after
**Origin:** the operator, 2026-09-06, three improvements: "make multiple
contests open in tabs within the app, not separate windows"; "make the window
position and size always stay the same after re-opens"; "remember if the band
map was turned on and the band map position across re-opens"

## Why

Every open log is its own `DocumentGroup` window, placed by SwiftUI at the
default 1280 × 800 and cascaded from the last one. Nothing about the window is
remembered between runs: the frame the operator dragged it to, whether the
band map was up, and — only by AppKit's frame autosave, which two windows fight
over — where the map was. Two contests on one weekend means two windows to
keep straight, which is what the bolted band map was for; the operator now
wants them as tabs of one window.

## Approaches considered

### Tabs

1. **AppKit window tabbing, asked for by the log window.** Every log window is
   marked `tabbingMode = .preferred` under one `tabbingIdentifier`; a window
   that arrives untabbed (SwiftUI shows it before our accessor runs) is added
   to the front log window's tab group by hand. The tab bar, ⌃Tab / ⌃⇧Tab, the
   Window menu's tab items and drag-out-to-a-window are AppKit's, free.
   **Chosen**: it is the native mechanism, each contest keeps its own
   `NSWindow` — so the key monitor, the shared radio's window count, sheets
   and the bolted band map all keep working per window unchanged.
2. **A tab bar drawn by the app inside one window** holding several documents.
   Every per-window mechanism above would have to be re-done per tab, and
   `DocumentGroup` gives one document per window — it would mean leaving the
   document architecture. Far more work for a worse imitation of the system's
   tabs.

### Window frame

1. **Remember the frame in the app's preferences** — saved on every move and
   resize, restored when a log window opens alone (a window opening into a tab
   group takes the group's frame). **Chosen**: one frame for every log window,
   explicit, testable, and on a screen that no longer exists it is ignored
   rather than restored off-screen.
2. **AppKit frame autosave (`setFrameAutosaveName`).** One name serves one
   window; the second tab's call fails silently and stops saving. It also
   restores at a time SwiftUI may still be placing the window.

### Band map

1. **`bandMapShown` and `bandMapFrame` in preferences**, next to the bolt
   settings. Shown is set by ⌘B and cleared by ⌘B or the panel's close button;
   the frame is saved on every move and resize of the panel. A log window that
   opens with `bandMapShown` on opens its map at the saved frame (or pinned to
   its side, if bolted). **Chosen** for the same reasons as the window frame,
   and it retires the shared autosave name the bolt design already noted as a
   problem.

## Design

### Tabs — `LogWindowTabs`

`Sources/UI/LogWindowTabs.swift`: a namespace with the identifier
(`"org.b5n.QSOPartyLogger.log"`), `configure(_:)` (sets the mode and the
identifier), and `join(_:among:)` — if the window has no tab siblings, it is
added to the first other *visible* log window's tab group, `ordered: .above`,
and becomes the selected tab. Called from the log window's `WindowAccessor`
once per window. The dashboard window is `tabbingMode = .disallowed`, so it
never lands in the log group.

### Frame memory — `WindowFrameMemory`

`Sources/UI/WindowFrameMemory.swift`: made for a window with a saved frame
and a `save` closure. `placement(saved:screens:)` is pure: the saved frame if
it intersects any screen's visible frame, else nil. On creation it restores
that placement if the window has no tab siblings; then it observes
`didMove` / `didResize` on the window and hands each new frame to `save`.
`AppSettings.logWindowFrame: CGRect?` (stored as `NSStringFromRect`) is the
store.

### Band map memory

- `AppSettings.bandMapShown: Bool` (default false) and `bandMapFrame: CGRect?`.
- `BandMapPanel.make(model:near:frame:)` takes the saved frame instead of an
  autosave name, docks right of the window when there is none or it is
  off-screen.
- `BandMapBolt.Attachment` gains `onFrameChanged` (panel move and resize) and
  `onClosedByOperator` (the panel's close button — `willClose` while the
  attachment is alive; `close()` removes the observer first so a window
  closing does not read as the operator closing the map).
- `MainView` sets `bandMapShown` in `showBandMap` / `toggleBandMap`, saves the
  frame from `onFrameChanged`, and restores an open map when both the model
  and the host window exist (`restoreBandMapIfWanted`, called from the
  accessor and from `onAppear`, idempotent). Every window follows the
  setting (`onChange(of: settings.bandMapShown)`), so ⌘B in one tab is ⌘B in
  every tab — the bolt's semantics.

### Tabs and the map

A tab that is not selected is ordered out; a floating map must go with it, or
every tab's map stacks up on screen. The attachment watches the host's
`didBecomeMain`, `didResignMain`, `didMiniaturize`, `didDeminiaturize` and
`didChangeOcclusionState`, and `sync()`s: the panel is on screen exactly when
the operator wants it (`show()` / `hide()`) *and* the host `isVisible`. The
bolted map already follows as a child; the same sync covers it, detaching
while hidden so the parent cannot bring it back on its own.

## Decisions

1. **Tabs, always.** `.preferred` overrides the system's "prefer tabs" setting
   for log windows. *Alternative:* `.automatic`, which leaves the choice to
   System Settings — the operator asked for tabs, not for a setting.
2. **One remembered frame for all log windows**, not one per document: a
   window is where the operator works, whichever log is in it.
3. **`bandMapShown` is machine-level**, like `bandMapBolted`: with two tabs
   open the operator is showing his maps, not one. Each tab opens its own map
   when it is the selected tab; only the selected tab's map is on screen.
4. **A saved frame that is off every screen is ignored**, for the window and
   for the map alike — a laptop unplugged from its monitor opens where the
   system puts it, not off-screen.
5. **The dashboard stays a window**, never a tab of the logs.

## Follow-ups from the first look, 2026-09-07

The operator ran the build and asked for eight more things; each is in the
same branch, one commit per group, with the same rule — a claim is a test.

1. **The window opened centred, then jumped to its frame.** The memory
   restores once the window exists — after SwiftUI has shown it.
   `DocumentGroup.defaultWindowPlacement` decides *before*, for restored
   windows too (the unified log showed the closure called for each), so
   `LogWindowPlacement` converts the saved frame into SwiftUI's space: the
   primary display's flipped coordinates (origin top-left, y down — the menu
   bar puts the visible rect at y 30), position the window frame's top-left,
   size the frame's own, chrome included — calibrated by placing at
   {300, 396, 1200 × 648} and reading the frame back as {300, 252, 1200 × 648}
   on a 1296-point display. The memory logs (`window` category) where the
   window was placed and whether it had to correct — the line that tells a
   jump the operator saw from one the app made.
2. **Every tab's map at one size and position.** The attachment takes the
   shared frame (`bandMapFrame`) on every show; bolted, the pin decides the
   position and the shared width stands.
3. **The map says whose it is.** `LogDocument.contestShortLabel` — the
   party's id in capitals, or the park for a POTA activation — in the
   panel's title (`KSQP — Band Map`, contest first so a narrow title bar
   keeps it) and in the header.
4. **The header folds.** `BandMapHeader`: band, VFO and contest on one line
   with the span and the funnel where the panel is wide enough (about 270),
   two lines where it is not (the narrowest panel is 230).
5. **Right-click on an F-key opens the editor at once.** `RightClickCatcher`,
   an overlay that claims only the right button (and ⌃-click) in `hitTest`,
   so a left click still sends. The context menu is gone.
6. **Settings in three pages.** `BandMapSettingsPopover` — Spots, Tuning,
   Window — each with its own reset, the page remembered. The popover was
   taller than the screen left room for below the funnel.
7. **The map is an ordinary window.** `level = .normal`, free or bolted:
   behind another app's window when that is in front, forward with the
   app, never floating over everything.
8. **A contest worked from a park is an outing too.** The dashboard's POTA
   cards and list read every record that activates a park as well as the
   program records; `PotaSeason` counts a party record's park contacts only
   (the hour before the park was set is the contest's alone), and the list
   names the contest beside the park. The record stays a contest entry.
9. **Contest Setup in the middle of the screen.** A sheet hangs from its
   window, and a window against the bottom of the display pushed the sheet's
   Save button off the screen. `CenteredDialog` presents the same view in an
   app-modal window centred on the log's screen — sheet-like (no title bar
   to see, no buttons, not resizable, draggable), Esc and Return reaching
   its own buttons, and the key monitor treating `NSApp.modalWindow` as it
   treats a sheet. `SetupSheet` closes through a closure it is handed,
   since the environment's `dismiss` closes only a sheet.
10. **Park names and states in the POTA list.** The dashboard reads the
   downloaded park list (the cache Contest Setup's POTA section fills) off
   the main actor on every refresh, and a "Park name" column shows each
   park as `Cedar Hill State Park · TX` (`PotaPark.nameAndState`; a park
   spanning states shows them all). Before the list is downloaded the column
   says so on hover.

## Testing

- `LogWindowTabsTests` (UI): configure sets mode and identifier; a second
  window joins the first's group and is selected; a window with no siblings
  is left alone; a hidden or foreign window is not a candidate.
- `WindowFrameMemoryTests` (UI): placement on/off screen; restore applied
  to a lone window and skipped for a tabbed one; moves and resizes are saved.
- `BandMapBoltAttachmentTests` (UI): frame changes reported; close button
  reported, a programmatic close not; a hidden host hides the map and a
  re-shown host brings it back, re-pinned.
- `WindowMemoryPreferenceTests` (App): defaults, persistence and the
  unreadable-frame fallback for the three new keys.
- `BandMapPanelPlacementTests` (UI): the saved frame is used; none or
  off-screen docks right of the window.

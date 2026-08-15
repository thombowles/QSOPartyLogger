# F-key diagnosis, shortcut hints, VFO nudge — design

Date: 2026-08-15 (during NAQP SSB). Three requests from Tom, in his words:

1. "the f-keys are not working for phone. I can press the button but f-keys
   do nothing"
2. "add a helper mode that shows the shortcuts for all the buttons"
3. "make shift-cmd-left/right move the vfo up or down 100Hz"

Written without Tom in the room; every choice below is reversible in one
place and named as a choice.

## 1. Phone F-keys — what the investigation found

**The app's F-key path is sound.** The row button and the F-key converge on
`MainView.sendMessageAt` → `EntryFlow.transmission` → `RadioController.playRecording`;
nothing after the key monitor is phone-specific. A harness compiled against
the real `KeyMonitorGate` (scratchpad `fkeyprobe`, launched as a real `.app`
via `open -W`) posted F1 through a MainView-style local monitor: it reached
`.sendMessage(0)` and was consumed before a SwiftUI sheet, was refused with
`.sheet` while the sheet was up (by design), and reached `.sendMessage(0)`
again after the sheet was dismissed. WindowServer's routing log shows keyboard
events reaching the live process, and the live log
(`2026-08-15 NAQPSSB KE5CW.qplog`, 19 QSOs) has recordings for every mapped
memory — the row buttons play them.

**What is left is upstream of the app.** The keyboard is a Keychron K17 Max
(IOKit). On Keychron boards the F row is multimedia by default in Mac mode
(brightness, Mission Control, …; F5/F6 drive the key backlight and send
nothing) and `fn`+`X`+`L` held 4 s locks it to F1–F12 — Keychron support,
"I am using a macOS, how can I make the F1-F12 function keys default…"
(zendesk article 6288101840151, fetched 2026-08-15). macOS's own
"standard function keys" switch (`com.apple.keyboard.fnState`, set to 1 on
this Mac) governs Apple keyboards, not third-party firmware. That would
give exactly "buttons work, F-keys do nothing", on CW as much as phone.

This is a hypothesis, not a proven cause. So the app changes are the ones
that make the *next* press self-diagnosing:

- **Key trace.** Every key the monitor decides on is logged through
  `os.Logger` (subsystem `org.b5n.QSOPartyLogger`, category `keys`): key
  code, modifiers, focus, action, consumed. Media keys (`.systemDefined`
  subtype 8) are logged too, decoded to their name. Read with
  `log show --predicate 'subsystem == "org.b5n.QSOPartyLogger"' --last 10m`.
- **Inline notice.** When a *media* key arrives while a contest window has
  the keyboard, the messages row shows one line — "F1 arrived as Brightness ▼:
  the keyboard's F row is in multimedia mode …" — with the fix for Keychron and
  Apple keyboards. It clears the moment a real function key arrives. Inline,
  not modal (Tom's rule).
- **Last-key readout** in the shortcut hints legend (below), so the operator can
  press a key and read what the app received.

Nothing maps media keys onto messages: F1/F2/F7/F8 would half-work and F3–F6
never could. A half-working F row is worse than a clear diagnosis.

## 2. Shortcut hints (helper mode) — ⌘/

- `AppSettings.showShortcutHints` (UserDefaults `showShortcutHints`, default
  off). Global, like the advisor goal: a preference about the operator, not
  a log.
- **Toggle:** ⌘/ through `KeyMonitorGate` (`.toggleShortcutHints`, keyCode 44
  with ⌘), plus **Help › Keyboard Shortcuts** in the menu bar (the same
  toggle, so it works from the dashboard too and is discoverable). ⌘/ is
  free: ⌘? is macOS's Help-menu search.
- **Badges.** A `.shortcutHint("⌘B")` modifier overlays a small keycap capsule
  on a control while hints are on. Applied to every control that has a key:
  toolbar Export (⌘E · ⇧⌘E), Spot (⇧⌘S), Messages (⇧⌘V phone tab), Band Map
  (⌘B); messages row Run/S&P (⌘R), CQ chip (⌘J); Log button (⏎); radio bar
  WPM (⌘= ⌘-), Esc; sidebar expand-all (⇧⌘M), Advisor collapse (⇧⌘A) and
  goal (⌥⌘A). F1–F8 already carry their key in the button label.
- **Legend strip** under the messages row while hints are on, for keys with
  no button: F12 clear · Esc abort · ⌘↑ ⌘↓ spots · ⌘J CQ · ⌘= ⌘- WPM ·
  ⇧⌘← ⇧⌘→ VFO ±100 Hz · ⌘A select all · ⌘/ hide — followed by the last-key
  readout.
- Controls with no shortcut (ESM, Repeat CQ, Setup…, iCloud, Spots) get no
  badge; hints show what exists rather than inventing chords.

## 3. VFO nudge — ⇧⌘← / ⇧⌘→

- `KeyMonitorGate`: keyCode 123/124 with ⌘ and ⇧ → `.nudgeVFO(byHz: -100/+100)`.
  Plain ⌘←/⌘→ stay with the text field (line start/end), as before. The
  shifted pair was macOS's "select to line start/end" in the entry fields;
  the operator asked for it by name, and there is nothing to select to in a
  callsign field worth a chord.
- `RadioController.nudgeFrequency(byHz:)`: absolute set from a base
  frequency. The base is the last nudge target when one was issued within
  the last 1.5 s (a poll in flight would otherwise undo the second of two
  quick presses), else the polled frequency. Pure `nudgeBase(...)` is
  tested; the driver call is `setFrequency(hz:)`.
- Disconnected: the band-map cursor moves 0.1 kHz instead, so the key does
  the same thing to the only VFO the app has.
- The band map's spot cursor follows the nudge, so ⌘↑/⌘↓ step from where the
  radio now is.

## Files

| Path | Change |
| --- | --- |
| `Sources/UI/KeyMonitorGate.swift` | `.toggleShortcutHints`, `.nudgeVFO(byHz:)` |
| `Sources/UI/KeyDiagnostics.swift` | new: media-key decoding, trace lines, F-row notice text |
| `Sources/UI/ShortcutHint.swift` | new: the badge modifier and the legend |
| `Sources/UI/MainView.swift` | monitor logs and records keys; systemDefined monitor; notice; legend; nudge |
| `Sources/UI/MessagesRow.swift`, `RadioBar.swift`, `EntryBar.swift`, `ScoreSidebar.swift`, `AdvisorSection.swift` | badges |
| `Sources/App/AppSettings.swift` | `showShortcutHints` |
| `Sources/App/RadioController.swift` | `nudgeFrequency(byHz:)`, `nudgeBase` |
| `Sources/App/QSOPartyLoggerApp.swift` | Help › Keyboard Shortcuts |
| `README.md` | keyboard table, features, F-row troubleshooting, test count |

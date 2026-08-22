# One radio connection, shared by every log window — design

**Date:** 2026-08-22
**Status:** built the same day from the operator's report; the policy choices
under *Decisions* are his to overturn, and each names the alternative
**Kind:** app-layer lifetime change — no party, no radio, no schema. Article 4's
quarantine applies: its own commit, the full suite green before and after
**Origin:** [`2026-08-22-kx2-support-design.md`](2026-08-22-kx2-support-design.md),
*Deferred — real, found here, not fixed here*, item 2

## Why

`MainView` declared `@State private var radio = RadioController()` inside a
`DocumentGroup` scene, so every open log window constructed its own
`RadioController`, and each one auto-connected to the same port when it opened.

Confirmed on the operator's Mac on 2026-08-22: `lsof` showed two file
descriptors open on `/dev/cu.usbserial-FTELBR55`, both with non-zero read
offsets — two drivers polling one port, each `read()` stealing bytes the other
needed, so CAT responses were split between two parsers. It looks like a flaky
cable, and it gets worse with more windows. The operator runs two or more log
windows routinely, so this is the normal configuration, not a stray window.

A serial port is one stream of bytes; two readers on it cannot both see every
response. The radio is the app's, not any window's, and the app must hold
exactly one connection to it.

## Approaches considered

1. **One `RadioController` for the app, held the way `AppSettings.shared` is.**
   `@MainActor static let shared`, lazy, built when the first log window
   appears; every `MainView` holds it as `@State private var radio =
   RadioController.shared`, exactly as it already holds `settings`. The state
   that belongs to one log stays in the window. **Chosen** — it is the idiom
   the app already has, the diff in the view is one line, and nothing new
   happens at launch.
2. **Inject through the SwiftUI environment from the `App`.** The same one
   instance, but built in the `App` body at launch and passed down with
   `.environment(_:)`. It moves construction — and IOKit port enumeration — to
   app launch for no gain, it is a second idiom beside the one the app uses,
   and the lesson of 2026-08-15 (`PreferenceIsolationTests`) is that
   launch-time scene state is where the hosted test bundle is most fragile.
   Nothing in it is better than 1.
3. **Keep one controller per window and share the transport underneath.** A
   pool keyed by port path, each window's controller a client of it. Every
   observable the radio feeds — `radioState`, `nowSending`, `voiceStatus`,
   `lastError` — would then need fanning out to N controllers, and the keyers
   and the voice player, which must be one per radio, would need the same
   treatment. Much more code for the same effect as 1.

## Decisions

1. **`RadioController.shared`**, lazy, built by the first window. `init()` stays
   internal: thirty-six tests construct their own controller and must keep
   doing so — one shared across tests would couple them through its state.
2. **The connection comes down when the last log window closes, and not
   before.** Closing one window while another is still logging leaves the
   radio alone. Today's single-window behaviour — close the log, release the
   port — is unchanged. *Alternative:* hold the port until the app quits. That
   leaves a radio being polled twice a second with no window showing it, and a
   port no other program can open.
3. **A new window auto-connects only when nothing is connected.** `autoConnect`
   already guards on `isConnected`; a second window opening onto a live link is
   a no-op. The README's promise — "Opening a contest file reconnects the last
   radio you used" — still holds for the case it was written for, an app with
   no radio up. It follows that a log opened *after* the operator pressed
   Disconnect reconnects, as it does today. *Alternative:* a sticky "the
   operator chose disconnected" state, cleared by Connect. New machinery for a
   case nobody has asked for.
4. **A transmission belongs to the radio, not to the window that sent it.**
   Closing a window mid-message no longer aborts the message while another
   window remains: that window's bar shows the badge, and its Esc stops it.
   The closing window's own repeat-CQ loop stops with it, as now
   (`pauseRepeat` in `onDisappear`).
5. **Port enumeration becomes injectable**, the way `resolveOutputDevice` and
   `makeVoicePlayer` already are. Not for the feature — for its proof.
   `autoConnect` acts only on a port `SerialPortEnumerator.availablePorts()`
   lists, which only IOKit answers, so the one rule this change turns on —
   *must not reconnect an already-connected radio* — was unprovable without an
   adapter on the desk. So was the positive case.

## Design

### What is the app's, and what is the window's

| Global — on `RadioController.shared` | Per window — stays in `MainView` |
| --- | --- |
| transport, driver, the one keyer, voice driver, streamer, transmit control, voice player | `EntryFlow`, the entry row, focus |
| `isConnected`, `connectionPhase`, `lastError`, the validation clock | `repeatCQ`, `repeatTask` |
| `radioState` — frequency, mode, TX — and `radioReportedWPM` | `BandMapModel` and its panel, reading the shared `radioState` |
| the `nowSending` badge, `isTransmitting` | `cqFrequencyHz`, `cqZone`, `manualBand`, `manualRawMode` |
| `voiceStatus`, `voiceBank`, `isVoicePlaying`, `voicePathStatus`, `voiceLog` | `VoiceStore` — the party's recordings — and the messages editor |
| `availablePorts` | spot clients, `SpotStore`, the dispatcher, call history, SCP |
| `attachedWindows` | key monitors, `hostWindow` |

The rule: a fact about the radio or the link is global; a fact about one log,
or one operator's view of it, is per window. Every observer in `MainView` —
`onChange(of: radio.radioState?.band)`, `…frequencyHz`, `…radioReportedWPM`,
`…isConnected` — is a per-window reaction to a shared fact and needs no
change: two windows each see the VFO move, each re-validate their own entry,
and each interrupt their own repeat loop on a disconnect. `refreshVoicePath`
and `syncSpeedFromRadio` run once per window when a setting changes; both are
idempotent.

### Lifetime

```swift
/// How many log windows are showing this connection. The connection is the
/// app's, not any one window's: the first window brings it up, and it comes
/// down with the last — never because *a* window closed while another was
/// still logging on it.
private(set) var attachedWindows = 0
func windowDidOpen()    // += 1
func windowDidClose()   // -= 1, floored at 0; disconnect() on reaching 0
```

`MainView.onAppear` calls `windowDidOpen()` and then `autoConnect(settings:)`;
`onDisappear` calls `windowDidClose()` where it called `disconnect()`. A stray
close with no matching open cannot drive the count negative — that would make
the next real close leave the port held with nothing showing it.

### The bar, in every window

Connect, Cancel and Disconnect act on the app's radio; every window's bar shows
the same phase, frequency, badge and error because they read the same object.
`clearError()` from any window clears it for all — it is one error about one
link.

### What does not change

`connect`, `disconnect`, `startValidation` (Article 14), both keying paths,
both voice paths, every driver. Nothing under `Sources/Hardware/`. No model
name enters `Sources/App/` or `Sources/UI/` — the Article 10 grep runs before
the commit.

## Tests

`Tests/App/RadioControllerSharedConnectionTests.swift`, over `/dev/null` as
the silent serial port, like `RadioControllerConnectionTests`; the port list
is injected so `autoConnect` can see it:

- **Auto-connect with the configured port present connects** — the positive
  case, previously unprovable without hardware.
- **Auto-connect leaves an already-connected radio alone**: connect, wait for
  `.unresponsive`, auto-connect again → still `.unresponsive` with its error
  intact. Then `connect()` — the bar's button — as the control: it *does*
  rebuild to `.waitingForRadio`, so the assertion is one that can fail.
- **Closing one window keeps the connection for the others**: two opens, one
  close → still connected; the second close → disconnected, clean slate.
- **A stray close never drives the count negative**: close on a fresh
  controller, then open, connect, close → disconnected.

## Docs

README, *Connecting*: the connection is the app's; a second log window shares
it; the port is released when the last window closes. The test count. The KX2
spec's deferred item 2 gains a pointer here.

## Commit sequence

1. `docs: design for one radio connection shared by every log window` — this
   file.
2. `radio: one connection for the app, shared by every log window` — the
   controller, `MainView`, the tests, README, the KX2 spec's pointer, and this
   spec's as-built note.

## Open questions

- The proof here is the suite; nobody has yet opened two log windows on the
  operator's Mac with this build. The check on the air is
  `lsof /dev/cu.usbserial-*` with two logs open: one descriptor, not two.

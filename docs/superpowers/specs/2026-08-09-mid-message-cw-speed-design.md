# Mid-message CW speed — design

**Date:** 2026-08-09
**Status:** approved

## The problem

`⌘=` / `⌘-` during a transmission does nothing. The speed lands on the *next*
message.

[`CWKeyer.transmit`](../../../Sources/Hardware/Keying/CWKeyer.swift) reads the
speed once, at the top of the message, and hands it to
`KeyerTiming.schedule(text:wpm:)`, which bakes it into a list of millisecond
durations:

```swift
let (currentConfig, speed) = lock.withLock { (config, _wpm) }
let events = KeyerTiming.schedule(text: text, wpm: speed)
```

`CWKeyer.wpm` is therefore write-only for the duration of a message. A schedule
denominated in milliseconds cannot express "and then it got faster".

## Why the radio can't do it for us

On the direct path the radio is not generating CW at all. The QMX operating
manual, CW menu:

> "Keying via the DTR signal works in straight-key mode independently of the
> main keyer. Therefore the QMX keyer can be in Iambic paddle mode, but the DTR
> signal will key separately as a straight key"

The DTR line is a straight key input. `KS` retargets the radio's *own* keyer —
paddles, front panel, `KY` buffer — and has no bearing on our edges. The shape
of those edges *is* the speed, and the app owns it. There is nothing for the
radio to sort out.

## Decisions

### Direct keying is the only CW path where control lines exist

Previously Article 11 required both paths implemented wherever both existed,
selectable by an operator preference. That preference is withdrawn. A radio
either has control lines (direct keying, app-timed) or it does not (its own
keyer, radio-timed). Never both.

The payoff is that mid-message speed change stops being a per-model firmware
question and becomes a property the app guarantees on every serial radio, with
one code path and one test.

**Accepted cost, recorded here so it is not a surprise later:** a QMX ships with
`Key from USB DTR: None` and needs a menu set before it will key, and keying is
open-loop — the radio never reports that a line we toggle is ignored. An
operator in that state now has silent dead-air with no in-app fallback. The
README's wiring instructions become load-bearing rather than advisory.

Consequences: every radio now offers exactly one CW path, so the keyer picker
has nothing to choose between. `AppSettings.KeyerBackend`,
`RadioDescriptor.keyerLabel` and `RadioBar.keyerGroup` all go.

### A speed change lands at the next element, never mid-element

A key-down element in flight finishes at the speed it began — no dit or dah is
ever stretched or clipped. Key-up gaps re-read the speed every dit, so a change
lands within one dit of the old speed. Worst case latency is one dah.

Rejected: continuous re-read (distorts an element on air) and next-character
(over a second of lag at 8 WPM).

## Design

### 1. `KeyerTiming` — schedules stop mentioning speed

```swift
struct KeyEvent: Equatable { let keyDown: Bool; let dits: Double }

static func schedule(text: String) -> [KeyEvent]              // no wpm
static func durationMs(_ events: [KeyEvent], wpm: Int) -> Double
static func totalDurationMs(text: String, wpm: Int) -> Double  // kept for estimates
```

A schedule that cannot name a speed cannot stale-bind one. `ditMs(wpm:)` stays
as the single conversion point.

### 2. `CWKeyer` re-reads the speed per element

```swift
transport?.set(line: currentConfig.keyLine, active: event.keyDown)
// A dit or dah in flight finishes at the speed it began — never distorted.
// Gaps re-read, so a speed change lands within one dit of the old speed.
let slice = event.keyDown ? event.dits : 1.0
var remaining = event.dits
while remaining > 0, !isAborted() {
    let step = min(remaining, slice)
    deadline += UInt64(step * KeyerTiming.ditMs(wpm: currentWPM()) * 1_000_000)
    sleepUntil(uptimeNanos: deadline)
    remaining -= step
}
```

`deadline` still accumulates absolutely from one base, so slicing introduces no
drift.

### 3. Completion replaces the estimate on the direct path

`CWKeyer` gains `onFinished`, fired by the run loop when the queue drains.
`RadioController.sendCW` uses it to clear `nowSending` instead of a timer, so
the sending badge and the TX hold track the real transmission. The internal
path keeps the estimate — CWX exposes no completion signal the app subscribes
to.

### 4. The driver protocol splits

`sendInternalKeyerText` / `stopInternalKeyer` leave `RadioDriver` for a
narrower protocol:

```swift
protocol RadioDriver: AnyObject { /* universal members */ }

/// A radio with no control lines keys through its own keyer.
protocol InternalKeyerDriver: RadioDriver {
    func sendInternalKeyerText(_ text: String)
    func stopInternalKeyer()
}
```

Only `FlexRadioDriver` conforms. `RadioController` builds a
`RadioInternalKeyer` only when the driver does. This models the new rule in the
type system rather than leaving no-op stubs, which Article 13 forbids.

`setKeyerSpeed` stays on `RadioDriver` for every radio — bidirectional speed
sync (Article 11) is still wanted on K3 and QMX so the paddles and front-panel
display match the app.

### 5. Flex speed command corrected

`cmdKeyerSpeed` emits `cwx wpm N`. FlexRadio's own API documentation gives the
command as `cw wpm N`, on both the `TCPIP-cw` and `TCPIP-cwx` pages — every
other verb on the CWX page is `cwx …`, WPM alone is not. Setting speed on a
Flex has therefore never worked. Fixed to `cw wpm`.

### 6. `syncWPM` stops bypassing the internal keyer

`directKeyer?.wpm = wpm; internalKeyer?.wpm = wpm` — the setter already
forwards to `driver.setKeyerSpeed`, so the CAT command still goes out
immediately and `RadioInternalKeyer._wpm` stops going stale.

## Tests

| Test | Asserts |
| --- | --- |
| `KeyerTimingTests` | schedules in dit units; `durationMs` reproduces today's millisecond values |
| `CWKeyerTests` (new) | timestamped mock transport; speed raised mid-message ⇒ later elements measurably shorter, and every key-down element matches one speed exactly |
| `CWKeyerTests` (new) | `onFinished` fires once when the queue drains, and on abort |
| `RadioRegistryTests` | every descriptor is **exactly one** of direct-keying or `InternalKeyerDriver` — never both, never neither |
| `FlexRadioDriverTests` | emits `cw wpm 25` |
| `K3ProtocolTests` / `QMXProtocolTests` | `KS` bytes unchanged; no `KY` bytes are emitted by either driver |

`CWKeyerTests` is proved red against current `main` before the fix lands, so it
is a real regression test.

## Commits

1. Bank both protocol references + `PROVENANCE.md` — docs only, no behaviour
2. Keyer core (dit units, live speed, completion) + constitution + README
3. Drop `KY` from K3 and QMX, split the protocol, delete the keyer picker
4. Flex `cw wpm` fix

## Out of scope

The CWX documentation also specifies that `cwx send` needs spaces replaced with
`0x7F`; the driver sends literal spaces. That is a real defect but it concerns
message *content*, not speed, and folding it in would cost Article 9's
bisectability. Flagged separately.

The `cwx … wpm=` status format `parseCWXSpeed` reads appears nowhere in
FlexRadio's official API documentation — its status-responses page does not
mention `cwx` at all. The parser is unchanged here; the gap is recorded in
`PROVENANCE.md` rather than papered over.

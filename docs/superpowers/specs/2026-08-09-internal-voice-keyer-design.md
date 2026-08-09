# Internal voice keyer — design

**Date:** 2026-08-09
**Status:** approved
**Kind:** protocol widening (Article 4) + one radio's capability (Articles 10–14)
**Research:** [`docs/research/k3_voice_keyer.md`](../../research/k3_voice_keyer.md)

## Why

The app keys CW two ways and phone not at all. On a mixed-mode QSO party the
operator loses the keyboard the moment they switch to SSB: no F-keys, no ESM, no
repeat CQ, and the run is worked by voice alone for the rest of the weekend.
That breaks Article 7 in the one mode where a voice is most easily worn out.

The K3's recorder (KDVR3) can close the gap, and the reason to do it here rather
than copy the reference implementation is that **N1MM's team does not support
radio-internal voice keyers at all.** Their manual documents a hand-written
`{CAT1ASC …}` escape hatch with three stated costs: Esc may not interrupt, auto
CQ repeat must be hand-tuned because nothing signals the end of a message, and
PTT cannot be managed so such radios must use VOX.

All three are limits of a generic architecture, not of the K3. The Elecraft
documents close each one:

| N1MM gives up | K3 provides | Source |
| --- | --- | --- |
| Esc may not stop playback | `RX;` terminates message play and repeating messages | Pgmrs Ref G5, `RX` |
| No end-of-message signal | `IC;` byte a bit B2 = MSG is playing | Pgmrs Ref G5, Table 4 |
| Must use VOX | Playing a DVR transmit message asserts PTT automatically | Owner's Man D10, `CONFIG:KDVR3` |

Plus `OM;` reports whether the recorder is even fitted, so a missing module reads
as an inline explanation rather than a dead key.

## Shape of the feature

A **phone message set**, chosen automatically when the radio reports a voice
mode. Eight F-key positions per operating style, each holding a **label and an
optional recorder slot 1–4**. F-keys, ESM, Esc and repeat CQ behave exactly as
they do on CW. An unassigned key advances and logs but transmits nothing.

**Eight positions, four slots.** `ESM.againIndex` is 4 (F5), so a set of four
would leave ESM's "AGN?" step with nowhere to point. Decoupling the F-key
position from the slot number means **`ESM.swift` does not change at all** —
`nextAction` returns the same indexes in both modes.

**Four slots, bank 1, and `SWH37;` is never sent.** The K3 has eight buffers in
two banks, but the bank is shared with the operator's CW memories and switching
it leaves the radio wherever the app last put it. Nothing here emits a bank
command.

### Defaults

| | F1 | F2 | F3 | F4 | F5 | F6–F8 |
| --- | --- | --- | --- | --- | --- | --- |
| Run | CQ → 1 | Exch → 2 | TU → 3 | — | AGN? → 4 | — |
| S&P | — | Exch → 2 | TU → 3 | — | AGN? → 4 | — |

S&P F1 is deliberately unassigned: it is the "send my call" step, and a callsign
is faster spoken than recorded — and four recordings will not stretch to a fifth.
Return in the call field then does nothing on the air while the operator speaks,
which is the same thing an empty CW slot already does.

## Design

### `Sources/Hardware/Keying/VoiceKeyer.swift` (new)

```swift
/// What the connected radio can do about recorded voice messages. Runtime
/// rather than a `RadioDescriptor` flag, because on some radios the recorder is
/// an option that may not be fitted: the answer is asked for at connect and
/// reported, never declared.
enum VoiceKeyerStatus: Equatable, Sendable {
    /// This radio has no voice keyer the app can drive.
    case unsupported
    /// It has one, but the option module is not installed.
    case notInstalled
    /// Ready. Slots are numbered 1...slots.
    case available(slots: Int)

    var slotCount: Int { if case .available(let n) = self { n } else { 0 } }
    var isReady: Bool { slotCount > 0 }
}

/// A radio that can play its own recorded voice messages.
///
/// A separate protocol rather than four more `RadioDriver` members with no-op
/// defaults. Article 11 forbids stubbing out the *CW* keyer members because both
/// keying paths exist on every serial radio and the operator may prefer either.
/// A recorder is different in kind: a radio that has none has nothing to stub,
/// and an empty implementation would let it claim a capability by silence.
/// `RadioController` tests for conformance.
protocol VoiceMessageCapable: RadioDriver {
    /// Play the radio's own recording in `slot` (1-based).
    func playVoiceMessage(slot: Int)
    /// Stop playback immediately.
    func stopVoiceMessage()
    /// What the radio turned out to be able to do, once asked.
    var onVoiceKeyerStatusChange: (@Sendable (VoiceKeyerStatus) -> Void)? { get set }
    /// True while the radio reports a message actually playing — a real signal,
    /// not an estimate.
    var onVoicePlaybackChange: (@Sendable (Bool) -> Void)? { get set }
}
```

No `VoiceSender` class parallel to `RadioInternalKeyer`. That abstraction exists
because CW has two interchangeable backends; voice has one.

### `ElecraftK3Driver`

Conforms to `VoiceMessageCapable`. Header comment gains the Owner's Manual D10
citation alongside the existing Programmer's Reference F2/G5 (Article 12).

```swift
/// M1–M4 tap, from Table 7 of the Programmer's Reference. In a voice mode these
/// play the recorder's messages; in CW the same switches play CW text memories,
/// which is why `RadioController` gates playback on the reported mode.
static let cmdPlayVoiceMessage = [1: "SWT21;", 2: "SWT31;", 3: "SWT35;", 4: "SWT39;"]

/// Documented to terminate transmit in all modes, message play included.
static let cmdStopVoiceMessage = "RX;"

static let cmdPollOptions = "OM;"
static let cmdPollIcons = "IC;"
```

- `OM;` is parsed by `static func parseOM(_:) -> VoiceKeyerStatus`: trailing
  `01`/`02` in the 12-character field means KX2/KX3 → `.unsupported`; otherwise
  `D` at index 4 means `.available(slots: 4)` and a `-` there means
  `.notInstalled`.

  **It is asked at `start` *and* again on the first `IF` the radio answers**, and
  then not again. A radio powered on after the app connects would miss a
  one-shot query at `start` and read as having no recorder for the rest of the
  session — the same silent-link problem `startValidation` exists for
  (Article 14). The first `IF` is the moment the radio proves it is listening.
- `IC;` joins the 0.5 s poll. `parseIC(_:) -> Bool?` returns byte a bit B2
  (`(a >> 2) & 1`), fired through `onVoicePlaybackChange` only on change, in the
  same style as `onKeyerSpeedChange`.

**KX3 and KX2 get no voice keying, and say so.** Their Table 8/8A has a single
`MSG` switch (`SWT11;`) and neither manual documents how to select *which*
message, so implementing it would mean guessing — which Article 1 forbids.
Detecting the model from `OM;` is what stops the app firing an `SWT21;` that
appears in no KX table. The registry keeps one descriptor; no saved `radioID`
moves.

### `MessageSets`

```swift
/// One F-key position on phone. A recording has no text and no macro can reach
/// inside one, so a phone key stores which slot to play and what to call it.
struct PhoneMessage: Codable, Equatable, Sendable {
    var label: String = ""
    var slot: Int?
}

var phoneRun: [PhoneMessage]
var phoneSearchPounce: [PhoneMessage]
func voiceMessages(for mode: OperatingMode) -> [PhoneMessage]
```

Additive per Article 4: an explicit `init(from:)` decodes both with
`decodeIfPresent ?? default`, so every log written before today decodes with its
`run` and `searchPounce` untouched and the phone defaults filled in. `encode(to:)`
stays synthesized.

**The `ExchangeMismatch` checks do not run against the phone set.** They ask
whether a message mentions `{SERIAL}` or `{RST}`; a recording cannot be
inspected, and reporting `missingSerial` for a CQP phone key would be a warning
the operator cannot act on. `exchangeMismatch(with:)` keeps reading `run` and
`searchPounce` only.

`MessagesDraft` gains `phoneRun`/`phoneSearchPounce` and a
`subscript(mode:index:) -> PhoneMessage`. `restoreDefaults(for:)` restores the
phone sets too — from constants, not from `defaults(for: party)`, since the
party's exchange shape cannot change what is on a recording.

### `EntryFlow`

Nested in `EntryFlow` beside `Context` and `Outcome`, since it is part of what
Return decided. `RadioController` never sees it — `MainView.apply` switches on
it and calls `sendCW` or `playVoiceMessage`.

```swift
/// What a message slot puts on the air. CW carries expanded text; a voice
/// message carries a slot number, because a recording has no text.
enum Transmission: Equatable {
    case cw(String)
    case voice(slot: Int, label: String)
    /// An empty CW slot or an unassigned phone key.
    case silent
}
```

`Outcome.send(index:text:)` becomes `send(index:transmission:)` and
`logged(rows:text:)` becomes `logged(rows:transmission:)`. `.silent` replaces
the `""`-means-nothing convention, which was only ever legible next to the
comment explaining it.

`Context` gains `var voiceKeyerReady = false` — defaulted, so every existing
`EntryFlowTests` context literal compiles unchanged.

```swift
/// ESM drives Return on CW, and on phone once the radio's recorder is ready.
func esmDrivesReturn(_ context: Context) -> Bool {
    guard context.keying.esmEnabled, context.radioConnected else { return false }
    switch context.modeClass {
    case .cw: return true
    case .phone: return context.voiceKeyerReady
    case .digital: return false
    }
}
```

`transmission(at:context:)` joins `expandedMessage(at:context:)`, which stays
for the messages-row preview and its existing tests. The `.logAndSend` ordering
— expand *before* logging — is untouched; a voice slot has no serial to get
wrong, but the arm is shared and the comment above it stays load-bearing for CW.

### `RadioController`

```swift
private(set) var voiceStatus: VoiceKeyerStatus = .unsupported
private(set) var isVoicePlaying = false
private var voiceDriver: (any VoiceMessageCapable)?
```

`connect` casts the new driver with `as? any VoiceMessageCapable` and wires both
callbacks; a driver that does not conform leaves `voiceStatus` at `.unsupported`,
which is the honest default.

`playVoiceMessage(slot:label:)` sets `nowSending` to the label and starts **no
timer** — `onVoicePlaybackChange` clears it for real. A private
`nowSendingIsVoice` flag keeps the two paths from clearing each other's badge.

`abortCW(settings:)` becomes `abortTransmission(settings:)`, aborting the CW
sender and, when a recorder is ready, sending `RX;`. Esc reaches both.

**Chaining is deliberately not corrected.** Tapping M1–M4 during playback chains
another message onto the current one; `CWKeyer` queues rather than replaces, and
N1MM stacks function keys the same way. Pressing F1 twice queues two in both
modes, which is the behaviour the operator already has.

### UI

`MessagesRow` stops taking `messages: [String]` and `expand:` and takes
prepared keys instead, so it never has to know which mode it is drawing:

```swift
/// One F-key as the row draws it: the caption under "F3", and whether the key
/// does anything at all.
struct MessageKey: Equatable {
    var caption: String
    var isActive: Bool
}
```

`MessagesEditor` gains a CW/Phone picker above the existing Run/S&P one, and
eight phone rows of a label field plus a slot picker (None, 1–4) — one labelled
control per row. Below them, the inline voice status, worded without naming a
manufacturer (Article 10): "The connected radio has no voice keyer" for
`.unsupported`, "The radio's voice recorder option isn't installed" for
`.notInstalled`. The phone set stays **editable while disconnected** — messages
get set up the week before the contest, with the radio off.

`MainView.startRepeat` widens its `currentModeClass == .cw` guard. For voice it
cannot use `estimatedSendDuration`, so it waits on the real signal: poll
`radio.isVoicePlaying` until it goes true (bounded at 2 s, in case the 0.5 s `IC`
poll misses a short message), then until it goes false, then sleep the interval.
If it never goes true, fall back to the interval alone rather than stalling.

## Testing

`K3ProtocolTests`, quoting the byte strings it verifies (Article 12):

- the exact command for each of slots 1–4, and that slots 0 and 5 emit nothing
- `RX;` for stop
- `parseOM`: K3 with `D` → `.available(slots: 4)`; K3 with `-` at index 4 →
  `.notInstalled`; `…01;` → `.unsupported`; `…02;` → `.unsupported`; a truncated
  response → `.unsupported` rather than a trap
- `parseIC`: byte a with B2 set → true, clear → false, short response → nil, and
  a response whose B7 is set on every byte (which is always) parsing correctly
- `OM;` is sent at start, and `IC;` is in the poll

`MessageSetsTests`: a log encoded before this change decodes with `run` and
`searchPounce` byte-identical and the phone defaults present; `exchangeMismatch`
against a CQP-shaped party returns nil for phone content that would trip
`missingSerial` if it were read.

`EntryFlowTests`: phone with `voiceKeyerReady` false → ESM does not drive Return;
true → the same indexes CW returns; an unassigned slot yields `.silent` and still
logs; a mode-class of `.digital` never drives ESM.

`RadioRegistryTests` and the Article 10 grep stay clean — no model name reaches
`Sources/App` or `Sources/UI`.

Per [the standing rule](../../../CLAUDE.md), each regression test is proved red
before it is proved green.

## Commits

Per Articles 4 and 9.

| | Contents |
| --- | --- |
| 1 | `VoiceKeyerStatus` + `VoiceMessageCapable` + `PhoneMessage`/`MessageSets`/`MessagesDraft` fields + `Transmission` refactor of `Outcome` + `Context.voiceKeyerReady`. No radio implements anything; every party scores and every radio keys identically. `MainView.apply` and `keyed(_:fromMessageAt:)` change with `Outcome` — a mechanical switch over the new cases, since the type they consume moved. That is the whole of the UI in this commit. |
| 2 | `ElecraftK3Driver` conformance + `K3ProtocolTests` + `RadioController` + the messages editor and row + repeat CQ + README, `PROVENANCE.md` and the banked research. |

Docs ship with commit 2 (Article 6): README radio bullet, the keyboard table
where an F-key gained a phone behaviour, and the test count.

## Known gaps, not closed

- **No hardware verification.** Tests prove the bytes, the parsing and the flow;
  they cannot prove the K3 plays the right recording. The two assumptions most
  likely to be wrong on the bench are the `OM;` letter position for `D` and
  whether `RX;` cuts a voice message as cleanly as it cuts CW. Both need a radio.
- **Recording is not supported.** The K3 records with REC then M1–M4 from the
  front panel; the app only plays. N1MM offers recording, but doing it blind over
  CAT with no audio feedback is worse than the front panel.
- **A programmable function switch shadows a message.** The Owner's Manual notes
  an M1–M4 assigned as a programmable function switch is unavailable for message
  play. The app cannot detect this — the slot simply will not sound. README caveat.
- **Bank 2 is unreachable**, by choice. If four recordings prove too few, the
  slot field widens to carry a bank without a migration.
- `MessagesEditor` still has no test of its own; the logic moved into
  `MessagesDraft` is covered, the view is not.

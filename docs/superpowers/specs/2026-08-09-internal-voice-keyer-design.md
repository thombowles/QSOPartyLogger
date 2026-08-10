# Internal voice keyer — design

**Date:** 2026-08-09
**Status:** approved
**Kind:** protocol widening (Article 4) + one radio family's capability (Articles 10–14)
**Governed by:** Article 11 as amended 2026-08-09 — voice plays from the radio's
own memories, never as audio streamed from the Mac
**Research:** [`docs/research/k3_voice_keyer.md`](../../research/k3_voice_keyer.md)

## Why

The app keys CW two ways and phone not at all. On a mixed-mode QSO party the
operator loses the keyboard the moment they switch to SSB: no F-keys, no ESM, no
repeat CQ, and the run is worked by voice alone for the rest of the weekend.
That breaks Article 7 in the one mode where a voice is most easily worn out.

The Elecraft radios have their own recorders, and the reason to drive those
rather than copy the reference implementation is that **N1MM's team does not
support radio-internal voice keyers at all.** Their manual documents a
hand-written `{CAT1ASC …}` escape hatch with three stated costs: Esc may not
interrupt, auto CQ repeat must be hand-tuned because nothing signals the end of
a message, and PTT cannot be managed so such radios must use VOX.

All three are consequences of the audio living on the computer side of the
cable. The Elecraft documents close each one:

| N1MM gives up | The radio provides | Source |
| --- | --- | --- |
| Esc may not stop playback | `RX;` terminates message play and repeating messages | Pgmrs Ref G5, `RX` |
| No end-of-message signal | `IC;` byte a bit B2 = MSG is playing | Pgmrs Ref G5, Table 4 |
| Must use VOX | Playing a transmit message asserts PTT automatically | Owner's Man D10, `CONFIG:KDVR3` |

That is now Article 11's voice clause rather than a decision local to this
design.

## Shape of the feature

A **phone message set**, chosen automatically when the radio reports a voice
mode. Eight F-key positions per operating style, each mapped to **one of the
radio's voice memories, or nothing**. F-keys, ESM, Esc and repeat CQ behave
exactly as they do on CW. An unassigned key advances and logs but transmits
nothing.

**Every memory carries a name, and the F-key caption shows both** — `M1 CQ`,
`M4 AGN?`, or a bare `M6` when that memory has not been named, or `—` when the
key is unassigned. Eight memories is more than anyone remembers by number, so
the name is what makes the row readable at 0200Z.

**The name belongs to the memory, not to the F-key.** One name per memory,
shared by the Run and S&P mappings and by every key that points at it. Naming
per F-key position would mean sixteen names for eight recordings, free to
disagree — Run F2 reading "Exch" and S&P F2 reading "TU" for the same audio.

**The number always leads.** A name is the operator's note to themselves about
what they recorded; nothing in the protocol reports what a memory actually
holds, so a name can go stale when a recording is replaced. Showing `M4 AGN?`
rather than `AGN?` means the caption is never *only* a claim the app cannot
check.

**Eight positions, and up to eight memories.** `ESM.againIndex` is 4 (F5), so
the position count follows CW's eight and stays independent of how many memories
the radio has. **`ESM.swift` does not change at all** — `nextAction` returns the
same indexes in both modes.

### Memory counts are discovered, not declared

Article 11 requires the count to come from the radio. One descriptor serves
three models with three different answers:

| Model | Memories | How a memory is played |
| --- | --- | --- |
| K3 / K3S with KDVR3 | **8** (2 banks of 4) | select bank, then `SWT21/31/35/39;` |
| K3 / K3S without it | **0** | — |
| KX3, KX2 | **2** | `SWT11;` then `SWT19;` or `SWT27;` |

**The KX models are supported.** The first draft of this design ruled them out
on the grounds that the Programmer's Reference documents no way to select a
message — which is true, and was the wrong conclusion. The owner's manuals
document the sequence (tap MSG, then tap the digit) and the reference documents
each keystroke's switch code. Two primary sources from the same manufacturer,
combined; not an inference.

### Defaults

Memory names:

| M1 | M2 | M3 | M4 | M5–M8 |
| --- | --- | --- | --- | --- |
| CQ | Exch | TU | AGN? | *(unnamed)* |

F-key mappings, which show as `M1 CQ`, `M2 Exch` and so on:

| | F1 | F2 | F3 | F4 | F5 | F6–F8 |
| --- | --- | --- | --- | --- | --- | --- |
| Run | M1 | M2 | M3 | — | M4 | — |
| S&P | — | M2 | M3 | — | M4 | — |

Memories 1–4 only, so **the default mapping never triggers a bank change**.
Memories 5–8 are there for an operator who wants them, not spent by a default.

S&P F1 is deliberately unassigned: it is the "send my call" step, and a callsign
is faster spoken than recorded. Return in the call field then does nothing on the
air while the operator speaks — the same thing an empty CW slot already does.

A mapping can reference a memory the connected radio does not have (M5 on a
KX3). That key renders unavailable with its reason, and does not transmit.

## Design

### `Sources/Hardware/Keying/VoiceKeyer.swift` (new)

```swift
/// What the connected radio can do about recorded voice messages. Runtime
/// rather than a `RadioDescriptor` flag, because Article 11 requires the count
/// to be discovered: one descriptor's family answers 8, 2 or 0 depending on the
/// model and on whether an option is fitted.
enum VoiceKeyerStatus: Equatable, Sendable {
    /// This radio has no voice memories the app can drive.
    case unsupported
    /// It has them, but the hardware that provides them is not fitted.
    case notInstalled
    /// Ready, with memories numbered 1...count.
    case available(count: Int)

    var memoryCount: Int { if case .available(let n) = self { n } else { 0 } }
    var isReady: Bool { memoryCount > 0 }
}

/// A radio that can play its own recorded voice messages.
///
/// A separate protocol rather than four more `RadioDriver` members with no-op
/// defaults. Article 11 forbids stubbing out the *CW* keyer members because both
/// keying paths exist on every serial radio and the operator may prefer either.
/// A recorder is different in kind: a radio without one has nothing to stub, and
/// an empty implementation would let it claim a capability by silence.
/// `RadioController` tests for conformance.
protocol VoiceMessageCapable: RadioDriver {
    /// Play the radio's own recording in `memory` (1-based). A memory the radio
    /// does not have is ignored, not clamped.
    func playVoiceMessage(memory: Int)
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

Conforms to `VoiceMessageCapable`. The header comment gains the Owner's Manual
D10, KDVR3 Rev C, KX3 C5 and KX2 B2 citations alongside the existing
Programmer's Reference F2/G5 (Article 12).

```swift
/// Model and options, from `OM;`. The one place a per-model difference lives,
/// because the memory count and the play sequence both depend on it.
enum ElecraftModel { case k3, kx3, kx2 }

/// K3 M1–M4 tap, Table 7. In a voice mode these play the recorder's messages; in
/// CW the same switches play CW text memories, which is why playback is gated on
/// the reported mode.
static let cmdPlayK3Memory = [1: "SWT21;", 2: "SWT31;", 3: "SWT35;", 4: "SWT39;"]
/// K3 REC hold — selects voice bank 1 or 2.
static let cmdSelectBank = "SWH37;"
/// KX3/KX2: tap MSG, then tap the digit. Codes 19 and 27 are digits 1 and 2 on
/// both models (Tables 8 and 8A).
static let cmdPlayKXMemory = [1: ["SWT11;", "SWT19;"], 2: ["SWT11;", "SWT27;"]]
/// Documented to terminate transmit in all modes, message play included.
static let cmdStopVoiceMessage = "RX;"
static let cmdPollOptions = "OM;"
static let cmdPollIcons = "IC;"
```

**`OM;` parsing** — `static func parseOM(_:) -> (model: ElecraftModel, voice: VoiceKeyerStatus)?`:
trailing `01`/`02` in the 12-character field means KX2/KX3 →
`.available(count: 2)`, the recorder being built in on both; otherwise K3/K3S,
where `D` at index 4 means `.available(count: 8)` and `-` means `.notInstalled`.

**It is asked at `start` *and* again on the first `IF` the radio answers**, then
not again. A radio powered on after the app connects would miss a one-shot query
at `start` and read as having no recorder for the rest of the session — the same
silent-link problem `startValidation` exists for (Article 14). The first `IF` is
the moment the radio proves it is listening.

**`IC;` joins the 0.5 s poll.** `parseIC(_:) -> (playing: Bool, bank: Int)?`
reads byte a bits B2 and B3. Playback changes fire `onVoicePlaybackChange` only
on change, in the same style as `onKeyerSpeedChange`.

#### Reaching K3 memories 5–8, without ever playing the wrong one

Memories 5–8 are bank 2's M1–M4, so the bank must change first. Article 11's
amendment makes the safety property explicit: **confirm, or abandon.**

The cached bank comes from a poll up to 0.5 s old, so it is not evidence. The
driver runs a small state machine:

1. Wanted bank equals the last *confirmed* bank → tap immediately.
2. Otherwise send `SWH37;`, then `IC;` out of band, and hold the play pending.
3. The `IC` response confirms the new bank → send the tap.
4. No confirmation within a short window (two `IC` attempts) → **drop the play
   and report it.** Nothing is transmitted.

At 38400 baud an out-of-band `IC;` round-trip is a few milliseconds, so the
added latency before a bank-2 message is small — and it is paid only by an
operator who has mapped a key into bank 2, never by the defaults.

**The bank is per mode group.** The Programmer's Reference footnote on the
MSG-bank bit states it is stored separately for CW/FSK-D/PSK-D and for
voice/DATA-A/AFSK-A, so changing the voice bank cannot disturb the operator's CW
message bank. *This corrects the first draft of this design, which avoided the
bank command entirely on the mistaken belief that one bank number served both.*

The bank is **left where the last play put it** rather than restored. Restoring
would mean issuing a switch during or just after playback, and no source says
what that does to a message in progress. What the app does instead is show the
current bank, so the state is visible rather than surprising.

### `MessageSets`

```swift
/// F1–F8 → the radio's voice memory number, or nil for an unassigned key.
var phoneRun: [Int?]
var phoneSearchPounce: [Int?]
func voiceMemories(for mode: OperatingMode) -> [Int?]

/// What is recorded in each of the radio's voice memories, M1 first. The
/// operator's own note — nothing in the protocol reports a memory's contents.
/// Indexed by memory rather than by F-key so that eight recordings have eight
/// names: naming per key would give Run F2 and S&P F2 separate names for the
/// same audio, free to disagree.
var voiceMemoryNames: [String]

/// "M4 AGN?", or "M6" when unnamed. The number always leads, because the name
/// can go stale when a recording is replaced and the number cannot.
func voiceMemoryCaption(_ memory: Int) -> String
```

These live on `MessageSets`, per document, alongside the CW macros rather than
in `AppSettings`. The recording itself is contest-specific — the memory holding
"59 Travis" this weekend holds "59 Bell" the next — so its name travels with the
log that describes it, exactly as the CW exchange macro does.

Additive per Article 4: an explicit `init(from:)` decodes all three with
`decodeIfPresent ?? default`, so every log written before today decodes with its
`run` and `searchPounce` untouched and the phone defaults filled in.
`encode(to:)` stays synthesized.

**The `ExchangeMismatch` checks do not run against the phone set.** They ask
whether a message mentions `{SERIAL}` or `{RST}`; a recording cannot be
inspected, and reporting `missingSerial` for a CQP phone key would be a warning
the operator cannot act on. `exchangeMismatch(with:)` keeps reading `run` and
`searchPounce` only.

`MessagesDraft` gains `phoneRun`/`phoneSearchPounce`, `voiceMemoryNames`, and a
`subscript(mode:index:) -> Int?`. `restoreDefaults(for:)` restores the phone
mappings and the names too — from constants, not from `defaults(for: party)`,
since the party's exchange shape cannot change what is on a recording.

### `EntryFlow`

Nested beside `Context` and `Outcome`, since it is part of what Return decided.
`RadioController` never sees it — `MainView.apply` switches on it.

```swift
/// What a message slot puts on the air. CW carries expanded text; a voice
/// message carries a memory number, because a recording has no text — plus the
/// caption to show while it plays, composed here so the TX badge and the
/// messages row cannot word the same memory two ways.
enum Transmission: Equatable {
    case cw(String)
    case voice(memory: Int, caption: String)
    /// An empty CW slot, an unassigned phone key, or one pointing at a memory
    /// this radio does not have.
    case silent
}
```

`Outcome.send(index:text:)` becomes `send(index:transmission:)` and
`logged(rows:text:)` becomes `logged(rows:transmission:)`. `.silent` replaces the
`""`-means-nothing convention, which was only ever legible next to the comment
explaining it.

`Context` gains `var voiceMemoryCount = 0` — defaulted, so every existing
`EntryFlowTests` context literal compiles unchanged. It carries the count rather
than a Bool so that `transmission(at:)` can tell an unassigned key from one
pointing past the end of this radio's memories.

```swift
/// ESM drives Return on CW, and on phone once the radio has voice memories.
func esmDrivesReturn(_ context: Context) -> Bool {
    guard context.keying.esmEnabled, context.radioConnected else { return false }
    switch context.modeClass {
    case .cw: return true
    case .phone: return context.voiceMemoryCount > 0
    case .digital: return false
    }
}
```

`transmission(at:context:)` joins `expandedMessage(at:context:)`, which stays for
the messages-row preview and its existing tests. The `.logAndSend` ordering —
expand *before* logging — is untouched; a voice memory has no serial to get
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

`playVoiceMessage(memory:caption:)` sets `nowSending` to the caption and starts
**no timer** — `onVoicePlaybackChange` clears it for real. A private
`nowSendingIsVoice` flag keeps the two paths from clearing each other's badge.

`abortCW(settings:)` becomes `abortTransmission(settings:)`, aborting the CW
sender and, when the radio has memories, sending `RX;`. Esc reaches both.

**Chaining is deliberately not corrected.** A second press during playback
appends on these radios; `CWKeyer` queues rather than replaces, and N1MM stacks
function keys the same way. Pressing F1 twice queues two in both modes, which is
the behaviour the operator already has.

### UI

`MessagesRow` stops taking `messages: [String]` and `expand:` and takes prepared
keys instead, so it never has to know which mode it is drawing:

```swift
/// One F-key as the row draws it: the caption under "F3" — expanded CW text, or
/// "M4 AGN?" — and whether the key can currently do anything.
struct MessageKey: Equatable {
    var caption: String
    var isActive: Bool
}
```

`MessagesEditor` gains a CW/Phone picker above the existing Run/S&P one. The
phone side has **two sections**, because the two things being edited answer
different questions:

1. **Voice memories** — one row per memory, `M1` … `M8`, each with a single text
   field naming what is recorded there. Not repeated per operating style; this
   is what is in the radio. Memories beyond the connected radio's count are
   shown disabled rather than hidden, so a set built for the K3 stays legible
   while a KX is plugged in.
2. **F-keys** — F1…F8 for the selected operating style, each a single picker
   offering None or `M1 CQ`, `M2 Exch`, … so the choice reads as the recording
   rather than as a number.

One labelled control per row throughout, per the standing rule about Form rows.
Below both, the inline voice status, worded without naming a manufacturer
(Article 10):

- `.unsupported` → "The connected radio has no voice memories."
- `.notInstalled` → "This radio's voice recorder option isn't installed."
- `.available(count:)` → "N voice memories available." plus, where the radio has
  banks, which bank it is currently in.

The phone set stays **editable while disconnected** — messages get set up the
week before the contest, with the radio off. All eight memories are offerable
then; the count only constrains what will actually transmit.

`MainView.startRepeat` widens its `currentModeClass == .cw` guard. For voice it
cannot use `estimatedSendDuration`, so it waits on the real signal: poll
`radio.isVoicePlaying` until it goes true (bounded at 2 s, in case the 0.5 s `IC`
poll misses a short message), then until it goes false, then sleep the interval.
If it never goes true, fall back to the interval alone rather than stalling.

## Testing

`K3ProtocolTests`, quoting the byte strings it verifies (Article 12):

- the exact command for K3 memories 1–4, and the two-command sequence for KX
  memories 1–2
- memory 0, 9, and a KX memory 3 emit nothing
- `RX;` for stop
- `parseOM`: K3 with `D` → `.available(count: 8)`; K3 with `-` at index 4 →
  `.notInstalled`; `…01;` → KX2 `.available(count: 2)`; `…02;` → KX3
  `.available(count: 2)`; a truncated response → nil rather than a trap; the
  form with and without the space after `OM`
- `parseIC`: byte a with B2 set → playing; B3 set → bank 2; a short response →
  nil; and a byte with B7 set (which it always is) not corrupting either bit
- `OM;` sent at start **and** re-sent on the first `IF`; `IC;` present in the poll
- **bank sequencing**: asking for memory 5 while bank 1 is confirmed emits
  `SWH37;` and *not* the tap; the tap follows only after an `IC` confirming bank
  2; and an `IC` that never confirms emits **no tap at all**

That last one is the test that matters most — it is the difference between a
missed transmission and the wrong audio on the air.

`MessageSetsTests`: a log encoded before this change decodes with `run` and
`searchPounce` byte-identical and the phone mappings *and memory names* present;
names survive a round-trip; `voiceMemoryCaption` renders `M4 AGN?` for a named
memory, a bare `M6` for an unnamed one, and trims a name that is only
whitespace; renaming a memory changes every F-key pointing at it in both
operating styles, in one assertion — that is the property the per-memory
indexing exists for; `exchangeMismatch` against a CQP-shaped party returns nil
for phone content that would trip `missingSerial` if it were read.

`EntryFlowTests`: phone with `voiceMemoryCount` 0 → ESM does not drive Return;
8 → the same indexes CW returns; an unassigned key and a key pointing past the
count both yield `.silent` and still log; `.digital` never drives ESM.

`RadioRegistryTests` and the Article 10 grep stay clean — no model name reaches
`Sources/App` or `Sources/UI`, and no memory count is written there either.

Per [the standing rule](../../../CLAUDE.md), each regression test is proved red
before it is proved green.

## Commits

Per Articles 4 and 9. The Article 11 amendment landed first, in its own commit.

| | Contents |
| --- | --- |
| 1 | `VoiceKeyerStatus` + `VoiceMessageCapable` + `MessageSets`/`MessagesDraft` phone fields + `Transmission` refactor of `Outcome` + `Context.voiceMemoryCount`. No radio implements anything; every party scores and every radio keys identically. `MainView.apply` and `keyed(_:fromMessageAt:)` change with `Outcome` — a mechanical switch over the new cases. That is the whole of the UI in this commit. |
| 2 | `ElecraftK3Driver` conformance including model detection and bank sequencing + `K3ProtocolTests` + `RadioController` + the messages editor and row + repeat CQ + README, `PROVENANCE.md` and the banked research. |

Docs ship with commit 2 (Article 6): README radio bullet, the keyboard table
where an F-key gained a phone behaviour, and the test count.

## Known gaps, not closed

- **No hardware verification.** Tests prove the bytes, the parsing, the bank
  sequencing and the flow; they cannot prove the radio plays the right
  recording. The assumptions most likely to be wrong on the bench are the `OM;`
  letter position for `D`, whether `RX;` cuts a voice message as cleanly as it
  cuts CW, and whether the bank change settles before the tap in practice.
- **Recording is not supported.** Both radios record from the front panel; the
  app only plays. N1MM offers recording, but doing it blind over CAT with no
  audio feedback is worse than the front panel.
- **The bank is left where the last play put it.** An operator who maps a key
  into bank 2 will find the front panel's M1–M4 addressing bank 2 afterwards.
  The status line shows the current bank; the app does not restore it, because
  no source says what a bank change during playback does.
- **The app cannot hear the memories.** Nothing in the protocol reports whether
  a memory holds audio, or what it says. So a key mapped to a never-recorded
  memory simply produces silence, and a name can go stale when a recording is
  replaced from the front panel. Both are why the caption always leads with the
  memory number: `M4 AGN?` degrades to a still-true `M4`, where a bare `AGN?`
  would just be wrong. README caveat.
- **A programmable function switch shadows a memory.** The Owner's Manual notes
  an M1–M4 assigned as a programmable function switch is unavailable for message
  play, and the app cannot detect it. README caveat.
- `MessagesEditor` still has no test of its own; the logic moved into
  `MessagesDraft` is covered, the view is not.

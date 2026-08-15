# Voice messages recorded on the Mac — design

**Date:** 2026-08-15
**Status:** approved (autonomous session; decisions recorded below, defaults chosen where the request left room)
**Kind:** constitutional amendment (Article 11) + protocol widening (Article 4) + two radios' capabilities (Articles 10–14)
**Supersedes in part:** [`2026-08-09-internal-voice-keyer-design.md`](2026-08-09-internal-voice-keyer-design.md) — the radio's own memories stay a supported source; they stop being the *only* source
**Research:** [`docs/research/voice_transports.md`](../../research/voice_transports.md)

## Why

The 2026-08-09 design put phone messages on the air from the radio's own recorder,
and wrote into Article 11 that this app "does not stream recorded audio to a
radio". Six days later the operator asked for exactly that:

> Add a voice recorder feature that would allow me to record, edit, and save
> voice files for each contest and play them back over the voice memories. There
> will need to be a way to play these to the radio. For flex it should be over the
> network, for elecraft it will need to be over its sound card interface. For
> radios that support on-board voice memories (DVR), make that the default but
> also make the onboard memories an option also.

Two facts the earlier article did not weigh:

1. **A Flex has no recorder.** The only phone-message path on a FLEX-6000/8000 is
   audio from the computer over DAX. Article 11 as written left the app's one
   network radio with no phone keys at all.
2. **Message sets are per contest, and recorders are not.** "CQ Texas QSO Party"
   is one recording, "CQ Alabama" another, and the exchange changes county to
   county. A recorder in the radio holds one set; re-recording eight memories from
   the front panel before every party is the chore this feature exists to remove.

The three objections the article raised against computer audio were about
*not owning the audio path*: no end-of-message signal, Esc that may not stop it,
PTT that needs VOX. Every one of them was a consequence of some *other* program
owning the playback. When this app owns the player, all three invert:

| Objection (Article 11, 2026-08-09) | With the app owning playback |
| --- | --- |
| No end-of-message signal, so repeat CQ is hand-tuned | The player reports the exact end of the clip; repeat CQ times off it |
| Esc may not interrupt | Esc stops our own player and drops PTT the same instant |
| PTT cannot be managed, so VOX is required | The app keys the radio over CAT (`TX;`/`RX;`) or over the Flex API (`xmit`), with a lead and a tail it controls |

What remains true, and is kept: the audio *level* into the radio is the
operator's to set, once, and the app gives them a meter and a "play to radio"
button to set it with. The article is amended in its own commit; the amendment
records this case.

## Decisions made without the operator in the room

The request is explicit about almost everything. Two readings were possible for
one sentence and both are recorded here so they can be reversed cheaply:

- **"make that the default"** is read as: on a radio that has both, **recordings
  on this Mac are the default source; the radio's own memories remain an option.**
  The alternative reading — "keep the recorder the default" — makes the sentence
  say "make the onboard memories the default and also an option", which is
  redundant; and the request's opening line ("play them back over the voice
  memories") describes recordings *replacing* what the F-keys play. This is one
  enum default (`AppSettings.phoneMessageSource`), one line to flip.
- **Recordings are kept per party, not per log file.** "Voice files for each
  contest" is read as *each QSO party*: TXQP's set is reused next year, and a new
  log for the same party finds them. They live outside the log because eight
  ten-second WAVs would put 8 MB of base64 into a JSON file that autosaves on
  every contact.

Everything else — trim, gain, import, copy-from-another-party, the transports,
the keyboard paths — follows from "record, edit, save, play to the radio" and
from Article 7.

## Shape of the feature

**Eight voice memories per party, recorded on the Mac.** The phone message model
from 2026-08-09 is kept whole: F1–F8 map (per operating style) to a memory number
1–8; every memory carries a name (`M2 Exch`); Run and S&P share memories. What is
new is that a memory can hold **a recording on this Mac** as well as, or instead
of, a recording in the radio. Which one plays is one setting:

> **Phone messages play from:** ● Recordings on this Mac ○ The radio's voice memories

The second option exists only when the connected radio reports memories. With
no radio connected, or a radio that has none, there is nothing to choose.

**Recording lives in the Messages editor, Phone tab.** One place already holds
the memory names, the F-key mapping and the voice status line; it gains a
recorder row per memory:

```
 M1  [CQ        ]  ▂▄▆█▆▄▂▁▂▄▆   2.4 s   ● Rec   ▶   ✂ Trim   ⇢ Radio   ⋯
 M2  [Exch      ]  ▂▄▆█▆         1.1 s   ● Rec   ▶   ✂ Trim   ⇢ Radio   ⋯
 …
 M8  [          ]  no recording          ● Rec   Import…
```

Above the rows: the source picker (when there is a choice), the microphone
picker with a live level meter, and — for a radio reached through a sound card —
the radio's audio output device, the PTT method (radio command, or VOX/none)
and its lead time; for a network radio, one line saying audio goes to the radio
over its own connection. A **Level** slider sets the transmit audio level for
either path. Below: the same status sentence the tab shows today, now covering
both sources ("Recordings play to the radio through *USB Audio CODEC*; PTT by
radio command." / "…over the network." / why nothing can play).

**Recording.** ● Rec (or `⌘1`–`⌘8`) starts; the row shows the meter and a
running clock; the same key, Space, Return or the button stops it; recording
stops by itself at 30 s. Leading and trailing silence are trimmed automatically
(with 120 ms kept on each side) so a clip starts when the voice does. The
recording is written to disk immediately as a 48 kHz mono 16-bit WAV — it is not
part of the sheet's Save/Cancel, and the tab says so.

**Editing.** ✂ opens a popover with a large waveform, two trim handles, a play
button, **Auto-trim** (redo the silence trim) and **Normalize** (peak to −1 dBFS).
Trim and gain are non-destructive — kept in the set's sidecar, applied at
playback — so a trim can be widened later. The waveform in the row draws the
trimmed region.

**▶** plays the clip on the Mac (default output device — the operator's
speakers) so it can be checked without keying up. **⇢ Radio** plays it *to the
radio*, exactly as F1 would, so levels can be set against the radio's ALC meter.
The **⋯** menu offers Import…, Reveal in Finder, and Delete.

**Copy from another party…** fills every *empty* memory of this party's set
from another party's recordings — TU, AGN?, 73 and "my call" are the same in
every party, and only CQ and the exchange need re-recording each weekend.

**On the air.** F1–F8, ESM, Esc and repeat CQ behave exactly as on CW and on
the radio's memories. The TX badge shows the caption while the clip plays and
clears when it ends — the *actual* end, reported by the player. A second F-key
during playback **replaces** the clip on the air (stops it, plays the new one):
that is what a voice keyer does, and it is what an operator wants when a station
answers mid-CQ. (CW keeps queueing; the radio's own recorder keeps whatever it
does. Only the path this app owns changes, and it is documented.)

**Keys.** `⌘1`–`⌘8` record/stop memory N; `⌥⌘1`–`⌥⌘8` play memory N on the
Mac; `⇧⌘V` opens the Messages editor on the Phone tab from the log window; the
trim popover's play is Space. Every other control is a button reachable by Tab.

**Never key on connect, never transmit the unconfirmed.** Nothing keys the radio
until an F-key, Return under ESM, repeat CQ, or ⇢ Radio asks. A recordings
source that is not ready — no radio audio device chosen, or the Flex refused the
stream — leaves the phone keys inert with the reason in the row's tooltip and
the tab's status line, and never falls back to the radio's recorder on its own.
(Microphone permission gates recording only; playback needs none.)

## Design

### Where things live

| Path | New | Purpose |
| --- | --- | --- |
| `Sources/Core/Voice/VoiceClip.swift` | ✔ | `VoiceClip`, `VoiceMessageSet` — the per-party set and its sidecar JSON |
| `Sources/Core/Voice/VoiceLibrary.swift` | ✔ | On-disk layout under `~/Library/Application Support/QSOPartyLogger/Voice/<partyID>/`; load/save/delete/copy |
| `Sources/Core/Voice/VoiceAudio.swift` | ✔ | `VoiceAudio` (mono float samples + rate) and the pure DSP: trim, gain, peak/RMS, silence bounds, normalize |
| `Sources/Hardware/Voice/VoiceTransports.swift` | ✔ | `TransmitControlCapable`, `AudioStreamTransmitCapable`, `TransmitAudioEvent` |
| `Sources/Hardware/Voice/AudioFileIO.swift` | ✔ | WAV write and any-format read via `AVAudioFile` → `VoiceAudio` |
| `Sources/Hardware/Voice/AudioResampler.swift` | ✔ | `AVAudioConverter` wrapper: `VoiceAudio` → any rate |
| `Sources/Hardware/Voice/AudioDevices.swift` | ✔ | CoreAudio device enumeration (input/output, UID ↔ name), default-device lookup |
| `Sources/Hardware/Voice/VoiceRecorder.swift` | ✔ | `AVAudioEngine` input tap → `VoiceAudio`, live level, chosen input device |
| `Sources/Hardware/Voice/VoicePlayer.swift` | ✔ | `VoicePlaying` protocol; `AVVoicePlayer` (engine → chosen output device, PTT lead/tail sequencing); `MonitorPlayer` for the Mac speakers |
| `Sources/Hardware/Voice/DAXPacketizer.swift` | ✔ | Pure: 24 kHz mono → VITA-49 IF-data packets, stereo float32 BE, 128 frames each |
| `Sources/Hardware/Network/UDPSender.swift` | ✔ | Connected UDP socket to host:port; reports its local port |
| `Sources/Hardware/Network/TCPTransport.swift` | edit | exposes `hostName` so a driver can reach the same host over UDP |
| `Sources/Hardware/Radio/ElecraftK3Driver.swift` | edit | `TransmitControlCapable`: `TX;` / `RX;` |
| `Sources/Hardware/Radio/FlexRadioDriver.swift` | edit | `AudioStreamTransmitCapable`: udpport, dax, stream, xmit, packets |
| `Sources/App/VoiceStore.swift` | ✔ | `@Observable`: the active party's set, rendered clips in memory, recorder/monitor glue, device lists |
| `Sources/App/RadioController.swift` | edit | `playRecording`, `voicePathStatus`, transport dispatch, abort |
| `Sources/App/EntryFlow.swift` | edit | `Transmission.recording`, `Context.phoneSource`, `voiceRecordings` |
| `Sources/App/AppSettings.swift` | edit | source, devices, level, PTT mode and lead |
| `Sources/UI/VoiceMessagesPane.swift` | ✔ | The Phone tab's recorder rows, pickers, trim popover |
| `Sources/UI/MessagesEditor.swift` | edit | embeds the pane; status text covers both sources |
| `Sources/UI/MainView.swift` | edit | `.recording` dispatch, `phoneSource` in the context, ⇧⌘V, toolbar label |

The `CLAUDE.md` layout table gains `Sources/Core/Voice/` and
`Sources/Hardware/Voice/`.

### Core — the model on disk

```swift
/// One recording, as the sidecar describes it. Non-destructive: the file is
/// what was recorded or imported; trim and gain are applied at playback.
struct VoiceClip: Codable, Equatable, Sendable {
    var fileName: String          // "M1.wav" — always relative to the set folder
    var duration: TimeInterval    // of the file, for the row without opening it
    var trimStart: TimeInterval   // seconds; 0 = from the top
    var trimEnd: TimeInterval     // seconds; == duration = to the end
    var gainDB: Float             // 0 = as recorded; Normalize sets it
    var recordedAt: Date
}

/// A party's eight memories. `clips` is keyed by memory number 1...8; a missing
/// key is an empty memory.
struct VoiceMessageSet: Codable, Equatable, Sendable {
    static let version = 1
    var version: Int
    var clips: [Int: VoiceClip]
}
```

`VoiceLibrary` (a `struct` with a `folder`, like `CallHistoryStore`):

- `folder/<partyID>/voice.json` + `folder/<partyID>/M<n>.wav`.
- `load(partyID:) -> VoiceMessageSet` (empty set when nothing is there; an
  unreadable sidecar is reported, never silently replaced — the WAVs are the
  operator's work).
- `save(_:partyID:)`, `fileURL(partyID:memory:)`, `remove(memory:partyID:)`
  (deletes file + entry), `copyMissing(from:to:) -> Int` (copies files and
  entries for memories the destination lacks), `partiesWithRecordings() -> [String]`.
- Party IDs are validated against `[A-Za-z0-9_-]+` before touching the file
  system.

`VoiceAudio` is the in-memory form everywhere else:

```swift
struct VoiceAudio: Equatable, Sendable {
    var sampleRate: Double
    var samples: [Float]              // mono, −1…1
    var duration: TimeInterval { Double(samples.count) / sampleRate }
    func trimmed(from: TimeInterval, to: TimeInterval) -> VoiceAudio
    func applyingGain(dB: Float) -> VoiceAudio
    var peak: Float; var rms: Float
    /// First and last sample above `thresholdDB` (default −40 dBFS), padded by
    /// `pad` seconds and clamped — nil for a silent clip.
    func voicedRange(thresholdDB: Float, pad: TimeInterval) -> ClosedRange<TimeInterval>?
    /// The gain that puts the peak at `targetDB` (−1 dBFS).
    func normalizationGainDB(targetDB: Float) -> Float
    /// `count` peaks across the clip, for the waveform.
    func waveform(bins: Int) -> [Float]
}
```

Rendering a clip for the air = read file → `trimmed` → `applyingGain` — done by
`VoiceStore` when the set loads or changes, and cached in memory so an F-key
never waits on disk. Eight clips at 48 kHz mono float, thirty seconds each, is
under 50 MB at the very worst and a few MB in practice.

### Hardware — two capabilities, one player, one packetizer

```swift
/// A radio the app can key over its control link for the duration of a
/// message played through a sound card. `TX;`/`RX;` on the Elecraft family.
protocol TransmitControlCapable: RadioDriver {
    func setTransmit(_ on: Bool)
}

/// A radio that takes transmit audio from the app over its own connection —
/// no sound card, no PTT line. The driver keys, streams, and unkeys.
protocol AudioStreamTransmitCapable: RadioDriver {
    /// The rate the radio wants samples at. The caller resamples to it.
    var transmitSampleRate: Double { get }
    /// Key the radio, put `audio` on the air, unkey. One at a time: a second
    /// call while one is in flight stops the first.
    func transmitAudio(_ audio: VoiceAudio)
    func stopTransmitAudio()
    var onTransmitAudioEvent: (@Sendable (TransmitAudioEvent) -> Void)? { get set }
}

enum TransmitAudioEvent: Equatable, Sendable {
    case started
    case finished          // played to the end, radio unkeyed
    case stopped           // aborted, radio unkeyed
    case failed(String)    // never keyed, or unkeyed early — the operator sees this
}
```

**`VoicePlaying`** (the sound-card path) is a protocol so `RadioController` can
be tested with a fake:

```swift
protocol VoicePlaying: AnyObject {
    /// Play `audio` to the output device with `deviceUID` (nil = system
    /// default), scaled by `gain`. `keyRadio`, when given, is called with
    /// `true` `leadMs` before the first sample and `false` `tailMs` after the
    /// last; nil means VOX/none. `onEvent` fires `.started` when audio begins,
    /// `.finished`/`.stopped`/`.failed` exactly once at the end.
    func play(_ audio: VoiceAudio, deviceUID: String?, gain: Float,
              keyRadio: ((Bool) -> Void)?, leadMs: Int, tailMs: Int,
              onEvent: @escaping @Sendable (TransmitAudioEvent) -> Void)
    func stop()
}
```

`AVVoicePlayer` implements it with an `AVAudioEngine` whose output unit is
pointed at the device (`kAudioOutputUnitProperty_CurrentDevice`), an
`AVAudioPlayerNode`, and `scheduleBuffer(…, completionCallbackType: .dataPlayedBack)`
for the real end. `stop()` stops the node and engine and calls `keyRadio(false)`
at once. The sequencing (lead → play → end → tail → unkey; stop at any point)
lives in a small pure state machine tested without audio.

**`DAXPacketizer`** (pure): `packets(for audio: VoiceAudio, streamID:, startingSequence:) -> [Data]`.
Every packet is a VITA-49 IF Data packet with stream ID and class ID, no
trailer, TSI=Other, TSF=SampleCount, OUI `0x001C2D`, information class
`0x534C`, packet class `0x03E3`, 128 frames of interleaved stereo float32
big-endian (the mono sample in both channels), packet size 263 words, sequence
count mod 16, last packet zero-padded to 128 frames. The header bytes are pinned
in tests byte for byte.

### Elecraft — `TransmitControlCapable`

`setTransmit(true)` writes `TX;`, `setTransmit(false)` writes `RX;` (Pgmrs Ref
G5: `TX` — "Same as activating PTT or using the XMIT switch"; `RX` — "Terminates
transmit in all modes"). Nothing else changes in the driver. The README's K3
section explains the audio side from the Owner's Manual D10: LINE IN "should be
connected to your computer's soundcard output"; `MAIN:MIC SEL` = LINE IN, or
`MIC+LIN` ON to keep the microphone live alongside it; sound-card level "6 to
10 dB below the level at which the sound card's output stage starts clipping".

### Flex — `AudioStreamTransmitCapable`

Everything is from the SmartSDR TCP/IP API wiki, FlexLib 3.2.37's
`DAXTXAudioStream`, and one FlexRadio staff answer on the sample format; the
research file quotes each. The driver:

1. **At `start`:** parses and keeps the `H<handle>` line (its own client
   handle); subscribes `sub dax all` in addition to today's `slice`/`tx`/`cwx`;
   parses `dax=<n>` and `tx=<0|1>` from slice status and `dax=<0|1>` from
   transmit status. Nothing else at connect — no socket, no stream, no `client
   udpport` until voice is first used, so a Flex used only for CW is untouched.
2. **First `transmitAudio`, once per session:** opens a connected UDP socket to
   the radio's host, port 4991; reads its local port; sends
   `client udpport <port>`; `dax audio set <ch> tx=1` where `<ch>` is the TX
   slice's DAX channel or 1; `stream create type=dax_tx`, and takes the stream
   ID from the `R<seq>|0|<id>` reply (kept per sequence number) or from the
   `stream <id> type=dax_tx client_handle=<ours>` status, whichever lands first.
   A non-zero reply code, or no stream ID within 2 s, is `.failed(reason)`
   with the radio's hex code in it — nothing is keyed.
3. **Every play:** `transmit set dax=1` unless already on; `xmit 1`; 120 ms of
   silence packets; the clip's packets one every 128/24000 s on a dedicated
   thread with absolute deadlines (the keyer's `sleepUntil`); 100 ms of silence;
   `xmit 0`; `transmit set dax=0` if it was off before. `.started` on the first
   audio packet, `.finished` after `xmit 0`.
4. **`stopTransmitAudio`:** stops the pacing thread, `xmit 0`, restores `dax`,
   `.stopped`.
5. **`stop()`:** `stream remove <id>` if one exists, closes the socket.

Sample format: 24 kHz, stereo interleaved IEEE-754 float32, 0 dBFS = 1.0 (staff
answer, banked). The caller resamples to `transmitSampleRate` (24000) and scales
by the level setting before the driver sees the samples.

### `RadioController`

```swift
/// Whether recordings can reach the connected radio right now, and how.
enum VoicePathStatus: Equatable, Sendable {
    /// This radio takes no audio from the Mac. Phone keys use its memories if it has any.
    case unsupported
    /// Supported, but not set up: the reason is what the operator must fix.
    case notReady(reason: String)
    /// Ready over the radio's own network connection.
    case readyOverNetwork
    /// Ready through a sound card, to the named output device.
    case readyOverDevice(name: String)
}
private(set) var voicePathStatus: VoicePathStatus
```

Derived on connect and whenever the relevant settings change
(`refreshVoicePath(settings:)`): a driver that is `AudioStreamTransmitCapable` →
`.readyOverNetwork`; `TransmitControlCapable` (or PTT mode VOX) with an output
device UID that resolves to a present device → `.readyOverDevice(name)`; a UID
that is nil or absent → `.notReady("Choose the radio's audio output in Messages → Phone")`;
neither capability → `.unsupported`.

`playRecording(_ audio: VoiceAudio, caption: String, settings:)`:

- claims the badge exactly as `playVoiceMessage` does (`nowSending = caption`,
  `nowSendingIsVoice = true`), sets `isVoicePlaying = true`, cancels any
  recording already playing (replace semantics);
- network: resample to `transmitSampleRate`, scale by level, `transmitAudio`;
- device: `voicePlayer.play(audio, deviceUID:, gain:, keyRadio: setTransmit or nil, leadMs:, tailMs: 100, …)`;
- on `.finished`/`.stopped`: `isVoicePlaying = false`, and clear the badge if the
  voice path still owns it; on `.failed(reason)`: the same, plus `lastError =
  ("Voice message not sent", reason)` — the inline slot the radio bar already
  shows.

`abortTransmission` additionally calls `voicePlayer.stop()` and
`stopTransmitAudio()`. `disconnect` does the same and resets `voicePathStatus`.
The player is injected (`makeVoicePlayer: () -> any VoicePlaying`) so tests
drive a fake.

### `EntryFlow`

```swift
enum PhoneSource: Equatable, Sendable {
    /// The radio's own recorder, memories 1...voiceMemoryCount.
    case radioMemories
    /// Recordings on this Mac. `ready` is the audio path; unready keys stay
    /// silent, with the reason shown by the row — they never fall back.
    case recordings(ready: Bool)
}
```

`Context` gains `var phoneSource: PhoneSource = .radioMemories` — additive, so
every existing `Context` literal and every existing test means what it did.
`EntryFlow` gains `var voiceRecordings: [Int: VoiceAudio] = [:]` (set by the
view from `VoiceStore`, like `callHistoryIndex`) and `Transmission` gains

```swift
case recording(memory: Int, audio: VoiceAudio, caption: String)
```

`transmission(at:)` on phone: unassigned key → `.silent`; `.radioMemories` →
today's logic; `.recordings(ready: false)` → `.silent`; `.recordings(ready:
true)` → `.recording(…)` if `voiceRecordings[memory]` exists, else `.silent`.
`esmDrivesReturn` on phone: `.radioMemories` → `voiceMemoryCount > 0`;
`.recordings(ready)` → `ready && !voiceRecordings.isEmpty`.

The view derives `phoneSource` in one place (`operatingContext`):

- setting `.recordings` and `voicePathStatus` is `.ready…` → `.recordings(ready: true)`;
- setting `.recordings` and `.notReady` → `.recordings(ready: false)`;
- setting `.recordings` and `.unsupported` → `.radioMemories` (the only thing
  that can play; the status line says so);
- setting `.radioMemories` → `.radioMemories`.

`MainView.transmit` gains `case .recording(_, let audio, let caption):
radio.playRecording(audio, caption: caption, settings: settings)`. `messageKeys`
captions a `.recording` like a `.voice`. `waitForEndOfTransmission` treats
`.recording` like `.voice` — `isVoicePlaying` is now driven by the player as
well as by the radio, so `waitForVoicePlaybackToFinish` needs no change.

### `AppSettings`

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `phoneMessageSource` | `PhoneMessageSource` (`recordings` / `radioMemories`) | `.recordings` | Which source phone keys use where both exist |
| `voiceInputDeviceUID` | `String?` | nil (system default) | Microphone for recording |
| `voiceOutputDeviceUID` | `String?` | nil (not chosen) | The radio's audio input, for the sound-card path |
| `voiceLevel` | `Double` 0…1 | 0.6 | Transmit audio level, both paths |
| `voicePTT` | `VoicePTTMode` (`radioCommand` / `vox`) | `.radioCommand` | Sound-card path only |
| `voicePTTLeadMs` | `Int` 0…500 | 120 | Silence between keying and the first sample |

Raw values are storage, never display (Article 10 practice); all read with
`?? default`.

### `VoiceStore` (App)

`@Observable`, one per document window, created by `MainView`:

- `partyID` (set by the view), `set: VoiceMessageSet`, `rendered: [Int: VoiceAudio]`
  (rebuilt off the main thread when the set changes; the view copies it into
  `flow.voiceRecordings`), `waveforms: [Int: [Float]]`;
- `record(memory:)`, `stopRecording()`, `isRecording`, `recordingMemory`,
  `inputLevel` (0…1, updated ~20 Hz), `elapsed`;
- `preview(memory:)` / `stopPreview()` — `MonitorPlayer` on the default output;
- `setTrim(memory:start:end:)`, `setGain(memory:dB:)`, `normalize(memory:)`,
  `autoTrim(memory:)`, `delete(memory:)`, `import(url:memory:)`, `copyMissing(from:)`;
- `inputDevices`, `outputDevices` (refreshed on appear and on CoreAudio device
  change), `microphoneAuthorized`, `requestMicrophoneAccess()`;
- `lastError: String?` for the tab's inline line.

Recording is 30 s max; the auto-trim keeps 120 ms of pad; a clip whose voiced
range is empty is kept as recorded (silent), and the row says "silent".

Microphone access needs `NSMicrophoneUsageDescription` (Info.plist, via
`project.yml`) and the `com.apple.security.device.audio-input` entitlement. The
tab asks only when ● Rec is first pressed, and shows the System Settings path
if refused — the same shape as the Local Network message.

### UI — `VoiceMessagesPane`

Embedded in `MessagesEditor` when `editClass == .phone`, replacing the plain
name grid. Two columns: memories (rows above) on the left, the existing F-key
mapping pickers on the right, so the sheet stays inside its 740 × 600 floor.
Above the columns: the source picker (only when `voiceStatus.isReady`), the
input/output/PTT/level controls (output/PTT only for `.readyOverDevice`/`.notReady`
paths). Below: the status sentence, worded without a manufacturer or a model
(`VoiceStatusTextTests` widens to cover every case). The trim popover is its own
small view. `MessagesEditor.voiceStatusText(_:bank:)` becomes
`voiceStatusText(_:bank:path:source:)` and stays a `nonisolated static func`.

Names and mappings stay in the sheet's draft with Save/Cancel; recordings apply
immediately, and the tab says "Recordings save as you make them."

### Error handling

- Every failure has an inline home: recorder failures in the tab's status line;
  playback failures in the radio bar's error slot with a summary and detail
  tooltip; readiness gaps in the phone keys' tooltip and the tab.
- The Flex reply codes are surfaced verbatim ("The radio refused the DAX stream
  (0x50000064 — no UDP port registered)") — the wiki's meanings are quoted where
  known, the hex is always shown.
- A UDP socket that cannot open, a device that vanished, an engine that fails to
  start: `.failed`, unkey if keyed, badge cleared, error shown. Nothing retries
  on its own; the next press retries.
- The player and the streamer both unkey on `stop()` first and report second, so
  Esc is never waiting on a callback.

### Testing

Everything runs without hardware, network or a microphone (Article 5):

- **Core:** `VoiceAudioTests` (trim, gain, peak/RMS, voiced range with pad and
  clamp, normalization gain, waveform bins); `VoiceLibraryTests` over a temp
  folder (empty set, save/load round trip, remove deletes the file, copyMissing
  copies only the gaps and returns the count, party ID validation, unreadable
  sidecar reported).
- **Hardware:** `AudioFileIOTests` (WAV write → read round trip, stereo import
  folds to mono, rate preserved); `AudioResamplerTests` (48 k → 24 k halves the
  count and keeps a 1 kHz tone's zero-crossing rate); `DAXPacketizerTests` (the
  header bytes of packet 0, stream and class IDs, packet size word, sequence
  wraps at 16, stereo duplication and big-endian floats, last packet padded, a
  clip shorter than a packet yields one packet); `VoicePlayerSequenceTests` (the
  lead/play/tail/unkey order, stop mid-lead never plays and unkeys, stop
  mid-clip unkeys at once, VOX never keys); `K3ProtocolTests` (`TX;`/`RX;`, and
  that nothing else in the driver changed — the existing suite); `FlexRadioDriverTests`
  (the exact command sequence for a first play and a second play, the stream ID
  from the reply, the stream ID from status, `dax` restored only when it was off,
  the udpport from the socket, `.failed` on a non-zero reply, `.failed` on no
  stream ID, stop mid-clip sends `xmit 0` and never `.finished`, `sub dax all`
  at start, and no UDP socket opened until the first play — over the mock
  transport and a mock UDP sender).
- **App:** `EntryFlowTests` (`.recording` for a recorded memory, `.silent` for
  an unrecorded one, `.silent` when unready, `.radioMemories` unchanged, ESM
  driven only when ready and something is recorded); `RadioControllerVoiceTests`
  (badge claim/clear through a fake player, `isVoicePlaying` from the player,
  replace semantics, abort stops the player and unkeys, `.failed` sets the inline
  error, `voicePathStatus` truth table, disconnect resets); `AppSettings`
  defaults; `VoiceStatusTextTests` (no manufacturer, no memory layout, every
  status).
- **UI:** the pane's key table and status wording as pure functions.

Regression tests are proved red first, per the standing rule.

### Commits

| | Contents |
| --- | --- |
| 1 | Article 11 amended (its own commit), with the case that forced it |
| 2 | Core voice model, transports protocols, packetizer, player, recorder, `EntryFlow`/`RadioController`/settings/`VoiceStore`, the pane, tests. **No radio conforms yet**: every radio keys and plays exactly as before, and the recordings source reports `.unsupported` everywhere. CLAUDE.md layout, README features + keyboard table + test count, entitlement, Info.plist key |
| 3 | Elecraft: `TransmitControlCapable`, `K3ProtocolTests`, README wiring (LINE IN / MIC SEL / MIC+LIN), PROVENANCE, banked owner's-manual excerpts |
| 4 | Flex: `AudioStreamTransmitCapable`, `FlexRadioDriverTests`, README "Connecting a Flex" voice paragraph, PROVENANCE, banked wiki pages and the FlexLib/staff-answer excerpts |

Then a `merge:` commit onto master, as the previous features did.

### Known gaps, stated

- **Hardware verification.** The Flex path was verified on the air on
  2026-08-15 — after two silent attempts that taught it the one thing the
  sources had not stated plainly: the `dax_tx` stream must *call* `stream set
  0x<id> tx=1` to be the one the radio modulates, whatever its status line
  says. The Elecraft path is tested to the byte over a mock transport but has
  not been on a bench; whether a 120 ms `TX;` lead suits a given amplifier is
  the open question there. See the research file's "Bench" and OPEN QUESTIONS.
- **PTT over a serial control line is not offered.** `KeyerLineConfig` already
  models a PTT line for CW; wiring voice to it is a later, separate change if
  the radio command proves too slow for someone's station.
- **One recorder at a time.** Two log windows for the same party share the
  files on disk; whichever saves last wins the sidecar. Not worth a lock.
- **The QMX** documents `TX;`/`RX;` and a USB sound card with an SSB source
  setting; it can conform to `TransmitControlCapable` in its own one-radio
  commit when someone wants to run phone on one.

# Full KX2 support — CW keying over CAT, and F-key right-click — design

**Date:** 2026-08-22
**Status:** approved by the operator (KE5CW), 2026-08-22
**Kind:** one new radio (Articles 10–14) + one structural refactor (Article 4) + one UI enhancement + docs (Article 6)
**Research:** [`docs/research/kx_cw_keying.md`](../../research/kx_cw_keying.md)

## Why

Reported 2026-08-22:

> Several enhancements surrounding support for the elecraft KX2:
> 1. CW keying from the app to the KX2 doesn't work.
> 2. when I have the KX2 connected and I go to edit the button presets for phone
>    memories in the app, the app freezes.
>
> Make sure to note the KX2 specific commands in this programmers reference, and
> make sure to include full support for the kX2, even for sending CW and using
> the on-board KX2 voice memories.
>
> Also add an enhancement to right click any of the F buttons to edit the
> memories.

Item 2 was withdrawn by the operator later the same day ("no longer a problem,
disregard") and is **out of scope**; the two defects found while investigating it
are recorded under *Deferred* below rather than fixed here.

On-board voice memories already work on a KX2 and are unchanged by this design:
`OM` reports the product identifier `01`, the driver reports two memories, and a
play taps `SWT11;` then `SWT19;`/`SWT27;` (Programmer's Reference G5, Table 8A).
That half of "full support for the KX2" shipped on 2026-08-09. **Only CW was
broken.**

### Why CW was broken

The app keys CW by toggling a serial control line on **the transport it opened
for CAT**:

```swift
// RadioController.connect
if descriptor.supportsDirectKeying {
    let keyer = CWKeyer(transport: newTransport, config: settings.keyerLineConfig, wpm: settings.wpm)
```

That is right for a K3 and for a QMX, and wrong for a KX, because the three
radios put their key line in different places:

| Radio | Where the computer's key line lands | Source |
| --- | --- | --- |
| K3 / K3S | `CONFIG:PTT-KEY` (menu **103**) maps the **RS-232 port's own** DTR/RTS to CW key and PTT *inside the radio* — one cable does CAT and keying | Pgmrs Ref G5, Table 5 (the menu exists in the K3 table only) |
| QMX | `CW → Key from USB DTR` — same idea, the radio's own USB port | QMX operating manual 1_04_004 |
| **KX2 / KX3** | **Nowhere on the CAT jack.** The key line is a separate physical wire into the **KEY jack** | KX2 Owner's Man B2; KX3 Owner's Man C5 |

The KX2's ACC jack pinout is tip = RX data, ring 1 = TX data, **ring 2 = key
*out*** (for keying amplifiers), sleeve = ground. Its only keying-related pin is
an output. The KX3's ACC2 is likewise a keyline **out** plus a GPIO that can be
configured as a PTT *input* — but not as a CW key, and not on the CAT port.

The KX **is** keyable from a computer, and Elecraft says so explicitly. Menu
entry `CW KEY1`, identical wording in both owner's manuals:

> "Specifies whether the left keyer paddle (tip contact on the KEY jack) is DOT
> or DASH. A third selection, HAND, allows either tip or ring to function as a
> hand key, **or as an input for an external keying device (keyer, computer,
> etc.)**."

So a KX2 with a keying interface wired into KEY, and `CW KEY1 = HAND`, keys
directly. **The operator's KX2 has no such wiring and is not going to grow
any:** its CAT link is a Digirig Mobile in RS-232 mode into the ACC jack, and on
that device the CAT port's lines are *either* TxD/RxD *or* open-collector
RTS/DTR keying drivers — selected by solder jumpers that "can not be changed
operationally" (digirig.net, *Selecting Digirig Mobile Serial Configuration*).
Jumpered for CAT, as this one is, no control line reaches the radio at all.

### What the other logger does, and what actually authorises it

The operator's instruction was "rumlogng does it just fine. research how it does
it." Per Article 1 another logger is **never** authority for a byte; it is a hint
that says which primary source to read. RUMlogNG's own documentation
([*CW Keyer and CW Memories in Transceiver*](https://dl2rum.de/RUMlogNG/docs/en/pages/CAT-CW.html),
fetched 2026-08-22) says:

> "Only some transceivers include a CW keyer that can be controlled via the CAT
> protocol." … "To use the internal keyer, you have to select **Transceiver** as
> CW interface in Preferences→CW." … "The CW speed is adjustable via Menu→CW by
> 2 wpm up or down." … "Press Escape to abort."

That is the hint: **text over CAT to the radio's own keyer**. The authority is
the Programmer's Reference G5, already banked in full, which documents every
byte needed:

- **`KY *[text];`** — "0 to 24 characters. If `*` is a W (for 'wait'), processing
  of any following host commands will be delayed until the current message has
  been sent. This is useful when a KY command is followed by other commands that
  may have side-effects, e.g., KS (keyer speed)." The **blank** form therefore
  does *not* defer, so a `KS` sent during a message reaches it — mid-message
  speed still works, and `KYW` is exactly the deferred-side-effect form
  Article 11 forbids.
- **`TBX`** — "Transmitted Text Read/Text Count; GET only; **KX3/KX2 only**",
  reporting "the count of buffered CW/data characters remaining to be sent
  (**from KY packets**)". Elecraft documenting a KX-only command that counts
  KY-buffered characters is the reference's own confirmation that a KX2 executes
  `KY`.
- **`KY;` (GET)** — "KYn; where n is 0 (CW text buffer not full) or 1 (buffer
  full)."
- **`RX;`** — "Terminates transmit in all modes, including message play and
  repeating messages."

### Why this needs no constitutional amendment

Article 11: "Where the radio's interface exposes hardware key lines, the app keys
it directly and only directly … Where it does not, the radio's own keyer is the
only path, and the driver says so by conforming to `InternalKeyerDriver`."

**The interface the app connects through is the ACC jack, and it exposes no key
line.** The KX therefore selects the internal-keyer arm of Article 11 on the
article's own terms — the same arm the Flex already takes. Nothing is amended,
nothing gains a second path, and
`RadioRegistryTests.testEveryRadioHasExactlyOneWayToSendCW` keeps passing
unchanged.

The article's preference for direct keying is not being overruled either: the K3
keeps it. What changes is the recognition that one descriptor was covering four
radios whose keying interfaces differ, so the descriptor has to split.

## Decisions

1. **Split the descriptor rather than branch inside one driver.** A driver's
   keying path is a *type* property — `InternalKeyerDriver` conformance — so one
   class cannot serve both arms of Article 11. Two descriptors, two drivers.
2. **`elecraft-k3` keeps its id**, so the operator's stored `radioID` and every
   other saved setting survive. The KX arrives as a new id, `elecraft-kx`, and is
   selected once from the radio picker.
3. **Pace on `KY;`, not on `TBX`.** `TBX`'s response prefix is ambiguous in G5 —
   the entry prints "RSP format: TBtts;" but gives the empty case as "TBX00;",
   which cannot both be right. `KY;`'s response is unambiguous. `TBX` is
   documented in the research file with the ambiguity flagged (Article 3) and is
   not parsed. See *Open questions*.
4. **The KX driver never sends `KYW`.** Article 11 names it as the trap.
5. **The freeze is out of scope**, withdrawn by the operator.
6. **The missing key-line UI is not built here.** The operator was offered it and
   asked only that the spec proceed; the README's false claim is corrected
   instead, and the UI is recorded under *Deferred*.

## Design

### 1. Shared Elecraft protocol, extracted first (own commit, no behaviour change)

`ElecraftK3Driver` currently holds three separable things: pure protocol
knowledge, transport plumbing, and two model-specific state machines. The first
two are common to both drivers and move out; the state machines stay with their
own driver.

- **`ElecraftProtocol`** (`enum`, pure statics) — `parseIF`, `parseFA`, `parseMD`,
  `parseKS`, `parseOM`, `parseIC`, and the command builders `cmdSetFrequency`,
  `cmdSetKeyerSpeed`, `cmdSetMode`, `cmdTransmit`, `cmdReceive`, plus the poll
  strings and the `ElecraftModel` enum. Every one already a `static` today, so
  the move is mechanical and the existing `K3ProtocolTests` prove it.
- **`ElecraftSession`** (`final class`) — owns the transport, the 0.5 s poll
  timer, the RX buffer and the split-on-`;` framing including the 4096-byte
  garbage guard, and hands complete responses to a closure. No radio behaviour,
  no model knowledge, so it is testable on its own.

The K3's bank-confirmation state machine — the most safety-critical code in the
driver, and the most heavily tested — **is not touched**. It stays in
`ElecraftK3Driver`.

### 2. `ElecraftK3Driver` narrows to the K3/K3S

Drops the KX branches from `playVoiceMessage` and stops claiming the KX product
identifiers. Everything else — direct keying, the bank machine, `TX;`/`RX;`,
`testDriverNeverSendsKY` — is unchanged.

### 3. `ElecraftKXDriver` — new

Conforms to `RadioDriver`, `InternalKeyerDriver`, `VoiceMessageCapable`,
`TransmitControlCapable`. Uses `ElecraftProtocol` and `ElecraftSession`.

- **CW.** `sendInternalKeyerText(_:)` splits the text into **≤24-character
  chunks** and feeds them to the radio, sending the next chunk only once a
  `KY;` GET answers `KY0;` (buffer not full). `stopInternalKeyer()` drops every
  queued chunk and sends `RX;`.
- **Speed.** `setKeyerSpeed(wpm:)` writes `KS` immediately; the blank `KY` form
  does not defer it, so it reaches a message already sending.
- **Voice.** Two memories; `SWT11;` then `SWT19;`/`SWT27;`; `RX;` stops;
  playback state from `IC` byte `a` bit B2. No banks — a KX has none, and the
  driver must never emit `SWH37;`.
- **Transmit control.** `TX;`/`RX;`, as on the K3.
- **Prosigns** are `MorseCode`'s job for the direct keyer, but on this path the
  radio does the encoding, so the driver passes the characters G5 lists
  (`( KN + AR = BT % AS * SK ! VE`) through untouched.

### 4. Registry

| id | displayName | connection | baud | direct keying |
| --- | --- | --- | --- | --- |
| `elecraft-k3` | Elecraft K3 / K3S | serial | 38400 | **yes** |
| `elecraft-kx` | Elecraft KX3 / KX2 | serial | 38400 | **no** (`InternalKeyerDriver`) |

`defaultRadioID` stays `elecraft-k3`.

### 5. Right-click an F-key to edit it

- `MessagesRow` gains `onEdit: (Int) -> Void`; each F-key button gets a
  `.contextMenu` with one item that opens the Messages editor on that slot.
- The editor opens on the tab the current mode calls for — CW text on CW, the
  Phone tab on phone — and focuses that slot: the CW `TextField` via
  `@FocusState`, or the F-key's memory picker on Phone.
- **Article 7 — keyboard path.** `⌥F1`–`⌥F8` do the same thing. This is the
  first `⌥` chord in `KeyMonitorGate`, so `action`, `isShortcut` and `response`
  gain an `option` parameter, and the existing call sites pass `false`.

### 6. Docs (same commits as the behaviour, Article 6)

- **`docs/research/kx_cw_keying.md`** — the KX2/KX3 keying facts, the KX2-specific
  command inventory from G5, sources with fetch dates, and the open questions.
- **Banked sources** — KX2 Owner's Manual B2 and KX3 Owner's Manual C5 excerpts,
  extracted by script, never hand-typed (Article 2).
- **`docs/PROVENANCE.md`** — both manuals, with URLs, `Last-Modified` and fetch
  date, and what each is authority for.
- **README** — the radio list, the CW-keying section, a *Wiring a KX2/KX3*
  subsection, the keyboard table (`⌥F1`–`⌥F8`), the test count.
- **Two stale README claims fixed in passing**, both found during this
  investigation: "changeable in the radio bar" (there has never been a key-line
  UI) and the QMX paragraph still describing the internal-keyer fallback that
  `14ea6d5` removed.

## Test floor (Articles 12–13)

Driver tests run over `MockSerialTransport` with no hardware.

**`ElecraftKXDriver`** — new `Tests/Hardware/KXProtocolTests.swift`:

- `OM` with product id `01`/`02` → KX2/KX3, two memories; a K3 `OM` is not
  claimed.
- A short message emits exactly one `KY ` packet with the expected text.
- A message longer than 24 characters is split at 24, and **the second chunk is
  not written until a `KY0;` arrives** — proved by injecting `KY1;` first and
  asserting nothing was written.
- `stopInternalKeyer()` writes `RX;` and no further chunk is written afterwards.
- `setKeyerSpeed` writes `KS` **immediately**, mid-message, and the driver
  **never writes `KYW`** — asserted on the wire across a full session, the
  mirror of `testDriverNeverSendsKY`.
- Voice: memory 1 → `SWT11;SWT19;`, memory 2 → `SWT11;SWT27;`, memory 3 → nothing,
  and `SWH37;` never appears.
- A truncated/malformed response does not trap.

**`RadioRegistryTests`** — unchanged and must stay green;
`testEveryRadioHasExactlyOneWayToSendCW` now covers four radios.

**`K3ProtocolTests`** — unchanged except that the KX cases move to the new file.
The K3's whole bank-confirmation suite must stay green through the refactor,
which is what proves the extraction was behaviour-free.

**UI** — `MessagesRow`'s edit callback and the gate's `⌥F`-key mapping are pure
functions and get tests; the context menu itself is not reachable from a test,
so the callback is what is pinned.

## Open questions (Article 3)

1. **`TBX`'s response prefix.** G5 gives both "TBtts;" and "TBX00;" in the same
   entry. Not resolved, and deliberately not depended on — pacing uses `KY;`.
   Re-check against the next revision.
2. **A radio that does not match the chosen entry.** Picking "Elecraft KX3 / KX2"
   with a K3 attached sends `KY` to a K3 (harmless, and it works); picking
   "Elecraft K3 / K3S" with a KX attached leaves CW silent, which is today's
   behaviour. `OM` makes the mismatch detectable, but reporting it needs a
   radio-neutral channel the app does not have, and naming models in the app
   layer is forbidden (Article 10). Left as-is, recorded here.
3. **Whether a KX keys accurately enough over CAT for contest speeds.** The radio
   does the element timing, so this is a firmware property the manual does not
   quantify. Not benchable without the radio on the desk.

## Deferred — real, found here, not fixed here

1. **`keyerLineConfig` has no UI at all.** Nothing under `Sources/UI` touches it,
   so the CW key line (DTR), the PTT line, PTT enable and the lead/tail are
   unreachable. The default happens to match a K3 wired `CONFIG:PTT-KEY =
   RTS-DTR`, which is why nobody noticed. The README claim is corrected here; the
   control itself is a separate change.
2. **One `RadioController` per document window.**
   `MainView` declares `@State private var radio = RadioController()` inside a
   `DocumentGroup`, so every open log window opens its **own** connection to the
   same serial port. Confirmed on the operator's Mac: two file descriptors open on
   `/dev/cu.usbserial-FTELBR55`, both with a non-zero read offset, i.e. two
   drivers polling one port and each `read()` stealing bytes the other needed.
   The operator confirmed multi-window is intended and normal, so the connection
   needs to be shared across windows. Its own design.

## Commit sequence (Article 9 — one radio per commit)

1. `refactor: ElecraftProtocol and ElecraftSession` — behaviour-free, all
   existing tests green.
2. `radio(elecraft-kx): KX3 / KX2, keyed by the radio's own keyer over CAT` —
   driver, descriptor, tests, research, PROVENANCE, README.
3. `keys: right-click an F-key to edit it, and ⌥F1–⌥F8` — row, editor focus,
   gate, tests, README keyboard table.
4. `docs: README corrections` — the key-line claim and the stale QMX fallback
   paragraph.

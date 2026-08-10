# Elecraft on-board voice memories — protocol research

Banked under Constitution Articles 1 and 12: every byte below traces to a named
Elecraft document with a revision and a fetch date. Facts are recorded here
(command syntax, bit positions, memory counts, front-panel behaviour); the
manuals' prose is paraphrased rather than reproduced.

Covers all three models the one `elecraft-k3` descriptor serves. They differ in
memory count and in how a memory is selected, so all three are documented.

## Sources

All fetched **2026-08-09**.

1. **K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5, Feb. 20 2019.**
   <https://ftp.elecraft.com/KX2/Manuals%20Downloads/K3S&K3&KX3&KX2%20Pgmrs%20Ref,%20G5.pdf>
   **The same document and revision `ElecraftK3Driver` already cites** for
   `IF`/`FA`/`MD`/`KS`/`KY`. Authority for every command byte and switch code.
2. **K3 Owner's Manual, Rev. D10.**
   <https://ftp.elecraft.com/K3/Manuals%20Downloads/E740107%20K3%20Owner's%20man%20D10.pdf>
3. **KDVR3 Digital Voice Recorder Option Installation, Rev. C.**
   <https://ftp.elecraft.com/K3S/Manuals%20Downloads/E740130%20KDVR3%20Option%20Installation%20Rev%20C.pdf>
   Authority for the K3's voice memory count.
4. **KX3 Owner's Manual, Rev. C5.**
   <https://ftp.elecraft.com/KX3/Manuals%20Downloads/E740163%20KX3%20Owner's%20man%20Rev%20C5.pdf>
5. **KX2 Owner's Manual, Rev. B2.**
   <https://ftp.elecraft.com/KX2/Manuals%20Downloads/KX2%20owner's%20man%20B2.pdf>
6. **N1MM Logger+ manual** — [Function Keys](https://n1mmwp.hamdocs.com/setup/function-keys/),
   [Interfacing](https://n1mmwp.hamdocs.com/setup/interfacing/),
   [Entry Window](https://n1mmwp.hamdocs.com/manual-windows/entry-window/).
   **Precedent only, never authority (Article 1).** Consulted for interaction
   design, not for a single byte.

Sources 2–5 are load-bearing and not redundant with source 1: the Programmer's
Reference gives the switch codes but never says what a switch *means*, and it
documents no memory counts at all. Selecting a KX memory needs both — the
owner's manual for the two-keystroke sequence, the reference for each keystroke's
code. That is two primary sources combined, not an inference.

## Memory counts and how a memory is played

| Model | Memories | Play sequence | Source |
| --- | --- | --- | --- |
| K3 / K3S | **8**, as 2 banks of 4 | select bank, then tap M1–M4 | 3 |
| KX3 | **2**, up to 15 s each | tap MSG, then tap 1 or 2 | 4 |
| KX2 | **2**, up to 15 s each | tap MSG, then tap 1 or 2 | 5 |

Source 3 states the K3's banks explicitly: holding REC selects bank 1 or 2, four
messages each. Sources 4 and 5 use identical wording for the KX3 and KX2 — two
recordable voice messages, played by tapping MSG then the digit.

### Commands (codes from source 1, Tables 7, 8 and 8A)

| Purpose | K3 / K3S | KX3 / KX2 |
| --- | --- | --- |
| Play memory 1 | `SWT21;` (M1) | `SWT11;` then `SWT19;` (MSG, then 1) |
| Play memory 2 | `SWT31;` (M2) | `SWT11;` then `SWT27;` (MSG, then 2) |
| Play memory 3 | `SWT35;` (M3) | — |
| Play memory 4 | `SWT39;` (M4) | — |
| Memories 5–8 | bank 2, then M1–M4 as above | — |
| Select bank | `SWH37;` (hold REC) | n/a |
| Auto-repeat | `SWH21/31/35/39;` (hold M#) | `SWT11;` then hold the digit |
| **Stop playback** | `RX;` | `RX;` |
| Playing? | `IC;` byte **a** bit **B2** | same |
| Current bank | `IC;` byte **a** bit **B3** | n/a |
| Options fitted | `OM;` letter `D` | n/a — recorder is built in |

The digit codes 19 and 27 are the same on the KX3 (Table 8: PRE=1, ATTN=2) and
the KX2 (Table 8A: PRE/ATTN=1, FIL=2), so one code pair serves both.

`SWT`/`SWH` are SET-only switch emulation. Source 1 warns that successive
commands may need a delay when a later one depends on the switch function having
already executed — which is exactly the K3 bank-then-tap case below.

### `IC` bit extraction

`ICabcde;` — five 8-bit ASCII characters, **B7 of every byte always 1** so no
control character is sent. Byte `a` is index 2 of the response. Playing state is
`(a >> 2) & 1`; current bank is `(a >> 3) & 1`, 0 = bank 1.

### `OM` field layout

Both variants carry a 12-character field. Source 1 prints the K3 example with a
space after `OM`, so a parser must tolerate one.

- **K3/K3S:** `OM APXSDFfLVR--;` — fixed positions, a missing module's letter
  replaced by `-`. Index 0=A(ATU) 1=P(PA) 2=X(XVTR) 3=S(sub RX) **4=D(DVR/KDVR3)**
  5=F 6=f 7=L 8=V 9=R(K3S RF board).
- **KX3/KX2:** `OM APF---TBXI0n;` — the trailing `0n` is a product identifier,
  **n=1 for KX2, n=2 for KX3**. No `D` position exists, and none is needed: on
  both KX models the recorder is built in rather than optional.

Positions 10–11 are therefore the model discriminator: `01`/`02` means KX2/KX3
(2 memories, always present), anything else means K3/K3S (8 memories if `D` is
at index 4, none fitted otherwise). Source 1's `ID` entry confirms `OM` is the
documented way to tell the three apart.

**OPEN QUESTION — the K3's trailing dashes are reserved, not guaranteed empty.**
Source 1 says of the K3/K3S format, in the sentence immediately after its
example: unused dashes are reserved for future module letters *and product ID*.
So Elecraft explicitly anticipates one day populating indices 10–11 on a K3 with
the same kind of product identifier the KX models already carry. Every K3/K3S
example in every revision consulted shows literal dashes there, so the
discriminator is correct for everything that has shipped — but it rests on a
field the manufacturer has reserved the right to fill.

The consequence is not cosmetic: K3 and KX play a memory with *different command
sequences*, so a K3 misread as a KX would be sent bytes from the wrong table.
`parseOM` therefore carries one extra guard beyond what the discriminator
strictly needs — **the KX branch also requires that index 4 is not `D`.** No KX
can have a `D` there (index 4 is a reserved dash in the `APF---TBXI0n` layout),
while a `D` on a K3 means the KDVR3 is fitted. That cannot produce a false
negative on any real KX, and it closes the dangerous half of the future case: a
K3 that one day reports a product ID *and* has a recorder fitted still resolves
as a K3. A recorder-less K3 that reported `01`/`02` would still be misread, but
that radio has no memories to play wrongly.

Re-check this against the current Programmer's Reference each season, per
Article 20.

## The bank is per mode group — CW memories are safe

Source 1, Table 4, footnote §, attached to the MSG-bank bit: the bank number is
stored **separately for CW/FSK-D/PSK-D and for voice/DATA-A/AFSK-A**.

So changing the voice bank cannot disturb the operator's CW message bank. They
are different stored values. This is what makes reaching memories 5–8 safe, and
it is the fact that reverses the first draft of this design, which avoided the
bank command on the mistaken belief that one bank number served both.

## Front-panel semantics

**K3 (sources 2, 3):**

- The KDVR3 option is required for voice messages and for AF REC/AF PLAY.
- Play: tap M1–M4. Cancel: tap REC, or hit the paddle or key.
- Record: tap REC then M1–M4. Hold REC selects the bank.
- Auto-repeat: *hold* M1–M4. Interval from `MAIN:MSG RPT`, 1–255 s.
- Chaining: source 2 describes tapping M1–M4 during playback as chaining another
  message onto the one playing; source 3 describes holding the first until
  REPEAT shows, then tapping the second. Either way, a second press during
  playback appends rather than replaces.
- **PTT:** the `CONFIG:KDVR3` menu entry states that playing DVR transmit
  messages normally asserts PTT automatically; manual PTT (`USE PTT`) is the
  opt-in for footswitch or external sequencing.
- **Caveat:** an M1–M4 switch assigned as a programmable function switch is not
  available for message play.
- Messages may be at least 10 s long (source 3).

**KX3 / KX2 (sources 4, 5):**

- Play: tap MSG, then tap 1 or 2. Cancel: tap XMIT, or hit the paddle/key.
- Record: hold REC, then tap 1 or 2; the existing message is erased first.
- Auto-repeat: tap MSG, then *hold* the digit. Interval from `MENU:MSG RPT`.
- Recording is SSB-mode only (source 5 says so explicitly).

Source 1's Table 4 footnote is also what establishes that M1–M4 address
*different* buffers depending on the mode group: CW text memories in CW, voice
recordings in a voice mode.

## N1MM precedent (source 6 — design only, not authority)

- CW, SSB and digital function-key messages are **separate sets in separate
  files**, switched automatically on the current mode.
- Native SSB voice keying plays **user-recorded WAV files from the computer**.
- **External (LPT) DVK** support is the slot model: F1–F7 trigger memories 1–7,
  Esc stops playback. Some DVKs have only 4 memories, in which case only F1–F4
  trigger.
- **Radio-internal DVKs are explicitly not supported by the N1MM team.** The
  documented workaround is a hand-written `{CAT1ASC …}` macro in a function key,
  with these stated consequences: Esc interrupts only if that radio's abort was
  implemented for it; auto-CQ repeat intervals must be hand-tuned because
  nothing reports the end of a message; and N1MM cannot manage PTT for a radio's
  built-in recorder because it cannot know when playback finished, so such
  radios must use VOX.

**All three are limits of a generic architecture, not of these radios**, and
sources 1–5 close each one: `RX;` aborts, `IC;` bit B2 reports the end of
playback, and on the K3 the radio asserts PTT itself.

**The PTT point is banked for the K3 only.** Source 2's `CONFIG:KDVR3` entry is
where it comes from; sources 4 and 5 make no PTT claim for the KX3 or KX2 either
way. Do not restate it as a property of the family — it is one menu entry in one
manual. Whether a KX needs VOX for message play is an open question nobody has
had to answer yet, because the app does not manage PTT for any of them.

## Engine shapes to watch

1. **M1–M4 are mode-dependent.** In CW they play CW text memories. Playback must
   be gated on the radio actually reporting a voice mode, or an F-key would key
   a CW memory instead.

   **Known limitation, accepted 2026-08-09.** The gate is UI-side, not the
   driver's, and it is stale-tolerant: `EntryFlow.transmission` routes on
   `context.modeClass`, sourced from `radio.radioState?.rawMode`, which the 0.5 s
   poll can serve up to that much stale. `ElecraftK3Driver.playVoiceMessage`
   itself taps `SWT21/31/35/39;` (or the KX MSG sequence) on request with no
   mode check of its own — so a front-panel mode change from phone to CW,
   followed by an F-key press, both inside one poll interval, could key a CW
   text memory instead of the voice memory the operator meant. Accepted rather
   than closed: it takes both a mode change *and* a keypress inside that
   sub-0.5 s window, and the consequence is an unexpected CW transmission, not
   a wrong voice recording on the air — the same wrong-audio-is-worse-than-
   silence asymmetry item 2's bank confirmation leans on, just not extended
   here. This is that same poll staleness the bank path explicitly refuses to
   trust, applied inconsistently: the bank path holds a tap until `IC` confirms
   it, this gate does not. Closing it the same way would cost a mode
   confirmation round trip before every play — on the hot path every F-key
   press already walks.
2. **Never play the wrong memory.** Reaching K3 memories 5–8 means changing bank
   first, and `IC;` is polled at 0.5 s, so the cached bank may be stale. The
   sequence must *confirm* the bank before tapping, and **abandon the play rather
   than transmit an unconfirmed memory** — wrong audio on the air is worse than
   silence.
3. **Chaining already matches this app.** `CWKeyer` queues rather than replaces,
   and N1MM stacks function keys the same way. A second press appends in both
   modes; no correction needed.
4. **`IC;` replaces the duration estimate.** For CW, `RadioController` holds the
   TX badge for an estimated send time because a rig in QSK drops its TX flag.
   Voice playback has a real signal and must not inherit the estimate.
5. **Counts are discovered, never hard-coded.** 8, 2 or 0 comes from `OM;` at
   runtime. A count written into the app layer would be a model constant in
   exactly the place Article 10 forbids one.

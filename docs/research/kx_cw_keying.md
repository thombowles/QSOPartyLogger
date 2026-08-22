# Keying a KX2 / KX3 from the computer, and the KX-specific command set

Banked under Constitution Articles 1 and 12. Every command byte below traces to
the **K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5, Feb. 20 2019**, already
banked in full as [`k3_programmers_reference_g5.txt`](k3_programmers_reference_g5.txt);
every front-panel and jack fact traces to the model's own owner's manual.

## Sources

| # | Source | Authority for | Banked as |
| --- | --- | --- | --- |
| 1 | **K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5**, Feb. 20 2019. <https://ftp.elecraft.com/KX2/Manuals%20Downloads/K3S&K3&KX3&KX2%20Pgmrs%20Ref,%20G5.pdf> — fetched 2026-08-09 | every command byte: `KY`, `KS`, `RX`, `TBX`, `OM`, `IC`, `SWT`/`SWH` Table 8A, `MN` Table 6A | [`k3_programmers_reference_g5.txt`](k3_programmers_reference_g5.txt) |
| 2 | **KX2 Owner's Manual, Rev. B2**. <https://ftp.elecraft.com/KX2/Manuals%20Downloads/KX2%20owner's%20man%20B2.pdf> — `Last-Modified` Mon 27 Mar 2023 18:52:53 GMT, fetched 2026-08-22 | the KEY jack, `CW KEY1`, the ACC pinout, the DVR, `VOX MD` | [`kx2_owners_b2_excerpts.txt`](kx2_owners_b2_excerpts.txt) |
| 3 | **KX3 Owner's Manual, Rev. C5**. <https://ftp.elecraft.com/KX3/Manuals%20Downloads/E740163%20KX3%20Owner's%20man%20Rev%20C5.pdf> — `Last-Modified` Thu 16 Nov 2017 01:06:57 GMT, fetched 2026-08-22 | the same four facts for the KX3 | [`kx3_owners_c5_excerpts.txt`](kx3_owners_c5_excerpts.txt) |
| 4 | **RUMlogNG documentation**, *CW Keyer and CW Memories in Transceiver*. <https://dl2rum.de/RUMlogNG/docs/en/pages/CAT-CW.html> — fetched 2026-08-22 | **nothing.** Precedent only (Article 1) — it named the mechanism to go and look up in source 1 | — |
| 5 | **digirig.net**, *Digirig Mobile* and *Selecting Digirig Mobile Serial Configuration*. <https://digirig.net/product/digirig-mobile/> — fetched 2026-08-22 | the operator's CAT interface, and why no control line reaches his radio | — |

Sources 2 and 3 are not redundant with source 1: the Programmer's Reference
documents no jack pinouts and no menu *meanings*, and the whole keying question
turns on which jack carries what.

## The question: can a KX2 be keyed from a serial control line?

**Yes — into the KEY jack, never over the CAT cable.** Source 2, menu entry
`CW KEY1` (identical wording in source 3):

> "Specifies whether the left keyer paddle (tip contact on the KEY jack) is DOT
> or DASH. A third selection, HAND, allows either tip or ring to function as a
> hand key, **or as an input for an external keying device (keyer, computer,
> etc.)**."

So the radio explicitly accepts a computer as a keying input. What it does *not*
have is the K3's trick of routing its own serial port's handshake lines to the
key line internally:

| | K3 / K3S | KX2 / KX3 |
| --- | --- | --- |
| Maps DTR/RTS to CW key & PTT in firmware | **`CONFIG:PTT-KEY`, menu 103** | **no such menu** — source 1's Table 5 has it, Tables 6 and 6A do not |
| CAT jack | RS-232 (or KUSB), and it carries the key line | ACC: tip = RX data, ring 1 = TX data, **ring 2 = key *out*** (amplifiers), sleeve = gnd |
| Key input reachable by the app's CAT cable | yes | **no** |

The KX3's ACC2 is likewise a keyline **output** plus a GPIO that `ACC2 IO` can
make a PTT *input* — never a CW key, and never on the CAT port.

### Why this app keys the KX over CAT instead

The operator's KX2 reaches the Mac through a **Digirig Mobile in RS-232 mode,
into the ACC jack**. On that device (source 5) the CAT port's lines are *either*
TxD/RxD *or* open-collector RTS/DTR keying drivers, selected by solder jumpers
that "can not be changed operationally". Jumpered for CAT, no control line
reaches the radio at all — so direct keying cannot work on this station without
new hardware, and the app must key over CAT.

That is what RUMlogNG does on the same radio (source 4: "Only some transceivers
include a CW keyer that can be controlled via the CAT protocol … select
Transceiver as CW interface"). Source 4 is precedent only; the bytes come from
source 1.

**Constitutionally this needs no amendment.** Article 11 keys directly "where the
radio's interface exposes hardware key lines". The interface the app connects
through is the ACC jack, which exposes none — so the KX takes the article's
`InternalKeyerDriver` arm, exactly as the Flex does.

## The CW-over-CAT path, from source 1

| Purpose | Command | The reference's own words |
| --- | --- | --- |
| Send text | `KY *[text];` | "`*` is normally a BLANK and `[text]` is 0 to 24 characters." |
| **Do not** defer | never `KYW` | "If `*` is a W (for 'wait'), processing of any following host commands will be delayed until the current message has been sent … e.g., KS (keyer speed)." |
| Buffer state | `KY;` (GET) | "`KYn;` where n is 0 (CW text buffer not full) or 1 (buffer full)." |
| Speed | `KSnnn;` | "nnn is 008-050 (8-50 WPM)" |
| Abort | `RX;` | "Terminates transmit in all modes, including message play and repeating messages." |
| Prosigns | in the text | `( KN` `+ AR` `= BT` `% AS` `* SK` `! VE` |
| Kill transmission | `^D` (ASCII 04) | "Quickly terminates transmission; use with CW-to-DATA." |

**The blank `KY` form is what makes mid-message speed work** — since it does not
defer following commands, a `KS` sent while a message is going out reaches that
message. This is the same sentence Article 11 already cites, read the other way
round: `KYW` is the trap, plain `KY` is the feature.

**That a KX2 executes `KY` at all** is settled by source 1's own `TBX` entry —
"Transmitted Text Read/Text Count; GET only; **KX3/KX2 only**", reporting "the
count of buffered CW/data characters remaining to be sent (**from KY packets**)".
A KX-only command that counts KY-buffered characters could not exist if the KX
did not process `KY`.

### Pacing: `KY;`, not `TBX`

`TBX` looks like the better gauge — 00-40 characters remaining, against the K3's
single capped digit — but **its response prefix is ambiguous in G5.** The entry
prints "RSP format: TB*tts*;" and then gives the empty case as "TBX00;". Those
cannot both be right, and guessing which is a parser that silently never matches.
So the driver paces on `KY;`, whose response is unambiguous, and does not parse
`TBX`. **Open question — re-check against the next revision.**

## KX2-specific commands in the Programmer's Reference

Source 1's Table 1 marks `(*)` "not functionally applicable to KX3/KX2" and
`(**)` "KX3/KX2 only". Collected here because the app serves the KX from its own
driver now, and because a K3 assumption that is wrong on a KX is exactly the
"wrong number that looks right" the constitution exists to prevent.

**KX3/KX2 only:**

| Command | What it is |
| --- | --- |
| `TBX` | Transmitted text read / count, GET only — the KY buffer gauge (see above) |
| `PO` | Actual power output, tenths of a watt in QRP mode |
| `AK` | ATU network values (L/C bitmaps), GET only |
| `MQ` | 16-bit direct menu parameter access — `TXCRNUL` only at present |
| `EL` | Error logging on/off — the radio reports `ERR xxx` and warnings to the PC |
| `IO`, `KE`, `KT`, `BC` | Internal use only |

**Same command, different behaviour on a KX2:**

| Command | The difference |
| --- | --- |
| `OM` | KX format `APF---TBXI0n` — `0n` is the product identifier, **`01` = KX2**, `02` = KX3. No `D` position: the voice recorder is built in, not an option module |
| `MD` | "FM mode does not apply to the KX2" — `MD4` is a K3/KX3 mode only |
| `VX` | GET **and** SET on a K3; **GET only on the KX2 and KX3**. "KX2 only: In SSB mode, the VOX state returned by VX applies only to the external mic" |
| `XF` | "The KX2 has only DSP filters, so XF always returns `XF1;`" |
| `SWT`/`SWH` | **Table 8A** is the KX2's switch map, and it is not the KX3's Table 8 or the K3's Table 7 |
| `MN` | **Table 6A** is the KX2's menu numbers; G5's own change note records that `MN143` is invalid on a KX2 (no NR menu entry) and that "NR can still be turned on/off on the KX2 using `SWH19;`" |
| `MP` | The bit-field special cases are "KX3 and KX2 only" — including `CW KEY1: bit0=tip is dot/dash; bit1=paddle/hand-key` |
| `DB` | KX2 special displays differ, and add `09` = amp hours |
| `PC` | KX2 range is 000-012 (80-20 m) / 000-015 (160, 15-6 m), or 000-110 with a KXPA100 |
| `RG` | On a KX2, 250 = maximum RF gain |
| `IC` byte `e` | Bits B1 and B0 carry KX3/KX2-only meanings (VFOB LED; Fast Play in effect) |
| `RV` | `RVA`, `RVR`, `RVF` name K3-only modules |

**Not available on a KX2 — and this one matters:**

`DE` (command processing delay) is **K3/K3S only**. Source 1 warns that switch
emulation "commands must sometimes be followed by a delay if successive commands
expect the switch function to have been executed", and `DE` is how a K3 macro
inserts one. A KX2 has no such command, so the two-tap voice-memory sequence
(`SWT11;` then `SWT19;`/`SWT27;`) has no documented way to space its taps from
the host. It has worked on the operator's KX2 since 2026-08-09; recorded here as
a **known risk**, not a known defect.

## Switch codes this app uses (Table 8A, KX2)

Verified identical to the KX3's Table 8 for the codes used, which is what lets
one driver serve both:

| Function | Code | KX2 switch (Table 8A) | KX3 switch (Table 8) |
| --- | --- | --- | --- |
| MSG | `SWT11;` | `MSG` (hold = REC) | `MSG (<-)` (hold = REC) |
| digit 1 | `SWT19;` | `PRE (/ATTN) (1)` | `PRE (1)` |
| digit 2 | `SWT27;` | `FIL (2)` | `ATTN (2)` |

## Front-panel semantics (sources 2 and 3)

- **Two CW keying inputs**, both physical: the KEY jack and an attached KXPD2
  (KX2) / KXPD3 (KX3) paddle. Configured by `CW KEY1` and `CW KEY2`; either can
  be set to `HAND`.
- **`VOX MD` defaults to `ON` in CW**, giving "hit-the-key transmit" — so a key
  line alone transmits, with no PTT line needed. (In voice and AF-data modes it
  defaults `OFF`.)
- **DVR: two messages, up to 15 s each.** Record by holding `REC` then tapping 1
  or 2; play by tapping `MSG` then the digit; cancel with `XMIT` or the paddle.
  Auto-repeat by *holding* the digit, interval from `MENU:MSG RPT`.
- **Recording is SSB-mode only** on both radios.
- The KX2's separate **CW/DATA message memories** (3 × 250 characters) are a
  different feature from the DVR and are not used by this app.

## Bench, 2026-08-22

**The CAT keying path was tried on a real KX2 the day it was written, and it
works.** The operator's station: KX2, Digirig Mobile jumpered for RS-232 into the
ACC jack, `/dev/cu.usbserial-21220`, radio picked as *Elecraft KX3 / KX2*. CW
from the F-keys goes out.

That answers the only question a mock transport could never reach — whether a KX2
actually executes the `KY` packets this driver builds. It does.

**What the bench did *not* separately exercise**, so the entries below stay open:
Esc against a message already sending (open question 2), the two-tap voice-memory
sequence (open question 3), and keying at the top of the speed range (open
question 4). None of them is known to be broken; none was deliberately tested.

## Open questions

1. **`TBX`'s response prefix** — G5 gives two incompatible forms in one entry.
   Not depended on; re-check next revision.
2. **Whether `RX;` empties the KY buffer, or only stops transmitting.** The
   entry says it "terminates transmit in all modes, including message play and
   repeating messages" — which is about *transmit*, and says nothing about text
   already handed over and not yet sent. `ElecraftKXDriver.stopInternalKeyer`
   therefore drops its own queue as well, so nothing further of ours reaches the
   radio; whether a packet already inside the radio is discarded is unverified.
   G5 documents two other stops that might settle it — `^D` (EOT, ASCII 04),
   "quickly terminates transmission", and the `@` character, which "normally
   terminates any CW message (via KY or manual send)" but is remapped to a
   prosign by `CONFIG:CW WGHT`. Neither is used, because neither is
   unconditional. Needs the radio on the desk.
3. **Tap spacing without `DE`.** No documented host-side delay exists on a KX2
   for successive `SWT` commands. Working in practice; unquantified.
4. **Keying accuracy at contest speeds** over CAT. The radio does the element
   timing and the manual does not quantify it. Keying works on the air
   (see *Bench* above); how it holds up at the top of the range, and whether a
   chunk boundary is audible at speed, is unmeasured.
5. **A radio that does not match the selected entry.** `OM` makes the mismatch
   detectable, but reporting it needs a radio-neutral channel the app does not
   have, and naming a model in the app layer is forbidden (Article 10).

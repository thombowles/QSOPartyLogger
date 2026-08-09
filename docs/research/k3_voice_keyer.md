# K3 internal voice keyer (KDVR3) — protocol research

Banked under Constitution Articles 1 and 12: every byte below traces to a named
Elecraft document with a revision and a fetch date. Facts are recorded here
(command syntax, bit positions, front-panel behaviour); the manuals' prose is
paraphrased rather than reproduced.

## Sources

1. **Elecraft K3S/K3/KX3/KX2 Programmer's Reference, Rev. G5, Feb. 20 2019.**
   <https://ftp.elecraft.com/KX2/Manuals%20Downloads/K3S&K3&KX3&KX2%20Pgmrs%20Ref,%20G5.pdf>
   Fetched 2026-08-09. **This is the same document and revision
   `ElecraftK3Driver` already cites** for `IF`/`FA`/`MD`/`KS`/`KY`, so the
   driver's provenance note needs no new revision — only the new commands.
2. **Elecraft K3 Owner's Manual, Rev. D10.**
   <https://ftp.elecraft.com/K3/Manuals%20Downloads/E740107%20K3%20Owner's%20man%20D10.pdf>
   Fetched 2026-08-09. Authority for front-panel semantics — what M1–M4 *mean* —
   which the Programmer's Reference does not state.
3. **N1MM Logger+ manual** — [Function Keys](https://n1mmwp.hamdocs.com/setup/function-keys/),
   [Interfacing](https://n1mmwp.hamdocs.com/setup/interfacing/),
   [Entry Window](https://n1mmwp.hamdocs.com/manual-windows/entry-window/).
   Fetched 2026-08-09. **Precedent only, never authority (Article 1).** Consulted
   for interaction design, not for a single byte.

## Commands (source 1)

| Purpose | Command | Where in source 1 |
| --- | --- | --- |
| Play voice message 1–4 | `SWT21;` `SWT31;` `SWT35;` `SWT39;` | Table 7, M1–M4 **TAP** |
| Auto-repeat message 1–4 | `SWH21;` `SWH31;` `SWH35;` `SWH39;` | Table 7, M1–M4 **HOLD** (M#-RPT) |
| Switch message bank | `SWH37;` | Table 7, REC hold (MSG Bank) |
| **Stop playback** | `RX;` | `RX` entry — terminates transmit in all modes, message play and repeating messages included |
| Playback state | `IC;` → byte **a**, bit **B2** | Table 4: 1 = MSG is playing, 0 = not |
| Current bank | `IC;` → byte **a**, bit **B3** | Table 4: 0 = bank 1, 1 = bank 2 |
| Is the KDVR3 fitted? | `OM;` → letter `D` | `OM` entry: "D = DVR (KDVR3)" |

`SWT`/`SWH` are SET-only switch emulation: `SWTnn;` taps, `SWHnn;` holds.
Source 1 warns that successive commands may need a delay when a later command
depends on the switch function having executed.

### `IC` bit extraction

`ICabcde;` — five 8-bit ASCII characters. **B7 of every byte is always 1** so
that no control character is sent. Byte `a` is index 2 of the response. Playing
state is therefore `(a >> 2) & 1`.

### `OM` field layout

Both variants carry a 12-character field. Source 1 prints the K3 example with a
space after `OM`, so a parser must tolerate one.

- **K3/K3S:** `OM APXSDFfLVR--;` — fixed positions, a missing module's letter
  replaced by `-`. Index 0=A(ATU) 1=P(PA) 2=X(XVTR) 3=S(sub RX) **4=D(DVR/KDVR3)**
  5=F 6=f 7=L 8=V 9=R(K3S RF board).
- **KX3/KX2:** `OM APF---TBXI0n;` — the trailing `0n` is a product identifier,
  **n=1 for KX2, n=2 for KX3**. There is no `D` position at all.

So positions 10–11 discriminate the models: `01`/`02` means KX2/KX3, anything
else means K3/K3S. Source 1's `ID` entry confirms `OM` is the documented way to
tell the three apart.

## Front-panel semantics (source 2)

From the CW/message-controls section and the `CONFIG:KDVR3` menu entry:

- **The KDVR3 option is required for voice messages** and for AF REC/AF PLAY.
- **8 message buffers, 2 banks of 4.** Holding REC switches banks.
- **Play:** tap M1–M4. Cancel by tapping REC, or by hitting the paddle or key.
- **Auto-repeat:** *hold* M1–M4 rather than tap. The interval comes from
  `MAIN:MSG RPT`, 1–255 seconds.
- **Chaining:** tapping M1–M4 *during* playback chains another message onto the
  one already playing.
- **PTT:** the `CONFIG:KDVR3` entry states that playing DVR transmit messages
  normally asserts PTT automatically; manual PTT (`USE PTT`) is the opt-in for
  footswitch or external sequencing.
- **Caveat:** an M1–M4 switch assigned as a programmable function switch is not
  available for message play.

Source 1's Table 4 footnote — MSG bank number is stored separately for
CW/FSK-D/PSK-D versus voice/DATA-A/AFSK-A — is what establishes that M1–M4
address *different* buffers depending on the mode group: CW text memories in CW,
DVR recordings in a voice mode.

## N1MM precedent (source 3 — design only, not authority)

- CW, SSB and digital function-key messages are **separate sets in separate
  files**, switched automatically on the current mode.
- Native SSB voice keying plays **user-recorded WAV files from the computer**,
  not the radio's recorder.
- **External (LPT) DVK** support is the slot model: F1–F7 trigger memories 1–7,
  Esc stops playback. Some DVKs have only 4 memories, in which case only F1–F4
  trigger.
- **Radio-internal DVKs are explicitly not supported by the N1MM team.** The
  documented workaround is hand-writing a `{CAT1ASC …}` macro into a function
  key, with these stated consequences:
  - Esc interrupts only if that radio's abort was implemented in N1MM for it;
    otherwise the operator uses the radio's front panel.
  - Auto-CQ repeat intervals must be hand-tuned, because nothing reports the end
    of a message.
  - N1MM cannot manage PTT for a radio's built-in DVK, since it cannot know when
    playback finished — such DVKs must use VOX.

**All three are limits of N1MM's generic architecture, not of the K3**, and
sources 1 and 2 close each one: `RX;` aborts, `IC;` bit B2 reports the end of
playback, and the radio asserts PTT itself.

## Engine shapes to watch

1. **M1–M4 are mode-dependent.** In CW they play CW text memories. Tapping them
   while the radio is in CW would key a CW memory, not a recording. Playback must
   be gated on the radio actually reporting a voice mode.
2. **Chaining already matches this app.** `CWKeyer` queues a second message
   rather than replacing it, and N1MM stacks function keys the same way. The
   K3's chaining behaviour needs no correction — pressing F1 twice queues two,
   in both modes.
3. **Never send the bank command.** `SWH37;` would leave the radio in whichever
   bank it last toggled to, and the bank is shared with the operator's CW
   memories. Four slots, bank 1, no bank command emitted.
4. **`IC;` replaces the duration estimate.** For CW, `RadioController` holds the
   TX badge for an estimated send time because a rig in QSK drops its TX flag.
   Voice playback has a real signal, so voice must not inherit the estimate.
5. **Availability is runtime, not static.** The KDVR3 is an option. A descriptor
   flag would claim a capability the radio may not have; `OM;` is asked at
   connect and the answer reported.

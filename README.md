# QSO Party Logger

A Mac-native contest logger for state QSO parties. It knows every party's own
rules — counties, points, multipliers, bonus stations — so the score in the
sidebar is the score you claim. County lines log the way sponsors ask for them,
CW keys straight off the serial port, and spots arrive with the county attached.

Everything is reachable from the keyboard: logging, QSY, mode changes, messages
and spot-hopping all happen without leaving the entry field.

Requires macOS 15 or later. SwiftUI, Swift 6. Built for KE5CW.

---

## Quick start

1. **New log** → Contest Setup opens. Pick your party, enter your callsign, and
   say where you are operating from.
2. Optional: pick your radio in the radio bar (Elecraft K3 family or QRP Labs
   QMX on serial, FlexRadio 6000/8000 over the network) and hit **Connect**.
3. Optional: click the toolbar antenna to connect a DX cluster, and ⌘B for the
   band map.
4. Type a call, press **Space**, type the exchange, press **Return**. That's a
   QSO.
5. **⌘E** exports ADIF, **⇧⌘E** exports Cabrillo, whenever you're ready.

The log saves itself. Every QSO change is written straight to disk, so a crash
never costs contacts.

## Supported parties

All 50 below are bundled, each built from the sponsor's own rules — with the
official county list wherever the party has one. **Every US state and regional
QSO party running from 2026-07-24 through 2026-12-31 is included**, and the
season's earlier parties are in as well; three parties remain to be added, plus
the Canadian Prairies, which is blocked because its districts are published
only as images. Two four-hour QRP sprints — the NJQRP Skeeter Hunt and the ARS
Flight of the Bumblebees — join the two NAQPs as the catalogue's non-state
contests.

Dates are the UTC start of each running; "12 h each" means two separate
runnings of that length.

| Party | 2026 | Window | Multipliers |
| --- | --- | --- | --- |
| North American QSO Party, CW | Jan 10 + Aug 1 | 12 h each | 46 NA entities |
| North American QSO Party, SSB | Jan 17 + Aug 15 | 12 h each | 46 NA entities |
| Vermont QSO Party | Feb 7 | 48 h | 14 counties |
| Minnesota QSO Party | Feb 7 | 10 h | 87 counties |
| British Columbia QSO Party | Feb 7 | 20 h | 43 districts |
| South Carolina QSO Party | Feb 28 | 11 h | 46 counties |
| North Carolina QSO Party | Mar 1 | 10 h | 100 counties |
| Oklahoma QSO Party | Mar 14 | 20 h | 77 counties |
| Idaho QSO Party | Mar 14 | 24 h | 44 counties |
| Wisconsin QSO Party | Mar 15 | 7 h | 72 counties |
| Virginia QSO Party | Mar 21 | 26 h | 133 counties + cities |
| Louisiana QSO Party | Apr 4 | 12 h | 64 parishes |
| Mississippi QSO Party | Apr 4 | 12 h | 82 counties |
| Missouri QSO Party | Apr 11 | 20 h | 115 counties |
| New Mexico QSO Party | Apr 11 | 12 h | 33 counties |
| Georgia QSO Party | Apr 11 | 20 h | 159 counties |
| North Dakota QSO Party | Apr 11 | 24 h | 53 counties |
| Michigan QSO Party | Apr 18 | 12 h | 83 counties |
| Ontario QSO Party | Apr 18 | 17 h | 50 areas |
| Quebec QSO Party | Apr 19 | 11 h | 17 regions |
| Nebraska QSO Party | Apr 25 | 36 h | 93 counties |
| Florida QSO Party | Apr 25 | 20 h | 67 counties |
| **Combined:** Indiana + 7QP + New England + Delaware | May 2 | 35 h | 422 codes, 16 states |
| 7th Call Area QSO Party | May 2 | 18 h | 259 counties |
| Indiana QSO Party | May 2 | 12 h | 92 counties |
| Delaware QSO Party | May 2 | 31 h | 3 counties |
| New England QSO Party | May 2 | 20 h | 68 counties |
| Arkansas QSO Party | May 16 | 12 h | 75 counties |
| Kentucky QSO Party | Jun 6 | 12 h | 120 counties |
| Alabama QSO Party | Jul 25 | 12 h | 67 counties |
| ARS Flight of the Bumblebees | Jul 26 + Sep 20 | 4 h each | Bumblebees worked |
| Maryland-DC QSO Party | Aug 8 | 14 h | 25 jurisdictions |
| NJQRP Skeeter Hunt | Aug 16 | 4 h | S/P/Cs |
| Hawaii QSO Party | Aug 22 | 36 h | 14 districts |
| Ohio QSO Party | Aug 22 | 12 h | 88 counties |
| Kansas QSO Party | Aug 29 | 18 h | 105 counties |
| Tennessee QSO Party | Sep 6 | 10 h | 95 counties |
| Colorado QSO Party | Sep 12 | 14 h | 64 counties |
| New Jersey QSO Party | Sep 12 | 12 h | 21 counties |
| Iowa QSO Party | Sep 19 | 12 h | 99 counties |
| Texas QSO Party | Sep 19 | 18 h | 254 counties |
| New Hampshire QSO Party | Sep 19 | 22 h | 10 counties |
| Washington Salmon Run | Sep 19 | 23 h | 39 counties |
| Maine QSO Party | Sep 26 | 24 h | 16 counties |
| California QSO Party | Oct 3 | 30 h | 58 counties |
| Arizona QSO Party | Oct 10 | 14 h | 15 counties |
| Pennsylvania QSO Party | Oct 10 | 21 h | 67 counties |
| South Dakota QSO Party | Oct 10 | 24 h | 66 counties |
| New York QSO Party | Oct 17 | 12 h | 62 counties |
| Illinois QSO Party | Oct 18 | 8 h | 102 counties |

**Two things worth knowing before you enter.** Most parties carry at least one
rule this app cannot express exactly — a ×1.5 power multiplier, a tiered rare-
county bonus — and Contest Setup tells you which, in orange, *before* the
contest starts. And the combined May weekend is one log for four contests: it
logs and exports correctly and shows what each of the four would count, but it
deliberately gives no single score, because the four sponsors score differently.

Per-party detail — what's unusual about each, and every known limitation — is in
[docs/PARTIES.md](docs/PARTIES.md). Sources and fetch dates are in
[docs/PROVENANCE.md](docs/PROVENANCE.md).

## Keyboard reference

Press **⌘/** (or Help › Keyboard Shortcut Hints) and every button wears its key
as a small badge — the toolbar, the message row, Log, WPM, the sidebar, the
editors — while a legend under the message buttons lists the keys that have no
button and shows the last key the app received. Press ⌘/ again to hide them.

| Keys | Action |
| --- | --- |
| `Enter` | Log the QSO (or send the next ESM message, or run a typed QSY command). In the empty call field under ESM with a ghost call showing, take it — call and county — and call him |
| `Space` | In an empty call field showing a ghost call: take it (call and county) and stay put. Otherwise cycle Call → Exchange → Call — via QSO number and Name ahead of the exchange, and the member number/power (Skeeter #, BB #) after it, where the party uses them. Signal reports are stepped over |
| `Tab` | Walk every field, reports included — landing in one selects the S digit, so 599 → 579 is one keystroke |
| `Tab` to **P2P park(s)** | During a POTA activation, the other station's park reference(s). Deliberately outside the `Space` cycle — most contacts aren't park-to-park — so `Space` from it returns to the call |
| `F12` | Wipe the entry fields and start over |
| `F1`–`F8` | Send the message in that slot (Run or S&P set) — CW text on CW; on phone, the voice memory recorded on this Mac (or the radio's own, if that source is chosen). The button shows what it will send: the expanded text, or `M4 AGN?`. A second key during a recording replaces it |
| `Esc` | Abort instantly — a CW message mid-character, a recording mid-playback (audio stops and the radio unkeys together), or a voice memory — stop repeat-CQ, close an open sheet — or, in the park picker's search box, clear it and close the results |
| `⇧⌘V` | Open the Messages editor on the Phone tab — the voice recorder |
| `⌘1`–`⌘8` | In the Phone tab: record memory M1–M8; the same key (or the button) stops. Stops by itself at 30 s |
| `⌥⌘1`–`⌥⌘8` | In the Phone tab: play memory M1–M8 back on the Mac (not the radio) |
| `↑` / `↓` | In the park picker: move through the results; `Return` adds the highlighted park |
| Any key | While repeat-CQ is running: pause the loop and abort the CQ on the air, then do the key's own job. The mode stays armed (the button turns orange, `Repeat CQ ⏸`) — `F1`, the CQ button or ESM's `Return` start it repeating again |
| `⌘=` / `⌘-` | CW speed ±2 WPM — takes effect mid-message (syncs to the radio) |
| `⌘↓` / `⌘↑` | Tune to the previous / next unworked spot on the band — `⌘↑` goes up the band map |
| `⇧⌘←` / `⇧⌘→` | Nudge the VFO down / up 100 Hz (a burst of presses adds up; disconnected, the band-map cursor moves instead) |
| `⌘R` | Toggle Run / Search & Pounce (the knob also switches: off the CQ frequency → S&P, back onto it → Run) |
| `⌘J` | Jump back to your CQ run frequency |
| `⌘B` | Toggle the band map window |
| `⇧⌘S` | Spot — yourself in Run, the call field in S&P — to the DX cluster, the QSO Party Hub and POTA, whichever apply, from one sheet |
| `⌘1` / `⌘2` / `⌘3` | In the spot sheet: tick or untick the cluster / the hub / POTA; `Return` posts to every ticked network at once |
| `⇧⌘R` | Restore the party's default CW messages (Messages editor) |
| `⌘E` / `⇧⌘E` | Export ADIF / Cabrillo |
| `⇧⌘M` | Expand / collapse every multiplier list in the score sidebar |
| `⇧⌘C` | Copy the score summary as text (also on the score card's right-click menu) |
| `⇧⌘A` | Collapse / expand the Advisor |
| `⌥⌘A` | Toggle what the Advisor optimises: Score ↔ QSOs |
| `⌘A` | Select every row in the log (`⇧`-click for a range, `⌘`-click for scattered rows) |
| `⌘.` | Dismiss the spots-already-used badge for this sitting |
| `⌘/` | Shortcut hints on / off (also Help › Keyboard Shortcut Hints): every button wears its key, and a legend under the message buttons lists the keys that have no button, with a "last key" readout of what the app received |
| `14025`, `7.040`, `40M`, `222`, `CW`, `SSB` in the call field | QSY, change band, change mode |

In the Contest Dashboard (**⌘⇧D**): `⌘[` / `⌘]` change year, `⌘R` re-reads the
history file, `Return` opens that contest's log, and `⌘E` / `⇧⌘E` export it.

While repeat-CQ is running, **any key does what `Esc` does**: the loop pauses and
the CQ on the air comes down mid-character, so the moment you start typing his
call you are not talking over him. A key that has its own job still does it,
after the abort — `F2` replaces the CQ with the exchange, `F1` starts the CQ
over — and an ordinary letter still lands in the call field. Repeat CQ is a
*mode*, the way N1MM's Alt+R is: pausing leaves it armed (the button turns
orange, `Repeat CQ ⏸`), so after the QSO `F1`, the CQ button or ESM's `Return`
start it repeating again from the top — no click on the toggle between
contacts. Only the toggle itself, a mode change or a disconnect turn the mode
off. With repeat off nothing is cut short: typing the next call while an `F2`
exchange goes out lets the exchange finish.

These keys belong to the log window with focus. While a sheet is open it owns
the keyboard — `F1`–`F8` do not transmit, so revising F2 and pressing it never
keys the old message. `Esc` still aborts CW instantly either way.

**If the F-keys do nothing but the buttons work**, the keyboard is almost
certainly sending its F row as media keys — brightness, Mission Control,
backlight — which never reach the logger as `F1`–`F12`. The app tells you when
that happens: a line under the message buttons names what arrived ("F1 arrived
as Brightness ▼ …") with the fix. Keychron and most third-party boards in Mac
mode default to multimedia on the F row; hold `fn`+`X`+`L` for 4 s to lock it
to function keys (older firmware: `fn`+`K`+`C` for 3 s), or press `fn` with the
key. Apple keyboards: System Settings › Keyboard › Keyboard Shortcuts… ›
Function Keys. Every key the app rules on is also traced to the unified log —
`log show --predicate 'subsystem == "org.b5n.QSOPartyLogger"' --last 10m` shows
the key code, which window had focus, and what the app did with it.

## Logging

- **County lines, N1MM style.** Type `LIN/AND` (up to 4 counties) and each
  county becomes its own log row, which is what sponsors require. The rows share
  a group marker, so they edit and delete together. Use `/` or `,` — space is
  not a separator, because Space moves the cursor.
- **County validation** against each party's official list, with suggestions for
  typos (`LNI` → `LIN`). The check follows where *you* are operating from, so an
  out-of-state entrant is checked against what they can actually receive.
- **Serial-number exchanges.** Where a party sends a QSO number instead of a
  report, the entry bar shows yours (pre-filled) and a field for theirs. A
  county-line contact is one contact and carries one number. Deleting a QSO
  never renumbers the rest.
- **The log shows the exchange you actually ran.** Ten of the bundled parties
  send no signal report at all, and the Sent and Rcvd columns follow each one:
  `TOM TX` for a name party (NAQP, MNQP), `1 SCLA` for a number party (CQP,
  PAQP, VAQP), the location alone for MDC, IdQP, NCQP and WIQP, and `599 MRN`
  everywhere a report is genuinely exchanged.
- **Run vs Search & Pounce follows your location** — an in-state log opens in
  Run, an out-of-state log in S&P. The mode is stored in the log, so reopening
  mid-contest puts you back where you were.
- **Worked before.** Type or tune to a call already in the log and a table
  appears listing every prior contact — band, mode, time, what they sent. The
  entry for the band and mode you're on right now is bold and orange: nothing
  left to work here.
- **Exchange pre-fill.** Work someone on a new band and their county is already
  in the field, from your last contact with them or from a previous contest in
  the history archive. Pre-filled text is greyed until you type over it, and it
  withdraws itself if the call changes. A county only carries over within the
  same sponsor's party, since `JEF` means different things in Colorado and
  Kansas.
- **Copied, not lost.** A station you can hear but who can't hear you costs you
  an exchange. Move to the next spot and the field clears — but what you copied
  stays under their call, and comes back when you land on them again. Fixing a
  typo never costs the exchange underneath it.
- **ESM (Enter Sends Message)**, toggled right on the message row. **The call
  field never logs**: while the cursor is there, Return only ever calls, however
  complete the row looks. Move to the exchange and the same Return logs and
  sends your report. Sitting on an exchange that matches nothing, Return sends
  **AGN?** — they're already talking to you. The F-key Return will send next is
  outlined.
- **RST pre-filled** (599/59 by mode) after every contact.
- **Fixing rows in bulk.** Select a range of log rows (`⇧`-click, `⌘`-click,
  `⌘A`) and right-click → **Edit N Contacts…** to change one field across all of
  them: band, mode, the location you were sending, and — where the party's
  exchange carries them — the name or member number you sent. That's the rover's
  fix for twenty contacts logged from the county you left half an hour ago. One
  ⌘Z puts them all back.

  What the *other* station sent is never edited in bulk. Their county, their
  name, their number are a different fact per station, and there is no one
  correct value across fifteen of them — those stay on the single-row editor.
  County-line rows are held back from a location change too, and the sheet says
  how many: your two counties collapsed onto one would leave two identical rows.

## Scoring

The score sidebar shows a running total, a QSOs-by-band/mode matrix, the full
multiplier checklist and bonus status — all computed from the active party's own
rules. Points by mode, multiplier scope (once, per band, per mode, or both),
bonus stations, mobile activation bonuses, power and station-category
multipliers, and 1×1 word trackers where the sponsor runs one. Dupes are flagged
but kept, because sponsors want them in the log. A **NEW MULT** badge appears
before you log. The log list's **Pts** column is what the engine paid each row —
the same breakdown the sidebar totals, so a Skeeter Hunt row reads 3, 2 or 1 by
the number or power it sent, and a dupe reads 0.

Each party names its own multiplier class, so NAQP counts *NA entities*, BCQP
*districts* and QCQP *regions* — nothing says "county" at a party that doesn't
have any.

**Copying the summary.** Right-click the score card — or press **⇧⌘C** — to put
the whole summary on the clipboard as fixed-width text, shaped after N1MM's
Score window: the band-by-mode matrix, the score components, the Skeeter/QRP/QRO
split where a party has one, and each sponsor's own QSO count for a combined
entry. That's the block a summary email or a 3830 post wants. Every figure comes
from the same breakdown the sidebar draws, under the same labels, so the paste
and the screen can't disagree.

### Rate

Beside the score, on the same lines, four figures in QSOs per hour:

| | |
| --- | --- |
| **Last 10** | Across the last ten QSOs, measured to *now* — so it falls away while you are off the air instead of reporting a run that has already died |
| **60 min** | Contacts in the trailing hour. A count, not a projection, and the one figure that reaches zero when the band does |
| **Hour** | This UTC clock hour so far, and where it lands at the current pace — `15→39` |
| **On air** | Averaged across time in the chair, breaks of 30 minutes or more excluded, so an overnight does not halve it |

Short windows are counted in QSOs and long ones in minutes on purpose: a
ten-QSO window always holds data and widens itself when things go quiet, while
only a clock-based window can fall to zero. Anything the log cannot yet support
reads `—` rather than a confident number — two contacts ten seconds apart are
not 120/hr. Dupes and out-of-scope contacts are excluded, so rate and the QSO
count beside it always agree.

### The Advisor

The app measures nearly everything a contest decision needs — four rate
windows, the exact worked-multiplier set, spots with counties on them, every
bonus rule and operating window. The Advisor, at the top of the score sidebar,
is the part that *reads* them back to you.

**It states facts, never orders.** The line on screen is a true sentence about
your own data — "Run fading: 18/hr last 10, down from 46 the past hour" — and
whatever usually pays lives in the tooltip. It is silent whenever it has
nothing true to say, which is most of a contest, and it never logs, never keys
and never moves the radio.

| | |
| --- | --- |
| **Run health** | Your run has halved against its own trailing hour, and held there for three minutes. Fires at 0.5×, clears at 0.75×, so it cannot flap |
| **Move calls** | Where the next hour is, and in which posture: every band and both Run and S&P, ranked by workable spots, needed multipliers, your own measured rate there, and — for a run — how the sky is likely treating that band. A working run is never interrupted |
| **Needed multipliers** | Unworked counties on the air right now, each a chip that tunes the radio and drops the call in the entry bar, exactly as a band-map click does |
| **Bonus stations** | The party's own bonus call while it is still earnable, naming what remains — "W7DX worked on CW — Phone bonus open" — with its frequency when somebody has spotted it |
| **Operating windows** | The last two hours of a window counting down, the next one's opening time between them, and silence after the last one closes |

**Score, or QSOs** (**⌥⌘A**, shown in the header). Score prices a new
multiplier heavily, because it multiplies everything. QSOs prices every valid
contact the same, which is what the State QSO Party Challenge pays — there a
needed county is worth exactly one QSO. One census, two yardsticks: the same
band map can recommend the
multiplier-rich band under Score and the busy one under QSOs. The setting is
global, because a Challenge season is a season rather than a log.

**The sky, honestly.** Sunrise, sunset and the gray line come from your grid
square and NOAA's own solar equations, checked against the US Naval
Observatory. Solar flux and the planetary K index come from NOAA SWPC, at most
once an hour, cached so a contest that opens offline still starts with what was
last true. All of it is *tendency, not measurement*: a spot you can see always
outranks it, the wording always says "usually", and the observation time is
always named. No grid, no network, or a reading over six hours old, and the
Advisor simply runs on what it can see.

A **NON-ASSISTED** entry never receives a spot at all, so every spot-derived
line is silent for it by construction — what remains is your own log and the
terminator, which are nobody's assistance. Right-click the header to silence
any single kind, or the Advisor entirely; **⇧⌘A** collapses it.

### The multiplier checklist

Every class the party counts is drawn whole — worked *and* still needed — so the
sidebar answers "what am I missing", not just "what have I done". NAQP shows all
50 states plus DC, the 13 provinces and the sponsor's 46 NA entities from the
first contact of the weekend.

Where a party counts a multiplier more than once, each chip carries a strip of
blocks beneath it, one per band, filled as that band is worked — N1MM's
Multipliers window in a 270pt column. A chip only goes fully green once every
band is done, so it can never read "worked" while five multipliers remain on it.
Hover any chip for what's still needed. **⇧⌘M** expands or collapses every list
at once, and each party remembers what you left collapsed.

The lists come from the party definition, so they are exactly what that sponsor
credits: a party that aliases DC to Maryland never lists DC as its own chip, a
home state reachable only through its counties is still listed, and OhQP shows
11 provinces where NAQP shows 13. Two tests drive every roster token of every
bundled party through the scorer in both directions to keep the checklist and
the score from ever disagreeing.

DX is the one class with no checklist — 340 entities is not a roster to chase —
so worked entities are listed as text.

### DX entities

Where a sponsor counts DXCC entities one by one, they are counted one by one:
22 of the 35 parties that count DX say so in their own words, and the other 13
grant a single DX multiplier, which is also what their rules say. Entities come
from the **ARRL DXCC List**, so `DL1ABC` and `DJ2XYZ` are one Germany, and the
Maine, New Hampshire and Salmon Run allowances that used to collapse into one
multiplier now count in full.

The entity is read from the received prefix where the sponsor's exchange
carries one, and from the **worked callsign** where the exchange is the bare
word `DX` — the same split N1MM makes. A token that is both a state code and a
prefix is decided by the callsign, so `PA0AAA` is the Netherlands and `W3XYZ`
is Pennsylvania. Nothing is guessed from a token's shape any more: a mistyped
county is an error again.

Each entity is labelled with the prefix an operator would recognise, and the
app checks that label list for you — once a day at most, at launch or contest
load, taking effect at the next launch rather than mid-contest. It can only
change a label, never a score.

For the combined May weekend the sidebar breaks down **QSOs by party** —
Indiana, 7QP, New England, Delaware — each with its own counties-worked count
and a ✓ once it clears the Challenge's two-QSO bar. The counts are each
sponsor's own, not a share of the total: the four don't run the same bands and
modes, so two digital Indiana contacts are logged, exported, and worth zero to
Indiana. Contacts a sponsor ignores are shown as ignored, not dropped, and the
county grid groups by contest and then by state.

## Radio control and CW

**Elecraft K3 / K3S / KX3 / KX2** over serial at 4800–38400 baud, with live
frequency, mode and TX polling, and the band stamped onto each QSO. The app asks
which model answered and what options are fitted, so it knows how many voice
memories the rig actually has before it offers you any.

**QRP Labs QMX+ / QMX** over its USB serial port — the whole series, since they
share one CAT manual. Same live frequency, mode and TX polling. The rig has no
FM and its `MD8` is not a mode but SWR Tune, so nothing you can type into the
mode field will key it into a tune-up.

**FlexRadio 6000 / 8000** over TCP/IP (SmartSDR API, port 4992). Push-based
slice status — no polling — with CW through the radio's CWX keyer,
bidirectional WPM sync, and phone messages streamed to the radio as its own
transmit audio (DAX) over the same connection.

Opening a contest file reconnects the last radio you used, and every connect
*validates* that the radio actually answers rather than letting a dead link
surface mid-pileup. Connection status lives in the radio bar, not in popups: it
reads "Waiting for radio…" while the link proves out, then shows the live
frequency — or warns **Radio not answering** in orange, with the details one
tooltip away. The button offers **Disconnect** only once the radio has answered;
an unproven link gets **Cancel**.

**CW keying.** A radio with key lines is keyed directly: DTR/RTS line keying
with sub-millisecond software timing (8–50 WPM, optional PTT line with lead and
tail). That is the only path on those radios — it is what lets **Esc** cut a
message mid-character and **⌘=** / **⌘-** change speed *while the message is
still going out*, rather than on the next one. A radio with no key lines, like
the Flex, keys through its own keyer instead.

> **Set your radio's key line up before the contest, not during it.** With no
> internal-keyer fallback there is no in-app way out, and keying is one-way —
> the radio never reports that it is ignoring the line. On a **QMX** set
> CW menu → *Key from USB DTR* to **USB 1**; it ships as *None* and will sit
> there silently until you do. On a **K3**, set CONFIG:PTT-KEY to map DTR.

F1–F8 messages support `{MYCALL} {CALL} {RST} {SERIAL} {NAME} {EXCH}
{MEMBER}` and default to the active party's own exchange shape — a serial party
sends `{SERIAL}` where the report would go, a name party sends `{NAME}`, and a
QRP-sprint party trails the location with `{MEMBER}`, which keys `NR 13` for a
member number and `5W` verbatim for a power. The editor
warns you, with a one-key fix (⇧⌘R), when a message contradicts its party's
exchange. Optional cut numbers (599 → 5NN, 40 → 4T). **Esc aborts instantly.**

**Phone keys play voice messages you record on the Mac.** Open Messages →
Phone (⇧⌘V) and record eight memories — `M1 CQ`, `M2 Exch`, `M3 TU`, `M4
AGN?` by default — straight from the microphone: ⌘1–⌘8 record and stop (30 s
maximum), ⌥⌘1–⌥⌘8 play a memory back on the Mac, and each row shows its
waveform and length. Leading and trailing silence are trimmed off
automatically — the start is where your voice reaches 25 dB under the clip's
own peak, so a breath before the first word is trimmed too, with 120 ms kept
either side; ✂ opens a trim editor with a big waveform, two handles, a **Gain**
slider (±20 dB), Auto-trim and Normalize, and everything is non-destructive.
Import a WAV or any audio file instead, or **Copy from another party…** to fill
the memories every party shares — TU, AGN?, 73 and your call — and re-record
only CQ and the exchange. Recordings are kept **per party** and save the moment
the red button stops (names and F-key mappings save with the sheet). ⇢ Radio
plays a memory to the radio exactly as the F-key will, so the level can be set
against the radio's ALC meter with the Level slider.

**They live in your iCloud folder.** Once you have chosen an iCloud Drive
folder (toolbar → iCloud → *Choose iCloud Folder…*, the same folder your logs
mirror to), recordings are kept in its `Voice` subfolder — one folder per
party — so your other Macs see the same messages once iCloud has synced them,
and next year's Texas QSO Party finds this year's. Recordings made before a
folder was chosen move there by themselves the next time the tab loads. With
no folder chosen they stay in this Mac's Application Support, and the tab says
so.

On the air the F-keys, ESM, `Esc` and Repeat CQ behave exactly as on CW: the TX
badge shows the caption while the clip plays and clears at the real end, `Esc`
stops the audio and unkeys the same instant, Repeat CQ times itself off the
clip's actual end, and a second F-key during a message **replaces** it — what a
voice keyer does, and what you want when a station answers mid-CQ. Two paths
carry the audio, and the driver decides which:

- **Through a sound card** (Elecraft): the Mac plays into an audio device you
  pick — the radio's USB codec or an interface into its line input — and keys
  the radio over CAT (`TX;`/`RX;`) with an adjustable lead, or leaves keying
  to VOX. See *Playing recordings through a K3* below.
- **Over the network** (Flex): the app streams the audio to the radio itself and
  keys it for each message. Nothing to wire; see *Connecting a Flex*.

Nothing keys the radio until an F-key, Return under ESM, Repeat CQ or ⇢ Radio
asks. If the path isn't ready — no output device chosen, the radio refused the
stream — the phone keys stay inert with the reason in their tooltip and in the
Phone tab, and never fall back to a different source on their own.

**The radio's own voice memories remain an option.** Where the radio reports
some (8 on a K3 with the KDVR3 recorder fitted, 2 on a KX3 or KX2), the Phone
tab offers *Phone messages play from: Recordings on this Mac / The radio's
voice memories*. On the radio's memories the app only plays: record them from
the front panel, and three things the app cannot see are whether a memory holds
a recording at all, whether you have re-recorded one since naming it, and
whether an M1–M4 button has been reassigned as a programmable function switch.
Reaching memories 5–8 changes the radio's message bank and leaves it there; the
Phone tab shows which bank the radio is in.

### Wiring a K3 for direct keying

1. Connect the K3's RS-232 port (or KUSB adapter) to the Mac.
2. On the K3, set `CONFIG:PTT-KEY` (menu 103) to `RTS-DTR` — PTT on RTS, CW key
   on DTR. That's the app's default mapping, changeable in the radio bar.
3. In the app: pick the port, 38400 baud, **Connect**. Both lines are deasserted
   at open, so the rig never keys on connect.

No extra interface needed — the same single-cable setup N1MM uses.

### Playing recordings through a K3

The K3's rear-panel **LINE IN** jack "should be connected to your computer's
soundcard output" (Owner's Manual D10) — a USB audio interface, or the Mac's
headphone jack, into LINE IN.

1. On the K3, set `MAIN:MIC SEL` to **LINE IN** — or leave the microphone
   selected and set `MAIN:MIC+LIN` to **ON**, so the mic and the line input are
   both live and you can answer on the mic between recordings.
2. In Messages → Phone, choose that interface as **Radio audio out** and leave
   **PTT** on *Radio command*: the app sends `TX;` before each recording and
   `RX;` after it, with the **Lead** you set (120 ms to start) so the first
   syllable is not clipped. Choose *VOX* instead if you would rather the radio's
   own VOX keyed on the audio.
3. Level: press ⇢ Radio on a memory and watch the ALC meter. The manual asks
   for the sound-card level "6 to 10 dB below the level at which the sound
   card's output stage starts clipping" — the app's **Level** slider is that
   control — and the K3's `MIC` knob (with MIC SEL on LINE IN) sets the line
   input gain.

The K3S, KX3 and KX2 route computer audio differently; their manuals name the
jack and the menu, and the app's side is the same. The radio's own recorder is
still one setting away — *Phone messages play from: The radio's voice memories*.

### Wiring a QMX for direct keying

1. Connect the QMX's USB port to the Mac. It appears as a serial port with no
   "QMX" in its name — plug it in and take the newcomer in the list.
2. On the radio, set **CW → Key from USB DTR** to `USB 1` (it ships `None`).
   The port keys as a straight key, independently of the radio's own keyer, so
   the internal keyer can stay in iambic mode for the paddles.
3. Leave **PTT** off in the radio bar. The QMX maps PTT to DTR as well, not to
   RTS, so a PTT line would fight the key line on the same wire.
4. In the app: pick the port, **Connect**. Baud is whatever you like — it is a
   USB virtual port and the rate never reaches the radio. Both control lines
   are deasserted at open, so the rig never keys on connect.

The radio's own keyer is the fallback here, as everywhere, and it works: text
goes out in chunks paced against the QMX's report of its own 80-character send
buffer, because a message that overflows that buffer is discarded silently
rather than truncated. Esc still aborts, and drops anything not yet handed over.

### Connecting a Flex

Radio bar → **FlexRadio 6000/8000 (TCP)** → enter the radio's IP (mDNS names
work) and port 4992 → **Connect**. CW keys through CWX automatically; there are
no control lines to wire.

The first connection triggers macOS's **Local Network** permission prompt. Allow
it, or the Flex is unreachable (System Settings → Privacy & Security → Local
Network if you dismissed it). The app keeps retrying while the prompt is up.

**Phone messages go to the Flex over the same network connection** — the
recordings you make in Messages → Phone are streamed to the radio as its own
transmit audio, and the radio is keyed for each one. There is nothing to wire
and no sound card to pick. On the first message after connecting, the app
registers itself with the radio, opens a DAX transmit stream and **claims
transmit on it** (`stream set … tx=1` — the radio modulates only the one DAX
TX stream that has claimed, and drops packets from every other); nothing is
keyed until the radio reports the stream is the app's and `tx=1`. For each
message it then switches the radio's transmit audio source to DAX (the DAX
button in SmartSDR's TX panel lights while a message plays), keys, streams the
clip with a short lead and tail of silence, unkeys, and puts the source back so
your microphone works between messages. Whichever slice is the transmitter is
what goes on the air.

Three things to check if the radio keys but nothing is heard:

- **The DAX control panel's own TX channel must be off.** If SmartSDR's DAX
  application (or any other program) has a TX channel enabled, the radio takes
  its transmit audio from *that* stream and silently drops this app's — PTT
  with silence is exactly what that looks like. Turn that program's TX off
  while you use recordings here; you can turn it back on for digital modes
  afterwards.
- MIC level and RF power on the radio must be non-zero, as for a microphone.
- Open **Details — what the radio said** at the bottom of the Phone tab: it
  lists every command the app sent for the stream, the radio's replies and
  status lines, and the packet count, and it has a Copy button. If the radio
  refuses the stream, the reason — with the radio's own response code — also
  appears in the radio bar, and nothing is transmitted.

The Level slider is the only level there is on this path (the radio's speech
processor still applies, as it does to a mic).

## Spotting and the band map

**⌘B** opens a floating N1MM-style band map: a vertical frequency ruler for the
current band with spots plotted where they live, a red VFO marker tracking the
radio, and a dashed line marking your run frequency. Zoom 25/50/100 kHz or the
whole band; click a spot to tune and fill the call, click empty map to QSY. It
stays on screen when another app takes focus, so it can sit beside a panadapter.

- **Two feeds, one map.** Connect any DXSpider or AR-Cluster telnet node
  (toolbar antenna icon), optionally automatically when a contest opens. On top
  of that, the app polls [qsopartyhub.com](http://qsopartyhub.com) for the active
  party — and unlike a cluster spot, a hub spot carries the **county**, which is
  the multiplier you're actually chasing. 39 of the 50 bundled parties have a hub
  page. A spot seen on both feeds is one entry.
- **Filters** (funnel button): North American stations only, North American
  spotters only, hide worked stations, hide RBN/skimmer spots, hub-only, per
  mode, per band, and how long spots live (5 min – 2 hr). It's a panel, not a
  menu — tick everything you want in one visit. All off by default.
- **Worked stations stay visible**, greyed and struck through so you can watch
  the band fill up, and ⌘↓ / ⌘↑ steps straight over them.
- **Rovers stop hiding.** A mobile that changes county is a new contact: work
  them in one county and they grey out, then come back the moment they spot from
  a county you still need.
- **Colours say what a spot is worth** — N1MM's scheme. **Red**: a multiplier
  you still need. **Blue**: unworked, not a multiplier (or nobody knows where
  he is). **Grey**, struck through: worked on this band and mode, or
  superseded. A cluster spot carries no county, so the app looks the call up
  the way the exchange pre-fill does — your log, previous contests, the party's
  call history file — and a red cluster spot is one whose county lands in the
  exchange field the moment you tune to it. The tooltip says where the county
  came from.
- **Stations you worked land on the map** while you're searching, at the
  frequency you worked them, so a station nobody spotted doesn't leave a hole in
  the band. **Running, they don't** — everyone answering your CQ is on your own
  frequency, which the map already marks, so a good run would otherwise bury it
  under a stack of its own callsigns.
- **Stacked spots** fan out sideways into extra columns rather than being shoved
  off frequency. Twenty calls on one frequency show all twenty. Label size is
  adjustable S/M/L/XL for reading across the room.
- **Band-plan-aware mode switching**: tune into the phone segment and the radio
  goes to SSB, into the CW segment and it goes to CW. It only fires when *the
  app* moves you, so your own VFO knob never changes mode mid-QSO. Crossovers
  come from 47 CFR §97.305(c). Untick **Follow band plan on QSY** to disable.
- **CQ frequency memory**: sending F1 in Run mode remembers your run frequency;
  **⌘J** jumps back to it after an S&P excursion.
- **Run and S&P follow the knob.** Tune more than the leave-Run distance off
  your CQ frequency (1 kHz on CW and digital, 3 kHz on phone) and the mode goes
  to S&P — a QRM dodge inside it keeps you in Run; tune back within the
  tolerance and you're in Run again, F1 ready to CQ. Only a *change* of zone
  acts, so ⌘R is never fought. Leaving Run stops Repeat CQ. Both halves are
  N1MM's ("QSYing will switch to S&P mode"; back "within the tuning tolerance
  of the marker, the program will switch automatically to Run mode"), each
  with its own switch under the funnel's **Tuning** section.
- **The call frame — a ghost call.** Searching, the nearest visible spot within
  the tuning tolerance (300 Hz on CW and digital, 1 kHz on phone; settable)
  appears in the empty call field in the map's colour for it. **Space**, or
  **Return** under ESM, takes it — call and county — and that same Return then
  calls him. Type anything and the ghost is just gone. A call the app put there
  (ghost, spot click, ⌘↑/⌘↓) is erased when you tune more than the tolerance
  away without having typed anything; typed text is never touched. Off, or
  the numbers, under **Tuning**.
- **VFO nudge**: **⇧⌘←** / **⇧⌘→** move the radio 100 Hz down / up without
  leaving the entry field — zero-beating a caller, or edging off a neighbour on
  phone. A burst of presses adds up even before the radio has reported back.

Hub spots are hand-posted, so they live longer than cluster spots — 60 minutes
against 15, matching what the hub itself keeps. Hub polling runs once a minute
and only inside the party's operating window.

### If a cluster node won't talk

The connection popover has a **live node window** showing everything the node
says, and a box for typing node commands (`sh/dx 30`, `set/skimmer`, `bye`). If
a node never answers, keeps re-prompting for a login, or accepts you and then
sends nothing, the app says so rather than sitting silently "connected".

The app waits for the node's real login prompt, answers with your contest call,
runs your startup commands (`sh/dx 30` by default, so the band map is populated
the moment you connect) and handles telnet option negotiation, so nodes behind a
real telnetd work. A cluster on the same Mac works the same way — point it at
`localhost` and your feed's port.

Verified end-to-end against `dxc.wa9pie.net:8000` (DXSpider), `dxc.nc7j.com:7373`
(AR-Cluster) and SDC's telnet server on `localhost:7373`. `ve7cc.net:23` accepts
the connection and prints its banner but never answers the login from this
client — use another node if you hit that.

### NON-ASSISTED means no spots

Declare `CATEGORY-ASSISTED: NON-ASSISTED` in Contest Setup and spotting switches
off completely — Connect is disabled, auto-connect doesn't fire, hub polling
stops, and declaring it mid-contest drops the connection and clears network
spots off the map. Sponsors score any spotting-network use as Assisted, so the
app makes the claim true rather than warning you afterwards.

Spotting *outward* (⇧⌘S) to the hub and to POTA, and your own logged contacts on
the band map, stay available: neither is receiving spotting information. The
cluster row of the spot sheet is the one thing that goes dark, because there is
no node to send through — the sheet says so, in the policy's own words. And if
you switch to NON-ASSISTED *after* taking spots, an orange badge says so —
those contacts are already made. Dismiss it with ⌘.; it returns once more at
Cabrillo export, which is never altered or held up.

### Spotting to the networks (⇧⌘S)

One shortcut, one sheet, every network that applies. Your operating mode
decides who the spot is for:

| Mode | Call field | ⇧⌘S spots |
| --- | --- | --- |
| Run | anything | **you** — your call, the VFO, your counties from the log, your park |
| S&P | `N4RT` | **N4RT** — the VFO, the county you've copied so far, the park from the P2P field |
| S&P | empty | a blank sheet, cursor in the call field |

You can also right-click a spot on the band map, or a row in the log, to spot a
station you worked earlier. The sheet lists three networks under **Send to**,
each with a checkbox (`⌘1`/`⌘2`/`⌘3`), where it goes, and — once ticked —
**exactly what that network will receive**, so nothing that goes out is a
surprise:

| Network | On offer when | What goes out | Confirmed by |
| --- | --- | --- | --- |
| **DX cluster** | a node is connected (so never under NON-ASSISTED) | `DX 7047 KE5CW AL-QSO-PARTY MDSN …` — the party's Cabrillo name and the county in the remarks, then your comment | the node echoing your spot back — DXSpider's own "proof of receipt" |
| **QSO Party Hub** | the party has a hub page | the form's own fields — call, kHz, county, comment, poster | your call appearing on the board at the next poll |
| **POTA** | the log is an activation (your park from Contest Setup); or, for another station, once you type their park on the row | pota.app's own Add-Spot fields — activator, spotter, kHz, one park, mode, comment, and `QSOPartyLogger` as the source | the board's own list, which the post answers with; else two follow-up reads |

A network that isn't on offer stays greyed with the reason in place of the
preview — *Not connected — Spots ▸ Connect*, *This party has no page on
qsopartyhub.com*, *Set your park in Contest Setup to spot yourself on POTA*
— so the way to enable it is never a mystery. The ticks are remembered per
network: untick POTA at home and it stays unticked next time POTA is offered,
without touching your hub and cluster habits. `Return` posts to every ticked
network at once; **Post Spot** waits until every ticked network is satisfied,
and an objection is shown under the row it belongs to (a county the party
doesn't have blocks the hub, not the cluster; a bad park blocks POTA alone),
so you fix it or untick it and nothing is skipped silently.

Every send is confirmed first, because the hub's form has no authentication
and submitting twice posts twice, and fanning one press out to three public
boards makes that rule matter more, not less. County lines go out whole
(`MDSN/LIME`), every county is checked against the party's list first, and
nothing is invented — with no radio connected the sheet waits for you to type a
frequency rather than guessing on a public board. An identical spot inside five
minutes is refused by every network; a changed frequency, county or park never
counts as a repeat. Change county in the log and the sheet opens by itself,
pre-filled.

After **Post Spot** the sheet closes and a **receipt capsule** appears in the
station strip, live: `KE5CW 7047 · Cluster — echoed by the node · Hub — on the
board · POTA — on pota.app`. Grey while anything is still in flight (a 200
means *sent*, not *accepted*), green once every network has shown the spot
back, orange the moment one fails — with the network's own words for why
(`pota.app refused the spot: …`, `The spot was sent but hasn't appeared on the
board`) and a **Retry…** that reopens the sheet with only the failed network
ticked. It leaves by itself twelve seconds after the last change (a minute
after a failure) and comes back for a verdict that lands late, such as the
hub's poll two minutes on. The hub, cluster and POTA windows keep the record.

## Call history files

The N1MM community maintains per-contest **call history files** — rosters of
what each station usually sends. N1MM users download them by hand; this app does
it for you. Pick a party and the newest revision is found, verified and cached,
and from then on typing a call puts what the file knows in the entry row before
the station has said anything: county, state, and the operator's name in the
name parties.

- **Automatic and current.** Fresh revisions are uploaded days before each
  contest, so the app searches for the newest matching file rather than using a
  bundled URL, checking at most once a day — or on the **Refresh** button in
  Contest Setup. A toggle turns the feature off.
- **Verified before installed.** A download that doesn't declare the active
  party, or that comes back empty or as an access-denied page, is discarded and
  the previous copy stays in service.
- **A hint, never authority.** Every value has to survive the party's own
  exchange parser for your operating role first. Offers rank below your own log
  and above a spot's claim, grey out until you accept them, and the row says
  **log what you copy**. Nothing from these files ever reaches the score.
- 47 of the 50 bundled parties have a source upstream — 45 on the N1MM
  listing, and two from their sponsors' own rosters: the NJQRP Skeeter Hunt,
  where each season's Skeeter-number sheet is discovered from the blog page,
  and the Flight of the Bumblebees, whose self-serve Bumblebee numbers come
  straight from the ARS report page (each bee offered under both its bare
  call and its `/BB` form). Both are converted to the same shape. Arizona,
  Maryland-DC and Vermont have none, and simply show no row in Contest Setup.

Cached files live in `~/Library/Application Support/QSOPartyLogger/CallHistory/`.

## Super check partial

The community's **MASTER.SCP** — ~50,000 calls distilled from submitted
contest logs — feeds a quiet strip under the entry row: type three or more
characters of a call and every known call containing that fragment appears,
the exact call tinted green once it's complete. A busted copy shows itself
as a call the database has never heard of. Purely for the eye — nothing
from it validates, scores, or fills anything.

- **Zero setup.** The file downloads itself on first launch and is
  re-checked at launch and contest load, at most once a day, by a
  Last-Modified HEAD — the ~360 KB body only moves when a new release is
  actually out. There is nothing to download by hand, ever.
- **An option.** One toggle in Contest Setup (with the cached release,
  call count, and a Refresh button); off means no strip and no network.
- **Verified before installed.** A download that comes back as an error
  page, truncated, or implausibly small is discarded and the previous copy
  stays in service.

The cached file lives in `~/Library/Application Support/QSOPartyLogger/SCP/`.

## Your season

- **Contest Dashboard (⌘⇧D)** — every contest you've logged, one year at a time
  (⌘[ / ⌘]): totals, each claimed score exactly as the sidebar computed it,
  on-air time with breaks excluded, QSO and score charts, and each party's
  year-over-year trend with your personal best flagged. Return reopens a
  contest's log; ⌘E / ⇧⌘E export it without reopening.
- **State QSO Party Challenge tracker** — your estimated standing by the
  sponsor's formula (total QSOs × parties entered), with the ≥2-QSO floor and
  the Bronze-to-Diamond ladder. A combined May entry counts as the four contests
  it's made of, worth up to four multipliers. Parties not on the approved list
  are shown and excluded rather than silently dropped. It's labelled an
  estimate — the official score comes from what you post to 3830scores.com.
- **Upcoming contests** — everything left this season, soonest first, with an ON
  AIR badge while a window is open, countdowns, and "entered ✓" once you've
  logged it. All 47 Challenge-approved parties are listed.
- **One history file in iCloud.** Every save archives the full log and score
  snapshot into `Contest History.qphistory` in your logs folder, so the
  dashboard follows you to any Mac. Two Macs merge by QSO, iCloud conflict
  copies fold in automatically, and a corrupt file is never overwritten.
  "Import Existing Logs" rebuilds the archive from the `.qplog` files you
  already have. Snapshots freeze each score as computed that season, so next
  year's rule updates never rewrite history.

## Files and export

Each contest is a `.qplog` file (JSON, with undo). New logs auto-save into your
logs folder and mirror to iCloud Drive if you've configured one.

The toolbar **Export** menu offers both formats:

- **Cabrillo V3** — per-county-line QSO rows, claimed score, and the full entry
  declaration: operator, assisted, power, station and transmitter categories, a
  multi-op `OPERATORS:` list, club, grid locator and address. Contest Setup
  collects all of it, so a Single Op **Assisted** or Multi-Two entry exports as
  exactly that. Every field there folds to caps as you type — really folds, so
  what the header carries is what the row showed — with one deliberate
  exception: your email address keeps the case you typed it in, since that is
  the one header a sponsor may write back to.
- **ADIF 3.1.4** — `CNTY`/`MY_CNTY` with full county names,
  `STX_STRING`/`SRX_STRING`, group ids in an `APP_` field, and the POTA
  fields below when the log is an activation.

Suggested filenames follow the log ("2026-08-29 KSQP KE5CW.adi"), and the app
declares the ADIF file type so the save panel keeps `.adi` instead of appending
`.txt`.

## POTA activations on any contest

Any contest log doubles as a POTA activation log. Contest Setup has a **POTA
Activation** section on every party — set your park(s) there and each contact
is stamped with them as it is logged, so a mid-contest move (or a rove) marks
only the contacts made after it.

- **Find the park by name or number.** The picker searches a cached copy of
  POTA's own US program list — 12,938 parks — and every word has to match, so
  "lake tx" narrows to Texas lakes and "3051" goes straight to Ray Roberts.
  Click into the empty search box and it offers the **parks nearest you**, in
  miles, from either the Mac's location or your grid square. `↑`/`↓` move
  through the results and `Return` adds the highlighted one; `Esc` clears the
  box and closes the list without touching the mouse or the sheet. Typing a
  full reference and pressing Return adds it outright, which is also how you
  enter a park from another program or one too new to be in the list.
- **It works with no signal.** The list is downloaded once — on an explicit
  button, never silently, since it is about 3 MB and most operators are not
  activating — then searched entirely offline and refreshed weekly. POTA's API
  refuses `HEAD` requests, so there is no cheap way to ask "has this changed?";
  a weekly re-download is the honest substitute. A failed refresh keeps the
  copy you have and says so.
- **Your grid square fills itself.** **Locate** beside the grid field asks
  macOS where the Mac is and converts it to a 6-character locator. It fills
  silently on opening Setup only when permission has already been granted —
  the permission dialog only ever appears from that button — and the field
  stays plain text, so no fix just means you type it yourself.
- **Park-to-park.** While a log is an activation, the entry bar grows a **P2P
  park(s)** field for the other station's park. A reference that doesn't parse
  refuses to log, the way an unreadable Skeeter number does — it is what earns
  the credit. Rows carrying one are tagged `P2P` in the log's Flags column, and
  both sides' parks stay editable afterwards (per row in the editor, or across
  a selection with **My POTA park(s)** in the bulk editor).
- **The export is what POTA credits.** Each row becomes one ADIF record per
  (my park × their park) pair, carrying `MY_SIG`/`MY_SIG_INFO`,
  `SIG`/`SIG_INFO`, and ADIF 3.1.4's `MY_POTA_REF`/`POTA_REF`. That duplication
  is POTA's own instruction for n-fers — work a three-fer and the QSO is listed
  three times, one park each — so activation, park-to-park, and n-fer credit
  all survive the upload. A log with no parks exports byte-for-byte as before.
- **Spot yourself on pota.app from the same ⇧⌘S** that spots you to the
  cluster and the hub. While the log is an activation the spot sheet's POTA
  row is on offer, pre-filled with your first park and the radio's mode as
  ADIF spells it (USB → `SSB`), both editable; the post is the one pota.app's
  own Add-Spot form makes, under `QSOPartyLogger` as the source, and the
  receipt says **on pota.app** only once the board's own list shows it. Work a
  park-to-park station and ⇧⌘S in S&P offers to spot *them*, park taken from
  the P2P field. See [Spotting to the networks](#spotting-to-the-networks-s).

The cached park list lives in `~/Library/Application Support/QSOPartyLogger/POTA/`.
Field definitions, upload rules and the spot API's contract are banked in
[`docs/research/pota/SOURCES.md`](docs/research/pota/SOURCES.md).

## Adding a party without writing code

Drop a JSON file in `~/Library/Application Support/QSOPartyLogger/Parties/`.
Files there override bundled parties with the same `id`. Malformed files are
reported with the reason, and the app keeps running on the bundled set. See
`Resources/Parties/ksqp.json` for a complete example:

```jsonc
{
  "schemaVersion": 1,
  "id": "mnqp",
  "name": "Minnesota QSO Party",
  "cabrilloContest": "MN-QSO-PARTY",
  "homeState": "MN",
  "countyAbbrLength": 3,
  "validBands": ["160m", "80m", "40m", "20m", "15m", "10m", "6m", "2m"],
  "points": { "phone": 1, "cw": 2, "digital": 2 },
  "dupeScope": "bandMode",
  "multipliers": {
    "inState":  { "classes": ["state", "county", "province", "dx"],
                  "homeStateCountsViaCounty": false, "countScope": "once" },
    "outState": { "classes": ["county"],
                  "homeStateCountsViaCounty": false, "countScope": "once" }
  },
  "bonuses": [
    { "type": "workStation", "call": "W0AA", "points": 100 },
    { "type": "mobileCountyCount", "per": 5, "points": 500 }
  ],
  "oneByOne": null,
  "counties": [ { "abbr": "AIT", "name": "Aitkin" } ],
  "caveats": [
    { "kind": "scoreAffecting",
      "summary": "Score is a floor — rare-county multipliers aren't modelled.",
      "detail": "Optional. The summary is the line the setup sheet displays." }
  ],
  "notes": "Verify against current-year rules."
}
```

`caveats` never affects scoring. It classifies the gaps between this app and the
sponsor's rules by what they cost you, so that a warning means something:

| kind | means | warns |
| --- | --- | --- |
| `exportBlocking` | the log this app writes can't be submitted as-is | **yes, in orange** |
| `scoreAffecting` | the app's total will differ from the sponsor's | **yes, in orange** |
| `ruleInference` | the sponsor's text is ambiguous; this app inferred a reading | no |
| `provenance` | source stale or archived; re-check before the next running | no |
| `cosmetic` | recorded for completeness, no consequence | no |

Only the first two interrupt you. Warnings and notes are drawn as separate
headed groups — an orange ⚠︎ over the warnings, a grey ⓘ over the notes — so the
icon says which is which without relying on colour.

One field is worth calling out because **every part of it is required, on
purpose**. Five sponsors give an in-state station a multiplier for each county
it *operates from*, on top of the ones it works, and no two of them agree on
any detail — so a default would be one sponsor's rule silently applied to the
next:

```jsonc
"inState": {
  "classes": ["county", "state", "province", "dx"],
  "activatedCountyMultiplier": {
    "minCount": 10,              // how many before the county counts
    "countUnit": "stations",     // "qsos", or "stations" for distinct calls
    "countScope": "once",        // this multiplier's scope, NOT the side's
    "categories": ["MOBILE", "ROVER", "EXPEDITION"],
    "notOtherwiseWorked": true   // does working the county forfeit it?
  }
}
```

VAQP counts ten *different stations* where MOQP counts fifty *QSOs*; TnQP grants
it **once** while counting worked multipliers per band, so the scope cannot be
inherited; NCQP gives it to **every** in-state entrant, fixed stations included,
so it is not a roving-category rule; and SCQP alone is additive, counting a
county both sat in and worked twice. This is a *multiplier*, distinct from the
per-county `activatedCountyCount` **bonus** — it compounds against every QSO
point in the log rather than being added once at the end.

Adding a party to the bundled set is governed by
[docs/CONSTITUTION.md](docs/CONSTITUTION.md). Read it first.

## Building

```bash
xcodegen generate
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'
```

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). `project.yml` is the source of truth — never edit the
`.xcodeproj` by hand. The app icon is drawn in code; rerun
`swift Tools/GenerateAppIcon.swift` after editing it.

**2820 unit tests**, none of which need hardware, a network or a microphone —
no serial port, no cluster, no HTTP. They cover the scoring engine, county data,
exporters, the K3, QMX and FlexRadio protocols and the connection lifecycle
(driven over `/dev/null` as a stone-deaf serial port), the voice-memory bank
sequence and its refusal to transmit a memory the radio has not confirmed, the
voice recorder's model and DSP and its per-party files, the sound-card keying
sequence (lead, play, tail, unkey — abort at every point, over a fake output),
what the flow puts on the air from a recording, cluster login and telnet handling, call history
parsing and its prefill priority chain, super check partial parsing, matching
and its download client, spot parsing and filtering and navigation, the
spotting policy, outgoing spots — which networks are on offer and why not,
the cluster `DX` command byte for byte, pota.app's own form rules and JSON
body, the fan-out dispatcher and its receipt — the band map scale and column
stacking, the band plan, typed
QSY commands, what the radio keys at every step of the entry flow, keyer
timing, the history archive and its two-Mac merge, season stats, the SQP
Challenge formula, the upcoming-contest engine, and the Advisor — solar
geometry pinned against the US Naval Observatory, the SWPC parsers against
payloads captured from the live products, and every advisory's own wording.

Four notes for anyone working in here:

- What goes on the air is decided by
  [`EntryFlow`](Sources/App/EntryFlow.swift), not by the view, so tests can drive
  the real sequences. Two bugs that put both stations out of each other's logs
  survived eight review rounds while this code was private to a SwiftUI `View`.
- The test bundle is hosted inside the app executable, so every preference goes
  through `Preferences.store`, which the test setup points at a throwaway suite.
  A full run leaves your station profile, radio wiring and cluster history
  untouched.
- A field that holds upper case is built with `uppercasingTextField`
  ([`Sources/UI/Uppercasing.swift`](Sources/UI/Uppercasing.swift)) and never with
  a `TextField` over a folding binding. Folding the value alone leaves AppKit's
  field editor holding what was typed while the model holds what will be logged,
  and the next redraw resolves that by replacing the editor's text — which puts
  the caret at the end of the field, mid-word. The pieces are private to that
  file so the two halves cannot be separated again.
- Never rebuild a copy of the app that is running. The process keeps going, but
  the code identity the kernel recorded at launch no longer matches the file, so
  every sandbox service that checks its caller refuses it — the save panel first
  of all, and ⌘E / ⇧⌘E silently do nothing (2026-08-15). The app now checks
  itself before opening a save panel and says so inline, with the remedy: quit
  and reopen. Build to a path nobody is running from (`Tools/make-dmg.sh` uses
  `build/Release`), and install releases in /Applications.

## Adding a radio

Implement `RadioDriver` — see `Sources/Hardware/Radio/ElecraftK3Driver.swift`
for serial polling and `FlexRadioDriver.swift` for push-based TCP — and append a
`RadioDescriptor` to `RadioRegistry.all`. Its `connection` field decides whether
the radio bar shows a serial port picker or host/port fields. Kenwood-style
ASCII radios share the `IF` field layout — `QRPLabsQMXDriver.swift` is that
case worked through, including what a radio's own manual leaves unsaid; network
radios get `TCPTransport` for free.
[docs/CONSTITUTION.md](docs/CONSTITUTION.md) governs this too.

## More documentation

| Document | Contents |
| --- | --- |
| [docs/PARTIES.md](docs/PARTIES.md) | Every bundled party in detail: what's unusual, what isn't modelled, where it's `verified: partial` |
| [docs/PROVENANCE.md](docs/PROVENANCE.md) | Every source, fetch date and generator behind the rules, counties, band data and Cabrillo headers |
| [docs/CONSTITUTION.md](docs/CONSTITUTION.md) | The rules for adding a party or a radio. Read before doing either |
| [docs/parties/WORKLIST-2026.md](docs/parties/WORKLIST-2026.md) | Per-party status, remaining work, re-verification schedule |

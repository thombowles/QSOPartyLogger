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
2. Optional: pick your radio in the radio bar (Elecraft K3 family on serial,
   FlexRadio 6000/8000 over the network) and hit **Connect**.
3. Optional: click the toolbar antenna to connect a DX cluster, and ⌘B for the
   band map.
4. Type a call, press **Space**, type the exchange, press **Return**. That's a
   QSO.
5. **⌘E** exports ADIF, **⇧⌘E** exports Cabrillo, whenever you're ready.

The log saves itself. Every QSO change is written straight to disk, so a crash
never costs contacts.

## Supported parties

All 48 below are bundled, each built from the sponsor's own rules with an
official county list. **Every US state and regional QSO party running from
2026-07-24 through 2026-12-31 is included**, and the season's earlier parties
are in as well; three parties remain to be added, plus the Canadian Prairies,
which is blocked because its districts are published only as images.

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
| Maryland-DC QSO Party | Aug 8 | 14 h | 25 jurisdictions |
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

| Keys | Action |
| --- | --- |
| `Enter` | Log the QSO (or send the next ESM message, or run a typed QSY command) |
| `Space` | Cycle Call → Exchange → Call, via QSO number and Name where the party uses them. Signal reports are stepped over |
| `Tab` | Walk every field, reports included — landing in one selects the S digit, so 599 → 579 is one keystroke |
| `F12` | Wipe the entry fields and start over |
| `F1`–`F8` | Send CW message (Run or S&P set) |
| `Esc` | Abort CW, stop repeat-CQ, close an open sheet |
| `⌘=` / `⌘-` | CW speed ±2 WPM (syncs to the radio) |
| `⌘↓` / `⌘↑` | Tune to the previous / next unworked spot on the band — `⌘↑` goes up the band map |
| `⌘R` | Toggle Run / Search & Pounce |
| `⌘J` | Jump back to your CQ run frequency |
| `⌘B` | Toggle the band map window |
| `⇧⌘S` | Spot to the QSO Party Hub — yourself in Run, the call field in S&P |
| `⇧⌘R` | Restore the party's default CW messages (Messages editor) |
| `⌘E` / `⇧⌘E` | Export ADIF / Cabrillo |
| `⇧⌘M` | Expand / collapse every multiplier list in the score sidebar |
| `⌘.` | Dismiss the spots-already-used badge for this sitting |
| `14025`, `7.040`, `40M`, `222`, `CW`, `SSB` in the call field | QSY, change band, change mode |

In the Contest Dashboard (**⌘⇧D**): `⌘[` / `⌘]` change year, `⌘R` re-reads the
history file, `Return` opens that contest's log, and `⌘E` / `⇧⌘E` export it.

These keys belong to the log window with focus. While a sheet is open it owns
the keyboard — `F1`–`F8` do not transmit, so revising F2 and pressing it never
keys the old message. `Esc` still aborts CW instantly either way.

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

## Scoring

The score sidebar shows a running total, a QSOs-by-band/mode matrix, the full
multiplier checklist and bonus status — all computed from the active party's own
rules. Points by mode, multiplier scope (once, per band, per mode, or both),
bonus stations, mobile activation bonuses, power and station-category
multipliers, and 1×1 word trackers where the sponsor runs one. Dupes are flagged
but kept, because sponsors want them in the log. A **NEW MULT** badge appears
before you log.

Each party names its own multiplier class, so NAQP counts *NA entities*, BCQP
*districts* and QCQP *regions* — nothing says "county" at a party that doesn't
have any.

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

DX is the one class with no checklist: under prefix style any plausible prefix
is a multiplier, so worked prefixes are listed as text with no roster to chase.

For the combined May weekend the sidebar breaks down **QSOs by party** —
Indiana, 7QP, New England, Delaware — each with its own counties-worked count
and a ✓ once it clears the Challenge's two-QSO bar. The counts are each
sponsor's own, not a share of the total: the four don't run the same bands and
modes, so two digital Indiana contacts are logged, exported, and worth zero to
Indiana. Contacts a sponsor ignores are shown as ignored, not dropped, and the
county grid groups by contest and then by state.

## Radio control and CW

**Elecraft K3 / K3S / KX3 / KX2** over serial at 4800–38400 baud, with live
frequency, mode and TX polling, and the band stamped onto each QSO.

**FlexRadio 6000 / 8000** over TCP/IP (SmartSDR API, port 4992). Push-based
slice status — no polling — with CW through the radio's CWX keyer and
bidirectional WPM sync.

Opening a contest file reconnects the last radio you used, and every connect
*validates* that the radio actually answers rather than letting a dead link
surface mid-pileup. Connection status lives in the radio bar, not in popups: it
reads "Waiting for radio…" while the link proves out, then shows the live
frequency — or warns **Radio not answering** in orange, with the details one
tooltip away. The button offers **Disconnect** only once the radio has answered;
an unproven link gets **Cancel**.

**CW keys two ways**: direct DTR/RTS line keying with sub-millisecond software
timing (8–50 WPM, optional PTT line with lead and tail), or the radio's internal
keyer. F1–F8 messages support `{MYCALL} {CALL} {RST} {SERIAL} {NAME} {EXCH}` and
default to the active party's own exchange shape — a serial party sends
`{SERIAL}` where the report would go, a name party sends `{NAME}`. The editor
warns you, with a one-key fix (⇧⌘R), when a message contradicts its party's
exchange. Optional cut numbers (599 → 5NN, 40 → 4T). **Esc aborts instantly.**

### Wiring a K3 for direct keying

1. Connect the K3's RS-232 port (or KUSB adapter) to the Mac.
2. On the K3, set `CONFIG:PTT-KEY` (menu 103) to `RTS-DTR` — PTT on RTS, CW key
   on DTR. That's the app's default mapping, changeable in the radio bar.
3. In the app: pick the port, 38400 baud, **Connect**. Both lines are deasserted
   at open, so the rig never keys on connect.

No extra interface needed — the same single-cable setup N1MM uses.

### Connecting a Flex

Radio bar → **FlexRadio 6000/8000 (TCP)** → enter the radio's IP (mDNS names
work) and port 4992 → **Connect**. CW keys through CWX automatically; there are
no control lines to wire.

The first connection triggers macOS's **Local Network** permission prompt. Allow
it, or the Flex is unreachable (System Settings → Privacy & Security → Local
Network if you dismissed it). The app keeps retrying while the prompt is up.

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
  the multiplier you're actually chasing. 39 of the 48 bundled parties have a hub
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

Self-spotting (⇧⌘S) and your own logged contacts on the band map stay available:
neither is receiving spotting information. And if you switch to NON-ASSISTED
*after* taking spots, an orange badge says so — those contacts are already made.
Dismiss it with ⌘.; it returns once more at Cabrillo export, which is never
altered or held up.

### Self-spotting (⇧⌘S)

One shortcut, and your operating mode decides who it means.

| Mode | Call field | ⇧⌘S spots |
| --- | --- | --- |
| Run | anything | **you** — your call, the VFO, your counties from the log |
| S&P | `N4RT` | **N4RT** — the VFO and the county you've copied so far |
| S&P | empty | a blank sheet, cursor in the call field |

You can also right-click a spot on the band map, or a row in the log, to spot a
station you worked earlier. Every send is confirmed first, because the hub's
form has no authentication and submitting twice posts twice. County lines go out
whole (`MDSN/LIME`), every county is checked against the party's list first, and
nothing is invented — with no radio connected the sheet waits for you to type a
frequency rather than guessing on a public board. Change county in the log and
the spot sheet opens by itself, pre-filled.

A 200 from the hub means *sent*, not *accepted*, so the app watches the next
couple of polls for your call and says **confirmed on the board** only once it
has actually seen it.

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
- 45 of the 48 bundled parties have a file upstream; Arizona, Maryland-DC and
  Vermont have none, and simply show no row in Contest Setup.

Cached files live in `~/Library/Application Support/QSOPartyLogger/CallHistory/`.

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
  exactly that.
- **ADIF 3.1.4** — `CNTY`/`MY_CNTY` with full county names,
  `STX_STRING`/`SRX_STRING`, and group ids in an `APP_` field.

Suggested filenames follow the log ("2026-08-29 KSQP KE5CW.adi"), and the app
declares the ADIF file type so the save panel keeps `.adi` instead of appending
`.txt`.

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

**1866 unit tests**, none of which need hardware or a network — no serial port,
no cluster, no HTTP. They cover the scoring engine, county data, exporters, the
K3 and FlexRadio protocols and the connection lifecycle (driven over `/dev/null`
as a stone-deaf serial port), cluster login and telnet handling, call history
parsing and its prefill priority chain, spot parsing and filtering and
navigation, the spotting policy, the band map scale and column stacking, the
band plan, typed QSY commands, what the radio keys at every step of the entry
flow, keyer timing, the history archive and its two-Mac merge, season stats, the
SQP Challenge formula, and the upcoming-contest engine.

Two notes for anyone working in here:

- What goes on the air is decided by
  [`EntryFlow`](Sources/App/EntryFlow.swift), not by the view, so tests can drive
  the real sequences. Two bugs that put both stations out of each other's logs
  survived eight review rounds while this code was private to a SwiftUI `View`.
- The test bundle is hosted inside the app executable, so every preference goes
  through `Preferences.store`, which the test setup points at a throwaway suite.
  A full run leaves your station profile, radio wiring and cluster history
  untouched.

## Adding a radio

Implement `RadioDriver` — see `Sources/Hardware/Radio/ElecraftK3Driver.swift`
for serial polling and `FlexRadioDriver.swift` for push-based TCP — and append a
`RadioDescriptor` to `RadioRegistry.all`. Its `connection` field decides whether
the radio bar shows a serial port picker or host/port fields. Kenwood-style
ASCII radios can reuse most of the K3 driver's parsing; network radios get
`TCPTransport` for free. [docs/CONSTITUTION.md](docs/CONSTITUTION.md) governs
this too.

## More documentation

| Document | Contents |
| --- | --- |
| [docs/PARTIES.md](docs/PARTIES.md) | Every bundled party in detail: what's unusual, what isn't modelled, where it's `verified: partial` |
| [docs/PROVENANCE.md](docs/PROVENANCE.md) | Every source, fetch date and generator behind the rules, counties, band data and Cabrillo headers |
| [docs/CONSTITUTION.md](docs/CONSTITUTION.md) | The rules for adding a party or a radio. Read before doing either |
| [docs/parties/WORKLIST-2026.md](docs/parties/WORKLIST-2026.md) | Per-party status, remaining work, re-verification schedule |

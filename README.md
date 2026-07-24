# QSO Party Logger

Mac-native QSO Party contest logger (SwiftUI, macOS 15+) with first-class
county-line support, live rules-based scoring, Elecraft K3 CAT control with
direct DTR/RTS CW keying, FlexRadio control over TCP/IP, DX cluster spotting,
and ADIF / Cabrillo export. Designed keyboard-first: logging, QSY, mode
changes, messages, and spot-hopping all happen without leaving the entry
field.

Built for KE5CW. Bundled parties, all with official county data:

- **Alabama QSO Party** (Jul 25–26, 2026) — verified against the official 2026
  rules: 2 pts CW/phone, mults once **per mode**, DX-prefix mults, DC→MD,
  county-line sitting not permitted, phone/CW only.
- **Kansas QSO Party** (Aug 29–30, 2026) — verified against the official 2026
  rules; 1×1 word tracker included.
- **Texas QSO Party** (Sep 19–20, 2026) — rules verified against txqp.net
  2026 (bands: all except 60/30/17/12; Cabrillo name `TXQP` per WA7BNM;
  robot site not yet live).

Research for seven more (MD-DC, Hawaii, Ohio, Tennessee, Colorado, Iowa,
New Jersey, New Hampshire, WA Salmon Run) is complete and banked in the
project notes; definitions land as they're built.

## Features

- **County-line logging, N1MM style.** Enter `LIN/AND` (or set your own
  location to up to 4 counties) and every county pair becomes its own log row —
  exactly what KSQP rule 11 requires ("a separate QSO must be logged for each
  county"). Rows share a group marker so they edit/delete together.
- **County abbreviation validation** against each party's official list
  (KSQP: 105 3-letter, TQP: 254 4-letter, both generated from the sponsors'
  official files). Typos get suggestions (`LNI` → `LIN`); the home-state token
  is rejected (Kansas stations always send a county).
- **Live scoring per party rules**: points by mode, single-count multipliers,
  KSQP's first-KS-county-counts-as-KS-state rule, dupes flagged but kept
  (sponsors want them), KS0KS +100 bonus, TQP mobile 5-county bonuses, and a
  "NEW MULT" badge before you log. KSQP 1×1 word tracker (KANSAS, QSOPARTY,
  SUNFLOWER, YELLOWBRICKROAD) with wildcard handling.
- **Elecraft K3/K3S/KX3/KX2 CAT** over serial (4800–38400 baud): live
  frequency/mode/TX polling (`IF;` — verified against Programmer's Reference
  revs F2 and G5), band stamped onto each QSO.
- **FlexRadio 6000/8000 CAT over TCP/IP** (SmartSDR API, port 4992): pick
  the radio in the radio bar, enter the Flex's IP, Connect. Push-based slice
  status (frequency/mode/TX via interlock), CW through the radio's CWX
  keyer, bidirectional WPM sync.
- **Auto-reconnect on open**: opening a contest file reconnects the last
  radio setup and *validates* it — if the radio doesn't answer within a few
  seconds you get told, instead of discovering a dead link mid-pileup.
- **CW keying two ways**: direct DTR/RTS line keying with sub-millisecond
  software timing (8–50 WPM, optional PTT line with lead/tail), or the
  radio's internal keyer (K3 `KY` / Flex CWX). F1–F8 messages with
  `{MYCALL} {CALL} {RST} {EXCH}` macros; **Esc aborts instantly**. Optional
  cut numbers for RST (599 → 5NN) in the CW Messages editor.
- **ESM (Enter Sends Message)** toggle right on the message row: Return
  sends CQ / exchange / TU based on what's filled in, and logs automatically
  after the exchange — N1MM muscle memory intact.
- **DX cluster spotting**: connect to any DXSpider/AR-Cluster telnet node
  (toolbar antenna icon), optionally **automatically when a contest opens**.
  Nodes you've used are remembered in a Recent Clusters menu, and the
  commands run at login are configurable — `sh/dx 30` by default, so the
  band map is populated with recent spots the moment you connect instead of
  starting empty. Current-band spots appear in the sidebar sorted by
  frequency, gray when already worked on this band+mode; click one to tune
  and pre-fill the call, or step spot-to-spot with ⌘← / ⌘→.
- **Band map window (⌘B)**: floating N1MM-style panel — vertical frequency
  ruler for the current band with spots plotted where they live, a red VFO
  marker tracking the radio, and a dashed CQ line marking your run
  frequency. Zoom 25/50/100 kHz or the whole band; click a spot to tune +
  fill the call, click empty map to QSY there. Remembers its position. This
  is the only place spots are shown — the score panel stays about scoring.
- **Spot filters** (funnel button in the band map), built for QSO party
  operating: **North American stations only** (drop DX you can't get an
  exchange from), **North American spotters only**, **hide stations already
  worked** on this band+mode, **hide RBN/skimmer spots**, per-mode (CW /
  phone / digital, inferred from the spotter's comment first and the band
  plan second), per-band, and how long spots live before ageing out
  (5 min – 2 hr, default 15). It's a panel, not a menu — tick as many boxes
  as you like in one visit — and everything applies instantly to the map and
  to ⌘← / ⌘→. All off by default; **Reset All** puts them back.
- **CQ frequency memory**: sending F1 (or starting repeat-CQ) in Run mode
  remembers the run frequency; ⌘J — or the chip next to Repeat — jumps back
  and flips you to Run after an S&P excursion.
- **Type-to-QSY in the call field**: `14025` or `14.025` tunes (kHz/MHz),
  `40M` jumps bands, `CW`/`SSB`/`USB`/`RTTY` switches mode — Enter executes.
  Anything that could be a callsign is treated as one; out-of-band numbers
  (like an RST) are ignored.
- **Score sidebar**: running total, QSOs-by-band/mode matrix, county grid
  with award tracking, per-class multiplier chips, bonus status, spots.
- **RST pre-filled** (599/59 by mode) after every contact, so the exchange
  is two keystrokes on a normal run.
- **Exports**: Cabrillo V3 (per-county-line QSO rows, category headers,
  claimed score) and ADIF 3.1.4 (`CNTY`/`MY_CNTY` with full county names,
  `STX_STRING`/`SRX_STRING`, group ids in an APP_ field).
- **Documents**: each contest is a `.qplog` file (JSON) with undo. New logs
  auto-save into your logs folder on setup, then **every QSO change writes
  straight to disk** (and mirrors to iCloud Drive if configured) — a crash
  never costs contacts.

## Keyboard reference

| Keys | Action |
| --- | --- |
| `Enter` | Log (or ESM next-message; or execute a typed QSY command) |
| `Space` | Jump to the next entry field (Call → Exchange) |
| `F12` | Wipe the entry fields and start the contact over |
| `F1`–`F8` | Send CW message (Run or S&P set) |
| `Esc` | Abort CW + stop repeat-CQ |
| `⌘=` / `⌘-` | CW speed ±2 WPM (syncs to the radio) |
| `⌘←` / `⌘→` | Tune to previous / next spot on the band |
| `⌘J` | Jump back to your CQ run frequency (Run mode) |
| `⌘B` | Toggle the band map window |
| `14025`, `7.040`, `40M`, `CW`, `SSB` in the call field | QSY / band / mode |
| `⌘E` / `⇧⌘E` | Export ADIF / Cabrillo |

## K3 wiring for direct CW keying

1. Connect the K3's RS-232 port (or KUSB adapter) to the Mac.
2. On the K3: `CONFIG:PTT-KEY` (menu 103) → set to `RTS-DTR` (PTT on RTS,
   CW key on DTR) — the app's default mapping, changeable in the radio bar.
3. In the app: pick the port, 38400 baud, Connect. The app deasserts both
   lines at open so the rig never keys on connect.

No extra interface is needed — same single-cable setup N1MM uses.

## FlexRadio setup

1. Radio bar → Radio: **FlexRadio 6000/8000 (TCP)**.
2. Enter the radio's IP (SmartSDR shows it; mDNS names work too) and port
   4992, then Connect. The app subscribes to slice/TX/CWX status — no
   polling, updates are instant.
3. CW keys through CWX automatically (there are no serial control lines to
   wire). Speed changes sync both ways.

The first connection triggers macOS's **Local Network** permission prompt —
allow it, or the Flex is unreachable (System Settings → Privacy & Security →
Local Network → QSO Party Logger if you dismissed it). The app keeps
retrying while the prompt is up, so approving it connects immediately.

## DX cluster spots

Toolbar → antenna icon → enter a cluster host/port → Connect. The app waits
for the node's actual login prompt, answers with your contest callsign, runs
the startup commands (`sh/dx 30` unless you change them), and filters the
stream to real spots on amateur bands — both live `DX de …` broadcasts and
the columnar `sh/dx` reply format. Spots carry their own timestamp, so a
`sh/dx` backfill shows true spot age; anything older than 15 minutes ages
out automatically. Telnet option negotiation is handled, so nodes behind a
real telnetd work too.

**North American spotters only** is a one-click filter for stateside QSO
parties, where EU/JA skimmer spots are noise: it keeps spots posted from the
US (incl. Alaska/Hawaii), Canada, Mexico, Central America, the Caribbean,
and Greenland, and drops the rest. It filters on the *spotter's* callsign —
the station that actually heard the signal — and applies instantly, with no
reconnect and no node-side filter commands, so it works on any cluster
software. Off by default. It lives with the mode, band, and age filters in
the band map's funnel panel.

The popover shows a **live node window** with everything the cluster says
and a box to type node commands (`sh/dx 30`, `set/skimmer`, `set/ft8`,
`bye`). If a node never answers, keeps re-prompting for a login, or accepts
you but sends nothing, the app says so rather than sitting silently
"connected" — and the node window shows exactly what happened.

Tick **Connect automatically when a contest opens** to have every contest
window come up already spotting. Previously used nodes are listed under
Recent Clusters.

Node notes: verified end-to-end against `dxc.wa9pie.net:8000` (DXSpider) and
`dxc.nc7j.com:7373` (AR-Cluster). `ve7cc.net:23` accepts the connection and
prints its banner, but never answers the login from this client — nothing
sent to it gets a reply — so use another node if you hit that.

## Adding a QSO party (no code)

Drop a JSON file in `~/Library/Application Support/QSOPartyLogger/Parties/`
(sandboxed apps: the container's equivalent path). Files there override
bundled parties with the same `id`. Schema (see `Resources/Parties/ksqp.json`
for a complete example):

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
  "notes": "Verify against current-year rules."
}
```

Malformed files are reported with the reason; the app keeps running with the
bundled parties.

## Adding a radio

Implement `RadioDriver` (see `Sources/Hardware/Radio/ElecraftK3Driver.swift`
for serial polling, `FlexRadioDriver.swift` for push-based TCP) and append a
`RadioDescriptor` in `RadioRegistry.all` — its `connection` field decides
whether the radio bar shows a serial port picker or host/port fields.
Kenwood-style ASCII radios can reuse most of the K3 driver's parsing
approach; network radios get `TCPTransport` for free.

## Building

```bash
xcodegen generate
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'
```

The app icon is drawn in code, not stored as artwork — rerun
`swift Tools/GenerateAppIcon.swift` after editing
[`Tools/GenerateAppIcon.swift`](Tools/GenerateAppIcon.swift) to rebuild every
size in `Resources/Assets.xcassets` (each size is drawn at its own
resolution, so 16pt stays crisp).

Requires Xcode 26 and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`). 220 unit tests cover the scoring engine, county
data, exporters, K3 and FlexRadio protocols, cluster login/telnet handling,
spot parsing (broadcast and `sh/dx`), spot filtering (continent, mode, band,
worked, skimmer), spot navigation, cluster history, the band map scale,
typed QSY commands, and keyer timing.

## Data provenance

- KSQP: rules + county abbreviations fetched from ksqsoparty.org (2026 rules
  PDF, official mults PDF) on 2026-07-23. County JSON generated by script
  from the official file — never hand-typed.
- TQP: rules from txqp.net; counties from the official `txcounty.zip`
  (2014 revision, current as of fetch). Marked `verified: partial` — confirm
  band list and current-year details before submitting.
- DC is accepted as a loggable state token (counted with states); strictly,
  KSQP rules enumerate 50 states — sponsors' checkers accept DC.

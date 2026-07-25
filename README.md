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
- **Maryland-DC QSO Party** (Aug 8, 2026) — verified against the official
  rules PDF (rev. 06 AUG 2024 v.5): 25 entities including Baltimore City
  separate from Baltimore County and DC as `WDC`, exchange is call +
  location with **no RST**, CW 3 / phone 1, mults once for the contest,
  Maryland never counts as a state, power × station-category final-score
  multipliers, W3VPR +50 and a tiered 250/500 jurisdiction sweep.
- **Hawaii QSO Party** (Aug 22–24, 2026) — 14 island **districts** rather than
  counties (Honolulu County alone is HON/LHN/PRL/WHN), taken from the sponsor's
  official multiplier map; out-of-state mults count **per band** (ceiling 84),
  Hawaii stations count everything **once**; all three modes legal with digital
  worth 3 points like CW. Marked `verified: partial` — the sponsor's own rule 1
  contradicts itself on the operating window (see below).
- **Ohio QSO Party** (Aug 22, 2026) — verified against the current MRRC rules
  (self-spotting is "[New 2026]"): 88 counties, mults **once per mode**, phone
  1 / CW 2, no digital. Only **11** Canadian provinces count, and `NT` is a
  *combined* Yukon–NWT–Nunavut multiplier, so `YT` and `NU` are rejected on
  entry the way the sponsor's official list requires. The rules' own "150
  multipliers for Ohio stations" is asserted end-to-end.
- **Kansas QSO Party** (Aug 29–30, 2026) — verified against the official 2026
  rules; 1×1 word tracker included.
- **Tennessee QSO Party** (Sep 6, 2026) — 95 counties, flat 3 points in every
  mode, mults **per band** (all 95 on two bands = 190), two-county lines
  allowed, DC counts as Maryland, K4TCG pays 100 bonus **per QSO** and TN
  mobiles 500 per county activated with 10+ QSOs. `verified: partial` — the
  posted rules document is still the 2025 edition.
- **Colorado QSO Party** (Sep 12, 2026) — verified against rules the sponsor
  itself dates "revised as of July 15, 2026". 64 counties with famously
  collision-prone codes (`MON` is Monte**zuma**, not Montrose), flat 2 points,
  mults **per mode**, no 160 m, two-county lines, 500-point bonus per county
  activated with 15+ QSOs. **New date for 2026** — the second Saturday in
  September, so older calendars may disagree.
- **New Jersey QSO Party** (Sep 12, 2026) — 21 counties (`CMDN` Camden, `WRRN`
  Warren — not truncations), mults counted **once**, phone 1 / CW 2 / digital 2,
  power as a **final-score multiplier** (High 1× / Low 2× / QRP 4×). All 13
  provinces count but Newfoundland is **`NF`**, not `NL`. Both of the sponsor's
  own worked score examples are reproduced in the tests. `verified: partial` —
  DC has no row in the official tables, and the works-only-NJ rule is implied
  rather than stated.
- **Iowa QSO Party** (Sep 19, 2026) — 99 counties with heavily clustered codes
  (`CLR`/`CLA`/`CLT`/`CLN`, `BTL` Butler not `BUT`, `OBR` O'Brien), mults **once
  only** by explicit rule, **four-county junctions** claimed in a single
  exchange, DC counts as Maryland, and Iowa itself is a multiplier earned via a
  county. First party where **DX scores points but is never a multiplier**.
  `verified: partial` — the posted rules are still the 2025 edition.
- **New Hampshire QSO Party** (Sep 19–20, 2026) — only 10 counties, and the
  multiplier scope runs **opposite** to most parties: out-of-state count NH
  counties **per band** (stated ceiling 50 = 10 × 5), while NH stations count one
  combined list **once**. Two operating windows totalling the rules' stated 22
  hours. `verified: partial` — and note the rules allow NH stations "up to 10
  DXCC country" while the exchange is the literal word "DX", so this app can only
  credit DX once (see provenance below).
- **Texas QSO Party** (Sep 19–20, 2026) — rules verified against txqp.net
  2026 (bands: all except 60/30/17/12; Cabrillo name `TXQP` per WA7BNM;
  robot site not yet live).
- **Washington Salmon Run** (Sep 19–20, 2026) — fully verified against WWDXC's
  rules. 39 counties with **mixed-length abbreviations** (3 *and* 4 chars, so
  `CLAL`/`CLAR` and `KITS`/`KITT` stay distinct), phone 2 / CW 3, no digital,
  mults once each, W7DX pays 500 **per mode** capped at 1000, and two windows
  totalling the rules' stated 23 hours. The only party where the 10-DXCC cap
  actually binds, because DX stations send their prefix rather than "DX".
- **Maine QSO Party** (Sep 26–27, 2026) — the party that breaks the most
  patterns. Points go by **who you worked, not how**: a Maine station is 2
  points and everyone else 1, CW and phone alike. Multipliers are the **same for
  everyone** — no in-state/out-of-state split — and count **once per band *and*
  per mode**, the first party needing that scope. Out-of-state entrants score
  non-Maine QSOs too, in the sponsor's own words. Canada is **14** tokens, not
  13, because Newfoundland (`NF`) and Labrador (`LB`) count separately and `NL`
  is invalid. 16 counties (`CBL` Cumberland, not `CUM`), six bands including
  160 m, no digital, and a county line is **two QSOs rather than one two-county
  QSO**. `verified: partial` — whether Maine itself is a state multiplier for
  Maine entrants is not stated.

- **California QSO Party** (Oct 3–4, 2026) — 58 counties in 4-letter codes, and
  the sponsor publishes the *formula* that makes them (`CCOS`, `LANG`, `MARN`,
  `MARP` are the stated exceptions; `San`/`Santa` fold to a single `S`), so the
  generator re-derives every abbreviation and asserts it matches. **Phone rose
  to 3 points for 2026** — CW and phone now pay alike. Multipliers are
  asymmetric: California stations count **states and provinces, never
  counties**, capped at **58 scored out of 63 possible**, with California itself
  earned via the first CA county worked — the first party to state that rule
  outright. Everyone else counts the 58 counties once each. DX scores points for
  California stations but is never a multiplier for anyone. **The exchange is a
  QSO number, not a signal report** — the entry bar shows a QSO-number pair
  instead of RSTs, and a county-line contact carries one number across all its
  rows.

- **Arizona QSO Party** (Oct 10, 2026) — the first party whose two sides use
  **different multiplier scopes**: Arizona stations count states, provinces and
  DXCC **per mode**, everyone else counts the 15 counties **per band and per
  mode** (the sponsor's own `15 × 6 × 2 = 180`). Every one of the 15
  abbreviations is irregular — `CHS`/`CNO` for Cochise/Coconino, `GHM`/`GLE`,
  `PMA`/`PNL`, `YVP`/`YMA` — and the sponsor publishes names and codes on two
  different pages as parallel lists, so the generator verifies the pairing three
  ways. DX sends a **prefix**, so entities are distinguishable here. K7A pays a
  one-time 100-point bonus; DC is *not* folded into Maryland. `verified: partial`
  — the published rules are still the 2025 revision under a 2026 banner.

- **Pennsylvania QSO Party** (Oct 10–11, 2026) — the first party whose
  non-county exchange is an **ARRL/RAC section**, not a state: `NTX` is valid and
  `TX` is not, `PA` itself is `EPA`/`WPA`, and Canada is **14 sections** where
  Ontario alone is four tokens (`GH`, `ONE`, `ONN`, `ONS`) and the territories
  are one (`TER`). PA stations count 67 counties + all 85 sections + **exactly
  1 DX**, everyone else the 67 counties, all **once** — and **EPA and WPA are
  granted outright**, since PA stations send a county so neither is ever
  transmitted. Serial-number exchange with no RST, QRP as a **×2 final-score
  multiplier**, 500 points per county a PA mobile activates with 10+ QSOs, and
  ten valid bands — the widest list here. `verified: partial` — the rules are the
  2025 revision and **the 2026 bonus station is not yet announced**, so none
  ships rather than crediting last year's call.

- **South Dakota QSO Party** (Oct 10–11, 2026) — 66 counties with **mixed 3/4
  character** codes (`DAY` is the lone 3-letter one), several vowel-dropped to
  break collisions (`BRWN` Brown vs `BROO` Brookings, `HNSN` Hanson vs `HAND`
  Hand), and `OGLA` for Oglala Lakota — Shannon County, renamed in 2015. Phone 1 /
  CW 2, mults **once** on both sides by explicit rule, W0OJY pays 100 **once for
  the contest**, county lines logged separately, ten bands (160 m–70 cm less
  WARC), and DX sends a prefix so DXCC countries count separately. The sponsor's
  own worked example — 50 phone × 20 counties + 100 bonus = 1,100 — is
  reproduced end-to-end in the tests. Cabrillo name is the short `SDQSOP`.
  `verified: partial` — the two standard open questions.

- **New York QSO Party** (Oct 17, 2026) — the best-documented party here: the
  sponsor's rules carry a county table, a Canadian list **and a full Cabrillo
  spec**, so `NY-QSO-PARTY` comes from the sponsor rather than from WA7BNM — the
  first party needing no fallback. **Digital pays 3 points, more than CW's 2** —
  also a first. The sponsor's arithmetic closes exactly: 50 states + 62 counties
  + 13 provinces = the stated **125** in-state maximum, which only works because
  "the first valid New York county logged will count as the multiplier for New
  York". DX scores points but never multiplies. County lines have a **stated
  maximum of two** counties, `/`-separated and logged as two QSOs. 62 counties
  with dense near-collisions (`CHA`/`CHE`/**`CGO`**, three Sch- counties,
  `STE`/`STL`) plus the five NYC boroughs. Eleven bands — the widest list here,
  and the only party permitting **60 m**. `verified: partial` — the rules are the
  2025 edition.

- **Illinois QSO Party** (Oct 18, 2026) — the season's last, and its shortest:
  **8 hours, Sunday only**. 102 counties with mixed 3/4 codes (`LEE` alone is
  three), and the rules name their own worst traps — `WHIT`/`WTSD`,
  `MASN`/`MACN` — which became the spot checks. Phone 1 / CW and digital 2,
  mults **once** with a **five-entity DX cap** that actually binds, county
  corners worth **2/3/4 counties as 2/3/4 QSOs**, and both club calls (`W9AWE`,
  `W9OAB`) paying 100 once each for 200 maximum. Eight bands — and unlike NYQP
  the sponsor **excludes 60 m**, counting it among the WARC bands.
  `verified: partial`, with two limitations recorded: ILQP's mode split is
  two-way (CW and digital are one mode for dupes, which this app doesn't flag),
  and FT4/FT8 earn no sponsor credit.

**Every US state and regional QSO party running through 2026-12-31 is now
bundled.** The season closed with Illinois on Oct 18; two independent calendars
agree there is no state or provincial party in November or December.
[`docs/parties/WORKLIST-2026.md`](docs/parties/WORKLIST-2026.md) keeps the
per-party status, the late re-verification schedule for the `verified: partial`
parties, and the remaining engine gaps. Adding a party is governed by
[`docs/CONSTITUTION.md`](docs/CONSTITUTION.md).

## Features

- **County-line logging, N1MM style.** Enter `LIN/AND` (or set your own
  location to up to 4 counties) and every county pair becomes its own log row —
  exactly what KSQP rule 11 requires ("a separate QSO must be logged for each
  county"). Rows share a group marker so they edit/delete together.
- **Serial-number exchanges.** Where a party sends a QSO number instead of a
  signal report, the entry bar shows the outgoing number (pre-filled with the
  next in sequence) and a field for theirs, and both reach Cabrillo's exchange
  columns and ADIF's `STX`/`SRX`. **A county-line contact is one contact and
  carries one number**, shared by every row it expands into — the operator sent
  one number on the air. Deleting a QSO never renumbers the others.
- **Run vs Search & Pounce follows your location.** An in-state log opens in
  Run — in-state stations are the multiplier everyone is chasing — and an
  out-of-state log opens in S&P. The mode is stored in the log, so reopening
  mid-contest restores the mode you were actually in, and it is only
  re-derived if you cross the state line.
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
  `{MYCALL} {CALL} {RST} {SERIAL} {EXCH}` macros, **defaulting to the party's
  own exchange shape** — CQP and PAQP send `{SERIAL}` where the report would
  go, MDC sends call and location only, and the messages editor warns (with a
  one-key fix, ⇧⌘D) when any message in either set contradicts its party's
  exchange. **Esc aborts instantly.** Optional cut numbers for reports and QSO
  numbers (0→T, 9→N: 599 → 5NN, 40 → 4T) in the CW Messages editor, with 1→A
  available separately for operators who cut harder.
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
  `40M` (or `222` for 1.25 m) jumps bands, `CW`/`SSB`/`USB`/`RTTY` switches
  mode — Enter executes.
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
| `Space` | Jump to the next entry field (Call → Exchange, or → QSO nr rcvd where the party sends one) |
| `F12` | Wipe the entry fields and start the contact over |
| `F1`–`F8` | Send CW message (Run or S&P set) |
| `⇧⌘D` | Restore the party's default CW messages (Messages editor) |
| `Esc` | Abort CW + stop repeat-CQ |
| `⌘=` / `⌘-` | CW speed ±2 WPM (syncs to the radio) |
| `⌘←` / `⌘→` | Tune to previous / next spot on the band |
| `⌘R` | Toggle Run / Search & Pounce |
| `⌘J` | Jump back to your CQ run frequency (Run mode) |
| `⌘B` | Toggle the band map window |
| `14025`, `7.040`, `40M`, `222`, `CW`, `SSB` in the call field | QSY / band / mode |
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
(`brew install xcodegen`). 644 unit tests cover the scoring engine, county
data, exporters, K3 and FlexRadio protocols, cluster login/telnet handling,
spot parsing (broadcast and `sh/dx`), spot filtering (continent, mode, band,
worked, skimmer), spot navigation, cluster history, the band map scale,
typed QSY commands, keyer timing, and keyer labelling.

## Data provenance

- KSQP: rules + county abbreviations fetched from ksqsoparty.org (2026 rules
  PDF, official mults PDF) on 2026-07-23. County JSON generated by script
  from the official file — never hand-typed.
- TQP: rules from txqp.net; counties from the official `txcounty.zip`
  (2014 revision, current as of fetch). Marked `verified: partial` — confirm
  band list and current-year details before submitting.
- MDC: rules + Table 1 entities from the sponsor's official PDF
  ("The Fun Contest Maryland-DC QSO Party Rules", rev. 06 AUG 2024 v.5,
  w3vpr.org) fetched 2026-07-23, sponsor page re-checked 2026-07-24. Entities
  generated from the committed rules text by
  [`docs/research/gen_mdc.py`](docs/research/gen_mdc.py) — never hand-typed.
  The sponsor has not published 2026 dates; the Aug 8 window is derived from
  the rules' "second Saturday in August" formula and cross-checked against two
  calendars.
- HQP: rules read verbatim from hawaiiqsoparty.org/rules-page/ on 2026-07-24.
  District abbreviations exist only on the sponsor's multiplier map
  (`docs/research/multmap_all.png`), transcribed to
  [`hqp_districts.tsv`](docs/research/hqp_districts.tsv) and generated by
  [`gen_hqp.py`](docs/research/gen_hqp.py). Marked `verified: partial`: the
  sponsor's rule 1 says "36 hours from 1800 UTC Aug 22 through 0359 UTC Aug 24"
  and *also* "6am Saturday … to 6pm Sunday in Hawaii" — those disagree (the
  literal UTC pair is 33h59m, and 1800Z is 8am HST). The shipped window is
  1600Z→0400Z, the only span matching both the stated 36 hours and both Hawaii
  times. Confirm with `info@hawaiiqsoparty.org` before submitting a log.
- OhQP: rules from ohqp.org (captured 2026-07-23, re-checked 2026-07-24);
  counties generated by [`gen_ohqp.py`](docs/research/gen_ohqp.py) from the
  sponsor's official multiplier list, which states "these abbreviations must be
  used … this list trumps all other lists". The generator asserts the rules'
  stated 150-multiplier total, which independently confirms the county count and
  Ohio's exclusion from the state list. Two sponsor typos ("Auglaze",
  "VanWert") are corrected in the display name with the abbreviations kept
  verbatim. The sponsor states it ignores Cabrillo headers entirely, so the
  `MRRC-OHQP` CONTEST value comes from WA7BNM's registry.
- TnQP: rules from the Tennessee Contest Group's posted document at tnqp.org
  (read 2026-07-23, page re-checked 2026-07-24 — still the same embedded DOCX,
  no 2026 revision announced). Counties generated by
  [`gen_tnqp.py`](docs/research/gen_tnqp.py) from the sponsor's official
  abbreviation PDF; `HARD` is Hardeman and `HARN` is Hardin, asserted in the
  generator. Cabrillo `TN-QSO-PARTY` comes from the sponsor's own Cabrillo
  template. `verified: partial` — the rules document is titled for 2025, so
  re-check in late August; and TnQP's extra self-activation *multiplier* for TN
  mobiles (distinct from the 500-point bonus, which is modeled) is not modeled.
- COQP: rules from coloradoqsoparty.org (captured 2026-07-23, re-fetched
  verbatim 2026-07-24); the page dates its own revision "July 15, 2026".
  Counties generated by [`gen_coqp.py`](docs/research/gen_coqp.py) from the
  sponsor's official abbreviation page, with the lookalike groups
  (`MON`/`MOT`/`MOF`/`MOR`, `LAK`/`LAP`/`LAR`/`LAA`, `ELP`/`ELB`,
  `SAG`/`SAJ`/`SAM`, `KIO`/`KIC`, `RIB`/`RIG`) asserted. The generator also
  asserts the rules' in-state ceiling of 128 mults per mode, which is what
  establishes that Colorado counts as a state multiplier earned via a county.
- NJQP: rules from the Burlington County Radio Club's official 2026 page
  (version `2026rev0.5`, captured 2026-07-23, re-read live 2026-07-24).
  **The sponsor's date contradicts the State QSO Party Challenge calendar** —
  the sponsor says Sep 12, the calendar said Sep 19, and WA7BNM agreed with the
  sponsor; Article 19 gives the sponsor authority. The multiplier tables exist
  only as images, committed as `docs/research/njqp_mults_*.png` and transcribed
  to [`njqp_counties.tsv`](docs/research/njqp_counties.tsv).
- IAQP: rules from w0yl.com/IAQP (captured 2026-07-23, re-checked live
  2026-07-24). Counties generated by
  [`gen_iaqp.py`](docs/research/gen_iaqp.py) from the sponsor's official county
  list, which pins 32 abbreviations by name because Iowa's codes cluster so
  badly. `verified: partial` — the page is still titled for 2025 and its rules
  PDF is dated 2018, with only the 2026 date announced; re-check in early
  September.
- NHQP: rules from w1wqm.org (revision "August 19, 2025", the one carrying the
  2026 dates), read verbatim 2026-07-24. The generator asserts the rules' own
  stated figures — a 50-multiplier out-of-state ceiling (10 counties × 5 bands)
  and a 22-hour total across two windows. **Known scoring limitation:** NH
  stations may count "up to 10 DXCC country", but every DX station sends the
  same literal token "DX", so without a DXCC prefix table this app credits DX as
  one multiplier and an NH entrant's count can run up to 9 low. Out-of-state
  entrants are unaffected — DX is not one of their multiplier classes.
- Salmon Run: rules from salmonrun.wwdxc.org ("Updated – July 22, 2024",
  re-read verbatim 2026-07-24); 2026 dates from the site-wide sidebar. Counties
  generated by [`gen_warun.py`](docs/research/gen_warun.py), which asserts the
  mixed 3/4 abbreviation lengths and the rules' in-state ceiling of 111
  (39 + 49 + 13 + 10). **Known limitation:** a DXCC prefix equal to a US state
  or province code is read as that state — `PA` (Netherlands) counts as
  Pennsylvania, `ON` (Belgium) as Ontario — the same resolution sponsors' log
  checkers apply, but it can leave the 10-DXCC allowance under-used.
- MEQP: rules from the Wireless Society of Southern Maine's official PDF
  (ws1sm.com/Images/Maine_QSO_Party_Rules.pdf, title block "2026 Official
  Rules") **and** rules page (ws1sm.com/MEQP.html), both read verbatim
  2026-07-24 — the two are not redundant, since the Canadian province list and
  the DC→MD note appear only on the page and the county-line rule only in the
  PDF. Counties and the 14 province tokens are parsed out of the committed
  source text by [`gen_meqp.py`](docs/research/gen_meqp.py); nothing is retyped.
  The sponsor publishes no multiplier ceiling, so the per-band-**and**-mode
  scope is verified against the sponsor's **own published results** instead: the
  2024 winner's 494,834 points on 1,212 QSOs factors only as 1,234 × 401, and
  401 multipliers is unreachable from a pool counted once or per mode. Those
  same numbers confirm the points rule (1,234 points on 1,212 QSOs = exactly 22
  two-point Maine contacts). The PDF's contest-period line misprints the year as
  2025; its own title block, its Oct 12 2026 deadline, the "last full weekend in
  September" formula, and the fact that 2025-09-26 was a Friday all settle it.
  **Known scoring limitation:** DXCC entities are multipliers for every entrant
  and uncapped, but the exchange is the literal token "DX" — the same missing
  prefix table that limits NHQP, biting harder here.
- CQP: rules from NCCC's official page and PDF (cqp.org/Rules.html and
  cqp.org/pdf/CQP_2026_Rules.pdf, both stamped "Last Update: 19-July-2026 at
  1500 UTC"), plus cqp.org/cqp_multipliers.html, which alone carries the county
  table, the DC→MD fold and the "1st CA county counts as CA" rule. Read verbatim
  2026-07-24. Counties are verified **twice** by
  [`gen_cqp.py`](docs/research/gen_cqp.py): parsed from the sponsor's table, then
  re-derived from the sponsor's own published abbreviation formula and asserted
  to match. **Rule change for 2026:** phone QSOs went from 2 points to 3, marked
  "**NEW in 2026**" by the sponsor; a full diff against the still-published 2025
  revision (Last Update 05-July-2025) shows it is the only substantive change.
  The exchange is "QSO number and 4-letter county abbreviation" and carries no
  RST; the QSO numbers reach Cabrillo's exchange columns, which is what CQP's log
  checker reads. Per the sponsor, county-line counties are sent "in a single
  exchange", so a county-line contact carries **one** number however many rows it
  logs.
- AZQP: rules from azqp.org/rules and the rules PDF linked there, read verbatim
  2026-07-24. `verified: partial` — **both are still the 2025 revision** (headed
  "2025 Arizona QSO Party", footer "Rev: 2501 6/23/2025"), so a 2026 rule change
  would not be visible; re-check before Oct 10. The **date** is not in doubt: the
  sponsor's site-wide banner gives "1500z Oct 10 to 0500z Oct 11, 2026 (UTC)",
  which agrees with the rules' own formula "2nd October Saturday, 8 AM to 10 PM
  (AZ)" — Arizona keeps MST year round, so 8 AM is 1500Z and 10 PM is 0500Z. The
  generator asserts both of the sponsor's multiplier totals, `(50 + 13 + DXCC) ×
  2` in-state and `15 × 6 × 2 = 180` out-of-state, which between them pin the
  county count, the band count and the mode count. County names and codes are
  published on two different pages as parallel lists, never paired, so
  [`gen_azqp.py`](docs/research/gen_azqp.py) verifies the positional pairing
  three ways — same codes in the same order from both sources, names
  alphabetical, and every code a subsequence of its county name (`CNO` ⊂
  `COCONINO`, `SCZ` ⊂ `SANTACRUZ`).
- PAQP: rules from the PA QSO Party Association's official PDF
  (paqso.org/files/PAQSO_Rules.pdf, 13 pages, footer "Revision: 08/19/25"), plus
  the sponsor's two official abbreviation PDFs — 67 counties and 85 ARRL/RAC
  sections — all read verbatim 2026-07-24. Both lists are parsed from the
  committed source text by [`gen_paqp.py`](docs/research/gen_paqp.py) with hard
  count assertions, and the rules state both counts independently (rule 10.b's
  "67 PA Counties", rule 16.a's "The 14 Canadian Sections"). `verified: partial`
  for two reasons: the rules are still the 2025 revision, and **the 2026 bonus
  station is unannounced**. Its value is not in doubt — the 2025 station N3XF
  published "1796 QSO's which results in 359,200 bonus points", exactly 200 per
  QSO — but shipping last year's call would credit a phantom bonus, so none
  ships. The **dates** are settled: the sponsor's banner says Oct 10 & 11 2026,
  the rules' own formula is "Always the 2nd Full Weekend in October", and their
  EDT parentheticals (1600Z = 1200EDT, 0400Z = midnight, …) still hold in 2026.
  **Known limitation:** the rules permit 630 m, 2200 m and microwave, which
  `Band` cannot express, so those QSOs cannot be logged; the sponsor itself
  describes typical activity as 160 m through 2 m.
- SDQP: rules from the Prairie Dog Amateur Radio Club's current page
  (sdqsoparty.com, headed "October 10 & 11, 2026"), read verbatim 2026-07-24.
  **Provenance hazard worth knowing:** the domain serves *two* rule pages — the
  root is current, while `/23-2/` is a stale WordPress copy still headed "2022
  CONTEST RULES" and still linked from search results. Nothing scoring-related
  differs between them, so this is not a rule change; the current page adds the
  explicit no-digital clause, a worked score example, and fuller bonus wording.
  Counties are generated by [`gen_sdqp.py`](docs/research/gen_sdqp.py), which
  asserts the mixed 3/4 lengths, that `DAY` is the only 3-letter code, and that
  the band list matches the sponsor's own suggested-frequency table row for row.
- NYQP: rules from the Rochester (NY) DX Association's official PDF ("2025 New
  York QSO Party", footer "v1.2 FINAL 2025-10-01"), read verbatim 2026-07-24, with
  the 62 county **codes cross-checked against the sponsor's own CSV** while the
  **names** come from the PDF's table — [`gen_nyqp.py`](docs/research/gen_nyqp.py)
  asserts the two sets agree exactly. The sponsor also states its Cabrillo
  `CONTEST:` value and its in-state multiplier maximum, both of which the
  generator asserts (50 + 62 + 13 = 125). `verified: partial` — no 2026 revision
  is posted, though the date is settled by the formula printed in the document's
  own title block ("Third Saturday in October") plus its EDT parentheticals.
  **Two readings worth knowing:** 60 m is included because the rules exclude only
  30/17/12 m, which no other bundled party does; and the sponsor's sample log
  contains 902 MHz, 1.2 GHz and 10 GHz QSOs, which `Band` cannot express, so
  microwave contacts cannot be logged.
- ILQP: rules from the Western Illinois ARC's official PDF ("Announcing the 2025
  Illinois QSO Party") plus the club's official county abbreviation PDF, both read
  verbatim 2026-07-24. **A secondary source was wrong and it mattered:** a web
  search reported that ILQP awards "one extra multiplier for every eight QSOs made
  with the same Illinois county". No such rule is in the sponsor's rules, and
  taking it on trust would have inflated every ILQP score —
  [`gen_ilqp.py`](docs/research/gen_ilqp.py) asserts the phrase is still absent.
  The generator also asserts the two abbreviation traps the rules name themselves,
  `WHIT`/`WTSD` and `MASN`/`MACN`; that second pair settles a conflict between two
  sponsor documents, since the site's FAQ says Macon is `MCON` while the county
  list and the rules both say `MACN`. *Retrieval note:* the rules PDF is on page 2
  of the site's file browser, which paginates in JavaScript with no link href.
- Band edges and ADIF band strings: the ADIF 3.1.4 Band Enumeration
  (adif.org/314/ADIF_314.htm), read 2026-07-24, cross-checked against
  47 CFR §97.301(a). Default per-band frequencies — used only for Cabrillo rows
  logged without CAT data — are the ARRL band plan's calling frequencies
  (arrl.org/band-plan, same date). 1.25 m is 222–225 MHz only: the US 219–220
  MHz point-to-point digital allocation is outside the ADIF band and is
  deliberately not loggable.
- DC is accepted as a loggable state token (counted with states); strictly,
  KSQP rules enumerate 50 states — sponsors' checkers accept DC.

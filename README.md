# QSO Party Logger

Mac-native QSO Party contest logger (SwiftUI, macOS 15+) with first-class
county-line support, live rules-based scoring, Elecraft K3 CAT control with
direct DTR/RTS CW keying, FlexRadio control over TCP/IP, DX cluster spotting,
and ADIF / Cabrillo export. Designed keyboard-first: logging, QSY, mode
changes, messages, and spot-hopping all happen without leaving the entry
field.

Built for KE5CW. Bundled parties, all with official county data:

- **Vermont QSO Party** (Feb 7–8, 2026) — the season's opener, and a party of
  extremes: the **longest window (48 hours)**, the **smallest county list (14)**,
  and the **highest CW value (3 points)** of any bundled party. Built from the
  sponsor's own 2026 rules document (RANV, footer `13-JAN-2026`) with the summary
  page cross-checking the county names. Mults **once per mode** on both sides,
  DC→MD, county lines paying "2 QSO's and 2 multipliers", and `W1AW/1` worth +2
  per QSO — a 2026-only America250 rule. The sponsor names its own worst trap and
  it became the spot check: `WNH` Windham vs `WNS` Windsor, neither of them
  `WIN`. `verified: partial`, with five limitations recorded — chief among them
  that VTQP's power multiplier is **×1.5 for low power**, which this app's
  whole-number score multiplier cannot represent, so **none is applied and you
  multiply the final score yourself**.
- **Minnesota QSO Party** (Feb 7, 2026) — ten hours, one Saturday. 87 counties,
  and the sponsor prints them **twice** — alphabetically by county and again by
  designator — so [`gen_mnqp.py`](docs/research/gen_mnqp.py) requires its two
  orderings to agree. Flat **2 points for every QSO**, phone and CW alike;
  multipliers count **once overall**, the only bundled party with that scope on
  both sides; all DX is worth exactly **one** multiplier. The sponsor states its
  own in-state maximum of **151**, and the app reproduces it exactly. DC counts
  as itself here, not as MD. County-line operation is **forbidden**.
  `verified: partial`: the exchange is a **first name** plus a location with no
  signal report, and this app has no name field — scoring is unaffected, but an
  exported Cabrillo log needs its name column filled in before submission.
  **Built from the archived 2026 edition** (`rev 31`): the sponsor now publishes
  only the 2027 rules, which change four scoring rules.
- **British Columbia QSO Party** (Feb 7–8, 2026) — **the first non-US party**.
  BC has no counties, so the county field carries its **43 federal electoral
  districts**, a list redrawn for the October 2025 election and new for 2026 —
  the sponsor's own Cabrillo sample still shows a retired code, which the
  generator asserts is absent. Two segments totalling the sponsor's stated 20
  hours. Phone 2 / **CW 4**, the highest CW value here; multipliers count **once
  per band *and* mode**; DC is lumped into MD, and Alaska and Hawaii are states
  rather than DX. `VA7ODX` pays **20 points per QSO**, added after multiplying.
  **Three of its rules exist only in the sponsor's FAQ** — DX earns points but no
  multiplier, "There is no power multiple", and there is no mobile/rover category
  at all — and each would have been a scoring error if only the rules page were
  read. `verified: partial` on one question: three sponsor documents list BC
  among the countable provinces, yet no BC station can ever send the token `BC`.
- **South Carolina QSO Party** (Feb 28 – Mar 1, 2026) — eleven hours, and the
  only bundled party whose window crosses a month boundary. **Points are paid by
  who was worked, not by mode**: 2 for a contact with an SC station, 4 for one
  outside, phone and CW and digital alike. Multipliers count **once per band and
  mode**; **three bonus stations** — `W4CAE` 350, `WW4SF` 250, `K4YTZ` 250 — each
  paying once in every one of the 24 band/mode slots. South Carolina is itself a
  multiplier reachable only through a county, which the sponsor states more
  plainly than any other party here. DC counts in its own right; US territories
  are DX. 46 counties with mixed 3/4 codes (`LEE` alone is three), and Calhoun is
  `CHOU` — the same code Alabama uses for its own Calhoun. `verified: partial`:
  the rules cap county-line operation nowhere, and SC mobile/expedition entrants
  undercount, since their per-county-activated **multiplier** is modelled here
  only as a bonus.
- **North Carolina QSO Party** (Mar 1, 2026) — ten hours, Sunday only. 100
  counties, and **the sponsor encodes each code as the dark-red letters of the
  county name**, not as its capitals: `CABarrus` is `CAB`, `DaViDson` is `DVD`.
  New Hanover proves the two rules differ — its capital `H` is black, so the code
  is `NEW`, not `NEWH` — so [`gen_ncqp.py`](docs/research/gen_ncqp.py) reads the
  PDF's colour and cross-checks all ten "Rarest of NC" codes against the rules.
  Phone 2 / CW 3 / **digital 5**, the only bundled party where digital outscores
  CW; multipliers count once overall to the sponsor's stated 164. No 160 m.
  **`verified: partial`, and this one's gaps are the largest in the app**: QSOs
  with ten designated "Rarest of NC" counties are worth **10×** *before*
  multiplication, and five of those ten pays a further 500 — neither is
  expressible, so an NCQP score here is a floor, with the correcting arithmetic
  spelled out in the party's notes. FT8/FT4 belong to a separate Weak Signal
  Showcase and must be kept out of this log.
- **Oklahoma QSO Party** (Mar 14–15, 2026) — 20 hours in two windows. 77
  counties, and **the sponsor names its own traps**: seven pairs it says "cause
  considerable confusion" (`GAR`/`GRV`, `GRA`/`GNT`, `HAR`/`HRP`, `MCL`/`MCU`,
  `ROG`/`RGM`, `WAS`/`WAT`, `WOO`/`WDW`), every one of which the naive first
  three letters gets backwards. Phone 2 / CW 3 / digital 3; multipliers once
  overall, with **uncapped DXCC** for Oklahoma stations. County lines pay up to
  **four**, each on its own log line — the sponsor names a real three-county
  junction. Oklahoma mobiles earn 500 points per county with ≥10 QSOs, which is
  modelled. **`verified: partial`** on whether Oklahoma itself counts via a
  county — and note that `qsl.net/okdxa/OKQP.htm`, still the top search result,
  is the **2003** rules and wrong four ways.
- **Idaho QSO Party** (Mar 14–15, 2026) — "The SPUD RUN", 24 hours in two
  windows. **Its dates are reconstructed, not copied:** the sponsor's date block
  carries four errors in eleven lines, including a literal `xxxxZ` placeholder
  where the Saturday start should be. The windows come from the three things that
  do agree — the formula, the printed "12 Hours" per day, and the local anchors
  read under **EDT** (daylight time began the weekend before). No signal report
  in the exchange; multipliers once **per mode**; Idaho itself counts through a
  county. 44 counties, and the `B` cluster is the worst in the app — ten counties
  begin with B and **`BON` is not a code at all**, since Bonner (`BNR`) and
  Bonneville (`BNV`) would both claim it. `verified: partial`: QRP QSOs are worth
  5 points and this app pays the normal rate, and the tiered dormant-county bonus
  can't be expressed. Also one of 7QP's seven states.
- **Wisconsin QSO Party** (Mar 15, 2026) — seven hours, the **shortest total
  operating time** of any bundled party. 72 counties with three dense clusters:
  three `Mar-` counties of which only Marathon is `MAR`, three `Gr-` counties
  including `GRE` Green against `GRL` Green Lake, and six `W-` counties.
  Multipliers count once overall to the sponsor's stated 135; Wisconsin itself
  counts through a county; DX earns points but no multiplier. Ten bands — the
  largest list here — derived from the suggested-frequency table, since the rules
  publish none. **Reading the sponsor's Cabrillo guide changed a field:** its
  rules say DX sends "Country", but its own example logs `DL6QK` as the literal
  token `DX`. `verified: partial` — its power multiplier is **×1.5 for low
  power**, the same gap Vermont has.
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

**Every US state and regional QSO party running from 2026-07-24 through
2026-12-31 is bundled**, and the season's earlier parties are being added in
contest-date order — Vermont, Minnesota, British Columbia, South Carolina, North
Carolina, Oklahoma, Idaho and Wisconsin are in. The 2026 season runs
Feb 7 → Oct 18; two independent calendars agree there is no state or provincial
party in January, November or December. **21 parties from March through June
remain**, listed in
contest-date order in
[`docs/parties/WORKLIST-2026.md`](docs/parties/WORKLIST-2026.md), which keeps the
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
  is rejected (Kansas stations always send a county). County lines are typed
  `LIN/AND` or `LIN,AND` — **space is not a separator**, because Space moves
  the cursor. Validation follows **where you are operating from**: an
  out-of-state entrant is checked against what it can actually receive, so on
  the seven parties where DX sends a prefix a mistyped county is an error
  rather than being read as a DX entity.
- **Live scoring per party rules**: points by mode, single-count multipliers,
  KSQP's first-KS-county-counts-as-KS-state rule, dupes flagged but kept
  (sponsors want them), KS0KS +100 bonus, TQP mobile 5-county bonuses, and a
  "NEW MULT" badge before you log. KSQP 1×1 word tracker (KANSAS, QSOPARTY,
  SUNFLOWER, YELLOWBRICKROAD) with wildcard handling.
- **Worked before**: type or tune to a call already in the log and a table
  appears between the F-keys and the log listing every prior contact with him —
  band, mode, time, and what he sent. The entry for the band and mode you are on
  right now is bold and orange: nothing left to work here. A county-line contact
  is one row, not two. It takes no space at all for a station you have not
  worked, and the room comes out of the log table rather than out of the window,
  so nothing resizes.
- **Exchange pre-fill**: work a station on a new band and his county or state is
  already in the field, taken from your most recent contact with him — or, when
  this contest has never worked him, from previous contests in the history
  archive. A county only carries over within the same sponsor's party: Colorado
  and Kansas both abbreviate Jefferson County `JEF`, so a Colorado exchange
  parses perfectly as a Kansas county and is still wrong. Every candidate has to
  survive the current party's own exchange parser before it is offered.
  Pre-filled text is greyed until you type over it, and it withdraws itself if
  the call changes.
- **Copied, not lost**: a station you can hear but who cannot hear you takes an
  exchange to copy and gives no contact for it. Moving to the next spot clears
  the field so nothing is logged against the wrong station, and keeps what you
  copied under his call — land back on him, by spot, by ⌘arrow, or by typing his
  call, and it is there again. Typing is untouched: only a deliberate move to
  another station stashes, so fixing a typo in a call never costs the exchange
  underneath it.
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
  `{MYCALL} {CALL} {RST} {SERIAL} {EXCH}` macros (defined once, in
  `MacroToken` — the editor lists whatever that enum holds), **defaulting to the party's
  own exchange shape** — CQP and PAQP send `{SERIAL}` where the report would
  go, MDC sends call and location only, and the messages editor warns (with a
  one-key fix, ⇧⌘R) when any message in either set contradicts its party's
  exchange. **Esc aborts instantly.** Optional cut numbers for reports and QSO
  numbers (0→T, 9→N: 599 → 5NN, 40 → 4T) in the CW Messages editor, with 1→A
  available separately for operators who cut harder.
- **ESM (Enter Sends Message)** toggle right on the message row, and **the
  call field never logs**. While the cursor is in it Return only ever calls —
  your call pouncing, his call and report running — however complete the row
  looks. Move to the exchange and the same Return logs and sends your report.
  That is what a **prefilled exchange** needs: hunting a station whose county
  you copied off his last QSO, the row holds a call and a valid exchange
  before you have worked him, and keeps holding them while he works three
  other people. Every one of those Returns keeps calling. Sitting in the
  exchange field with a county that matches nothing, Return sends **AGN?** —
  he is already talking to you, so the thing to do is ask him to repeat, not
  call him again. ESM never moves the cursor for you (Space does), and the
  F-key Return will key next is **outlined**, so what it is about to do is
  visible rather than guessed at.
- **DX cluster spotting**: connect to any DXSpider/AR-Cluster telnet node
  (toolbar antenna icon), optionally **automatically when a contest opens**.
  Nodes you've used are remembered in a Recent Clusters menu, and the
  commands run at login are configurable — `sh/dx 30` by default, so the
  band map is populated with recent spots the moment you connect instead of
  starting empty. Click a spot to tune and pre-fill the call, or step
  spot-to-spot with ⌘← / ⌘→ or ⌘↓ / ⌘↑.
- **QSO Party Hub spots**: several sponsors point their operators at
  [qsopartyhub.com](http://qsopartyhub.com) to self-spot, and unlike a cluster
  spot those carry the **county** — the multiplier the party is actually
  scored on. The app polls the active party's page alongside your cluster,
  badges each spot with its county, and highlights the ones that are still
  multipliers. 17 of the 19 bundled parties are covered (California's page is
  an unfinished stub and WA Salmon Run has none). Polling only runs inside the
  party's own operating window.
- **Exchange pre-fill from a spot**: when nothing in your own log or the
  archive knows a station, a hub spot's county fills the exchange as a last
  resort — shown **unconfirmed** (dashed, with a reminder) rather than merely
  provisional. A spotter's county is their claim about a station you've never
  worked, and a wrong one is cross-checked against their log. Anything you
  copied, and anything you worked before, outranks it. Toggle in the band map
  funnel.
- **Rovers stop hiding**: a mobile that changes county is a new contact, and
  now the band map knows it. Work a rover in one county and it greys out; the
  moment it spots from a county you still need it comes back, un-greyed and
  back in the ⌘← / ⌘→ / ⌘↑ / ⌘↓ rotation. Cluster spots never carried a
  county, so this was invisible before.
- **Band map window (⌘B)**: floating N1MM-style panel — vertical frequency
  ruler for the current band with spots plotted where they live, a red VFO
  marker tracking the radio, and a dashed CQ line marking your run
  frequency. Zoom 25/50/100 kHz or the whole band; click a spot to tune +
  fill the call, click empty map to QSY there. Remembers its position, and
  stays on screen when another app takes focus, so it can sit beside a
  panadapter in SmartSDR rather than disappearing the moment you click one.
  This is the only place spots are shown — the score panel stays about scoring.
- **Spot label size** (S / M / L / XL at the top of the funnel popover): the
  callsign is drawn at 10, 12, 14 or 16 pt, for a dense display or an operating
  position you read from across the room. Small is the default and is exactly
  what the map has always drawn. The column pitch and row clearance travel with
  the size rather than staying fixed, so bigger calls stack into wider columns
  instead of overlapping — and because a wider column needs a wider panel, the
  panel's minimum width grows with the size to keep at least two columns
  available. **Reset All** leaves it alone: that button is about filters.
- **Stacked spots**: a pile-up no longer shoves labels off frequency. Spots
  too close to plot separately fan out **sideways** into a second and third
  column, each one still drawn at its own frequency, and the column count
  follows the panel width — widen the panel to spread a pile-up. Nothing is
  ever dropped: twenty calls on one frequency show all twenty.
- **Worked stations stay visible**: a call already in the log on this
  band+mode is greyed and struck through rather than removed, so you can see
  the band filling up — and ⌘← / ⌘→ / ⌘↑ / ⌘↓ steps straight over it, because there is
  nothing left to work there. If every spot on the band is worked, the keys
  leave the radio where it is.
- **Stations you worked land on the map**: work someone nobody spotted and he
  used to leave no trace — ten minutes later his frequency read as empty. Now
  logging a contact puts him on the band map at the frequency you worked him
  on, struck through like any other worked call, carrying the exchange he
  sent. N1MM's bandmap has always carried locally-added calls beside network
  ones. He is added only when nobody has already spotted him, so another
  operator's spot keeps its own reported frequency, and only when the radio
  gave a frequency to place him at — a contact logged with no radio is not
  given a guessed one. They age out on the same **Age out after** setting as
  cluster spots, and *Hide stations already worked* clears them all.
- **Band-plan-aware mode switching**: tune into the phone portion of a band
  and the radio goes to SSB; tune into the CW portion and it goes to CW. It
  fires only when *the app* moves you — clicking a spot, typing a frequency
  or band, ⌘← / ⌘→ / ⌘↑ / ⌘↓, ⌘J — so your own VFO knob never triggers a mode change
  mid-QSO. It never selects a digital mode, never fights a RTTY operator
  working the data segment, and never picks a mode the party doesn't score.
  Crossovers come from 47 CFR §97.305(c) (with §97.301(a) for the 80/75 m
  split and the ARRL band plan for 160 m); 60 m, 1.25 m and 70 cm have no
  defensible CW/phone boundary, so there the mode is left alone. On by
  default — untick **Follow band plan on QSY** in the band map popover.
- **Spot filters** (funnel button in the band map), built for QSO party
  operating: **North American stations only** (drop DX you can't get an
  exchange from), **North American spotters only**, **hide stations already
  worked** on this band+mode (off by default — worked calls normally stay
  greyed), **hide RBN/skimmer spots**, per-mode (CW / phone / digital,
  inferred from the spotter's comment first and the band plan second, then
  held to the modes the active party actually permits — in a party with no
  digital class, the digital sub-band is CW, which is where that activity
  really sits), per-band, and how long spots live before ageing out (5 min – 2 hr,
  default 15). It's a panel, not a menu — tick as many boxes as you like in
  one visit — and everything applies instantly to the map and to the spot keys.
  All filters off by default; **Reset All** puts them back, along with the
  age-out and the band-plan toggle. The same popover carries the **spot label
  size** picker above the filters — that one **Reset All** deliberately leaves
  alone, since clearing a band filter is no reason to resize your text.
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
- **Contest Dashboard (⌘⇧D)**: your whole season in one window. Pick a year
  (⌘[ / ⌘]) and see totals, every contest's claimed score exactly as the
  score sidebar computed it (QSOs, mults, bonus, on-air time with ≥30-min
  breaks excluded), QSO and score charts, and each party's year-over-year
  trend with your personal best flagged. Return (or double-click) on a row
  reopens that contest's `.qplog`.
- **State QSO Party Challenge tracker**: estimated standing by the sponsor's
  own formula — total QSOs × parties entered, with the official ≥2-QSO
  multiplier floor and the Bronze 500 → Diamond 100,000 ladder (levels
  require two qualifying parties). A 1-QSO party shows "1 more QSO to
  count"; parties logged but not on the 2026 approved list (Maine) are shown
  and excluded rather than silently dropped. Labeled an estimate: the
  official score comes from what you post to 3830scores.com.
- **Upcoming contests**: everything left this season, soonest first — an ON
  AIR badge while a window is open, countdowns, "entered ✓" once you've
  logged it, and all 47 SQP-Challenge-approved parties included: bundled
  ones use the sponsor's verified schedule, the rest are dated from the
  challenge's calendar and labeled so (that calendar has been wrong before —
  NJQP 2026 — so the sponsor always wins where this app has rules).
- **One history file in iCloud**: every save also archives the full log +
  score snapshot into `Contest History.qphistory` in your logs folder, so
  the dashboard — logs and statistics both — follows you to any Mac. Edits
  from two Macs merge by QSO (the later save wins conflicts, nothing is
  lost); iCloud conflict copies fold in automatically; a corrupt file is
  never overwritten. "Import Existing Logs" (or first launch with an empty
  history) rebuilds the archive from the `.qplog` files already in the
  folder, idempotently. Snapshots freeze each score as computed that season,
  so next year's rule updates never rewrite history.

## Keyboard reference

| Keys | Action |
| --- | --- |
| `Enter` | Log (or ESM next-message; or execute a typed QSY command) |
| `Space` | Cycle the entry fields — Call → Exchange → Call, via QSO nr rcvd where the party sends one. Signal reports are stepped over |
| `Tab` | Walk every entry field, signal reports included — landing in one selects the S digit, so 599 → 579 is a single keystroke |
| `F12` | Wipe the entry fields and start the contact over |
| `F1`–`F8` | Send CW message (Run or S&P set) |
| `⇧⌘R` | Restore the party’s default CW messages (Messages editor) |
| `Esc` | Abort CW + stop repeat-CQ — and close the sheet, when one is open |
| `⌘=` / `⌘-` | CW speed ±2 WPM (syncs to the radio) |
| `⌘←` / `⌘→` | Tune to previous / next unworked spot on the band |
| `⌘↓` / `⌘↑` | The same, on the vertical axis — `⌘↑` goes up the band map |
| `⌘R` | Toggle Run / Search & Pounce |
| `⌘J` | Jump back to your CQ run frequency (Run mode) |
| `⌘B` | Toggle the band map window |
| `14025`, `7.040`, `40M`, `222`, `CW`, `SSB` in the call field | QSY / band / mode |
| `⌘E` / `⇧⌘E` | Export ADIF / Cabrillo |
| `⇧⌘S` | Spot to the QSO Party Hub — yourself in Run, the call field in S&P (Return sends, Esc cancels) |
| `⌘⇧D` | Contest Dashboard (season history + SQP Challenge) |
| `⌘[` / `⌘]` | Dashboard: previous / next year |
| `⌘R` | Dashboard: re-read the history file |
| `Return` on a dashboard row | Open that contest's log |

These keys belong to the log window that has focus. While a sheet is open —
Setup, the Messages editor, Edit QSO — the sheet owns the keyboard: `Esc` closes
it and `F1`–`F8` do not transmit, so revising F2 and pressing it never keys the
old message. `Esc` still aborts CW instantly in either place (Article 11). With
two logs open, the F-keys act on the one you are typing in.

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
for the node's actual login prompt — whether the node leaves it unterminated
(`login: `) or ends it with a newline, as local skimmer feeds tend to —
answers with your contest callsign, runs
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

A cluster on the same Mac works the same way: point it at
`localhost` and the port your feed serves — a local SDC skimmer collector on
`localhost:7373`, say — and it logs in, backfills with `sh/dx`, and streams
live decodes like any remote node.

## QSO Party Hub spots

Several sponsors — South Dakota, Iowa and Pennsylvania among them — tell their
operators to self-spot at [qsopartyhub.com](http://qsopartyhub.com) rather than
on a cluster. Those spots carry something no cluster spot ever does: the
**county**. That is the multiplier a state QSO party is scored on, so the app
polls the active party's page and puts the county straight on the band map,
highlighted when it is still a multiplier worth chasing.

It runs **alongside** your cluster, not instead of it. Both feeds land in the
same band map with the same filters and the same ⌘← / ⌘→ rotation, and a spot
seen on both is a single entry. Be realistic about volume: the hub is a
volunteer-run board that may hold a handful of spots where a cluster holds
hundreds. Its value is the county, not the count — the funnel panel has a
**QSO Party Hub spots only** filter for when you are hunting multipliers and
the cluster is drowning them out.

Because those spots are hand-posted rather than skimmer-fed, they live longer:
60 minutes by default against the cluster's 15, matching what the hub itself
keeps. At the cluster's setting a typical hub table would empty on arrival.

Polling only happens inside the party's own operating window (plus half an
hour either side), one request a minute — lighter than leaving the page open
in a browser tab, which refreshes itself every 53 seconds.

Two of the 19 bundled parties are not covered, and the app says so rather than
polling a dead page: California's hub page is an unfinished sponsor template,
and WA Salmon Run has no page at all.

What the app will not do is guess. The table's columns are read by position,
so if the hub ever changes them the app stops reading rather than showing you
a county from the wrong column. Rows it cannot parse are listed rather than
silently dropped, a frequency it had to reconstruct from a malformed entry is
flagged before you tune there, and a call the board has already corrected —
these boards keep the typo alongside the fix — is greyed and stepped over.

### Spotting (⇧⌘S, or right-click)

One shortcut, and your operating mode decides who it means. Calling CQ, you
want yourself on the board; hunting, you want the station you just found. Two
commands a modifier apart only ever produced a sheet with the wrong call in it
mid-QSO.

| Mode | Call field | ⇧⌘S spots |
| --- | --- | --- |
| Run | anything | **you** — your call, the VFO, your counties from the log |
| S&P | `N4RT` | **N4RT** — the VFO, and the county out of the exchange you have copied so far |
| S&P | empty | a blank sheet, cursor in the call field, for a call you heard but have not typed |

The toolbar button says which one it is before you press it, and names the
call. Run ignores the call field on purpose: half a call typed while you are
running still means your own run.

The hub is not a self-spot board — in the live ALQP capture every spot was
posted by one operator for other stations — so you can also **right-click a
spot** on the band map, including one that came from your own log, or
**right-click a row in the log** to spot a station you worked earlier.

**Every send is confirmed first.** The hub's form has no CSRF token, no
authentication and no session — whatever is posted reaches a public board
instantly, and submitting twice posts twice. An identical spot repeated within
five minutes is refused, though changing frequency or county never counts as a
repeat, because those are exactly when a re-spot matters.

**County lines go out whole.** The county field is free text, and an operator
on a line spots as `MDSN/LIME`. A spot naming only the first county tells
somebody hunting the second to skip a station that would have given them the
multiplier. Every county is checked against this party's own list before it can
be sent, and each is translated to the hub's own spelling separately — Illinois'
`PULA/JACK` goes out as `PULS/JACK`.

**Rovers get prompted.** Change county in the log and the spot sheet opens by
itself, pre-filled for the new counties — including a line that changed in its
second position only. It still never posts on its own; it just stops the county
change from being the thing you forget.

Nothing is invented. The county is only offered when it really is one of this
party's counties, so an out-of-state `TX`, a `DX`, or a half-copied exchange is
never posted as one. With no radio connected there is no frequency to offer, so
the sheet opens on an empty frequency field and holds the send until you type
one — a guess on a public board is worse than a blank. Frequency goes out in
clean kilohertz, the one thing this app can do to reduce the ambiguity its own
parser exists to resolve.

A 200 back from the hub means *sent*, not *accepted* — the page re-renders
rather than reporting a status. The app therefore watches the next couple of
polls for your call to appear and says **confirmed on the board** only once it
has actually seen it. If it never shows up you are told, rather than left
sitting on a frequency believing you are advertised.

Node notes: verified end-to-end against `dxc.wa9pie.net:8000` (DXSpider),
`dxc.nc7j.com:7373` (AR-Cluster), and SDC's telnet server on
`localhost:7373`. `ve7cc.net:23` accepts the connection and
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
(`brew install xcodegen`). 1179 unit tests cover the scoring engine, county
data, exporters, K3 and FlexRadio protocols and the radio registry's
app-facing defaults, cluster login/telnet handling,
spot parsing (broadcast and `sh/dx`), spot filtering (continent, mode, band,
worked, skimmer), spot navigation including worked-station skipping, contacts
from your own log reaching the band map (and never displacing somebody else's
spot), what a spot sheet may offer as a county for any station, cluster
history, the band map scale and its column stacking (including that every
label-size preset still leaves room for two columns, so a pile-up never falls
back to pushing labels off frequency), the band plan and its
CW/phone crossovers, typed QSY commands, the key-monitor focus gate and its key
table, what the radio keys on every step of the entry flow, the CW messages
editor's Restore Defaults and exchange-mismatch banner, keyer timing, keyer
labelling, the contest history archive (snapshot parity with the engine,
two-Mac merge, unknown-field preservation, coordinated store), season stats,
the SQP Challenge formula and calendar resource, and the upcoming-contest
engine.

What goes on the air is decided by
[`EntryFlow`](Sources/App/EntryFlow.swift), not by the view. It returns the
string it would key and `MainView` hands that to the radio, so a test can drive
the real sequences — Contest Setup changes the party, then F2; ESM Return in
Search & Pounce, then compare the keyed number against the one written to the
log. Two 2026-07-25 bugs that put both stations out of each other's logs went
through eight review rounds undetected because this code was private to a
SwiftUI `View`; `Tests/App/EntryFlowTests.swift` reproduces both.

The test bundle is hosted inside the app executable, so `UserDefaults.standard`
inside a test would be the real `org.b5n.QSOPartyLogger` preference domain.
Every preference therefore goes through `Preferences.store`, which
[`Tests/TestBundleSetup.swift`](Tests/TestBundleSetup.swift) points at a
throwaway suite before the first test runs — a full run leaves your saved
station profile, radio wiring and cluster history untouched.

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
- ALQP: the **2026 rules page** (alabamacontestgroup.org/aqp/rules/, fetched
  2026-07-25, extracted to [`alqp_rules_2026.txt`](docs/research/alqp_rules_2026.txt))
  states it as the party Object — "Stations outside of Alabama make contact with
  Alabama amateur radio stations and as many Alabama counties as possible" —
  with out-of-state multipliers capped at "Maximum of 67 Alabama counties".
  Resolved as for the other aim-not-prohibition parties; analysis in
  [`alqp_out_of_state_credit.md`](docs/research/alqp_out_of_state_credit.md).
  The short `/aqp-rules/` path 404s; the rules are at `/aqp/rules/`.
- KSQP: the **2026 rules PDF** (ksqsoparty.org, fetched 2026-07-25, extracted to
  [`ksqp_rules_2026.txt`](docs/research/ksqp_rules_2026.txt)) states the
  restriction as the party's OBJECT and names both sides — "Stations outside of
  Kansas work as many Kansas stations in as many Kansas counties as possible.
  Stations in Kansas work everyone" — with the multiplier table capping
  non-Kansas entrants at "105 Kansas county multipliers". Resolved as for the
  other aim-not-prohibition parties; analysis in
  [`ksqp_out_of_state_credit.md`](docs/research/ksqp_out_of_state_credit.md).
  That PDF also carries an **FT4/8 category** the bundled definition predates.
- TQP: the **operating rules** at txqp.net (fetched 2026-07-25, extracted to
  [`tqp_operating_rules.txt`](docs/research/tqp_operating_rules.txt)) write the
  out-of-state restriction into the QSO points rule itself — a non-Texas station
  counts points only "with any Texas station" — so a non-Texas entrant earns
  nothing for working another non-Texas station. Best-evidenced instance of that
  rule in the catalogue after MDC 10b; analysis in
  [`tqp_out_of_state_credit.md`](docs/research/tqp_out_of_state_credit.md). Note
  `txqp.net/rules/` 404s; the rules live under the Joomla `index.php` path.
- **DX prefixes, all parties.** Where DX stations send a prefix rather than the
  literal `DX` (`alqp`, `azqp`, `ilqp`, `mdc`, `sdqp`, `tnqp`, `warun`), a token
  matching no county, state or section is guessed at as a DXCC prefix, because
  a prefix really can be almost any short string and there is no DXCC table
  here to check against. The guess now runs **only where DX is a multiplier
  class for the operator's own role**, which removes it entirely for
  out-of-state entrants and makes their typos errors again. **Known limitation:**
  an *in-state* entrant on those parties still has the loose guess, so a
  mistyped county can still be accepted as a DX entity. Only a real DXCC prefix
  table fixes that, and it would also close the NHQP and MEQP limitations below.
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
- VTQP: rules from the Radio Amateurs of Northern Vermont's **official 2026 rules
  document** (`ranv.org/vtqso.doc`, titled "VERMONT QSO Party Rules", created
  2026-01-13, footer `13-JAN-2026`) with the RANV summary page
  (`ranv.org/vtqso.html`, page-dated January 31 2026) alongside it, both read
  verbatim 2026-07-26. The page says outright that it is a summary and that the
  `.doc` carries the specific rules, so the `.doc` is the authority; the page
  supplies only the county **names**, since the `.doc` prints abbreviations only.
  [`gen_vtqp.py`](docs/research/gen_vtqp.py) makes the two documents check each
  other — names parsed from the page's table, and the resulting abbreviation set
  asserted equal to the `.doc`'s own sentence "14 Vermont Counties: ADD, BEN, …".
  It also asserts the sponsor's own trap note ("Take care to not mix up WiNdHam
  (WNH) and WiNdSor (WNS)!!") and that `GRA` is Grand Isle, not the "Grand Island"
  that appears in one operating-schedule line. **This is the first party in the
  repo built entirely from a current-year rules document since MEQP** — nothing
  here rests on a stale edition. `verified: partial` all the same, because five
  verified rules cannot be expressed: the **×1.5 low-power score multiplier**
  (whole numbers only, so none is applied), the W1AW/1 bonus being out-of-state
  only, RTTY and FT8 sharing one mode class where the sponsor counts two,
  30/17/12 m shipping as fully valid when the sponsor allows them for FT8/FT4
  only, and two absent multiplier kinds — approved club stations (`W1NVT`) and
  grid squares. Two genuine unknowns are open: whether Vermont is a state
  multiplier for Vermont entrants, and whether 60 m is legal.
- MNQP: rules from the Minnesota Wireless Association's **2026** document,
  `MNQP_Contest_Rules rev 31.pdf`, footer `Rev 31 – December 31, 2025`, read
  verbatim 2026-07-26, with the sponsor's official county multiplier list PDF.
  Counties are generated by [`gen_mnqp.py`](docs/research/gen_mnqp.py), which
  parses the sponsor's list **twice** — the PDF prints all 87 alphabetically by
  county *and* alphabetically by designator — and requires the two orderings to
  agree. **The live site no longer serves the 2026 rules.** w0aa.org now
  publishes only `MNQP_2027_Contest_Rules_A.pdf`, which flags four of its own
  changes as "NEW 2027": multipliers move to once-per-mode, in-state county
  multipliers stop counting for MN stations while Minnesota itself starts
  counting, CW rises from 2 points to 3, and rovers gain two-county operation.
  Building from the live document would have been wrong in all four. Rev 31 was
  recovered from the Wayback Machine snapshot of 2026-02-09, whose copy of the
  rules page reads "last updated for the 2026 QSO Party" and links exactly that
  file; the generator pins both editions so a future re-verification cannot
  apply the 2027 rules by accident or miss them. *Two retrieval notes:* the
  sponsor's own changelog sentence is stale and identical in both years, badly
  understating the revision; and w0aa.org 404s its own PDFs unless the request
  carries a `Referer` of `https://www.w0aa.org/mnqp-rules/`.
  `verified: partial` — the exchange carries a **first name** and no signal
  report, and this repo has no name field, so an exported Cabrillo log's `ex1`
  column is empty where the log robot expects the name.
- BCQP: rules from the Orca DX and Contest Club's own 2026 page
  (`orcadxcc.org/bcqp_rules.html`, footer `Updated: Feb. 5, 2026 VA7ST`), with its
  official multiplier list, its FAQ and its score summary sheet — four current,
  mutually consistent sponsor documents, read verbatim 2026-07-26. **The sponsor
  prints its own Cabrillo `CONTEST:` value**, so unlike almost every other
  bundled party this one does not rest on the WA7BNM registry. **Reading the FAQ
  was not optional:** three rules appear nowhere else — DX contacts earn points
  but no multiplier, "There is no power multiple", and there is no mobile or
  rover category — and the first of those would have handed a BC entrant a
  phantom multiplier on every band and mode. The FAQ's two worked scoring
  examples are asserted arithmetically by
  [`gen_bcqp.py`](docs/research/gen_bcqp.py), which also pins the sponsor's three
  own misspellings (`Shuwswap`, `Okangan`, `Richmond Center`) so nobody corrects
  them, and asserts the retired district code `NWB` is absent. `verified: partial`
  — see the BC-as-a-multiplier question above, plus one export note: ADIF's `cnty`
  field is written `BC,<district>`, which is well formed but meaningless for a
  region that has no counties. Cabrillo, the format the sponsor requires, is
  unaffected.
- SCQP: rules from the SCQP Team's official 2026 PDF, header `SOUTH CAROLINA QSO
  PARTY RULES (rev. 2.2.26)`, read verbatim 2026-07-26. The cleanest source of
  the run: one current-year document carries the rules, the 46 counties, the
  states, the provinces **and** the sponsor's own Cabrillo `CONTEST:` value, so
  nothing rests on an archive, a secondary page or a registry. **The filename
  lies and the revision line does not** — the PDF is served as
  `SCQPRULES2024_0126.pdf`, which reads like a 2024 document, while its header
  says `rev. 2.2.26` and its contents carry the 2026 dates and bonus stations.
  That is the mirror image of MNQP, whose filename was honestly 2027 while the
  trap was that the sponsor no longer published the year being built. Between
  them: never take a year from a URL.
  [`gen_scqp.py`](docs/research/gen_scqp.py) asserts all four of the sponsor's
  point sentences, because the pay-by-who-was-worked shape is the easiest thing
  here to get backwards.
- NCQP: rules from the North Carolina QSO Party Committee's official 2026 PDF
  ("Updated 10/13/2025") plus the sponsor's county abbreviation sheet, both read
  verbatim 2026-07-26. **The abbreviation is encoded by colour, not by case** —
  the sheet prints each county name with its code in dark red and says so — so
  [`gen_ncqp.py`](docs/research/gen_ncqp.py) parses `pdftohtml -c` output and
  takes the `#cc0000` runs as the code, while taking the *names* from the plain
  text (pdftohtml pads every run, making a mid-word boundary indistinguishable
  from the real space in "New Hanover"). The cross-check is the rules PDF, which
  prints ten codes in plain text for the "Rarest of NC" counties; all ten agree.
  Independent validation: 99 of the 100 names match the real North Carolina
  county list exactly, and the hundredth is the sponsor's own typo — the sheet
  spells Chowan "Chowen", which ships as printed and is asserted, the same call
  the repo makes for NHQP's "Merrimac".
- OKQP: rules from the sponsor's official 2026 PDF (`k5cm.com/okqp2026rules.pdf`)
  with its county locator page and its own 2026 summary, read verbatim
  2026-07-26. **The first search result for this party is the 2003 rules** —
  `qsl.net/okdxa/OKQP.htm`, headline "2003 Oklahoma QSO Party", still live — and
  it is wrong in four scoring dimensions: it says the exchange carries a QSO
  *number* (2026: a signal report), that *nine* Canadian provinces count (13),
  that 160 m is a contest band (80 m and up now), and it has no mobile activation
  bonus at all. Reaching the real rules took three hops, via the log robot at
  `okqp.contesting.com`. [`gen_okqp.py`](docs/research/gen_okqp.py) pins all four
  2026 values, and asserts the sponsor's own list of confusable abbreviations
  verbatim. *A schedule note worth keeping:* the sponsor's local anchors ("9 to 9
  on Saturday, 9 to 5 on Sunday") only land under **CDT** — its remark that "DST
  does NOT start on this weekend" means daylight time began the weekend *before*,
  not that Oklahoma is on standard time.
- IDQP: rules from the Idaho QSO Party's own pages, read verbatim 2026-07-26.
  **The dates are reconstructed rather than copied**, because the sponsor's date
  block contains four errors in eleven lines: it calls 13 March 2026 a Saturday
  (it is a Friday), prints a literal `xxxxZ` placeholder for the Saturday start,
  dates the Saturday end `14/March/2025`, and labels 1400Z on the 14th as the
  *Sunday* start. [`gen_idqp.py`](docs/research/gen_idqp.py) derives the four
  instants from the formula, the printed "12 Hours" per day and the local anchors
  under EDT — and **asserts the sponsor's errors are still present**, so a
  corrected page is noticed rather than silently absorbed. *Retrieval note:* the
  county page 403s a plain fetch and needs both a browser User-Agent and a
  Referer.
- WIQP: rules from the West Allis Radio Amateur Club's 2026 page, with the
  sponsor's official Multiplier List and its Cabrillo guide, read verbatim
  2026-07-26. **The Cabrillo guide was not optional reading:** the rules say
  non-Wisconsin stations send "State or Province or Country", which reads like a
  DX prefix, while the sponsor's own worked example logs `DL6QK` as the literal
  token `DX` — so reading only the rules page would have shipped the wrong
  `dxStyle` and rejected the sponsor's own sample line. The same example confirms
  the exchange carries no signal report, and the guide prints the `CONTEST:`
  value. DC appears **nowhere in the rules** and only in the multiplier list, as
  the single row `MD Maryland/(D.C.)`. *Retrieval note:* warac.org 403s a plain
  fetch of its multiplier page and needs both a browser User-Agent and a Referer.
- Band edges and ADIF band strings: the ADIF 3.1.4 Band Enumeration
  (adif.org/314/ADIF_314.htm), read 2026-07-24, cross-checked against
  47 CFR §97.301(a). Default per-band frequencies — used only for Cabrillo rows
  logged without CAT data — are the ARRL band plan's calling frequencies
  (arrl.org/band-plan, same date). 1.25 m is 222–225 MHz only: the US 219–220
  MHz point-to-point digital allocation is outside the ADIF band and is
  deliberately not loggable.
- Band plan (the CW→phone crossovers that drive automatic mode switching):
  **47 CFR §97.305(c)**, the authorized-emission-types table, read 2026-07-25
  via Cornell LII because ecfr.gov 302-redirects to an interstitial;
  **§97.301(a)** for the one boundary §97.305(c) names without a number
  (80 m is 3.500–3.600 and 75 m 3.600–4.000 in ITU Region 2, so the crossover
  is 3600 kHz); and the **ARRL band plan** (arrl.org/band-plan, same date) for
  160 m alone, where §97.305(c) permits phone band-wide and so supplies no
  crossover — the plan reads "1.843-2.000 SSB, SSTV and other wideband modes".
  Excerpts banked in
  [`band_plan_sources.md`](docs/research/band_plan_sources.md). The
  emission-type edges are used deliberately in place of §97.301(a)'s stricter
  license-class phone edges: the logger does not know the operator's class, and
  putting a radio in SSB is not itself an unlawful act. 30 m has an RTTY/data
  row and no phone row, so it is treated as CW throughout; 60 m, 1.25 m and
  70 cm have no defensible CW/phone split and the mode is left alone there.
  This table is **separate from the spot mode-inference table** in
  `SpotFilter`, on purpose — that one guesses what mode a cluster spot is in
  and is allowed to be wrong, this one decides what mode your radio is put in
  and is not.
- DC is accepted as a loggable state token (counted with states); strictly,
  KSQP rules enumerate 50 states — sponsors' checkers accept DC.
- State QSO Party Challenge: rules from the official 2026 PDF
  (stateqsoparty.com, fetched 2026-07-25, committed verbatim in
  `docs/research/`), scoring formula and award levels quoted in
  [`sqp_challenge_rules.md`](docs/research/sqp_challenge_rules.md). The
  approved-contest resource is **generated** by
  [`gen_sqp_challenge.py`](docs/research/gen_sqp_challenge.py) from the
  challenge's own calendar (fetched 2026-07-24) and homepage list (read
  2026-07-25), with hard assertions: 47 contests, 61 windows, 26 mapped to
  bundled parties. **Maine QSO Party is not on the 2026 approved list**
  (verified twice), so the dashboard shows MEQP logs but excludes them from
  challenge scoring, saying so. The calendar's NJQP row is known-wrong
  (Sep 19; the sponsor says Sep 12) — bundled sponsor schedules always
  supersede calendar dates, which are used only for parties this app has no
  rules for, labeled as calendar-sourced.

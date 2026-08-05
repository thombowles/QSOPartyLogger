# Vermont QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the two documents in §1.

The 68th running, and the **opening party of the 2026 season**.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Radio Amateurs of Northern Vermont (RANV)**, club call `W1NVT` |
| Contest Manager | **W1SJ** — `w1sj@arrl.net` |
| Rules (authority) | <https://www.ranv.org/vtqso.doc> — Word `.doc`, document title "VERMONT QSO Party Rules", created **2026-01-13**, footer prints **`13-JAN-2026`** |
| Summary page | <https://www.ranv.org/vtqso.html> — headed "2026 VERMONT QSO PARTY", page-dated **January 31, 2026** |
| Log robot | <https://vtqp.contesting.com/vtqpsubmitlog.php> (the rules `.doc` still prints the older `https://www.b4h.net/vtqp/vtqpsubmitlog.php`) |
| Paper logs | Vermont QSO Party, PO Box 9392, South Burlington, VT 05403-9392 |
| Deadline | 2026-02-22 2359 UTC |
| Fetched | **2026-07-26** |

Banked verbatim next to this file:

- [`vtqp_rules_2026.txt`](vtqp_rules_2026.txt) — `textutil -convert txt` of the
  official `.doc`. **This is the authority.**
- [`vtqp_page.txt`](vtqp_page.txt) — text of the summary page.

**Which document wins.** The page says so itself: *"The discussion below is a
summary of the QSO Party. Please download The Official 2026 Vermont QSO Party
Rules for specific rules."* Every rule below is cited from the `.doc` where the
`.doc` states it; the page is used only for the county **names** (the `.doc`
prints abbreviations only), the club list, and colour. Where they differ, §14
records it.

No revision of these rules was superseded — the `.doc` is the 2026 edition and
carries the 2026 dates, so **Article 20 has nothing to diff against**. This is
the first party in the repo built from a current-year rules document since MEQP.

## 2. Dates and times for 2026, in UTC

> "The Vermont QSO Party will be held on the first full weekend of February. The
> 2026 Vermont QSO Party will start at 0000 UTC on February 7, 2026 and end 2400
> UTC on February 8, 2026. This corresponds to a start time of 7:00 PM EST on
> Friday, February 6 and an end time of 7:00 PM EST on Sunday, February 8, 2026.
> **This is a 48 hour period** and stations may choose to operate any number of
> hours within this period." — rule 2

**One continuous window:**

| Start | End | Length |
| --- | --- | --- |
| `2026-02-07T00:00:00Z` | `2026-02-09T00:00:00Z` | 48 h 00 m |

"2400 UTC on February 8" is midnight at the *end* of the 8th, i.e.
`2026-02-09T00:00:00Z`. Three independent checks agree and there is no ambiguity
to carry forward:

1. The sponsor states the length outright — **48 hours** — and 0000Z Feb 7 →
   0000Z Feb 9 is exactly 48 h. (2359Z Feb 8 would be 47 h 59 m.)
2. The local anchors: EST is UTC−5, so 7:00 PM EST Fri Feb 6 = 0000Z Sat Feb 7 ✓
   and 7:00 PM EST Sun Feb 8 = 0000Z Mon Feb 9 ✓.
3. The formula "first full weekend of February" gives Feb 7–8 in 2026 ✓, and the
   State QSO Party Challenge calendar independently prints `2/7 0000Z → 2/8
   2400Z` ✓ (build order only, per Article 19 — but it agrees).

**Internal inconsistency, recorded and not carried:** the W1AW/1 sub-rule 1A(H)
restates the window as *"February 7, 0000Z until February 8, 2359Z"*, one minute
short, and the summary page repeats that in its ADIF instructions. Rule 2 is the
Date/Time rule, states the length, and agrees with both local anchors; 1A(H) is a
loose restatement inside a sub-clause about a special callsign. **48 hours
ships.** The only QSO the difference could touch is one made in the final minute
of the contest. This is *not* the Hawaii case — there, two sponsor statements
implied different lengths and neither matched the stated hours.

**2027 is not published.** The formula would give Feb 6–7 2027, but per Article
19 a formula-derived window is not shipped as though printed. Nothing about 2027
goes in the JSON.

## 3. Exchange

Rule 6, verbatim and complete:

> (A) Vermont stations send signal report and Vermont county.
> (B) W/VE stations (including Alaska and Hawaii) send signal report and state or province.
> (C) DX stations (including U.S. Territories) send signal report.
> Properly configured contest software will determine the DXCC country and list the official prefix.

| Role | Sends |
| --- | --- |
| **In-state (VT)** | RS(T) + one of the 14 VT county codes |
| **Out-of-state W/VE** | RS(T) + 2-letter state or province. **Alaska and Hawaii are W/VE here**, not DX — they send `AK`/`HI`. |
| **DX** | RS(T) **only** — and US Territories count as DX |
| **FT8/FT4** | dB report + 4-digit grid square (page: *"Use only 4-digit grid squares in your log. That is, FN34, not FN34km!"*) |

RST **is** part of every form → `exchangeIncludesRST: true`. No serial number
anywhere → `exchangeIncludesSerial: false`.

**`dxStyle` is `prefix`, and the reason is subtle.** The DX station *transmits*
only a signal report, so at first reading neither `token` nor `prefix` fits. But
the sponsor immediately says the software supplies the country — *"Properly
configured contest software will determine the DXCC country and list the official
prefix"* — and rule 10(C) requires the **logged** exchange to carry it: *"received
exchange (signal report and state/county/province/**DXCC prefix**)"*. The logged
token is therefore the prefix, and each distinct prefix is its own multiplier for
Vermont entrants (§6). `token` would collapse every DXCC entity into one `DX`.

**`DC` is counted as `MD`** — rule 7(B)(a): *"Use standard 2-leter postal
abbreviations. DC is counted as MD."* [sic, "2-leter"] → `stateAliases: {"DC": "MD"}`.
This is the second party after MDC to alias DC, and the first to alias it *away*
from its own home state.

## 4. QSO points by mode

Rule 7(A):

> Each complete non-duplicate Phone contact is worth 1 point, per band. Each
> complete non-duplicate CW contact is worth 3 points, per band. Each complete
> RTTY contact is worth 2 points, per band. Each complete non-duplicate Digital
> contact is worth 2 points, per band. All digital modes (WSJTx) count as a
> single mode. No partial contact credit. No duplicate contact credit.

| Mode | Points |
| --- | --- |
| Phone | 1 |
| CW | **3** |
| RTTY | 2 |
| Digital (WSJT-X) | 2 |

**Four sponsor modes collapse to three `ModeClass` cases without loss here**,
because RTTY and WSJT-X digital pay the *same* 2 points. `PointsTable` is
`{phone: 1, cw: 3, digital: 2}` and is exactly right for scoring. The RTTY/WSJT
split does matter for multipliers and dupes — see §6 and §5.

CW at 3 points is the highest CW value of any bundled party (ILQP and IAQP pay 2).

## 5. Dupe rule

> "(D) Stations may be worked once per mode, per band. i.e., WC4E may be worked
> on 20 CW, 20 SSB, and 20 digital for credit." — rule 9(D)

→ `dupeScope: "bandMode"`.

Two refinements from the page, both narrowing rather than widening:

- *"Stations can only count once per band for credit on digital modes. That is,
  if you work a station on both FT8 and FT4 on a particular band, it only counts
  once."* — already how `ModeClass.digital` behaves, so no gap.
- *"Note: RTTY is considered a legacy mode and is not part of this digital
  group."* — this one **is** a gap: the sponsor treats RTTY and WSJT-X as
  different modes, so RTTY + FT8 on one band is two QSOs for the sponsor and one
  mode class here. See §14 and KNOWN LIMITATION 3.

Rule 9(B): *"No cross-mode contacts."*

## 6. Multipliers

Stated separately for each side, exactly as Article 16 demands. Rule 7(B):

> (1) For Vermont stations, the multipliers are: U.S. States, Canadian
> Provinces, DXCC Countries, Vermont Counties and Vermont Club Stations. **A
> multiplier can be counted only once per mode, regardless of the number of bands
> on which it is worked.**
>
> (2) For Non-Vermont stations: Vermont Counties and Vermont Club Stations. A
> multiplier can be counted only once per mode, regardless of the number of bands
> on which it is worked.

| | In-state (VT) | Out-of-state |
| --- | --- | --- |
| Classes | 50 US states, 13 provinces, DXCC countries, 14 VT counties, VT club stations | **VT counties** and VT club stations only |
| Scope | **once per mode** | **once per mode** |
| Cap | none | none |

→ `countScope: "perMode"` on **both** sides; `inState.classes = [county, state,
province, dx]`, `outState.classes = [county]`. No `dxMultCap` on either side —
the rules state none.

Component detail from 7(B)(a)–(d):

- *"(a) 50 U.S. States … DC is counted as MD."*
- *"(b) 13 Canadian Provinces and Territories (per RAC listing): AB, BC, MB, NB,
  NL, NS, NT, NU, ON, PE, QC, SK, YT."* — **the standard 13, with the standard
  `NL` spelling**, so this repo's default list is correct here and no `provinces`
  override is needed. (Read anyway, per worklist open question 6: OhQP counts 11,
  NJQP spells it `NF`, MEQP splits `NF`/`LB`. VTQP is a control case.)
- *"(d) DXCC Countries, as designated by the official ARRL DXCC listing. U.S.,
  Canada, Alaska and Hawaii will not count as DXCC multipliers."* — exactly how
  this app already resolves them: states and provinces respectively.

Two multiplier kinds this repo's schema has no class for — both real, both
verified, neither modelled:

- **(e) Approved Vermont club stations.** *"A licensed Vermont Club station must
  inform the QSO Party Manager no later than one week prior to the event and
  commit to at least 5 hours of operation."* The page names the 2026 approved
  club: **`W1NVT`**, *"These count on each mode: Phone, CW, Digital."* A
  multiplier keyed on **callsign** is a shape `MultClass` does not have. See §14.
- **(f) Grid-square multipliers on WSJT-X modes.** Vermont entrants: *"totaling
  up the number of grid squares worked, dividing by 3, and rounding down."*
  Non-Vermont entrants: *"the total number of Vermont grid squares worked, which
  is a maximum of 5: (FN34, FN33, FN32, FN44, FN35)."* Neither a class nor an
  arithmetic the engine has. See §14.

**Is Vermont itself a multiplier for Vermont entrants? Not stated — OPEN
QUESTION.** VT stations count "U.S. States" and work everyone, so a VT–VT contact
is legal; but the other VT station sends a *county*, so the token `VT` is never
received, and no rule says a VT county also yields the VT state multiplier. There
is no stated multiplier total to settle it by arithmetic. Shipped as **not**
counting (`homeStateCountsViaCounty: false`), the same call as NHQP, MEQP, SDQP
and ILQP. This is worklist recurring-judgement-call 5 in its usual form.

`excludedStateTokens` therefore keeps its default `[homeState]` = `["VT"]`, and
`DC` stays loggable through `stateAliases`.

## 7. Bonus stations and bonus points

**One, and it is unusual.** Rule 1A(F):

> "Stations OUTSIDE of Vermont will get an additional 2 point bonus for each
> W1AW/1 station they work. **Vermont stations will not get this bonus.**"

Rule 1A(E): *"W1AW/1 may be worked in each Vermont County on each band/mode."*
The page restates it: *"Stations OUTSIDE of Vermont will get a 2-point bonus for
every W1AW/1 station in Vermont they work."*

→ `workStation(call: "W1AW/1", points: 2, scope: "perQSO")` — a per-QSO adder,
the same scope TnQP's `K4TCG` uses, at the smallest value in the repo.

Two constraints the sponsor puts on it, both narrowing:

- Rule 1A(D): the QSO must carry the full exchange to count.
- Rule 1A(G): *"W1AW/1 QSO's on 30, 17 and 12 meters will ONLY count for digital
  credit."* And the page: *"W1AW will be active from other states (AL, IN, KS) as
  well. **These do not count for Vermont QSO Party credit!**"* — a plain
  `W1AW/1` from Vermont sends a VT county, and this party restricts out-of-state
  entrants to VT stations anyway (§14), so an Alabama W1AW/AL contact is already
  flagged NO CREDIT. The `/1` in the call is the discriminator and the app
  matches on it exactly.

**The in-state exclusion is not modelled** — `ScoreEngine.bonusPoints` applies
`workStation` regardless of the entrant's own location. A Vermont entrant would
be over-credited 2 points per W1AW/1 QSO. See §14 and KNOWN LIMITATION 2.

**This is a 2026-only rule.** It exists for the America250 WAS / ARRL Year of the
Club celebration: *"W1AW/1 will be active from Vermont during the week of
February 4 through February 11."* It should be **removed** when the 2027 rules
are read — recorded as an open question so a later session does not carry it
forward silently.

## 8. Final-score multipliers

**Yes — a power multiplier, and it is fractional.** Rule 7(D)(1):

> If all QSO's were made using 5W or less, multiply your score by **2**
> If all QSO's were made using more than 5W and less than or equal to 150W
> output, multiply your score by **1.5**
> If any or all QSO's were made using more than 150W, multiply your score by **1**

> "Final Score = Total Points X Total Multipliers X Power Multiplier" — rule 7(D)

| Category | Rule 4 definition | Factor |
| --- | --- | --- |
| QRP | ≤ 5 W PEP | ×2 |
| Low | > 5 W and ≤ 150 W PEP | **×1.5** |
| High | > 150 W PEP | ×1 |

Rule 4: *"Logs not showing power output category will be listed as high power."*

**Shipped in full on 2026-07-28.** This was the first fractional score
multiplier in the repo — MDC, NJQP and PAQP are all integers — and while
`ScoreMultipliers` was `[String: Int]` it could not be held at all, so this
party shipped none rather than a wrong whole number. `ScoreFactor` now carries
it as an exact rational and `scoreMultipliers` reads
`{"power": {"QRP": 2, "LOW": 1.5, "HIGH": 1}}`.

**Rounding: the sponsor states no rule, and this is the whole of the evidence.**
`multiply your score by 1.5` on an odd points × multipliers product lands on a
half, and rule 7(D) says nothing about what to do with it. Searching the `.doc`
and the summary page for *round*, *nearest*, *fraction*, *decimal*, *integer*
and *whole* returns exactly one hit each, and both are the same rule — 7(B)(f)
on **multiplier** counts, not on the score:

> "totaling up the number of grid squares worked, dividing by 3, and **rounding
> down**." — rule 7(B)(f)

> "43 grids / 3 = 14.33 which is **rounded down** to 14 multipliers." — the
> summary page's worked example

So down is the sponsor's own idiom for its own fractions, and is what this app
applies to the final score: **once**, on the whole points × multipliers product,
before bonuses. Recorded as an inference rather than a quoted rule.

## 9. County-line / multi-county rules

> "Vermont stations on a county line may be claimed as a QSO and a multiplier
> from each county (**2 QSO's and 2 multipliers**)." — rule 7(B)(c)

The page adds the logging instruction:

> "Mobiles may operate from a location straddling a Vermont county line. They
> will announce this as such. You can work these stations once, but you can count
> them as two contacts from the different counties. **Be sure to log these as
> separate contacts. Do not try to enter both counties on the same log line!**
> This rule only applies to Vermont counties. If you are situated on a state
> line, pick one."

→ `maxSimultaneousCounties: **2**` — the sponsor states the number outright, and
two is the ceiling. (ALQP forbids line sitting at 1; TnQP/WA/COQP allow 2; IAQP
junctions 4.)

**"Do not enter both counties on the same log line" is satisfied, not violated,
by entering `ADD/CHI` here.** `CountyLineExpander` turns one entry into *separate
QSO rows* sharing a `groupID` — which is precisely the two separate log lines the
sponsor asks for. The instruction is aimed at loggers that would emit one
Cabrillo line carrying two counties.

Mobiles changing county mid-contest: rule 3(C) defines the Mobile/Rover category
as *"stations operating from multiple counties in Vermont"*, so a county change
is a new QSO, not a dupe.

## 10. Valid bands

Rule 8, verbatim:

> "Use of 30, 17 and 12 meters are **prohibited except** when operating FT8/FT4
> on the recognized frequencies of 10.136/10.140, 18.110/18.104 and
> 24.915/24.919 MHz upper sideband only. **VHF and UHF frequencies are allowed**,
> but repeaters may not be used. Otherwise, operators may use any frequency
> allowed by their license, however, it is suggested that activities concentrate
> in the following areas…"

**This party has no band list.** It has one prohibition and one permission, which
is the opposite of how every other bundled party words it. Derived list — 13
bands:

`160m, 80m, 40m, 30m, 20m, 17m, 15m, 12m, 10m, 6m, 2m, 1.25m, 70cm`

- **160–10 m** — suggested frequencies are given for 160 m (1850–1875 kHz),
  "80-15 meters" phone, 10 m (28.400–28.425), and CW "25 KHz above the lower band
  edge and up" on each.
- **30/17/12 m are IN, deliberately.** They are prohibited for phone/CW and
  *explicitly permitted* for FT8/FT4 on named frequencies. `validBands` is not
  mode-scoped, so the choice is between blocking a QSO the sponsor encourages and
  permitting one it forbids. Blocking loses real contacts; permitting one costs
  nothing an operator would do by accident (30 m is CW/digital-only under FCC
  rules regardless). Recorded as KNOWN LIMITATION 4.
- **VHF/UHF are IN** — "VHF and UHF frequencies are allowed", with suggested
  frequencies 50.130 / 144.200 / 146.520 MHz. 1.25 m and 70 cm follow from "VHF
  and UHF" as a class; the sponsor names no upper bound.
- **60 m is OUT — and this is an OPEN QUESTION.** "Any frequency allowed by their
  license" would admit it; the sponsor neither lists it, suggests a frequency for
  it, nor prohibits it. US 60 m is five fixed channels and no state party
  currently counts it. Excluded rather than silently included, and flagged.

## 11. Categories

Rule 3 — three, and one asymmetry:

- **(A) Single operator** — *"One person performs all operating and logging
  functions. Only one transmitted signal is permitted on the air at any time."*
- **(B) Multi-operator** — *"Those obtaining any form of live assistance, such as
  relief operators or loggers."*
- **(C) Mobile or Rover** — *"stations operating from multiple counties in
  Vermont."*

> "**All outside Vermont stations are considered to be Single operator.**" — rule 3(A),
> and the page: "There is only one category - Single-Op - for stations outside of
> Vermont, regardless of the number of operators."

Power (rule 4): QRP ≤5 W, Low >5–150 W, High >150 W; unmarked logs are scored high.

Cabrillo `CATEGORY-*` headers take these directly. Rule 10(B) additionally
requires the log to state the location as a *"Vermont county, State or Province
(**NOT ARRL Section**)"*.

## 12. Cabrillo `CONTEST:` header

**`VT-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, entry 236, fetched 2026-07-26),
which Article 1 names as the one codified secondary authority, **because the
sponsor publishes no `CONTEST:` token**. Rule 10(A) requires Cabrillo — *"Contest
log must be in Cabrillo Format!"* — but neither document prints a header value.
No alias is registered.

The page does print a QSO-line example, which confirms the exchange columns:

```
QSO: 14150 PH 2023-02-04 0000 W1NVT  59  CHI K7GMB  59   WA
QSO:  7074 DG 2023-02-05 0506 W1NVT  04 FN34 W9FMC  11 EN53
```

Digital logs go up as **ADIF**, not Cabrillo: *"Phone, SSB, CW and RTTY contacts
must be uploaded as a Cabrillo file. Digital contacts (FT8/FT4) must be uploaded
as an ADIF file."* Both exporters already exist.

## 13. County list

**14 counties, uniform 3-letter abbreviations** — the smallest county list of any
bundled party (next smallest is Hawaii's districts).

The `.doc` prints the abbreviations authoritatively, rule 7(B)(c):

> "14 Vermont Counties: ADD, BEN, CAL, CHI, ESS, FRA, GRA, LAM, ORA, ORL, RUT,
> WAS, WNH, WNS."

The page prints the **abbreviation → name** table. The generator parses the
page's table for names and asserts the resulting abbreviation set is exactly the
`.doc`'s list — two sponsor documents cross-checking each other, which is the
strongest form Article 2 allows without a machine-readable file.

| Abbr | County |
| --- | --- |
| ADD | Addison |
| BEN | Bennington |
| CAL | Caledonia |
| CHI | Chittenden |
| ESS | Essex |
| FRA | Franklin |
| GRA | Grand Isle |
| LAM | Lamoille |
| ORA | Orange |
| ORL | Orleans |
| RUT | Rutland |
| WAS | Washington |
| WNH | **Windham** |
| WNS | **Windsor** |

**Spelling anomalies flagged, so nobody "fixes" them later:**

1. **`WNH` Windham vs `WNS` Windsor** — the sponsor calls this out in its own
   voice: *"Take care to not mix up WiNdHam (WNH) and WiNdSor (WNS)!!"* Neither
   is the naive `WIN`. The generator asserts both.
2. **`GRA` is Grand Isle, not "Grand Island."** The county table says GRAND ISLE;
   the page's *KI1P schedule prose* says "Grand Island/Chittenden Co." That is
   loose prose in an operating schedule, not the county table. **Grand Isle**
   ships.
3. The page's second note: *"Be sure to use the correct VTQSO 3-letter
   designations shown above."* Rule 7(C) makes a miscopied exchange cost the QSO
   *and* the multiplier if it was the only source of it.
4. `WAS` (Washington) collides with nothing here, but is worth noting as a code
   several parties reuse for different counties.

## 14. Engine shapes to watch

Seven, and they are the reason this party ships `verified: partial`. **Four are
rules that are fully verified but that the schema cannot express** — Article 3
distinguishes these from unverified rules, and Article 17 explicitly allows
shipping with a note ahead of the field. One (item 1) is now built. One is a
placement the sponsor never states, and one is a genuine unknown.

1. ~~**Fractional score multipliers — the big one.**~~ **Done 2026-07-28.**
   VTQP's Low Power factor is **×1.5**, and while `ScoreMultipliers` was
   `[String: Int]` shipping `{QRP: 2, LOW: 1, HIGH: 1}` would have silently
   under-scored every low-power entrant by 33 % — exactly the "wrong number that
   looks right" the constitution's preamble is about — so **no `scoreMultipliers`
   shipped at all** and the operator saw the limitation instead. The widening was
   a schema *and* a stored-history migration (`factor(power:station:)`,
   `ScoreBreakdown.categoryFactor`, `ScoreEngine.total`, `ScoreSidebar`, and
   `ScoreSnapshot.Figures.categoryFactor` in the iCloud archive), so it landed in
   its own party-free commit under Article 4, and this party gained the field in
   the next one. See §8 for the rounding rule and its evidence.
2. **`workStation` bonuses ignore the entrant's own location.** Rule 1A(F) gives
   the W1AW/1 bonus to out-of-Vermont stations only — *"Vermont stations will not
   get this bonus"* — and `bonusPoints` has no in/out-of-state condition. The
   bonus ships, because for an out-of-state operator (the case this app is used
   in) it is exactly right; a Vermont entrant is over-credited 2 points per
   W1AW/1 QSO. A `scope`-adjacent `appliesTo: "outState"` would fix it. **One
   user so far**, so it waits for a second, per the repo's own bar.

   **Where the bonus enters the formula is a second, separate question, and the
   sponsor does not answer it.** Rule 1A(F) calls it *"an additional 2 point
   bonus"*, which reads as QSO points and would therefore fall **inside**
   `Total Points X Total Multipliers X Power Multiplier`. But the bonus lives in
   section 1A rather than in section 7, and rule 7(D)'s formula names no bonus
   term at all. This app adds bonuses last, scaled by neither the multipliers nor
   the power factor — the same placement it uses for every party — so a
   low-power station outside Vermont may be under-credited by half a point per
   W1AW/1 QSO under the other reading. Recorded as a `ruleInference` caveat, not
   as a gap: there is no sentence to be right or wrong about. Moot from 2027.
3. **RTTY and WSJT-X are one `ModeClass` here and two modes for the sponsor.**
   The page: *"RTTY is considered a legacy mode and is not part of this digital
   group."* Multipliers count *once per mode*, and the two digital families do
   not even use the same multiplier kind — RTTY uses states/countries, WSJT-X
   uses grid squares. So a Vermont entrant working `TX` on both RTTY and FT8
   earns two multipliers from the sponsor and one here. This is the **second**
   party to want a mode-grouping change (ILQP wants the mirror image — *fewer*
   groups, `[["cw","digital"]]`), which together suggest the right field is a
   party-supplied mode-class partition rather than either party's special case.
4. **`validBands` is not mode-scoped**, so 30/17/12 m ship as fully valid when
   the sponsor allows them for FT8/FT4 only. See §10 for why permitting beats
   blocking.
5. **Two multiplier kinds have no `MultClass`:** approved Vermont **club
   stations** (keyed on callsign — `W1NVT` for 2026) and **grid squares** on
   WSJT-X modes, the latter with per-side arithmetic (in-state: grids ÷ 3 rounded
   down; out-of-state: VT grids worked, max 5 of `FN34 FN33 FN32 FN44 FN35`).
   Both are omitted, so a digital-heavy or club-chasing log under-counts. Neither
   is worth a schema change for one party; both are named in `notes` so the
   operator can add them by hand on the summary sheet.
6. **Genuine unknown:** whether Vermont is a state multiplier for Vermont
   entrants (§6). One email to `w1sj@arrl.net` settles it, along with the 60 m
   question (§10).

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| Phone 1 / CW 3 / RTTY 2 / digital 2 | `points {phone:1, cw:3, digital:2}` |
| "once per mode, per band" | `dupeScope: "bandMode"` |
| "only once per mode, regardless of … bands" | `countScope: "perMode"`, both sides |
| "DC is counted as MD" | `stateAliases {"DC": "MD"}` |
| DXCC prefix in the logged exchange | `dxStyle: "prefix"` |
| "2 QSO's and 2 multipliers" on a line | `maxSimultaneousCounties: 2` |
| W1AW/1 +2 per QSO | `bonuses: [workStation … perQSO]` |
| "Stations outside Vermont work Vermont stations" | `outStateWorksHomeStationsOnly: true` |
| 48 h, one window | `schedule` |

**`outStateWorksHomeStationsOnly` is stated outright**, twice — rule 1: *"Stations
outside Vermont work Vermont stations. Stations within Vermont work everyone"*,
and the page: *"Remember that stations outside of Vermont can only work Vermont
stations for credit."* That makes VTQP the **eighth** party to state the
restriction rather than imply it, and it needs no open question, unlike NJQP,
IAQP, NHQP and ILQP.

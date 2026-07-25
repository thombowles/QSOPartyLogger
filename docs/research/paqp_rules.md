# Pennsylvania QSO Party (PAQP) — 2026 Rules Research

Researched 2026-07-24 for Mac contest logger implementation.
Written to the [Article 15](../CONSTITUTION.md#article-15--research-before-code) template.

## 1. Sponsor / sources

- Sponsor: the **PA QSO Party Association (PA QSO PA)**, PO Box 260, New
  Berlinville, PA 19545-0260. Contact: Anthony "Goody" Good, K3NG,
  `info@paqso.org`. 2026 is the **70th** running.
  *(A web search attributed the party to the Nittany Amateur Radio Club, which
  ran it historically. Per Article 1 that is a secondary source and not
  authority; the sponsor's own rules and site say the Association, so that is
  what ships.)*
- Rules page (fetched 2026-07-24): https://www.paqso.org/pa-qso-party-rules.html
  — extracted to [`paqp_rules_page.txt`](paqp_rules_page.txt). Carries the 2026
  banner; the rules themselves are an embedded PDF.
- **Official rules PDF**, 13 pages, footer `Revision: 08/19/25`:
  https://www.paqso.org/files/PAQSO_Rules.pdf — extracted to
  [`paqp_rules_2025.txt`](paqp_rules_2025.txt).
- **Official county list** (67, with abbreviations):
  https://paqso.org/files/PA_QSO_County_Abbreviations.pdf — extracted to
  [`paqp_counties.txt`](paqp_counties.txt).
- **Official ARRL/RAC section list** (85):
  https://paqso.org/files/ARRL-Section-List.pdf — extracted to
  [`paqp_arrl_sections.txt`](paqp_arrl_sections.txt). Rule 5.b and 10.f both
  point at `paqso.org/pa-cntys-arrl-sects.html`, which links these two PDFs.
- Bonus-station page (still 2025's): https://paqso.org/bonus-station.html
- Log submission: Cabrillo 3.0 only, uploaded at
  https://paqso.org/log-submission.html. "Paper logs or logs in formats other
  than Cabrillo 3.0 will not be accepted." Deadline 7 days after the contest.
- Cabrillo name registry (WA7BNM): https://www.contestcalendar.com/cabnames.php

The rules PDF carries its **own change log** (13 numbered years of revisions),
which is unusually good provenance — §4 and §14 below cite it directly.

## 2. Dates and times for 2026, in UTC — and why this party is `verified: partial`

**The site is updated for 2026; the rules document is not.** Every page banner
reads:

> "**70th PA QSO Party - October 10 & 11, 2026** — Always the **2nd Full
> Weekend in October**"

while the rules PDF is headed "Pennsylvania QSO Party **2025** Rules" with:

> "2.a. For the year **2025**: 1600Z (1200EDT) October 11 to 0400Z (Midnight
> EDT) October 12, and 1300Z (0900EDT) October 12 to 2200Z (1800EDT) October 12."

and `Revision: 08/19/25`. Its change log shows this is the sponsor's normal
rhythm — every year's first entry is "Updated dates in header, 2.a and 17.a", and
2026's has not happened yet.

**The 2026 dates are settled anyway, from the sponsor's own two statements:**

- The banner names the days: **October 10 & 11, 2026**.
- The stated formula — "Always the 2nd Full Weekend in October" — gives the same:
  October 2026's full weekends are Oct 3–4, **Oct 10–11**, 17–18, 24–25, 31–Nov 1.
- The **times** transfer unchanged, and the rules' own parenthetical local times
  prove the offset: 1600Z = 1200 EDT, 0400Z = midnight EDT, 1300Z = 0900 EDT,
  2200Z = 1800 EDT. All four hold on 10–11 October 2026, which is still EDT
  (UTC−4) — US DST ends 1 November 2026.

**Ships as two windows:**

| | |
| --- | --- |
| Saturday | `2026-10-10T16:00:00Z → 2026-10-11T04:00:00Z` (12 h) |
| Sunday | `2026-10-11T13:00:00Z → 2026-10-11T22:00:00Z` (9 h) |

21 hours total. Same shape as NHQP and the Salmon Run.

The party still ships `verified: partial`: the rules text is a 2025 revision, so
a 2026 rule change would not be visible, and **the 2026 bonus station is not yet
announced** (§7). This is the AZQP/TnQP/IAQP situation with one extra unknown.

## 3. Exchange

> "5.a. **Sequential serial number plus PA county, ARRL section, Canadian
> section, or "DX"**. Serial numbers may be sent out of order or skipped due to
> software serial number reservation systems. It is important to correctly record
> the serial number that was sent and correctly copy the serial number received
> from the other station."

- **No RST anywhere** → `exchangeIncludesRST: false`. Third party after MDC and
  CQP.
- **A serial number** → `exchangeIncludesSerial: true`. **The second user of the
  capability added for CQP**, which is this repo's own bar for a field being
  worth having.
- The location half is a **PA county**, an **ARRL/RAC section**, or the literal
  token **`DX`** → `dxStyle: "token"`.
- **Non-PA stations send a section, not a state.** `TX` is not a valid PAQP
  token — Texas is `NTX`, `STX` or `WTX`. See §6 and §13.

> "5.b. Logged exchanges **must conform to** the specified Pennsylvania County or
> the ARRL/Canadian section abbreviations listed below."

Rule 5.h enumerates what must be logged without error to earn credit, and it
includes "Received and transmitted **serial numbers**" as its own line — so the
number is not decoration.

## 4. QSO points by mode

> "6.a. **CW: 2 points/QSO**" … "6.c. **Phone: 1 point/QSO**"
> "6.c.1. SSB, FM, AM, etc. Any voice mode allowed per FCC Regulations.
> 6.c.2. QSOs made using multiple voice modes on the same band only count once."

> "6.b. **DELETED**"

**There is no digital mode.** The change log records the removal outright —
"Removed digital modes. Deleted 4.c and 6.b" — so `allowedModes: ["phone",
"cw"]`, and a digital row is invalid rather than zero-point. (An older change-log
entry, "RTTY & PSK combined into one Digital Mode", is the superseded state; it is
listed here so nobody reads it as current.)

Note 6.c.2: FM and SSB on the same band are one QSO, which is exactly what the
engine's `ModeClass.phone` grouping already does.

## 5. Dupe rule

> "5.d. **Work stations once per band and mode.**"
> "5.e. **Work Rovers and Mobiles again when they change counties.**"

→ `dupeScope: "bandMode"`, and a received-county change is a new QSO — already
the engine's behaviour.

> "5.c. Multi-stations can send QSO number by band."

A multi-op may run one serial sequence per band. This app keeps a single
sequence, which is legal (the rules permit per-band numbering, they do not
require it) — and 5.a explicitly tolerates non-sequential numbers: "Serial
numbers may be sent out of order or skipped".

## 6. Multipliers — in-state and out-of-state

> "10.a. **In-State Multipliers: ARRL Sections + Canadian Sections + PA Counties
> + 1 DX.** Each multiplier counts **once, not once per band**."
>
> "10.b. **Out-of-State Multipliers: 67 PA Counties.** Each multiplier counts
> once, not once per band."

- In-state classes: `["county", "section", "dx"]` with `dxMultCap: 1` — the
  sponsor's "+ 1 DX" is a hard cap of one, the tightest in the repo (WA and NHQP
  cap at 10).
- Out-of-state classes: `["county"]`, ceiling 67 = the county count exactly.
- Both `countScope: "once"`. The "not once per band" clause was added
  deliberately — change-log entry for 1 July 2023: "Clarified 10.a & 10.b such
  that multipliers count once, not once per band."

### The EPA/WPA wrinkle

> "12.d. … **EPA and WPA multipliers are automatically added during the rescore
> process – there is no need to enter them.**"

Eastern and Western Pennsylvania are ARRL sections, but PA stations send a
**county**, so no one ever transmits `EPA` or `WPA`. Without this rule an
in-state entrant could never earn those two section multipliers. The sponsor
credits them automatically.

This is the same *kind* of rule as `homeStateCountsViaCounty` (a home
jurisdiction reachable no other way) but a different *shape*: two fixed
multipliers granted outright rather than one derived from a county. It needs its
own field — see §14.

Note it applies to the **in-state** side only: out-of-state multipliers are the
67 counties and nothing else (10.b), so adding sections there would contradict
the rule.

### Who may work whom

> "1.a. Pennsylvania amateurs … contact as many other amateurs in Pennsylvania,
> the United States, Canada, and the world.
> 1.b. **Non-Pennsylvania Amateurs try to contact as many Pennsylvania Amateurs
> as possible.**"

That is a statement of purpose, not a restriction, and no rule elsewhere says a
non-PA station earns nothing for a non-PA contact. But out-of-state multipliers
are *only* PA counties (10.b), and out-of-state points would come from contacts
whose exchange carries no PA county at all. **Open question**, resolved the way
NJQP/IAQP/NHQP were: ship `outStateWorksHomeStationsOnly: true`, so a stray
non-PA contact is visibly flagged as no-credit rather than silently scoring.

## 7. Bonus stations and bonus points

Two separate bonuses.

**Bonus station — 200 points per QSO:**

> "11.c. **Valid QSOs with the bonus station are worth 200 points** plus a
> possible county multiplier."
> "11.d. The Bonus Station(s) for the **2025** PAQSO Party is **N3XF** and crew,
> operating from Somerset County."

The scope is *per QSO*, and the sponsor's own published numbers prove it. N3XF's
write-up on the bonus-station page reports:

> "We were able to generate **1796 QSO's** which results in **359,200 bonus
> points**!"

359,200 ÷ 1796 = **exactly 200**. So 200 is a per-QSO *bonus* on top of the QSO's
own 1 or 2 points, not the QSO's total value — which is what the engine's
`workStation(scope: .perQSO)` computes. Same shape as TnQP's K4TCG at 100.

**The 2026 bonus station is not yet announced.** The rules still name the 2025
station and the bonus-station page still describes 2025, ending with "Could This
Be Your Group Next Year?". The change log shows the annual pattern — set 11.d to
TBD, then update it in July or August. **Shipping last year's N3XF would credit a
phantom bonus**, so no bonus station ships; it is an open question, and an
operator can add one via a user file (Article 21) the moment it is announced.

**PA mobile/rover activation — 500 points per county:**

> "10.e. **PA Mobile and Rover Bonus: Add 500 Points to final score for each PA
> County you operated from where you made at least 10 valid QSOs.**"

→ `activatedCountyCount(minQSOs: 10, points: 500)` — identical in shape to TnQP.
Rovers additionally "must travel 5 miles or more between stops to be eligible for
the 500 point bonus" (9.d), which is not something a logger can check.

## 8. Final-score multipliers

> "10.d. **QRP Operation Multiplier: Multiply QSO Points times 2.** Applied only
> if the entry runs QRP power **AND** enters in a QRP-specific Entry Division …
> no QRP multiplier is applied to any High or Low Power divisions regardless of
> actual power used."

→ `scoreMultipliers: {"power": {"QRP": 2}}`. Second party after NJQP and MDC to
use one.

> "10.c. **Final Score: Total points times Total Multipliers + Bonus Station
> Points + other Bonus Points**"

Which is exactly the engine's formula: `qsoPoints × multipliers × categoryFactor
+ bonusPoints`.

## 9. County-line / multi-county rules

> "9.e. A County Line station position is situated very near the boundaries of
> **at least two or more adjacent counties**. … The station must be set up as
> near as practical to the adjacent borders and **is fixed for the entire QSO
> Party**. … A County Line station **sends a single report with the multiple
> county abbreviations (CAR/LEH)**. The County Line and receiving station **logs a
> QSO for each county**. Both stations receive QSO points for each QSO entry."

So a county line is **one exchange, several logged rows** — the CQP shape, not the
MEQP one, and the sponsor's separator is `/`, which is already this app's syntax.
No numeric maximum is stated ("two or more"), so the app's ceiling of 4 stands.

**And the sponsor explicitly blesses this app's serial-number design:**

> "If possible, the County line station should log these QSO's **with the serial
> number as sent**. There may be small differences in the sent and received
> serial number due to differences in logging programs or **the automatic
> expansion of county line compound exchanges into separate QSO's**. This is
> acknowledged and accepted."

That is the exact question the serial-number design doc had to answer, answered by
a second sponsor independently: one contact, one number as sent, expanded into
rows.

Mobile, Rover and Bonus stations may **not** be County Line stations (9.e, 11.b),
and mobiles/rovers move county-to-county instead (5.e).

## 10. Valid bands

> "3.a. QSOs are permitted on **all ham band allocations authorized by station
> licensee, including 630m and 2200m and any VHF/UHF/Microwave frequencies**,
> except as noted below in Section 3.b. Primary activity … has typically been on
> 160m, 80/75m, 40m, 20m, 15m, 10m, 6m, and 2m."
>
> "3.b. QSOs are **not** permitted on the WARC bands (**12m, 17m, 30m, or 60m**)."
>
> "3.c. QSOs are not permitted via repeaters, satellites, EchoLink, IRLP, or
> similar VoIP services."

This is the widest band list of any bundled party. From the app's `Band`
enumeration, that is **160, 80, 40, 20, 15, 10, 6, 2, 1.25 m and 70 cm** — ten
bands, everything except the four WARC exclusions.

**Known limitation:** `Band` has no **630 m or 2200 m** case, and no microwave
bands above 70 cm, so QSOs there cannot be logged. Unlike the 1.25 m gap this is
not worth closing on spec — 2200 m and 630 m are LF/MF bands with essentially no
QSO-party activity, and the sponsor itself lists "typical" activity as 160 m
through 2 m. Recorded in `notes` rather than fixed, the same way the 1.25 m gap
was recorded before it was closed.

## 11. Categories (for Cabrillo `CATEGORY-*` headers)

**24 entry divisions** (§7): Single Op × {High, Low, QRP} × {CW, Phone, Mixed} =
9; Multi Op × {High, Low, QRP} = 3; Portable Single/Multi Op × {High, Low, QRP} =
6 (in-state only); Rover Single/Multi Op = 2; Mobile Single/Multi Op = 2; County
Line Single/Multi Op = 2.

Power (§8, by highest power used at any point): High >100 W to legal limit; Low
>5 W to 100 W; QRP ≤5 W.

Useful mappings the sponsor states: `Category-Station: FIXED` → divisions 7.a–7.l;
`PORTABLE` → the Portable divisions; `Category-Operator: MULTI-OP` for every
multi-op division. "The Cabrillo Standard does not include a station category for
County Line but it can be selected during the log submission process."

Spotting, self-spotting, skimmer and spectrum scopes are allowed in **all**
categories.

## 12. Cabrillo `CONTEST:` header

The sponsor mandates Cabrillo 3.0 and cites the Cabrillo QSO-data spec, but
prints no `CONTEST:` token. Under the
[Article 1](../CONSTITUTION.md#article-1--provenance-or-it-does-not-exist)
codified exception, WA7BNM's registry is authority: **`PA-QSO-PARTY`**, no
aliases (fetched 2026-07-24).

## 13. County list — and the section list

**67 counties, 3-letter abbreviations**, from the sponsor's own PDF. The count is
confirmed twice: the list itself, and rule 10.b's "Out-of-State Multipliers: **67**
PA Counties".

**Ten abbreviations are not the first three letters**, and the collision clusters
are why:

| Abbr | County | Why |
| --- | --- | --- |
| `BUX` | Bucks | `BUC` would collide with nothing, but `BUT` is Butler — one letter apart |
| `CMB` | Cambria | `CAM` would collide with Cameron |
| `CRN` | Cameron | see above; `CAR` is Carbon |
| `DCO` | Delaware | not `DEL` |
| `INN` | Indiana | not `IND` |
| `MOE` | Monroe | `MON` would be ambiguous across Monroe/Montgomery/Montour |
| `MGY` | Montgomery | see above |
| `MTR` | Montour | see above |
| `NHA` | Northampton | `NOR` would be ambiguous with Northumberland |
| `NUM` | Northumberland | see above |

Also worth a test: `MCK` McKean (internal capital), and the four W-counties
`WAR`/`WAS`/`WAY`/`WES` (Warren, Washington, Wayne, Westmoreland), where `WAS`
collides visually with the state code `WA` — which is *not* a PAQP token anyway,
since Washington state is the section `EWA` or `WWA`.

**85 ARRL/RAC sections** — 71 US + 14 Canadian, the count matching rule 16.a's
"The **14** Canadian Sections". Both lists parse cleanly out of the committed
source text with hard count assertions.

The Canadian 14 are worth naming because they are **not** provinces and differ
from every previous party's Canada list: `AB`, `BC`, **`GH`** (Ontario Golden
Horseshoe), `MB`, `NB`, `NL`, `NS`, **`ONE`**, **`ONN`**, **`ONS`** (Ontario
East/North/South), `PE`, `QC`, `SK`, **`TER`** (Territories). So Ontario is four
tokens, and `NT`/`NU`/`YT` do not exist — they are `TER`.

## 14. Engine shapes to watch

1. **ARRL/RAC sections replace states and provinces entirely.** This is the big
   one. `MultClass` has `county`/`state`/`province`/`dx`, and
   `multContributions` matches against `MultClass.usStates` and the party's
   `provinces`. PAQP's non-county tokens are 85 sections — `EMA`, `NLI`, `SCV`,
   `NTX`, `GH`, `ONE`, `TER` — of which many are *not* state codes at all, and
   several state codes (`TX`, `NY`, `CA`, `FL`, `WA`, `PA`…) are **invalid**.
   Needs a new `MultClass` case and a party-supplied token list that supplants
   the state/province sets. Its own commit, before the party.
2. **Two multipliers granted outright** — "EPA and WPA multipliers are
   automatically added" (§6). A generalisation of `homeStateCountsViaCounty`:
   fixed multipliers credited to one side without any QSO carrying them.
3. **`dxMultCap: 1`** — "+ 1 DX". The tightest DX cap in the repo, and one that
   the existing token-style DX handling satisfies exactly (every DX station sends
   the same `DX` token, which collapses to one multiplier anyway — so for once
   the repo's missing DXCC table costs nothing).
4. **Serial numbers** — second user of `exchangeIncludesSerial`, and the sponsor
   independently confirms the one-number-per-contact design for county lines (§9).
5. **QRP as a final-score multiplier** (×2 on QSO points) — `scoreMultipliers`.
6. **500 points per activated county with ≥10 QSOs** — `activatedCountyCount`.
7. **Bonus station at 200 per QSO, but the 2026 call is unknown** — ships with no
   bonus station and an open question rather than last year's call.
8. **Ten valid bands**, the widest yet; 630 m and 2200 m are permitted by the
   rules but absent from `Band`, and are recorded as a limitation rather than
   built.

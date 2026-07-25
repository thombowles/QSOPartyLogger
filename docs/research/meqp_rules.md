# Maine QSO Party (MEQP) — 2026 Rules Research

Researched 2026-07-24 for Mac contest logger implementation.
Written to the [Article 15](../CONSTITUTION.md#article-15--research-before-code) template.

## 1. Sponsor / sources

- Sponsor: **Wireless Society of Southern Maine (WSSM)**, club call **WS1SM**,
  P.O. Box 1603, Scarborough, ME 04070 USA.
- Rules page (fetched 2026-07-24): http://www.ws1sm.com/MEQP.html — extracted to
  [`meqp_page.txt`](meqp_page.txt).
- **Official rules PDF**, title block "Maine QSO Party / **2026 Official Rules**"
  (fetched 2026-07-24): http://www.ws1sm.com/Images/Maine_QSO_Party_Rules.pdf —
  extracted to [`meqp_rules_2026.txt`](meqp_rules_2026.txt).
- Log submission: email Cabrillo to `maineqsoparty@gmail.com`; paper to the P.O.
  box above. "Any entry with 10 or more contacts must be submitted
  electronically in Cabrillo format."
- Sponsor's own published results, used below as arithmetic verification:
  http://www.ws1sm.com/MEQP-2025.html and http://www.ws1sm.com/MEQP-2024.html.
- Cabrillo name registry (WA7BNM): https://www.contestcalendar.com/cabnames.php

No superseded revision is published — the sponsor keeps one rules PDF at a
stable URL and edits it in place, so there is no diff to record under Article 20.

**The page and the PDF are not redundant.** Two rules appear *only* on the web
page and are absent from the PDF: the Canadian province token list, and the
DC-counts-as-MD note. Both are modeled; both are quoted below. Two more appear
only in the PDF: the mobile/county-line rule and the suggested frequencies.

### Worklist open question 2 — RESOLVED

The worklist flagged that Maine is **absent from the State QSO Party Challenge
calendar** while WA7BNM lists it. The sponsor settles it: the party runs, and the
rules PDF is titled for 2026. The Challenge calendar is simply missing an event.
Per [Article 19](../CONSTITUTION.md#article-19--the-schedule-is-annual-and-dated),
this is the NJQP lesson again in a different shape — an aggregator's *silence* is
no more evidence than an aggregator's date.

## 2. Dates and times for 2026, in UTC

Web page: "Contest Period: **1200 UTC Saturday, September 26 to 1200 UTC Sunday,
September 27, 2026**."

PDF: "Contest Period: 1200 UTC 26 September to 1200 UTC 27 September **2025**."

**The PDF's year is a typo, and the resolution is not a judgement call:**

- The same PDF's title block reads "2026 Official Rules" and its rule 8 reads
  "The entry deadline for logs is **October 12, 2026**."
- The rules state the formula — "The Maine QSO Party always takes place the
  **last full weekend in September**" — and 26–27 September 2026 is Sat/Sun and
  is that weekend (September 2026 weekends: 5–6, 12–13, 19–20, **26–27**).
- 26 September **2025** was a **Friday**, so "1200 UTC Saturday 26 September"
  cannot describe 2025 at all.
- The page's FUTURE DATES list continues the same formula: 2027 Sep 25–26,
  2028 Sep 23–24, 2029 Sep 29–30, 2030 Sep 28–29, 2031 Sep 27–28 — each the last
  full weekend, and 2027-09-25 is a Saturday.

Article 19 requires the sponsor's formula and the sponsor's printed dates to
agree; here they do, on day and month, in both sources. Only the year digit in
one sentence is stale.

**Ships as:** one continuous 24-hour window,
`2026-09-26T12:00:00Z → 2026-09-27T12:00:00Z`.

## 3. Exchange

One sentence covers all three cases, identically on the page and in the PDF:

> "Stations in Maine send signal report and county. Stations outside Maine, but
> within either the United States or Canada, send signal report and
> state/province. DX stations send signal report and 'DX.'"

- **In-state (ME):** RS(T) + 3-letter Maine county abbreviation.
- **Out-of-state W/VE:** RS(T) + state/province.
- **DX:** RS(T) + the literal token **"DX"** → `dxStyle: "token"`.
- RST **is** part of the exchange → `exchangeIncludesRST: true` (unlike MDC).

## 4. QSO points by mode

**None — MEQP pays by *who was worked*, not by mode.**

> "QSOs: Contacts with stations in Maine are worth **2 points**. Contacts with
> stations outside Maine are worth **1 point**."

CW and phone pay the same. This is the shape no bundled party has had before;
see §14.

Note the second sentence is not decoration — QSOs *between two non-Maine
stations* score, which is unusual and is confirmed again under §5a below.

## 5. Dupe rule

> "You may work any station once on each of the two modes, on each of the six
> contest bands."

→ `dupeScope: "bandMode"`. A station is workable 12 times (6 bands × 2 modes).

> "Cross-mode, cross-band and repeater QSO's are not permitted."

### 5a. Are non-Maine QSOs valid for a non-Maine entrant?

**Yes — explicitly.** The sponsor's Notes section on the rules page:

> "We would also like to remind participants that **all QSOs made during the
> contest period that meet MEQP criteria are eligible for points—not just
> contacts with Maine stations.** We continue to receive logs that include only a
> handful of Maine QSOs and no additional contacts. … this approach significantly
> limits your potential score."

That paragraph is addressed to precisely the entrants who would have few Maine
QSOs — out-of-state ones. → **`outStateWorksHomeStationsOnly: false`.**

This is the **first bundled party to answer that question with a clear no.** The
worklist records nine consecutive parties needing it *on*; MEQP breaks the run,
and it does so in the sponsor's own words rather than by silence.

## 6. Multipliers — in-state and out-of-state

> "**Multipliers are the same for all participants:** Use Maine counties (16),
> States (50), Canadian Provinces (14), and DXCC countries as multipliers."

**Symmetric.** In-state and out-of-state count the same four classes. Article 16
warns that asymmetry is the norm; MEQP is the exception, and it says so in the
first four words — which is exactly why the sentence is quoted rather than
assumed.

**Counting scope:**

> "**Each multiplier may be counted once on each mode on each of the six contest
> bands.**"

→ per band **and** per mode, for every class. Supporting third sentence:

> "Final Score: The total QSO points from all bands multiplied by the total
> number of multipliers **from all bands**."

Note the scope sentence is typeset under the "Maine County Abbreviations"
heading, but reads "Each **multiplier**", not "each county" — and it is the only
counting-scope sentence in either source. Flagged here so nobody later "fixes"
it into a county-only rule.

### Arithmetic verification (the cheapest check available)

The sponsor publishes no maximum multiplier count, so the usual arithmetic check
is unavailable. The sponsor's **published results** substitute for it. Score =
QSO points × multipliers, and QSO points are bounded by the QSO count (each QSO
is worth 1 or 2), so the published (score, QSO count) pairs bound the multiplier
count:

| Year | Station | Score | QSOs | Feasible (points × mults) | Implied mults |
| --- | --- | --- | --- | --- | --- |
| 2024 | W1DED (ME, MOHP) | 494,834 | 1,212 | **1,234 × 401** — unique | **401** |
| 2025 | W1DED (ME, MOHP) | 221,067 | 841 | 847×261, 957×231, 1089×203 | **203–261** |

A once-per-contest pool is at most 16 counties + 50 states + 14 provinces + the
DXCC entities actually worked — on the order of 80–100. Per-mode doubles that at
most. **Neither can reach 203, let alone 401.** Band-scoped counting is therefore
in force, which is what the rules say. (The pairs are every factorization of the
score whose points term lies in `[QSOs, 2×QSOs]`.)

The 2024 figure verifies §4 as a bonus: 1,234 points from 1,212 QSOs means
exactly **22** two-point QSOs and 1,190 one-pointers — i.e. a *Maine* station
scoring 1 point each for 1,190 contacts with non-Maine stations. That is §4 and
§5a both, in the sponsor's own published numbers.

*(Caveat recorded: the 2024 results page gives 494,834 in prose and 494,614 in
its table for the same station. The prose figure is the coherent one — the table
figure factors only to 2,218 × 223, which would require 1,006 of W1DED's 1,212
contacts to have been with other Maine stations, in a year when 9 Maine counties
submitted logs. Either figure exceeds the once/per-mode ceiling, so the
conclusion does not depend on the choice.)*

### Multiplier notes (web page only — absent from the PDF)

> "For U.S. states, **DC and MD will be counted as a single multiplier**."

→ `stateAliases: {"DC": "MD"}`.

> "For Canadian Provinces, use the following abbreviations: **NB, NS, QC, ON,
> MB, SK, AB, BC, NT, NF, LB, YT, PE, NU**. Please note that **Newfoundland (NF)
> and Labrador (LB) will count separately**."

Fourteen tokens, and **a third distinct deviation from the default 13** (worklist
open question 6):

| | This repo's default | MEQP |
| --- | --- | --- |
| Newfoundland & Labrador | `NL`, one token | **`NF` + `LB`, two separate multipliers** |
| Count | 13 | **14** |

`NL` is **not valid** in MEQP. `NF` is the same legacy spelling NJQP uses, but
NJQP counts 13 with `NF` replacing `NL`; MEQP counts 14 by splitting Labrador
out. OhQP folds three territories into one. Three parties, three different
Canada lists — read every sponsor's own list.

### Does Maine itself count as a state multiplier?

**Not stated.** "States (50)" enumerates the class; nothing says a Maine county
*also* yields the ME state multiplier, and Maine stations always send a county so
the token `ME` is never received. There is no stated multiplier maximum to settle
it by arithmetic. → ships `homeStateCountsViaCounty: false`, asserting no
multiplier the sponsor never described, and carried as the single **OPEN
QUESTION**. Same call, same reasoning, as NHQP — and the third time the worklist's
lesson 5 applies.

## 7. Bonus stations and bonus points

**NONE.** Neither source names a bonus station, a bonus multiplier, or bonus
points of any kind. `bonuses: []`.

## 8. Final-score multipliers

**NONE.**

> "Final Score: The total QSO points from all bands multiplied by the total
> number of multipliers from all bands."

Nothing further is applied — power categories affect awards only, not score.
`scoreMultipliers` omitted.

## 9. County-line / multi-county rules

PDF only, and unusually explicit:

> "Mobiles count QSO points per county. **Mobiles that change counties are
> considered to be new stations, and can be worked for both multiplier and QSO
> point credit. County line QSO's should be logged as two separate QSO's.**"

And category note 3:

> "Operating while your vehicle is parked across a county line, occupying two
> counties, **counts as two counties and two contacts**."

→ **`maxSimultaneousCounties: 1`.** Two-county operation is permitted, but it is
logged as two QSOs, not as one QSO claiming two counties — so the entry field
must refuse a county-line entry. Mobiles changing county mid-contest are new
stations for dupe purposes, which the engine already does.

## 10. Valid bands

> "Bands and Modes: **160, 80, 40, 20, 15, and 10**, CW and phone (SSB, FM, AM)."

Six bands: 160 m, 80 m, 40 m, 20 m, 15 m, 10 m. No WARC (12/17/30), no 60 m, no
VHF/UHF. The band count is cross-checked twice by the rules' own phrase "each of
the **six** contest bands".

**Modes: CW and phone only — there is no digital category.** "the **two** modes"
appears twice. → `allowedModes: ["phone", "cw"]`; a digital row is invalid, not
zero-point.

> "Suggested frequencies: CW – 25 kHz up from the band edge and for SSB – 1850,
> 3850, 7280, 14280, 21250, 28450 kHz. Check for CW activity on the half-hour."

> "It is prohibited to make CW contacts in the conventional phone sub-bands and
> phone contacts in the conventional CW sub-bands."

Spotting is explicitly **encouraged**: "Use of a DX spotting system, including
Skimmer … is encouraged."

## 11. Categories (for Cabrillo `CATEGORY-*` headers)

- Single Operator High Power (>100 W)
- Single Operator Low Power (max. 100 W output)
- Single Operator QRP (max. 5 W output)
- Single Operator Mobile (max. 100 W output)
- Multi-Operator Single Transmitter High Power (>100 W)
- Multi-Operator Single Transmitter Low Power (max. 100 W output)
- Multi-Operator Multi-Transmitter, any authorized power

Category note 2: an unclear power class is scored as the **highest** power class.
Category note 6: "all Maine stations should indicate their county, based on their
actual address, as provided in the Cabrillo header."

## 12. Cabrillo `CONTEST:` header

The sponsor requires Cabrillo but **prints no `CONTEST:` token** in either
source. Under the [Article 1](../CONSTITUTION.md#article-1--provenance-or-it-does-not-exist)
codified exception, the WA7BNM Cabrillo name registry is authority:
**`ME-QSO-PARTY`**, listed with no aliases (fetched 2026-07-24).

## 13. County list

**16 counties, 3-letter abbreviations**, printed identically on the page and in
the PDF as a single sentence:

> "The counties are: Androscoggin (AND), Aroostook (ARO), Cumberland (CBL),
> Franklin (FRA), Hancock (HAN), Kennebec (KEN), Knox (KNO), Lincoln (LIN),
> Oxford (OXF), Penobscot (PEN), Piscataquis (PSQ), Sagadahoc (SAG), Somerset
> (SOM), Waldo (WAL), Washington (WAS), York (YOR)."

Generated from the committed source by [`gen_meqp.py`](gen_meqp.py), which parses
that sentence rather than trusting a re-typed list (Article 2).

**Irregular abbreviations — not the first three letters:**

| Abbr | County | Why it is a trap |
| --- | --- | --- |
| `CBL` | Cumberland | **not** `CUM` — the state's most populous county |
| `PSQ` | Piscataquis | not `PIS` |
| `SAG` | Sagadahoc | not `SAGA`/`SGD` |
| `ARO` | Aroostook | not `ARS`/`AROO` |
| `KNO` | Knox | 3 letters from a 4-letter name |
| `WAS` | Washington | collides visually with the state token `WA` |

No spelling anomalies in the sponsor's county names (contrast NHQP's
"Merrimac"). Every name is the county's official name.

## 14. Engine shapes to watch

1. **Points depend on the worked station's location, not on mode** — the first
   party to need this. `PointsTable` is per mode class only. Needs a new
   optional field (Article 4): a second table used when the received location is
   a home-state county. Default `nil` = every existing party unchanged.
2. **Multipliers counted per band *and* per mode** — `CountScope` has `once`,
   `perMode`, `perBand`, but not both together. Needs a new case,
   `perBandMode`. Additive: no existing file names it.
3. **Symmetric multipliers** — in-state and out-of-state identical, which
   Article 16 says to expect *not* to happen. Quoted, not assumed.
4. **Out-of-state entrants score non-Maine QSOs** — `outStateWorksHomeStationsOnly:
   false`, the first bundled party where the sponsor says so outright.
5. **14 Canadian tokens with `NF` and `LB` split** — `NL` invalid.
6. **Six bands including 160 m**, and **no digital mode**.
7. **County-line entries are two QSOs, not one two-county QSO** —
   `maxSimultaneousCounties: 1`.
8. **DXCC entities are multipliers for everyone, uncapped, but arrive as the
   literal token "DX"** — the repo's known DXCC-prefix-table gap. In NHQP this
   affected in-state entrants only and was capped at 10; here it affects *every*
   entrant with no cap, so it is the most consequential appearance of that gap so
   far. Recorded as a KNOWN SCORING LIMITATION in `notes`, not as a rule
   uncertainty.

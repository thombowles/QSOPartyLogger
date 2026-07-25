# Arizona QSO Party (AZQP) — 2026 Rules Research

Researched 2026-07-24 for Mac contest logger implementation.
Written to the [Article 15](../CONSTITUTION.md#article-15--research-before-code) template.

## 1. Sponsor / sources

- Sponsor: the **Arizona QSO Party** organisation, `info@azqp.org`; 2026 is the
  **18th running**. (The site credits the World Wide Radio Operators Foundation
  as its web sponsor — not the rules author.)
- Rules page (fetched 2026-07-24): https://www.azqp.org/rules — extracted to
  [`azqp_rules_page.txt`](azqp_rules_page.txt).
- Official rules PDF, linked from that page:
  https://www.azqp.org/_files/ugd/7bfd55_eae6582b7cdc4054ae5c25c3274555da.pdf —
  extracted to [`azqp_rules_pdf.txt`](azqp_rules_pdf.txt). **Identical in
  substance to the page**, footer `Rev: 2501 6/23/2025 1100`.
- Counties page (county names + abbreviations):
  https://www.azqp.org/counties — extracted to
  [`azqp_counties_page.txt`](azqp_counties_page.txt).
- Log submission: Cabrillo via the sponsor's web app (azqp.contesting.com).
- Cabrillo name registry (WA7BNM): https://www.contestcalendar.com/cabnames.php

The "Categories & Multipliers" page (azqp.org/categories) publishes its tables as
**images only** — no extractable text — so it is not used as a source. Everything
below comes from the rules page, the rules PDF, or the counties page.

## 2. Dates and times for 2026, in UTC — and why this party is `verified: partial`

**The site banner is updated for 2026; the rules themselves are not.**

Every page carries a site-wide banner reading:

> "**2026** — **1500z Oct 10 to 0500z Oct 11, 2026 (UTC)** — Arizona Section —
> AZQP 2026 begins in: … **18th Running of the AZQP**"

But the rules body — on the page *and* in the PDF — is headed "**2025** Arizona
QSO Party" and reads:

> "CONTEST PERIOD: **1500z Oct 11 to 0500z Oct 12, 2025 (UTC)**
> [**2nd October Saturday, 8 AM to 10 PM (AZ)**]"

with `Rev: 2501 6/23/2025 1100` in the footer and a log deadline of "0000z
October 22, **2025**". The page footer says "Last Updated: 1/28/2026", i.e. the
site was touched in 2026 but the rules document was not re-issued.

**The 2026 date is nevertheless settled, and by the sponsor:**

- The banner is the sponsor's own published 2026 date.
- The rules' own **formula** — "2nd October Saturday, 8 AM to 10 PM (AZ)" —
  gives **Saturday 10 October 2026** (October 2026 Saturdays: 3, **10**, 17, 24,
  31), which is exactly what the banner says.
- The times check out against the formula: Arizona does not observe DST, so
  MST = UTC−7 all year. 8 AM MST = **1500Z**; 10 PM MST = **0500Z** next day.
  A **14-hour** window.
- The 2025 body is self-consistent under the same formula (11 Oct 2025 was the
  2nd Saturday), so it is simply last year's document left in place.

[Article 19](../CONSTITUTION.md#article-19--the-schedule-is-annual-and-dated)
wants the formula and the printed dates to agree, and they do. **Ships as
`2026-10-10T15:00:00Z → 2026-10-11T05:00:00Z`.**

The party still ships `verified: partial`, because the *rules text itself* is a
2025 revision: any 2026 rule change would not be visible here. This is the same
situation as TnQP and IAQP, and it wants the same late re-check.

## 3. Exchange

> "Arizona stations — Send signal report RS(T) and 3-letter county abbreviation:
> (APH, CHS, CNO, GLA, GHM, GLE, LPZ, MCP, MHV, NVO, PMA, PNL, SCZ, YVP, YMA).
> Stations outside of Arizona — Send signal report RS(T) and 2-letter state or
> Canadian province / territory. **DX stations send signal report RS(T) and DXCC
> prefix.**"

- In-state: RS(T) + 3-letter county → `countyAbbrLength: 3`.
- Out-of-state W/VE: RS(T) + state/province.
- **DX: RS(T) + the DXCC prefix, not the literal word "DX"** → `dxStyle:
  "prefix"`. Only the third party to use prefix style (ALQP, TQP, TnQP, WA, MDC
  do; NHQP/MEQP/CQP use the token).
- RST is present → `exchangeIncludesRST: true`.

## 4. QSO points by mode

> "QSO POINTS: **CW=2; Phone=1**"

No digital mode exists ("MODES: CW, Phone") → `allowedModes: ["phone", "cw"]`.

## 5. Dupe rule

> "Work stations once per band per mode per AZ county."
> "A fixed single county station may be worked once on CW and once on Phone on
> each of the 6 bands (**maximum of 12 contacts**)."

→ `dupeScope: "bandMode"`, and the sponsor's own 12 = 6 bands × 2 modes confirms
both counts. The "per AZ county" qualifier is the mobile/expedition case, which
the engine already handles: a different received county is a different QSO.

> "Crossmode, crossband and repeater contacts are not permitted."

## 6. Multipliers — asymmetric, with two different scopes

### Arizona stations

> "Multipliers are the 50 US states, the 13 Canadian provinces and territories,
> and DXCC countries. **Multipliers count again for each mode.** Total possible
> multipliers = (50 + 13 + DXCC) **x 2**."

→ classes `["state", "province", "dx"]`, `countScope: "perMode"`. The ×2 is the
sponsor's own confirmation of the per-mode scope. **Counties are not an in-state
class** — the same shape as CQP.

### Stations outside Arizona

> "Multipliers are the 15 Arizona counties. **Multipliers count again for each
> band and mode.** Total possible multipliers = **15 x 6 x 2 = 180**."

→ classes `["county"]`, `countScope: "perBandMode"` — the **second user** of the
scope added for MEQP, and here the sponsor spells the arithmetic out. The
generator asserts 15 × 6 × 2 = 180 against the sponsor's printed 180, which
simultaneously confirms the county count, the band count and the mode count.

So the two sides differ in *scope* as well as in *class*: per mode in-state, per
band **and** mode out-of-state. Article 16 in its purest form.

### Does Arizona itself count as a state multiplier for AZ stations?

**Not stated in words — derived from the sponsor's own arithmetic, and named as
an open question.**

An Arizona station can never *receive* the token `AZ`: Arizona stations send
counties. So the only route to an `AZ` state multiplier is a county yielding it
— `homeStateCountsViaCounty`. The sponsor writes the in-state maximum as
"(**50** + 13 + DXCC) x 2", and 50 is unreachable unless AZ counts that way.

This is precisely the arithmetic that settles the flag `true` for KSQP, COQP and
IAQP, and its **absence** is the stated reason NHQP and MEQP ship it `false`
("there is no stated in-state maximum to settle it by arithmetic"). AZQP has
one, so it ships **`true`** — with the reasoning recorded here and the inference
flagged in `notes`, because the sponsor never wrote the sentence.

### Canada, DC

"the 13 Canadian provinces and territories" — the standard 13, left at the
default. **No DC rule is stated anywhere**, so no alias is configured: `DC` is
loggable as its own token, as in NHQP. Recorded rather than invented.

### Who may work whom

> "Arizona stations work everyone. Stations outside of Arizona work as many AZ
> stations as possible."
> "A valid contact consists of the complete, correctly copied, two-way exchange
> **between an Arizona station (AZ) and any other station (Non-AZ or AZ)**."

Every valid contact has an Arizona station in it → `outStateWorksHomeStationsOnly:
true`, from the definition of a valid contact rather than by implication.

## 7. Bonus stations and bonus points

> "BONUS POINTS: Receive a **one-time bonus of 100 points for a QSO with K7A** on
> any band or mode during the contest."

→ `bonuses: [{"type": "workStation", "call": "K7A", "points": 100, "scope":
"once"}]`. "On any band or mode" and "one-time" together fix the scope as `once`,
not per band or per mode.

The counties page confirms K7A is real and shows who runs it: the Pima row reads
"PMA **K7A (K6WSC)**".

## 8. Final-score multipliers

**NONE.**

> "SCORING: Total Score = (QSO POINTS x MULTIPLIERS) + BONUS POINTS."

Which is exactly the engine's formula, bonus added after the multiply.

## 9. County-line / multi-county rules

> "**Expeditions (or mobiles) spanning multiple county lines should be logged as
> multiple contacts**, where each contact counts as both multiplier and QSO point
> credit."
> "Mobiles that change counties are considered new stations and can be worked
> again for both multiplier and QSO point credit."

→ **`maxSimultaneousCounties: 1`.** Like MEQP and unlike CQP, a county line is
two QSOs rather than one two-county exchange, so a `APH/CHS` entry must be
refused. Note the entry categories *do* include "Expedition Multi-Op:
**County-line** or Single-county" — county-line operating is expected, it is just
logged as separate contacts.

## 10. Valid bands

> "BANDS: **160, 80, 40, 20, 15, 10 meters**"

Six bands, cross-checked twice by the sponsor's own arithmetic ("15 x 6 x 2 =
180" and "maximum of 12 contacts"). No WARC, no 60 m, no VHF/UHF.

Suggested frequencies — phone 1848, 3848, 7189, 14248, 21348, 28448 "at top of
the hour"; CW 1812, 3548, 7048, 14048, 21048, 28048 "at 1/2 past the hour".

> "CW contacts must not be made in the phone band segments."

## 11. Categories (for Cabrillo `CATEGORY-*` headers)

Mobile; Expedition Multi-Op (county-line or single-county); Expedition Single-Op
(county-line or single-county); Multi-Op Unlimited Transmitters; Multi-Op One
Transmitter (High >100 W / Low ≤100 W); Single-Op (High >100 W / Low ≤100 W /
QRP ≤5 W, Mixed / CW / Phone).

"Spotting assistance & self-spotting permitted in all categories" — unusually
permissive, and stated twice.

## 12. Cabrillo `CONTEST:` header

The sponsor requires Cabrillo but prints no `CONTEST:` token. Under the
[Article 1](../CONSTITUTION.md#article-1--provenance-or-it-does-not-exist)
codified exception, WA7BNM's registry is authority: **`AZ-QSO-PARTY`**, no
aliases (fetched 2026-07-24).

## 13. County list

**15 counties, 3-letter abbreviations.** The sponsor publishes the two halves in
**two different places, as parallel lists rather than a paired table**:

- The rules (page and PDF) give the abbreviations, in order:
  `APH, CHS, CNO, GLA, GHM, GLE, LPZ, MCP, MHV, NVO, PMA, PNL, SCZ, YVP, YMA`.
- The counties page gives the names, in the same order: Apache, Cochise,
  Coconino, Gila, Graham, Greenlee, La Paz, Maricopa, Mohave, Navajo, Pima,
  Pinal, Santa Cruz, Yavapai, Yuma — then repeats the same 15 abbreviations in
  the same order.

Pairing by position is therefore the only route, which is exactly the kind of
step [Article 2](../CONSTITUTION.md#article-2--never-hand-type-data-that-exists-in-a-file)
exists to make safe. [`gen_azqp.py`](gen_azqp.py) does not simply zip the lists —
it asserts:

1. both sources list the **same 15 abbreviations in the same order**;
2. the names are in **alphabetical order** (as both lists are);
3. every abbreviation's letters form a **subsequence of its county name**
   (`CNO` ⊂ `COCONINO`, `LPZ` ⊂ `LAPAZ`, `SCZ` ⊂ `SANTACRUZ`) — which a
   mis-alignment by even one position would break.

**Every abbreviation is irregular** — none is the first three letters of its
county:

| Abbr | County | Note |
| --- | --- | --- |
| `APH` | Apache | not `APA` |
| `CHS` | Cochise | not `COC` |
| `CNO` | Coconino | not `COC` either — `CHS`/`CNO` are the collision this avoids |
| `GLA` | Gila | not `GIL` |
| `GHM` | Graham | not `GRA` |
| `GLE` | Greenlee | `GRA`/`GRE` would have collided |
| `LPZ` | La Paz | space dropped |
| `MCP` | Maricopa | `MAR` would collide with nothing, but `MCP`/`MHV` keep M-counties apart |
| `MHV` | Mohave | not `MOH` |
| `NVO` | Navajo | not `NAV` |
| `PMA` | Pima | `PIM`/`PIN` would have been one letter apart |
| `PNL` | Pinal | see above |
| `SCZ` | Santa Cruz | not `SAN` |
| `YVP` | Yavapai | `YAV`/`YUM` |
| `YMA` | Yuma | not `YUM` |

There is no spelling anomaly in the sponsor's county names.

## 14. Engine shapes to watch

1. **Two different multiplier scopes in one party** — in-state `perMode`,
   out-of-state `perBandMode`. Both already exist; `perBandMode` was added for
   MEQP one iteration ago and AZQP is its second user, which is the repo's own
   bar for a field being worth having.
2. **`homeStateCountsViaCounty` inferred from arithmetic, not quoted** — see §6.
3. **DXCC multipliers with `dxStyle: "prefix"`**, so unlike NHQP/MEQP the app
   *can* tell entities apart. The standing limitation still applies: a DXCC
   prefix equal to a US state or Canadian province code is read as that
   state/province (`PA` Netherlands, `ON` Belgium, `LA` Norway) — the same
   resolution sponsors' log checkers apply. It matters here because DXCC counts
   for AZ stations, exactly as it does for the Salmon Run.
4. **County lines are separate contacts** — `maxSimultaneousCounties: 1`.
5. **No DC rule at all** — no alias, unlike ALQP/TnQP/COQP/IAQP/MEQP/CQP.
6. **Rules are the 2025 revision under a 2026 banner** — `verified: partial`,
   with a late re-check wanted, like TnQP and IAQP.

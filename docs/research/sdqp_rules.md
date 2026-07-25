# South Dakota QSO Party (SDQP) — 2026 Rules Research

Researched 2026-07-24 for Mac contest logger implementation.
Written to the [Article 15](../CONSTITUTION.md#article-15--research-before-code) template.

## 1. Sponsor / sources

- Sponsor: the **Prairie Dog Amateur Radio Club (PDARC)** of Southeastern South
  Dakota, Yankton SD. Sponsoring club station **W0OJY** (printed `WØOJY`).
  Contest coordinator and log receiver: Bill Nixon, **W0EJ**, `w0ej@arrl.net`
  (questions to `w0ej@goldenwest.net`, or 605-369-2100).
- **Current rules** (fetched 2026-07-24): https://sdqsoparty.com/ — headed "South
  Dakota QSO Party - **October 10 & 11, 2026**", with the full rule set, the
  county list, the award categories and the log-submission details on one page.
  Extracted to [`sdqp_rules_page.txt`](sdqp_rules_page.txt).
- County list page: https://sdqsoparty.com/23-2/south-dakota-counties/ — the same
  66 counties, one per line, which is the cleaner source to parse. Extracted to
  [`sdqp_counties.txt`](sdqp_counties.txt).
- **Superseded copy, kept deliberately:**
  https://sdqsoparty.com/23-2/ — a stale WordPress sub-site still headed "OCTOBER
  14 – 15, **2023**" and "**2022** CONTEST RULES". Extracted to
  [`sdqp_rules_2023_superseded.txt`](sdqp_rules_2023_superseded.txt) for the
  diff in §4.
- Cabrillo name registry (WA7BNM): https://www.contestcalendar.com/cabnames.php

**Two rule pages live on the same domain, and only one is current.** The root
GoDaddy-hosted club site carries the 2026 rules; the `/23-2/` WordPress sub-site
is three years stale but still reachable and still linked from search results.
Anyone re-verifying this party must read the **root**. Recorded here so the next
session does not read the wrong one.

## 2. Dates and times for 2026, in UTC

> "South Dakota QSO Party - **October 10 & 11, 2026**"
> "**1 PM Central Daylight Time Saturday to 1 PM Central Daylight Time Sunday.
> GMT is 1800z.** This is an annual contest planned to be held on the **2nd full
> weekend of October** each year."

All three of the sponsor's statements agree:

- The heading names the days: **10 & 11 October 2026**.
- The formula — "2nd full weekend of October" — gives the same: October 2026's
  full weekends are Oct 3–4, **Oct 10–11**, 17–18, 24–25.
- The sponsor converts its own local time: 1 PM CDT = **1800Z**, and CDT is
  UTC−5, so that arithmetic is right. 10–11 October 2026 is still CDT — US DST
  ends 1 November 2026.

**Ships as one continuous 24-hour window:**
`2026-10-10T18:00:00Z → 2026-10-11T18:00:00Z`.

Corroborated independently by the log deadline, which is also current: "Logs Are
Due by 08:00 hours Central Daylight Time (13:00z) on **October 24, 2026**".

## 3. Exchange

> "EXCHANGE: Stations outside South Dakota send **signal report and state,
> province or DXCC country**. South Dakota stations send **signal report and
> county**."

- In-state: RS(T) + county. Counties are 3 *or* 4 letters — see §13.
- Out-of-state W/VE: RS(T) + state/province.
- **DX: RS(T) + "DXCC country"** → `dxStyle: "prefix"`. The sponsor writes
  "country" rather than "prefix", but in-state stations count "DXCC countries" as
  separate multipliers (§6), which is only possible if the entities are
  distinguishable — and prefix style is what every other party with this
  multiplier uses (ALQP, TQP, TnQP, WA, MDC, AZQP). Noted rather than assumed
  silently.
- RST **is** part of the exchange → `exchangeIncludesRST: true`, and there is no
  serial number.

## 4. QSO points by mode

> "QSO POINTS: **Phone contacts are worth 1 point. CW contacts are worth 2
> points.**"

> "**NO DIGITAL MODES:** The South Dakota QSO Party does not include digital
> modes."

→ `allowedModes: ["phone", "cw"]`; a digital row is invalid, not zero-point.

### Diff against the superseded 2023/2022 copy

Nothing scoring-related has changed. Points, multipliers, bands, modes, classes,
power levels, the mobile rule and the suggested frequencies are **word-for-word
identical** between the stale `/23-2/` page and the current root page. What the
current page **adds**:

- the explicit "**NO DIGITAL MODES**" clause (previously only implied by "Modes
  are phone, CW, and mixed");
- a **FINAL SCORE CALCULATION** section with a worked example (§8);
- the fuller bonus wording — "may only be used once. Additional contacts with
  that station count as regular contacts" (§7);
- a **SPOTTING** section pointing at the State QSO Party Challenge's spot page.

So this is clarification, not a rule change, and no Article 20 diff note is owed
for scoring. Recorded because a reader comparing the two pages would otherwise
have to work that out.

## 5. Dupe rule

> "Stations may be worked **only once per mode per band** – 160m thru 70cm (no
> WARC bands). Repeater contacts do not qualify."

→ `dupeScope: "bandMode"`.

> "MOBILES: South Dakota Mobile (Rover/Portable) stations are considered **a new
> contact each time they change counties**."

Already the engine's behaviour.

## 6. Multipliers — in-state and out-of-state

> "MULTIPLIERS: Stations outside South Dakota multiply QSO points by **total
> South Dakota counties worked**. Stations inside South Dakota multiply QSO points
> by the total of the **South Dakota counties worked, US States, Provinces and
> DXCC countries**. **South Dakota counties may only be used ONCE as a
> multiplier.**"

- Out-of-state: classes `["county"]`, `countScope: "once"`, ceiling 66.
- In-state: classes `["county", "state", "province", "dx"]`, `countScope: "once"`.
- The "ONCE" sentence is explicit and applies to both, so no per-band or per-mode
  reading is available. The county-list page repeats it: "Counties may only be
  used ONCE as a multiplier".

No DX cap is stated, so none is set.

### Does South Dakota itself count as a state multiplier?

**Not stated.** In-state multipliers include "US States", but South Dakota
stations send a **county**, so the token `SD` is never received and the only
route to it would be `homeStateCountsViaCounty`. The sponsor gives no in-state
maximum to settle it by arithmetic — unlike KSQP, COQP, IAQP and AZQP, where a
stated total does settle it.

→ ships **`false`**, asserting no multiplier the sponsor never described, and
carried as an open question. Same call and same reasoning as NHQP and MEQP; this
is the fourth time the worklist's lesson 5 has applied.

### Canada and DC

"Provinces" with no list and no count, so the repo default of 13 stands. **No DC
rule is stated**, so no alias is configured and `DC` is loggable as its own token
— as in NHQP and AZQP.

### Who may work whom

> "OBJECT: Stations outside South Dakota work as many South Dakota stations and
> counties as possible. **Stations inside South Dakota work everyone.**"

An aim, not a prohibition, and no rule elsewhere restricts a non-SD entrant. But
out-of-state multipliers are SD counties only, so a non-SD contact could add
points while adding nothing else. **Open question**, resolved as for NJQP, IAQP,
NHQP and PAQP: ship `outStateWorksHomeStationsOnly: true`, so a stray contact is
visibly flagged as no-credit rather than silently scoring.

## 7. Bonus stations and bonus points

> "BONUS: Stations that work the Sponsoring Club (**WØOJY**) station during the
> event may claim an **extra 100 points**. The extra points shall be added to the
> total. **The sponsoring station 100 point bonus may only be used once.**
> Additional contacts with that station count as regular contacts."

And the county-list page again: "The Bonus Station **W0OJY** is worth 100 points
and will be added to the final total of points after calculation. The bonus
station **may only be worked once regardless of mode**."

→ `workStation(call: "W0OJY", points: 100, scope: .once)`. The scope is stated
twice and unambiguously — once for the contest, not per band and not per mode,
and further W0OJY contacts still score as ordinary QSOs.

The call is printed with a slashed zero (`WØOJY`); the callsign is `W0OJY`.

No mobile/rover activation bonus and no other bonus points exist.

## 8. Final-score multipliers

**NONE.** Power classes (High >150 W, Low ≤150 W, QRP ≤5 W) decide which award
you compete for, not the score. Note the 150 W boundary — most parties use 100 W.

> "FINAL SCORE CALCULATION: **QSO Points x Multipliers = Total + Bonus = Grand
> Total** (Example **50 contacts SSB x 20 counties = 1,000 points + 100 bonus =
> 1,100 points grand total**)."

The worked example is a free end-to-end test: 50 phone QSOs at 1 point = 50
points… ×20 counties = 1,000, +100 bonus = 1,100. It also confirms the bonus is
added **after** the multiply, which is exactly the engine's formula
(`qsoPoints × multipliers × categoryFactor + bonusPoints`). Reproduced in the
tests.

## 9. County-line / multi-county rules

> "County line contacts will count as multiple contacts for both, but **must be
> logged separately**."

→ **`maxSimultaneousCounties: 1`.** Two-county operation is permitted and both
stations get credit, but as two QSOs rather than one two-county exchange — the
MEQP and AZQP shape, not the CQP/PAQP one. A `AURO/BEAD` entry must be refused.

## 10. Valid bands

> "160m thru 70cm (**no WARC bands**)"

Ten bands: **160, 80, 40, 20, 15, 10, 6, 2, 1.25 m and 70 cm** — tying PAQP for
the widest list in the repo, and the same set.

The sponsor's suggested-frequency table is an exact cross-check: it tabulates
rows for 160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m, 1.25m and 70cm and no others. The
generator asserts the band count against that table.

Note 1.25 m is in the list — the band added on 2026-07-24 — so SDQP would have
needed an open question about it a day earlier.

## 11. Categories (for Cabrillo `CATEGORY-*` headers)

In-State Multi-Op Fixed, In-State Single-Op Fixed, In-State Multi-Op
Rover/Portable, In-State Single-Op Rover/Portable, Out of State Single-Op Fixed —
each in (CW / Phone / Mixed) × (QRP / Low / High) — plus DX Single-Op, any mode
and power. Power: High >150 W, Low ≤150 W, QRP ≤5 W.

"Only W0OJY will operate as Multi-Multi and will not be eligible for the In-State
Log Drawing."

## 12. Cabrillo `CONTEST:` header

The sponsor requires Cabrillo ("Please submit logs in Cabrillo format and include
your callsign and claimed score") but prints no `CONTEST:` token. Under the
[Article 1](../CONSTITUTION.md#article-1--provenance-or-it-does-not-exist)
codified exception, WA7BNM's registry is authority: **`SDQSOP`**, no aliases
(fetched 2026-07-24).

Note the short form — like TQP's `TXQP` and unlike the `XX-QSO-PARTY` pattern
most parties use. Not a typo.

## 13. County list

**66 counties**, and the abbreviations are **mixed 3 and 4 characters** — the
second party after the Salmon Run to mix lengths, so `countyAbbrLength` alone
cannot describe it and `countyAbbrLengths` reports `[3, 4]`.

**`DAY` (Day) is the only 3-letter abbreviation**; the other 65 are 4.

Irregular abbreviations worth pinning — the vowel-dropped ones and the
two-word names:

| Abbr | County | Note |
| --- | --- | --- |
| `BRWN` | Brown | not `BROW`; `BROO` is Brookings |
| `CLRK` | Clark | not `CLAR` |
| `DEWY` | Dewey | not `DEWE` |
| `DGLS` | Douglas | not `DOUG` |
| `HNSN` | Hanson | not `HANS`; `HAND` is Hand |
| `HRDG` | Harding | not `HARD` |
| `JKSN` | Jackson | not `JACK` |
| `MRSH` | Marshall | not `MARS` |
| `MCOO` | McCook | internal capital |
| `MCPH` | McPherson | internal capital |
| `BONH` | Bon Homme | two words |
| `CHAR` | Charles Mix | two words, and not `CHMI` |
| `FALL` | Fall River | two words |
| `DAY` | Day | the lone 3-letter code |

**Naming anomaly, flagged so nobody "corrects" it:** the sponsor prints
`OGLA Oglala Lakota (Former Shannon county), SD`. Shannon County was renamed
**Oglala Lakota County** in 2015. The display name ships as "Oglala Lakota"; the
parenthetical is the sponsor's own aid to operators with old county lists, and
`OGLA` is unaffected.

## 14. Engine shapes to watch

1. **Mixed 3/4-letter county abbreviations** — only the Salmon Run has done this
   before, and `countyAbbrLengths` already handles it.
2. **Nothing else is new.** Every rule maps onto a field that exists: `once`
   scope both sides, `workStation(scope: .once)` for W0OJY, `dxStyle: "prefix"`,
   `maxSimultaneousCounties: 1`, no score multipliers, no serial. After four
   consecutive parties that each needed an engine change, SDQP is data only —
   which is what Article 22 says adding a party should normally be.
3. **The sponsor's worked example is an end-to-end test** — 50 phone QSOs × 20
   counties + 100 bonus = 1,100.
4. **Two live rule pages, one stale** (§1) — the re-verification hazard here is
   reading `/23-2/` instead of the root.
5. Two open questions, both the standard pair: whether SD counts as a state
   multiplier for in-state entrants, and whether out-of-state entrants may work
   only SD stations.

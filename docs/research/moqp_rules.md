# Missouri QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The party with the most bonus rules in the repo** — five of them, of which two
fit, two do not, and one is not about QSOs at all. §7 is the section that matters.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Boeing Employees Amateur Radio Society – St. Louis (BEARS-St. Louis)**, `WØMA` |
| **Rules** | `moqp-2026-rules-final.pdf` — header **"2026 Missouri QSO Party Rules"** |
| County list | <https://www.w0ma.org/mo_qso_party/MO-Counties.pdf> — "Missouri County Listing" |
| Home page | <https://www.w0ma.org/mo_qso_party/> |
| Logs | **electronic Cabrillo only** — *"No paper logs will be accepted"* |
| Fetched | **2026-07-26** |

Banked verbatim: [`moqp_rules_2026.txt`](moqp_rules_2026.txt),
[`moqp_counties.txt`](moqp_counties.txt), [`moqp_page.txt`](moqp_page.txt).

**Retrieval note:** the site's own "2026 MOQP Rules" link points at
`./results/thisyear/moqp-2026-rules-final.pdf`, which **403s**. The identical file
is served from `./results/2026/reports/`. A session that stopped at the advertised
link would have concluded the rules were unavailable and fallen back to the 2025
edition, which is still the top search result.

## 2. Dates and times for 2026, in UTC

> "The contest has two separate operating periods. **For 2026 due to the Easter
> weekend the contest is on 11-12th of April.**
> 1st Day — 1400 UTC Saturday → 0400 UTC Sunday
> 2nd Day — 1400 UTC Sunday → 2000 UTC Sunday"

| Segment | Start | End | Length |
| --- | --- | --- | --- |
| Saturday | `2026-04-11T14:00:00Z` | `2026-04-12T04:00:00Z` | 14 h |
| Sunday | `2026-04-12T14:00:00Z` | `2026-04-12T20:00:00Z` | 6 h |
| | | **total** | **20 h** |

**The sponsor states why the date moved**, which is unusually helpful: MOQP
normally runs the *first full weekend of April*, and 2026's would have been 4–5
April — the same weekend as Louisiana and Mississippi — but that is Easter, so it
shifted a week. Recorded because it means **the usual formula does not give the
2026 date**, and a future session deriving it from the formula would land a week
early.

**The sponsor publishes future dates**, and they confirm the formula resumes:
*"2027: Apr 3 and 4 · 2028: Apr 1 and 2 · 2029: Apr 7 and 8"*. Per Article 19
those go in `notes`, not `schedule`.

## 3. Exchange

> "**Missouri stations** will provide call sign, **RST**, and a three letter
> county code…
> **Non-Missouri stations** will provide call sign, RST, and their US state… or
> Canadian province or territory…
> **DX stations** will provide callsign, RST, and the exchange "**DX**"."

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`,
`dxStyle: "token"` — the sponsor asks for the literal string, and DX is worth
exactly one multiplier however many entities are worked (§6).

## 4. QSO points by mode

> "1. Valid phone contacts equals **one** point each.
> 2. Valid CW contacts equals **two** points each.
> 3. Valid digital contacts equals **two** points each."

| Mode | Points |
| --- | --- |
| Phone | 1 |
| CW | 2 |
| Digital | 2 |

## 5. Dupe rule

> "All Missouri stations may work any other Missouri station **once per mode on
> each band per Missouri county**. Missouri stations may work non-Missouri
> stations once per mode per band. All non-Missouri stations may work Missouri
> stations once per mode on each band per Missouri county."

→ `dupeScope: "bandMode"`, with a county change making a new QSO — already how
`DupeChecker` behaves, since `theirLoc` is part of the key.

## 6. Multipliers

> "1. The multipliers for **Missouri stations** are Missouri counties (**115
> maximum**), US states (**49 maximum**), and Canadian provinces and territories
> (13 maximum) worked. **An additional multiplier of the value of one will be
> added if at least one DX station is worked.**
> 2. The multipliers for **Non-Missouri and DX stations** are Missouri Counties
> (115 maximum) worked."

| | In-state (MO) | Out-of-state |
| --- | --- | --- |
| Classes | 115 counties + 49 states + 13 provinces + **one** DX | **115 MO counties** |
| Scope | **once overall** | **once overall** |

→ `countScope: "once"` on both sides — the stated maxima settle it, exactly as
they did for WIQP: a per-band count could not have a maximum of 115.
`inState.classes = [county, state, province, dx]`; `outState.classes = [county]`.

- **`homeStateCountsViaCounty: false`** — *"US states (**49** maximum)"*. Not 50,
  so Missouri is excluded; the sixth party this run to say so by arithmetic or
  outright, after MNQP, NCQP, VAQP, LAQP and MSQP.
- *"An additional multiplier of the value of **one** … if at least one DX station
  is worked"* — which is precisely what `dxStyle: "token"` produces, since every
  DX contact yields the single value `DX`. No cap needed.
- No `stateAliases`: DC is never mentioned.

**One multiplier rule is not modelled** — the self-activation provision, for the
**fifth** time this run:

> "3. Any **mobile or portable** category entry that makes **50 or more** valid
> contacts from a county or county lines will be given the multiplier for that
> county or counties."

Fifth user after TnQP, SCQP, NCQP and VAQP — and the highest threshold yet at 50
(TnQP 10, SCQP 1, NCQP unconditional, VAQP 10). In-state mobiles and portables
only.

## 7. Bonus points — five rules, and only two fit

> "4. At least one valid contact with the **WØMA** special event station will
> count as a **single 100-point bonus** added to the total score.
> 5. At least one valid contact with special event station **KØGQ** will count as
> a single **100-point** bonus…
> 6. **A 100 point bonus will be awarded for successfully submitting a Cabrillo
> log electronically.**
> 7. Any valid contacts made **between the hours of 1400 UTC Saturday to 2000 UTC
> Saturday and 1400 UTC Sunday to 2000 UTC Sunday** on the **40 and 80 meter**
> bands will count as **an additional point each. Up to 250-point bonus** can be
> added to the total score."

| Rule | Modelled? |
| --- | --- |
| WØMA, 100 once | ✅ `workStation(scope: "once")` |
| KØGQ, 100 once | ✅ `workStation(scope: "once")` |
| Cabrillo submission, 100 | ❌ not about QSOs at all |
| 40/80 m daytime, +1/QSO capped at 250 | ❌ band **and** time **and** cap |

The last is the interesting one: a per-QSO bonus conditioned on **band** *and* on
a **time window narrower than the contest**, with a **cap**. Nothing in
`BonusRule` carries any of those three. See §13.

> "Score … multiplying the total number of valid contact points by the total
> number of multipliers, then **adding the bonus points**."

No power multiplier; power selects the entry class. `scoreMultipliers` absent.

## 8. County-line rules

> "Expedition stations may be located at the **intersection of two or more
> counties**. County line operations must **log these contacts as separate
> QSOs**. Single-op expedition operations from county lines must have a portion
> of the station **physically located inside each county claimed**… All equipment
> (including antennas) must lie within a circle whose diameter does not exceed
> **300 meters (1000 feet)**."

**"Two or more", with no stated cap.** → `maxSimultaneousCounties: 4`, this app's
own maximum rather than a sponsor's number — the same honest default SCQP got,
and recorded as such. The required logging shape ("separate QSOs") is exactly what
`CountyLineExpander` produces.

## 9. Valid bands

> "CW, Digital, and phone operation on **160M, 80M, 40M, 20M, 15M, 10M, 6M, 2M,
> 1.25M, and 70cm**."

**Ten bands**, listed outright — the joint-largest list in the repo with WIQP and
VAQP, and the third party to include 1.25 m.

## 10. Categories

**Missouri Fixed** (Multi-Op; Single-Op High >150 W / Low ≤150 W / QRP ≤5 W) ·
**Missouri Expedition** (temporary station, may sit on a county intersection,
300 m circle) · plus mobile and portable classes referenced by the multiplier
rule. *"MOQP participants may not submit entries in multiple categories."*

## 11. Cabrillo `CONTEST:` header

**`MO-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, fetched 2026-07-26), Article 1's
codified exception. The rules **require** Cabrillo and even pay 100 points for
submitting it, but never print the `CONTEST:` value.

## 12. County list

**115 entities** — Missouri's 114 counties **plus the independent City of St.
Louis**, which the sponsor lists as `STL` "St. Louis City" alongside `SLC` "St.
Louis County". Uniform 3-letter codes.

**`STL` vs `SLC` is the trap this party turns on**: two adjacent, differently
governed entities whose names differ by one word, with codes that share all three
letters in a different order. Getting them the wrong way round swaps a county for
a city.

Other clusters worth spot-checking:

1. **Five `C-l` codes, none obvious:** `CAL` Callaway, `CLA` Clay, `CLK` Clark,
   `CLN` Clinton, **`CWL` Caldwell**.
2. **Four `B` counties:** `BAR` Barry, **`BTN` Barton**, `BAT` Bates, **`BTR`
   Butler** — the two that contract are not the two you would guess.
3. **Four `M` counties:** `MAC` Macon, `MAD` Madison, `MAR` Marion, `MCD`
   McDonald.
4. **The `S` block:** `SAL` Saline, `SCH` Schuyler, `SCL` St. Clair, `SCO` Scott,
   `SCT` Scotland, `STC` St. Charles, `STF` St. Francois, `STG` St. Genevieve.
   Eight codes, five of them `SC*`/`ST*`.
5. **The sponsor prints "St. Genevieve"**; the county is officially **Ste.
   Genevieve**. Shipped as printed, per the repo's practice with NHQP's
   "Merrimac" and NCQP's "Chowen".
6. `CPG` Cape Girardeau, `CHN` Chariton and `LCN` Lincoln are contractions.

## 13. Engine shapes to watch

1. **A band-and-time-windowed per-QSO bonus, with a cap.** §7 rule 7. Contacts on
   **40 and 80 m** during two six-hour daytime windows earn **+1 point each**, up
   to **250**. `BonusRule` has no band predicate, no time predicate and no cap —
   three separate absences in one rule. It is also the first bonus in the repo
   that adds to *QSO points* rather than to the post-multiplication total, so it
   compounds. Recorded; **every entrant is affected**, since 40 and 80 m in
   daylight are where most of this contest happens.
   *(A band predicate is now wanted by two rules — this one and WIQP's
   below-50 MHz W9FK bonus — which is the second data point for that field.)*
2. **A non-QSO bonus.** §7 rule 6: 100 points simply for submitting a Cabrillo
   log electronically. Nothing in the engine models a bonus that is not about
   contacts, and arguably nothing should — but an operator's claimed score is 100
   higher than this app's, every time, so it must be said in `notes`.
3. **Self-activation multipliers — FIFTH user**, at the highest threshold yet
   (50 contacts). §6.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| phone 1, CW 2, digital 2 | `points` |
| "once per mode on each band per county" | `dupeScope: "bandMode"` |
| stated maxima of 115 / 49 / 13 | `countScope: "once"`, both sides |
| "US states (49 maximum)" | `homeStateCountsViaCounty: false` |
| "one … if at least one DX station is worked" | `dxStyle: "token"` |
| WØMA and KØGQ, 100 each, once | two `workStation(scope: "once")` |
| "two or more counties", uncapped | `maxSimultaneousCounties: 4` (this app's max) |
| 160 m – 70 cm, ten bands | `validBands` |

**`outStateWorksHomeStationsOnly` is inferred, not stated.** The objective points
that way — *"to provide all licensed radio amateurs outside the state of Missouri
the opportunity to work Missouri counties"* — and non-Missouri multipliers are MO
counties only; but the same objective also gives Missouri stations *"an
opportunity to work other states and countries"*, and no sentence forbids a
non-Missouri pair. Shipped **on**, as for the seven other parties that only imply
it. Recorded as an open question.

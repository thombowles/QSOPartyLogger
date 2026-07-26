# Louisiana QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The first party whose home entities are parishes, not counties**, and the
second (after ILQP) to group CW with digital as one mode.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Louisiana Contest Club**, club call **`N5LCC`** |
| Chairman | Bobby, **WM5H** — `questions@laqp.org` |
| **Rules** | <https://laqp.louisianacontestclub.org/laqso-rules-htm/> |
| Parish list | <https://laqp.louisianacontestclub.org/la-parish-abbreviations/> |
| Logs | LAQP Log Handling site, **Cabrillo**, within **10 days** |
| Fetched | **2026-07-26** |

Banked verbatim: [`laqp_rules_2026.txt`](laqp_rules_2026.txt),
[`laqp_parishes.txt`](laqp_parishes.txt).

**The site is partly stale, and it matters for exactly one field.** Its footer
reads "© 2026 The Louisiana QSO Party" and the rules are otherwise current in
substance, but **rule 2 still carries the 2025 dates**, the "LAQP Dates" menu
item **404s**, and the Recent Posts list stops at the 2021 results. Every rule
below except the schedule is taken from the page as printed; §2 explains what the
schedule rests on instead.

## 2. Dates and times for 2026, in UTC — **derived, and the open question**

> "2. Contest Period: The Louisiana QSO Party will run from **14:00 UTC April 5,
> 2025 to 02:00 UTC April 6, 2025**" — rule 2, *unchanged from the 2025 running*

**The sponsor publishes no 2026 date anywhere.** Shipped:

| Start | End | Length |
| --- | --- | --- |
| `2026-04-04T14:00:00Z` | `2026-04-05T02:00:00Z` | 12 h |

The derivation, and it is weaker than any other party built this run:

1. **The shape is stable.** 1400Z Saturday → 0200Z Sunday, twelve hours, is what
   rule 2 prints for 2025 and what the LAQP has run for years.
2. **The day follows "first Saturday in April"**, which fits the printed 2025
   date exactly — 1 April 2025 was a Tuesday, so the first Saturday was the 5th ✓
   — and gives **Saturday 4 April 2026** (1 April 2026 is a Wednesday). The
   sponsor's own archived post *"2020 LAQP is April 4th"* fits the same rule
   (1 April 2020 was a Wednesday).
3. **The State QSO Party Challenge calendar independently prints
   `4/4 1400Z → 4/5 0200Z`.**

**But the sponsor states no formula**, so point 2 is inference from two data
points rather than a rule — unlike ILQP, whose page prints "Sunday the third full
weekend of October". That makes the date this party's principal open question,
and `verified: partial` rests mainly on it. One email to `questions@laqp.org`
settles it.

## 3. Exchange

> "7.1 Non-Louisiana stations send **call, signal report and
> state/province/country**
> 7.2 Louisiana stations send **call, signal report and parish abbreviation**"

| Role | Sends |
| --- | --- |
| **In-state (LA)** | RS(T) + one of the 64 parish codes |
| **Out-of-state** | RS(T) + state, province, or **country** |

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`.

→ **`dxStyle: "prefix"`** — the sponsor asks for a *country*, not the literal
"DX", and Louisiana stations count **DXCC** entities individually (§5), so the
prefix is what tells them apart.

## 4. QSO points by mode

> "8.1.1 Count **two (2) points** for each complete PHONE QSO
> 8.1.2 Count **four (4) points** for each complete CW/Digital QSO"

| Mode | Points |
| --- | --- |
| Phone | 2 |
| CW | 4 |
| Digital | 4 |

**CW at 4 points ties BCQP for the highest in the repo**, and digital matches it —
the sponsor treats the two as one thing throughout (§6).

## 5. Multipliers

> "8.2.1 For Non-Louisiana stations, multipliers are Louisiana Parishes (**64
> possible per band/mode**)
> 8.2.2 For Louisiana stations, multipliers are: Louisiana Parishes, **States
> (other than Louisiana)**, Provinces, and DXCC, **per band/mode**
> 8.2.3 …the following **13 Canadian provinces** shall be recognized: AB, BC, MB,
> NB, NL, NS, NT, NU, ON, PE, QC, SK, and YT. **To be more in line with other
> state QSO parties, Maritime regions will not be recognized as multipliers.**"

| | In-state (LA) | Out-of-state |
| --- | --- | --- |
| Classes | 64 parishes + 49 states + 13 provinces + DXCC | **64 LA parishes only** |
| Scope | **per band and mode** | **per band and mode** |

→ `countScope: "perBandMode"` on both sides — the fourth party to use it, after
MEQP, BCQP and SCQP. The sponsor's "64 possible per band/mode" is what fixes it.

- **`homeStateCountsViaCounty: false`, stated outright** — *"States (**other than
  Louisiana**)"*. Fourth party this run to exclude its own state explicitly,
  after MNQP, NCQP and VAQP.
- The 13 are the standard list with the standard `NL`, and the sponsor explains
  *why* it dropped the Maritime sub-regions it once counted — a rare case of a
  sponsor documenting its own alignment with other parties.
- No `stateAliases`: DC is never mentioned.

## 6. Dupe rule — CW and digital are **one** mode here

> "9.4 All fixed stations may be worked **once on CW/Digital and once on Phone
> PER BAND**
> 9.1 Multipliers: **CW/Digital and Phone contacts count as separate
> multipliers**"

The sponsor has **two** mode groups — Phone, and CW/Digital together — where this
app has three `ModeClass` cases. So working one station on CW and again on RTTY
on the same band is two QSOs here and **one** for the sponsor.

**This is exactly ILQP's gap, and LAQP is its second user** — which matters,
because VTQP wants the *opposite* (RTTY split out of the WSJT group). See §13.

> "9.4.1 Rovers may be worked once on CW/Digital and once on Phone per band, **in
> EACH parish activated**."

A parish change makes a new QSO, already how `DupeChecker` behaves.

## 7. Bonus points

**Two, and both fit.**

> "9.5 Any station working **N5LCC**, the Louisiana Contest Club station, may
> claim a **one-time 100 POINT BONUS**."

→ `workStation(call: "N5LCC", points: 100, scope: "once")` — "one-time" is
explicit.

> "8.3.3 Rovers: Multiply QSO points by total multipliers …, **PLUS 50 points per
> Parish activated**"

→ `activatedCountyCount(minQSOs: 1, points: 50)`. No QSO threshold is stated, so
one contact activates; the engine already gates on an in-state roving category.

**No power multiplier** — High/Low/QRP select the award only (rule 6).

## 8. Parish-line rules

> "9.4.3 Rovers who are **PRECISELY on a parish line** may give contacts for
> **both parishes**, however, a separate and complete QSO and log entry must be
> made for each contact"

→ `maxSimultaneousCounties: **2**`, with each parish on its own log line — which
is exactly what `CountyLineExpander` produces.

## 9. Valid bands

> "1. Object: …on the **160, 80, 40, 20, 15, 10, 6 and 2 meter** bands"
> "3.4 **No WARC band contacts**"

**Eight bands:** `160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m`. Stated in the objective
rather than a band rule, and confirmed by the suggested-frequency lists, which
cover 160–10 m plus 50 and 144 MHz for both CW and phone.

## 10. Categories

Twelve main categories, in four groups of three (Phone only / CW-Digital only /
Mixed): **Non-Louisiana**, **Louisiana fixed**, **Rover (inside Louisiana)**, plus
three **Overlays** — `WIRES`, `TB-WIRES` and **`POTA`** (*"POTA, Campground,
Federal Wildlife Refuge"*). Power: High ≤1500 W, Low ≤100 W, QRP ≤5 W, with
*"if ANY contacts are made at a higher power level, then the entire log shall be
classified at that higher power level"*.

Unusually, **`CATEGORY-OPERATOR` is ignored**: *"Cabrillo tag is ignored and
everyone is lumped together regardless of the number of operators."*

Assistance: spotting is allowed, **self-spotting is not**.

## 11. Cabrillo `CONTEST:` header

**`LA-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, fetched 2026-07-26), Article 1's
codified exception, because **the rules print no `CONTEST:` value** despite
requiring Cabrillo (*"All logs generated using a computer must submit an ASCII
text file of the log in ARRL (Cabrillo) format"*).

## 12. Parish list

**64 parishes** — Louisiana has parishes, not counties, and this is the first
bundled party where that is so. **Mixed 3- and 4-character codes**: 59 are four
characters, five are three.

The five three-character codes are all contractions of long names:

| Code | Parish |
| --- | --- |
| `EBR` | East Baton Rouge |
| `WBR` | West Baton Rouge |
| `PCP` | Pointe Coupee |
| `SJB` | St. John Baptist |
| `SMT` | St. Martin |

Traps worth spot-checking:

1. **Nine `St.` parishes, and no two follow the same pattern:** `SBND` St.
   Bernard, `SCHL` St. Charles, `SHEL` St. Helena, `SJAM` St. James, **`SJB`** St.
   John Baptist, `SLAN` St. Landry, **`SMT`** St. Martin, `SMAR` St. Mary, `STAM`
   St. Tammany. Note `SMT` (Martin) against `SMAR` (Mary) — three characters
   against four, for two parishes whose names differ by three letters.
2. **The Baton Rouge / Carroll / Feliciana triples:** `EBR`/`WBR`, `ECAR`/`WCAR`,
   `EFEL`/`WFEL` — East and West of each, and only the Baton Rouges contract.
3. `JFDV` Jefferson Davis vs `JEFF` Jefferson — two different parishes.
4. `LASA` La Salle, `DESO` De Soto and `REDR` Red River are two words each.
5. **The sponsor prints "St. John Baptist"**, dropping the "the" of the official
   *St. John the Baptist Parish*. Shipped as printed.

## 13. Engine shapes to watch

1. **Mode grouping — ILQP's gap gets its second user.** §6. LAQP's split is
   two-way (Phone | CW/Digital) and this app keys on three mode classes, so a CW +
   RTTY pair on one band shows as two valid QSOs where the sponsor counts one, and
   as two multipliers where the sponsor counts one. **Multipliers are affected
   here, which they were not in ILQP** — ILQP counts multipliers once overall, so
   only its dupe accounting was wrong; LAQP counts *per band/mode*, so the
   over-count propagates into the score.
   Two parties now want the coarser grouping (ILQP, LAQP) and one wants a finer
   one (VTQP, which splits RTTY out of WSJT). The worklist's sketch — a
   party-supplied partition of modes consulted by both `DupeChecker` and the
   multiplier scope — covers all three; this is the third data point and the
   first where it moves a score.
2. **The 2026 date is inferred, not published.** §2.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| phone 2, CW/digital 4 | `points` |
| once per band per mode group | `dupeScope: "bandMode"` (see gap 1) |
| "64 possible per band/mode" | `countScope: "perBandMode"`, both sides |
| "States (other than Louisiana)" | `homeStateCountsViaCounty: false` |
| "state/province/country" | `dxStyle: "prefix"` |
| both parishes on a line, logged separately | `maxSimultaneousCounties: 2` |
| N5LCC one-time 100 | `workStation(… scope: "once")` |
| 50 points per parish activated | `activatedCountyCount(minQSOs: 1, points: 50)` |
| "Non-Louisiana stations work Louisiana stations only" | `outStateWorksHomeStationsOnly: true` |

**`outStateWorksHomeStationsOnly` is rule 1.2** — *"Non-Louisiana stations work
Louisiana stations only"* — the fifteenth party to state it rather than imply it.

# Oklahoma QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The sharpest provenance trap of the run:** the page that ranks first in search
for this party is the **2003** rules, and it is wrong in four scoring dimensions.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Oklahoma DX Association / OKQP**, contact **K5CM** |
| **Rules** | <http://k5cm.com/okqp2026rules.pdf> — "The 2026 Oklahoma QSO Party" |
| Summary page | <http://k5cm.com/okqp.htm> — a **frameset**; the content is `oklahoma_qso_party_for_2012_will.htm` |
| County list | <http://k5cm.com/counties_files/counties-x.htm> — "Oklahoma County Locator Map" |
| Log robot | <https://okqp.contesting.com/> (site revision date **February 27, 2026**) |
| Deadline | 2026-04-05 |
| Fetched | **2026-07-26** |

Banked verbatim: [`okqp_rules_2026.txt`](okqp_rules_2026.txt),
[`okqp_counties.txt`](okqp_counties.txt),
[`okqp_summary_page.txt`](okqp_summary_page.txt).

### The 2003 page, and why it matters

**<https://www.qsl.net/okdxa/OKQP.htm> is the 2003 rules** — headline "2003
Oklahoma QSO Party", dates "1100 UTC 22 MARCH 2003". It is still live, still
indexed, and still the top search result for this party. Building from it would
have been wrong four times over:

| Rule | 2003 page (wrong) | 2026 rules |
| --- | --- | --- |
| Exchange | "send **QSO number** and county" | "send **signal report** and county" |
| Canadian provinces | "Canadian Provinces (**9**)" | "The **13** Canadian Provinces/Territories" |
| Bands | "**160**, 80, 40, 20, 15, 10, 6 meters" | "3.5, 7, 14, 21, 28, 50, and **144** MHz" — no 160, plus 2 m |
| Mobile bonus | none | **500 points per county** with ≥10 QSOs |
| DXCC multipliers | not counted | counted by OK stations, uncapped |

A QSO-number exchange instead of a signal report would have mis-set
`exchangeIncludesSerial`, put the wrong token in every Cabrillo line, and driven
the wrong CW macros. **Reaching the real rules needed three hops:** search → the
2003 qsl.net mirror → `okqp.contesting.com` (the log robot, which is current) →
its "OKQP Home" link to `k5cm.com/okqp.htm` → the frameset's content frame.

*(The live content frame is served from a file named
`oklahoma_qso_party_for_2012_will.htm`. The **filename** is a 2012 leftover; the
**content** is headed "Oklahoma QSO Party 2026". Third party in a row where a
filename lies about a year — after MNQP and SCQP.)*

## 2. Dates and times for 2026, in UTC

> "Saturday March 14 **1400 to 0200** UTC / Sunday March 15 **1400 to 2200** UTC
> — 9 to 9 on Saturday, 9 to 5 on Sunday, local Oklahoma time" — rules header

**Two windows ship:**

| Segment | Start | End | Length |
| --- | --- | --- | --- |
| Saturday | `2026-03-14T14:00:00Z` | `2026-03-15T02:00:00Z` | 12 h |
| Sunday | `2026-03-15T14:00:00Z` | `2026-03-15T22:00:00Z` | 8 h |
| | | **total** | **20 h** |

**The local anchors confirm the UTC times only under CDT, and that is the
subtlety.** The summary page says *"DST does NOT start on this weekend"*, which
is easy to misread as "Oklahoma is on standard time". It is not: US DST began
**Sunday 8 March 2026**, the *previous* weekend, so Oklahoma is on **CDT
(UTC−5)** throughout. Then 1400Z = 9 am ✓, 0200Z = 9 pm ✓, 2200Z = 5 pm ✓ —
all three of the sponsor's local anchors land exactly. Under CST every one of
them would be an hour out.

**One discrepancy, recorded and not carried:** the rules also say *"Everyone may
operate the entire **19 hour** period"*, where the two windows total 20. The four
printed instants and all three local anchors agree with each other and with the
State QSO Party Challenge calendar; the lone "19" agrees with nothing, and reads
as a leftover from the 2003 rules' off-time limit (*"All entries may operate 18
hours of the 24 hour time frame"*). **20 hours ship.**

## 3. Exchange

> "Oklahoma stations send **signal report and county**.
> W/VE stations (**including KH6/KL7**) send signal report and state or province.
> DX stations (**including KH2/KP4**) send signal report and **DXCC prefix**."

| Role | Sends |
| --- | --- |
| **In-state (OK)** | RS(T) + one of the 77 county codes |
| **W/VE** | RS(T) + state or province; **Alaska and Hawaii are W/VE**, not DX |
| **DX** | RS(T) + **DXCC prefix**; **Guam and Puerto Rico are DX**, not states |

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: **false**` — and that
second one is the trap the 2003 page sets (§1).

→ `dxStyle: "prefix"`. DX sends a prefix, and OK stations count **DXCC countries
individually** (§6), so the prefix is what distinguishes them. This is the
opposite of NCQP and MNQP, where all DX collapses to one multiplier.

**The KH6/KL7 vs KH2/KP4 split is stated in the same breath and is worth
keeping:** Alaska and Hawaii send a state, Guam and Puerto Rico send a prefix.

## 4. QSO points by mode

> "Count **two** points per phone QSO with any station. Count **three** points
> per CW QSO. Count **three** points per Digital QSO (No FT8/FT4)."

| Mode | Points |
| --- | --- |
| Phone | 2 |
| CW | 3 |
| Digital | 3 |

Stated identically for Oklahoma and non-Oklahoma stations, so a single `points`
table covers both — no `homeStationPoints` here.

**FT8 and FT4 are barred outright**, and the sponsor says so four separate times
("NO FT8 allowed", "No FT8/FT4", *"Just to be clear, no FT8 or FT4"*). The
summary page names what *is* allowed: *"Only PSK, RTTY and JS8Call are allowed as
digital contacts."* Below the granularity of `ModeClass.digital`; recorded in
`notes`.

> "Again this year, **CW and Digital contacts will be scored separately**, so you
> can work the same station on both CW and PSK and get credit for both modes."

That is exactly how `ModeClass` behaves — three classes, CW distinct from digital
— so OKQP needs nothing. Worth recording as the counter-case to ILQP, which
groups CW with digital and is one of the two parties driving the mode-grouping
engine gap.

## 5. Dupe rule

> "Stations may be worked again on each band and mode." → `dupeScope: "bandMode"`.

> "Oklahoma mobile stations that change counties are considered to be a new
> station and may be worked again for QSO and multiplier credit."

Already how `DupeChecker` behaves.

## 6. Multipliers

> "**Oklahoma stations** — The 50 states (**DC counts as Maryland**); The 13
> Canadian Provinces/Territories - NS, NB, NL, PE, QC, ON, MB, SK, AB, BC, NT,
> NU, YT ; The 77 Oklahoma counties; **DXCC countries*** (excluding US, Canada,
> KH6 and KL7). **A Multiplier counts once, regardless of the number bands or
> modes it is worked on.** *(note: OK stations please do not abuse the unlimited
> dxcc mult rule by s/p only DX stations)."
>
> "**Non Oklahoma stations** — The 77 Oklahoma counties."

| | In-state (OK) | Out-of-state |
| --- | --- | --- |
| Classes | 77 counties + 50 states + 13 provinces + **uncapped DXCC** | **77 OK counties only** |
| Scope | **once overall** | **once overall** |

→ `countScope: "once"` both sides; `inState.classes = [county, state, province,
dx]`, `outState.classes = [county]`. No `dxMultCap` — the sponsor calls it "the
**unlimited** dxcc mult rule" in its own aside.

- **`stateAliases: {"DC": "MD"}`** — "DC counts as Maryland", the same call VTQP,
  BCQP and MDC make, and the opposite of MNQP, NCQP and SCQP. Six parties, split
  three-three: there is no default worth assuming.
- The 13 are enumerated and are the standard 13 with the standard `NL`.

**`homeStateCountsViaCounty: true`, on a weaker footing than SCQP's.** The rules
say "The 50 states" without qualification, and Oklahoma is one of the 50 — while
OK stations always send a county, so `OK` is never received. Two parties this run
excluded their home state *explicitly* (MNQP: "49 states (does not include
Minnesota)"; NCQP: "49 US States (not NC)"), and this one conspicuously does not.

**The 2003 page settles the sponsor's intent, and is cited only for that:**
*"Oklahoma stations working other Oklahoma stations must log the complete
exchange, including county **even though they all count as the 'OK'
multiplier**."* That is not authority for a 2026 rule (Article 1), so it does not
decide the flag on its own — but it does mean the plain reading of "the 50
states" is the sponsor's long-standing practice rather than an inference. Shipped
`true` with an open question.

**No stated total to check the arithmetic against**, unlike MNQP's 151, NCQP's
164 and BCQP's implied ceiling — the uncapped DXCC class makes one impossible.

## 7. Bonus stations and bonus points

**No bonus station.** One activation bonus, and it fits the schema exactly:

> "Oklahoma Mobile stations can earn **500 points per county** by making at least
> **10 QSO** in the county." — rules, *Bonus*; repeated on the summary page as a
> 2026 change ("For 2026: …")

→ `activatedCountyCount(minQSOs: 10, points: 500)` — **the identical rule TnQP
has**, down to both numbers, and the engine already models it. Applies to
in-state roving categories only, which is what `ScoreEngine` already gates on.

## 8. Final-score multipliers

**NONE.** *"Scoring: Multiply total QSO Points by total Multipliers."* Power
selects the entry class only. `scoreMultipliers` absent.

## 9. County-line rules

> "Oklahoma mobile stations operating on a **2, 3, or 4 county line** may be
> counted as 2, 3, or 4 QSO and multipliers. **Separate log entries must be
> entered for each county/QSO** by both Oklahoma and Non Oklahoma stations."
>
> "**Do not put PIT/LAT/HAS on the same line in your log.** Use a separate line
> for each county." — Miscellaneous
>
> "Ex: MUS/OKM/MCI is **NOT exceptable**. Each county must have a separate line
> in the Cabrillo file." [sic]

→ `maxSimultaneousCounties: **4**`, stated outright — the second party after IAQP
to allow four, and the only one to name a real three-county junction (Pittsburg /
Latimer / Haskell) while forbidding it *on one line*.

**Entering `PIT/LAT/HAS` in this app is correct, not forbidden.**
`CountyLineExpander` turns one entry into separate rows sharing a `groupID`, which
is precisely the "separate line for each county" the sponsor demands. The
prohibition is on loggers that emit one Cabrillo line carrying three counties.

The sponsor adds a safety proviso worth quoting: *"Make sure you can get to the
County line… Operating from either end of a bridge on a water county line is OK.
Do not park in the middle of a bridge."*

## 10. Valid bands

> "Operate **only** the 3.5, 7, 14, 21, 28, 50, and 144 MHz bands." — rules

**Seven bands:** `80m, 40m, 20m, 15m, 10m, 6m, 2m`.

**No 160 m** — and the 2003 page *did* include it, which is the fourth of its
four errors. The suggested-frequency lists cover 80 through 10 for CW and 80
through 6 for phone; 2 m is in the band rule and ships.

## 11. Categories

**Oklahoma fixed:** SOHP (>100 W), SOLP (≤100 W), QRP (≤5 W), Multi-1, Multi-Multi.
**Oklahoma mobile:** Non-Assisted (no driver or second op), Assisted (driver may
not operate), Unlimited (any number of operators, one signal, mixed only).
**Non-Oklahoma:** Single-Op High/Low/QRP × CW/SSB/Mixed, Multi-Op.
**DX:** Single-Op High/Low × CW/SSB/Mixed.

The rules print the exact `CATEGORY:` strings to paste into the Cabrillo header —
a single free-text `CATEGORY:` line rather than the split `CATEGORY-*` headers
most parties use. Recorded because this app writes the split form.

Assistance is unrestricted: *"Spotting nets, packet node, internet spotting
websites etc, can be used by all stations."*

## 12. Cabrillo `CONTEST:` header

**`OK-QSO-PARTY` — printed by the sponsor** in its own worked Cabrillo example:

```
CALLSIGN: K5CM
CONTEST: OK-QSO-PARTY
LOCATION: OK
QSO: 7042 CW 2014-03-22 1301 K5CM  599 MUS  K4AMC  599 TN
```

Article 1's WA7BNM exception is not needed. The example's exchange columns
confirm §3: a signal report and a location, no QSO number.

## 13. County list

**77 counties, uniform 3-letter codes**, from the sponsor's "Oklahoma County
Locator Map" page, which numbers them 1–77 left to right, top to bottom.

**The sponsor names its own traps**, which makes them the best possible spot
checks — seven pairs it says "cause considerable confusion":

| | | |
| --- | --- | --- |
| `GAR` Garfield | `GRV` Garvin | |
| `GRA` Grady | `GNT` Grant | |
| `HAR` Harmon | `HRP` Harper | |
| `MCL` McClain | `MCU` McCurtain | (and `MCI` McIntosh) |
| `ROG` Rogers | `RGM` Roger Mills | |
| `WAS` Washington | `WAT` Washita | |
| `WOO` Woods | `WDW` Woodward | |

Every one of these is a case where the naive first-three-letters would pick the
*other* county of the pair. The generator asserts all fourteen, plus `MCI`.

Two further notes: `LEF` is Le Flore (two words), and `OKL` Oklahoma County is
distinct from the `OK` state token, which is never sent.

## 14. Engine shapes to watch

**None — this party needs no schema change**, which after NCQP is worth saying
plainly. Everything maps:

| Rule | Field |
| --- | --- |
| phone 2, CW 3, digital 3 | `points` |
| "worked again on each band and mode" | `dupeScope: "bandMode"` |
| "counts once, regardless of … bands or modes" | `countScope: "once"`, both sides |
| "The 50 states" incl. OK, county always sent | `homeStateCountsViaCounty: true` |
| "DC counts as Maryland" | `stateAliases {"DC": "MD"}` |
| DX sends a prefix, DXCC counted individually | `dxStyle: "prefix"`, no cap |
| "2, 3, or 4 county line" | `maxSimultaneousCounties: 4` |
| 500 points per county with ≥10 QSOs | `activatedCountyCount(minQSOs: 10, points: 500)` |
| "Non Oklahoma stations work only Oklahoma stations" | `outStateWorksHomeStationsOnly: true` |
| two windows, 12 h + 8 h | `schedule` |

Two things recorded in `notes` rather than modelled, neither of which changes a
score:

1. **FT8/FT4 are barred while other digital modes are allowed** — below
   `ModeClass.digital`'s granularity. The same limitation ILQP carries, and the
   third party to want it (ILQP, NCQP, OKQP), though NCQP's is a separate-event
   exclusion rather than a ban.
2. **The Cabrillo `CATEGORY:` line is a single free-text string** here
   (`OKLAHOMA MOBILE ASSISTED LOW MIXED`), where this app writes the split
   `CATEGORY-*` headers. The sponsor's robot accepts standard Cabrillo, so this
   is a cosmetic mismatch at worst, but an entrant chasing a specific category
   award should paste the sponsor's exact string.

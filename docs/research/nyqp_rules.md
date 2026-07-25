# New York QSO Party (NYQP) — 2026 Rules Research

Researched 2026-07-24 for Mac contest logger implementation.
Written to the [Article 15](../CONSTITUTION.md#article-15--research-before-code) template.

## 1. Sponsor / sources

- Sponsor: the **Rochester (NY) DX Association**, whose own sample Cabrillo header
  in the rules reads `CLUB: Rochester (NY) DX Assoc`. Site: https://nyqp.org
- Rules page (fetched 2026-07-24): https://nyqp.org/wordpress/nyqp-rules/
- **Official rules PDF**, 17 pages, footer `v1.2 FINAL 2025-10-01`:
  `nyqp.org/wordpress/wp-content/uploads/2025/10/2025-New-York-QSO-Party-Rules-v1.2-2025-10-01-FINAL.pdf`
  — extracted to [`nyqp_rules_2025.txt`](nyqp_rules_2025.txt).
- **Official county CSV**, abbreviations only:
  `nyqp.org/wordpress/wp-content/uploads/2025/04/NYQP-Counties-Sheet1.csv` —
  committed as [`nyqp_counties.csv`](nyqp_counties.csv).
- Log submission: Cabrillo only, via the webform at
  https://nyqp.contesting.com/nyqpsubmitlog.php, within 14 days. "Paper logs are
  not accepted."

**This is the best-documented party in the repo.** The rules PDF carries a table
of contents, a full county table, a Canadian multiplier list, *and* a complete
**Cabrillo log specification with a sample header and sample QSO lines** — which
means §12 below needs no WA7BNM fallback for the first time in this project.

Two sponsor sources cover the counties and they are used against each other: the
**names** come from the rules PDF's Name/Abbreviation table, and the
**abbreviation set** is cross-checked against the official CSV.
[`gen_nyqp.py`](gen_nyqp.py) asserts the two agree exactly, so a
mis-parse of either shows up as a set difference rather than as a wrong county.

*(Parsing note for the next session: "New York County List" and "SCORING" both
appear in the PDF's table of contents before they appear as headings, so anchoring
a parser on those strings alone captures the TOC. The generator anchors on the
table's own `Name  Abbreviation` header row instead.)*

## 2. Dates and times for 2026, in UTC

The published rules are the **2025** edition:

> "**Third Saturday in October**: October 18, 2025 1400 UTC (10 AM Eastern) —
> **12 Hours**"
> "12-hour Contest Period: October 18, 2025, from **14:00:00 UTC through
> 01:59:59 UTC**. (10:00 AM Eastern Time through 9:59:59 PM Eastern Time)."

The sponsor has not yet posted a 2026 revision — the same situation as AZQP and
PAQP. But the **formula is stated in the document's own title block**, and it
settles 2026 without ambiguity:

- "Third Saturday in October" → October 2026's Saturdays are 3, 10, **17**, 24,
  31, so the third is **Saturday 17 October 2026**.
- The times transfer unchanged, and the rules' own parentheticals prove the
  offset: 1400 UTC = 10 AM Eastern and 01:59:59 UTC = 9:59:59 PM Eastern, i.e.
  EDT at UTC−4. 17–18 October 2026 is still EDT — US DST ends 1 November 2026.
- 2025's own instance checks the formula: 18 October 2025 *was* the third
  Saturday.

**Ships as one 12-hour window:**
`2026-10-17T14:00:00Z → 2026-10-18T02:00:00Z`.

The rules write the end as `01:59:59 UTC`; the schedule stores the exclusive
02:00:00 instant, which is the same window and how every other party in this repo
is stored.

## 3. Exchange

> "New York stations send signal report and **three-letter county
> abbreviation**.* Contacts must be logged using the three character
> abbreviations listed below."
> "*Stations operating on a county line shall transmit **both county names**
> (phone) or three-letter designators (CW, digital modes)."
> "Stations outside of New York send signal report plus **state or Canadian
> province** (see list below). For those outside the US and Canada, send signal
> report and **"DX."**"

- RST **is** part of the exchange → `exchangeIncludesRST: true`; no serial number.
- DX form is the literal token → `dxStyle: "token"`.
- The sponsor's sample Cabrillo QSO lines confirm the shape end to end:
  `QSO: 14006 CW 2022-09-05 2117 N2ZN 599 MON KH7X 599 HI`.

## 4. QSO points by mode

> "Each complete, non-duplicate **Phone** contact is worth **1 point** per band.
> Each complete, non-duplicate **CW** contact is worth **2 points** per band.
> Each complete, non-duplicate **RTTY (or other valid digital mode)** contact is
> worth **3 points** per band."

**Digital is legal and pays the most** — 3 points, the first party in the repo
where digital outscores CW. → `allowedModes` is all three classes.

> "All RTTY/digital modes are considered to be the same mode. Only digital modes
> that natively support the NYQP exchange are permitted for contest credit."
> "RTTY and digital modes are permitted in the **Mixed** category only."

The Mixed-category restriction is an entry-class rule, not a scoring one, so it
does not affect the logger.

## 5. Dupe rule

> "You may contact each station **once on each band and mode**, for a maximum of
> **three contacts per station**, i.e. Phone, CW, and RTTY/digital–one QSO on
> each mode, per band."

→ `dupeScope: "bandMode"`, and the sponsor's "three per station" is per band.

> "New York stations that change counties are considered to be a **new station**
> and may be contacted again for points and multiplier credit."

> "No credit is awarded for cross-mode or cross-band contacts."
> "Do not remove duplicates from your log before submission. They are used for
> cross-checking other logs."

Dupes stay in the log and score zero — already the engine's behaviour.

## 6. Multipliers — in-state and out-of-state

> "**New York Stations** — Count US states (**50**), New York Counties (**62**)
> and Canadian provinces (**13**): AB, BC, MB, NB, NL, NT, NS, NU, ON, PE, QC,
> SK, YT. **Maximum of 125 multipliers.** (DX counts as QSO points but not
> multipliers.)"
>
> "**US/Canada/DX Stations** — Count New York counties for a **maximum of 62
> multipliers**."

- In-state classes: `["county", "state", "province"]` — **not** `dx`, stated
  outright. Out-of-state: `["county"]`.
- **The arithmetic closes exactly: 50 + 62 + 13 = 125.** The sponsor's own stated
  maximum, which the generator asserts. This is the cheapest and strongest
  verification available and it leaves no room for a per-band reading — 125 is a
  count of distinct entities, so `countScope: "once"` on both sides.
- Canada is the **standard 13**, listed explicitly twice (inline and in the
  document's Canadian Multiplier List appendix). No deviation.

### New York is earned via a county — stated, not inferred

> "The first valid New York county logged will count as the **multiplier for New
> York**."

→ `homeStateCountsViaCounty: true`, in the sponsor's own words, exactly as CQP
does it. And the 125 arithmetic requires it: New York is one of the 50 states,
NY stations send counties, so the token `NY` is never received and could not
otherwise be reached.

### DC

Not mentioned. The exchange is "state or Canadian province" and the multiplier
class is "US states (50)". This app accepts `DC` as a loggable token by default
and counts it with `.state`, which is left alone — but it is not something the
sponsor addresses, and no alias to `MD` is invented.

### Who may work whom

> "**New York stations:** Work as many stations inside and outside New York as
> possible."
> "**Stations outside of New York State:** Work as many New York stations and as
> many New York counties as possible."

An aim rather than a prohibition, and out-of-state multipliers are NY counties
only. **Open question**, resolved as for NJQP, IAQP, NHQP, PAQP and SDQP: ship
`outStateWorksHomeStationsOnly: true`.

## 7. Bonus stations and bonus points

**NONE.** No bonus station, no bonus points, nowhere in the 17 pages.

## 8. Final-score multipliers

**NONE.**

> "SCORING — The total score is the total number of QSO points multiplied by the
> total number of multipliers. (NY = 125, Non-NY = 62 maximum)."

Power classes (High >100 W, Low >5–100 W, QRP ≤5 W) decide the award only.

## 9. County-line / multi-county rules

> "Portable stations and stationary mobile stations may operate on a county line.
> Contacts with these stations can be used as **credit for two counties**. …
> If the portable or mobile station is operating from the intersection of **three
> or more** NY counties, **only two counties at a time may be counted for the
> same contact**."
>
> "CW and digital operators should use a "**/**" to separate county names in the
> exchange. **County line exchanges should be logged as two separate QSOs.**"
>
> "CW: "KX2NY 599 **DUT/PUT**" … sending the CW exchange with the slash between
> the counties … is important; that's how the logging software knows you're on a
> county line and gives both you and the other station credit for both counties."

→ **`maxSimultaneousCounties: 2`**, and this is one of the very few parties to
state a numeric maximum outright rather than leave it to be inferred. The
sponsor's separator is `/` and the expected behaviour is "logged as two separate
QSOs" — which is precisely what `CountyLineExpander` does with a `DUT/PUT` entry.

Only Portable and stationary Mobile stations may do it; a moving mobile changes
county instead (§5).

## 10. Valid bands

> "**All FCC allocated amateur frequencies (excluding the 30, 17, and 12 meter
> bands)** are available for QSO credit."

Exactly three exclusions, all WARC. Everything else the FCC allocates counts, and
the sponsor's sample Cabrillo file proves they mean it — it contains QSOs on
`50`, `144`, `222`, `432`, `902`, `1.2G` and `10G`.

From the app's `Band` enumeration that is **eleven bands**: 160, 80, **60**, 40,
20, 15, 10, 6, 2, 1.25 m and 70 cm — the widest list in the repo, beating PAQP
and SDQP by one.

**Two things to flag:**

- **60 m is included on a literal reading.** The rules exclude only 30, 17 and
  12 m, and 60 m is an FCC amateur allocation, so the sentence includes it. No
  other bundled party permits 60 m, and many sponsors ban it by convention, so
  this is called out in `notes` as a literal reading rather than presented as
  certain.
- **Microwave cannot be logged.** `Band` stops at 70 cm, so the 902 MHz, 1.2 GHz
  and 10 GHz contacts in the sponsor's own sample log have nowhere to go. Same
  limitation as PAQP's 630 m/2200 m, and recorded the same way rather than built
  on spec.

## 11. Categories (for Cabrillo `CATEGORY-*` headers)

Fixed: Single Op (QRP/Low/High × CW/Phone/Mixed), Multi-One (Low/High),
Multi-Multi (Low/High), School Single-Op and Multi-One (Low, Mixed, in-state
only). Mobile and Portable: Single Op, Multi-One, Multi-Multi. Overlays: Rookie
(licensed after 1 Jan 2022 for the 2025 running), Youth 12-and-under, Youth
13–17, YL.

> "For CATEGORY-OVERLAY … Only these values are valid in the Overlay field:
> Rookie, Youth12, Youth17, YL"

Self-spotting is **not** permitted except for Mobile and Portable classes.

## 12. Cabrillo `CONTEST:` header

**The sponsor publishes it — no WA7BNM fallback needed.** Both the sample header
and the full sample file read:

> `CONTEST: NY-QSO-PARTY`

The rules also specify the permitted mode tokens (`FM`, `PH`, `CW`, `RY`, `DG`;
`RY` = RTTY, `DG` = all other digital) and Cabrillo-standard band designators
including the microwave `…G` forms.

## 13. County list

**62 counties, 3-letter abbreviations**, cross-checked between the rules PDF's
table and the official CSV (§1).

The abbreviation scheme is dense with near-collisions, which makes for good spot
checks:

| Cluster | Codes |
| --- | --- |
| Chautauqua / Chemung / **Chenango** | `CHA` / `CHE` / **`CGO`** — Chenango breaks the pattern entirely |
| Columbia / Cortland | `COL` / `COR` |
| Oneida / Onondaga / Ontario | `ONE` / `ONO` / `ONT` |
| Orange / Orleans | `ORA` / `ORL` |
| **Schenectady / Schoharie / Schuyler** | `SCH` / `SCO` / `SCU` — three Sch- counties |
| Steuben / **St. Lawrence** | `STE` / **`STL`** |
| Warren / Washington / Wayne / Westchester | `WAR` / `WAS` / `WAY` / `WES` |

Plus the New York City boroughs, which are counties in their own right and none
of which is the first three letters of anything obvious: **`BRX`** Bronx,
**`KIN`** Kings (Brooklyn), **`NEW`** New York (Manhattan), **`QUE`** Queens,
**`RIC`** Richmond (Staten Island). `BRM` is Broome, upstate, and is one letter
from `BRX`.

`STL` is the only county whose name contains a period — "St. Lawrence" — which the
parser keeps.

## 14. Engine shapes to watch

1. **Digital scores 3 points, more than CW** — a first. Nothing new is needed;
   `PointsTable` already carries a digital value, and every other party either
   bans digital or pays it the same as CW.
2. **`maxSimultaneousCounties: 2` stated numerically** — "only two counties at a
   time may be counted for the same contact", with `/` as the separator and
   "logged as two separate QSOs" as the expected behaviour. The app already does
   exactly this.
3. **`homeStateCountsViaCounty: true`, stated and arithmetically required** — 50
   + 62 + 13 = 125 only closes if New York is reachable via a county.
4. **DX scores points but is never a multiplier**, for either side — the IAQP
   shape, stated outright here.
5. **Eleven valid bands including 60 m** (§10), the widest list in the repo, with
   microwave unloggable and recorded as a limitation.
6. **The sponsor publishes the Cabrillo `CONTEST:` value** — the first party where
   Article 1's WA7BNM exception is not needed at all.
7. Nothing else is new: no bonus, no score multiplier, no serial, `once` scope
   both sides. This is the second data-only party in a row.

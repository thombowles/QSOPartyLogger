# Colorado QSO Party (COQP) — 2026 Rules Research

Raw capture 2026-07-23; written up and re-verified against the live site
2026-07-24. Article 15 template.

## 1. Sponsor / sources

- Sponsor: **Grand Mesa Contesters of Colorado (GMCC)** — a host change for 2026.
  Contact `info@coloradoqsoparty.org`.
- **S1 (official rules page)**: https://www.coloradoqsoparty.org/rules/ —
  captured as `coqp_src_rules.txt` on 2026-07-23, re-fetched 2026-07-24 and
  quoted back verbatim. Titled "Colorado QSO Party 2026 Rules" and carries its
  own revision note: *"The following rules were revised as of July 15, 2026:
  Rule 7 (Entry Categories); Rule 12 (scoring mixed entries), and Rule 15
  (Awards)."* This is an explicitly dated current-year revision — the strongest
  provenance of any party so far.
- **S2 (official county abbreviations page)**:
  https://www.coloradoqsoparty.org/ (Getting Started → "Colorado County
  Abbreviations and Map") — captured as `coqp_src_counties.txt`.
- **S3 (Cabrillo name registry)**: https://www.contestcalendar.com/cabnames.php
  — "COQP", no aliases.
- Log submission: Cabrillo within 7 days, by 2026-09-19 23:59 UTC, at
  https://coqp.contesting.com.
- Note the domain: `coqp.org` does not resolve; the site is
  `coloradoqsoparty.org`.

## 2. Dates and times — no conflict

S1: *"New Schedule. Commencing with the 2026 event and moving forward, the event
will be held on the second Saturday in September each year. Date. Saturday,
September 12, 2026. Hours of Operation. 14:00 UTC Saturday through 03:59 UTC
Sunday."*

- Second Saturday of September 2026 = **Sep 12**, confirmed with `date(1)`.
- Shipped as **2026-09-12T14:00:00Z → 2026-09-13T04:00:00Z**, a 14-hour window.
  The sponsor writes the end as "through 03:59 UTC", i.e. 03:59 is the last
  countable minute and the window closes at 0400Z. `schedule` end instants are
  exclusive throughout this repo (every other party's end is a round hour), so
  0400Z is both the correct instant and the consistent representation. This is a
  formatting reading, not a rules ambiguity — nothing here contradicts anything.
- **2026 is the first year on the new date.** Prior years ran on a different
  weekend, so older third-party calendars and logger presets may disagree.

## 3. Exchange

S1: *"Colorado stations send RST plus the 3-character Colorado county
abbreviation. Stations outside Colorado send RST plus their State, Canadian
Province or Territory, or 'DX' 2-character abbreviation."*

RST is part of the exchange. DX sends the literal token → `dxStyle: token`.

## 4. QSO points by mode

S1: *"Two points are awarded for each valid QSO between a Colorado station and
any other station."* — flat 2 points, phone and CW alike. No digital exists.

## 5. Dupe rule

S1 Misc: *"Duplicate QSOs (i.e., same call, band, mode, and Colorado county) …
shall not be counted, but no additional penalty will be assessed."*

The sponsor spells out the dupe key including the Colorado county, which is
exactly `DupeChecker`'s key — so a mobile changing county is workable again with
no special handling. `dupeScope: bandMode`.

## 6. Multipliers — per MODE, and the 128 ceiling proves a rule

S1: *"Multipliers are per mode, not per band."*

- **Colorado stations**: *"One multiplier per mode is awarded for each Colorado
  county, U.S. state, Canadian province or territory, and one DX multiplier if
  any DX station is worked. **Maximum multipliers per mode: 128.**"*
- **Outside Colorado**: *"One multiplier per mode for each Colorado county
  worked. **Maximum multipliers per mode: 64.**"*

The out-of-state ceiling of 64 confirms the county count. The in-state ceiling
resolves something the prose leaves open — whether "U.S. state" means 50 or 49:

    64 counties + 50 states + 13 provinces + 1 DX = 128 ✓
    64 counties + 49 states + 13 provinces + 1 DX = 127 ✗

So Colorado **is** among the counted states. A Colorado station never receives
the token `CO` (Colorado stations send counties), so the only way to earn it is
via a Colorado county — i.e. `homeStateCountsViaCounty: true`. The arithmetic is
asserted in `gen_coqp.py` and tested end-to-end.

`DC` does not add a 51st state: S1 Misc, *"The District of Columbia counts as
Maryland."*

## 7. Bonus points

S1: *"Colorado Mobile and Portable stations shall receive a 500-point bonus for
each Colorado county activated, with at least 15 QSOs per county required to earn
the bonus."* → `activatedCountyCount: {minQSOs: 15, points: 500}`.

Note the threshold differs from TnQP's 10 — do not carry one party's number to
another.

## 8. Final-score multipliers

**NONE.** S1: *"Final score equals the total number of QSO points (not counting
any bonus points) times the total number of multipliers. Any bonus points are
then added to that product."* Power and station categories are award splits only.

Also from the July 15 revision: *"For mixed entries, QSO points and multipliers
from both modes are combined into a single total before multiplying; CW and Phone
are not scored separately. Multipliers remain per mode (Rule 10), so a county
worked on both CW and Phone counts as two multipliers."* That is precisely the
engine's existing behaviour — one combined total, `perMode` multiplier scope.

## 9. County-line / multi-county rules

S1 Misc: *"QSOs on county lines must be logged as two entries and two exchanges
should be given, one for each county."* → two counties, which is what
`CountyLineExpander` produces. `maxSimultaneousCounties: 2`.

## 10. Valid bands

S1: *"80, 40, 20, 15, 10, 6, and 2 meters."* — **no 160 m**, no WARC, no 70 cm.
Seven bands including VHF.

Suggested frequencies: CW 3555/7055/14055/21055/28055; SSB
3850/7180/14280/21380/28380; 6 m 50.125 SSB and 52.525 FM; 2 m 146.52 FM.

## 11. Categories

Every entry is Single- or Multi-Operator. In-state: Fixed (QRP/Low/High),
Mobile (Low), Portable (QRP/Low). Out-of-state: by mode and power only, not by
station type. QRP ≤5 W, Low ≤100 W, High >100 W; *"Mobile and Portable
categories may not use High Power."* Only one transmitter on the air at a time.
Spotting and self-spotting permitted.

## 12. Cabrillo `CONTEST:` header

**`COQP`** per S3. S1 requires Cabrillo but prints no header token, so this uses
the Article 1 registry exception.

## 13. County list — 64 counties, 3-letter abbreviations

From S2, generated by `gen_coqp.py`. Colorado's abbreviations are unusually
collision-prone and are the reason this list must never be hand-typed. Groups
the generator and tests both assert:

| Prefix | Abbreviations |
| --- | --- |
| `MO…` | `MON` **Montezuma**, `MOT` Montrose, `MOF` Moffat, `MOR` Morgan |
| `LA…` | `LAK` Lake, `LAP` La Plata, `LAR` Larimer, `LAA` Las Animas |
| `EL…` | `ELP` El Paso, `ELB` Elbert |
| `SA…` | `SAG` Saguache, `SAJ` San Juan, `SAM` San Miguel |
| `KI…` | `KIO` Kiowa, `KIC` Kit Carson |
| `RI…` | `RIB` Rio Blanco, `RIG` Rio Grande |
| `D…`  | `DEL` Delta, `DEN` Denver, `DOL` Dolores, `DOU` Douglas |
| `CH…` | `CHA` Chaffee, `CHE` Cheyenne, plus `CLC` Clear Creek |

`MON` is the trap worth naming: it is **Montezuma**, not Montrose. Guessing from
the name would produce Montrose and silently mis-credit a multiplier.

## 14. Engine shapes to watch

1. **`homeStateCountsViaCounty: true`**, deduced from the 128 ceiling (§6) rather
   than stated in prose. Same shape as KSQP, ALQP and IAQP.
2. **Mults per mode**, like ALQP and OhQP — a county on CW and again on phone is
   two multipliers.
3. **No 160 m**, unlike almost every other party in this repo.
4. **`activatedCountyCount` threshold is 15**, not TnQP's 10.
5. **`outStateWorksHomeStationsOnly`** — S1 Misc: *"QSOs must include at least
   one Colorado station."* Fifth consecutive party needing this field.
6. **Two-county lines**, with the sponsor explicitly requiring two logged rows.
7. Known slack: the activation bonus fires for any roving category
   (`ScoreEngine.isRovingCategory` includes rover and expedition), while COQP
   names only Mobile and Portable. COQP has no rover/expedition category, so an
   entrant would have to pick a category the party does not offer to see a
   difference. Not worth a schema field.
8. Not modeled: cross-mode/cross-band/repeater/satellite QSOs not counting, and
   the one-transmitter rule — operator discipline, not scoring inputs.

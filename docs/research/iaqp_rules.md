# Iowa QSO Party (IAQP) — 2026 Rules Research

Raw capture 2026-07-23; written up and re-verified 2026-07-24. Article 15 template.

## 1. Sponsor / sources

- Sponsor: **Story County Amateur Radio Club (W0YL)**, Ames, Iowa. Contest
  committee styled the "Iowa QSO Party High Council", chaired by Pat Rundall
  N0HR. Contact `iowaqsoparty@hotmail.com`.
- **S1 (rules page)**: https://www.w0yl.com/IAQP — captured as `iaqp_page.txt`
  on 2026-07-23, re-fetched live 2026-07-24. **Still titled "Iowa QSO Party
  2025"**, with the rules heading "Iowa QSO Party -- 2025 Rules" and a linked
  rules PDF marked "updated 12 AUG 2018". The page announces only the 2026 date:
  "Mark your calendar for next year's event on September 19, 2026."
- **S2 (official county list)**: linked from S1, captured as
  `iaqp_county_list.txt` — "IOWA QSO Party County List, Updated: 08 JUNE 2018",
  99 counties. S1: "All operators must use these abbreviations in their exchanges
  and in their logs."
- **S3 (official state/province list)**: captured as `iaqp_state_prov.txt` —
  "Updated: 12 AUG 2018".
- **S4 (Cabrillo name registry)**: https://www.contestcalendar.com/cabnames.php
  — "IAQP", no aliases.
- Log upload: https://iaqp.contesting.com/iaqpsubmitlog.php. Spotting info at
  qsopartyhub.com/iaqp-spots.php.

## 2. Dates and times

S1 announces the 2026 date directly: "**September 19, 2026**". The 2025 rules
give the pattern: "Saturday, September 20, 2025 from 9AM - 9PM US Central Time
(1400Z, September 20 - 0200Z, September 21)" — the third Saturday of September,
9AM–9PM Central.

- Sep 19 2026 is a Saturday and the third one of the month (checked with `date(1)`).
- Central in September is CDT = UTC−5, so 9AM → 1400Z and 9PM → 0200Z next day.
- **2026-09-19T14:00:00Z → 2026-09-20T02:00:00Z**, a single 12-hour window.
- Matches the State QSO Party Challenge calendar and WA7BNM.

## 3. Exchange

S1: "Iowa Stations: send RS/T and county… All Other US/Canada Stations: send RS/T
and state/province… DX Stations (outside US and Canada): send RS/T and 'DX'".
RST included; DX sends the literal token → `dxStyle: token`.

## 4. QSO points by mode

S1: "Each phone contact is worth one (1) point. Each CW contact is worth two (2)
points. Each digital mode contact is worth two (2) points. Duplicate contacts are
worth zero (0) points."

Modes: "Phone (includes digital phone) / CW / Digital (excludes digital phone but
includes other digital modes)". All three count. FT modes are allowed "as long as
the FULL Iowa QSO Party exchange is completed by BOTH parties", which S1 notes
WSJT-X cannot do; satellite QSOs are allowed, repeater and network QSOs are not.

## 5. Dupe rule

S1: "Non-Iowa stations may be worked ONCE per MODE per BAND. Iowa stations may be
worked ONCE per MODE per BAND per COUNTY. Iowa Mobile/Rover stations may work all
stations AGAIN for each county that they operate from."

The engine's dupe key already includes the received location, so the asymmetry
needs no special handling — a non-Iowa station has no county to vary, an Iowa
mobile does. `dupeScope: bandMode`.

## 6. Multipliers — once only, and Iowa counts itself

S1, with the sponsor's own emphasis:

> "Stations Outside Iowa: One multiplier for each Iowa county worked."
> "Iowa Stations: One multiplier for each Iowa county worked, and one multiplier
> for each state (**including Iowa**) or Canadian province worked."
> "Iowa Stations: **No multiplier for working DX stations.** DX stations still
> count as QSOs, so definitely DO work them!"
> "Multipliers are applied one time only, **NOT per Band, and NOT per Mode**.
> This has always been our normal scoring method, we have just added this note
> for clarification."

Three consequences:

1. `countScope: once` on both sides, stated outright rather than inferred.
2. **"including Iowa"** → `homeStateCountsViaCounty: true`. Iowa stations send a
   county and never the token `IA`, so the Iowa state multiplier can only be
   earned through an Iowa county. Same shape as KSQP, ALQP and COQP.
3. **No `dx` multiplier class for anyone.** This is the first bundled party where
   DX contacts score QSO points but can never be a multiplier — achieved by
   omitting `dx` from both class lists while keeping `dxStyle: token` so the
   token still validates.

S3 makes the state list concrete: all 50 states **including Iowa**, the 13
provinces, and — importantly — `MD` is printed as "**Maryland and DC**", so DC is
credited as Maryland. The province list uses the modern `NL` for Newfoundland,
unlike NJQP's legacy `NF`.

## 7. Bonus stations / bonus points

**NONE.** S1: "No bonus points this year" and "No Bonus Stations this year"
(the page's stale text says 2024). Club competition exists but credits clubs, not
entrants' scores.

## 8. Final-score multipliers

**NONE.** S1: "Multiply total QSO Points by the total number of Multipliers."
Power classes (QRP ≤5 W / Low 5–150 W / High >150 W) split awards only.

S1 also warns: "not all claimed scores produced by logging software are accurate.
Your official score is the number we arrive at during the scoring process."

## 9. County-line / multi-county rules — up to four, in one exchange

S1: "Iowa Mobile/Rover stations and Portable stations may park/setup on a county
line/junction and represent **all counties at the intersection simultaneously**…
Some portion of the vehicle or station must physically be in each county being
run. For example, if your antenna is in one county, the feedline passes thru a
second county, and the transmitter is in a third county, then you may claim all
three counties at the same time… **All intersecting counties may be worked in a
single exchange** (JA6DX this is W0YL, you are 59 in Story STR, Marshall MSL, and
Hardin HDN counties)."

Iowa junctions reach four counties, so `maxSimultaneousCounties: 4` — the most
permissive of any bundled party, and the reason the app supports four at all.
County-line operators "should be prepared to provide proof".

## 10. Valid bands

S1: "Contacts may be made on any amateur band EXCEPT the 60m, 30m, 17m, and 12m
bands." Suggested frequencies are tabulated for 160, 80, 40, 20, 15, 10, 6, 2,
**1.25 m** and 70 cm.

Shipped: 160, 80, 40, 20, 15, 10, 6, 2 m and 70 cm. The app has no 222 MHz band
(see §14).

## 11. Categories

Twelve classes: Iowa Single/Multi-Op Fixed, Mobile/Rover, Portable (all 5–150 W);
Out-of-State; Iowa QRP and Out-of-State QRP (≤5 W); Iowa and Out-of-State High
Power (>150 W); and DX (any legal power). "Stations are not allowed to change
their entry class once established." Spotting and self-spotting permitted.

## 12. Cabrillo `CONTEST:` header

**`IAQP`** per S4. S1 strongly prefers Cabrillo ("Did we mention your log file
should be in Cabrillo format?") and links a template, but prints no CONTEST
token, so this uses the Article 1 registry exception.

## 13. County list — 99 counties, 3-letter abbreviations

From S2. Iowa's codes cluster badly, which is exactly why they are generated:

| Cluster | Abbreviations |
| --- | --- |
| `CL…` | `CLR` Clarke, `CLA` Clay, `CLT` Clayton, `CLN` Clinton |
| `MO…`/`M…` | `MNA` Monona, `MOE` Monroe, `MTG` Montgomery, `MRN` Marion, `MSL` Marshall, `MAH` Mahaska, `MAD` Madison |
| `PO…` | `POC` Pocahontas, `POL` Polk, `POT` Pottawattamie, `POW` Poweshiek |
| `W…` | `WNB` Winnebago, `WNS` Winneshiek, `WOO` Woodbury, `WOR` Worth, `WRI` Wright |
| Not truncations | `BTL` Butler (**not** `BUT`), `HDN` Hardin, `HRS` Harrison, `BKH` Black Hawk, `BNV` Buena Vista, `CEG` Cerro Gordo, `DSM` Des Moines, `PLA` Palo Alto, `LYN` Lyon, `CRF` Crawford, `VAN` Van Buren |

`OBR` is **O'Brien** — the only bundled county name containing an apostrophe, so
the generator's name pattern has to allow one.

## 14. Engine shapes to watch

1. **No DX multiplier class at all**, while DX still scores points. First party
   with that shape; expressed by omitting `dx` from the class lists.
2. **`homeStateCountsViaCounty: true`** from "each state (including Iowa)".
3. **Four-county junctions** — the widest `maxSimultaneousCounties` in the repo,
   and the sponsor explicitly wants all of them in one exchange, which is exactly
   what `CountyLineExpander` produces as separate rows.
4. **`DC → MD`** because the sponsor's own state list prints "Maryland and DC".
5. **Multipliers once only**, stated in the rules rather than inferred from a
   stated ceiling — a welcome change from COQP and NJQP.
6. **No 222 MHz band** in this app, though IAQP permits 1.25 m and tabulates
   222.150 / 223.450. Same gap TnQP raised; recorded in the worklist.
7. **Whether out-of-state entrants may work only Iowa stations is not stated.**
   The Objective reads "Iowa stations work everybody, including other Iowa
   stations. Stations outside Iowa work as many Iowa stations as possible" — an
   aim, not a limit. Cutting the other way, the dupe rule "Non-Iowa stations may
   be worked ONCE per MODE per BAND" is *not* scoped to Iowa entrants, and this
   sponsor is demonstrably careful about the points-versus-multiplier distinction
   (it says so explicitly for DX). So the text genuinely does not settle it.

   There is a real tension with Article 1 here: setting the field `true` asserts
   a restriction the sponsor never wrote. It ships `true` anyway, for two
   reasons. Consistency — every other bundled party restricts it, five of them
   explicitly. And asymmetric visibility: if `true` is wrong, the operator sees
   **NO CREDIT** flags on legitimate contacts and will notice within minutes; if
   `false` is wrong, the score inflates silently and nobody finds out until the
   sponsor publishes results. Recorded as an open question with the sponsor's
   address so it can be settled rather than assumed.
8. Not modeled: satellite QSOs being explicitly allowed, and club competition.

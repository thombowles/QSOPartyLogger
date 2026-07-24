# Maryland-DC QSO Party 2026 — Rules Research

Researched 2026-07-23. Sponsor: Anne Arundel Radio Club (AARC), W3VPR.

## Sources

- **S1 (official rules PDF, current)**: "The Fun Contest Maryland-DC QSO Party Rules", Revised 06 AUG 2024, v.5 — https://w3vpr.org/wp/wp-content/uploads/2026/05/MDCQSOPartyRules_Revised_8-06-24_ras_v5.pdf
  - Linked as "Current Rules" from the club's current MDC QSO Party page (S2); uploaded to the club site May 2026. Byte-identical (MD5 `a0f7693c9975d4d4441bcc8c940109d8`) to the legacy copy at https://www.w3vpr.org/sites/default/files/mdcqsoparty/Documents/Maryland-DC_QSO_Party_Rules_2020-03-04.pdf. No newer revision found as of 2026-07-23.
- **S2 (sponsor event page)**: https://w3vpr.org/wp/2025/12/21/mdc-qso-party/ (Anne Arundel Radio Club, "Maryland-DC QSO Party", posted Dec 21 2025)
- **S3 (WA7BNM contest detail)**: https://www.contestcalendar.com/contestdetails.php?ref=86
- **S4 (WA7BNM Cabrillo names)**: https://www.contestcalendar.com/cabnames.php
- Legacy sponsor rules page (referenced by S2 as "www.w3vpr.org/maryland-dc_qso_party") currently returns HTTP 500 (Drupal site broken); club has migrated to w3vpr.org/wp/.

## 2026 dates/times (UTC)

- **Saturday 2026-08-08 1400Z through Sunday 2026-08-09 0400Z** (single 14-hour period; no off-time requirement stated).
- S1 §2: "This contest is conducted in a single 14-hour operating period beginning on the second Saturday in August at 1400 UTC and ending at 0400 Sunday UTC." (2nd Saturday of Aug 2026 = Aug 8.)
- S3: "1400Z, Aug 8 to 0400Z, Aug 9, 2026" (State QSO Party Challenge calendar's "0359Z" is the same window expressed inclusively).
- Log deadline, S1 §3: "Valid entries must be received within 14 days of the end of the contest."

## Exchange

- S1 §7: "You give your Call Sign and Location to each contacted station." (No RST, no serial number.)
  - MD/DC stations: "For MDC stations, use your county or city as indicated below in Table 1." (25 entities; see mdcqp_counties.tsv)
  - US/Canada non-MDC: "For Canadian and non-MDC stations, use your province or state."
  - DX: "For stations outside of Canada and the United States, use your country."

## Modes and QSO points

- **Only Phone and CW are legal modes. There are NO digital modes (no RTTY, no FT8) in this contest.**
  - S1 §6: "Modes: Only two transmitting modes are allowed. a) Phone: Any phone mode may be used. b) CW: Only International Morse Code may be used."
  - S3 lists "Modes: CW, Phone".
- Points, S1 §14a: "3 points if the contact was made in CW mode … 1 point if the contact was made using phone."
- S1 §10e: "Cross-mode contacts are prohibited."

## Dupe rule

- S1 §10f: "Stations may be worked only once per band per mode except as exempted by paragraph g. below." (i.e., same station may be worked up to twice per band: once CW, once phone.)
- Relocation exception, S1 §10g: "Stations that change their location from one MDC entity (as listed in Table 1) to another, shall be considered as a 'new' station, and may be worked again from this new location in all contest modes … Similarly non-MDC stations who change their location from one US State, Canadian Province, or country to another shall also be considered a 'new' station."
- S1 §10b: "Stations not located in the state of Maryland, or the District of Columbia may only receive credit for contacts with stations located in Maryland or the District of Columbia … Stations located in the state of Maryland or District of Columbia may work stations anywhere."
- Also void: repeaters/digipeaters/satellite/Internet (S1 §10d), net QSOs (S1 §10j). Self-spotting prohibited (S1 §12).

## Multipliers (geographic "State Multiplier")

Counted **once per entity per contest** ("initial contact") — NOT per mode and NOT per band. All entity counts are summed into a single State Multiplier.

- **MD/DC (in-state) entrants**, S1 §16: "Stations in Maryland and the District of Columbia earn one multiplier point for making initial contact with the following: a) Each Maryland County, and cities of Baltimore (BAL) and the District of Columbia (WDC) – 25 maximum. b) Each State (less Maryland) – 49 maximum. c) Each Canadian Province – 13 maximum. d) Each DXCC country except the United States of America, Canada, Hawaii, and Alaska. e) Multiplier points described in a) through d) above will be added together before being used as a multiplier."
- **Non-MDC (out-of-state) entrants**, S1 §17: "…earn one multiplier point for making initial contacts with: a) Each Maryland County, the cities of Baltimore (BAL) and the District of Columbia (WDC) – 25 maximum." (That is their only multiplier class.)
- **DC and Baltimore City are county-equivalents**: both appear in Table 1 as jurisdictions 3 (Baltimore City, BAL) and 25 (Washington DC, WDC), making 25 total MDC entities (23 MD counties + Baltimore City + DC). Baltimore County (BCT) is separate from Baltimore City (BAL).
- **No home-state-via-county rule — the opposite**: S1 §10i: "Participating stations may not count Maryland as a state they have worked. The emphasis is on working Maryland Counties, Baltimore City or Washington DC." Maryland is excluded from the state list entirely (hence "49 maximum").
- S1 §10h: "For the MDC QSO party, Alaska, and Hawaii count as States only." (Never DXCC countries; DXCC class excludes USA, Canada, Hawaii, Alaska per §16d.)
- Canadian provinces/territories list (13), S1 Table 2: NL NB NS PE QC ON MB SK AB BC NT NU YT.

## Final-score multipliers (category/power) — YES, this contest has them

Score formula, S1 §20e: "(Contact Points) x (Maximum Power Multiplier) x (Station Category Multiplier) x (State Multiplier) = (Basic Score)"; §20g: "(Basic Score) + (Bonus Points) = (Total Score)."

- **Station Category Multiplier**, S1 §15a: Club = 1, Rover = 4, Portable = 3, Mobile = 2, Fixed = 1. ("i) 1 if the Entrants Station Category is Club. ii) 4 If the Entrants Station Category is Rover. iii) 3 the Entrant's Station Category is Portable. iv) 2 If the Entrants Station Category is Mobile. v) 1 if Entrants Station Category is Fixed.")
- **Power Category Multiplier**, S1 §15b: QRP (≤5 W) = 3, Low (≤100 W) = 2, High (>100 W) = 1. "The highest power used during the QSO Party determines the power level." (S1 §5)
- Categories (choose one), S1 §4: Club, Rover, Portable, Mobile, Fixed. Rover, S1 §4b: "A MDC mobile or portable station which operates from three or more MDC contest locations as listed in Table 1 during the contest period."

## Bonus points

Scope: **all entrants** — S1 §18 heading: "Bonus Points: (MDC or non-MDC)".

- **W3VPR bonus station**: S1 §18a: "Fifty bonus points will be awarded to each station submitting a contest log with at least one confirmed contact with station W3VPR (The call sign of the Anne Arundel Radio Club). The Fifty points may be claimed on the website entry." One-time (not per band/mode): S1 §20f(i): "If you have contacted W3VPR during the contest, in any mode, you earn a one-time 50 bonus points." W3VPR is the only bonus station. (S2: "Completing at least one contact with the AARC host station, W3VPR, is worth 50 bonus points.")
- **Jurisdiction sweep bonus (tiered)**: S1 §18b: "FIVE HUNDRED bonus points will be awarded for working all 25 MDC jurisdictions … i) TWO HUNDRED-FIFTY bonus points will be awarded for working 13 of the 25 MDC jurisdictions." S1 §20f(ii): "If you worked all 25 MDC jurisdictions during the contest, you earn 500 bonus points. If you worked 13 MDC jurisdictions during the contest, you earn 250 bonus points." (Worded as tiers, either/or; rules do not state they stack.)
- Bonus is added AFTER all multipliers (see formula above).

## County-line / multi-county rules

- **No county-line provision exists** in the official rules — nothing permits transmitting from a county line and counting as two entities simultaneously. The only multi-county mechanism is relocation (S1 §10g, quoted under Dupe rule): a station that moves to a different Table-1 entity "shall be considered as a 'new' station". Rovers must activate "three or more MDC contest locations" (S1 §4b). One QSO = one location.

## Valid bands

- **160, 80, 40, 20, 15, 10 m** (HF minus WARC and 60 m).
- S1 §13: "Contacts on WARC bands, 60 meters, and VHF/UHF are not allowed." Suggested W3VPR frequencies: "CW: 3.557, 7.045, 14.045, 21.045, 28.045 / SSB: 1.895, 3.821, 7.230, 14.271, 21.371, 28.371."
- S3 lists "Bands: 160, 80, 40, 20, 15, 10m".

## Cabrillo

- **CONTEST header value: `MDC-QSO-PARTY`** — S4 (WA7BNM Cabrillo Names, contest #86: "Maryland-DC QSO Party | MDC-QSO-PARTY"). The sponsor's rules require Cabrillo but do not print the header token themselves.
- S1 §23a: "The participant's MDC QSO Party Log must be in the Cabrillo format. No handwritten logs are allowed … All entrants must use the WEBSITE ENTRY form to upload logs." Submission via sponsor web form (2024 URL pattern: w3vpr.org/QSO_Party_Submission_2024; 2026 form URL not yet published), within 14 days.

## Engine-relevant oddities (summary)

1. Power category (QRP 3 / Low 2 / High 1) and station category (Rover 4 / Portable 3 / Mobile 2 / Club-Fixed 1) are FINAL-SCORE multipliers in the score formula.
2. No digital modes at all — points table is CW=3 / Phone=1 only; FT8/RTTY are not contest modes.
3. Dupes: once per band per mode; relocated station (new Table-1 entity, or new state/province/country) is a wholly new station.
4. Geographic mults count once per contest (initial contact), never per band or mode; single summed State Multiplier.
5. Maryland may not be counted as a state; AK/HI are states-only; DXCC mults exclude USA/Canada/HI/AK; DC counts only as MDC entity WDC (not a "state").
6. Tiered sweep bonus (250 @ 13 / 500 @ 25 entities) plus one-time 50-point W3VPR bonus, all added after multiplication.
7. Non-MDC entrants score only QSOs with MDC stations; MDC entrants may work anyone.

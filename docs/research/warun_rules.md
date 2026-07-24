# 2026 Washington State Salmon Run — Rule Facts for Logger Implementation

Sponsor: Western Washington DX Club (WWDXC), club call W7DX.
Primary source (official rules, "Updated – July 22, 2024", current as of 2026-07-23):
- RULES: https://salmonrun.wwdxc.org/rules/
- COUNTY ABBREVIATIONS: https://salmonrun.wwdxc.org/wa-county-abbreviations/
- HOME (2026 dates sidebar): https://salmonrun.wwdxc.org/

## 1. 2026 Dates/Times (UTC)

Site sidebar (every page): "Salmon Run 2026: 1600Z Saturday, September 19, 2026 - 2359Z Sunday, September 20"

Rules page: "The third full (two-day) weekend of September from 1600Z (9AM PDT) Saturday through 0700Z (12AM PDT) Sunday and then from 1600Z – 2400Z (9AM-5PM PDT) Sunday. All entry classes may operate the full 23 hours of the contest."

Concrete 2026 periods:
- Period 1: 2026-09-19 16:00Z → 2026-09-20 07:00Z (15 h)
- Period 2: 2026-09-20 16:00Z → 2026-09-20 24:00Z (8 h; sidebar renders end as 2359Z)
- Total 23 h; no off-time requirement (overnight 0700Z–1600Z gap is contest-wide, not per-entrant).

## 2. Exchange

Quote (RULES → EXCHANGE):
- "Washington state stations: RS(T) and County (see Washington multiplier list)"
- "USA stations: RS(T) and State"
- "Canadian Stations: RS(T) and Canadian multipler" [sic]
- "DX stations send DXCC entity prefix"

## 3. QSO Points by Mode

Quote (RULES → QSO POINTS): "2 points for Phone / 3 points for CW"

Digital: NOT a contest mode at all. Quote (FREQUENCIES & MODES): "Contest Modes: Phone and CW. We cannot accept WJST modes (e.g. FT-8/FT-4) because they do not provide the proper exchange." [sic "WJST" = WSJT]
There is no digital/RTTY point value; digital QSOs are invalid, not merely 0-point.
Note: CW is 3 points in the current rules (older editions used 4; do not use 4).

Single-mode entries: "For single-mode entries, contacts on modes other than the mode of entry may not be counted for QSO point, multiplier, or bonus credit."

## 4. Dupe Rule

Quote: "The same station may be worked for QSO points on each band on Phone and CW."
= one QSO per station per band per mode (7 bands × 2 modes).
Quote (GENERAL RULES): "A station that changes counties may be contacted again for point and multiplier credit."

## 5. Multipliers

Quote (RULES → MULTIPLIERS):
Washington stations:
- "Washington counties (39)"  ← home-state stations DO count WA counties; WA itself is NOT a state mult
- "US States less WA (49) – District of Columbia counts as MD, Alaska and Hawaii count as states."
- "VE multipliers (13) – Canadian Provinces and Territories as defined by the Candian Multipliers List" [sic]
- "Up to 10 DXCC entities other than US and VE can be worked for multiplier credit. US and VE do not count as DX entities."
  (WA max = 39+49+13+10 = 111)

Non-Washington stations:
- "Washington counties (39 total)" — only mult type.

Counting basis (both sides): "Each multiplier may be counted ONLY ONCE regardless of mode or band"
Mobile/Expedition entrants: "Expedition and Mobile stations count multipliers ONLY ONCE and not once from each county activated" (sum QSO points across counties, single mult set, single score).

DXCC validity: "DXCC entities claimed for multiplier credit must match the entity prefix in the most current ARRL DXCC Entities List. Invalid Washington county, state, province, or DXCC entities will count for QSO credit but not multiplier credit."

## 6. Bonus Station

Quote (SPECIAL BONUS STATION): "A QSO with the sponsoring club's (Western Washington DX Club) call sign, W7DX, will add a 500-point bonus for each mode (Phone and CW). A total of 1000 points may be earned in this manner (not 500 points for each QSO on each different band). A single-mode entry (Phone and CW) may claim the 500-point bonus only once."

"Bonus points are added after all other scoring is completed (they are not multiplied by the 'multiplier'). The Special Bonus Station will count for its normal county multiplier. Contacts with the Special Bonus Stations will also earn 2 points on phone and 3 points on CW."

Summary: W7DX = normal QSO points + normal county mult + flat bonus 500/mode (per mode, NOT per band), cap 1000 mixed / 500 single-mode, added after multiplication.

## 7. Final Score Formula

Quote (SCORING): "Total = QSO points from all bands x total multipliers + Special Bonus Station bonus points"
"Mobile and Expedition classes sum QSO points from all counties before multiplying. Do not calculate separate scores from each county."
No power multiplier and no other final-score multiplier (power is an entry-class dimension only: HP >100 W, LP, QRP ≤5 W).

## 8. County-Line / Multi-County Rules

Quote (GENERAL RULES): "Contacts with stations operating from a county-line must log one QSO from each county." (i.e., a county-line station is logged as TWO QSOs, one per county.)
"County lines, whether land or water, are defined in accordance with the County Line Definition in the MARAC rules."
Wet lines: "it is not acceptable to operate from the shore of a body of water and claim a county line that runs through the body of water."
"In the case of 3-county or more intersections … only one county line consisting of two counties may be run at a time." (max 2 simultaneous counties)
Log check quote (LOGS): "Please review your Cabrillo log to ensure that county-line stations are logged as two QSOs and that abbreviations are consistent."
Expedition results: "Single-County and Multi-County (including county line) Expedition entries will be scored separately in the results."

## 9. Valid Bands

Quote: "Contest Bands: 160, 80, 40, 20, 15, 10, and 6 meters" / "No contacts on 60, 30, 17, or 12 meters are allowed"

## 10. Cabrillo

CONTEST header value: WA-SALMON-RUN — quote (LOGS): "Log review has become the most challenging part of running the WA-SALMON-RUN (our official name)."
"Cabrillo format logs are required; v3.0 preferred." "Your email address must be included in the Cabrillo file (use the Cabrillo Tag 'EMAIL: …')." Club aggregate: "Use the Cabrillo Tag 'CLUB:'".
Upload only, via SR logs page at contesting.com (linked from https://salmonrun.wwdxc.org/log-submission-2/); ADIF/paper not scored.
Deadline: "Entries MUST BE SUBMITTED ONLINE NO LATER THAN TWO WEEKS AFTER THE CLOSE OF THE SALMON RUN." (2026: by ~2026-10-04)

## 11. Entry Classes (for Cabrillo category mapping)

- SOAB: WA-SOAB / NONWA-SOAB; Mode CW, Phone, Mixed; Power HP/LP/QRP (9 classes each side)
- MOST-WA / MOST-NONWA: mixed-mode only, no power classes, permanent fixed station
- WA-CLUB-MOST / WA-CLUB-MO2T: club call, members only, mixed-mode only
- Washington Mobile (MOB): CW/Phone/Mixed, no power classes; "Non-Washington Mobiles will be classified as SOAB"
- WA County Expedition: EXP-SOST / EXP-MOST / EXP-MO2T, mixed mode only
- Unlimited (anything goes; listed separately)
- Spotting/self-spotting allowed in ALL classes.

## 12. Engine-Impact Notes (shapes a generic engine may not support)

- Bonus is per-MODE (500 × ≤2), not per-band/per-QSO; capped 1000 (500 for single-mode entries); flat add after mults.
- Multipliers count ONCE overall (not per band, not per mode) for both in-state and out-of-state.
- WA stations: DX mult type is CAPPED at 10 entities.
- DC→MD state aliasing.
- Digital is an invalid mode (reject, don't zero-score).
- CW=3/Phone=2 point ratio.
- County-line contact = two logged QSOs (each earns QSO points; both counties are mults).
- County abbreviations are mixed-length (3 and 4 chars), e.g. CLAL/CLAR, GRAN/GRAY, KITS/KITT, SKAG/SKAM.

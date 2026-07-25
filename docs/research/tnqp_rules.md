# 2026 Tennessee QSO Party (TnQP) — Rules Research

Researched 2026-07-23. Sponsor: Tennessee Contest Group (TCG). Official site: https://tnqp.org/

**Source caveat:** The rules document embedded on https://tnqp.org/rules/ is titled "Tennessee QSO Party 2025 Rules"
(DOCX at https://tnqp.org/wp-content/uploads/2025/09/Tennessee-QSO-Party-2024-Rule-Revisions-.docx, uploaded Sep 2025).
As of 2026-07-23 no 2026-specific revision is posted. All rule quotes below are from that document unless noted.
The 2026 date is confirmed by the tnqp.org home page.

## Dates / times (2026)

- **Sunday 2026-09-06 17:00 UTC through Monday 2026-09-07 03:00 UTC** (10 hours, single period, no off-time rule).
- tnqp.org home page (https://tnqp.org/): "September 6 , 2026".
- Rules doc pattern (2025 wording): "1700z Sunday, September 7 until 0300z Monday, September 8, 2025" — first Sunday of September; in 2026 that is Sep 6.
- Matches State QSO Party Challenge calendar: Sep 6 1700Z – Sep 7 0300Z 2026.

## Object / who works whom

> "Stations outside of Tennessee work as many Tennessee stations in as many Tennessee counties as possible. Stations in Tennessee work everyone."
- "Tennessee stations may work anyone"; "Outside Tennessee stations work only Tennessee stations."

## Bands

> "All amateur bands are valid, with the exception of 60, 30, 17 and 12 meters."
- I.e. 160/80/40/20/15/10/6/2 m, 1.25 m, 70 cm, etc. Suggested frequencies list VHF/UHF: 50.195, 144.195, 146.55, 223.50, 446.0.

## Modes

- Phone-SSB ("no repeater QSOs"), CW, Digital ("Any digital mode that supports the required exchange").
- Mode equivalence for dupes/credit: "All voice modes are considered phone and are therefore equivalent." "All digital modes besides CW are equivalent." CW is its own mode. So three mode groups: CW / PHONE / DIGITAL.
- "Repeater QSOs DO NOT count (this includes packet digipeaters). However, direct station-to-station packet contacts do count."

## Exchange

> "RS(T) and Tennessee County, U.S. state, Canadian province/territory, or DXCC entity."
- TN stations send RS(T) + TN county abbreviation. Others send RS(T) + state / province-territory / DXCC entity.
- Equipment location rule: "All radio equipment, including antennas, must be located within the county, state, province/territory or entity given in the exchange."
- DC note (from multiplier rule): "District of Columbia counts as Maryland."

## QSO points by mode

> "3 points per QSO regardless of mode."
- Flat 3 pts for phone, CW, and digital alike (no per-mode differentiation in TnQP).

## Dupe rule

- > "Fixed Stations may be worked once per band/mode" (mode = the three groups above).
- > "Mobiles and Rovers may be worked again if they change counties" — i.e. dupe key for mobiles/rovers is band + mode + county.
- Example given: same station on 3540 CW, 3585 RTTY, 3820 SSB = 3 valid QSOs on 80 m; but 2 m SSB then 2 m FM = dupe (both phone); 14085 RTTY then 14070 FT8 = dupe (both digital).

## Multipliers

Both in-state and out-of-state: **multipliers count per band** (NOT per mode).
- **Out-of-state:** > "Multipliers accumulate on a per band basis. Multipliers are Tennessee counties (95 max/band). For example, if you work all 95 Tennessee counties on 40M and again on 20M you earn 190 multipliers." Counties only — no states/provinces/DX mults for out-of-state entrants.
- **In-state (TN stations)**, per band:
  - Tennessee counties (95 max/band) — **yes, TN stations DO count TN counties worked** (so `county` is in the in-state class list).
    Note: this is *not* the schema's `homeStateCountsViaCounty`, which means "a home-state county also yields the home state's own
    state multiplier". TnQP says the opposite — "do not count Tennessee as a state" — so that flag stays `false` and `TN` is an
    excluded state token. (Corrected 2026-07-24; the original note here mislabelled the flag.)
  - U.S. states: "49 max/band – do not count Tennessee as a state, District of Columbia counts as Maryland".
  - Canadian provinces/territories: "13 max/band: British Columbia, Alberta, Manitoba, Saskatchewan, Ontario, Quebec, New Brunswick, Nova Scotia, Prince Edward Island, Newfoundland & Labrador, Yukon, NWT and Nunavut".
  - DXCC entities: "see ARRL DXCC list – less USA, Canada, Alaska & Hawaii — Do not count USA nor Canada as countries; Alaska & Hawaii count as states only".
- **TN mobile/rover self-activation mult:** > "Tennessee mobiles and rovers may claim one multiplier for any Tennessee county from which they complete at least 10 QSOs if they do not earn a multiplier for that county otherwise."

## Bonus station / bonus points

- > "All entrants may claim 100 bonus points for each QSO with TCG headquarters station K4TCG."
  - **2026 bonus call: K4TCG** (per the current official rules doc; also in the Cabrillo template and prior years' rules).
  - The callsign does NOT change yearly — K4TCG is the TCG club HQ station, the standing bonus call for many years (present in the 2020 Cabrillo template sample and older results). Its operating county/mobility can vary year to year.
  - "each QSO" — so 100 pts per valid K4TCG QSO (each band/mode, and each county if K4TCG is mobile), not once per log.
- TN mobiles/rovers: > "Tennessee mobile & rover operators may claim 500 bonus points for each Tennessee county from which they complete at least 10 QSOs."
- Timing: > "All bonus points are added after the geographic multiplier."
- Award note: "Bonus station K4TCG and the TCG itself are not eligible for awards."

## Final score formula / power multiplier

- **No power multiplier and no QRP bonus.** Power levels are entry-category splits only: "High:>100 watts, Low: 5-100 watts, QRP: <=5 watts".
- Final score = (QSO points × multipliers) + bonus points. (Formula implied by "All bonus points are added after the geographic multiplier.")

## Categories

- Fixed / Mobile & Rover; Single-Op / Multi-Op; High / Low / QRP; CW / SSB / Digital / Mixed.
- "All Out-of-State entries compete in the Fixed categories." "All Tennessee portable operations operating from a single location compete in the Fixed categories."
- Mobile: self-contained, capable of legal motion; motion optional; single-op mobile driver may not assist.
- Rover: vehicle-mounted and/or temporary antennas; must be stationary while operating in each county; if operating in motion, becomes Mobile.
- Spotting/self-spotting permitted for all categories.

## County-line / multi-county rules

- Mobiles/rovers may operate on county lines per MARAC County Hunter rules (https://countyhunter.com/awardmain.htm), with:
  - > "Three and four county lines may not be run simultaneously." (max 2 counties at once)
  - > "A part of the vehicle must be in each of the 2 counties simultaneously."
  - Wet county lines (bridges) allowed only if safe.
  - > "The logging software, like N1MM, must generate 2 rows in the log file, one for each county." (one QSO row per county; each row scores/dupes independently)

## Cabrillo / log submission

- **CONTEST header value: `TN-QSO-PARTY`** (from official Cabrillo template, https://tnqp.org/wp-content/uploads/2025/01/cabrillo_template.pdf, sample header line "CONTEST: TN-QSO-PARTY").
- Template QSO line: `QSO: freq mo date time call rst qth ... call rst qth` (sent RST+QTH, rcvd RST+QTH; QTH = county abbr for TN, state/prov/DX otherwise). Mobile example logs same call in two counties as separate rows (KB4NKA/M ... MONT then WILS).
- ARRL-SECTION: TN for in-state; valid section for state/province otherwise; "DX stations: enter DX." If both ARRL-SECTION: and LOCATION: present, the one appearing last is used. Station location field is "state, province or DXCC entity, NOT ARRL section".
- File name: {YOURCALL}.log. Submit online at https://tnqp.contesting.com/ (validates and emails confirmation).
- Deadline pattern: "Logs must be received by 16 September 2025" (2025 wording — ~9 days after the event; 2026 deadline not yet posted).

## Counties

- 95 Tennessee counties. Official abbreviation list (4-letter codes): https://tnqp.org/wp-content/uploads/2025/01/tnqp_county_abbreviations.pdf ("TNQP Counties List"); same list also printed in the rules DOCX. Extracted to tnqp_counties.tsv (95 lines, verified unique).
- Gotchas: Hardeman = HARD, Hardin = HARN; official list spells "Dekalb" (not DeKalb); Van Buren = VANB.

## Source URLs

- Home (2026 date): https://tnqp.org/
- Rules page: https://tnqp.org/rules/ (embeds the DOCX below via EmbedPress)
- Rules DOCX (current, titled 2025): https://tnqp.org/wp-content/uploads/2025/09/Tennessee-QSO-Party-2024-Rule-Revisions-.docx
- Resources: https://tnqp.org/resources/
- County abbreviations PDF: https://tnqp.org/wp-content/uploads/2025/01/tnqp_county_abbreviations.pdf
- Cabrillo template PDF: https://tnqp.org/wp-content/uploads/2025/01/cabrillo_template.pdf
- Log submission: https://tnqp.contesting.com/

# New Hampshire QSO Party (NHQP) — 2026 Rules Research

Researched 2026-07-23 for Mac contest logger implementation.

## Sponsor / sources
- Sponsor: Port City Amateur Radio Club (PCARC), W1WQM, Stratham NH.
- Rules page (current, "Revised August 19, 2025"): https://w1wqm.org/nh-qso-party/
- Official rules PDF (current, footer "Revised: August 25, 2025", lists 2026 dates): https://w1wqm.org/wp-content/uploads/2025/08/NHQP_Rules.pdf
- Superseded PDF (footer "Revised: June 1, 2025") — kept for diff notes below: https://w1wqm.org/wp-content/uploads/2025/06/NHQP_Rules.pdf
- Log upload: https://w1wqm.org/submit-log.php (accepts ".log or .cbr"); email alternative (older PDF): NHQP[at]w1wqm[dot]org
- Cabrillo name registry (WA7BNM): https://www.contestcalendar.com/cabnames.php

The web page text and the Aug 2025 PDF are the same revision (page says Aug 19, PDF footer Aug 25). All quotes below are from the current Aug 2025 rules unless marked otherwise.

## 2026 dates/times (UTC)
- "Contest Period: Third weekend in September. ... 2026: September 19 - 20"
- "Time: 1600 Z to 0400 Z Saturday; 1200 Z to 2200 Z Sunday. Total operating time 22 hours."
- Concretely for 2026: Sat 2026-09-19 16:00Z → Sun 2026-09-20 04:00Z, and Sun 2026-09-20 12:00Z → 22:00Z.
- Matches the State QSO Party Challenge calendar window given in the task.

## Exchange
- NH stations: "NH: RS(T) + County" — county sent as "three letter NH county abbreviation" (wording from June 2025 PDF examples; e.g. Phone "59, three letter NH county abbreviation", CW "5NN three letter NH county abbreviation").
- Non-NH US/Canada: "non-NH W/VE: RS(T) + (State/Province)"
- DX: "DX: RS(T) + \"DX\""

## QSO points by mode
- "1 Point per phone QSO"
- "2 points by CW/Digital QSO"
- Modes listed: CW, Digital, Phone.

## Dupe rule
- "Work Stations: Once per band per mode."
- So a given station may be worked up to 15 times (5 bands x 3 modes).

## Multipliers
- NH (in-state) stations: "NH Stations – one multiplier only: Each NH county, each state, each Canadian province and up to 10 DXCC country once."
  - Single combined multiplier list, each counted ONCE for the whole contest (not per band, not per mode).
  - NH stations count NH counties as multipliers, alongside states/provinces/DXCC — i.e. `county` is in the in-state class list.
    **Correction (2026-07-24):** this line originally read "Home-state-via-county: YES", which mislabels the schema flag.
    `homeStateCountsViaCounty` means "a home-state county *also* yields the home state's own state multiplier". NHQP's rule
    is "Each NH county, each state, each Canadian province and up to 10 DXCC country once" — it never says NH itself counts
    as a state, and NH stations send a county so the token `NH` is never received. There is no stated in-state maximum to
    settle it by arithmetic either, so the flag ships `false` (asserting no multiplier the sponsor did not describe). This is
    the same mislabel that appeared in `tnqp_rules.md`; `warun_rules.md` reasons it correctly ("WA itself is NOT a state mult").
  - DXCC entities are capped at 10 for NH stations ("up to 10 DXCC country").
- Non-NH (out-of-state) stations: "Non-NH Stations: Each NH county once per band. Maximum multiplier count: 50 (10 counties per band, 5 bands)"
  - Counties count PER BAND (not per mode). Theoretical max 50.
  - RULE CHANGE NOTE: the superseded June 1, 2025 PDF said "Count each NH county only once for a maximum multiplier of ten (10)." The Aug 2025 revision (which lists the 2026 dates) changed this to once per band / max 50. Use the per-band rule for 2026.
- Clauses present ONLY in the superseded June 2025 PDF, removed in the Aug 2025 revision (treat as legacy guidance, not current rule text): "Washington DC QSOs count as Maryland contacts. Maritime mobile contacts should be counted as a QSO but not as a multiplier".

## Bonus stations / bonus points
- NONE. No bonus station, no bonus points, in either the current page/PDF or the June 2025 PDF.

## Final-score multiplier
- NONE. "Score Calculation: Total score = total QSO points x total multipliers." Nothing else is applied.

## County-line / multi-county rules
- No county-line rule exists (no provision for simultaneous two-county credit from a county line).
- "A portable station may operate from one or more counties." and "A mobile station is a station that can be operated from a vehicle while in motion or while parked. All antennas are mounted on the vehicle. A mobile station may operate from one or more counties." — i.e., NH mobiles/portables may change counties during the contest (logger must support mid-contest sent-county changes), but each QSO carries a single county.

## Valid bands
- "Frequency Bands: 80 through 10 M, except WARC bands (12, 17, 30 M)" → 80, 40, 20, 15, 10 meters (5 bands; confirmed by "10 counties per band, 5 bands"). No 160 m, no VHF/UHF.
- "Suggested frequencies: CW 35 kHz up from bottom, SSB US General Band."
- "The use of repeaters is prohibited." (June 2025 PDF General Rules; dropped from Aug revision's General Rules, which retains only the comply-with-regulations rule.)

## Categories / classes (for CATEGORY headers, not multipliers)
- "Fixed Single Op, Multi Single, Multi Multi / Portable Single Op, Multi Single, Multi Multi / Mobile Single Op, Multi Single"
- Power: "High: >100 watts to legal limit; Low: ≤ 100 watts; QRP: ≤ 5 watts"
- "Use of spotting assistance and self-spotting is permitted in all categories." POTA portables counted ("provide your Park designation(s) with your log").

## Cabrillo CONTEST header
- The sponsor's rules do NOT specify a CONTEST: value; they only say "Preferred Log Submission: Cabrillo formatted log uploaded to: https://w1wqm.org/submit-log.php."
- De facto standard value per WA7BNM Cabrillo name registry (contestcalendar.com/cabnames.php): `NH-QSO-PARTY` ("New Hampshire QSO Party — NH-QSO-PARTY"). Use `CONTEST: NH-QSO-PARTY`.

## County list note
- Official 10-county abbreviation list is on rules page + PDF page 3 ("NH County (Abbreviation)"): BEL, CAR, CHE, COO, GRA, HIL, MER, ROC, STR, SUL. See nhqp_counties.tsv.
- Spelling note: current sponsor page/PDF prints "Merrimac (MER)"; the county's official name (and the sponsor's own June 2025 PDF) is "Merrimack". Abbreviation MER is unaffected.

## Engine shapes to watch (logger implementation)
- Asymmetric multiplier counting: in-state = combined list once-per-contest; out-of-state = counties once-per-band (not per mode).
- In-state DXCC multiplier cap (max 10 DXCC entities) — unusual shape.
- Dupe scope (band+mode) differs from out-of-state mult scope (band only).
- No bonuses, no final-score multiplier, no county-line simultaneous credit.

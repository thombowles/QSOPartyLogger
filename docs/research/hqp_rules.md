# Hawai'i QSO Party (HQP) — 2026 Rules Research

Researched 2026-07-24. Written to the constitution's Article 15 template.

**The README previously claimed this research was banked; it was not.** What
existed was the sponsor's multiplier map (`multmap_all.png`) with no rules
write-up. This document closes that gap.

## 1. Sponsor / sources

- Sponsor site: https://www.hawaiiqsoparty.org/ — contact `info@hawaiiqsoparty.org`
- **S1 (official rules page, current)**: https://www.hawaiiqsoparty.org/rules-page/
  — read verbatim 2026-07-24. Carries 2026 dates in rule 1, so it is the
  current-year revision. The page prints no revision number or date.
- **S2 (official multiplier map)**: https://www.hawaiiqsoparty.org/mult-map/ —
  image `https://www.hawaiiqsoparty.org/wp-content/uploads/2019/10/MultMap-1024x733.png`,
  committed as `multmap_all.png`, transcribed to `hqp_districts.tsv`. Maps
  credited to EI8IC. The rules page links here instead of printing a list, so
  this map is the *only* published source for the district abbreviations.
- **S3 (Cabrillo name registry)**: https://www.contestcalendar.com/cabnames.php
  — "HI-QSO-PARTY", no aliases.
- **S4 (State QSO Party Challenge calendar)**: `2026_state_qso_party_calendar.txt`
  — "8/22/2026 1600Z → 8/24/2026 0200Z".
- **S5 (ARRL news item)**: http://www.arrl.org/news/view/hawaii-qso-party-grid-madness-events-just-ahead
  — referenced only for the reported 2026 schedule change; not authority.
- Grid-square policy detail page: https://www.hawaiiqsoparty.org/grid-squares/
- Cabrillo detail page: https://www.hawaiiqsoparty.org/rules-page/cabrillo-log-details/
- Log upload: "HQP Log Upload Page", within 14 days (S1 rule 7).

## 2. Dates and times — ⚠️ THE SPONSOR'S RULE 1 IS SELF-CONTRADICTORY

S1 rule 1, verbatim:

> "Operating period is 36 hours from 1800 UTC Aug 22 through 0359 UTC Aug 24,
> 2026. Note: That's 6am Saturday Aug 22 to start and end at 6pm Sunday in
> Hawaii."

Hawaii is UTC−10 year-round (no DST). Checking the four claims in that sentence
against each other:

| Claim | Implication |
| --- | --- |
| "36 hours" | the window is 36 h long |
| "1800 UTC Aug 22" start | = 0800 HST Sat — **8am**, not 6am |
| "0359 UTC Aug 24" end | = 1759 HST Sun — ≈ 6pm Sunday ✓ |
| "6am Saturday … in Hawaii" | = **1600 UTC** Aug 22 |
| "6pm Sunday in Hawaii" | = **0400 UTC** Aug 24 |

- The literal UTC pair (1800Z → 0359Z) spans **33 h 59 m**, contradicting "36 hours".
- 1600Z Aug 22 → 0400Z Aug 24 spans **exactly 36 hours** and matches *both* local
  anchors — the only reading consistent with three of the sentence's four claims.
- S4's calendar gives 1600Z → 0200Z (34 h), agreeing with the 6am start but
  matching neither "36 hours" nor "6pm Sunday".

**Resolution used:** `2026-08-22T16:00:00Z` → `2026-08-24T04:00:00Z` (36 h). This
is the unique reading that satisfies the sponsor's stated duration and both of
its Hawaii-time anchors; the published "1800 UTC" is the single outlier, and
"0359 UTC" is the conventional way of printing a window that ends at 0400.
Because it is an interpretation rather than a quotation, the party ships
`verified: partial`. **Someone should email `info@hawaiiqsoparty.org` to
confirm before submitting a log.** The field is display-only in this app
(`SetupSheet`), so the risk is a misleading window, not a mis-scored log.

## 3. Exchange

S1, "Exchange":

> "Hawai'i stations send signal report plus Hawai'i Multiplier
> Non-Hawai'i stations send signal report plus State or Province as appropriate.
> Non-USA / Canada stations send 'DX'"

- RST **is** part of the exchange (unlike MDC).
- DX stations send the literal token "DX" → `dxStyle: token`.
- Grid-square alternative: "If you're mode cannot send the proper QTH name, then
  a Grid Square (4 characters) is allowed." Also under Contest Multipliers:
  "Log checking will determine the most likely multiplier and apply it to the
  final score." **Not modeled** — see §14.

## 4. QSO points by mode

S1, "Points": "SSB: 2 points   CW: 3 points   digital: 3 points"

## 5. Dupe rule

S1 rule 3: "Stations can be worked only once per band-mode (CW, SSB, digital)."
S1, "Contacts": "Each station can be worked three times per band. Once each on
CW, SSB, digital." → `dupeScope: bandMode`.

## 6. Multipliers — asymmetric scope

S1, "Contest Multipliers":

> "Non-Hawaiian stations: 14 Hawai'i districts per band. Maximum of 84 (6 bands
> x 14 districts)"
> "Hawai'i stations: 14 Hawai'i districts plus US states (including DC), plus
> Canadian provinces, plus DXCC entities. ONCE ONLY – NOT PER BAND –"

- **Out-of-state**: districts only, **per band**, ceiling 84 (= 6 × 14, which
  confirms both the district count and the band count).
- **In-state**: districts + states incl. DC + provinces + DXCC, **once for the
  whole contest**, explicitly not per band. No DXCC cap (unlike NHQP).
- No home-state-via-district provision: Hawaii stations count districts and
  states as separate classes, and no rule says a district also yields "HI".
- The "HI" state token is never sent — Hawaii stations send a district.

## 7. Bonus stations / bonus points

**NONE.** S1 has no bonus section, no bonus station, no bonus points.

## 8. Final-score multipliers

**NONE.** S1, "Score": "Final Score is the total number of QSO points times the
number of earned multipliers." Power/operator categories affect awards only.

## 9. County-line / multi-district rules

**No provision exists.** S1 says nothing about operating from a district
boundary or claiming two districts at once, and there is no mobile/rover
category. One QSO carries exactly one district →
`maxSimultaneousCounties: 1`.

## 10. Valid bands

S1 rule 2: "Stations must be worked only on the 10, 15, 20, 40, 80, and 160
meter bands." → 160, 80, 40, 20, 15, 10 m. Six bands, corroborated by the
"6 bands x 14 districts" multiplier ceiling. No WARC, no VHF/UHF, no 60 m.

Suggested frequencies (S1): CW 1815 or 30–40 kHz up from each band edge;
SSB 1845, 3850, 7230, 14250, 21300, 28450; digital per ARRL band plan.

## 11. Categories

S1, "Categories": S/O QRP (≤5 W), S/O LP (≤100 W), S/O HP (≤1500 W or legal
max), M/M LP (100 W max), M/M HP (1500 W or legal limit).

Note there is **no mobile, portable, or rover category** — consistent with §9.
Spotting networks are "permitted and encouraged" (rule 5).

## 12. Cabrillo `CONTEST:` header

**`HI-QSO-PARTY`** per S3 (WA7BNM registry, no aliases). The sponsor requires
"Cabrillo 3 format" (S1, Log Submission) but does not print the header token,
so this falls under the constitution's Article 1 exception for the registry.

## 13. District list

14 districts, 3-letter abbreviations, spread across Hawaii's 5 counties —
Honolulu County alone contributes 4. Full list in `hqp_districts.tsv`,
transcribed from S2. Note these are **districts, not counties**: `KOH`
(Kohala), `KON` (Kona), `HIL` (Hilo) and `VOL` (Volcano Park) are all within
Hawai'i County, and `PRL` (Pearl Harbor Area), `LHN` (Leeward), `WHN`
(Windward), `HON` (Honolulu) are all within Honolulu County.

Spelling note: the map prints county names with an ʻokina rendered as a
backtick ("Kaua`i County", "Hawai`i County", "O`ahu"), and district names
mostly without ("Kauai", "Molokai", "Niihau") except "Lana`i". The TSV
normalizes the backtick to a straight apostrophe and preserves the map's
district spellings otherwise.

## 14. Engine shapes to watch

1. **Asymmetric mult scope**: out-of-state per **band**, in-state **once** —
   and neither matches the dupe scope (band + mode). Same trap shape as NHQP,
   opposite direction.
2. **`outStateWorksHomeStationsOnly` applies**: S1, "Contacts" — "Hawai'i
   stations work anyone – non-Hawai'i stations work only Hawai'i". This is the
   field MDC introduced; HQP is its second user and states the rule even more
   plainly.
3. **All three mode classes are legal** — unlike ALQP/MDC, digital is a
   first-class contest mode worth 3 points, equal to CW.
4. **The multiplier entities are districts, not counties.** The schema's
   `counties` array carries them, and `countyAbbrLength` is 3. Consequence: the
   ADIF exporter writes district names into `CNTY`, which is not a real county
   name for HQP. Cabrillo (what the sponsor actually checks) is unaffected.
   Left as-is; recorded here so it is not mistaken for a data error.
5. **Grid squares as a substitute QTH** are permitted for modes that cannot
   send a name, with the sponsor's log checker resolving them to a multiplier.
   Not modeled — the app validates district abbreviations, so an operator
   logging FT8 grids would need to enter the district. Recorded as a known
   limitation, not a blocker: this app has no FT8 integration.
6. **No bonuses, no final-score multipliers, no county lines** — the scoring is
   points × mults and nothing else.
7. **The date conflict in §2** is the one thing a user could be misled by.

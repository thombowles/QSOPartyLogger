# Ohio QSO Party (OhQP) — 2026 Rules Research

Researched 2026-07-23 (raw capture), written up and re-verified 2026-07-24.
Article 15 template.

## 1. Sponsor / sources

- Sponsor: **Mad River Radio Club (MRRC)**. Contest chair Jim Stahl, K8MR.
  Contacts `info@OhQP.org`, `web@OhQP.org`.
- **S1 (official rules page)**: https://www.ohqp.org/index.php/rules/ — captured
  verbatim as `ohqp_rules_text.txt` on 2026-07-23; page re-checked 2026-07-24.
  Header reads "Next OhQP Sat 22 Aug 2026" and one rule is tagged "[New 2026]"
  (self-spotting now permitted), so this is the current-year revision. The page
  prints no revision number.
- **S2 (official multiplier list, Ohio stations)**:
  https://www.ohqp.org/index.php/official-list-of-mults-for-ohio-stations/ —
  captured as `ohqp_mults_ohio.html`. Carries the authoritative statement:
  *"To assure credit is received for a multiplier, these abbreviations must be
  used. … If conflicts exist, this list trumps all other lists."*
- **S3 (official multiplier list, non-Ohio stations)**:
  https://www.ohqp.org/index.php/official-list-of-mults-for-non-ohio-stations/
- **S4 (official Cabrillo page)**:
  https://www.ohqp.org/index.php/cabrillo-information/ — read 2026-07-24.
- **S5 (Cabrillo name registry)**: https://www.contestcalendar.com/cabnames.php
  — "MRRC-OHQP", no aliases.
- Log submission: web upload page, or paper postmarked within 30 days.

Note the URL shape: `ohqp.org/rules/` 404s; the live paths carry `/index.php/`.

## 2. Dates and times — no conflict

S1: "The Ohio QSO Party occurs on the fourth Saturday of August. The contest
period extends from 1200 EDT [noon] to 2400 EDT [midnight] (1600Z Saturday
until 0400Z Sunday). All stations may operate the full twelve hours."

- Fourth Saturday of August 2026 = **Aug 22** (Aug 1 is a Saturday).
- **2026-08-22T16:00:00Z → 2026-08-23T04:00:00Z**, a single 12-hour period.
- The sponsor gives both local and UTC, and they agree (EDT = UTC−4: noon EDT =
  1600Z, midnight EDT = 0400Z next day). The State QSO Party Challenge calendar
  says the same. Unlike HQP, nothing to reconcile.

## 3. Exchange

S1, "Exchange":
- "Ohio stations send RST and their Ohio county."
- "Non Ohio W/VE stations (including KH6/KL7) send RST and their state or
  province."
- "DX stations outside of W/VE send RST and 'DX'."

RST **is** part of the exchange. DX sends the literal token → `dxStyle: token`.
Note KH6/KL7 are W/VE for this party, so Hawaii and Alaska send state, never DX.

## 4. QSO points by mode

S1: "Each complete non-duplicate SSB contact is worth one point. Each complete
non-duplicate CW contact is worth two points."

Phone 1, CW 2. **No digital** — S1 "Bands & Modes" is "CW and SSB" only.

## 5. Dupe rule

S1: "Stations may be worked once per mode on each band; i.e. K8MAD may be worked
on both 40 CW and 40 SSB for point credit. Each station may be contacted 12
times (once per each of the 6 bands and once per mode on each band)."
→ `dupeScope: bandMode`, ceiling 12 contacts per station (6 bands × 2 modes).

Mobiles/rovers that change county (or state/province) "may be contacted again
for QSO points and multiplier credit" — the engine's dupe key already includes
the received location, so this needs no special handling.

## 6. Multipliers — per MODE, and the counts tie out exactly

S1: "Multipliers are counted once per mode, i.e. working the same multiplier on
both CW and SSB counts as two multipliers." → `countScope: perMode` on both sides.

- **Ohio stations**: "the 49 American States (excluding Ohio), 1 Washington DC,
  11 Canadian Provinces (NL, PE, NS, NB, VE2-7, NT), 88 Ohio Counties and 1 DX.
  **Total of 150 multipliers for Ohio Stations.**"
- **All other stations**: "multipliers are the 88 Ohio counties."

49 + 1 + 11 + 88 + 1 = **150** ✓. That arithmetic is asserted in `gen_ohqp.py`
and tested — it independently confirms the county count, the province count, and
that Ohio itself is excluded from the state list.

No home-state-via-county provision: Ohio counties and states are separate
classes and Ohio is struck from the state list outright.

## 7. Bonus stations / bonus points

**NONE.** S1 has no bonus section. Club competition exists but affects only
aggregate club standings, not an entrant's score.

## 8. Final-score multipliers

**NONE.** S1: "For non-mobile stations, multiply QSO points by the total number
of multipliers. For mobile/rover stations, multiply the total QSO points by the
total number of unique multipliers worked from all counties activated." Power
and operator categories affect awards only, never the score.

## 9. County-line / multi-county rules

Explicitly forbidden. S1 Misc: "**No station may claim simultaneous operation in
more than one county, state, or province.** A mobile or rover station must move
a minimum of 500 feet before claiming to be in a new county, state, or province.
The complete station (operator, transceiver, antenna, etc) must exist in a
single county/state/province." → `maxSimultaneousCounties: 1`.

## 10. Valid bands

S1: "CW and SSB on 160, 80, 40, 20, 15, and 10 meters." Six bands, corroborated
by the 12-contacts-per-station ceiling. No WARC, no 60 m, no VHF/UHF.

Suggested frequencies — CW: 1815/3545/7045/14045/21045/28045;
SSB: 1850/3825/7200/14250/21300/28450.

## 11. Categories

Single Operator (QRP ≤5 W / Low ≤100 W / High >100 W), Multi Operator,
Emergency Operations Center (EOC, Ohio only), Mobile (≤100 W), Rover (two or
more counties, ≤100 W). "All single operator entries are classified as mixed
mode." Spotting nets and — new for 2026 — self-spotting are permitted.

## 12. Cabrillo `CONTEST:` header

**`MRRC-OHQP`** per S5. The sponsor prints no CONTEST token, and S4 states
outright:

> "OhQP does NOT use Cabrillo header info as it has been found over the years to
> be incorrect. That is why we collect Call, Location, Category and Club info
> when the log file is submitted to the web upload page."

So the header value is immaterial to OhQP's own log checking; the registry value
is used under the Article 1 exception. What OhQP *is* strict about is the QSO
line, and this app already matches it:

- "Correct number of fields: 10" — Freq, Mode, Date, Time, SentCall, SentRST,
  SentQth, RcvCall, RcvRST, RcvQth ✓ (`CabrilloExporter.qsoLine`)
- "Mode is CW or PH" ✓ (`cabrilloMode` maps SSB/USB/LSB/AM → `PH`)
- "Date is yyyy-mm-dd", "Time is hhmm in UTC" ✓
- "Ohio stations must list county abbreviation and NOT OH or OHIO!" ✓ — the
  `OH` token is rejected by `excludedStateTokens`.
- S4 also says the transmitter-number field "is not permitted in OhQP entries";
  moot given headers are ignored.

## 13. County list — 88 counties, 4-letter abbreviations

From S2, the sponsor's authoritative list. Generated by `gen_ohqp.py`; never
hand-typed.

**Sponsor typos preserved in abbreviation, corrected in name** (documented, and
the generator asserts it is correcting exactly these two and no others):

| Abbr | S2 prints | Actual county |
| --- | --- | --- |
| `AUGL` | "Auglaze" | Auglaize |
| `VANW` | "VanWert" | Van Wert |

S2 also misspells two states ("Virgina" for VA, "West Virgina" for WV). Those
are state tokens, not county data, so they never enter the party file.

**⚠️ `NT` is a COMBINED entity.** S2 lists `NT = Yukon-NWT-Nu` — one multiplier
covering Yukon, Northwest Territories *and* Nunavut. Combined with S1's "11
Canadian Provinces (NL, PE, NS, NB, VE2-7, NT)", the valid province tokens are
exactly:

    NL PE NS NB QC ON MB SK AB BC NT

`YT` and `NU` are **not valid OhQP tokens** — a Yukon or Nunavut station sends
`NT`. The party file overrides `provinces` accordingly, so typing `YT` is
rejected rather than silently credited. This is faithful to S2's "these
abbreviations must be used … this list trumps all other lists."

Historical note from S2: "three abbreviations have changed starting in 2017:
Maryland-DC is now MD; Prince Edward Island is now PE; Northern Territories is
now NT." S2 accordingly still labels `MD = Maryland DC` while also listing
`DC = Washington DC` separately — both are valid, distinct multipliers.

## 14. Engine shapes to watch

1. **Mults per mode** — same shape as ALQP: working one county on CW and again
   on SSB is two multipliers. Ceiling for out-of-state entrants is 176
   (88 × 2 modes), for Ohio entrants 300 (150 × 2).
2. **Province list override to 11**, with `NT` standing for Yukon/NWT/Nunavut.
   This is the party that motivated `provinces` in the schema.
3. **`outStateWorksHomeStationsOnly` applies** — S1 Objective: "Non-Ohio
   stations may work only Ohio stations, while Ohio stations may contact
   anyone." Third consecutive party needing this field.
4. **No digital** — phone/CW only, so digital rows are invalid, not zero-point.
5. **The 150 total is a free integrity check** on county count, province count,
   and the exclusion of Ohio from the state list. Asserted in the generator.
6. **No bonuses, no final-score multipliers, no county lines.**
7. Not modeled: the 500-foot rule for mobiles claiming a new county, and the
   no-cross-mode-contacts rule — both operator discipline, not scoring inputs.

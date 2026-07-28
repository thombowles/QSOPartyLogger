# North American QSO Party, CW — official rules research

Researched 2026-07-27 for the 2026 runnings (January already past; August 1–2
upcoming). Template per constitution Article 15; reference implementation
`nhqp_rules.md`.

**NAQP is not a State QSO Party and is not on the State QSO Party Challenge's
approved list** — a logged NAQP must appear under the dashboard's
"not approved" bucket and contribute nothing to the Challenge score. That is a
requirement of this build, stated by KE5CW 2026-07-27: "they do not count in
the state qso party challenge."

## 1. Sponsor / sources

- **Sponsor:** National Contest Journal (NCJ), an ARRL publication.
- **Rules:** "Rules: 2026 North American QSO Party (CW/SSB/RTTY)", printed in
  NCJ October/November 2025 (page footers "26–28 October/November 2025 NCJ").
  One document governs all three modes.
  - PDF: <https://www.ncjweb.com/NAQP-Rules.pdf>, fetched **2026-07-27**.
  - Banked: [`naqp_rules_2026.pdf`](naqp_rules_2026.pdf) +
    [`naqp_rules_2026.txt`](naqp_rules_2026.txt) (pdftotext -layout).
- **Multiplier list:** rule 11 — "See multiplier list included with sample
  paper logs." That document is the official NAQP paper log form:
  <https://ncjweb.com/NAQP-Paper-Log-Form.pdf>, fetched **2026-07-27**, banked
  as [`naqp_paper_log_form.pdf`](naqp_paper_log_form.pdf) +
  [`naqp_paper_log_form.txt`](naqp_paper_log_form.txt). Its "Multiplier Check
  List" prints the same 47-entity country list six times, once per band.
- **Entity names:** rules 3 and 11 defer to "the ARRL DXCC List" by name, so
  the ARRL DXCC List *is* the sponsor-designated authority for what the
  country prefixes mean. Banked: "ARRL DXCC LIST CURRENT ENTITIES, January
  2026 Edition", <http://www2.arrl.org/files/file/DXCC/DXCC_Current.pdf>,
  fetched **2026-07-27**, as [`arrl_dxcc_current_2026.pdf`](arrl_dxcc_current_2026.pdf)
  + [`arrl_dxcc_current_2026.txt`](arrl_dxcc_current_2026.txt).
- **Log submission:** rule 16 — web upload only, all modes:
  <https://www.ncjweb.com/naqplogsubmit>, "no later than 7 days after the end
  of the contest" (CW August: due 0600 UTC August 9, printed in the rule 4
  table). Web-to-Cabrillo form for paper logs (CW):
  <https://www.b4h.net/cabforms/naqpcw_cab.php>.
- **Contest manager (CW):** Dave Mueller, N2NL, cwnaqpmgr@ncjweb.com.
- No revision marker is printed beyond the title year and the NCJ issue date.

## 2. Dates and times for 2026, UTC

Rule 4, quoted (CW rows):

> "CW  1800 UTC Jan 10 to 0559 UTC Jan 11  0600 UTC January 18  2nd full weekend January
>      1800 UTC Aug 1 to 0559 UTC Aug 2    0600 UTC August 9    1st full weekend August"

Rules 5A(v)/5B(v) pin the endpoint exactly: "The contest period ends at
05:59:59 UTC." Encoded with the repo's exclusive-end convention (MNQP's
"through 2359" ships as `end: 00:00:00Z`):

- **2026-01-10 18:00:00Z → 2026-01-11 06:00:00Z** (already run)
- **2026-08-01 18:00:00Z → 2026-08-02 06:00:00Z**

Formula cross-check: 2026-01-10 is the second full weekend of January
(Jan 1 was a Thursday, so Jan 3 opens the first full weekend), and 2026-08-01
is a Saturday opening August's first full weekend. Printed dates and formulas
agree; no Article 19 conflict. Single ops may operate at most 10 of the 12
hours (30-minute minimum off-times); the app does not track off-time — see
§14.

## 3. Exchange

Rule 10, quoted in full:

> "Exchange: Operator name and station location (state, province, or country)
> for North American stations; operator name only for non-North American
> stations. Each entrant is required to use a single name throughout the
> entire contest period, including multi-operator entries."

- **No RST** and **no serial** — the exchange is NAME + LOCATION, both
  directions. (`exchangeIncludesRST: false`, `exchangeIncludesName: true`.)
- There is no in-state/out-of-state asymmetry: every North American station
  sends the same shape. US stations send their state, Canadians their
  province/territory, other NA stations their country prefix.
- Non-NA stations send **name only**; rule 11 directs that they "should be
  entered as DX in the received location field."
- Hawaii is explicitly North American here — rule 3: "North American Station:
  Defined by the ARRL DXCC List, with the addition of Hawaii." A KH6 sends
  name + HI (state), not a country.

## 4. QSO points by mode

Rule 13: "Scoring: Multiply total valid contacts by the sum of the number of
multipliers worked on each band." Every valid contact is worth **one point**;
mode cannot vary it because rule 7 permits exactly one mode: "CW only in CW
parties." Points table ships 1/1/1 with `allowedModes: ["cw"]`, so a phone or
digital row in this log is invalid (no points, no mults), which is rule 7's
meaning.

Working non-NA stations: rule 11 — non-NA countries "do not count as
multipliers but may be worked for QSO credit." Rule 12: "A valid contact
consists of a complete, correctly copied and logged two-way exchange between a
North American station and any other station." So NA↔non-NA pays a point; the
non-NA end contributes no multiplier.

## 5. Dupe rule

Rule 12: "Stations may be worked once per band. Duplicate contacts on a band
will not receive credit as a valid contact." One mode exists in this contest,
so the app's `bandMode` dupe scope is exactly per-band here. The dupe key also
includes both locations, so a station logged again on a band under a
*different* received location is treated as new — the same reading every
bundled party ships for movers, and the sponsor's cross-check resolves it.

## 6. Multipliers

Rule 11, quoted in full:

> "Multipliers: Multipliers are all 50 US states, including Alaska and Hawaii,
> the District of Columbia (DC), the 13 Canadian provinces/territories
> (British Columbia, Alberta, Saskatchewan, Manitoba, Ontario, Quebec, New
> Brunswick, Nova Scotia, Prince Edward Island, Newfoundland-Labrador, Yukon,
> Northwest Territories, and Nunavut) and other North American entities as
> defined by the ARRL DXCC List. For other North American entities, please use
> the standard DXCC prefix for the country in the received location field in
> your log. See multiplier list included with sample paper logs. Multipliers
> count again on each band. Non-North American countries, maritime mobiles,
> and aeronautical mobiles do not count as multipliers but may be worked for
> QSO credit; these should be entered as DX in the received location field."

- **In-state and out-of-state are the same rule** — the party has no home
  state. Both `MultRule` sides ship identically: classes county + state +
  province, `countScope: perBand` ("Multipliers count again on each band"),
  no caps, no granted mults, `homeStateCountsViaCounty: false`.
- **DC is its own multiplier** — never aliased to MD (contrast MDC/VTQP).
  `stateAliases` is empty; the engine's accepted-state table already carries
  DC as a distinct `.state` value. 51 state-class values are possible.
- **Provinces:** the sponsor's list is the standard 13, Newfoundland-Labrador
  = `NL`. The repo default province set matches one-for-one; no override.
- **Other NA countries:** the closed 47-token list on the sponsor's own
  multiplier checklist (§13) — modeled as this party's county-class list, one
  entry per entity, counted per band like everything else.
- **Your own state counts.** Nothing excludes the entrant's own location: a
  Texas station logs TX stations and Texas is a multiplier. The party file
  must therefore override nothing into `excludedStateTokens` beyond the
  default (the pseudo-state `NA` never collides with a real token).
- **Maximum per band:** 51 states + 13 provinces + 46 shipped countries = 110
  (111 for the sponsor, who can distinguish the Dominican Republic — §13).

## 7. Bonus stations and bonus points

**NONE.** No bonus rule of any kind appears in the rules.

## 8. Final-score multipliers

**NONE.** Rule 6's power classes (QRP ≤5 W, Low 5–100 W, >100 W = check log)
are entry categories, not score factors. `scoreMultipliers` is absent.

## 9. County-line / multi-county rules

Not a county party; the exchange carries exactly one location (rule 10).
`maxSimultaneousCounties: 1`, so a `/`-joined entry is rejected. No mobile
county-change rules exist; rule 9 pins one station per call sign
("Use of multiple stations during the contest using the same call sign …
is prohibited"), and a station "may be operated remotely."

## 10. Valid bands

Rule 8: "Bands: 160, 80, 40, 20, 15, and 10 meters only, except no 160 meters
for the RTTY contest." CW keeps all six: 160/80/40/20/15/10 m. No WARC, no
VHF. Matches the paper form's six band boxes.

## 11. Categories

Rule 5: Single Operator (SO), Single Operator Assisted (SOA), Multioperator
Two-Transmitter (M2). Rule 6 power: QRP (≤5 W), Low (5–100 W); over 100 W is
reclassified as a check log ("Maximum of 100 W from the output of the final
amplifier"). Rule 14 team competition is a registration-side arrangement
("Inclusion of team information in submitted Cabrillo logs is not required").
M2 carries a 10-minute band timer (rule 5C(vi)) the app does not model — §14.

**Cabrillo `CATEGORY-*` mapping** (added 2026-07-28; header value authority
is the wwrof spec, [`cabrillo_v3_headers.md`](cabrillo_v3_headers.md)):

| Rule 5/6 entry | `CATEGORY-OPERATOR` | `CATEGORY-ASSISTED` | `CATEGORY-TRANSMITTER` |
| --- | --- | --- | --- |
| SO (5A) | `SINGLE-OP` | `NON-ASSISTED` | `ONE` |
| SOA (5B) | `SINGLE-OP` | `ASSISTED` | `ONE` |
| M2 (5C) | `MULTI-OP` | `ASSISTED` allowed (5C(ii)) | `TWO`, `OPERATORS:` lists the crew |

Power: rule 6 A/B → `CATEGORY-POWER: QRP` / `LOW`; a station "choosing to
use more than 100 W or entered as High Power" exports `HIGH` and is received
as a check log by the sponsor — the export stays honest rather than
blocking. `CATEGORY-BAND:` is always `ALL` (no single-band awards exist in
rule 19), `CATEGORY-MODE: CW`. No overlay or time categories exist. The
reference for a real accepted submission is KE5CW's January 2026 log (N1MM):
`SINGLE-OP` + `ASSISTED` + `LOW` + `ONE` — SOA, the category rule 5B
defines. The sponsor's upload form (read 2026-07-28) separately asks for
power bucket, spotting assistance, and operator count at submission time.

## 12. Cabrillo `CONTEST:` header

The rules print no header token, so per constitution Article 1's codified
exception the WA7BNM Cabrillo registry
(<https://www.contestcalendar.com/cabnames.php>, read 2026-07-27) is the
authority: entry **[218] "North American QSO Party, CW" → `NAQP-CW`**. No
alias is listed.

## 13. County list — the 47 NA entities, and what ships

The paper log form's "Multiplier Check List" prints, per band, the states,
the provinces, and this 47-token country list:

> 4U1/u 6Y 8P C6 CM CY9 CY0 FG FJ FM FO FP FS HH HI HK0 HP HR J3 J6 J7 J8
> KG4 KP1 KP2 KP4 KP5 OX PJ5 PJ7 TG TI TI9 V2 V3 V4 VP2E VP2M VP2V VP5 VP9
> XE XF4 YN YS YV0 ZF

All six per-band boxes carry the identical list; `gen_naqp.py` parses all six
and asserts they agree, then joins each token to its entity name in the ARRL
DXCC List (January 2026 edition) and asserts the mapping is total. Names are
generated, never hand-typed (Article 2).

Three tokens need a note:

- **HI (Dominican Republic) is omitted from the shipped list — 46 entities
  ship, not 47.** The sponsor's own checklist prints HI twice: in the state
  rows ("CA HI") and in the country rows (Dominican Republic, ARRL list line
  "HI# Dominican Republic NA"). One token cannot be two multipliers in this
  engine; the state table wins, so a received `HI` is always credited as
  Hawaii. Working *both* KH6 and an HI3 on one band earns 2 multipliers from
  the sponsor and 1 here — the score is a floor by at most one per band. The
  sponsor's checkers resolve the token by callsign; this app cannot
  (`caveats`: scoreAffecting, the Salmon Run's shadowing precedent).
- **4U1/u ships as `4U1`** (United Nations HQ, ARRL list "4U_UN"). The
  checklist's literal token contains "/", which the exchange field reserves
  for county-line separators, so it cannot be typed. The prefix root `4U1` is
  unambiguous in practice: the *other* 4U1 station (4U1WB, World Bank,
  Washington DC) is not this entity and sends `DC` per rule 11's state list.
- **Cuba is `CM`** on the sponsor's checklist — not `CO` — so the Colorado
  collision never arises. An operator who types `CO` for a Cuban gets
  Colorado; type what the sponsor's checklist prints.

Prefix→name joins of note, from the ARRL list as extracted: KP4 → Puerto
Rico ("KP3,4"), KP5 → Desecheo I., PJ5 → Saba & St. Eustatius ("PJ5,6"),
PJ7 → Sint Maarten, FO → Clipperton I. (the NA FO row), HK0 → San Andres &
Providencia, XF4 → Revillagigedo, YV0 → Aves I., KG4 → Guantanamo Bay,
CY9 → St. Paul I., CY0 → Sable I.

## 14. Engine shapes to watch

1. **The country list rides in `counties`** — the BCQP precedent ("nothing
   requires … the county class to be a county"): a closed, sponsor-published
   token set of the party's finest multiplier class. This buys exact-token
   validation with edit-distance suggestions, per-band counting, and a
   sidebar grid that mirrors the sponsor's own checklist. `homeState` is the
   pseudo-state `NA` (labels only; nothing real collides with it), and
   `County.state` stays nil.
2. **Non-NA = the NDQP shape:** `dxStyle: token` with `dx` in *neither*
   side's classes. `DX` is enterable, pays its point, contributes no
   multiplier — rule 11's sentence exactly. Prefix guessing stays off, so a
   mistyped token is rejected instead of minting a phantom multiplier.
3. **The exchange is a NAME — this party is why `exchangeIncludesName`
   exists.** NAQP CW and SSB are the second and third users of the name gap
   MNQP banked (worklist: "Watch for a second user"), and the Cabrillo ex1
   column is the name, so without it no NAQP log is submittable. Ships only
   after the name-exchange capability commit
   (`2026-07-27-name-exchanges-design.md`).
4. **Every entrant is out-of-state to the engine.** A US/VE entrant's setup
   is "Outside" + their state/province token; `myLoc` is that token,
   Cabrillo `LOCATION:` follows it. Both mult rules are identical, so the
   in/out classification cannot move a score. An entrant in one of the 46
   listed countries picks "Inside" and their country; their Cabrillo
   `LOCATION:` then exports as `NA` and must be hand-corrected to `DX`
   (cosmetic caveat — this app's audience is a US entrant).
5. **Not modeled, deliberately:** the SO 10-of-12-hour / 30-minute off-time
   accounting (no bundled party models operating-time caps); M2's 10-minute
   band timer (rule 5C(vi)) and its QSO invalidation; the rule 12 penalty
   arithmetic for busted calls (sponsor-side log checking); non-NA ↔ non-NA
   invalidity (a non-NA entrant logging another non-NA station would be
   over-credited — unreachable for the app's audience).
6. **Two schedule windows, six months apart** — January and August are
   separate runnings scored separately; the app's schedule array simply
   carries both 2026 windows (Article 19: target year only), and the January
   pair being past is correct data, not a defect.

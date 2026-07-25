# New Jersey QSO Party (NJQP) — 2026 Rules Research

Raw capture 2026-07-23; written up and re-verified against the live site
2026-07-24. Article 15 template.

## 1. Sponsor / sources

- Sponsor: **Burlington County Radio Club (K2TD)**. Logs to
  `NewJerseyQSOParty@gmail.com`, deadline **Oct 1**.
- **S1 (official 2026 rules)**:
  https://sites.google.com/view/k2td-bcrc/nj-qp/2026-rules — captured as
  `njqp_2026rules.txt` on 2026-07-23; re-read live 2026-07-24. Footer version
  **`2026rev0.5`**, and the page states "2026 Changes are highlighted in RED",
  so this is an explicitly versioned current-year revision.
- **S2 (official multiplier tables)**:
  https://sites.google.com/view/k2td-bcrc/nj-qp/nj-mults — the tables are
  published **only as images**. Committed as `njqp_mults_counties_provinces.png`
  and `njqp_mults_states.png`, transcribed to `njqp_counties.tsv`.
- Cabrillo help page: https://sites.google.com/view/k2td-bcrc/nj-qp/cabrillo-format
- **S3 (Cabrillo name registry)**: https://www.contestcalendar.com/cabnames.php
- Note the host: `k2td-bcrc.org` 302-redirects to `sites.google.com/view/k2td-bcrc`.

## 2. Dates and times — ⚠️ THIS RESOLVES THE WORKLIST'S DATE CONFLICT

S1, verbatim and confirmed live 2026-07-24:

> "Date: Saturday September 12, 2026
> Start Time: Sat 10:00 AM EDT (1400 UTC)
> End Time: Sat 10:00 PM EDT (0200 UTC)"

**2026-09-12T14:00:00Z → 2026-09-13T02:00:00Z**, a single 12-hour window.
(EDT = UTC−4: 10:00 EDT Sat = 1400Z Sat; 22:00 EDT Sat = 0200Z Sun. Sep 12 2026
is a Saturday, checked with `date(1)`.)

**The aggregators were wrong, including the primary one.** At worklist time the
State QSO Party Challenge calendar PDF — designated the primary calendar source
— put NJQP on **Sep 19–20**, and an initial web search agreed, while WA7BNM's
page said **Sep 12–13**. Two of three pointed at Sep 19. The sponsor says
**Sep 12**, so the majority of aggregators *and* the primary calendar were both
wrong. This is the concrete case for Article 19's rule that `schedule` comes from
the sponsor and never from a calendar: a majority vote among aggregators is not
evidence.

Consequence worth noting: NJQP and the Colorado QSO Party now sit on the **same
day**, both starting at 1400Z.

## 3. Exchange

S1: "New Jersey Stations: RS(T), 4-character county… Outside of New Jersey
Stations: RS(T), 2-character state abbreviation, Canadian province abbreviation,
or DX". RST included; DX sends the literal token → `dxStyle: token`.

## 4. QSO points by mode

S1: "each contact will score two points if a valid CW / Digital contact OR one
point if a valid phone contact." → phone 1, CW 2, **digital 2**.

Digital is explicitly a first-class mode: "Digital - Any mode capable of
completing a QSO with the NJQP exchange will be considered a valid digital
contact. No repeater or internet modes."

## 5. Dupe rule

S1: "The same station may be contacted on CW, Digital and Phone on each band."
→ `dupeScope: bandMode`. Plus "Mobile or portable stations that change geographic
area (county for NJ stations or S/P/DX for others) are considered to be a new
station and may be contacted again for QSO points and multiplier credit", which
the engine's dupe key already covers via the received location.

## 6. Multipliers — counted ONCE, and the 84 total pins the state count

S1:
> "NJ Stations: add up contacted NJ Counties (21) + States (49 not NJ) +
> Canadian Provinces (13) + DX (1) for a maximum of 84x contact multiplier."
> "Non-NJ Stations: count up contacted NJ Counties (21) for a maximum of 21x
> multiplier. Add total unique counties for contact multiplier."

    21 counties + 49 states + 13 provinces + 1 DX = 84 ✓

Neither per band nor per mode — the stated maxima equal the entity counts, so
`countScope: once`. S1's own worked examples confirm it: a non-NJ station with
26 contacts across three modes into 9 NJ counties has "Contact multiplier 9x",
and the rover example lists 11 contacts resolving to "9 unique multipliers".

**49 states means no DC.** The official states table (S2) runs Alabama→Wyoming
with **no District of Columbia row at all**, and closes with the note
"**NJ : use counties**". 50 US states − NJ = 49, exactly the stated figure, so DC
is neither a state multiplier nor a listed token. See §14 for how that is handled
and why it is an open question.

No home-state-via-county credit: NJ is struck from the state list, not earned
through a county.

## 7. Bonus points

**NONE.** S1 has no bonus station and no bonus points. (Club aggregate scoring
exists but affects only club standings, never an entrant's score.)

## 8. Final-score multipliers — YES, a power multiplier

S1: "Power Multiplier: High power = 1x, Low power = 2x, QRP = 4x… Note the power
multiplier is for the highest power used for any NJQP QSO."

S1: "Final Score = QSO score total X Contact Multiplier X Power Multiplier"

→ `scoreMultipliers.power = {HIGH: 1, LOW: 2, QRP: 4}`. No station-category
multiplier (unlike MDC). Verified against both of S1's worked examples:

- Non-NJ, low power: `39 × 9 × 2 = 702` ✓
- NJ, QRP: `23 × 14 × 4 = 1288` ✓

## 9. County-line / multi-county rules

S1: "**No station may claim simultaneous operation in more than one county,
state, or province.**" → `maxSimultaneousCounties: 1`.

NJ stations working more than one county over the day must append the county to
their call ("must append a slash and the county abbreviation to their call"),
which is a logging convention rather than a scoring input.

## 10. Valid bands

S1: "80, 40, 20, 15 and 10 meters **ONLY**." Five bands — no 160 m, no WARC, no
VHF/UHF. Self-spotting and assisted operation are both permitted.

## 11. Categories

Single Operator / Multi-Operator, each High / Low / QRP. Mobile/Rover/Portable
takes `category-station: Mobile`, Low or QRP only. Rookie overlay for operators
licensed within one year. Fixed stations must fit inside a 1000-foot circle;
remote operation inside that circle is allowed, and a remote station's location
is defined by its transmitter.

## 12. Cabrillo `CONTEST:` header

**`NJQP`** per S3. S1 requires Cabrillo ("Only electronic Cabrillo logs will be
accepted") and links its own Cabrillo help page but prints no CONTEST token, so
this uses the Article 1 registry exception.

## 13. Multiplier tables — 21 counties, and two abbreviation traps

Counties (S2, transcribed to `njqp_counties.tsv`) are 4-character and **not**
first-four-letter truncations:

| Abbr | County | Why it bites |
| --- | --- | --- |
| `CMDN` | Camden | not `CAMD` |
| `WRRN` | Warren | not `WARR` |
| `MONM` / `MORR` | Monmouth / Morris | both start `MO` |
| `HUDS` / `HUNT` | Hudson / Hunterdon | both start `HU` |

**⚠️ Newfoundland & Labrador is `NF`, not `NL`.** S2's province table reads
"Newfoundland & Labrador (VO1 / VO2) — **NF**", the legacy abbreviation. This
repo's default province set (`MultClass.canadianProvinces`) uses the modern
`NL`, so NJQP must override the list. All 13 provinces/territories count
(unlike OhQP's 11), and NJQP keeps `YT` and `NU` as separate entities (unlike
OhQP folding them into `NT`).

NJQP province tokens: `AB BC MB NB NF NS NT NU ON PE QC SK YT`

Foreign stations: a single `DX` multiplier.

## 14. Engine shapes to watch

1. **`NF` for Newfoundland.** Second party in a row to abbreviate Canada
   non-standardly, in a different direction from OhQP. The `provinces` override
   is load-bearing: without it, an NJ station working VO1 and logging `NF` would
   have the token rejected.
2. **Power-only score multiplier** — `scoreMultipliers.power` with no
   `stationCategory`, which the schema already supports (MDC uses both).
3. **DC is unrepresented by the sponsor.** Shipped as an excluded token
   (`excludedStateTokens: ["NJ", "DC"]`) so it can never inflate the multiplier
   count past the official 49/84. The cost is that an operator who works a DC
   station has no valid token to log — NJQP's tables simply have no answer for
   DC, and inventing a `DC → MD` alias would be a rule this sponsor never wrote
   (ALQP, TnQP and COQP all state that alias explicitly; NJQP does not).
   Recorded as an open question.
4. **No explicit "non-NJ works only NJ" rule.** S1's Objectives say "Contact as
   many NJ amateurs in as many NJ counties as possible. NJ stations contact as
   many amateurs in the US, Canada and the world as possible", and the live page
   contains no "only NJ" phrasing anywhere. Every other party built so far states
   the restriction outright. Shipped `outStateWorksHomeStationsOnly: true`
   because it matches the objectives, the multiplier structure (non-NJ count only
   NJ counties) and universal convention — and because when it is on, a stray
   non-NJ contact is flagged **NO CREDIT** in the log where the operator can see
   and judge it, whereas leaving it off would silently add points. Recorded as an
   open question.
5. **Mults count once**, unlike the per-mode/per-band parties either side of it
   on the calendar — do not carry COQP's `perMode` over just because they share a
   date.
6. Not modeled: the 1000-foot circle, the Rookie overlay, the call-suffix
   convention for NJ stations changing county, and club aggregate scoring.

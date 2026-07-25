# Illinois QSO Party (ILQP) — 2026 Rules Research

Researched 2026-07-24 for Mac contest logger implementation. The last party of
the 2026 season.
Written to the [Article 15](../CONSTITUTION.md#article-15--research-before-code) template.

## 1. Sponsor / sources

- Sponsor: the **Western Illinois Amateur Radio Club (WIARC)**, W9AWE, PO Box
  3132, Quincy IL 62305-3132. WIARC has run the ILQP since 2006; the Radio
  Amateur Megacycle Society (RAMS) ran it for nearly four decades before that.
  Logs to `n9jf@arrl.net`.
- ILQP page (fetched 2026-07-24): https://w9awe.org/ilqp/ — extracted to
  [`ilqp_page.txt`](ilqp_page.txt). Carries the "Sunday the third full weekend of
  October" formula and a long FAQ.
- **Official rules PDF**, 4 pages, "Announcing the **2025** Illinois QSO Party":
  `w9awe.org/download/86/2025/2064/2025-illinois-qso-party-rules` — extracted to
  [`ilqp_rules_2025.txt`](ilqp_rules_2025.txt).
- **Official county abbreviation PDF**:
  `w9awe.org/download/68/ilqp/1919/ilqp-counties-abbreviations` — extracted to
  [`ilqp_counties.txt`](ilqp_counties.txt).
- Cabrillo name registry (WA7BNM): https://www.contestcalendar.com/cabnames.php

**Retrieval note for the next session:** the rules PDF is on **page 2** of the
site's file browser, which paginates in JavaScript with no `href` on the "Next"
control, so a plain fetch of `w9awe.org/ilqp/` never reveals it. It was reached
by driving the page in a browser and clicking through. The counties PDF is on
page 1 of the Resources folder and fetches normally.

### A secondary source was wrong, and it matters

A web search reported that in ILQP "**all stations may earn one extra multiplier
for every eight QSOs made with the same Illinois county**". **That rule is not in
the sponsor's current rules** — it appears nowhere in the 2025 PDF, and the
multiplier paragraph (§6) is a plain sum with a DX cap. It is presumably a
recollection of a RAMS-era rule.

Had it been taken on trust, every ILQP score would have been inflated by a
multiplier bonus the sponsor does not award. This is
[Article 1](../CONSTITUTION.md#article-1--provenance-or-it-does-not-exist)
working exactly as intended: secondary sources are a hint about which primary
source to read, never authority.

## 2. Dates and times for 2026, in UTC

The published rules are the **2025** edition:

> "Date/Time: **1700 UTC October 19, 2025 to 0100 UTC October 20, 2025**"

and the site's own banner still reads "Next Date for the ILQP: October 19, 2025".
But the formula is printed on the same page:

> "Held Annually on **Sunday the third full weekend of October**"

October 2026's full weekends are Oct 3–4, 10–11, **17–18**, 24–25, so the third
is 17–18 and its **Sunday is 18 October 2026**. The same formula reproduces
2025's own printed date (October 2025's third full weekend was 18–19; Sunday the
19th), which is the check that the formula is being read the way the sponsor
means it.

**Ships as one 8-hour window:** `2026-10-18T17:00:00Z → 2026-10-19T01:00:00Z` —
the shortest window of any bundled party, and Sunday-only, which is unique here.

## 3. Exchange

> "Exchange: **IL stations give RS/T and county; others give RS/T and state,
> province or country**"

- RST **is** part of it → `exchangeIncludesRST: true`; no serial.
- DX sends its **country** → `dxStyle: "prefix"`, since in-state stations count
  DXCC countries as distinct multipliers (§6) and could not otherwise tell them
  apart. Same reading as SDQP.

The FAQ adds a useful gloss: "While RST is currently a required portion of the
exchange, **all RSTs will be assumed to be 59/599 by the log checkers.**"

County names may be sent in full or abbreviated: "It is quite acceptable to enter
either the complete and correctly spelled county name **or** the unique
abbreviated form". This app logs the abbreviation, which is the form the rules
call for in a submitted log.

## 4. QSO points by mode

> "Scoring: **Phone QSO: 1 point; CW/digital QSO 2 points.** No repeater QSOs."

Digital is legal and pays the same as CW — but with a carve-out:

> "Note on digital modes: NEW….NOTE!! Due to the complexity of creating a log
> entry conforming to ILQP log submission rules, **FT4 and FT8 contacts will
> receive no contact credit.** Other digital modes are encouraged."

**KNOWN LIMITATION:** `allowedModeClasses` works at the class level — phone / CW /
digital — so it cannot admit RTTY while excluding FT8, both of which are
`.digital`. Digital ships as legal and worth 2 points, and the notes state
plainly that FT4/FT8 QSOs will be logged and scored by this app but earn nothing
from the sponsor. Recorded rather than modeled; see §14.

## 5. Dupe rule

> "Stations may be worked **once per band and mode (phone and CW/digital)** and
> once per band/mode/county for IL Mobile and Rover stations."

**This is a two-way mode split, not three.** ILQP treats CW and digital as one
mode for dupe purposes, so the same station worked on CW *and* RTTY on one band
is a duplicate. This app's `ModeClass` has three cases and `dupeScope: bandMode`
keys on all three, so **it will not flag that dupe** — the second QSO shows as
valid and adds points the sponsor will remove.

Recorded as a KNOWN LIMITATION and added to the worklist's deferred engine gaps.
It affects the dupe *warning* only: multipliers here count once regardless (§6),
so no multiplier is over-credited, and the sponsor's FAQ confirms there is "no
penalty beyond loss of the QSO". See §14 for the shape a fix would take.

The mobile/rover clause — "once per band/mode/**county**" — is already the
engine's behaviour, since a different received county is a different QSO.

## 6. Multipliers — in-state and out-of-state

> "**IL stations** multiply points by the sum of IL counties, US states, VE
> provinces and DXCC countries (**maximum 5**) worked. Canada, KH6 and KL7 do not
> count as DX entities. Additional DX contacts count for points but not
> multipliers. **Non-IL stations** multiply points by the number of IL counties
> worked."

- In-state classes: `["county", "state", "province", "dx"]` with **`dxMultCap:
  5`** — a genuinely low cap that this app *can* honour, because the exchange
  carries a prefix rather than the literal token `DX`.
- Out-of-state: `["county"]` only.
- No per-band or per-mode language anywhere → `countScope: "once"` on both sides.
- "Canada, KH6 and KL7 do not count as DX entities" is consistent with the
  default handling: Canadian provinces are the `.province` class, and Hawaii and
  Alaska send `HI` and `AK`, which are states.

There is **no stated multiplier total** to check the arithmetic against — unlike
NYQP's 125 or PAQP's 67 — so the county count is verified against the sponsor's
county list alone (§13).

### Does Illinois itself count as a state multiplier?

**Not stated.** In-state multipliers include "US states", but Illinois stations
send a county, so the token `IL` is never received, and there is no in-state
maximum to settle it by arithmetic. → ships **`false`**, as for NHQP, MEQP and
SDQP, and carried as an open question. The fifth party where this pattern
applies.

### DC and Canada

Neither is enumerated. "VE provinces" with no list → the repo default of 13. No
DC rule → no alias, and `DC` remains loggable as its own token.

### Who may work whom

Nothing in the rules restricts a non-IL entrant to Illinois stations, and the
Objective is not phrased as a limit. But out-of-state multipliers are Illinois
counties only. **Open question**, resolved as for NJQP, IAQP, NHQP, PAQP, SDQP
and NYQP: ship `outStateWorksHomeStationsOnly: true`.

## 7. Bonus stations and bonus points

> "**NEW FOR 2025: BONUS STATIONS!!** The sponsoring club of ILQP is the Western
> Illinois ARC, which is authorized to use two callsigns: **W9AWE** (the
> historical call) and **W9OAB** (the call of a long-time member and benefactor).
> Both of these calls will be used during the 2025 event, and any entrant
> contacting these stations will have a **100 point bonus** added to the final
> score. **Total of 200 points possible.** W9AWE will be primarily CW, W9OAB will
> be primarily phone."

→ two `workStation` bonuses, **100 points each, scope `once`**. "Total of 200
points possible" fixes the scope: one payment per station, not per band or mode.

Unlike PAQP — whose bonus station is a different group each year and so was
omitted — these are the **sponsoring club's own two callsigns**, so they ship.
The "NEW FOR 2025" marker means they have only run once, so the notes flag them
for the same late re-check as the dates.

## 8. Final-score multipliers

**NONE.** Power classes (High >100 W, Low ≤100 W — both reduced from 200 W for
2025 — and QRP ≤5 W) and the new "Unlimited" class decide awards, not score.

Score is QSO points × multipliers, with the bonus added after — the engine's
formula.

## 9. County-line / multi-county rules

> "Contacts with/by stations at the border of **2/3/4 counties count as 2/3/4
> counties and 2/3/4 QSOs**."

→ **`maxSimultaneousCounties: 4`**, stated numerically and confirmed by the FAQ,
which discusses three- and four-county corners at length ("To claim three or four
counties, the operator should 1) As nearly as possible, locate the exact
corner…"). One exchange, one row per county — this app's behaviour exactly.

Two restrictions worth recording:

> "(NOTE: County lines established by waterways may not be activated for ILQP)."
> "Mobile entrants may operate from only one county at a time. Simultaneous
> operation from multiple counties will result in reclassification as a 'Rover'."

Neither is checkable by a logger.

## 10. Valid bands

> "Bands: **160 through 2 meters, excluding WARC bands (60, 30, 17 and 12
> meters)**"

**Eight bands:** 160, 80, 40, 20, 15, 10, 6, 2. Note two things:

- The sponsor counts **60 m among "WARC bands"**, which is not strictly correct
  — WARC is 30/17/12 — but the intent is unambiguous: 60 m is excluded. This is
  the opposite of NYQP, which includes 60 m by excluding only three bands, and
  the two together are why each party's band sentence has to be read rather than
  assumed.
- "160 **through 2 meters**" caps the list at 2 m, so unlike PAQP, SDQP and NYQP
  there is no 1.25 m or 70 cm here.

## 11. Categories (for Cabrillo `CATEGORY-*` headers)

IL Fixed High/Low; Illinois Portable (may be on a county line or corner);
Illinois Mobile (one county at a time); Illinois Rover (more than one
non-permanent location, county lines and corners permitted); Outside Illinois
High/Low; QRP as a certified overlay; and **Unlimited** (new: multiple
simultaneous signals at one site, "created as an experiment to encourage groups
to train new operators").

Power: High >100 W PEP, Low ≤100 W PEP (both "Note change…was 200 watts"), QRP
≤5 W.

> "Spotting … is encouraged. **All categories of entrants are allowed to
> self-spot.** (Change from previous years.)"

## 12. Cabrillo `CONTEST:` header

The sponsor prefers Cabrillo but does not require it — the FAQ explicitly accepts
an Excel log ("I logged in Excel. How do I create a Cabrillo file for
submission? / **You don't. Send the Excel file.**") and hand-written paper logs
with a summary sheet. It prints no `CONTEST:` token.

Under the [Article 1](../CONSTITUTION.md#article-1--provenance-or-it-does-not-exist)
codified exception, WA7BNM's registry is authority: **`IL-QSO-PARTY`**, no
aliases (fetched 2026-07-24).

## 13. County list

**102 counties**, and the abbreviations are **mixed 3 and 4 characters** — the
third party after the Salmon Run and SDQP to mix. The rules say so outright:

> "Each Illinois county has an established **4 letter abbreviation (Lee County
> excepted)**"

So **`LEE` is the only 3-letter code**, which the generator asserts.

**The rules name their own worst traps, which makes the best possible spot
checks:**

> "This often involves **White (WHIT) and Whiteside (WTSD)** counties as well as
> **Mason (MASN) and Macon (MACN)** counties."

Both pairs are asserted. That second pair also **resolves a conflict between two
sponsor documents**: the ILQP FAQ on the website says "Macon County (should be
**MCON**)", while the counties PDF and the rules PDF both say **`MACN`**. Two
documents to one, and the two that agree are the abbreviation list and the rules
themselves, so `MACN` ships. Recorded here so the FAQ's `MCON` is not mistaken
for a correction later.

Other irregular codes worth pinning: `BURO` Bureau, `CHRS` Christian, `CLRK`
Clark vs `CLAY` Clay vs `CLNT` Clinton, `DEKA` DeKalb, `DEWT` DeWitt, `DUPG`
DuPage, `EFFG` Effingham, `JODA` JoDaviess, `LASA` LaSalle, `LIVG` Livingston,
`MCPN` Macoupin, `MADN` Madison, `MSHL` Marshall, `MSSC` Massac, `MCDN`
McDonough, `ROCK` Rock Island, `SCHY` Schuyler, `STEP` Stephenson, `TAZW`
Tazewell, and **`SCLA` St. Clair** — which happens to be the same code CQP uses
for Santa Clara, in a different party.

## 14. Engine shapes to watch

1. **ILQP's mode split is two-way, not three** — "once per band and mode (phone
   and CW/digital)". This app keys dupes on three mode classes, so a CW + RTTY
   pair on one band is not flagged. **The one genuine gap this party leaves**,
   recorded in `notes` and in the worklist. A fix would be a party-level grouping
   of mode classes for dupe purposes — e.g. `dupeModeGroups: [["cw",
   "digital"]]` consulted by `DupeChecker` — and it would want a second user
   before the shape is fixed. Scoring is otherwise unaffected: multipliers count
   once regardless, and the sponsor's stated penalty is loss of the QSO only.
2. **FT4/FT8 earn no credit while other digital modes do** — a distinction below
   the granularity of `ModeClass`. Recorded, not modeled.
3. **`dxMultCap: 5`** — the lowest cap after PAQP's 1, and one this app can
   actually honour, because ILQP's DX exchange is a prefix.
4. **`maxSimultaneousCounties: 4`**, stated numerically ("2/3/4 counties and
   2/3/4 QSOs") and elaborated in the FAQ.
5. **Mixed 3/4-character abbreviations**, with `LEE` the sole 3-letter code.
6. **An 8-hour Sunday-only window** — the shortest and the only single-day
   Sunday party in the repo.
7. **Two fixed bonus stations** rather than a rotating one, so they ship (§7).
8. Otherwise data only: `once` scope both sides, no score multiplier, no serial,
   eight bands.

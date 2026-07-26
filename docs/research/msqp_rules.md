# Mississippi QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The first party in this repo that builds FT4/FT8 in on purpose** — four
parties this run bar it outright, and MSQP makes "Incorporate FT4/8 digital modes
into the event" one of its three stated objectives. That is also where its two
gaps come from.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Vicksburg Amateur Radio Club**; contest manager **Malcolm, W5XX** (`W5XX@ARRL.NET`) |
| Published via | ARRL Mississippi Section, <https://arrlmiss.org/mississippi-qso-party/> |
| **Rules** | `2026-MS-QSO-PARTY-RULES-FINAL.pdf` — header **"2026 MS QSO PARTY RULES"** |
| County list | `MSQP-Counties.pdf` — the sponsor's "County Check List" |
| Activity page | <https://msqp.eqth.net/> |
| Logs | e-mail to `W5XX@ARRL.NET`, deadline **30 April 2026** |
| Fetched | **2026-07-26** |

Banked verbatim: [`msqp_rules_2026.txt`](msqp_rules_2026.txt),
[`msqp_counties.txt`](msqp_counties.txt), [`msqp_page.txt`](msqp_page.txt).

**Retrieval note:** arrlmiss.org **404s a plain fetch of its own PDFs**. They need
a browser `User-Agent` *and* a `Referer` of the MSQP page — the fifth sponsor this
run to gate its documents that way.

## 2. Dates and times for 2026, in UTC

> "**Starts: 1400z / 4 April 2026 · Ends: 0200z / 5 April 2026 · Duration: 12
> Hours**"

| Start | End | Length |
| --- | --- | --- |
| `2026-04-04T14:00:00Z` | `2026-04-05T02:00:00Z` | 12 h |

**The cleanest date of the run**, and worth saying so after Idaho and Louisiana:
the rules print both instants *and* the duration, all three agree, and the
sponsor's separate activity page independently states *"April 4, 2026 — 9:00 am –
9:00 pm CDT"*, which is exactly 1400Z→0200Z under CDT. Nothing is derived here.

*(A web search asserted "Sunday April 05, 2026 at 1400Z to Monday April 06 at
0159Z". It is wrong on all three counts — day, date and end instant. Recorded
because it is the fourth time this run a secondary source has confidently
misdated a party.)*

MSQP shares 4 April with Louisiana, and the two overlap for their whole 12 hours.

## 3. Exchange

> "W/VE stations send **signal report and State or Province**.
> DX stations send **signal report and Country**.
> MS stations send **signal report and County**.
> **ALL FT4/8 stations send signal report and Grid Square.**"

| Role | Sends |
| --- | --- |
| **In-state (MS)** | RS(T) + one of the 82 county codes |
| **Out-of-state W/VE** | RS(T) + state or province |
| **DX** | RS(T) + **country** |
| **anyone, on FT4/FT8** | RS(T) + **grid square** |

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`,
`dxStyle: "prefix"` — DX sends a country and MS stations count DXCC entities
individually (§5).

**The FT4/8 exchange is a different exchange**, not a variant of the others: a
grid square rather than a county or a state. This app has one exchange shape per
party, so an FT4/8 QSO cannot be logged with the token the sponsor wants. See
§12.

## 4. QSO points by mode

> "QSO Points: **SSB = 1; CW = 2; RTTY = 2; FT4/8 = 2**"

| Mode | Points |
| --- | --- |
| Phone | 1 |
| CW | 2 |
| Digital (RTTY **and** FT4/8) | 2 |

Four sponsor modes collapse into three `ModeClass` cases with **no loss of points
accuracy**, because RTTY and FT4/8 pay alike — the same shape VTQP has. The
difference between them matters for *multipliers*, not points (§5).

> "Contacts: **Same station can be worked on each separate band/mode.** Example,
> W5XX can work W1AW on 20m CW, 20m SSB, 20m RTTY, 20m FT4/8."

→ `dupeScope: "bandMode"`. **Note the sponsor's own example treats RTTY and
FT4/8 as separate modes** — so this app, which collapses them, would flag the
fourth QSO in that example as a dupe. See §12.

## 5. Multipliers

> "Multipliers: (**Earned ONCE regardless of band/mode worked.**)
> — **W/VE stations** earn 1 for each MS County worked in SSB/CW/RTTY (**82
>   possible**) + 1 for each **MS Grid Square worked in FT8/4** (9 possible…
>   EM41-44 and EM50-54).
> — **DX stations** [the same].
> — **MS stations** earn 1 for each MS County worked (82 possible), 1 for each of
>   the **remaining States** worked (49 possible), 1 for each Canadian
>   Province/Territory worked (13 possible), 1 for each remaining DX
>   Country/Entity worked (336 possible) in SSB/CW/RTTY, then taking the total
>   number of **Grid Squares worked in FT8/4 and dividing by 4**… (Round up to
>   nearest whole number.)"

| | In-state (MS) | Out-of-state |
| --- | --- | --- |
| Classes | 82 counties + 49 states + 13 provinces + DXCC | **82 MS counties** |
| Scope | **once overall** | **once overall** |
| Plus, unmodelled | grid squares ÷ 4, rounded up | up to **9** MS grid squares |

→ `countScope: "once"` on both sides — stated in the heading, in parentheses,
before the list. `inState.classes = [county, state, province, dx]`;
`outState.classes = [county]`.

- **`homeStateCountsViaCounty: false`** — *"1 for each of the **remaining** States
  worked (**49** possible)"*. Forty-nine, not fifty, so Mississippi is excluded;
  the fifth party this run to say so, after MNQP, NCQP, VAQP and LAQP.
- No `stateAliases`: DC is never mentioned.
- The provinces are the standard 13, and the sponsor pins the spelling by
  reference: *"MSQP uses the standard Canadian Province/Territory abbreviations
  found at [the Wikipedia list]"*.

**The grid-square multipliers are the party's largest gap** — for an out-of-state
entrant they are up to 9 extra on a base of 82, better than a tenth of the total.
See §12.

## 6. Bonus points and final-score multipliers

**Neither.** No bonus station, no activation bonus, no power multiplier — and
*"Entry Categories: (No separate mode or power categories)"* says so explicitly.

> "Scoring: **Fixed:** Final score equals the sum of QSO points multiplied by the
> total multipliers."

That is `qsoPoints * multiplierCount` exactly.

> "**Portable/Mobile:** Final score will be the sum of the scores from **each
> County operated.**"

A per-county score aggregation — a *different scoring model* for roving entrants,
not a bonus. Not modelled; in-state mobiles and portables only. See §12.

## 7. County-line rules

**Not mentioned anywhere.** The rules contain no county-line provision at all —
neither permitting nor forbidding it — which is unusual enough to record after
five parties in a row that address it.

→ `maxSimultaneousCounties: **1**`, on the reading that **silence is not
permission**: claiming two counties from one contact is a credit the sponsor
nowhere grants, and the Portable/Mobile scoring model above ("the sum of the
scores from each County operated") reads as one county at a time. Flagged as an
open question. *(Contrast SCQP, which explicitly permits line contacts without
capping them, and where the schema default of 4 was therefore the honest choice.)*

## 8. Valid bands

> "Bands: **160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m**"

**Eight bands**, listed outright with no derivation and no exclusion clause —
the second-most explicit band statement of the run after SCQP's "only".

## 9. Categories

Seven, and **no power or mode split**: Single Operator Fixed · Single Operator
Portable · **Single Operator Mobile With Driver** · **Single Operator Mobile
Without Driver** · Unlimited Operators/Transceivers Fixed / Portable / Mobile.

The with-driver / without-driver distinction is unusual — most sponsors treat a
non-operating driver as neutral; MSQP makes it a category boundary.

Assistance: *"QSO-finding assistance (e.g., monitoring DX clusters) is allowed.
**Self-spotting or asking to be spotted is allowed by mobile/portable MS stations
ONLY.**"*

## 10. Cabrillo `CONTEST:` header

**`MS-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, fetched 2026-07-26), Article 1's
codified exception, because **the rules print no `CONTEST:` value**. They do not
even require Cabrillo: *"Hand-written legible logs will be accepted."*

## 11. County list

**82 counties, uniform 3-letter codes**, from the sponsor's County Check List.

Traps worth spot-checking — Mississippi's clusters are among the densest yet:

1. **Four `Cl-`/`Ca-` counties, none obvious:** `CAL` Calhoun, `CLA` Clay, `CLB`
   Claiborne, `CLK` Clarke. `CLA` is **Clay**, not Claiborne or Clarke.
2. **Four `La-` counties:** `LAF` Lafayette, `LAM` Lamar, `LAU` Lauderdale,
   `LAW` Lawrence.
3. **Four `Wa-` counties:** `WAL` Walthall, `WAR` Warren, `WAS` Washington,
   `WAY` Wayne.
4. **`MAR` Marshall vs `MRN` Marion** — neither is the other's naive form, and
   `MAD` Madison sits between them alphabetically.
5. **`GRN` Greene vs `GRE` Grenada** — one letter apart, and the *shorter-looking*
   code is the longer name.
6. **`JEF` Jefferson vs `JDV` Jefferson Davis** — the same pair Louisiana has
   (`JEFF`/`JFDV`), two states apart, with different codes.
7. **`PER` Perry vs `PEA` Pearl River**; `MGY` Montgomery; `NOX` Noxubee;
   `OKT` Oktibbeha; `ISS` Issaquena.
8. `DES` is **DeSoto**, one word — Louisiana prints the same name as two, `De
   Soto`. Both ship as their own sponsor prints them.

## 12. Engine shapes to watch

Three, all flowing from the party's deliberate embrace of FT4/8:

1. **GRID-SQUARE MULTIPLIERS ARE NOT MODELLED, and they are the biggest gap.**
   §5. An out-of-state entrant earns **up to 9** MS grid squares (EM41–44,
   EM50–54) on top of 82 counties — more than a tenth of the achievable total. An
   MS entrant earns *grids worked ÷ 4, rounded up*, uncapped. `MultClass` has no
   grid case and `QSO` has no grid field. **This is the same gap VTQP carries**,
   and MSQP is its second user; VTQP's is smaller (a cap of 5 out-of-state) and
   MSQP's is both larger and applies to everyone.
2. **The FT4/8 exchange is a grid square, not a location token — and a grid is
   silently accepted as a phantom DX multiplier.** §3. This app has one exchange
   shape per party, so an FT4/8 QSO cannot carry the token the sponsor asks for.
   Worse: because DX stations here send a *country prefix*, `isPlausibleDXPrefix`
   accepts any 1–5 alphanumeric token containing a letter — so `EM42` parses
   happily **as a DX prefix**, and an MS entrant who logs one is credited a DXCC
   entity that does not exist. Combined with gap 1, **FT4/8 contacts are best
   kept out of this log and scored by hand** — the reverse of the advice four
   other parties needed, where FT8 was barred outright. *(Found by a test written
   to assert the grid would be rejected. It is not.)*
3. **RTTY and FT4/8 are separate modes to the sponsor and one `ModeClass` here.**
   §4. The sponsor's own worked example — *"W5XX can work W1AW on 20m CW, 20m SSB,
   20m RTTY, 20m FT4/8"* — has four QSOs where this app sees three and flags the
   fourth as a dupe. **VTQP wants the identical split**, so this is the second
   party asking for a *finer* mode partition, against ILQP's and LAQP's two
   requests for a coarser one. Four data points now, all pointing at the same
   party-supplied partition the worklist already sketches.

Plus one that is not about FT4/8:

4. **`Portable/Mobile: Final score will be the sum of the scores from each County
   operated`** is a different scoring model, not a bonus — `ScoreEngine` computes
   one score for the log. In-state mobiles and portables only.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| SSB 1, CW 2, RTTY/FT4-8 2 | `points` |
| "each separate band/mode" | `dupeScope: "bandMode"` |
| "Earned ONCE regardless of band/mode" | `countScope: "once"`, both sides |
| "the remaining States (49 possible)" | `homeStateCountsViaCounty: false` |
| "DX stations send … Country" | `dxStyle: "prefix"` |
| 160/80/40/20/15/10/6/2 | `validBands` |
| no bonuses, no power categories | `bonuses: []`, `scoreMultipliers` absent |

**`outStateWorksHomeStationsOnly` is inferred, not stated** — the objectives point
that way (*"Encourage amateurs around the world to contact as many MS stations as
possible"*) and W/VE multipliers are MS counties only, but no sentence forbids
credit for a non-MS contact. Shipped **on**, as for the six other parties that
only imply it, so a stray contact is visibly flagged NO CREDIT rather than
silently scored. Recorded as an open question.

# Georgia QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**159 counties — the second-largest county list in the app**, behind Texas's
254 and ahead of Virginia's 133. Georgia has more counties than any state but
Texas, and unlike some sponsors this one lists every one of them.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **South East Contest Club** and **Southeastern DX Club** (co-sponsors), <https://gaqsoparty.com> |
| **Rules** | <https://gaqsoparty.com/georgia-qso-party-rules/> |
| Dates | the sponsor's own home page, <https://gaqsoparty.com/> |
| **County list** | <https://gaqsoparty.com/county-list/> — the live HTML table |
| County cross-check | <https://gaqsoparty.com/images/GQP/GQPCounties.pdf> — the county page's own "printer-friendly copy", `Last-Modified: 2017-01-18` |
| Fetched | **2026-07-26** |

Banked verbatim: [`gaqp_rules_2026.txt`](gaqp_rules_2026.txt),
[`gaqp_home_2026.txt`](gaqp_home_2026.txt),
[`gaqp_counties_2026.tsv`](gaqp_counties_2026.tsv),
[`gaqp_counties_printable_2017.txt`](gaqp_counties_printable_2017.txt).

**Everything here is first-party.** No PDF hunting, no Wayback, no calendar
inference — a rare and welcome shape after Minnesota, Oklahoma and Louisiana.
The one nine-year-old document is used only as a second opinion on the county
list, never as authority; the live table wins any disagreement.

## 2. Dates and times for 2026, in UTC

> "The Georgia QSO Party is held annually the **2nd full weekend of April**.
> There are two operating periods: **1800Z** (2:00 pm EDST) Saturday until
> **0359Z** (11:59 pm EDST) and Sunday and **1400Z** (10:00 am EDST) to
> **2359Z**. (7:59 pm EDST)"

and, on the home page, as a plain statement of fact rather than a formula:

> "The **2026 Dates were April 11th – April 12th**."

| Start | End | Length |
| --- | --- | --- |
| `2026-04-11T18:00:00Z` | `2026-04-12T04:00:00Z` | 10 h |
| `2026-04-12T14:00:00Z` | `2026-04-13T00:00:00Z` | 10 h |

**20 hours in two 10-hour legs.** April 2026 begins on a Wednesday, so the
first *full* weekend is the 4th–5th and the second is the 11th–12th — the
formula and the sponsor's stated dates agree, which is not something the last
two parties managed (Missouri moved off its formula for Easter; Louisiana's
rules still printed 2025). The independent
[`2026_state_qso_party_calendar.txt`](2026_state_qso_party_calendar.txt) carries
both legs to the minute.

GQP shares 11 April with Missouri and New Mexico and starts four hours after
both — **three parties on one Saturday**, the busiest day of the season.

## 3. Exchange

> "**GEORGIA stations** — Send signal report and GA county abbreviation…
> **NON-GEORGIA US stations** — Send signal report and STATE (U.S.P.S.
> abbreviation)… **CANADA** — Send signal report and Canadian PROVINCE (ARRL
> Zone abbreviation)… **DX** — Send signal report and "**DX**"."

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`,
`dxStyle: "token"` — the sponsor names the literal token in the rule itself,
so there is nothing to infer.

## 4. Modes — no digital

> "NOTE: **Digital contacts aren't allowed in the Georgia QSO Party.**"
>
> "MODE CATEGORIES — Mixed: CW and SSB · SSB: Phone only contacts · CW: CW only
> contacts"
>
> "**No cross mode contacts allowed.** No partial contact credit."

→ `allowedModes: ["phone", "cw"]`. The thirteenth bundled party to exclude
digital, and one of the few that says so in a single unambiguous sentence
rather than leaving it to be read out of a category table.

## 5. QSO points

> "Each completed **SSB** contact counts **one** point. Each completed **CW**
> contact counts **two** points."

## 6. Multipliers — per mode, and the sponsor does the arithmetic

> "Stations may be worked **once per band and mode** for QSO Points… **Each
> multiplier may be counted once per mode. (Not per band.)**"

→ `dupeScope: "bandMode"`, `countScope: "perMode"` on both sides. Note the
deliberate asymmetry — **QSO credit is per band and mode, multiplier credit is
per mode only.** The parenthesis exists because that trips people up.

> "**Multipliers – Georgia Stations**
> Each USA State and DC, **including Georgia (51)**
> Each Canadian Province (13)
> **DX counts for QSO points only, there are no country multipliers.**
> **128 possible multipliers.** (once on CW and once on SSB)
>
> **Multipliers – Non-Georgia Stations**
> Each Georgia county (159)
> **318 possible multipliers.** (once on CW and once on SSB)"

| | In-state (GA) | Out-of-state |
| --- | --- | --- |
| Classes | 51 states+DC + 13 provinces, **no DX** | **159 GA counties** |
| Scope | **per mode** | **per mode** |
| Sponsor's ceiling | **128** = (51 + 13) × 2 | **318** = 159 × 2 |

**Both ceilings are checkable arithmetic and both check out**, which makes them
the cheapest possible verification of the county count and the class lists at
once. The generator asserts both.

- **`homeStateCountsViaCounty: true`** — *"including Georgia (51)"*. Fifty-one
  is 50 states plus DC, so Georgia is inside the 51; and Georgia stations send
  a county, so the token `GA` is never received.
- **DC is its own multiplier, not an alias.** 51 = 50 + DC. No `stateAliases`;
  this is the opposite of New Mexico's DC→MD one party earlier, and the
  arithmetic is what distinguishes them.
- **DX is worth points and nothing else** for a Georgia entrant — stated
  outright. North Dakota, the next party built and the same weekend on the
  calendar, turned out to do the same, so this shape has two users rather than
  the one claimed when Georgia shipped. Modelled by leaving `dx` out of `classes`: the engine scores
  every in-scope row for points and consults `classes` only for multipliers.

## 7. Out-of-state credit

> "For radio amateurs **OUTSIDE** of the state of Georgia to make contacts with
> as many SSB and/or CW **Georgia** stations… Amateurs **INSIDE** the state of
> Georgia can make contacts with **everyone**."
>
> "**Stations outside Georgia may not count contacts with non-Georgia or DX
> stations.**"

→ `outStateWorksHomeStationsOnly: true`, stated twice and in both directions.

## 8. Rovers and county lines

> "GEORGIA **ROVER** stations may be worked **once per county, per mode, per
> band** for QSO Points… Rovers that move to a new county can work everyone
> again."

Already the behaviour of `DupeChecker`, which keys on `theirLoc`.

> "Rover stations are allowed to stop and operate from **county lines**. **See
> the County Hunter rules for guidance.**"
>
> "It's suggested the ROVER and PORTABLE stations send their call sign followed
> by a "/" and the Georgia County Abbreviation. For example **KU8E/HARR** …
> **KU8E/HARR/MUSC** if operating from the Harris/Muscogee county line."

**The sponsor states no maximum.** It defers to MARAC's county-hunter rules,
whose allowance is what `maxSimultaneousCounties: 4` was written for, and its
own worked example shows two. Shipping the schema default of **4** is the
choice that never rejects a legal exchange mid-contest; shipping 2 would risk
refusing something the sponsor permits. **OPEN QUESTION** — see §13.

Note also what the sponsor asks of *the other* station:

> "NON-GEORGIA US stations… Note: Please make sure you **log GA county line
> QSO's as two separate contacts**."

That is this app's behaviour already: `CountyLineExpander` turns one keystroke
into two logged rows.

## 9. Bands

The rules give **suggested frequencies** and no band list:

> "SSB: 1.865, 3.810, 7.190, 14.250, 21.300, 28.450, 50.135.
> CW: 1.815, 3.545, 7.045, 14.045, 21.045, 28.045, 50.095."

→ 160, 80, 40, 20, 15, 10 and **6** metres — seven bands. **This is inference
from a suggested-frequency list, not a stated rule**, which is why it is an
**OPEN QUESTION** (§13). It costs less than it looks: multipliers here are
counted *per mode, not per band*, so the band list cannot change anyone's
multiplier total, only which rows the app will accept.

## 10. Categories

Single Operator (Mixed / SSB / CW) · Multi-Op Single Transmitter · Multi-Op Two
Transmitters (two bands or modes, never two of the same mode) · **ROVER**
(Georgia only, single- or multi-op, and a separate Multi-2 rover) · **Portable**
(Georgia only, temporary antenna — a mobile antenna on a car makes you a Rover).
Power: QRP 5 W CW / 10 W SSB, Low ≤150 W, High >150 W.

**No score multiplier by power or station** — the categories partition the
entrants, they do not scale the score:

> "**Final Score** — Multiply total QSO points by total multipliers."

→ no `scoreMultipliers`, no `categoryFactor`. Nothing to defer.

## 11. Bonus points

**None.** The word does not appear in the rules. There are plaques and there
are North Fulton ARL special-event stations, but no rule pays points for them.

## 12. Cabrillo `CONTEST:` header

**`GA-QSO-PARTY` — printed by the sponsor** in a Cabrillo specification written
for logging-program authors, which is about as first-party as this gets:

```
CONTEST: GA-QSO-PARTY
QSO: 14000 CW 2016-04-09 1805 KU8E 599 HARR AA3B 599 PA
```

Article 1's WA7BNM exception is not needed.

## 13. Open questions

1. **The band list is inferred from suggested frequencies.** §9. The rules
   never say which bands are legal, only where activity will be. 160–10 m plus
   6 m ships. WARC exclusion is the universal contest convention but is not
   written here, and 2 m is neither listed nor forbidden. *Impact is limited to
   row acceptance: multipliers are per mode, so no band list can change a
   score.*
2. **No stated maximum for simultaneous counties.** §8. The default 4 ships,
   following the MARAC reference; the sponsor's own example shows 2.

Both are recorded in the party's `notes` and re-checked in the late
re-verification pass.

## 14. Engine shapes to watch

**Nothing new is needed and nothing is deferred** — the first party of this run
that asks for no engine work at all:

| Rule | Field |
| --- | --- |
| SSB 1, CW 2 | `points` |
| "Digital contacts aren't allowed" | `allowedModes: ["phone", "cw"]` |
| "once per band and mode for QSO Points" | `dupeScope: "bandMode"` |
| "once per mode. (Not per band)" | **`countScope: "perMode"`, both sides** |
| "including Georgia (51)" | `homeStateCountsViaCounty: true` |
| "DX counts for QSO points only" | **`dx` omitted from in-state `classes`** |
| "may not count contacts with non-Georgia or DX" | `outStateWorksHomeStationsOnly: true` |
| county lines, no stated max | `maxSimultaneousCounties: 4` (default) |
| two 10-hour legs | `schedule` |

The one thing worth naming is the **DX-points-but-no-multiplier** shape, which
needed no new field only because the engine already separates the two: points
are scored for every in-scope row, and `classes` is consulted for multipliers
alone. Georgia is the first party to exercise that separation deliberately.

## 15. County list

**159 counties** — more than any state but Texas, and the sponsor states the
number twice, in the Objective and in the multiplier table.

Codes are four letters, **with one exception**: `LEE` for Lee, which has only
three letters to work with.

**The trap is `CHAT`, and it is New Mexico's `SAN` all over again** — the
obvious code belongs to the county nobody would guess:

| Code | County |
| --- | --- |
| **`CHAT`** | **Chattahoochee** — *not* Chatham, which is `CHTM` |
| `CHTM` | Chatham — Savannah, one of the best-known counties in the state |
| `CHGA` | Chattooga |
| `CHAR` | Charlton |

Four `Cha…` counties, and the shortest, most familiar name gets the least
obvious code. The generator asserts all four by name.

The other confusable groups, listed by the generator itself so the list cannot
go stale — five sets of codes separated only by a fourth letter:

| | |
| --- | --- |
| `HARA` Haralson · `HARR` Harris · `HART` Hart | the only **three**-way group, and `HARR` is the county in the sponsor's own county-line example |
| `BARR` Barrow · `BART` Bartow | |
| `COLQ` Colquitt · `COLU` Columbia | |
| `WARE` Ware · `WARR` Warren | |
| `CHAR` Charlton · `CHAT` Chattahoochee | see above |

Two counties are named for a Jefferson and do **not** collide: `JEFF`
Jefferson, `JFDA` **Jeff Davis**. The two `Mc` counties do not collide either
(`MCDU` McDuffie, `MCIN` McIntosh).

Both sources are parsed independently and required to agree. They do, on all
159 — nine years apart, by two different parsers.

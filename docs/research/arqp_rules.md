# Arkansas QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The rule that looked unmodellable turned out to be exact**, and the DX cap
that every other party's is unreachable actually binds here. §5 and §6.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **The Noise Blankers Radio Group**, <https://arkqp.com> |
| **Rules** | <https://arkqp.com/arkansas-qso-party-rules/> — carries a "New for 2026" bonus |
| **County list** | `…/Arkansas-County-Abbreviations-Arkansas-QSO-party.pdf`, `Last-Modified: 2022-02-16` |
| Cabrillo name | WA7BNM Contest Calendar (Article 1 exception — §9) |
| Fetched | **2026-07-26** |

Banked: [`arqp_rules_2026.txt`](arqp_rules_2026.txt),
[`arqp_counties_2022.txt`](arqp_counties_2022.txt),
[`arqp_cabrillo_name.txt`](arqp_cabrillo_name.txt).

## 2. Dates — the sponsor states none

> "Contest Period: **The third Saturday in May.**"

That is the whole of it. **No times anywhere**, exactly as Delaware's rules do.

| Start | End |
| --- | --- |
| `2026-05-16T14:00:00Z` | `2026-05-17T02:00:00Z` |

The **date** derives from the sponsor — the third Saturday in May 2026 is the
16th. The **hours** come from the SQP Challenge calendar. **OPEN QUESTION 1.**

## 3. Exchange, bands, modes

> "Arkansas stations send signal report and **three-letter county
> abbreviation**. Non-Arkansas stations send signal report and U.S. State or
> Canadian Province, or "**DX**" if in another country."
>
> "**160, 80, 40, 20, 15, 10, 6, and 2 meter bands only.** No repeaters may be
> used for contest QSOs."

Eight bands; CW, phone and digital, with the sponsor noting that digital counts
"if the proper exchange can be accomplished and properly logged".

## 4. Counties

**75**, three letters, and the codes are **not truncations**:

| | |
| --- | --- |
| `CLA` Clay · **`CLK` Clark** | the only collision with both counties present to explain it |
| **`PLK` Polk**, **`JAK` Jackson** | `POL` and `JAC` are simply unused |
| **`ARK`** | there is an **Arkansas County** in Arkansas |
| `HSP` | Hot Spring |

The list dates itself — *"Three-letter designation is **NEW for 2022**"* — so its
2022 file date is intent rather than staleness, and **any pre-2022 list uses
different abbreviations entirely**.

## 5. Points — the rule that looked unmodellable

> "**Mobile, Portable, and Rover stations claim 2 points per QSO** for any band,
> any mode… **All other categories claim 1 point per QSO** on any band, any
> mode."
>
> "The TOTAL SCORE is the total QSO points multiplied by the total number of
> multipliers worked, **plus any bonus points**."

That keys points on the **entrant's own category**, which `PointsTable` cannot
express — it is keyed by mode, and by received location at best.

**But it fits exactly anyway.** The engine computes

```
total = qsoPoints × multiplierCount × categoryFactor + bonusPoints
```

and multiplication is associative, so **doubling the points and doubling the
factor give the same number**, with the bonus added after in both cases. So
`scoreMultipliers.stationCategory = {MOBILE: 2, PORTABLE: 2, ROVER: 2}` carries
the rule with **no approximation at all** — unlike Delaware's role-dependent
points, which genuinely could not be expressed.

## 6. Multipliers — and a DX cap that binds

> "**For Arkansas Stations:** Arkansas counties: 75… **U.S. States EXCEPT
> Arkansas**: 49… Canadian Provinces… [A maximum of 13]… **DX: Regardless of
> number of DX QSOs made, only count 1 DX multiplier.**
> **For Stations Outside of Arkansas:** 75 Arkansas counties."

- `countScope: "once"` — no band or mode axis is stated.
- **`homeStateCountsViaCounty: false`** — *"EXCEPT Arkansas"* — and Arkansas
  entrants count the 75 counties directly.
- **`dxMultCap: 1`, and it is the first cap in the app that binds.** Every other
  party's DX cap is unreachable because the token style collapses all DX to one
  multiplier; here **one is exactly what the sponsor pays**, so the two agree
  instead of fighting. New Hampshire's cap of ten remains unreachable for
  precisely the opposite reason.

## 7. Bonuses — two fit, one cannot

> "All stations claim **200 points for each valid QSO** with bonus station
> **WR5P**."
>
> "Mobile, Portable, or Rover stations that activate multiple counties can claim
> **200 points for each Arkansas county** from which they make a QSO."

→ `workStation(WR5P, 200, .perQSO)` and `activatedCountyCount(minQSOs: 1, 200)`
— **one QSO is enough**, the lowest activation threshold in the app.

> "**New for 2026:** Any station **live streaming** a portion or all of their
> operation on social media such as YouTube, Twitch, Facebook, etc. may claim
> **500 points**."

**Not modelled** — see §8.

## 8. Engine shapes to watch

1. **The 500-point live-streaming bonus is not modelled.** §7. It pays for
   streaming to YouTube or Twitch, which is not something a logger can observe,
   and no `BonusRule` shape describes it. Nothing is invented for it.

Everything else fits, including the two that looked as if they would not: the
mobile point value (§5) and the DX cap (§6).

## 9. Cabrillo `CONTEST:` header

**Not named** by the sponsor. `AR-QSO-PARTY` comes from WA7BNM under
[Article 1](../CONSTITUTION.md)'s exception.

## 10. County lines

> "Mobile, Rover or Portable stations that are **within three miles** of a county
> line… can transmit county abbreviations for **all of the applicable
> counties**."

**No cap is stated**, so the schema default of 4 ships. The sponsor adds a
warning worth repeating: *"this may not conform to official County Hunter rules
for their awards credit."*

## 11. Open questions

1. **What are the contest hours?** §2. The rules give "the third Saturday in
   May" and no times. The Challenge calendar's 1400Z–0200Z ships; worth
   confirming before 2027.

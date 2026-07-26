# Kentucky QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The site has rolled forward to 2027 and it does not matter** — which is worth
saying after Michigan and Ontario, where it did.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | the **Kentucky Contest Group**, <https://kyqsoparty.org> |
| **Rules** | <https://kyqsoparty.org/rules/> |
| **County list** | `…/uploads/2018/02/Kentucky_Counties.pdf`, `Last-Modified: 2019-07-09` |
| Cabrillo name | WA7BNM Contest Calendar (Article 1 exception — §8) |
| Fetched | **2026-07-26** |

Banked: [`kyqp_rules_2026.txt`](kyqp_rules_2026.txt),
[`kyqp_counties.txt`](kyqp_counties.txt),
[`kyqp_cabrillo_name.txt`](kyqp_cabrillo_name.txt).

The site advertises "Saturday June 5th, 2027" and has its 2026 results posted.

## 2. Dates — a formula and year-independent times

> "Date/Time … **UTC: 13Z – 01Z** … EDT: 9AM – 9PM / CDT: 8AM – 8PM / MDT: 7AM –
> 7PM / PDT: 6AM – 6PM"
>
> "always **1st Saturday in June**"

| Start | End | Length |
| --- | --- | --- |
| `2026-06-06T13:00:00Z` | `2026-06-07T01:00:00Z` | 12 h |

**The rollover is harmless because nothing in the schedule is year-bound**: the
formula gives the day and the times are stated in UTC. The first Saturday in
June 2026 is the 6th. The sponsor prints **four** local zones and all are
consistent; the test checks Eastern against a real zone rather than the prose.

## 3. Bands, modes, exchange

> "**80, 40, 20, 15, 10, 6, 2**" — seven bands, **no 160 m**.
>
> "All simplex QSOs, no repeaters, **NO digital QSOs**."
>
> "**KY stations:** RS(T) + County Abbreviation. **USA stations (non-KY):**
> RS(T) + State. **Canada:** RS(T) + Province. **DX:** RS(T) + "DX"."

## 4. Points and the power multiplier

> "**1 point** per completed Phone QSO. **2 points** per completed CW QSO."
>
> "High Power: More than 100 watts, Power Multiplier = **1**. Low Power: 100
> watts or less, **2**. QRP: 5 watts or less, **3**."
>
> "Total score = QSO Points × QSO Multipliers × Power Multiplier + Bonus Station
> points."

Whole numbers, so the power multiplier ships — the **fifth** party to manage it.
The formula is the engine's exactly.

## 5. Multipliers

> "**Kentucky Station operators:** Each Kentucky station is a multiplier when
> worked in each of the **120 counties**… KY stations log USA state (not ARRL
> section), **including DC**, and Canadian Provinces. **KY stations log DX
> contacts for QSO points only**, and enter "DX" for the exchange.
> **Non-Kentucky Station operators:** Each Kentucky station is a multiplier based
> on their county."

- Kentucky entrants count the 120 counties **directly**, plus states and
  provinces. `KY` is never received — *"enter the County as the exchange (**not
  KY**)"*.
- **DX pays points and no multiplier** — the fourth party with that shape, after
  Georgia, North Dakota and Indiana.

## 6. The bonus station — and a scope this run already added

> "**Bonus Station K4KCG.** K4KCG may be worked **once per BAND and MODE** for
> **100 bonus points per QSO**."

That is exactly `BonusRule.WorkStationScope.perBandMode`, which this run
introduced for South Carolina back in February's parties. **Second user, and it
fits without adjustment** — the kind of result that justifies having added the
case rather than approximating it.

The sponsor adds a warning worth carrying forward:

> "**Bonus stations may change each year**, without needing logging program
> updates."

So a 2027 session must re-read the call rather than assume `K4KCG`.

## 7. Engine shapes to watch

1. **The 100-point log-submission bonus is not modelled.** *"An additional 100
   points is added to your final score as a bonus for submitting your Cabrillo
   log file online."* It pays for uploading a file, not for anything on the air.
   **Delaware has the identical gap** with its 50-point version — two users now.
2. **County-line permission is per category and the schema is per party.**
   *"KY **Fixed** stations on a county line must choose a KY county… **No
   multiple county exchanges**"*, while *"KY **Mobile and Expedition** stations
   may setup on a county line"* and send several. `maxSimultaneousCounties` is
   one number for the whole party, so the permissive default of 4 ships:
   correct for mobiles, and too permissive for fixed stations. Refusing a legal
   mobile exchange would be the worse failure.

## 8. Cabrillo `CONTEST:` header

**Not named** by the sponsor. `KYQP` comes from WA7BNM under
[Article 1](../CONSTITUTION.md)'s exception.

## 9. County list

**120 counties** — the third-largest single-state list here, after Texas and
Georgia. The codes are truncations **only where the letters were free**:

| | |
| --- | --- |
| `HAR` Hardin · `HRL` Harlan | |
| `MON` Monroe · `MOT` Montgomery | |
| `GRE` Green · `GRP` Greenup · `GRT` Grant · `GRV` Graves · `GRY` Grayson | five counties, two shared letters |

The PDF's 2019 date is age rather than staleness — it is linked from a site
current for 2026, and Kentucky's counties have not changed since 1912.

## 10. Open questions

**None.**

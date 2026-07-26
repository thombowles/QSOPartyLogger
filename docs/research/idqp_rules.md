# Idaho QSO Party ("The SPUD RUN") — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**Also one of 7QP's seven states**, so this county list is reusable when the 7th
Call Area party is built — see the worklist's *Scope* section.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Idaho QSO Party Contest Committee**, <https://idahoqsoparty.org> |
| Contact | `idahoqso@gmail.com` |
| **Rules** | <https://idahoqsoparty.org/rules.htm> |
| County list | <https://idahoqsoparty.org/MAPcountylist.htm> — "MAP & LIST of the 44 Idaho Counties" |
| Log robot | <https://idqp.contesting.com/idqpsubmitlog.php> — **Cabrillo required** |
| Fetched | **2026-07-26** |

Banked verbatim: [`idqp_rules_2026.txt`](idqp_rules_2026.txt),
[`idqp_counties.txt`](idqp_counties.txt).

**Retrieval note:** the county page **403s a plain fetch**. It needs a browser
`User-Agent` *and* a `Referer` of `https://idahoqsoparty.org/`. Third sponsor this
run to gate its own documents (after w0aa.org's Referer requirement and k5cm.com's
frameset).

## 2. Dates and times for 2026, in UTC

**The rules' date block is the worst in the repo and must not be read literally.**
In eleven lines it manages four errors:

| What it says | Why it is wrong |
| --- | --- |
| "The IDQP starts Saturday, March 13" | 13 March 2026 is a **Friday** |
| "**xxxxZ** (13/March/2026 GMT)" | a literal **placeholder** — the start time is simply absent |
| "END TIME FOR SATURDAY is 03:59Z (14/March/**2025**, GMT)" | wrong **year** |
| "START TIME FOR **SUNDAY** 1400Z (14/March/2026, GMT)" | the 14th is a **Saturday** |

**Two windows ship, reconstructed from three things that do agree:**

| Segment | Start | End | Length |
| --- | --- | --- | --- |
| Saturday | `2026-03-14T16:00:00Z` | `2026-03-15T04:00:00Z` | 12 h |
| Sunday | `2026-03-15T14:00:00Z` | `2026-03-16T02:00:00Z` | 12 h |
| | | **total** | **24 h** |

1. **The formula.** *"Always the second full weekend of March."* March 2026 opens
   on a Sunday, so the full weekends are 7–8 and **14–15 March** ✓.
2. **The stated durations.** *"ON THE AIR 12 Hours"*, printed under each day.
3. **The local anchors, under EDT** — and the sponsor flags the trap itself:
   *"LOOK OUT! check your computer time, Daylight time kicked in."* US DST began
   8 March 2026, the weekend before.
   - Saturday end `03:59Z` = 11:59 pm EDT ✓ (the page's own "11:59pm midnight").
     Twelve hours back puts the start at **1600Z** = 12 noon EDT ✓ (its "12
     noon"). The page's `EsT` labels are decoration; the numbers are EDT.
   - Sunday `1400Z` = 10 am EDT ✓ ("EDT 10 AM"), end `01:59Z` = 9:59 pm EDT ✓
     ("EDT 9:59 PM"). Twelve hours ✓.

The printed `03:59Z` / `01:59Z` are last-minute notation, as in MNQP, BCQP and
SCQP; the stated 12-hour durations put the ends at `0400Z` and `0200Z`.

**Independently corroborated:** the State QSO Party Challenge calendar prints
exactly `3/14 1600Z → 3/15 0400Z` and `3/15 1400Z → 3/16 0200Z`. Per Article 19 a
calendar decides build order, not dates — but where the sponsor's own block is
self-contradictory, an independent source agreeing with the reconstruction is
worth recording. **This is nonetheless an open question**; one email to
`idahoqso@gmail.com` would settle it.

## 3. Exchange

> "A. Idaho stations send your counties three letter abbreviation.
> B. W/VE stations (including KH6/KL7) send your state or province.
> C. DX stations (including KH2/KP4, etc.) send your DXCC prefix/country.
> **please note: the RST is no longer part of the contest**, logging software
> sometimes requires the RST, 59 is perfect, **you are not scored on RST
> reports**" — rule 7

| Role | Sends |
| --- | --- |
| **In-state (ID)** | one of the 44 county codes — **nothing else** |
| **W/VE** | state or province; **Alaska and Hawaii are W/VE** |
| **DX** | DXCC prefix; **Guam and Puerto Rico are DX** |

→ `exchangeIncludesRST: **false**` — stated outright, and the fourth party to
drop the report after MDC, MNQP and NCQP. → `dxStyle: "prefix"`, since Idaho
stations count DXCC countries individually (§6).

The KH6/KL7-vs-KH2/KP4 split is worded identically to OKQP's, one party earlier.

## 4. QSO points by mode — and the one rule that does not fit

> "Each phone QSO counts as **one** point. Each CW and Digital QSO counts as
> **two** points. **ALL QRP QSO's count 5 points.** voice, CW, digital." — rule 8A

| Mode | Points | QRP |
| --- | --- | --- |
| Phone | 1 | **5** |
| CW | 2 | **5** |
| Digital | 2 | **5** |

**`PointsTable` is keyed by mode alone, with no notion of the entrant's power
class**, so the QRP rule cannot be expressed. Shipped at the non-QRP values, with
the limitation recorded — a QRP entrant's score is understated by a factor of
between 2.5 and 5 per QSO. See §14, limitation 1.

*(The rule is also ambiguous as written — "ALL QRP QSO's" could mean QSOs **made
by** a QRP station or QSOs **with** one. The former is the only reading that
scores consistently, since a worked station's power is not part of the exchange,
and it is how the power categories in rule 4 are framed. Recorded as part of the
open question.)*

> "D. Stations may be worked once per mode, per band (for mobiles in each new
> county), i.e., w7abc may be worked on both 20 CW and 20 SSB for QSO credit."
> — rule 10D

→ `dupeScope: "bandMode"`. "B. No cross-mode contacts are allowed."

**FT8 is barred:** *"FT-8 is incompatible with our exchange, so No FT-8 type
modes"* — rule 5D. Below `ModeClass.digital`'s granularity, as in ILQP, NCQP and
OKQP. This sponsor gives the *reason*, which is worth keeping: the exchange is a
county abbreviation, and FT8 cannot carry one.

## 5. Multipliers

> "1) For Idaho stations, count each US state (**including Idaho**), Canada
> province, and DXCC country as "a" (one) multiplier. **A multiplier is counted
> once per mode, regardless of the number of bands on which it is worked.**
>
> 2) For non-Idaho stations: **Idaho counties are multipliers.** … An Idaho
> county multiplier will be counted **once per mode**, regardless of the number
> of bands on which it is worked." — rule 8B

| | In-state (ID) | Out-of-state |
| --- | --- | --- |
| Classes | 50 states **including Idaho** + provinces + DXCC countries | **44 Idaho counties** |
| Scope | **once per mode** | **once per mode** |

→ `countScope: "perMode"` both sides; `inState.classes = [county, state,
province, dx]`, `outState.classes = [county]`. No DX cap.

**`homeStateCountsViaCounty: true`, stated as plainly as SCQP's** — "each US
state (**including Idaho**)" — while Idaho stations send a county, so the token
`ID` is never received. That makes it the second party this run to say yes
outright, against MNQP's and NCQP's explicit no.

*(The in-state class list keeps `.county` because rule 8B(2)'s county multipliers
are framed for non-Idaho stations, while an Idaho station working another Idaho
station still receives a county. The sponsor does not say whether that county
counts for the Idaho station beyond yielding the `ID` state multiplier; shipped
counting, which is the reading that makes the received token meaningful. Part of
the open question in §14.)*

> "Idaho mobile stations that change counties are considered to be a new station
> and may be contacted again for point and multiplier credit."

> "HOWEVER, once you work 'say' Kansas, that's the one and only multiplier for
> KS." — rule 3C, on rover scoring

## 6. County-line rules

> "Idaho stations on a county line may be claimed as a QSO and a multiplier from
> **each county (2 QSO's and 2 multipliers)**. County lines whether land or
> water, are defined per "County Hunter" rules." — rule 8B(2)

→ `maxSimultaneousCounties: **2**`, stated with the number. Like NCQP, the
sponsor delegates the definition of a county line to the county-hunter
community's rules.

## 7. Bonus points

**One, and it does not fit.** From the Categories section:

> "Heads UP IDAHO STATIONS — **Bonus Points for activating dormant counties.**
> Any Expedition or Rover or a home station residing in a county, that activates
> that county, which has been dormant during previous year(s) (See List HERE)
> those station will get **500 bonus points (or 1000) (or 1500) (see list)** if
> they make **MORE THAN 10 contacts**"

`BonusRule.activatedCountyCount(minQSOs:points:)` carries **one** points value;
this pays 500, 1000 or 1500 **depending which county**, from a list published
separately and refreshed each year. Not shipped — see §14, limitation 2. It
affects Idaho rovers and expeditions only.

## 8. Final-score multipliers

**None that this app can act on**, but the wording is unclear enough to record:

> "C. Final Score: Fixed stations **Multiply QSO x Mode multiplier x Mults**…"

"Mode multiplier" appears nowhere else in the rules — there is no mode-based
score factor defined, and rule 8B already scopes multipliers per mode, which is
the only sense the phrase can carry without double-counting. Read as a loose
restatement of *"a multiplier is counted once per mode"*, which is how
`countScope: "perMode"` already behaves. `scoreMultipliers` absent. Power selects
the award category (rule 4) and, per §4, the QSO point value.

## 9. Valid bands

> "6. Bands, **only 160 - 80 - 40 - 20 - 15 - 10 meters.**" — repeated verbatim
> in rule 9

**Six bands:** `160m, 80m, 40m, 20m, 15m, 10m`. HF only, no WARC, no VHF.

## 10. Categories

Single operator · Multi-operator (Multi-Single, Multi-Multi — *"only one per mode
per band at a time"*) · **Mobile/Rover**, with separate In-State and Out-of-State
categories. Power: QRP ≤5 W, Low ≤150 W, High >150 W; *"Logs not showing power
output category will be listed as high power."*

A rover who also operates from home submits **two logs under two calls**:
*"we request you submit a Rover log and a home station log."*

## 11. Cabrillo `CONTEST:` header

**`ID-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, fetched 2026-07-26), Article 1's
codified exception, **because the sponsor prints no `CONTEST:` value** anywhere
in its rules despite requiring Cabrillo (*"ALL Logs must be Cabrillo files"*).

## 12. County list

**44 counties, uniform 3-letter codes**, from the sponsor's own map/list page.

Spot checks worth making — Idaho's list is dense with near-collisions, and **the
`B` cluster is the worst in the repo**:

| Code | County | |
| --- | --- | --- |
| `BAN` | Bannock | |
| `BEA` | Bear Lake | two words |
| `BEN` | Benewah | |
| `BIN` | Bingham | |
| `BLA` | Blaine | |
| `BOI` | Boise | |
| `BNR` | **Bonner** | *not* `BON` |
| `BNV` | **Bonneville** | *not* `BON` either — the pair that forces both |
| `BOU` | Boundary | |
| `BUT` | Butte | |

Ten counties beginning with `B`, of which **`BON` is not a code at all**. Also:

- `CAM` Camas, `CAN` Canyon, `CAR` Caribou, `CAS` Cassia — four `Ca` counties.
- `CLA` Clark vs `CLE` Clearwater; `CUS` Custer.
- `LAT` Latah, `LEM` Lemhi, `LEW` Lewis, `LIN` Lincoln — four `L` counties.
- `NEZ` Nez Perce and `TWI` Twin Falls are two words.
- `IDA` is Idaho **County**, distinct from the `ID` state token, which is never
  sent — the same shape as OKQP's `OKL`.

## 13. Engine shapes to watch

Two gaps, both affecting a minority of entrants, and neither in doubt as a rule:

1. **QRP QSOs are worth 5 points and this app cannot pay them.** §4.
   `PointsTable` is keyed by mode; nothing in the schema knows the entrant's
   power class at scoring time — `StationProfile.categoryPower` exists and
   `ScoreMultipliers` already reads it for a *final-score* factor, so the data is
   there, but it is not wired into `pointsTable(forTheirLoc:countyAbbrs:)`.
   Sketch: an optional `powerPoints: {"QRP": {...}}` consulted alongside
   `homeStationPoints`. **A QRP entrant's score is understated 2.5–5× per QSO**;
   everyone else is exact.
2. **Dormant-county bonuses are tiered per county, at 500/1000/1500.**
   `activatedCountyCount` carries one value. The tier list is published
   separately and changes yearly, so even a fixed table would go stale — this
   wants a `{county: points}` map, or simply to stay a manual adjustment.
   **Idaho rovers and expeditions only.**

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| phone 1, CW/digital 2 | `points` |
| "once per mode, per band" | `dupeScope: "bandMode"` |
| "counted once per mode, regardless of … bands" | `countScope: "perMode"`, both sides |
| "each US state (including Idaho)" | `homeStateCountsViaCounty: true` |
| DX sends a prefix, counted individually | `dxStyle: "prefix"`, no cap |
| "2 QSO's and 2 multipliers" on a line | `maxSimultaneousCounties: 2` |
| "the RST is no longer part of the contest" | `exchangeIncludesRST: false` |
| 160–10 m "only" | `validBands` |

**`outStateWorksHomeStationsOnly`: TRUE, but by inference rather than by
sentence** — and this is the one to re-read. Rule 1 says the objective for
outside stations is *"to contact as many Idaho stations and Idaho counties as
possible"*, and rule 8B(2) gives non-Idaho stations Idaho counties as their only
multiplier; but no sentence forbids credit for a non-Idaho contact outright, the
way MNQP's and NCQP's do. Shipped on, as for the six other parties that only
imply it, so a stray non-Idaho contact is visibly flagged NO CREDIT rather than
silently scored. Recorded as an open question.

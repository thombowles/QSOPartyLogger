# Virginia QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The first party whose entity list is not just counties**, and the first where
four entities share a name with another — see §13, which is the section that
matters here.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Sterling Park Amateur Radio Club (SPARC)**, PO Box 29, Sterling VA 20167 |
| Contact | `vqp@verizon.net` (`vqp@arrl.net` for problems) |
| **Rules** | <https://www.qsl.net/sterling/VA_QSO_Party/2026_VQP/2026_VAQP_Rules.pdf> — "2026 Virginia QSO Party Rules" |
| Entity list | <https://www.qsl.net/sterling/VA_QSO_Party/2024_VQP/VQP_Counties&Cities.html> — linked from the 2026 main page |
| Logs | online portal, or `vqp@verizon.net`, by **15 April** |
| Fetched | **2026-07-26** |

Banked verbatim: [`vaqp_rules_2026.txt`](vaqp_rules_2026.txt),
[`vaqp_counties.txt`](vaqp_counties.txt).

The entity list is served from a **2024** path and is headed *"as of 2017"*, but
the 2026 rules restate its counts verbatim — *"95 Virginia Counties and 38
Virginia Independent Cities"* — so it is current and the generator asserts the
agreement. Virginia has not created or dissolved an independent city since 2013.

## 2. Dates and times for 2026, in UTC

> "**Saturday, 21 March 2026, 1400 UTC – Sunday, 22 March, 0400 UTC and Sunday,
> 22 March, 1200 UTC – 2400 UTC.** (For Virginia, this is Saturday 10 AM – 12
> Midnight and Sunday 8 AM – 8 PM Virginia local time.)"

| Segment | Start | End | Length |
| --- | --- | --- | --- |
| Saturday | `2026-03-21T14:00:00Z` | `2026-03-22T04:00:00Z` | 14 h |
| Sunday | `2026-03-22T12:00:00Z` | `2026-03-23T00:00:00Z` | 12 h |
| | | **total** | **26 h** |

**Round instants, no reconstruction.** All four local anchors land exactly under
**EDT** (UTC−4; US daylight time began 8 March): 1400Z = 10 am ✓, 0400Z =
midnight ✓, 1200Z = 8 am ✓, 2400Z = 8 pm ✓. `2400 UTC` on the 22nd is midnight
ending that day, i.e. `2026-03-23T00:00:00Z`.

**26 hours is the longest total of any bundled party except Vermont's 48.**

## 3. Exchange

> "**Exchange QSO number and QTH** (Virginia County or Independent City for VA
> stations; State, Province or "**DX**" for others). Virginia Stations log QSO's
> by Virginia Independent City or County of operation. Identify all QSO's with
> band/mode, **sequential QSO number sent/received** and date/time of contact in
> UTC."

| Role | Sends |
| --- | --- |
| **In-state (VA)** | QSO number + one of the 133 county/city codes |
| **Out-of-state** | QSO number + state, province, or the literal `DX` |

→ **`exchangeIncludesSerial: true`** — the third party to carry a QSO number,
after CQP and PAQP. → **`exchangeIncludesRST: false`**: no signal report appears
anywhere in the rules, and the "identify all QSO's with" list omits it. VAQP is
the first party to pair a serial number with *no* report — CQP and PAQP do the
same, so this is the third of that shape and the schema already allows all four
combinations.

→ `dxStyle: "token"` — the sponsor asks for the literal `"DX"`.

## 4. QSO points — and the one rule that does not fit

> "QSO's count **1 point per Phone, 2 points per CW, 2 points per digital mode**
> (RTTY, PSK31, etc.), and **3 points per contact made with a Virginia Mobile,
> Expedition, or Rover.**"

| Mode | Points |
| --- | --- |
| Phone | 1 |
| CW | 2 |
| Digital | 2 |
| *any mode, with a VA mobile/expedition/rover* | **3** |

**The 3-point rule is keyed on the worked station's category, which is not part
of the exchange and is not in the log.** `PointsTable` is keyed by mode;
`homeStationPoints` switches on the *received location*, and every VA station
sends a county or city, so it cannot distinguish a mobile from a fixed station.
Shipped at the by-mode values, with the limitation recorded — see §14.

The sponsor's own convention is the only hint available at logging time:
*"Mobile, Rover, and Expedition stations must use appropriate suffix in call
sign"* — so the information is in the callsign (`/M`, `/R`), not the exchange.
That makes a future fix tractable but not free.

## 5. Dupe rule

> "Work fixed stations **once per band/mode**. Work Virginia Expeditions, Rovers,
> and Mobiles in **each Virginia County or Independent City** from which they
> operate."

→ `dupeScope: "bandMode"`, with a county change making a new QSO — already how
`DupeChecker` behaves, since `theirLoc` is in the key.

> "No cross-mode or repeater QSO's."

## 6. Multipliers

> "Multipliers are **only counted once**, i.e., contacting the same Virginia
> County, Independent City, State, Province or Country using a different band or
> mode counts only as a new QSO, not as a new multiplier.
>
> **Virginia … multipliers** are the total number of Virginia counties, Virginia
> independent cities, **U.S. States (except Virginia)**, Canadian Provinces, and
> DX entities. **No extra DX multiplier for U.S. (including Alaska and Hawaii),
> Virginia, and Canada.**
>
> **Outside of Virginia station multipliers** are the total number of Virginia
> Counties (**95**) and Independent Cities (**38**) worked."

| | In-state (VA) | Out-of-state |
| --- | --- | --- |
| Classes | 133 counties+cities + 49 states + provinces + DX entities | **133 counties + cities** |
| Scope | **once overall** | **once overall** |
| Stated max | — | **133** |

→ `countScope: "once"` both sides; `inState.classes = [county, state, province,
dx]`, `outState.classes = [county]`.

- **`homeStateCountsViaCounty: false`, stated outright** — *"U.S. States (**except
  Virginia**)"*, and again *"No extra DX multiplier for … Virginia"*. Third party
  this run to exclude its own state explicitly, after MNQP and NCQP.
- **Alaska and Hawaii are states, not DX**, stated in the same clause.
- No `stateAliases`: DC is never mentioned. It stays its own state-class token,
  as in MNQP, NCQP and SCQP.

**One multiplier rule is not modelled**, the self-activation provision again:

> "Mobile, Rover, and Expedition stations that contact **10 (ten) or more**
> different stations while operating from a county or independent city may claim
> it as a multiplier, **if not otherwise worked**."

**Fourth user** of the deferred self-activation-multiplier gap, after TnQP, SCQP
and NCQP — and the first to add an *"if not otherwise worked"* condition, which
the sketch will have to carry. In-state mobiles/rovers/expeditions only.

## 7. Bonus points

**Two, one modelled and one that cannot be.**

> "Virginia Mobile, Rover, and Expedition stations receive a bonus of **100
> additional points for each Virginia County/Independent City from which they log
> a valid QSO.**"

→ `activatedCountyCount(minQSOs: 1, points: 100)` — "a valid QSO" is a threshold
of one, and the engine already gates on an in-state roving category. Fits
exactly.

> "A QSO with each different VA QSO Party **Bonus Station** gives a one-time
> bonus of **50 points**. **Bonus stations are listed on the VaQP Web Site.**"

**The rules do not name them**, and the web site's list is published close to the
event. **None ships** — the same call PAQP's unannounced 2026 station got. See
§14.

> "Final score is the number of QSO Points multiplied by the number of
> Multipliers plus Bonus Points."

No power multiplier: High/Low/QRP select the award category only.
`scoreMultipliers` absent.

## 8. County-line rules — and this one is unusual

> "**Stations on County or Independent City lines count as one QSO and one
> County/Independent City multiplier.**"

→ `maxSimultaneousCounties: **1**`.

**Note what this is not.** Most parties either forbid line operation (ALQP, MNQP,
WIQP) or pay for every county on the line (IAQP and OKQP pay up to four). VAQP
*permits* a station to sit on a line and then pays for **one** — so a two-county
entry is wrong here not because line-sitting is banned but because it would claim
two multipliers where the sponsor gives one. The operator picks which.

## 9. Valid bands

> "**160 meters and up, except no WARC band QSO's permitted.**" Suggested: CW
> 1805 kHz and 50 kHz up from each band edge; phone 1845, 3860, 7260, 14270,
> 21370, 28370; **VHF 50.130, 144.200, 146.580 and 223.50 MHz; UHF 446.00 MHz.**

**Ten bands:** `160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m, 1.25m, 70cm` — the same
set as WIQP, and derived the same way, from the suggested-frequency list. "No
WARC" excludes 30/17/12; 60 m appears nowhere.

*(The sponsor suggests 223.50 and 446.00 MHz, which WIQP's rules explicitly tell
operators to avoid as national calling frequencies. Two sponsors, opposite
conventions — worth not "harmonising".)*

**"Satellite contacts allowed"** — a mode this app has no concept of. Recorded in
§14; it changes no score here, since a satellite QSO still lands on a band this
app knows.

## 10. Categories

**Operator:** Single Operator · Multi-Op/Single Transmitter · Multi-Op/Multi
Transmitter. **Station:** Fixed · **Mobile** · **Expedition** · **Rover**, each
carefully distinguished (the Rover is *"a vehicle-mounted designed for contesting
and is not a mobile or expedition station"* [sic]). **Power:** High >150 W, Low
≤150 W, QRP ≤5 W. **Band:** Multi-Band or Single Band. **Mode:** Phone, CW,
Digital, Mixed. Plus a **Club** entry needing three valid entries.

*"Please submit separate logs for Fixed, Expedition, Mobile, and Rover
operation."*

## 11. Cabrillo `CONTEST:` header

**`VA-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, fetched 2026-07-26), Article 1's
codified exception, because **the rules print no `CONTEST:` value** and give no
Cabrillo example.

## 12. Entity list — 95 counties and 38 independent cities

**133 entities, uniform 3-character codes.** The sponsor's list marks independent
cities with an asterisk:

> "**95 Counties and 38 Independent Cities with 3 Character Abbreviations —
> Cities marked with an "*"**"

**Four names appear twice**, once as a county and once as an independent city —
Virginia's unique arrangement, and the thing this party turns on:

| Name | County | City |
| --- | --- | --- |
| Fairfax | `FFX` | `FXX` |
| Franklin | `FRA` | `FRX` |
| Richmond | `RIC` | `RIX` |
| Roanoke | `ROA` | `ROX` |

**So county names are NOT unique here, and no test may assert that they are** —
a first for this repo. The abbreviations are unique, which is what
`PartyDefinition.validate()` actually requires.

**Cities are rendered `"Name (City)"`**, which is this repo's only transformation
of a sponsor's printed name, and it is deliberate: it renders the sponsor's own
asterisk as readable text, makes all 133 display names unique, and stops an
operator picking `FRA` when they meant `FRX`. The generator asserts exactly 38
such names and exactly 95 without.

Most city codes end in `X` (`ALX`, `LYX`, `NNX`, `VBX`…), which is the sponsor's
convention — but **it is not a reliable test**: `FFX` Fairfax *County* ends in X
too. The asterisk is the authority, not the letter.

Other codes worth spot-checking: `CCY` Charles City, `KQN` King & Queen, `KGE`
King George, `KWM` King William, `IOW` Isle of Wight, `MPX` Manassas Park,
`COX` Colonial Heights, `BVX` Buena Vista.

## 13. Engine shapes to watch

1. **NO POINTS BY STATION CATEGORY.** §4. A contact with a Virginia mobile,
   expedition or rover is worth **3** regardless of mode; this app pays 1/2/2.
   The worked station's category is not in the exchange — only in its callsign
   suffix, by convention. **This under-credits anyone who chases Virginia
   mobiles, which in a party with 133 entities is most of the field.** Sketch: a
   party flag plus a callsign-suffix predicate feeding
   `pointsTable(forTheirLoc:)`, which would also want the operator to be able to
   mark a row manually, since the suffix is a convention rather than a rule.
2. **Bonus stations are not enumerated in the rules.** §7. Published on the web
   site near the event; none ships, as with PAQP's 2026 station. 50 points each,
   one-time.
3. **Self-activation multipliers — FOURTH user**, and the first with an *"if not
   otherwise worked"* condition. §6.
4. **Satellite contacts allowed** — no satellite concept exists here. §9.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| phone 1, CW 2, digital 2 | `points` |
| "once per band/mode" | `dupeScope: "bandMode"` |
| "only counted once … different band or mode" | `countScope: "once"`, both sides |
| "U.S. States (except Virginia)" | `homeStateCountsViaCounty: false` |
| QSO number, no report | `exchangeIncludesSerial: true`, `exchangeIncludesRST: false` |
| `"DX"` | `dxStyle: "token"` |
| lines pay one multiplier | `maxSimultaneousCounties: 1` |
| 100 points per county/city activated | `activatedCountyCount(minQSOs: 1, points: 100)` |
| "Out-of-State stations work Virginia stations only" | `outStateWorksHomeStationsOnly: true` |
| two windows, 14 h + 12 h | `schedule` |

**`outStateWorksHomeStationsOnly` opens the VALID CONTACTS section** — *"Virginia
stations work all stations. Out-of-State stations work Virginia stations only."*
The fourteenth party to state it rather than imply it.

# Wisconsin QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The second party to want a fractional power multiplier**, which met the
repo's own two-user bar and got the field built — see §8 and §14.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **West Allis Radio Amateur Club (WARAC)**, club call **`W9FK`** |
| **Rules** | <https://www.warac.org/wqp/wiqp_rules.htm> — page headed **2026** |
| Multiplier list | <https://www.warac.org/wqp/wiqp_mults.htm> — 72 counties, states, provinces |
| Cabrillo guide | <https://www.warac.org/wqp/wiqp_cabrillo.htm> |
| Logs | `wiqp-logs@warac.org`, due **29 March 2026** |
| Fetched | **2026-07-26** |

Banked verbatim: [`wiqp_rules_2026.txt`](wiqp_rules_2026.txt),
[`wiqp_mults.txt`](wiqp_mults.txt), [`wiqp_cabrillo.txt`](wiqp_cabrillo.txt).

**The Cabrillo guide is not optional reading** — it settles two things the rules
page leaves loose (§3, §11), and its worked example independently confirms the
exchange shape. **Retrieval note:** the multiplier page 403s a plain fetch and
needs a browser `User-Agent` plus a `Referer`; the fourth sponsor this run to
gate its own documents.

## 2. Dates and times for 2026, in UTC

> "**March 15, 2026 from 1800Z to 0100Z March 16** (1:00PM CDT to 8:00PM CDT on
> March 15)"

| Start | End | Length |
| --- | --- | --- |
| `2026-03-15T18:00:00Z` | `2026-03-16T01:00:00Z` | 7 h 00 m |

**No reconstruction needed** — round instants, and the local anchors confirm them
under CDT (UTC−5): 1800Z = 1 pm ✓, 0100Z = 8 pm the previous day ✓. **The
shortest TOTAL OPERATING TIME of any bundled party**, beating ILQP's eight
hours. **Not** the shortest single session — KSQP and TQP each have a six-hour
Sunday leg, though both run eighteen hours overall. (The first draft of this
party's test asserted the wrong one of those two and failed, which is how the
distinction got found.)

**A stale note, recorded so nobody acts on it:** the page carries *"Note: First
day of Daylight Saving Time!"*, which is wrong for 2026 — US DST began **8
March**, a week earlier. It sits immediately before an HTML comment terminator in
the source, so it appears to be leftover copy the sponsor meant to comment out.
It changes nothing: the UTC instants are printed outright and the CDT anchors
already assume daylight time.

*(Wisconsin runs the day after Oklahoma's and Idaho's second segments, closing
the 14–15 March weekend.)*

## 3. Exchange

> "**Wisconsin stations send County. Non-Wisconsin stations send State or
> Province or Country.**"

| Role | Sends |
| --- | --- |
| **In-state (WI)** | one of the 72 county codes |
| **Out-of-state** | state, province, or the literal `DX` |

→ **`exchangeIncludesRST: false`** — no report is mentioned anywhere, and the
sponsor's own Cabrillo example proves it, carrying call + location only:

```
QSO: 7240 PH 2020-03-15 1801 W9HNW RAC ND9Z BRO
QSO: 28567 PH 2020-03-15 2145 W9HNW RAC DL6QK DX
```

Fifth party to drop the report, after MDC, MNQP, NCQP and IDQP.

→ **`dxStyle: "token"`, and the Cabrillo guide is why.** The rules say DX
stations send "Country", which reads like a prefix — but the sponsor's own
example logs `DL6QK` as **`DX`**, the literal token. Since DX yields no
multiplier at all (§6), nothing is lost by collapsing entities, and the token is
what the log robot will see. **Had only the rules page been read, this would have
shipped as `prefix` and rejected the sponsor's own sample line.**

## 4. QSO points by mode

> "Phone contacts count **1** point; CW and Digital contacts count **2** points."

| Mode | Points |
| --- | --- |
| Phone | 1 |
| CW | 2 |
| Digital | 2 |

## 5. Dupe rule

> "All stations may be worked **once per mode on each band**. **Cannot work the
> same station on more than one Digital mode on the same band.**"

→ `dupeScope: "bandMode"`, and the digital sentence is exactly what
`ModeClass.digital` already enforces — all digital modes collapse to one. Same
as SCQP, and the opposite of VTQP.

> "Mobiles and portables may be worked **once per mode per Wisconsin county**
> that they operate from."

A county change makes a new QSO, already how `DupeChecker` behaves.

**FT8/FT4 are barred:** *"CW, Phone and Digital (RTTY, PSK, Olivia, Feld-Hell).
**FT8/FT4 QSO's are not accepted.**"* Below `ModeClass.digital`'s granularity —
the fifth party to want that distinction, after ILQP, NCQP, OKQP and IDQP.

## 6. Multipliers

> "**Wisconsin Stations:** The sum of Wisconsin counties (max. 72), plus US
> states (max. 50) plus Canadian provinces (max. 13) worked. **Wisconsin may be
> counted as a state multiplier.** DX countries worked count for QSO points but
> **not as multipliers**.
>
> **Non-Wisconsin Stations:** The number of Wisconsin counties worked (max. 72).
> **Only Wisconsin stations may be worked.**"

| | In-state (WI) | Out-of-state |
| --- | --- | --- |
| Classes | 72 counties + 50 states + 13 provinces | **72 WI counties only** |
| Scope | **once overall** | **once overall** |
| Stated max | 72 + 50 + 13 = **135** | **72** |
| DX | **points only, no multiplier** | no multiplier |

→ `countScope: "once"` on both sides — the stated maxima settle it: 72 counties
*total*, not per band or per mode. `inState.classes = [county, state, province]`
with **no `.dx`**; `outState.classes = [county]`.

- **`homeStateCountsViaCounty: true`, stated outright** — *"Wisconsin may be
  counted as a state multiplier"* — while WI stations send a county, so the token
  `WI` is never received. The multiplier list corroborates it by including `WI
  Wisconsin` in the states table. Third party this run to say yes plainly, after
  SCQP and IDQP.
- **`stateAliases: {"DC": "MD"}`** — the multiplier list prints **`MD
  Maryland/(D.C.)`** as one row, and there is no DC row. The rules page never
  mentions DC; only the multiplier list settles it.
- The provinces are the standard 13 with the standard `NL`.

## 7. Bonus points

**Two, and both are *nearly* modelled.**

> "**Wisconsin Mobiles/Portables:** Add **500 bonus points** for each county that
> you operate from **outside your home county**. A minimum of **12 QSO's** per
> county is required to qualify."

→ `activatedCountyCount(minQSOs: 12, points: 500)`. **One deviation:** the
sponsor excludes the operator's *home* county, and `ScoreEngine` counts every
county with enough QSOs, including home. A Wisconsin mobile who also makes 12+
QSOs from home is over-credited 500. Recorded; see §14.

> "**W9FK:** Add **100 points for each time you work W9FK on each band and mode
> below 50MHz**. (W9FK is the West Allis Club callsign)."

→ `workStation(call: "W9FK", points: 100, scope: "perBandMode")` — the scope
added for SCQP two parties ago, now with its second user. **One deviation:** the
sponsor caps it *below 50 MHz*, and this app's `perBandMode` counts every
band/mode slot including 6 m and up. A 6 m or 2 m contact with W9FK would be
over-credited 100. Recorded; see §14.

## 8. Final-score multipliers — fractional, and this is the second time

> "QRP — less than 5 watts — **Power Mult = 2**
> Low — 5 to 100 watts — **Power Mult = 1.5**
> High — over 100 watts — **Power Mult = 1**"

> "Add CW, Phone and Digital points. **Then multiply by Power Level multiplier.
> Then multiply by your multiplier count** under MULTIPLIERS. Finally, add your
> bonus points."

**Shipped in full on 2026-07-28.** `ScoreMultipliers` was `[String: Int]` and
**could not hold 1.5** — identical to VTQP's problem, down to the same three
factors — so `scoreMultipliers` was **not shipped** rather than have
`{QRP: 2, LOW: 1, HIGH: 1}` understate the most common power class by a third
while looking correct. **WIQP was the second user of that gap, which met the
repo's own bar of waiting for a second party**, and both parties gained the
field once `ScoreFactor` made the factor an exact rational.

The stated order — points × power × multipliers, *then* bonuses — is exactly
what `ScoreEngine` computes, and the "finally" is load-bearing: the county and
W9FK bonuses are added after the power factor and are never scaled by it.

**Rounding: the sponsor states nothing, anywhere.** Searching the rules page,
the official Multiplier List and the Cabrillo guide for *round*, *nearest*,
*fraction*, *decimal*, *integer* and *whole* returns **no hits at all**, and
×1.5 on an odd points × multipliers product lands on a half. This app rounds
**down**, once, on the whole product — the direction that cannot overstate a
`CLAIMED-SCORE:`, and the same rule Vermont gets, where the sponsor at least has
its own idiom for it (rule 7(B)(f) rounds a fractional multiplier count down).
Recorded as an inference. If WARAC ever prints a worked example whose score
lands on a half, it settles this and supersedes the inference.

## 9. County-line rules

> "**Mobiles or portables may not sit on a county line.**"

→ `maxSimultaneousCounties: **1**`, forbidden outright. The third party to do so,
after ALQP and MNQP (and BCQP, which removes the category instead).

## 10. Valid bands

**No list is published.** The rules say only:

> "**All amateur bands and modes not prohibited for contesting may be used.** No
> Repeater QSO's."

The suggested-frequency table is what fixes the set, and it covers exactly ten
bands:

> CW: 1.820, 3.550, 7.050, 14.050, 21.050, 28.050
> Phone: 1.870, 3.860, 7.230, 14.260, 21.350, 28.400
> VHF: **6 meters** 50.140 / 52.530 · **2 meters** 146.550 · **1.25 meters**
> 223.520 · **70 cm** 446.025

**Ten bands:** `160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m, 1.25m, 70cm` — the
largest band list of any bundled party, and the second (after VTQP) to include
1.25 m. "Not prohibited for contesting" is the conventional exclusion of the WARC
bands (30/17/12) and 60 m, none of which appears in the table.

**Two bands beyond the schema, recorded:** the do-not-use calling-frequency list
names **906.50 and 1294.50 MHz** — 33 cm and 23 cm — which `Band` cannot express.
A VHF award category exists (*"50Mhz and above"*), so microwave contacts are
plausibly legal here and simply cannot be logged. The same shape as NYQP's
902 MHz/1.2 GHz/10 GHz gap.

## 11. Cabrillo `CONTEST:` header

**`WI-QSO-PARTY` — printed by the sponsor**, in its own Cabrillo guide:

```
CONTEST: WI-QSO-PARTY
```

Article 1's WA7BNM exception is not needed.

## 12. Categories

Single Operator Fixed · Single Operator Mobile · **Single Operator Rookie** ·
Multi Operator Fixed · Multi Operator Mobile · Multi-Xmtr/Multi-Op Fixed ·
Multi-Xmtr/Multi-Op Mobile. Power: QRP <5 W, Low 5–100 W, High >100 W.

The **Rookie** category is unusual and worth recording: *"No previous WIQP entry
other than in the Rookie category… May enter this category no more than twice and
entries must be in two consecutive years."*

Remote operation is explicitly a *pre-existing portable*, **not eligible for
bonus points**, and *"the transmitter location must be given as the sent
exchange."*

## 13. County list

**72 counties, uniform 3-letter codes**, from the sponsor's multiplier list.

Traps worth spot-checking — Wisconsin's clusters are dense:

1. **Three `Mar-` counties, and only one is `MAR`:** `MAR` Marathon, **`MRN`**
   Marinette, **`MRQ`** Marquette.
2. **Three `Gr-` counties:** `GRA` Grant, `GRE` Green, **`GRL` Green Lake** —
   and `GRE`/`GRL` are two different counties one letter apart.
3. **Six `W-` counties:** `WAL` Walworth, `WAS` Washington, **`WSB`** Washburn,
   `WAU` Waukesha, `WAP` Waupaca, **`WSR`** Waushara. Neither Washburn nor
   Waushara takes the naive form, and `WAS` belongs to Washington.
4. Multi-word names printed without punctuation: `FON` **Fond du Lac**, `LAC`
   **La Crosse**, `STC` **St Croix** (no period, as in MNQP's `STL` St Louis),
   `EAU` Eau Claire, `GRL` Green Lake.
5. `ONE` is Oneida — a code that reads as a number.

## 14. Engine shapes to watch

1. ~~**FRACTIONAL SCORE MULTIPLIERS — SECOND USER, so the repo's bar is met.**~~
   **Done 2026-07-28.** §8. VTQP's power factors are QRP ×2 / low ×1.5 / high
   ×1; WIQP's are **identical**, and neither was expressible in `[String: Int]`.
   The sketch shipped as written: `ScoreFactor` carries the factor as a rational
   rather than a `Double` so the final score stays exact, and
   `ScoreSnapshot.Figures` kept its whole-number key and gained
   `categoryFactorExact` beside it, since it is persisted to the iCloud archive
   and this was a stored-history migration as well as a schema change. Both VTQP
   and WIQP gained the field, each in its own commit (Article 9).
2. **`activatedCountyCount` cannot exclude the home county.** §7. WIQP pays 500
   "for each county that you operate from **outside your home county**"; the
   engine counts every county with ≥12 QSOs. Over-credits a Wisconsin
   mobile/portable who also works 12+ from home. Sketch: an optional
   `excludesHomeCounty: Bool` on the case. **In-state mobiles and portables
   only.**
3. **`workStation(.perBandMode)` cannot be band-limited.** §7. W9FK pays 100 per
   band/mode slot **below 50 MHz**; the engine counts 6 m and up too. Over-credits
   by 100 per VHF slot. Sketch: an optional band predicate on the case — or, more
   generally, the same "which bands does this rule apply to" shape a couple of
   other deferred gaps want.
4. **33 cm and 23 cm are unloggable.** §10. Shared with NYQP.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| phone 1, CW/digital 2 | `points` |
| "once per mode on each band" | `dupeScope: "bandMode"` |
| stated maxima of 72 / 135 | `countScope: "once"`, both sides |
| "Wisconsin may be counted as a state multiplier" | `homeStateCountsViaCounty: true` |
| `MD Maryland/(D.C.)` | `stateAliases {"DC": "MD"}` |
| DX logged as `DX`, no multiplier | `dxStyle: "token"`, `.dx` absent |
| "may not sit on a county line" | `maxSimultaneousCounties: 1` |
| no report in the exchange | `exchangeIncludesRST: false` |
| "Only Wisconsin stations may be worked" | `outStateWorksHomeStationsOnly: true` |
| 1800Z–0100Z, 15 March | `schedule` |

**`outStateWorksHomeStationsOnly` is stated inside the multiplier rule** — *"Only
Wisconsin stations may be worked"* — making WIQP the thirteenth party to state it
rather than imply it.

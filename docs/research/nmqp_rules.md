# New Mexico QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the document in §1.

**The first party this run whose power multiplier actually fits** — QRP ×5, Low
×2, High ×1, all whole numbers — so `scoreMultipliers` ships for the first time
since PAQP. VTQP and WIQP have been waiting on a fractional field; NMQP does not
need it.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **New Mexico QSO Party**, <https://www.newmexicoqsoparty.org> |
| **Rules** | `NMQP_Forms.pdf` — "2026 New Mexico QSO Party Form Packet", **Last modified: 09 April 2026** |
| Fetched | **2026-07-26** |

Banked verbatim: [`nmqp_rules_2026.txt`](nmqp_rules_2026.txt). One document
carries the rules, the county check sheet and the Cabrillo specification.

**The packet keeps its own change log**, which no other sponsor this run does,
and it earns its place:

> "**24 March:** Initial release… For 2026 only: New bonus points opportunity for
> working W1AW/5… New High Score – YL/XYL award… Removal of Outside New Mexico,
> Multi-Op category.
> **09 April:** Clarified rules around working W1AW/5 multiple times. **Reduced
> number of bonus points for working W1AW/5 from 500 to 250.**"

So the W1AW/5 bonus is **250, not 500**, and a source that captured the packet
between 24 March and 9 April would have it wrong. The generator asserts the 250.

The sponsor also asks readers to re-check: *"Please visit this page prior to the
start of NMQP to ensure you have downloaded the latest revision."*

## 2. Dates and times for 2026, in UTC

> "CONTEST PERIOD: **Second Saturday of April, 8:00 MDT (1400 UTC) to 20:00 MDT
> (0200 UTC). Duration: 12 hours** (full-time operation permitted)."

| Start | End | Length |
| --- | --- | --- |
| `2026-04-11T14:00:00Z` | `2026-04-12T02:00:00Z` | 12 h |

**Formula, UTC instants, local instants and duration, all in one sentence** — the
most self-checking date statement of the run. The second Saturday of April 2026
is the **11th** (the 4th is the first), and the sponsor's own home page confirms
*"April 11, 2026 (8:00am-8:00pm MDT)"*. NMQP shares the day with Missouri and
overlaps it for its whole 12 hours.

## 3. Exchange

> "New Mexico stations: **RS(T) + New Mexico county**
> Non-New Mexico stations: **RS(T) + State/Province/DXCC entity**"

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`.

**`dxStyle: "token"`, and the Cabrillo section is what settles it.** Rule 6 says
DX stations send a "DXCC entity", which reads like a prefix — but the packet's
log specification says the QTH field is *"three letter NM county abbreviation, or
two-letter State/Province abbreviation, or **"DX"**"*, and its sample log carries
`LY2ZZ 599 **DX**`. The literal token is what reaches the log, so it is what this
app parses. **That has a consequence** — see §12, limitation 1.

**FT8/FT4 are permitted but require manual editing**, which the sponsor spells
out at length:

> "For an FT8/FT4 QSO to be valid, it must include the required QSO exchange from
> both stations… QSOs that contain grid squares or signal reports instead of the
> required exchange **cannot be scored** by the New Mexico QSO Party's automated
> scoring software. Participants using FT8/FT4 must either use a mode that
> supports the required exchange (such as **JS8Call**) or **manually edit their
> logs prior to submission** by replacing signal reports with "599" and
> converting grid squares to the appropriate state, province, or DXCC entity."

That is the opposite of MSQP's approach one party earlier — MSQP made grid
squares a first-class exchange; NMQP requires them converted away. Both parties
allow FT8; neither can be logged natively.

## 4. QSO points by mode

> "Each Phone contact = **1** point · Each CW contact = **2** points · Each
> Digital contact = **2** points"

## 5. Multipliers, and the power multiplier

> "**Power multiplier** based on maximum power used: QRP (5 watts or less): **×5**
> · Low Power (> 5 – 150 watts): **×2** · High Power (> 150 watts): **×1**"

→ `scoreMultipliers: {power: {QRP: 5, LOW: 2, HIGH: 1}}` — **whole numbers, so
this ships**. ×5 for QRP is the largest score multiplier in the repo (MDC's QRP is
×3, NJQP's ×4). Note the shape is identical to VTQP's and WIQP's *except* that
their low-power factor is 1.5; NMQP's is 2, and that single difference is why this
one fits and those two do not.

> "**Location Multipliers for New Mexico participants**: Multiply QSO points by
> total of each different NM county worked (**up to 33**), **states worked (up to
> 50)**, Canadian provinces/territories worked (up to 13…) and DX entities worked.
> — Alaska and Hawaii count as state multipliers only; **District of Columbia (DC)
>   counts as Maryland**.
> — United States and Canada do not count as DX entity multipliers.
> — **Each multiplier may be counted ONLY ONCE, regardless of mode or band.**
>
> **Location Multipliers for Non-New Mexico Participants**: … NM county worked
> (up to 33). Each multiplier may be counted ONLY ONCE regardless of mode or band."

| | In-state (NM) | Out-of-state |
| --- | --- | --- |
| Classes | 33 counties + 50 states + 13 provinces + DX | **33 NM counties** |
| Scope | **once overall** | **once overall** |

→ `countScope: "once"` both sides.

- **`homeStateCountsViaCounty: true`** — *"states worked (**up to 50**)"*. Fifty,
  not forty-nine, so New Mexico is included; and NM stations send a county, so the
  token `NM` is never received. The arithmetic is the whole argument, exactly as
  it was for MNQP and NCQP in the opposite direction.
- **`stateAliases: {"DC": "MD"}`** — stated outright.
- The 13 are the standard list with `NL` spelled "Newfoundland-Labrador".

## 6. Bonus points

**Two, and both fit.**

> "**Mobile Operations Bonus** (for New Mexico mobile stations only): Add an
> additional **5,000 points** to the final score for every county from which at
> least **15 valid QSOs** were made."

→ `activatedCountyCount(minQSOs: 15, points: 5000)` — **by far the largest
activation bonus in the repo** (TnQP 500, OKQP 500, WIQP 500, VAQP 100, LAQP 50).

> "**W1AW/5 Bonus (new, for 2026 only)**: Add an additional **250 points**… for a
> valid contact with W1AW/5. **Bonus points are valid for one (1) W1AW/5 QSO
> only**, regardless of band, mode, or W1AW/5's county."

→ `workStation(call: "W1AW/5", points: 250, scope: "once")`. **2026-only**, like
VTQP's W1AW/1 rule, and recorded as such so a 2027 session deletes it.

The packet also handles the dupe interaction, and this app already behaves that
way:

> "W1AW/5 may be on the air from multiple New Mexico counties. Stations may work
> W1AW/5 again on the same band and mode, **only if W1AW/5 is operating from a
> different county**… Each county activation is considered a new station for QSO
> point credit; however, the W1AW/5 bonus may be claimed only once."

`DupeChecker` keys on `theirLoc`, so a county change is already a new QSO, and
`scope: .once` already pays the bonus once. Nothing special is needed.

> "SCORING — For non-mobile participants: Total = (Sum of QSO points from all
> bands **× power multiplier × location multiplier**) + W1AW/5 contact bonus"

That is `qsoPoints * multiplierCount * categoryFactor + bonusPoints` exactly.

## 7. County-line rules

> "…'a stationary mobile may operate on a County Line and contacts with the mobile
> can be used as credit for both counties.' … Furthermore, '**only one County Line
> at a time** can be run for [NMQP] credit. If the mobile is operating from the
> intersection of **three or more** USA Counties, **only two counties at a time
> may be counted** for the same contact.'"

→ `maxSimultaneousCounties: **2**`, stated with the number and with the
three-county case ruled out explicitly. County lines are defined by MARAC's
county-hunter rules by reference, as in NCQP and IDQP, with a 50-metre tolerance.

## 8. Valid bands

> "Contest bands: **160-10 meters, plus 6 and 2 meters**. Not permitted: **WARC
> bands, 60 meters, and bands above 2 meters**."

**Eight bands**, with both the inclusion and the exclusion stated — and 60 m named
separately from the WARC bands, which is the correct distinction and one several
sponsors blur.

## 9. Categories

Single Operator (one signal; 500-metre circle) · Multi-Operator (**New Mexico
only** — the 2026 change log records the removal of the Outside-NM Multi-Op
category) · Mobile, single- or multi-operator, per MARAC's definition ·
**Expedition** (portable, field-deployed, ≥30 QSOs to qualify). Power: QRP ≤5 W,
Low ≤150 W, High >150 W.

## 10. Cabrillo `CONTEST:` header

**`NM-QSO-PARTY` — printed by the sponsor** in its own sample log:

```
START-OF-LOG: v2.0
CONTEST: NM-QSO-PARTY
QSO: 14000 PH 2010-02-07 1501 N5ZGT 59 BER  NK5W   59 SAN
QSO: 14000 CW 2010-02-07 1507 N5ZGT 599 BER LY2ZZ 599 DX
```

Article 1's WA7BNM exception is not needed. The packet also specifies that NM
stations set `ARRL-SECTION: NM` / `LOCATION: NM` for the automated scorer.

## 11. County list

**33 counties, uniform 3-letter codes**, from the packet's own Check Sheet.

The trap is the `San`/`Santa` cluster, where the obvious code belongs to none of
them:

| Code | County |
| --- | --- |
| **`SAN`** | **Sandoval** — *not* San Juan, San Miguel or Santa Fe |
| `SJU` | San Juan |
| `SMI` | San Miguel |
| `SFE` | Santa Fe |

Also worth checking: `COL` Colfax against `CIB` Cibola; `LOS` Los Alamos, `RIO`
Rio Arriba, `DEB` De Baca and `DON` Dona Ana are two words each.

**The sponsor prints "Dona Ana"**, without the tilde of the official *Doña Ana*.
Shipped as printed, per the repo's practice with NHQP's "Merrimac", NCQP's
"Chowen" and MOQP's "St. Genevieve".

## 12. Engine shapes to watch

**Only one gap, and it is inherited rather than new** — this is the cleanest fit
of the run:

1. **DX collapses to one multiplier where the sponsor counts entities.** §3, §5.
   The rules count "DX entities worked" individually, but the log format carries
   the literal `DX`, so `dxStyle: "token"` yields exactly one. An NM entrant
   working ten DXCC entities is credited one multiplier instead of ten.
   **The sponsor's own automated scorer faces the same problem**, since the QTH
   field it reads is `DX` too — it must derive the entity from the callsign, which
   is precisely the DXCC-prefix table NHQP and MEQP already want. **Third user of
   that gap**, and the first where the sponsor's own log format is the cause.
   *Out-of-state entrants are unaffected: their only multipliers are NM counties.*

Everything else maps cleanly, and unusually much of it:

| Rule | Field |
| --- | --- |
| phone 1, CW 2, digital 2 | `points` |
| "only once per mode, per band" | `dupeScope: "bandMode"` |
| "ONLY ONCE, regardless of mode or band" | `countScope: "once"`, both sides |
| "states worked (up to 50)" | `homeStateCountsViaCounty: true` |
| "DC counts as Maryland" | `stateAliases {"DC": "MD"}` |
| **QRP ×5, Low ×2, High ×1** | **`scoreMultipliers.power`** |
| 5,000 per county with ≥15 QSOs | `activatedCountyCount(minQSOs: 15, points: 5000)` |
| W1AW/5, 250, once | `workStation(scope: "once")` |
| "only two counties at a time" | `maxSimultaneousCounties: 2` |
| 160–10 m plus 6 and 2 | `validBands` |

**`outStateWorksHomeStationsOnly` is stated in the Object** — *"Non-NM stations:
Work NM stations for NM counties only"* — the fifteenth party to state rather
than imply it.

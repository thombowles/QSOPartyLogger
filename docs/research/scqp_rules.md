# South Carolina QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the document in §1.

**The cleanest source yet:** one current-year PDF carries the rules, the county
list, the states, the provinces *and* the Cabrillo `CONTEST:` value. Nothing here
came from an archive, a secondary page or a registry.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **the SCQP Team**, <https://scqso.com> (Swamp Fox Contest Group among the sponsors) |
| Contact | `daveedmo@gmail.com` (operating plans; the rules name no rules address) |
| **Rules** | <https://scqso.com/wp-content/uploads/2026/02/SCQPRULES2024_0126.pdf> — header **`SOUTH CAROLINA QSO PARTY RULES (rev. 2.2.26)`** |
| Home page | <https://scqso.com/> — banner "SC QSO Party™ – FEBRUARY 28, 2026 @ 1500Z" |
| Log robot | scqso.com → "Log Submission"; **Cabrillo only, no paper logs** |
| Deadline | 14 days after the contest |
| Fetched | **2026-07-26** |

Banked verbatim: [`scqp_rules_2026.txt`](scqp_rules_2026.txt),
[`scqp_page.txt`](scqp_page.txt).

**A filename that lies, and a revision line that does not.** The PDF is served as
`SCQPRULES2024_0126.pdf`, which reads like a 2024 document. Its own header says
**`rev. 2.2.26`** — 2 February 2026 — and its contents carry the 2026 dates and
the 2026 bonus stations. **The revision line governs; the filename is a stale
upload name.** This is the mirror image of MNQP, where the *filename* was
honestly 2027 and the trap was that the sponsor no longer published the year
being built. Between them: never take a year from a URL.

## 2. Dates and times for 2026, in UTC

> "Begins at 1500Z on the **4th Saturday in February** and ends on the following
> Sunday at 0159Z. (**11 hours total**)." — rule 2

**One window ships:**

| Start | End | Length |
| --- | --- | --- |
| `2026-02-28T15:00:00Z` | `2026-03-01T02:00:00Z` | 11 h 00 m |

The sponsor's stated length settles the end instant, exactly as it did for MNQP
and BCQP: 1500Z → 0200Z is 11 hours, and the printed `0159Z` is last-minute
notation. February 2026's Saturdays are the 7th, 14th, 21st and **28th**, so the
4th Saturday is 28 February ✓ — which the home page states outright in its
banner, and which the State QSO Party Challenge calendar prints too.

**This is the only bundled party that crosses a month boundary**, and the only
one whose window ends in a different month from the one it starts in.

## 3. Exchange

Rule 5, complete:

> 5.1 **South Carolina Stations** — Signal report and county abbreviation.
> 5.2 **USA Stations Outside South Carolina** — Signal report and two-letter
> state abbreviation. **Note that Washington, D.C. is a multiplier for contest
> purposes. Puerto Rico, USVI, Guam, and other US territories are considered DX
> for contest purposes.**
> 5.3 **Canadian Stations** — Signal report and two-letter province/territory abbreviation.
> 5.4 **DX Stations** — Signal report and "**DX**" (not country).

| Role | Sends |
| --- | --- |
| **In-state (SC)** | RS(T) + one of the 46 county abbreviations |
| **Out-of-state US** | RS(T) + 2-letter state; **`DC` is its own multiplier** |
| **Canada** | RS(T) + province/territory |
| **DX** | RS(T) + the literal `DX` — *"not country"* |

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`,
`dxStyle: "token"` (and the sponsor spells out *why* the token: "not country").

**`DC` is a multiplier in its own right and must not be aliased** — the rules say
so twice (5.2 and 9.2.1) and list it in the states table. That puts SCQP with
MNQP and against VTQP/BCQP/MDC, which fold it into MD. Three parties in four have
now done it differently; there is no default worth assuming.

**US territories are DX here** (PR, USVI, Guam), which is the opposite of the
several parties that treat KH6/KL7 as states — though note SCQP says nothing
special about Alaska and Hawaii, which are simply among the 50 states.

## 4. QSO points — by **who was worked**, not by mode

This is the party's most distinctive rule and the one most easily got wrong.
Rules 9.1.1–9.1.4:

> **9.1.1 PHONE (South Carolina Stations)** — Each completed and valid PHONE
> contact with other South Carolina stations shall count as **two (2)** points.
> Each completed and valid phone contact with stations **outside** of South
> Carolina shall count as **four (4)** points.
> **9.1.2 CW or DIGITAL (South Carolina Stations)** — …with other South Carolina
> stations … **two (2)** points. …with stations outside of South Carolina …
> **four (4)** points.
> **9.1.3 PHONE (All Out-Of-State Stations)** — Each completed and valid PHONE
> contact with South Carolina stations shall count as **two (2)** points.
> **9.1.4 CW or DIGITAL (All Out-Of-State Stations)** — …**two (2)** points.

| | Contact with an **SC** station | Contact with a **non-SC** station |
| --- | --- | --- |
| SC entrant | 2 | **4** |
| Out-of-state entrant | 2 | *no credit at all* (§9.5) |

**Mode does not affect points anywhere.** Phone, CW and digital all pay the same;
what varies is who was worked. That is exactly `homeStationPoints`, the field
MEQP introduced:

- `points` = `{phone: 4, cw: 4, digital: 4}` — the table for a contact whose
  received location is *not* an SC county.
- `homeStationPoints` = `{phone: 2, cw: 2, digital: 2}` — the table for a contact
  with an SC station, recognised the only way the exchange allows: they sent a
  county.

Both sides fall out correctly without a second mechanism. An out-of-state entrant
only ever logs SC counties (rule 9.5 voids everything else), so every one of
their contacts resolves to `homeStationPoints` = 2 ✓. An SC entrant resolves to 2
for another SC station and 4 for a state, province or `DX` token ✓.

## 5. Dupe rule

> "Stations may be worked **ONCE per MODE per BAND** for QSO Points. For QSOs
> with SC Mobiles, also **per county**. There is no partial contact credit." — rule 9

→ `dupeScope: "bandMode"`, with a mobile's county change making a new QSO —
already how `DupeChecker` behaves, since `theirLoc` is part of the key.

**The digital-mode collapse is stated explicitly, and it matches this app
exactly:**

> "Note that for contest purposes, FT8, FT4, PSK, RTTY, JT65 or other digital
> modes shall be considered equivalent. **Thus a FT8/4 and RTTY contact on the
> same band with the same station is considered a dupe.**" — 9.1.2, repeated in 9.1.4

`ModeClass.digital` already treats all of those as one mode, so SCQP needs
nothing. Worth recording because it is the **exact opposite of VTQP**, which
splits RTTY out of the WSJT group and is one of the two parties driving the
mode-grouping engine gap. SCQP is the case for leaving the default alone.

## 6. Multipliers

> "**Multipliers are counted ONCE PER MODE PER BAND.**" — rule 9.2

**9.2.1 SC Stations:**
> 1. Each South Carolina county
> 2. Each USA state **including South Carolina** and Washington, D.C. **When
>    logging other SC stations, enter the SC County as the exchange (not SC).**
> 3. Each Canadian Province/Territory.
> 4. **DX contacts count for QSO points only.** Enter DX for the exchange.

**9.2.3 Non-SC Stations:**
> 1. Each SC county
> 2. SC Mobile stations, when they change counties, may be worked as a new station.

| | In-state (SC) | Out-of-state |
| --- | --- | --- |
| Classes | 46 counties + 50 states (incl. SC) + DC + 13 provinces | **46 SC counties only** |
| Scope | **once per band and mode** | **once per band and mode** |
| DX | **points only — no multiplier** | no multiplier |

→ `countScope: "perBandMode"` on both sides — the third party to use it, after
MEQP and BCQP. `inState.classes = [county, state, province]` with **no `.dx`**;
`outState.classes = [county]`.

**`homeStateCountsViaCounty: true`, and this is the clearest statement of that
rule anywhere in the repo.** 9.2.1 counts "Each USA state **including South
Carolina**" and then, in the same breath, tells you the token `SC` is never sent:
*"When logging other SC stations, enter the SC County as the exchange (not SC)."*
A multiplier that exists, is reachable only through a county, and whose own token
is forbidden — which is precisely what the field models.

Contrast the four parties before it. NHQP and MEQP and SDQP and ILQP and VTQP all
shipped `false` because nobody said either way; MNQP shipped `false` because the
sponsor said *"49 states (does not include Minnesota)"*; BCQP shipped `false`
because the enumeration listed BC with no path to it. **SCQP is the first of this
run to say yes outright**, and it is worth keeping as the reference wording.

In-state ceiling per band per mode: 46 counties + 51 state-class tokens (50
states including SC, plus DC) + 13 provinces = **110**.
Out-of-state ceiling: 46 × 8 bands × 3 modes = **1,104**.

**One multiplier kind is not modelled** — 9.2.2, for SC Mobile/Expedition
stations only:

> "3. **Each SC county activated.** At least one (1) QSO must be made from a
> county in order for it to count as activated."
> "Expedition stations that operate from more than one county will receive a
> multiplier (ONCE PER MODE PER BAND) for each county activated."

The repo has `activatedCountyCount` as a **bonus** rule (TnQP's 500 points per
county activated), not as a multiplier. See §14 — this is the deferred
"self-activation multipliers" gap acquiring its **second** user.

## 7. Bonus stations

**Three, and they need the scope this repo did not have.**

> "**Bonus Stations may be worked ONCE per BAND per MODE for bonus points.** You
> may work a bonus station more than once per band per mode for additional QSO
> points and multipliers. You can work mobile Bonus Stations when the mobile
> station changes counties.
>
> Example: You can work WW4SF/CHAR, WW4SF/GVIL, WW4SF/JASP and WW4SF/HORR on 40m
> CW, but **only the first contact with WW4SF on 40m CW will qualify for Bonus
> Station points**. Likewise for all three modes.
>
> **350 points - W4CAE** (Columbia Amateur Radio Club)
> **250 points - WW4SF** (Swamp Fox Contest Group)
> **250 points - K4YTZ** (York County Amateur Radio Society)" — rule 9.3

→ three `workStation` rules with `scope: "perBandMode"`, **a case added to
`BonusRule.WorkStationScope` in its own preceding commit** (Article 4/9). None of
`once`, `perMode` or `perQSO` is close: with 850 points available per band/mode
slot across 8 bands and 3 modes, `perMode` undercounts by a factor of eight and
`perQSO` pays every county a mobile bonus station is worked from — the very thing
the sponsor's example rules out.

> "Final Score: **Total QSO Points x Multipliers + Bonus Station Points**" — 9.4

which is `qsoPoints * multiplierCount + bonusPoints` exactly.

## 8. Final-score multipliers

**NONE.** Power (QRP ≤5 W / Low ≤100 W / High >100 W, rule 7) selects the award
category only; 9.4 has no power term. `scoreMultipliers` absent.

## 9. County-line / multi-county rules

> "'**County-line' contacts must appear in the log as separate contacts.**" — rule 12

County-line operation is **permitted**, and the sponsor's only requirement is the
logging shape — which `CountyLineExpander` already produces, since it turns one
entry into separate rows sharing a `groupID`.

**No limit is stated.** The rules cap nothing: not two, not four. Shipped on the
schema default of `maxSimultaneousCounties: 4`, which is this app's own maximum
rather than a sponsor's number, and recorded as an open question. Inventing a cap
of 2 would be no better founded, and would reject a legal entry.

## 10. Valid bands

> "The SCQP shall be conducted on the **160, 80, 40, 20, 15, 10, 6 and 2 meter
> bands only**." — rule 3

**Eight bands:** `160m, 80m, 40m, 20m, 15m, 10m, 6m, 2m`. The word "only" makes
this the most explicit band list of any party built this run — no derivation
needed, unlike VTQP (a prohibition) or BCQP/MNQP (a range plus an exclusion).

The suggested-frequency table (rule 11) lists seven bands, stopping at 6 m
(50.135 SSB / 50.095 CW); **2 m has no suggested frequency but is in rule 3**, so
the list is 8, not 7. Recorded so nobody trims it to match the table.

## 11. Categories

**Fixed** — Single Operator; Multi-Operator (Multi-Single / Multi-Multi); all
from a single fixed location. **Mobile** — Mobile Single, Mobile Multi-Operator,
each operating "from at least two (2) different South Carolina counties and
making at least one (1) contact from each county". **Expedition** — a portable,
field-day-type stationary setup, everything "within a 1000' diameter circle";
**SC stations only**.

Cabrillo headers are spelled out in rule 8: `CATEGORY-MODE` (SSB | CW | DIGITAL |
MIXED), `CATEGORY-OPERATOR` (SINGLE-OP | MULTI-OP | CHECKLOG), `CATEGORY-POWER`
(HIGH | LOW | QRP), `CATEGORY-STATION` (FIXED | MOBILE — *"EXPEDITION stations
use 'MOBILE'"*), `CATEGORY-TRANSMITTER` (ONE | TWO | UNLIMITED).

Assistance is unusually permissive: *"Use of spotting assistance including packet
clusters, reverse beacon networks, CW Skimmer, APRS telemetry, etc. is permitted
in all categories. **'Self-spotting' is also permitted.**"* — the opposite of
BCQP, which forbids self-spotting outright.

## 12. Cabrillo `CONTEST:` header

**`SC-QSO-PARTY` — printed by the sponsor**, in the full example log at rule 15:

```
START-OF-LOG: 3.0
CONTEST: SC-QSO-PARTY
CATEGORY-MODE: SSB
QSO: 14000 PH 2007-04-14 1813 KN4QD 59 RICH KI4HPX 59 RICH
QSO:  7000 CW 2007-04-15 2159 KN4QD 599 MARI W8CAR  599 OH
```

Article 1's WA7BNM exception is therefore not needed, as with BCQP. *(The sample
carries April 2007 dates — it was never re-dated — but the header line and the
exchange columns are what it is being read for.)*

## 13. County list

**46 counties, and the abbreviations are MIXED 3- and 4-character** — `LEE` is
three, every other is four. That is the third party to mix lengths, after the
Salmon Run, SDQP and ILQP, and the second (with ILQP) where the three-letter code
is Lee specifically.

Spelling anomalies and traps, flagged so nobody "fixes" them:

1. **`CHOU` is Calhoun**, not `CALH`. **The identical code means the identical
   county in ALQP** — Alabama also abbreviates Calhoun `CHOU`. Worth knowing, and
   worth not assuming: same code, same name, two different parties.
2. **Three "Ch" counties, none of them `CHER`:** `CHES` Chester, `CHFD`
   Chesterfield, **`CKEE` Cherokee**.
3. **`GVIL` Greenville vs `GRWD` Greenwood** — adjacent in the list, neither is
   `GREE`.
4. **`LNCS` Lancaster vs `LAUR` Laurens** — `LAN` belongs to neither.
5. **`MCOR` McCormick**, `ORNG` Orangeburg, `SUMT` Sumter, `UNIO` Union, `CLRN`
   Clarendon — none is the naive first four letters.
6. `LEE` is the only 3-character code, and the rules give no note about it (unlike
   ILQP, whose rules call their `LEE` out explicitly).

*(The same PDF's US-state table misspells Louisiana as "Lousiana". It is not
used — `MultClass.usStates` supplies the states — but it is noted so a future
reader does not treat that table as authoritative. Its province table is the
standard 13 with the standard `NL`.)*

## 14. Engine shapes to watch

1. **`BonusRule.WorkStationScope.perBandMode` — added in the commit immediately
   before this party** (Article 4: additive, its own commit, no party). §7 has
   the reasoning and the arithmetic. `BonusScopeTests` pins all four scopes
   against one another and proves the other three are unmoved.
2. **Self-activation multipliers — now a SECOND user, so the repo's own bar is
   met.** Rule 9.2.2 gives SC Mobile/Expedition stations "Each SC county
   activated" as a **multiplier**, once per mode per band. TnQP wants the same
   shape (its self-activation rule is the multiplier half of a bonus this repo
   *does* model). The worklist recorded TnQP as "the sole user so far … revisit
   if a second party wants it" — SCQP is that second party. Not built here:
   Article 9 keeps it out of a party commit, and it now wants its own, like the
   bonus scope did. An SC entrant who is *not* mobile or expedition — the normal
   case, and the only case for an out-of-state operator — is unaffected.
3. **`homeStationPoints` fits without modification** (§4). Second user after
   MEQP, and the first where the *higher* value is for out-of-area contacts —
   MEQP pays more for home-state ones. The field is symmetric, so nothing had to
   change; recorded because the direction is easy to reverse by reflex.
4. **`maxSimultaneousCounties` is the schema default, not a sponsor's number**
   (§9). Open question.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| 2 pts with SC stations / 4 pts otherwise | `homeStationPoints` + `points` |
| "ONCE per MODE per BAND" | `dupeScope: "bandMode"` |
| "Multipliers are counted ONCE PER MODE PER BAND" | `countScope: "perBandMode"`, both sides |
| "Each USA state including South Carolina … enter the SC County (not SC)" | `homeStateCountsViaCounty: true` |
| "Washington, D.C. is a multiplier" | no `stateAliases` |
| "'DX' (not country)", points only | `dxStyle: "token"`, `.dx` absent from classes |
| three bonus stations, once per band per mode | `bonuses` × 3, `scope: "perBandMode"` |
| 9.5 invalid contacts | `outStateWorksHomeStationsOnly: true` |
| 160/80/40/20/15/10/6/2 "only" | `validBands` |

**`outStateWorksHomeStationsOnly` is stated as its own numbered rule** —
9.5: *"Stations outside of South Carolina may not count contacts with
non-South Carolina stations or DX stations for contest credit or multipliers."*
The eleventh party to state it rather than imply it.

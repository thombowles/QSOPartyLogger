# British Columbia QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the four documents in §1.

**The first non-US party in this repo.** British Columbia has no counties, so the
"county" class carries **federal electoral districts** instead. §14 explains why
that needs no schema change and what it does need.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Orca DX and Contest Club** (`VA7ODX`) |
| Coordinator | `va7bec@gmail.com` |
| **Rules** | <http://www.orcadxcc.org/bcqp_rules.html> — footer **`Updated: Feb. 5, 2026 VA7ST`** |
| Multiplier list | <http://www.orcadxcc.org/bcqp_districts.html> — footer `Updated: July 4, 2025 VA7ST` |
| FAQ | <http://www.orcadxcc.org/bcqp_faq.html> |
| Summary sheet | <http://www.orcadxcc.org/content/bcqp_summary.pdf> |
| Log robot | <http://bcqp.contesting.com/bcqpsubmitlog.php> — Cabrillo required |
| Deadline | 14 days after the contest |
| Fetched | **2026-07-26** |

Banked verbatim next to this file: [`bcqp_rules_2026.txt`](bcqp_rules_2026.txt),
[`bcqp_districts.txt`](bcqp_districts.txt), [`bcqp_faq.txt`](bcqp_faq.txt),
[`bcqp_summary.txt`](bcqp_summary.txt).

**All four are current and consistent**, and unlike MNQP nothing here had to be
recovered from an archive. The FAQ is not decoration: it settles three rules the
rules page leaves implicit (§6, §8, §9), and its two worked examples confirm the
scoring formula arithmetically (§4).

## 2. Dates and times for 2026, in UTC

> "The contest comprises two segments. The first segment starts Saturday, Feb. 7,
> 2026 at 1600z, and runs for **12 hours** until 0359z Sunday Feb. 8, 2026. The
> second segment starts Sunday, ~~Feb. 2, 2025~~ at 1600z, and runs for **eight
> hours** until 2359z Sunday Feb. 8, 2026. Participants may operate during both
> segments or just one segment but not during the gap between the two segments.
> **Participants may operate all 20 hours of the contest.**"

**Two windows ship:**

| Segment | Start | End | Length |
| --- | --- | --- | --- |
| 1 | `2026-02-07T16:00:00Z` | `2026-02-08T04:00:00Z` | 12 h |
| 2 | `2026-02-08T16:00:00Z` | `2026-02-09T00:00:00Z` | 8 h |
| | | **total** | **20 h** |

**The sponsor's own arithmetic settles the end instants**, exactly as MNQP's did.
The printed `0359z`/`2359z` are last-minute notation; the *stated* lengths are 12
and 8 hours, which put the ends at 0400z and 2400z, and the sponsor then states
the total outright — *"all 20 hours"* — which only 12 + 8 satisfies. The page's
own headline agrees (`Starts 1600z Saturday, Feb. 7 -- Ends 0359z Sunday, Feb.
8`), and the State QSO Party Challenge calendar prints the same pair.

**A stale-date typo, recorded so nobody follows it:** the second segment's
sentence begins *"starts Sunday, **Feb. 2, 2025** at 1600z"*. Every other
statement — the page headline, the same sentence's own end instant ("2359z Sunday
Feb. 8, 2026"), and the FAQ's formula — says **Sunday 8 February 2026**. This is
the same class of error as MEQP's misprinted contest year, and the same
resolution: the surrounding document outvotes the slip.

The formula, from the FAQ: *"The first Saturday and Sunday of February"* → 7–8
February 2026 ✓.

## 3. Exchange

> "British Columbia stations send: RS(T) and District (three letter abbreviation)
> Non-British Columbia stations send: RS(T) and state/province/territory or DX.
> **Note: Hawaii and Alaska should be included under state, not DX.** (Examples:
> enter a QSO from Hawaii as "59 HI" and a QSO from Japan as "59 DX"."

| Role | Sends |
| --- | --- |
| **In-province (BC)** | RS(T) + one of the 43 electoral-district codes |
| **Out-of-province** | RS(T) + state / province / territory, **or the literal `DX`** |
| **Alaska and Hawaii** | `AK` / `HI` — explicitly **states, not DX** |

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`,
`dxStyle: "token"`.

`DX` is a single literal token here, and it is **worth no multiplier at all**
(§6) — so the token style is right for a second, stronger reason than usual:
there is nothing to distinguish between DXCC entities *for*.

**"Maryland and DC are lumped together as MD"** (rules, MULTIPLIERS) →
`stateAliases: {"DC": "MD"}`. The sponsor's own US-state table corroborates it
structurally: it lists **50 rows and has no DC row at all**.

## 4. QSO points by mode

> "2 points for Phone QSOs / 4 points for CW QSOs" — rules, QSO POINTS

| Mode | Points |
| --- | --- |
| Phone | 2 |
| CW | **4** |
| Digital | n/a — not a legal mode (§10) |

**CW at 4 points is the highest of any bundled party**, ahead of VTQP's 3.

The FAQ restates it and gives two worked examples, which confirm the whole
scoring shape including where the bonus lands:

> "((100 x 4) x 33) + (5 x 20) = 13,300"
> "(((25 x 4) + (25 x 2)) x 50) + (6 x 20) = ((100+50) x 50)) + 120 = 7,620"

That is exactly `qsoPoints * multiplierCount + bonusPoints`, which is what
`ScoreEngine` computes. Both examples are asserted by the generator, and the
second is reproduced as a test.

## 5. Dupe rule

> "The same station may be worked for QSO points on each band on CW and Phone."

→ `dupeScope: "bandMode"`.

No mobile or rover category exists (§9), so there is no county-change case to
consider — the one respect in which this party is simpler than every other.

## 6. Multipliers

> "For BC stations: 43 British Columbia electoral districts (see multiplier
> list); 13 Canadian provinces/territories: NL, PE, NS, NB, QC, ON, MB, SK, AB,
> BC, YT, NT, NU; and US states, including Hawaii and Alaska. Maryland and DC are
> lumped together as MD.
> For non-BC stations: 43 British Columbia electoral districts (see multiplier list).
> **Multipliers can be counted only once per band and mode.** Example: A mixed
> mode op can count DEL on CW 20 and Phone 20 as well as CW 40 and Phone 40, etc."

And the FAQ, which adds the rule the rules page omits:

> "For BC stations: 43 BC federal electoral districts, Canadian provinces and
> U.S. states. **DX contacts are worth QSO points but do not provide a
> multiplier.**
> Stations outside BC: 43 BC federal electoral districts."

| | In-province (BC) | Out-of-province |
| --- | --- | --- |
| Classes | 43 districts + Canadian provinces + US states | **43 districts only** |
| Scope | **once per band *and* mode** | **once per band *and* mode** |
| DX | **no multiplier** — points only | no multiplier |

→ `countScope: "perBandMode"` on both sides — only the second party to use it
after MEQP. `inState.classes = [county, state, province]` with **no `.dx`**, and
`outState.classes = [county]`.

**The DX exclusion is stated only in the FAQ**, and it matters: without it a BC
entrant would gain a phantom multiplier per band per mode. It is the clearest
case yet for reading a sponsor's secondary pages rather than only the rules.

Out-of-province ceiling: 43 × 6 bands × 2 modes = **516**.
In-province ceiling: 43 + 50 + 12 = **105** per band per mode (see below).

### Is British Columbia itself a multiplier for BC entrants? — OPEN QUESTION

**Three sponsor documents list `BC` among the countable provinces** — the rules'
enumeration above, the summary sheet's bracketed list (*"…AB (VE6/VA6), **BC
(VE7/VA7)**, NT(VE8)…"*), and the FAQ's "Canadian provinces". And yet **no BC
station can ever send the token `BC`**: the exchange from British Columbia is a
district, always, and the FAQ tells an operator who does not know their district
to look it up rather than fall back to the province.

So the enumeration lists a multiplier with no path to it. Two readings:

1. The lists are **reference boilerplate** — the standard 13 with their prefixes,
   printed so an operator can recognise `VE7` as BC — and BC is simply
   unreachable in practice. A log checker computing multipliers from received
   exchanges would never see `BC`.
2. The sponsor means a BC district **also** yields the BC province multiplier,
   which is what `homeStateCountsViaCounty: true` models.

**Shipped as reading 1**: `homeStateCountsViaCounty: false`, and `provinces` is
supplied as **the 12 without BC**, so that `BC` is not a loggable token. This
follows the worklist's recurring judgement call 5 — banked research has twice
mislabelled this flag, and the flag means the narrow thing, not "the home
region appears in a list". It is also the call made for NHQP, MEQP, SDQP, ILQP
and VTQP. If reading 2 is right, a BC entrant is one multiplier short per band
per mode; one email to `va7bec@gmail.com` settles it.

**`provinces` must be overridden, not left to default.** The default list is the
standard 13 *including* BC, and `validOutStateTokens` unions `provinces` in
**after** subtracting `excludedStateTokens` — so the default `excludedStateTokens
= [homeState] = ["BC"]` cannot remove it. Supplying 12 is the only way to keep
`BC` off the loggable list.

## 7. Bonus stations and bonus points

**One.**

> "Any QSO with the Orca DXCC station, **VA7ODX**, will be worth an additional
> **20 points**. Bonus points are added after calculating QSO points and location
> multipliers." — rules
>
> "**Each** QSO with VA7ODX will add 20 points to your score AFTER all other
> calculations." — FAQ

→ `workStation(call: "VA7ODX", points: 20, scope: "perQSO")`. The FAQ's examples
put it beyond doubt — *"You had 5 QSOs with VA7ODX … + (5 x 20)"* — and the
placement "after all other calculations" is exactly where `ScoreEngine` adds
`bonusPoints`.

## 8. Final-score multipliers

**NONE**, and the FAQ says so in three words:

> "**There is no power multiple.**"

> "Total = (QSO points from all bands X total location multipliers) plus bonus
> station points" — rules, SCORING

`scoreMultipliers` absent. Power (QRP ≤5 W / Low ≤100 W / High >100 W) selects
the award category only.

## 9. County-line / multi-district rules

**Not applicable, and the sponsor explains why rather than merely omitting it:**

> "**Is there a mobile or rover category?** No. Driving around to activate
> multiple districts in BCQP isn't a particularly practical or safe option for
> operating in BCQP due to weather conditions in February — still lots of snow in
> many areas — as well as the fact that federal electoral districts beyond the
> Lower Mainland and Vancouver Island are vast, sparsely populated and generally
> mountainous." — FAQ

→ `maxSimultaneousCounties: **1**`. This is **backed by rule text rather than by
silence**: there is no mobile or rover category at all, so no station may claim
two districts. ALQP and MNQP forbid line-sitting explicitly; BCQP removes the
category that would need it.

## 10. Valid bands

> "Contest bands: 160m to 10m, no WARC bands." — rules, FREQUENCIES & MODES
> "(No WARC bands)" — FAQ, categories

**Six bands:** `160m, 80m, 40m, 20m, 15m, 10m` — HF only, no VHF/UHF, the same
shape as MNQP.

The sponsor's suggested-frequency table has exactly one CW and one phone
frequency for each of those six bands and no others, which fixes the count:

> CW — 1815, 3535, 7035, 14035, 21035, 28035 kHz
> Phone — 1845, 3850, 7230, 14250, 21300, 28490 kHz

> "Contest modes: Phone and CW" → `allowedModes: ["phone", "cw"]`. No digital.

## 11. Categories

> "Single-Operator, All Bands (SOAB) / Multi-Operator, All Bands (Multi-Multi or
> Multi-Single). Modes: CW, Phone, Mixed. Power: QRP - 5 watts or less; Low - up
> to 100 watts; High - over 100 watts."

No mobile, no rover, no single-band category (*"You may operate on all bands, or
just one, though there is no single-band category"*). The Cabrillo `CATEGORY:`
line in the sponsor's sample is `SINGLE-OP ALL LOW MIX`.

Assistance: *"Use of packet spots, Skimmer is allowed in all classes. Requests to
be spotted or **self-spotting is prohibited** in all classes."* — worth knowing,
since this app can post spots to the hub.

## 12. Cabrillo `CONTEST:` header

**`BC-QSO-PARTY` — and the sponsor prints it itself**, so Article 1's WA7BNM
exception is not needed here. From the sample log on the rules page:

```
START-OF-LOG: 3.0
ARRL-SECTION: BC
CALLSIGN: VA7ODX
CONTEST: BC-QSO-PARTY
CATEGORY: SINGLE-OP ALL LOW MIX
QSO: 14035 CW 2018-02-04 1601 VA7ODX 599 NWB K7CUL 599 AZ
```

*(The sample predates the 2025 redistribution and uses `NWB`, which is not one of
the current 43 codes — the sample was not regenerated when the districts changed.
Harmless, but noted so nobody treats the sample as a district source.)*

The sample's QSO lines confirm the exchange columns are RS(T) + location, which
is what this app already exports.

## 13. District list ("counties")

**43 federal electoral districts, uniform 3-letter codes**, from the sponsor's
multiplier page.

> "British Columbia does not have counties — the typical multiplier in QSO
> parties. Therefore, in BCQP, we have opted to use federal electoral districts.
> These districts, or ridings, are not demarcated by signposts and are not part of
> any street addresses. **A redrawing of the electoral map for the October 2025
> election gave BC 43 federal electoral districts.** For BCQP purposes — and only
> for BCQP purposes — each district has been given a three-letter abbreviation."
> — FAQ

> "Note that these districts **came into effect in 2025 and are used for the 2026
> BCQP** and until further notice." — multiplier page

**This list is new.** It is not the pre-2025 set, which is why the rules page's
own Cabrillo sample still shows a retired code (§12). Any older BCQP district
list found elsewhere is wrong for 2026.

Spelling anomalies flagged, so nobody "fixes" them later — **all three are the
sponsor's, and all three ship as printed**:

1. **`KSC` — "Kamloops-Shuwswap-Central Rockies."** The place is Shuswap; the
   sponsor prints *Shuwswap*.
2. **`SSW` — "Similkameen-South Okangan-West Kootenay."** The place is Okanagan;
   the sponsor prints *Okangan*.
3. **`RCM` — "Richmond Center-Marpole"**, with the US spelling *Center*; Elections
   Canada uses *Centre*. (The sponsor writes *Centre* for `SUC` Surrey Centre in
   the same list, so it is inconsistent with itself.)

Codes worth spot-checking because they collide or mislead:

- **`CKS` Columbia-Kootenay-Southern Rockies vs `KSC` Kamloops-Shuwswap-Central
  Rockies** — an anagram pair, both ending "Rockies", both starting from a
  K-word. The single worst trap in the list.
- **`KTN` Kamloops-Thompson-Nicola vs `KSC`** — two Kamloops districts.
- **Seven `VA*` codes** — `VAC` Vancouver Centre, `VAE` Vancouver East, `VAG`
  Vancouver Granville, `VAK` Vancouver Kingsway, `VAQ` Vancouver Quadra, plus
  `VSB` Vancouver Fraserview-South Burnaby and `VIC` Victoria. `VAN` is **not** a
  code.
- **`BUC` Burnaby Central vs `BNS` Burnaby North-Seymour** — neither is `BUR`.
- **`SUC` Surrey Centre, `SUN` Surrey Newton, `SWR` South Surrey-White Rock** —
  three Surreys, one of which does not start `SU`.

## 14. Engine shapes to watch

**This party needs no schema change**, which is the main finding. A province with
districts instead of counties fits the existing model because nothing in the
schema requires `homeState` to be a *US* state or the county class to be a
*county*: `validate()` only requires two characters, and `homeState` is used for
UI labels, the ADIF `state`/`my_state` fields, the Cabrillo in-state location, and
`homeStateCountsViaCounty`. `"BC"` is correct in every one of those.

Four things to watch:

1. **`provinces` MUST be overridden to the 12 without BC.** See §6. Left to
   default, `BC` is a loggable token that no BC station can ever send, because
   `validOutStateTokens` unions `provinces` in after subtracting
   `excludedStateTokens`. This is the first party to need a `provinces` override
   for a reason other than the sponsor counting a short list (OhQP's 11).
2. **`inState.classes` omits `.dx`** — the FAQ's *"DX contacts are worth QSO
   points but do not provide a multiplier"*. First bundled party where DX is
   loggable, scores points, and multiplies nothing.
3. **ADIF `cnty` will read `BC,<district name>`.** `AdifExporter` writes
   `field("cnty", "\(party.homeState),\(countyName)")`, which is ADIF's
   `State,County` shape for a US secondary administrative subdivision. BC
   electoral districts are not in ADIF's enumeration and are not counties at all,
   so this field is well-formed but not meaningful to an ADIF consumer. **Cabrillo
   — the format the sponsor actually requires — is unaffected**, since it carries
   the raw exchange token. Recorded as a known limitation rather than fixed: the
   fix is an ADIF-subdivision-kind field, and no other party wants one yet.
4. **Self-spotting is prohibited in all classes**, while this app can post spots
   to qsopartyhub. Not a scoring gap and not something the app should enforce, but
   worth an operator-facing note.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| Phone 2, CW 4 | `points {phone: 2, cw: 4, digital: 4}` |
| "worked … on each band on CW and Phone" | `dupeScope: "bandMode"` |
| "only once per band and mode" | `countScope: "perBandMode"`, both sides |
| "Maryland and DC are lumped together as MD" | `stateAliases {"DC": "MD"}` |
| "or DX", worth no multiplier | `dxStyle: "token"`, `.dx` absent from classes |
| no mobile or rover category | `maxSimultaneousCounties: 1` |
| VA7ODX +20 per QSO | `bonuses: [workStation … perQSO]` |
| "outside BC to work only BC stations" | `outStateWorksHomeStationsOnly: true` |
| two segments, 12 h + 8 h | `schedule` |

**`outStateWorksHomeStationsOnly` is the party's first line** — *"Stations
outside British Columbia to work only BC stations in the 43 BC Federal Electoral
Districts. Stations in BC to work anyone, anywhere."* — and the FAQ repeats it
(*"Stations outside BC must find VE7/VA7s"*). The tenth party to state it rather
than imply it.

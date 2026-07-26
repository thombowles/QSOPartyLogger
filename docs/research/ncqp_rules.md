# North Carolina QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The party with the most unmodellable scoring in the repo.** Two of its rules —
the 10× "Rarest of NC" QSO points and the five-county sweep — move every
entrant's score, in-state and out, and neither fits the schema. §14 is the
important section here.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **North Carolina QSO Party Committee**, <http://www.ncqsoparty.org> |
| **Rules** | <http://ncqsoparty.org/wp-content/uploads/2025/10/Rules_2026_251013.pdf> — "2026 North Carolina QSO Party Contest Rules", **`Updated 10/13/2025`** |
| County abbreviations | <http://ncqsoparty.org/wp-content/uploads/2022/11/NCQP_Abbreviations_221121.pdf> — dated `11/21/22`, still the sheet the 2026 rules page links |
| Log robot | ncqsoparty.org → "Logs"; **Cabrillo only, paper no longer accepted** |
| Deadline | 2026-03-15 |
| Fetched | **2026-07-26** |

Banked verbatim: [`ncqp_rules_2026.txt`](ncqp_rules_2026.txt),
[`ncqp_counties.txt`](ncqp_counties.txt), and
[`ncqp_abbreviations.html`](ncqp_abbreviations.html) — see §13 for why the last
one exists.

Both documents are current for 2026: the rules are dated after the 2026
announcement, and the abbreviation sheet is the one the 2026 rules page serves.
Nothing here came from an archive.

## 2. Dates and times for 2026, in UTC

> "**1500 UTC March 1 to 0100 UTC March 2, 2026.** (10 am to 8 pm EST on March 1,
> 2026). All stations may operate the entire contest period." — Contest Period

| Start | End | Length |
| --- | --- | --- |
| `2026-03-01T15:00:00Z` | `2026-03-02T01:00:00Z` | 10 h 00 m |

**No arithmetic needed, and no last-minute notation to resolve** — the sponsor
prints the end instant as a round `0100 UTC`, unlike MNQP's `2359`, BCQP's
`0359` or SCQP's `0159`. The local anchors confirm it: EST is UTC−5, so 1500Z =
10 am ✓ and 0100Z (2 March) = 8 pm on 1 March ✓.

**NCQP is a Sunday-only party**, and the second one in the repo after ILQP.
Sunday 1 March 2026 is the day after SCQP ends — the two are back-to-back and
overlap by nothing.

## 3. Exchange

> "North Carolina (NC) stations work everyone, send **call sign and NC county**.
> Use county abbreviations as needed. Stations outside of North Carolina (Non-NC)
> work NC stations only. Send **call sign and state/province, or "DX"**. Use
> abbreviations as needed. **Sending signal report (i.e., 59) is optional.**"

| Role | Sends |
| --- | --- |
| **In-state (NC)** | call sign + one of the 100 NC county codes |
| **Out-of-state** | call sign + state/province, **or the literal `DX`** |

→ **`exchangeIncludesRST: false`.** The report is explicitly *optional*, and the
scoring section's definition of a valid QSO leaves it out entirely: *"A valid QSO
logged for award credit consists of date, time, mode, call sign, and location as
described in Exchange above."* NCQP is the third party to drop the report, after
MDC (call + location) and MNQP (name + location) — and unlike MNQP it puts
nothing in its place, so there is **no missing field here**: call + location is
exactly what this app logs.

→ `dxStyle: "token"`. "Any location not listed above is considered DX. This
includes US Territories, Mexican provinces, and DXCC countries."

## 4. QSO points by mode

> "Phone - 2 points each / CW - 3 points each / **Digital - 5 points each**"

| Mode | Points |
| --- | --- |
| Phone | 2 |
| CW | 3 |
| Digital | **5** |

**The only bundled party where digital outscores CW**, and by a wide margin.
Every other party pays digital at or below the CW rate.

> "It is permissible to work the same station on each mode (Phone, CW, Digital)
> on each band for credit."

**FT8 and FT4 are excluded from the main contest**, and this is not a nuance:

> "Digital – Except for FT-8/4 as noted below in Weak Signal Showcase, all other
> digital modes are allowed and considered one mode. (**Note: QSO's made using
> FT-8/4 should not be included.**)"
>
> "**DO NOT INCLUDE FT-8/4 QSOS in the regular Cabrillo log.**"

FT8/FT4 belong to a separate, separately-scored **Weak Signal Showcase** with its
own ADIF log, its own grid-square multipliers and its own awards. That event is
out of scope for this party definition — it is not the NCQP contest — and is
recorded in `notes` so an operator does not put those QSOs in the wrong log.

## 5. Dupe rule

Worked once per band per mode → `dupeScope: "bandMode"`.

> "Mobile stations that choose to move to a new county may work everyone again
> for QSO credit. If returning to a previously activated county, only new
> stations, respective of band and mode, not previously worked from there, may be
> counted as QSO credit."

A county change makes a new QSO, which is already how `DupeChecker` behaves.

## 6. Multipliers

> "**NC participants:** Work 100 North Carolina Counties, **49 US States (not
> NC)** plus DC, 13 Canadian Provinces/Territories (AB, BC, MB, NB, NL, NS, NT,
> NU, ON, PE, QC, SK, and YT), **plus one DX. 164 total possible.**"
>
> "**Non-NC participants:** Work stations in 100 North Carolina Counties."
>
> "**Count each multiplier worked only once across all modes, bands, and
> operating location.**"

| | In-state (NC) | Out-of-state |
| --- | --- | --- |
| Classes | 100 counties + 49 states + DC + 13 provinces + 1 DX | **100 NC counties only** |
| Scope | **once overall** | **once overall** |
| Stated total | **164** | 100 |

→ `countScope: "once"` on both sides; `inState.classes = [county, state,
province, dx]`; `outState.classes = [county]`.

**The sponsor's own total reconciles exactly, and pins two choices:**

```
100 counties
+ 50 state-class tokens  (acceptedStateTokens = 50 states ∪ {DC}, less
                          excludedStateTokens = {NC}  →  49 states + DC)
+ 13 provinces
+  1 DX
= 164  ✓
```

- *"49 US States (**not NC**)"* → `homeStateCountsViaCounty: false`, stated
  outright in the negative, as MNQP does and the opposite of SCQP.
- *"plus **one** DX"* → the token style gives exactly one `DX` value however many
  entities are worked, so no cap is needed. `.dx` **is** a class here, unlike
  BCQP and SCQP where DX multiplies nothing.
- DC is counted with the states and is **not** aliased.

**One multiplier rule is not modelled** — the self-activation provision:

> "Note: **NC stations may include the county from which operation takes place in
> the Multiplier count regardless of whether any QSOs are logged from that same
> county.** This includes Mobile and Portable stations where operations may take
> place in more than one county. In that case this provision is applied to each
> county activated where at least one QSO was completed."

This is the **third** user of the deferred self-activation-multiplier gap, after
TnQP and SCQP — and the broadest form yet, since a fixed NC station's own county
counts with *no* QSOs from it at all. See §14.

## 7. Bonus QSO points — the "Rarest of NC", and the biggest gap here

> "Ten NC Counties designated below as "Rarest of NC". A QSO with someone in one
> of these counties will be scored **10X QSO points** as follows:
> Phone - 20 points each / CW – 30 points each / Digital - 50 points each
> **Note: These points are added to the rest of the regular QSO Points prior to
> MULT multiplication so they have a significant positive effect on the final
> score.**"

| County | Code |
| --- | --- |
| Cabarrus | `CAB` |
| Graham | `GRM` |
| Vance | `VAN` |
| Macon | `MAC` |
| Davie | `DAV` |
| Currituck | `CUR` |
| Pamlico | `PAM` |
| Alleghany | `ALL` |
| Person | `PER` |
| Caswell | `CAS` |

**Nothing in the schema pays points by county.** `PointsTable` is keyed by mode
alone, and `BonusRule` adds *after* multiplication — which the sponsor
specifically says this is not. See §14, limitation 1.

## 8. Bonus points and final-score multipliers

**A sweep bonus, keyed on a named subset:**

> "If at least one QSO is made with a station in **five of the "Rarest of NC"
> counties, 500 additional bonus points** are added to the score **after
> multiplication**. This would constitute a sweep."

`BonusRule.sweepTiers` exists and adds after multiplication in the right place —
but it counts `workedValues(.county).count`, i.e. *any* five counties, not five
of a named ten. Shipping it would pay the 500 to almost every log. See §14,
limitation 2.

**No power multiplier.** Power selects the award class only.

> "**Final Score:** Multiply the total (QSO points plus Bonus QSO Points) times
> the total multiplier value. Add bonus points to score (as applicable) after the
> multiplication."

`ScoreEngine`'s `qsoPoints * multiplierCount + bonusPoints` is the right *shape*;
what it cannot do is get the right `qsoPoints` (§7) or the right `bonusPoints`
(here).

## 9. County-line rules

> "A Mobile (while stationary,) Portable, or Expedition may operate on a county
> line and contacts can be used as credit for two counties. **A maximum of two
> counties may be worked simultaneously** under this provision."
>
> "A two county QSO **must be logged as separate QSOs with two lines in the log**,
> one for each of the two counties."

→ `maxSimultaneousCounties: **2**`, stated outright, and the required logging
shape is exactly what `CountyLineExpander` produces.

The sponsor delegates the definition of a county line to a third party, which is
unusual enough to record: *"The methods to determine the county line are dictated
by MARAC County Hunter rules… Note that this reference to MARAC is officially
part of these rules."*

## 10. Valid bands

> "Operate on **80/75, 40, 20, 15, 10, 6, and 2 meters. No 160, WARC, or above 2
> meters.**"

**Seven bands:** `80m, 40m, 20m, 15m, 10m, 6m, 2m`.

**No 160 m** — the only bundled party that runs 80 m and up while excluding 160,
and the sponsor names the exclusion explicitly rather than leaving it to a range.
No WARC, nothing above 2 m. The suggested-frequency list covers exactly these
seven bands.

## 11. Categories

**Single-Op** (one fixed location; QRP / Low / High) · **Multi-Op** (≤2
simultaneous signals, one location, Mixed only, High or Low) · **Mobile**
(self-contained vehicle, Mixed Low only) · **Portable** (temporary stationary,
Mixed Low only) · **Expedition** (as Portable but one fixed location all
contest).

Power: QRP ≤5 W CW/digital or 10 W PEP phone; Low ≤150 W; High legal limit.

Cabrillo headers are listed in the rules: `CATEGORY-OPERATOR` (Single-Op,
Multi-Op, Mobile, Portable, Expedition, Checklog), `CATEGORY-MODE` (CW, SSB,
MIXED), `CATEGORY-POWER` (HIGH, LOW, QRP), plus `ARRL-SECTION`, `ADDRESS`,
`EMAIL`, `OPERATORS`.

Assistance is unrestricted: *"Use of spotting networks, nets, Packet Cluster,
Skimmer, RBN, or other assistance is allowed in all categories."*

## 12. Cabrillo `CONTEST:` header

**`NC-QSO-PARTY`** — from the WA7BNM Cabrillo name registry
(<https://www.contestcalendar.com/cabnames.php>, fetched 2026-07-26), Article 1's
codified exception, **because the sponsor prints no `CONTEST:` value**. Its rules
enumerate the `CATEGORY-*` headers an entrant must set and simply omit `CONTEST:`
— so unlike BCQP and SCQP, this one does rest on the registry.

## 13. County list — and why it is generated from colour

**100 counties, uniform 3-letter codes.**

The sponsor's abbreviation sheet does not print the code beside the name. It
prints the county name with **the code picked out in dark red**, and says so:

> "North Carolina QSO Party Abbreviations
> **(Abbreviation in dark red capital letters: i.e. CAPS)**"

So `CABarrus` is `CAB`, `GRahaM` is `GRM`, `DaViDson` is `DVD`, `PErQuimans` is
`PEQ`, `WiLKes` is `WLK`. Ten of these are confirmed independently by the rules
PDF, which prints the "Rarest of NC" codes in plain text — `CAB GRM VAN MAC DAV
CUR PAM ALL PER CAS` — and all ten agree with the colour reading. That is the
cross-check Article 2 wants, and `gen_ncqp.py` asserts it.

**Case alone is not sufficient, and one county proves it.** `NEW Hanover` has a
capital `H`, so a case-based parse yields `NEWH` — four characters, and wrong.
Reading the colour shows `NEW` in `#cc0000` and ` Hanover` in black: the code is
**`NEW`**, and every code in the party is three letters.

The generator therefore parses [`ncqp_abbreviations.html`](ncqp_abbreviations.html)
— `pdftohtml -c` output of the sponsor's own PDF, which preserves the colour —
and takes the `#cc0000` runs as the code and the full run sequence as the name.
The plain-text extraction is committed alongside it for auditing, but it is not
what is parsed.

**The code comes from the colour; the name comes from the plain text.** They are
zipped in row-major order and the counts must match. This split is necessary
because `pdftohtml` pads every run with `&#160;` on both sides, which makes a run
boundary *inside* a word (`CAB` + `arrus`) indistinguishable from the real space
in `NEW Hanover` — so the colour file cannot be trusted for spacing, and the
plain text cannot be trusted for the code.

Names need one repair and carry one sponsor error:

- `MCDowell` title-cases to "Mcdowell" and must be **`McDowell`**. The only such
  name, and the generator asserts it.
- **The sheet misspells Chowan as `CHOwen`.** Shipped as printed — the same call
  the repo makes for NHQP's "Merrimac" — because the *code* `CHO` is unaffected
  and the note is what stops someone "fixing" it later. The generator asserts
  both that the shipped name is "Chowen" and that the source sheet still says so,
  so a corrected sheet is noticed rather than silently absorbed.

**Independent validation of the whole parse:** 99 of the 100 names produced match
the real North Carolina county list exactly, and the hundredth is the sponsor's
typo above. Nothing else is off by a letter.

Traps worth spot-checking:

1. **`DVD` Davidson** — three non-adjacent capitals inside one word, and `DAV`
   belongs to **Davie**, a different county *and* one of the ten rare ones.
   Getting these two wrong swaps a normal county for a 10× county.
2. **`GRM` Graham vs `GRA` Granville** — `GRA` is not Graham.
3. **`PEQ` Perquimans vs `PER` Person** — `PER` is one of the rare ten.
4. **`CHO` Chowan, `CHA` Chatham, `CHE` Cherokee** — three `Ch` counties.
5. **`WLK` Wilkes** — not `WIL`; `WIL` is not a code at all (Wilson is `WIL`…
   check: `WILson` → `WIL`, so `WIL` **is** Wilson and `WLK` is Wilkes).
6. **`NEW` New Hanover** — the colour case above.
7. **`ALL` Alleghany vs `ALA` Alamance vs `ALE` Alexander** — and `ALL` is rare.

## 14. Engine shapes to watch

**Three gaps, and the first two are the largest scoring gaps in the repo** —
larger than VTQP's ×1.5 power multiplier, because they affect *every* entrant
rather than one power class, and because they compound with the multiplier.

1. **NO POINTS-BY-COUNTY: the "Rarest of NC" 10× is not applied.** §7. A QSO with
   one of the ten rare counties is worth 20 / 30 / 50 instead of 2 / 3 / 5, and
   the sponsor stresses that these land *before* multiplication. `PointsTable` is
   keyed by mode alone. Sketch: an optional `bonusCountyPoints: {counties: [...],
   factor: 10}` (or an explicit per-mode table) consulted by
   `ScoreEngine.pointsTable(forTheirLoc:)`, which already takes the received
   location and already chooses between two tables for `homeStationPoints` — so
   the hook exists and the change is small. **This is the one to build first.**
2. **NO NAMED-SUBSET SWEEP: the 500-point five-rare-county bonus is not applied.**
   §8. `sweepTiers` counts any counties, not five of a named ten, so it cannot be
   reused without paying nearly every log. Sketch: a `sweepOf(counties: [String],
   need: Int, points: Int)` `BonusRule` case; it lands after multiplication where
   `bonusPoints` already goes, so only the predicate is new.
3. **Self-activation multipliers — THIRD user.** §6, and the broadest form yet: a
   fixed NC station counts its own county with no QSOs from it. TnQP (once), SCQP
   (per band per mode) and now NCQP (once, and unconditional for the operating
   county) — three sponsors, three scopes, which settles that the field must
   carry its scope. Affects in-state entrants only.

Both 1 and 2 are recorded in `notes` as KNOWN LIMITATIONs with the arithmetic an
operator needs to correct by hand, per Article 17's allowance for shipping ahead
of the field.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| Phone 2 / CW 3 / digital 5 | `points` |
| worked once per band per mode | `dupeScope: "bandMode"` |
| "only once across all modes, bands, and operating location" | `countScope: "once"`, both sides |
| "49 US States (not NC)" | `homeStateCountsViaCounty: false` |
| "plus one DX" | `dxStyle: "token"`, `.dx` in the in-state classes |
| "a maximum of two counties … simultaneously" | `maxSimultaneousCounties: 2` |
| "Sending signal report … is optional" | `exchangeIncludesRST: false` |
| "Non-NC … work NC stations only" | `outStateWorksHomeStationsOnly: true` |
| 80–2 m, "No 160, WARC, or above 2 meters" | `validBands` |

**`outStateWorksHomeStationsOnly` is in the Object and again in Operating
Details** — *"Stations outside of North Carolina (Non-NC) work NC stations
only"* — the twelfth party to state it rather than imply it.

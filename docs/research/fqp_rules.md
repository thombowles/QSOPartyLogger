# Florida QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**Everything here is first-party, including the Cabrillo header** — which is the
first time in six parties, and the header is not the value anyone would guess.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Florida Contest Group** (FCG), <https://floridaqsoparty.org> |
| **Rules** | <https://floridaqsoparty.org/rules/> |
| **County list** | <https://floridaqsoparty.org/counties/counties-list/> — the live table |
| County cross-check | <https://www.floridaqsoparty.org/files/countabb.pdf> — the printable copy |
| **Cabrillo spec** | `…/uploads/Cabrillo-Specification-V3-FQP.pdf` — the sponsor's own |
| Spelling Bee | <https://floridaqsoparty.org/fqp-2026-special-calls/> |
| Fetched | **2026-07-26** |

Banked verbatim: [`fqp_rules_2026.txt`](fqp_rules_2026.txt),
[`fqp_counties_2026.tsv`](fqp_counties_2026.tsv),
[`fqp_counties_pdf.txt`](fqp_counties_pdf.txt),
[`fqp_cabrillo_spec.txt`](fqp_cabrillo_spec.txt),
[`fqp_spelling_bee_2026.txt`](fqp_spelling_bee_2026.txt).

The site is **current for 2026** and states its dates outright — no rollover, no
archive, no formula to apply.

## 2. Dates and times for 2026, in UTC

> "CONTEST PERIOD: **Starts the last Saturday of April.** For 2026, the Florida
> QSO Party dates will be **April 25th- 26th**.
> There are **two 10-hour operating periods separated by a 10-hour break
> period.** All operators may operate the full **20 hours**.
> Saturday **16:00:00Z** (Noon EDT) – Sunday **01:59:59Z** (9:59:59 PM EDT)
> Sunday **12:00:00Z** (8 AM EDT) – **21:59:59Z** (5:59:59 PM EDT)"

| Start | End | Length |
| --- | --- | --- |
| `2026-04-25T16:00:00Z` | `2026-04-26T02:00:00Z` | 10 h |
| `2026-04-26T12:00:00Z` | `2026-04-26T22:00:00Z` | 10 h |

**All four local-time glosses convert correctly** against the UTC instants —
EDT is UTC−4, and 16→12, 02→22, 12→08, 22→18 all check out. That is worth
saying out loud after Nebraska, where *none* of them did, and the generator
asserts the arithmetic rather than the text.

Florida shares its weekend with Nebraska and overlaps it.

## 3. Exchange

> "Signal report (RS or RST) and location…
> **Florida operators send county.**
> **US (including KH6/KL7) operators send State.** Canadian operators send
> province.
> **DX (including KP4, etc.) operators send DXCC prefix.** Maritime mobile
> operators send **ITU Region (1, 2 or 3)**."

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`,
**`dxStyle: "prefix"` stated outright** — no inference needed, unlike Ontario
and North Dakota, which each had to be argued.

The maritime-mobile clause is limitation 1 (§12).

And a warning the sponsor repeats twice:

> "Contacts with Florida stations must include their county as part of the
> received exchange. **Don't log the exchange as FL.**"

## 4. Bands and modes — the narrowest list in the app

> "**No 160 or 80 meters, WARC or VHF bands.**"

→ **40, 20, 15 and 10 metres. Four bands**, fewer than any other bundled party
(Michigan, Alabama and New Hampshire each have five).

**The sponsor's own arithmetic fixes the count**, which is the cheapest possible
check:

> "Stations may be worked once per mode per band for a total of **8 maximum
> QSOs**."

Four bands × two modes = eight. The suggested-frequency list also names a CW
range on each of exactly those four.

> "MODES: Phone, CW, Mixed (Phone and CW)… **No digital QSOs are allowed in the
> FQP**."
>
> "No cross-mode contacts."

→ `allowedModes: ["phone", "cw"]`.

## 5. QSO points

> "Each complete non-duplicate **Phone** contact is worth **1** point per band.
> Each complete non-duplicate **CW** contact is worth **2** points per band."

## 6. Multipliers — and Florida entrants get no counties

> "A multiplier is counted **once per mode**, regardless of the number of bands
> on which it is worked."

→ `countScope: "perMode"` both sides.

> "For Florida entrants: **50 States (including Florida)**; District of Columbia
> (DC); 13 Canadian Provinces …; DXCC Countries (outside the US and Canada);
> Maritime Mobile (ITU Regions R1, R2, R3). **There is no in-state County
> multiplier.**
> For non-Florida entrants: **67 Florida Counties.**"

| | In-state (FL) | Out-of-state |
| --- | --- | --- |
| Classes | states + DC + provinces + DXCC — **no counties** | **67 counties** |
| Scope | **per mode** | **per mode** |

- **"There is no in-state County multiplier"** is unusual and worth stating
  plainly: a Florida entrant gets nothing for working the other 66 counties. It
  is the mirror of North Dakota, where in-state entrants count *only* their own
  counties.
- **`homeStateCountsViaCounty: true`** — *"50 States (**including Florida**)"*.
  Fifty, not forty-nine; and Florida stations send counties, so `FL` is never
  received. The sponsor even forbids sending it.

> "**POWER MULTIPLIER** … 5 watts output or less, use a Power Multiplier of **3**
> … greater 5 watts and less than 100 watts output, use a Power Multiplier of
> **2** … more than 100 watts output, there is **no** Power Multiplier."
>
> "FINAL SCORE: **QSO Points times Multipliers then times Power Multiplier**"

**Whole numbers, so it ships** — the third party to manage that, after New
Mexico and Nebraska. The formula is the engine's exactly.

## 7. Out-of-state credit — implied, not stated

> "OBJECT: For radio amateurs **outside of the state of Florida** to make
> contacts with as many **Florida** stations… **Florida operators can work anyone
> outside and within Florida.**"

`outStateWorksHomeStationsOnly: true` ships, but note **the asymmetry is the
only evidence**: no sentence forbids a non-Florida station from claiming a
non-Florida contact, and non-Florida entrants' only multipliers are Florida
counties anyway. **OPEN QUESTION 1** (§13).

## 8. County lines

> "Florida stations on a county line (**maximum of two counties**) may be claimed
> as a separate QSO and multiplier from each county. County lines are defined
> per the County Hunter guidelines."

→ `maxSimultaneousCounties: 2`, capped explicitly rather than left to MARAC.

> "Florida Mobiles and Expeditions that move to a new county are considered to be
> a new station and may be contacted again for QSO Point credit."

## 9. The Spelling Bee, and `oneByOne`

> "We had a total of **20 special 1×1 stations whose suffixes spell US
> BIRTHDAY**. There will be two stations per suffix. Contact at least one station
> of each suffix letter spelling US BIRTHDAY to earn this award."

→ `oneByOne: {"words": ["USBIRTHDAY"]}` — the second party to use that field,
after Kansas. **The word is 2026-only**: it marks the USA's 250th birthday, so a
2027 session must replace it.

The 1×1 stations are also a scoring exception, though not one this app models
for them: *"The final score is based on total QSOs. No multipliers."* — that is
the 1×1 operator's own entry class, not something an ordinary entrant needs.

## 10. Bonus points

**None.** No rule in either document pays bonus points.

## 11. Cabrillo `CONTEST:` header — first-party, and not the guess

The sponsor publishes its own Cabrillo specification, and it prints:

```
CONTEST: FCG-FQP
QSO: 14045 CW 2019-04-27 1600 K4KG          599 POL    K9NW          599 IN
```

**`FCG-FQP`, not `FL-QSO-PARTY`.** Every other party this run has followed the
`XX-QSO-PARTY` pattern, so the obvious guess would have been wrong — and this is
the first party in six where no [Article 1](../CONSTITUTION.md) exception is
needed, because the sponsor states it. (WA7BNM agrees, which is corroboration
rather than authority.)

## 12. Engine shapes to watch

**One limitation.**

1. **Maritime-mobile ITU regions cannot be counted.** §3, §6. The rules give
   maritime-mobile stations their own exchange — *"send ITU Region (1, 2 or
   3)"* — and make **R1, R2 and R3 multipliers** for Florida entrants.
   `MultClass` covers county, state, province and dx; there is no region class,
   so a Florida entrant working all three loses three multipliers. **First user
   of that gap.** The tokens are rare, so the scoring cost is small — but the
   sharper edge is that a `/MM` exchange **cannot be logged at all**, since
   `R1` matches no county, no state and no province, and `isPlausibleDXPrefix`
   would have to guess it as a DXCC prefix.

Everything else fits:

| Rule | Field |
| --- | --- |
| phone 1, CW 2 | `points` |
| "No digital QSOs are allowed" | `allowedModes: ["phone", "cw"]` |
| "No 160 or 80 meters, WARC or VHF" | `validBands` — four |
| "once per mode per band" | `dupeScope: "bandMode"` |
| "counted once per mode" | `countScope: "perMode"`, both sides |
| "50 States (including Florida)" | `homeStateCountsViaCounty: true` |
| **"There is no in-state County multiplier"** | **`county` absent from in-state `classes`** |
| "send DXCC prefix" | `dxStyle: "prefix"` |
| ITU regions R1/R2/R3 | **no mult class — limitation 1** |
| QRP ×3, low ×2, high ×1 | `scoreMultipliers.power` |
| "maximum of two counties" | `maxSimultaneousCounties: 2` |
| 1×1 suffixes spelling US BIRTHDAY | `oneByOne` |
| two 10-hour legs | `schedule` |

## 13. Open questions

1. **Is the out-of-state restriction stated or only implied?** §7. The Object is
   asymmetric and non-Florida entrants' only multipliers are Florida counties,
   but no sentence forbids a non-Florida station claiming points for a
   non-Florida contact. `outStateWorksHomeStationsOnly: true` ships as the
   reading every FQP summary takes; worth confirming before 2027.

## 14. County list

**67 counties**, uniform 3-letter codes, and **parsed twice** — from the live
HTML table and from the sponsor's own printable PDF, which lists them in the
opposite order (code first). The two are required to agree, and they do on all
67 once one typographic difference is normalised: the live page prints
`MIAMI-DADE`, the PDF `MIAMI - DADE`. The live page's spelling ships, because
it is the one that says:

> "Please **do not deviate from these names and abbreviations** in your logs."

**The sponsor flags its own trap**, which no other sponsor this run has done:

> "**Pay attention to "MIAMI-DADE" COUNTY as the abbreviation is DAD.**"

Two more worth knowing:

- **`BAY` and `LEE` are their own codes** — both county names are already three
  letters. A parser that collapses repeated lines loses exactly those two, which
  is how they were nearly lost here.
- Four codes are not simple truncations: `CAH` Calhoun (not `CAL`), `CLR`
  Collier and `CLM` Columbia (which would both truncate to `COL`), `IDR` Indian
  River, and `MTE` Manatee against `MAO` Marion.

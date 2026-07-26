# North Dakota QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the document in §1.

**One document, five pages, and it carries everything** — rules, summary sheet,
suggested frequencies, the 53-county list and the Canadian abbreviations. It
also carries its own province spellings, which are not the app's, and that is
the finding that costs real work here.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **ARRL North Dakota Section** — Section Manager **N0RDF**, ASM **K0YL** |
| **Rules** | <http://ndarrlsection.com/2026/2026_nd_qsp_party_rules.pdf> — "2026 ND QSO Party Rules", `Last-Modified: 2026-03-06`, footer "Revised January 2026" |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — see §11) |
| Fetched | **2026-07-26** |

Banked verbatim: [`ndqp_rules_2026.txt`](ndqp_rules_2026.txt),
[`ndqp_cabrillo_name.txt`](ndqp_cabrillo_name.txt).

Unusually for this season, the sponsor is a **section**, not a club — the ARRL
ND Section Manager runs it directly. There is no ndqsoparty.com; the section
site is the only home it has.

## 2. Dates and times for 2026, in UTC

> "Date/Time: Starts at **1800Z** (1:00 PM CDST) **April 11th, 2026** until
> **1800Z** (1:00 PM CDST) **April 12th, 2026**"

| Start | End | Length |
| --- | --- | --- |
| `2026-04-11T18:00:00Z` | `2026-04-12T18:00:00Z` | **24 h** |

**A single unbroken 24-hour window** — a shape it shares with exactly two other
bundled parties, Maine and South Dakota. Both instants are given in UTC *and*
local, both years are printed, and there is no formula to misapply. Nothing to
derive, which after Missouri and Louisiana is worth saying out loud.

It shares 11 April with Missouri, New Mexico and Georgia, and opens at the same
minute as Georgia — **four parties on one Saturday**, the busiest day of 2026.

## 3. Exchange

> "ND stations give **RST and County**. U.S. and Canadian stations give RST and
> **State, Province or Territories**. DX Stations give RST and **DX country**."

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`.

**`dxStyle: "token"`, and here that is a deliberate compromise rather than a
reading of the rule.** See §12, limitation 1 — the short version is that the
alternative setting is inert in this party and would leave an ND operator
unable to log a DX contact at all.

## 4. Modes — digital yes, FT8 no

> "Modes: Phone= (SSB/FM both counts as Phone); CW= (CW counts as CW) and
> Digital = (RTTY/PSK), **NO FT8**"

→ `allowedModes: ["phone", "cw", "digital"]`, and **the FT8 exclusion cannot be
expressed** — `ModeClass.digital` is one class covering RTTY, PSK and FT8
alike. See §12, limitation 2.

Note also, in the same breath as the mode list:

> "**You are allowed to make a Phone, CW and a Digital contact with the same
> station on the same band in each mode.**"

which is `dupeScope: "bandMode"` stated from the operator's side rather than
the scorer's.

## 5. QSO points

> "All contacts count as **1 point** per non-duplicated phone, CW or Digital
> contact on each band."
>
> "CW, Digital or Phone contacts will all count one point."

**Flat one point, every mode** — said twice, which is worth noting in a season
where CW usually pays double.

## 6. Multipliers — and the sponsor's arithmetic

> "Multipliers: ND stations multiply points by the sum of ND Counties (**53**),
> states/provinces (**49 states excluding North Dakota + DC, + 10 Canadian
> provinces + 3 Canadian Territories = 63 W/VE multipliers total**): **116
> Total Multipliers** for W/VE (Outside North Dakota stations) and DX stations
> are the **53 ND counties**."
>
> "**Multipliers count once overall, not once per band or mode.**"

| | In-state (ND) | Out-of-state |
| --- | --- | --- |
| Classes | 53 counties + 50 states/DC + 13 provinces, **no DX** | **53 ND counties** |
| Scope | **once overall** | **once overall** |
| Sponsor's ceiling | **116** = 53 + 63 | **53** |

→ `countScope: "once"` both sides, stated in one sentence with both
alternatives named and refused.

- **`homeStateCountsViaCounty: false`** — *"49 states **excluding North
  Dakota**"*. North Dakota is not a state multiplier at all here; an ND station
  counts its own state's counties directly, all 53 of them. This is the
  opposite of Georgia, New Mexico and Minnesota, and the arithmetic proves it:
  49 + DC = 50, plus 13 = 63, and 53 + 63 = 116.
- **ND stations count their own counties**, which most parties do not give the
  home side. It is why the in-state ceiling is 116 rather than 63.
- **DX pays points and nothing else**: *"North Dakota stations may work DXCC
  countries for points only — no multipliers."* The second party in a row with
  that shape, after Georgia one day earlier on the calendar.

The summary sheet restates all of it as fill-in-the-blank arithmetic
(*"Multipliers max 63 plus # North Dakota Counties = ___ Multipliers max 53"*),
which is a second, independent statement of the same ceilings.

## 7. The Canadian list is not the standard thirteen

The sponsor prints its own:

> "Canadian Abbreviations (13) AB Alberta, BC British Columbia, **LB Labrador**,
> MB Manitoba, NB New Brunswick, **NF Newfoundland**, NS Nova Scotia, **NT
> Northwest Territory**, ON Ontario, PE Prince Edward Is., QC Quebec, SK
> Saskatchewan, YT Yukon Territory"

Thirteen tokens, but **not the app's thirteen**:

| | Standard (`MultClass.canadianProvinces`) | North Dakota |
| --- | --- | --- |
| Newfoundland and Labrador | `NL`, one token | **`NF` and `LB`, two** |
| Nunavut | `NU` | **absent** |

This is the pre-2001 RAC nomenclature, still in use by several QSO parties. It
needs a **`provinces` override** — the same field OhQP uses to count only 11 —
and without it an ND log would reject `LB` and `NF` while accepting a `NU` and
an `NL` the sponsor does not recognise. The generator parses the sponsor's list
rather than typing it, and asserts the count is 13 and the delta is exactly
those two swaps.

## 8. County lines

> "Mobile stations may park on a county line but **each county must be worked in
> a separate contact**."

→ `maxSimultaneousCounties: **1**`. Note this is *not* the same as forbidding
line-sitting: the mobile may park there, but it must make two QSOs rather than
one two-county QSO. From the logger's side the effect is identical — one county
per exchange — and it is the opposite of Georgia's arrangement one row earlier
in the worklist, where the rover sends both counties at once.

> "Mobile ND stations that change counties are considered to be a **new station
> in each new county**."

Already `DupeChecker`'s behaviour, which keys on `theirLoc`.

## 9. Bands

> "Bands: **160 through 10 meters, 6 & 2 meters, (Excluding the WARC Bands)**"

**Eight bands**, with the exclusion stated — no inference needed, unlike
Georgia one row earlier. `Use of a Repeater is not allowed` and the VHF note
says *"6 meter & 2 meter SSB & FM Band Plans should be used"*.

## 10. Categories and scoring

> "There are **no power limitations** in this contest, within legal limit."
>
> "There are **no multi-op categories**."
>
> "Final Total = Contact Total X Multiplier Total"

→ no `scoreMultipliers`, no bonuses, a bare product. Entry classes are
geographic only: North Dakota Station (fixed, portable or mobile — *"They will
count as one station"*), Outside ND US Station, Canadian-DX Station.

## 11. Cabrillo `CONTEST:` header

**Not printed anywhere in the sponsor's document**, which is the case
[Article 1](../CONSTITUTION.md) reserves the WA7BNM exception for. The WA7BNM
Contest Calendar's Cabrillo Names table gives **`ND-QSO-PARTY`**, banked in
[`ndqp_cabrillo_name.txt`](ndqp_cabrillo_name.txt).

The sponsor does ask for Cabrillo — *"please submit their log Cabrillo file via
email along with a Summary sheet"* — it simply never says what to put in the
header.

## 12. Engine shapes to watch

**Two limitations, both recorded and both new in kind.**

1. **An ND station cannot log a DX country the way the rules ask.** §3, §6. The
   rules want the DX country in the log, but `ExchangeParser` only guesses at
   DXCC prefixes **where DX is a multiplier class for that operator** — a
   deliberate safety gate, because the guess is loose and would otherwise turn
   every mistyped county into a valid exchange. North Dakota grants DX no
   multipliers, so the gate is shut, and `dxStyle: "prefix"` would be *inert*:
   it would not enable prefix parsing, and it would remove the literal `DX`
   token from the accepted set, leaving an ND operator with no way to log the
   contact at all. **`token` is therefore strictly better here**, and the cost
   is confined to the recorded text: the operator enters `DX`, the sponsor
   would rather see `DL`. **The score is unaffected** — DX is never a
   multiplier and every mode pays the same one point. *The gate itself is
   correct policy; North Dakota is simply the first party where it costs
   anything.*
2. **"NO FT8" cannot be enforced.** §4. `ModeClass.digital` is one class, and
   the party admits RTTY and PSK under it. A logged FT8 row will score. This is
   **not a new gap — Illinois got there first** ("FT4 and FT8 contacts will
   receive no contact credit. Other digital modes are encouraged"), and North
   Dakota is its **second user**, which meets the repo's own two-user bar and
   makes it buildable. `QSO.rawMode` already carries the concrete mode, so the
   fix is a party-level list of excluded raw modes. Mississippi (FT4/FT8
   first-class) and New Mexico (FT8 permitted but requiring manual log editing)
   show the same axis being cut three different ways.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| 1 point, all modes | `points` |
| "NO FT8" | **cannot be expressed — limitation 2** |
| "once per band and mode" | `dupeScope: "bandMode"` |
| "count once overall, not once per band or mode" | `countScope: "once"`, both sides |
| "49 states **excluding** North Dakota" | `homeStateCountsViaCounty: false` |
| ND counties are in-state multipliers | `classes` includes `county` in-state |
| "for points only — no multipliers" | `dx` omitted from in-state `classes` |
| `LB`/`NF`, no `NU` | **`provinces` override** |
| "each county… in a separate contact" | `maxSimultaneousCounties: 1` |
| 160–10 m plus 6 and 2, no WARC | `validBands` |
| 24 hours, one window | `schedule` |

## 13. The sponsor's own errors, shipped as printed

Per the repo's standing practice, these are asserted so that a correction is
noticed rather than silently absorbed:

- **"Entries must be postmarked by May 15th, 2025"** in a document whose other
  three deadlines all say 2026 — a leftover from the previous edition, sitting
  two lines above *"by the May 15th, **2026** deadline"*.
- **"January 2025"** printed immediately before **"Revised January 2026"**.
- **`3705`** in the CW suggested-frequency list, where every other entry carries
  its decimal point (`3.550`, `7.050`). It means 3.705 MHz.
- **"Northwest Territory"**, singular, and **"Prince Edward Is."**

## 14. County list

**53 counties, uniform 3-letter codes**, from the list at the end of the rules —
*"List of ND Counties with 3 letter abbreviations are included at the end of
this document. All operators are asked to use these abbreviations."*

Parsing it is the one awkward job here: `pdftotext` reflows the block so that
the separator between a county's name and its code is inconsistent — sometimes
a hyphen (`Adams County-ADM`), sometimes a space (`Cavalier County CAV`) and
sometimes **nothing at all** (`Barnes CountyBRN`, `Golden Valley CountyGNV`).
The generator joins the block into one line and splits on commas, then matches
`<name> County[-\s]*<CODE>`, so all three shapes fall out of the same pattern.

The four `Mc` counties are the group to check — `MCH` McHenry, `MCI` McIntosh,
`MCK` McKenzie, `MCL` McLean — four codes separated by a single third letter,
and every one of them is a real North Dakota county.

**The sponsor prints "La Moure"** as two words; the county's own spelling is
*LaMoure*. Shipped as printed, per the repo's practice with NHQP's "Merrimac",
NCQP's "Chowen", MOQP's "St. Genevieve" and NMQP's "Dona Ana".

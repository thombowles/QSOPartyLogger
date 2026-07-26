# Quebec QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The sponsor publishes the rules in both French and English**, which is a free
second source — not a second fetch of the same page. The generator parses both
and requires them to agree. They agree on all 17 region codes, and **they
disagree about Canada**, which is §7.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Club Radio Amateur de l'Outaouais** (CRAO) |
| **Rules (English)** | <https://quebecqsoparty.org/rules-quebec-qso-party/> |
| **Rules (French)** | <https://quebecqsoparty.org/reglements-quebec-qso-party-2/> |
| Dates | <https://quebecqsoparty.org/> — the bilingual banner |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — §11) |
| Fetched | **2026-07-26** |

Banked verbatim: [`qcqp_rules_en_2026.txt`](qcqp_rules_en_2026.txt),
[`qcqp_rules_fr_2026.txt`](qcqp_rules_fr_2026.txt),
[`qcqp_home_2026.txt`](qcqp_home_2026.txt),
[`qcqp_cabrillo_name.txt`](qcqp_cabrillo_name.txt).

**Both editions are current for 2026** — unlike Michigan and Ontario, whose
sites had rolled forward. The sponsor's own abbreviation is **QCQP**.

## 2. Dates and times for 2026, in UTC

> "The Quebec QSO Party will be held on **Sunday April 19th, 2026, from 13:00 to
> 24:00 UTC**."
>
> "Generaly speaking the event will be held on **the Sunday of the third full
> weekend of April**."

| Start | End | Length |
| --- | --- | --- |
| `2026-04-19T13:00:00Z` | `2026-04-20T00:00:00Z` | **11 h** |

One window, and **the times are new for 2026** — the home page's banner says so
in both languages:

> "**Nouveau 2026** — Nouvelles heures d'opérations — **New operating times**"

So a pre-2026 source has the wrong hours, exactly as with Ontario the day
before. Quebec runs on the Sunday of Ontario's weekend and overlaps it: Ontario's
Sunday leg is 1200–2000Z, Quebec's is 1300–2400Z.

## 3. Exchange

> "**VE2 stations**: Must send a signal report and their **administrative region
> abbreviation**… **Non-VE2 stations**: Must send a signal report and their
> **province, US state or DX** for other entities."

→ `exchangeIncludesRST: true`, `exchangeIncludesSerial: false`.

"VE2" is defined generously:

> "VE2 is used here for any station operating within the physical boundary of the
> province of Quebec. Possible prefixes are **VA2, VB2, VE2 and VX2**… Any station
> operating within the province of Quebec and using a prefix referencing some
> other territory shall use the "**/VE2**" suffix."

The French edition prints a worked exchange, which is the clearest statement of
the shape anywhere in either document:

> "VE2CRO: … You are Five-Nine from region **Oscar Tango Sierra**. Back to you.
> KA1BCD: QSL, please take my Four Nine from New-York, **November Yankee**."

## 4. Bands and modes

> "Frequencies: **All amateur bands between 80 et 2 m, excepted WARC bands.**"

→ 80, 40, 20, 15, 10, 6 and 2 metres — **seven bands, and no 160 m**, which
Ontario has. The range genuinely starts at 80. See §13 for 60 m.

> "Modes: **Phone (SSB or FM) and Morse code (CW)**."
>
> "Frequency Modulation: Is allowed but operators **cannot use repeaters**…"

→ `allowedModes: ["phone", "cw"]`, no digital anywhere in either edition.

> "A station can be contacted **twice per band, once on phone and once on CW**.
> Only one QSO per station for each band and each mode can provide points.
> **Additional logged QSOs have no value but are not penalized either.**"

→ `dupeScope: "bandMode"`, and the sponsor spells out that dupes are worth zero
rather than negative — which is the engine's behaviour.

## 5. QSO points

> "**1 point** per QSO on **phone** on each frequency band.
> **2 points** per QSO on **CW** on each frequency band."

Worth putting beside Ontario, which for 2026 raised phone to 2 so that both
modes pay alike. **Quebec did not** — the two neighbours share a weekend and
score phone differently.

## 6. Multipliers — per band, mode explicitly ruled out

> "For all stations, one multiplier point is given for each first contact made in
> each administrative region, **on each frequency band** worked on these regions.
> **No additional multipliers are given for working multiple modes.**"
>
> "Additionally, a VE2 station is given one multiplier point for each first
> contact with a **province or Canadian territory, US state or DX**, for each band
> worked with these territories. **Only one DX multiplier is given for entities
> worked outside of Canada or USA.**"

| | In-state (VE2) | Out-of-state |
| --- | --- | --- |
| Classes | 17 regions + states/DC + provinces + **DX** | **17 regions** |
| Scope | **per band** | **per band** |

→ `countScope: "perBand"` both sides, with the mode axis **denied in so many
words** — the clearest statement of that scope in the app.

**`dxStyle: "token"` is exactly right here, and that is unusual.** The sponsor
grants *"only one DX multiplier"* for everything outside Canada and the USA, and
requires *"Other DXCC entities must be logged as **DX**"*. So the single
collapsed multiplier the token style produces **is** the rule, not an
approximation of it. Ontario, built the day before, has the opposite shape and
pays for it — the contrast is worth keeping straight.

- **`homeStateCountsViaCounty: false`** — Quebec is not a territory at all here
  (§7), and VE2 stations claim the regions directly.

> "The total score is: **QSO-score = (Total of the QSO points) \* (Total of the
> multiplier points)**"

## 7. Appendix II — where the two editions disagree

Both editions carry the same table of Canadian abbreviations, and it has
**fourteen rows for thirteen entities**:

| | English edition | French edition |
| --- | --- | --- |
| `NT` | "**Northern Territories**" | "**Territoires du Nord-Ouest**" (= Northwest Territories) |
| `NWT` | "Northwest Territories" | "Northwest Territories" — *left untranslated* |

Two findings, and the second explains the first:

1. **The editions disagree about `NT`.** The French is right — `NT` is the
   Northwest Territories, as it is everywhere else in amateur radio. "Northern
   Territories" is not a Canadian entity, so the English label is simply wrong.
2. **`NWT` is a duplicate of `NT`**, and the French page **did not translate
   that row** — the only English string left in an otherwise French table. That
   is the signature of a row appended late and never revisited.

Also note, in both editions:

> "**Note that the Province of Quebec (QC) is not a valid territory entry** for
> the Quebec QSO Party. Logging QSOs with VE2 stations must use the Quebec
> administrative region instead."

and the split Newfoundland the app has seen once before:

> "Newfoundland **NF** … Labrador **LB**"

**What ships:** all fourteen tokens as printed, `QC` excluded. Accepting `NWT`
never blocks a legal exchange; rejecting it would, and the repo's standing rule
is that refusing something the sponsor prints is the worse failure. The
over-count it theoretically allows requires one operator to log the same
territory under two labels, which no log does. The generator asserts the
fourteen, the duplication, and the English/French disagreement, so a correction
by the sponsor is noticed rather than absorbed.

This is the **second party with a non-standard Canadian list**, after North
Dakota — and the second to split `NL` into `NF` + `LB`. Unlike North Dakota,
Quebec *does* carry Nunavut.

## 8. Out-of-Quebec credit

> "The VE2 stations obtain points for contacts with **all stations**. **Non-VE2
> stations obtain points for contacts for VE2 stations only.**"

→ `outStateWorksHomeStationsOnly: true`.

## 9. Region boundaries and the mobile bonus

> "If a mobile station is on a boundary between 2 or more administrative regions,
> a **separate QSO and complete exchange must be made and logged for each**
> administrative regions worked."

→ `maxSimultaneousCounties: 1`, same as Ontario.

> "**Bonuses are added after the calculation of the QSO-score.**"
>
> "**Starting in 2026, there is no bonus station(s)**"
>
> "Mobile stations add **300 bonus points for each Quebec administrative region
> activated**. To earn the mobile/rover bonus a station must make at least **three
> contacts with three different stations** from the multiplier area."

→ `activatedCountyCount(minQSOs: 3, points: 300)` — **identical to Ontario's**,
wording and all, including the three-different-stations clause the schema cannot
express (§12). The "no bonus station" line is an explicit 2026 removal and is
asserted, so its return would be caught.

The sponsor also states the bonus placement, and it is the engine's:

> "Mobile stations are given the total of the multiplication points made in each
> administrative region activated."

## 10. Categories, and a multiplier that is *not* a score multiplier

Nine categories: Multi-op mixed · Single Op QRP Mixed · Single Op Mixed Low and
High · Phone-only Low and High · CW-only Low and High · **Mobile**. Remote
operation is allowed in fixed categories, sending the transmitter's region, and
all equipment must sit *"within a maximum diameter of 500m"*.

**The power multiplier in paragraph 20 must not be modelled.** It reads:

> "A multiplier of one (1) is used for stations operating at **High Power** and a
> multiplier of two (2) is granted to stations working at a **lower power** level."

That is inside *"Awards per club, inside Quebec"* and applies only to the club
and per-region award tallies — **not to the entrant's own score**, which
paragraph 16 fixes as QSO points × multipliers. → no `scoreMultipliers`. A
reader skimming for "multiplier of two" would ship a wrong ×2 for every low-power
entrant.

## 11. Cabrillo `CONTEST:` header

**Not named in either edition**, though both require a Cabrillo log. So
`QC-QSO-PARTY` comes from WA7BNM's Cabrillo Names table under
[Article 1](../CONSTITUTION.md)'s exception — the fourth in a row, after North
Dakota, Michigan and Ontario.

The exception sits more comfortably here than usual: **the sponsor itself cites
WA7BNM**, pointing readers at `contestdetails.php?ref=53` for upcoming dates.

## 12. Engine shapes to watch

**One limitation, and it is inherited from Ontario rather than new.**

1. **The activation bonus counts QSOs, not distinct stations.** §9. Both Quebec
   and Ontario require "three contacts with three different stations";
   `activatedCountyCount(minQSOs:)` counts three valid QSOs, which three bands'
   worth of one station satisfies. **Second user of that gap, one day apart on
   the calendar** — which meets the repo's two-user bar and makes it worth
   building: the fix is to count `Set(qsos.map(\.call)).count` instead of
   `qsos.count`, behind an optional flag so the parties that really do mean
   QSOs are untouched. Overpayment is bounded at 300 points per region.

Everything else fits, including the two things that did *not* fit for Ontario:

| Rule | Field |
| --- | --- |
| phone 1, CW 2 | `points` |
| phone and CW only | `allowedModes` |
| 80–2 m less WARC | `validBands` — seven, no 160 m |
| "twice per band, once on phone and once on CW" | `dupeScope: "bandMode"` |
| "on each frequency band… no additional for modes" | **`countScope: "perBand"`** |
| **"only one DX multiplier"** | **`dxStyle: "token"` — the rule, not an approximation** |
| **"no bonus station(s)" from 2026** | **no `workStation` bonus to model** |
| "QC is not a valid territory entry" | `QC` absent from `provinces` |
| separate QSO per region | `maxSimultaneousCounties: 1` |
| 300 per activated region | `activatedCountyCount` |
| 13:00–24:00 UTC | `schedule` |

## 13. Open questions

1. **Is 60 m legal?** §4. "All amateur bands between 80 et 2 m, excepted WARC
   bands" puts 60 m inside the range and 60 m is not strictly WARC — the same
   ambiguity Ontario and North Dakota have, resolved the same way. Seven bands
   ship without it; no 5 MHz frequency appears in the sponsor's suggested list.

## 14. Region list

**17 administrative regions**, uniform 3-letter codes, numbered 1–17 by the
sponsor in the order Quebec itself numbers them.

**The trap is `QUE`, which is not Quebec the province:**

| Code | Region | |
| --- | --- | --- |
| **`QUE`** | **Capitale-Nationale** (region 3) | the Quebec City region, *not* the province — and `QC` is not a valid entry at all (§7) |
| `MTL` | Montréal (6) | |
| `MEE` | Montérégie (16) | no letter in common with the obvious guess |
| `ETE` | Estrie (5) | |
| `CDQ` | Centre-du-Québec (17) | against `NDQ` Nord-du-Québec (10) |
| `CND` | Côte-Nord (9) | against `CDQ` and `NDQ` |
| `CAS` | Chaudière-Appalaches (12) | |

**The accents come from the French edition**, which is the sponsor's primary
language and prints them correctly; the English edition strips them
("Cote-Nord", "Montreal", "Gaspesie-îles-de-la-Madeleine" — which loses two
accents and keeps a third). The generator asserts both spellings exist and that
the two editions agree on every code, so the divergence is recorded rather than
silently resolved.

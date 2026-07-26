# Ontario QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The site rolled forward to 2027 but the rules did not** — the landing page
advertises the 30th Annual OQP while `rules.htm` is still headed *"2026 Ontario
QSO Party Rules (revised 01 March 2026)"*. That split is worth knowing before
reading anything else here, and §2 is how it was proved.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | **Contest Club Ontario** (CCO), which has run the OQP since 2006; founded 1998 by Bob Chandler VE3SRE |
| **Rules (2026)** | <https://www.va3cco.com/oqp/rules.htm> — live, and still the 2026 edition |
| Rules (2025) | [`web.archive.org/web/20260124025618/…/rules.htm`](http://web.archive.org/web/20260124025618/http://va3cco.com/oqp/rules.htm) — the previous edition, for the diff |
| Change log | <https://www.va3cco.com/oqp/index.htm> — the sponsor's own "2026 Rules Changes" list |
| **Multiplier list** | <https://www.va3cco.com/oqp/OQPMultList.pdf> — "Effective 01Jan2023", `Last-Modified: 2025-05-20` |
| Cabrillo name | WA7BNM Contest Calendar, Cabrillo Names table (Article 1 exception — §11) |
| Fetched | **2026-07-26** |

Banked verbatim: [`oqp_rules_2026.txt`](oqp_rules_2026.txt),
[`oqp_rules_2025.txt`](oqp_rules_2025.txt),
[`oqp_index_2027.txt`](oqp_index_2027.txt),
[`oqp_mults_page.txt`](oqp_mults_page.txt),
[`oqp_multlist_2023.txt`](oqp_multlist_2023.txt),
[`oqp_cabrillo_name.txt`](oqp_cabrillo_name.txt).

## 2. Which edition is live, and how that was settled

The Wayback digest history for `rules.htm` shows three distinct versions across
2025–26, and the useful one is the pair either side of the 2026 contest:

| Snapshot | Content |
| --- | --- |
| `2026-01-24` | byte-identical to `2025-04-27` — **the 2025 rules were still up in January 2026** |
| `2026-05-04` | a new edition, headed "2026 … (revised 01 March 2026)" |
| **live, 2026-07-26** | **identical to the 2026-05-04 snapshot** |

So the live rules *are* the 2026 rules, and the generator asserts that
identity. The 2027 advertisement lives only on the landing page:

> "The **30th Annual Ontario QSO Party 2027** … 1800Z April 17 to 0300Z April
> 18, 2027 and 1200Z to 2000Z April 18, 2027"

**The 2025→2026 diff independently confirms every item on the sponsor's own
change list**, which is the strongest corroboration available here:

| Sponsor's "2026 Rules Changes" | What the diff shows |
| --- | --- |
| "Phone QSO's now count the same as CW QSO's (2 points)" | `Score 1 QSO point for each station worked on phone` → `Score 2` |
| "addition of VE3RHQ as bonus station" | `station VA3RAC.` → `stations VA3RAC and VE3RHQ.` |
| "County line proximity definition (250m)" | `(within 250m of a county line)` inserted |
| "Fixed County Line Category added" | two new lines defining it |
| "2 hours moved from Saturday to Sunday" | `0500Z`→`0300Z` and `1800Z`→`2000Z` |

**Any pre-2026 source is therefore wrong about both the times and the phone
points**, which is exactly the trap Minnesota set in the other direction.

## 3. Dates and times for 2026, in UTC

> "Dates and Times: Held on the **third full weekend of April** each Year. **For
> 2026, the contest periods are 1800Z April 18 to 0300Z April 19, and 1200Z to
> 2000Z April 19.**"

| Start | End | Length |
| --- | --- | --- |
| `2026-04-18T18:00:00Z` | `2026-04-19T03:00:00Z` | 9 h |
| `2026-04-19T12:00:00Z` | `2026-04-19T20:00:00Z` | 8 h |

**17 hours in two legs**, and the sponsor prints the 2026 instants outright
rather than leaving the formula to be applied. The formula agrees: April 2026's
full weekends are the 4th–5th, 11th–12th and 18th–19th. It shares the weekend
with Michigan, which is the same "third full weekend" rule read the same way.

## 4. Bands and modes

> "Frequencies: **All Bands 160-2 meters with the exception of the WARC bands.**"

→ 160, 80, 40, 20, 15, 10, 6 and 2 metres. **60 m is neither named nor
excluded** — see §12. The suggested-frequency list covers exactly those eight
and no more.

Modes are **phone and CW only** — there is no digital category, no digital
scoring rule, and the exchange rule names neither:

> "You may work a station **TWICE per band: once on phone and once on CW**."
>
> "Use of FM: Operators can **not use repeaters** for either contest contacts or
> for soliciting contacts."

FM counts as phone. → `allowedModes: ["phone", "cw"]`, `dupeScope: "bandMode"`.

## 5. QSO points

> "Score **2 QSO points** for each station worked on **phone** per band. Score
> **2 QSO points** for each station worked on **CW** per band."

**Flat two points, both modes — new for 2026**, when phone was worth one. A
source from 2025 or earlier gets this wrong.

> "Score **10 QSO points** for each contact made with CCO club stations
> **VA3CCO & VE3CCO**, ODXA club station **VE3ODX**, and RAC Ontario stations
> **VA3RAC and VE3RHQ**."

**This cannot be modelled** — see §12, limitation 1. It is *QSO points*, inside
the multiplication, not a bonus added after it.

## 6. Multipliers — per band

> "Stations claim 1 multiplier point for each Ontario county worked **on each
> band**… Ontario stations also claim 1 multiplier point for each Canadian
> province/territory, U.S. state (plus District of Columbia) and DXCC country
> worked **on each band**."

| | In-state (ON) | Out-of-state |
| --- | --- | --- |
| Classes | 50 Ontario mults + states + DC + provinces + **DXCC countries** | **50 Ontario mults** |
| Scope | **per band** | **per band** |

→ `countScope: "perBand"` both sides — **not per mode**, even though a station
is worked twice per band. The band is the axis; the mode is not. Only Tennessee
counts that way on both sides; Hawaii and New Hampshire do it out-of-state only.

- **`homeStateCountsViaCounty: false`** — Ontario stations claim the Ontario
  multipliers directly, and `ON` itself is not among the provinces they count.
- **DXCC countries count individually**, which drives the `dxStyle` decision in
  §12.
- **`provinces` override**: the twelve, with `ON` removed — the same treatment
  BCQP has for `BC`.

> "**Total Score = Total QSO points x total multiplier points.**"
>
> "**Mobile/Rover Score = (total QSO points x total multiplier points) + bonus.**"

Both are the engine's formula exactly.

## 7. Out-of-Ontario credit

> "Scoring: **Ontario stations work everyone. Non-Ontario stations work Ontario
> stations only.** Mobile/Rover stations may be worked again when they change
> multiplier areas."

→ `outStateWorksHomeStationsOnly: true`.

## 8. County lines and the mobile bonus

> "If a mobile or a rover station is on a county line or junction between 2 or
> more counties **(within 250m of a county line)**, a **separate QSO and complete
> exchange must be made and logged for each county** worked."

→ `maxSimultaneousCounties: 1`. The 250-metre definition is new for 2026 and is
the sponsor's answer to "how close is on the line". The same paragraph now also
defines a **Fixed Station County Line** category, with the identical
separate-QSO requirement.

> "**Mobile/Rover Bonus**: Mobile/Rover stations add **300 bonus points for each
> Ontario multiplier activated**. To earn the mobile/rover bonus a station must
> make at least **three contacts with three different stations** from the
> multiplier area."

→ `activatedCountyCount(minQSOs: 3, points: 300)`, with one small infidelity:
the schema counts three *QSOs*, the sponsor wants three *different stations*.
See §12, limitation 2.

## 9. Categories

Fixed (Multi-Multi / Multi-Two / Multi-Single; Single Op QRP Mixed; Single Op
Mixed, Phone-only and CW-only each at Low and High) · **Fixed Station County
Line** (new for 2026) · **Rover/Mobile** (multi- and single-operator, and the
rules stress *"for all intents and purposes rover/mobile are treated the same in
the OQP. They are NOT separate categories"*) · **Distributed Multi-Operator**,
where several sites share one callsign and *"all station(s) must be located
within one county"*.

**Power categorises but does not scale** → no `scoreMultipliers`.

Remote operation is permitted in all fixed categories, *"send the county/QTH
where the transmitter is located."*

## 10. Bonus points

One: the mobile/rover activation bonus in §8. The five 10-point club stations
are **QSO points, not bonus points**, and are the subject of limitation 1.

## 11. Cabrillo `CONTEST:` header

**Not stated.** The rules ask for a Cabrillo log and even link a text-to-Cabrillo
converter (`b4h.net/cabforms/onqp_cab3.php`) without naming the header, so
`ON-QSO-PARTY` comes from WA7BNM's Cabrillo Names table under
[Article 1](../CONSTITUTION.md)'s exception — the third party in a row to need
it, after North Dakota and Michigan.

## 12. Engine shapes to watch

1. **The five 10-point club stations cannot be modelled.** §5. The sponsor pays
   *QSO points* for working VA3CCO, VE3CCO, VE3ODX, VA3RAC and VE3RHQ, so those
   points sit **inside** the multiplication: `(QSO points incl. the 10s) ×
   mults`. The nearest schema shape, `BonusRule.workStation(scope: .perQSO)`,
   adds to `bonusPoints`, which the engine applies **after** multiplication —
   so an entrant with 60 multipliers would be credited 8 points where the
   sponsor credits 480. **Modelling it that way would be worse than not
   modelling it**, because a wrong number that looks deliberate is harder to
   notice than a missing one. **Nothing ships for these five**, and the QSOs
   score the ordinary 2 points.
   *This is the second user of the points-table gap NCQP opened* — NCQP wants
   points by county, Ontario wants points by callsign, and both want
   `pointsTable(forTheirLoc:countyAbbrs:)` to consult something more than the
   mode. The hook already takes the received location; adding the call is the
   same commit.
2. **The activation bonus counts QSOs, not distinct stations.** §8. The sponsor
   requires "three contacts with three different stations" from a multiplier
   area; `activatedCountyCount(minQSOs:)` counts three valid QSOs, which three
   bands' worth of one station would satisfy. Every other party using this rule
   says "QSOs", so Ontario is the first to distinguish. The overpayment is
   bounded at 300 points per county and needs a deliberately thin operation to
   occur at all.
3. **`dxStyle: "prefix"`, and the literal `DX` is the casualty.** §3, §6. The
   sponsor counts DXCC countries individually and asks non-Ontario stations for
   "province, state, or **DXCC country or abbreviation**" — but adds that when
   an Ontario station logs it, *"the abbreviation "DX" is also acceptable."*
   The two settings each fail one half:
   - `token` accepts the literal `DX` but collapses every DXCC entity into one
     multiplier per band, **and** leaves an Ontario station unable to log `DL`
     at all — the common case.
   - `prefix` counts entities individually and accepts `DL`, but
     `isPlausibleDXPrefix` **explicitly rejects the literal `DX`**, so the
     secondary form cannot be typed.

   **`prefix` ships**, because it gets the scoring right and accepts the
   sponsor's primary form; the rare secondary form is what breaks. This is the
   exact mirror of North Dakota, where the same two settings traded places and
   `token` won.

Everything else maps cleanly:

| Rule | Field |
| --- | --- |
| phone 2, CW 2 | `points` |
| phone and CW only | `allowedModes` |
| 160–2 m less WARC | `validBands` |
| "TWICE per band: once on phone and once on CW" | `dupeScope: "bandMode"` |
| "worked on each band" | **`countScope: "perBand"`, both sides** |
| Ontario mults claimed directly | `homeStateCountsViaCounty: false` |
| "Non-Ontario stations work Ontario stations only" | `outStateWorksHomeStationsOnly: true` |
| separate QSO per county | `maxSimultaneousCounties: 1` |
| 300 per activated multiplier, 3 QSOs | `activatedCountyCount` |
| two legs, 17 hours | `schedule` |

## 13. Open questions

1. **Is 60 m legal?** §4. "All Bands 160-2 meters with the exception of the WARC
   bands" puts 60 m inside the range, and 60 m is not strictly a WARC band —
   but it is channelised in Canada, absent from the sponsor's suggested
   frequencies, and universally excluded from contests. Eight bands ship,
   without 60 m. *North Dakota's "160 through 10 meters" has the identical
   ambiguity and was resolved the same way.*

## 14. Multiplier list

**50 Ontario multipliers**, uniform 3-letter codes, from the sponsor's own PDF —
which also carries each one's RAC section (ONN, ONS, ONE, GH) as a third column
the schema has no use for.

**They are not all counties**, and the sponsor says why:

> "A number of former counties (e.g. Brant) have recently become "single tier
> municipalities", so are now listed as cities or towns."

So the list mixes counties, districts, regional municipalities, cities, towns
and united counties — *United Counties of Stormont, Dundas & Glengarry* is one
multiplier, `SDG`.

**The trap is `HAL`:**

| Code | Multiplier |
| --- | --- |
| **`HAL`** | **Town of Haldimand** — *not* Halton |
| `HTN` | Halton Regional Municipality |

Two adjacent southern-Ontario entities, and the obvious abbreviation belongs to
the smaller one. Others worth checking, all asserted by the generator:

| | |
| --- | --- |
| `BRA` Brant County · `BFD` City of Brantford | a county and the city inside it, both multipliers |
| `PED` City of Prince Edward · `PEL` Peel · `PER` Perth | three `PE?` codes, three unrelated places |
| `NOR` Northumberland · `NFK` Town of Norfolk | |
| `MAN` Manitoulin District | not Manitoba, which is `MB` |

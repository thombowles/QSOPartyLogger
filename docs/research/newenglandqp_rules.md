# New England QSO Party — rules research

Per [Article 15](../CONSTITUTION.md#article-15--research-before-code). All
quotations are the sponsor's own words, from the documents in §1.

**The second multi-state party**, on the schema 7QP proved — and it needed no
further change to it. Two things are worth knowing before anything else:
**Connecticut no longer uses counties**, and **this party cannot have the id
`neqp`**, because Nebraska does.

## 1. Sponsor / sources

| | |
| --- | --- |
| Sponsor | the **New England QSO Party**, <https://neqp.org>, run out of West Suffield CT |
| **Rules** | <https://neqp.org/rules/> — footer "Last updated 4/27/2026" |
| **Multiplier list** | <https://neqp.org/neqp-county-abbreviations/> |
| Cabrillo name | WA7BNM Contest Calendar (Article 1 exception — §9) |
| Fetched | **2026-07-26** |

Banked verbatim: [`newenglandqp_rules_2026.txt`](newenglandqp_rules_2026.txt),
[`newenglandqp_counties_2026.tsv`](newenglandqp_counties_2026.tsv),
[`newenglandqp_counties_page_prose.txt`](newenglandqp_counties_page_prose.txt).

The county page's **table and prose are banked apart**, so the sponsor's stated
rationale can be asserted against the sponsor's own words rather than against a
comment this repo wrote.

## 2. The id is `newenglandqp`, not `neqp`

**Both parties are called NEQP in the wild.** Nebraska was built five parties
earlier and holds `neqp`, and it has the better claim: every single-state
party's id is its state abbreviation. New England is not a state, so — like the
7th Call Area, which is `sevenqp` — it gets a spelled-out id.

Their Cabrillo headers disambiguate them anyway: **`NE-QSO-PARTY`** for
Nebraska, **`NEQP`** for New England.

*This was found the hard way: the generator's first run wrote `neqp.json` and
clobbered Nebraska. `testNebraskaAndNewEnglandBothExistAndAreDistinct` is the
regression guard.*

## 3. Dates and times for 2026, in UTC

> "Date: **First full weekend of May** (May 2-3, 2026)
> Contest Period: **2000Z Saturday until 0500Z Sunday** (4pm EDT Saturday until
> 1am EDT Sunday) and **1300Z Sunday until 2400Z Sunday** (9am EDT Sunday until
> 8pm EDT Sunday)."

| Start | End | Length |
| --- | --- | --- |
| `2026-05-02T20:00:00Z` | `2026-05-03T05:00:00Z` | 9 h |
| `2026-05-03T13:00:00Z` | `2026-05-04T00:00:00Z` | 11 h |

**20 hours**, which is the site's own headline, and all four local glosses
convert correctly. It shares its Saturday with the 7th Call Area — which is why
the multi-state schema had to land before either.

## 4. Six states, 68 multipliers

> "…in as many New England counties (**68**) as possible… **for a total of 68
> (CT/9 MA/14 ME/16 NH/10 RI/5 VT/14)**"

The per-state breakdown is the arithmetic check and it holds: 9+14+16+10+5+14 =
68.

### Connecticut no longer uses counties

> "Note that **CT switched from counties to Regional Councils of Government
> (2024)**."
>
> "Note that in CT, stations will use **Regional Councils of Government**."

So Connecticut's nine are COGs — Capital Region (`CTCAP`), Naugatuck Valley
(`CTNAU`), Northwest Hills (`CTNOW`) and the rest — and **Hartford, New Haven,
Fairfield and Litchfield are not multipliers any more**. The generator asserts
both halves, so a source predating 2024 fails loudly rather than shipping nine
dead multipliers.

### The sponsor's own example of why codes carry the state has gone stale

> "Note: some county names are the same in each state (**Middlesex is in MA and
> CT**, for example). We prefer that logs use the full **5-letter
> abbreviations – state then county**."

That *was* true. Connecticut's Middlesex went with the 2024 COG switch, so only
`MAMID` survives. **The convention is still fully justified — just not by that
example.** Four names still repeat across ten multipliers:

| | |
| --- | --- |
| Franklin | `MAFRA` `MEFRA` `VTFRA` |
| Washington | `MEWAS` `RIWAS` `VTWAS` |
| Bristol | `MABRI` `RIBRI` |
| Essex | `MAESS` `VTESS` |

## 5. Exchange, bands, points

> "Send signal report and state/province (DX stations send signal report and
> "**DX**"). New England stations send signal report, **state and county**."
>
> "…on **80-40-20-15-10m**."

**Five bands — no 160 m and no VHF.**

> "QSO Points: Count **one point per phone** QSO, **two points per CW (includes
> digital modes)** QSO."

**Digital scores as CW**, which the sponsor says outright in parentheses.

> "Work New England stations **once per band/mode**… Cross mode, cross-band, and
> repeater QSOs are not permitted."

## 6. Multipliers

> "Stations outside of New England use **counties** as multipliers for a total of
> 68. New England stations use **states(50)(Count DC as MD), Canadian
> provinces(14 – VO1/VO2 are separate) and DXCC countries (not USA)**."
>
> "**Total score is QSO points times the multiplier.**"

| | In-state (NE) | Out-of-state |
| --- | --- | --- |
| Classes | states + DC + provinces + DX — **no counties** | **68 multipliers** |
| Scope | **once overall** | **once overall** |

New England entrants count **no counties**, so a New England pair earns points
only. `stateAliases: {"DC": "MD"}`.

## 7. County lines

> "**County line QSOs should be logged as two separate QSOs.**"

→ `maxSimultaneousCounties: 1`.

## 8. Open questions

1. **The Canadian list has fourteen entries and the sponsor names none of
   them.** §6. *"Canadian provinces(14 – VO1/VO2 are separate)"* gives the count
   and the reason — Newfoundland and Labrador split — but no abbreviations.
   `NF` and `LB` ship, following North Dakota's and Quebec's lists, the only
   other sponsors in this app that split it. Worth confirming before 2027.

## 9. Cabrillo `CONTEST:` header

**Not named**, though the rules ask for Cabrillo. `NEQP` comes from WA7BNM under
[Article 1](../CONSTITUTION.md)'s exception.

## 10. Engine shapes to watch

**Nothing new and nothing deferred.** The multi-state schema added for 7QP
carried New England unchanged, which is the useful result: the second user
needed no second change.

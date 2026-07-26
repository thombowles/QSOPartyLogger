# Atlantic Canada QSO Party — research banked, party not yet built

**Nothing is blocking this one.** The research is complete and every source is
banked; the build simply did not happen before this session's context ran out.
Whoever picks it up should be able to go straight to the generator.

Banked: [`acqp_rules_2026.txt`](acqp_rules_2026.txt),
[`acqp_counties_2026.tsv`](acqp_counties_2026.tsv),
[`acqp_counties_pdf.txt`](acqp_counties_pdf.txt).

**This is *not* the Canadian Prairies situation** — that one is genuinely
blocked (districts published only as images, four contradicting totals; see
[`cpqp_blocked.md`](cpqp_blocked.md)). Atlantic Canada has a machine-readable
list in two independent copies.

## Sponsor and sources

| | |
| --- | --- |
| Sponsor | Atlantic Canada QSO Party committee, <https://acqp.ca> |
| Rules | <https://acqp.ca/rules/> |
| Codes | <https://acqp.ca/resources/> — a live HTML table **and** a PDF, so they can be cross-checked |
| Cabrillo spec | `…/uploads/2025/03/ACQP-Cabrillo-Specification-V3-1-2.pdf` — the sponsor publishes its own |

## The JSON is essentially decided

| | |
| --- | --- |
| **Third multi-state party** | four provinces: NL, PE, NB, NS — on the schema 7QP and NEQP proved |
| Exchange | "**5-letter province + county/division code**", same shape as NEQP's — so `County.state` is a decomposition again, not an invention |
| Multipliers | **47**, and the sponsor gives the breakdown: **NS 18, NB 15, PE 3, NL 11** (NL uses *divisions*, not counties) |
| Scope | **per band** — "63 mults/band" in region, "47 multipliers/band" out |
| In-region classes | 13 provinces + 50 states, **DC counts as MD**, and **DX is not a multiplier** — the fifth party with that shape |
| Points | **1 per QSO regardless of mode** |
| Bands | 80-40-20-15-10 — five |
| Modes | SSB and CW. **No digital**, no cross-mode, no repeaters |
| County lines | "a separate QSO and complete exchange must be logged for each" → `maxSimultaneousCounties: 1` |
| Score | "SCORE = (QSO × mults) + Bonus" — the engine's formula |

## Two things to get right

1. **The contest window changed.** The rules head it *"Contest Period: **New 11
   hours**"* — 1400Z Sunday to 0100Z Monday. Any older source has a different
   window. The site has rolled to 2027 ("June 6, 2027") but states the formula,
   *"First Sunday of June"*, so 2026 derives as **7 June**, which matches the
   SQP Challenge calendar.

2. **The bonus stations are a list, not a station, and they are provisional.**

   > "QSOs with each of these stations will add **5 bonus points once per band and
   > mode**" — `VE1RAC, VE9RAC, VY2RAC, VO1RAC, VO2RAC`, plus
   > `VE0CNM, VE0MMA, VO1ACQ, VE9ACQ, VA1ACQ`.

   That is ten `workStation` bonuses at **`perBandMode`** — the same scope
   South Carolina introduced and Kentucky just re-used, so it fits. But the
   sponsor warns: *"Specific provincial or club bonus stations operations are
   **not guaranteed**"*, so the list needs a note like Kentucky's.

## Remaining after this

Only **West Virginia** (20 June) is then unbuilt, plus the blocked Prairies.

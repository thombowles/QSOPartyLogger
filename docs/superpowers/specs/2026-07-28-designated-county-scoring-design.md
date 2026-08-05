# Designated-county scoring — design

Two rules North Carolina publishes and this app has never paid: QSOs with ten
sponsor-designated counties are worth **10× before multiplication**, and working
five of those ten pays a further **500 after multiplication**. Together they are
the largest scoring gap in the repo, and they move *every* NCQP entrant's score,
in state and out.

Constitution: [Article 4](../../CONSTITUTION.md#article-4--the-schema-evolves-additively-refactors-are-quarantined)
(additive; every bundled party scores identically),
[Article 9](../../CONSTITUTION.md#article-9--one-party-or-one-radio-per-commit)
(the engine capability lands party-free, then NCQP alone).

## 1. What the sponsor actually says

Both quotations are from *2026 North Carolina QSO Party Contest Rules*, "Updated
10/13/2025", banked verbatim at
[`ncqp_rules_2026.txt`](../../research/ncqp_rules_2026.txt) and read 2026-07-26.

> Ten NC Counties designated below as "Rarest of NC". A QSO with someone in one
> of these counties will be scored **10X QSO points** as follows: Phone - 20
> points each / CW - 30 points each / Digital - 50 points each. **Note: These
> points are added to the rest of the regular QSO Points prior to MULT
> multiplication so they have a significant positive effect on the final
> score.**

> If at least one QSO is made with a station in **five** of the "Rarest of NC"
> counties, **500 additional bonus points** are added to the score **after
> multiplication**. This would constitute a sweep.

**Both sides earn the 10×.** The rule is stated unconditionally under a general
"Bonus QSO Points" heading. Two paragraphs earlier the same document splits
"NC participants:" from "Non-NC participants:" when it means one side only, and
the Final Score formula that follows is single and shared — *"Multiply the total
(QSO points plus Bonus QSO Points) times the total multiplier value."* So an NC
station working another NC station in Graham earns 10× exactly as a Texan does.
The predicate is the **received county**, and nothing else.

**The 500 pays once.** Singular "500 additional bonus points", singular "a
sweep", and *"a certificate… awarded to all participants achieving this sweep"*.
The threshold is **at least** five: working six or ten still pays 500, and there
is no second tier.

## 2. Why neither fits today

`ScoreEngine`'s formula is `qsoPoints × multiplierCount × categoryFactor +
bonusPoints`. `PointsTable` is keyed by mode alone, so there is no way to pay
more for one county; and `bonuses` are added *after* the multiplication, which is
precisely where the sponsor says the 10× must not go. Expressing the 10× as a
bonus would credit an entrant with 60 multipliers 27 points where the sponsor
credits 1,620.

`BonusRule.sweepTiers` lands in the right place but counts
`workedValues(.county).count` — *any* counties — so reusing it for the 500 would
pay nearly every log.

## 3. The two shapes

### 3a. `countyPointFactor` — points before multiplication

```json
"countyPointFactor": {
  "counties": ["ALL", "CAB", "CAS", "CUR", "DAV", "GRM", "MAC", "PAM", "PER", "VAN"],
  "factor": 10
}
```

Optional, absent from every other bundled party, and consulted by the method
that already decides a row's points:

```swift
func pointsTable(forTheirLoc theirLoc: String, countyAbbrs: Set<String>) -> PointsTable
```

That method already takes the received location and already chooses between two
tables for `homeStationPoints`, so **the hook exists and `ScoreEngine` needs no
change at all** for the 10×: the scaled table flows through the existing
`qsoPoints +=` and lands inside the multiplication by construction. Composition
with `homeStationPoints` is base-table-then-scale, which is what "10× QSO points"
means whichever table supplied the base.

The factor is stored, not the sponsor's worked-out 20/30/50 table, because the
factor is the rule as written (*"will be scored 10X QSO points"*) and 20/30/50 is
its arithmetic consequence. [`gen_ncqp.py`](../../research/gen_ncqp.py) parses
both out of the rules text and asserts that `factor × points` reproduces the
printed table, so a sponsor who changes either half fails the generator loudly.

One free consequence: [`LogTable`](../../../Sources/UI/LogTable.swift) already
renders its Pts column through the same method, so a rare-county CW row shows 30
without a UI change.

### 3b. `BonusRule.designatedCountySweep` — a sweep of a named subset

```json
{ "type": "designatedCountySweep",
  "counties": ["ALL", "CAB", …], "need": 5, "points": 500 }
```

**The existing enum cannot carry this.** `workStation` keys on a callsign;
`mobileCountyCount` and `activatedCountyCount` count counties per station and per
activation; `sweepTiers` counts any county. Extending `sweepTiers` with an
optional subset was considered and rejected: its tier machinery reads
`workedValues(.county)` — the multiplier-derived set — where the sponsor's
predicate is *"at least one QSO is made with a station in"*, which is
row-derived. Two derivations under one case would be a silent trap. A new case
keeps each predicate stated once.

The predicate lives in one `ScoreEngine` helper used by both the score and the
sidebar's progress readout, so the number shown and the number paid cannot drift.

## 4. Does the shape cover anyone else?

Three parties have banked "the points table needs more than the mode" gaps, and
this shape settles exactly one of them:

| Party | What it wants keyed on | Covered here? |
| --- | --- | --- |
| **NCQP** | received **county**, as a multiple | **yes** |
| **OQP** | received **callsign** — five club stations at a flat 10 points | no: different key *and* flat rather than a multiple |
| **DEQP** | **band** (6 m and up), and the entrant's own role | no: neither key is a location |

So this ships as the county-keyed shape it is, named for what it keys on rather
than for North Carolina, and leaves room for a callsign-keyed sibling and an
explicit-table alternative to arrive later under Article 4. Ontario's five club
stations are **not** built here — a flat per-callsign rate is a different field,
and Article 9 says one party per commit.

The sweep shape is more general than its one user: any party designating a subset
and paying for *n* of it is now expressible, including a tiered version if one
turns up (a second rule, not a second field).

## 5. Commits

**Commit 1 — engine, party-free.** `countyPointFactor` +
`PointsTable.scaled(by:)`, the `designatedCountySweep` case and its evaluation,
the sidebar branch, and `Tests/Core/DesignatedCountyScoringTests.swift` over a
synthetic party — modelled on
[`BonusScopeTests`](../../../Tests/Core/BonusScopeTests.swift), including its
Article 4 proof that no bundled party's score moves. No party JSON changes.

**Commit 2 — NCQP alone.** `gen_ncqp.py` emits both rules from the `RAREST`
constant it already cross-checks against the rules PDF, with the factor and the
sweep numbers parsed from the rules text rather than typed (Article 2); notes
lose KNOWN LIMITATIONs 1 and 2 and renumber; `gen_caveats.py` drops the two
`scoreAffecting` caveats; the two pinning tests in
`NorthCarolinaQSOPartyTests` flip from "does not pay" to the sponsor's own
arithmetic; README's NCQP entry, test count and worklist entry follow (Article 6).

NCQP stays `verified: partial`: the self-activation multiplier (in-state only)
is untouched and keeps its caveat, so the badge roster does not move.

## 6. Testing

Engine, party-free:

- a factor county pays `factor ×` the mode rate, an ordinary one does not;
- the scaled points land **inside** the multiplication — the same log scored
  with and without the factor differs by `9 × points × mults`, not `9 × points`;
- the factor composes with `homeStationPoints` (base table, then scale);
- absent `countyPointFactor` decodes to `nil` and every points value is unchanged;
- the sweep pays at `need`, not at `need − 1`, pays **once** past `need`, ignores
  counties outside the designated list, and is not paid twice by a dupe;
- no bundled party gains a `countyPointFactor` or a `designatedCountySweep`.

NCQP, per Article 18:

- CW with `GRM` = 30, phone 20, digital 50 — the sponsor's printed table;
- `DAV` (rare) and `DVD` (not) pay differently, which is the trap the county
  generator exists for;
- five rare counties pays 500, four pays 0, all ten still pays 500;
- an in-state entrant earns the 10× too;
- a worked end-to-end total combining both rules with the multiplier.

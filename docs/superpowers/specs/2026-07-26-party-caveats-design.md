# Typed party caveats — replacing the binary `verified: partial` warning

**Status:** approved 2026-07-26. Supersedes the UI half of
[Article 3](../../CONSTITUTION.md#article-3--verified-or-explicitly-partial-never-silently-uncertain);
that article is amended in the same commit as the behaviour.

## The problem

**38 of 45 parties (84%) carried the orange ⚠︎.** After `b91a974` made the alert
text readable it is 39 of 46, because the marker is unchanged — that commit fixed
*how* the warnings read, not *how many* parties raise one.

A signal that fires on 84% of rows is not a signal. It is the default state, and
it makes the picker read as a list of broken things. Worse, it flattens four
genuinely different situations into one triangle:

| What the notes actually say | Does it affect the operator? |
| --- | --- |
| MNQP: "the exported Cabrillo is not submittable as it stands" | **Yes — the log is rejected** |
| NCQP: "an NCQP score from this app is a floor, not a total" | **Yes — the score is wrong** |
| NHQP: whether NH counts itself as a multiplier is not stated | Maybe — one multiplier, defensible either way |
| AZQP: rules are the 2025 revision under a 2026 banner | No — a maintenance reminder |
| GAQP: "no band list can change a score, only which rows the app accepts" | No |

The first two deserve to interrupt someone. The last three do not.

## Design

### Schema — `caveats`, additive

```json
"caveats": [
  { "kind": "scoreAffecting",
    "summary": "Score is a floor — the fractional power multiplier isn't applied.",
    "detail": "<the existing KNOWN LIMITATION text, copied verbatim>" }
]
```

Five kinds, ordered by severity:

| kind | means | badges? |
| --- | --- | --- |
| `exportBlocking` | the log this app writes cannot be submitted as-is | **yes** |
| `scoreAffecting` | the app's total will differ from the sponsor's | **yes** |
| `ruleInference` | the app resolved a genuine ambiguity by inference | no |
| `provenance` | source stale or archived; re-check before the next running | no |
| `cosmetic` | no scoring or export consequence | no |

`caveats` defaults to `[]` when absent, so **every existing party decodes and
scores identically**. It is never read by `ScoreEngine` — it is descriptive only,
which is what makes the migration commit safe to do in one pass.

`isPartiallyVerified` **stays**. The Article 3 marker remains mandatory in
`notes` and stays covered by `PartyCatalogTests`; it simply stops driving the UI.
`operatorAlerts` stays too, as the fallback for any party — including a
user-installed one — that carries no typed caveats.

### Why `ruleInference` sits below the badge line

An inference like "NH does not count itself" can move a score by one multiplier,
so the case for badging it is real. It loses on volume: roughly 15 parties carry
one, which puts the badge straight back to a third of the catalogue and rebuilds
the problem this design exists to remove. They remain visible in the sheet, in
the informational tone, and in full under Rules provenance.

### UI

**The picker carries no marker at all.** Choosing a contest and understanding how
the app handles it are different jobs, and the sheet re-renders as the selection
changes — so the sheet is already the before-you-commit surface.

In the sheet, under the schedule line:

- `blockingCaveats` non-empty → orange label, then one bullet per summary.
  Phrased as an app-capability statement, not doubt: *"Score is a floor — the
  power multiplier isn't applied"*, never *"rules could not be confirmed"*.
- otherwise, advisory caveats (or `operatorAlerts` when a party has no typed
  ones) → the `info.circle.fill` secondary tone `b91a974` already built.
- `exportBlocking` additionally surfaces at Cabrillo export time, which is when
  "this log isn't submittable" actually matters.
- Rules provenance disclosure: unchanged.

Expected result: **12–18 parties badge instead of 39**, and each badge names
something the operator can act on.

### Migration

`detail` is copied **programmatically** from the existing `KNOWN LIMITATION` /
`OPEN QUESTION` sections by a one-time script, per
[Article 2](../../CONSTITUTION.md). Only `kind` and `summary` are authored, and
those are judgement rather than transcription.

Promoting the `KNOWN LIMITATION` marker wholesale was considered and rejected: it
badges 26 parties (58%). The per-item classification is the whole point.

## Companion work (same session, separate commits)

1. **Nebraska namespace collision.** `gen_neqp.py` generates
   `newenglandqp.json`, and `neqp_rules.md` / `neqp_rules_2026.txt` /
   `neqp_counties_2026.tsv` are New England's — they overwrote Nebraska's at
   14:09 on 2026-07-26. Nebraska has **no generator and no research doc**, so its
   county list is unregenerable and count-unasserted, an Article 2 hole. Rename
   New England's to `newenglandqp_*`, then re-fetch and rebuild Nebraska's.
2. **Catalog consistency test.** For every party with `homeStates.count > 1`,
   group its counties by `County.state` and assert the name set equals that of
   the standalone party whose `homeState` matches. Verified clean by hand today
   for ME/NH/VT and AZ/ID/WA; the test stops future drift.
3. **Canadian Prairies.** Attempt the unblock paths in
   [`cpqp_blocked.md`](../../research/cpqp_blocked.md). If no machine-readable
   district list with a self-checkable count appears, it stays blocked and the
   research doc records the attempt. No guessed list ships.

## Commits

Article 5 wants the structural change party-free; Article 9 wants one party per
commit.

1. Schema + UI + tests + Article 3 amendment + README — no party JSON touched
2. Caveat population across all parties — data only, no scoring change.
   **A deliberate Article 9 exception:** this is a cross-cutting migration, and
   caveats cannot cause a scoring regression because the engine never reads them.
3. New England research rename
4. Nebraska research + generator restoration
5. Catalog consistency test
6. Canadian Prairies — party or research-doc update, per what the sources yield

## Out of scope

Merging the umbrella parties with their standalone namesakes. New England,
7QP and their member-state parties are **different contests with different
sponsors, dates and rules**; county names were verified identical across all six
overlaps today. `2d3cc9a` already grouped the four May-weekend parties under a
combined entry, which is the correct form of consolidation and needs no follow-up.

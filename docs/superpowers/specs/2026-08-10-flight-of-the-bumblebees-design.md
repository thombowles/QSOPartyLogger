# ARS Flight of the Bumblebees support — design

2026-08-10. Requested by KE5CW ("add the flight of the bumble bees contest").
Rules research: [`fobb_rules.md`](../../research/fobb_rules.md) — read that
first; this document is only the mapping onto the app.

FOBB is the third non-State-QSO-Party contest in the catalogue (NAQP, Skeeter
Hunt) and the second QRP sprint — it is the ARS event the Skeeter Hunt was
modelled on, so **almost all of its machinery already exists**: the
number-or-power exchange element, its entry field, prefill, `{MEMBER}` macro,
exports, the no-county/no-home-region party shape, and the roster-download
concept all shipped with Skeeter. What FOBB adds is a different *scoring
geometry* — the sponsor's printed formula is

    [Total Score] = [Total Contacts] × [Number of Bumblebees] × 3

— which needs **two small engine shapes** (a membership multiplier class and
a multiplier floor) and **one roster kind** (a stable-URL HTML table instead
of a discovered Google Sheet). Both engine shapes are modelled generically
under Article 4: optional fields, defaults that leave all 49 existing parties
byte-identical, proven by the existing suite. Unlike Skeeter, FOBB has **no
entry classes, no bonuses, and no location multipliers at all** — the S/P/C
is exchanged, validated, and worth nothing.

## Phase plan (Articles 4 and 9)

Commits may be finer than these phases (the plan commits per task), but no
commit mixes phases and every commit touches FOBB alone:

1. **Engine, party-free** — `MultClass.member` + `MultRule.multiplierFloor`,
   their plumbing, sidebar label, and tests.
2. **Roster download, party-free** — the `CallHistorySource` kind for the
   ARS self-serve roster report, its parser, client wiring, fixtures, tests.
3. **The party** — `gen_fobb.py` → `fobb.json`,
   `FlightOfTheBumblebeesTests`, generator-roster updates (pipeline order:
   `gen_hub_map` → `gen_callhistory` → `gen_caveats`, 49→50), the
   roster-pinning test edits, README/PARTIES/PROVENANCE.

## 1. `MultClass.member` — Bumblebees worked as the multiplier

The score's multiplier side is "valid contacts whose received member element
is a number, counted per band" — "Working the same Bumblebee on a different
band counts as an additional Contact **and as an additional Bumblebee
Worked**." A new `MultClass` case rides the entire existing multiplier
machinery (keys, NEW MULT badge, sidebar count, roster, `newMultRowIDs`)
instead of inventing a parallel counter:

- **Contribution rule**: when the party carries `memberExchange` and the
  row's `memberRcvd` parses as `.member`, the row contributes
  `MultKey(.member, value: raw logged callsign uppercased, scope: ordinary
  countScope component)`. FOBB's `countScope: "perBand"` makes one bee on
  three bands three keys; same band twice is already a dupe. The count
  therefore equals valid Bumblebee contacts exactly — [Number of
  Bumblebees].
- **Raw-call identity, deliberately**: dupe checking already keys the raw
  call, and the member key follows it. `K3JZD/BB` on 40 m plus `K3JZD` on
  20 m = two contacts, two bees — correct regardless (different bands). The
  same-band retype case is ordinary call-typo variance, not modelled
  (research §14.7).
- **Plumbing**: `multContributions` gains the received member element (it
  already takes `call`); `score()` passes `row.memberRcvd`.
  `wouldAddMultiplier` gains `call:` and `memberRcvd:` inputs so the entry
  bar's badge can light up for "a bee you have not worked on this band" —
  the sponsor's own advice ("try looking for Bumblebees on all of the
  bands"). Callers that pass locations only get `nil`/empty defaults and
  behave exactly as before.
- **Display**: `ScoreSidebar`'s class labels source `.member` from
  `party.memberExchange.memberPlural` ("Bumblebees") — data, not a party
  special case. `MultiplierRoster` builds its sections from enumerable
  token sets, which the member class deliberately has none of, so no
  roster grid appears — the worked-bee count surfaces as the multiplier
  count plus the existing Bumblebee/QRP/QRO figures the sidebar already
  renders from `memberQSOs`. `NeededMult` already guards on
  `classes.contains(.county)` and needs nothing; the member class is not
  enumerable in advance (any call may turn out to be a bee), so nothing
  may try to chip it.
- **No location classes for FOBB**: `classes: ["member"]` both sides. The
  received S/P/C is still validated and logged (`dxStyle: "prefix"`,
  `acceptsDXToken: true`, no `dx` class — NDQP proved prefix-without-
  counting, NAQP proved token-with-no-class; FOBB combines them), and
  contributes nothing, by construction, at the existing
  `wantedClasses.contains` gate.

## 2. `MultRule.multiplierFloor` — "(Defaults to … [Number of Bumblebees] = 1)"

The sponsor prints the floor in the scoring block: a home station that
works no Bumblebee still scores `contacts × 1 × 3`.

- `var multiplierFloor: Int { multiplierFloorRaw ?? 0 }` on `MultRule`,
  beside its mirror `maxScoredMultipliers`. `ScoreBreakdown` carries it like
  `multiplierCap`, and
  `multiplierCount = max(floor, min(multiplierKeys.count, cap))`.
- Default 0 reproduces today's arithmetic everywhere (`max(n, 0) = n`);
  FOBB sets 1 on both sides.
- An **empty log still totals 0** because `qsoPoints` is 0 — which matches
  the one zero row observed on the sponsor's calculator (K4UPG, research
  §8). The genuinely unobserved edge (contacts > 0, bees = 0 → `3·C` here)
  is the party's OPEN QUESTION 1 and a `ruleInference` caveat.
- Sidebar: when the floor binds, the multiplier row shows 1 with no listed
  values — mirroring the sponsor's own form default, and pinned by a test.

## 3. The ×3, folded into points

`points: {phone: 3, cw: 3, digital: 3}` and `memberExchange` with
`memberPoints = qrpPoints = otherPoints = 3`: every valid contact pays 3
regardless of what was received, so
`total = qsoPoints × multiplierCount = 3·C × max(1, B)` — the sponsor's
product exactly, inside the engine's existing shape, with **zero** scoring
code beyond §§1–2. The element still gates logging, drives the
Bumblebee/QRP/QRO sidebar counters, and prefills — it just never moves the
rate. `qrpMaxWatts: {phone: 5, cw: 5, digital: 5}` from the event's own
"5W QRP Maximum" (cosmetic here — the split never changes a score).

## 4. Roster download (the "history file")

No N1MM file exists (inventory grep 2026-08-10). Unlike Skeeter's
per-season Google Sheet, the ARS roster is a **stable URL** — the sponsor's
own self-serve report `https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php`,
a plain HTML table `BB | Callsign | Name | SPC | Expected Location`. So the
kind is *simpler* than Skeeter's: no discovery hop.

- `CallHistorySource.Kind` gains `.arsFobbRoster`. FOBB ships
  `{"kind": "arsFobbRoster", "pageURL": "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php",
  "filePrefix": "FOBB", "token": "FOBB ROSTER"}` — bundled in JSON so a
  user file can override it mid-season (Article 21).
- `FOBBRosterParser` (sibling of `SkeeterRosterParser`, same drift stance):
  parse the table, require the observed header, accept rows with an
  all-digit number and a non-empty call; unrecognized markup is an explicit
  `nil`, never a silent empty. Convert to N1MM call-history text (`# FOBB
  ROSTER` + `!!Order!!,Call,Name,State,Exch1`, S/P/C in State, number in
  Exch1) so the store, token gate, parser and prefill pipeline run
  untouched.
- **Emit each bee under both `CALL` and `CALL/BB`**: bees sign /BB on the
  air and `CallHistoryFile.entry(for:)` is an exact-match lookup, so the
  double row is what makes prefill fire however the operator types the
  call. One call under two numbers (NN5DE in the banked capture) follows
  whatever `CallHistoryFile` already does with a repeated call — the
  Skeeter K3UT case, pinned in the parser tests, not special-cased.
- **Live data**: numbers issue until the event and the table resets per
  event (self-serve opens one month before), so the kind re-downloads on
  the ordinary 24 h staleness clock with no unchanged-revision
  short-circuit — exactly the Skeeter client arrangement. Between events
  the report serves the *previous* event's numbers; that is prefill-hint
  staleness, recorded in notes, and costs nothing (log what you copy).

## 5. The party itself (`fobb.json`, highlights)

- `id: "fobb"`, name "ARS Flight of the Bumblebees", `homeState: "NA"`,
  `hasHomeRegion: false`, `counties: []`, `countyAbbrLength: 2`,
  `maxSimultaneousCounties: 1` — the Skeeter shape.
- `allowedModes: ["cw"]` (first CW-only party since NAQP CW), bands
  80/40/20/15/10 from the Target Scents list (inference note, as Skeeter).
- `dupeScope: "bandMode"` — under one legal mode this **is** the sponsor's
  per-band rule, so Skeeter's Mixed-entry open question does not exist here.
- Mult rule both sides: `{"classes": ["member"], "homeStateCountsViaCounty":
  false, "countScope": "perBand", "multiplierFloor": 1}`.
- `bonuses: []`, no `entryClasses`, no `scoreMultipliers` — all explicit
  NONEs in the research (§§7–8).
- **Two windows** (NAQP CW precedent), both sponsor-printed: 2026-07-26
  1700–2100Z (Legacy; Wayback capture of the sponsor's page, already run)
  and 2026-09-20 1700–2100Z (Fall; live page — the next running).
- `cabrilloContest: "ARS-FOBB"` — app-invented (sponsor accepts no log
  files; WA7BNM has no entry, fetched 2026-08-10), cosmetic caveat; the
  sidebar carries the two numbers the 3830 form wants.
- `verified: partial` with **OPEN QUESTION 1** (the zero-Bumblebee log,
  research §8). Four caveats: that `ruleInference`; the invented-Cabrillo
  `cosmetic`; a second `cosmetic` for the roster serving the previous
  event's numbers between events (prefill hint only); and a `provenance`
  caveat (page edited in place, "Last Updated : 27JUL26" the only marker;
  never read dates from the stale HTML title). None badge — the party
  warns nobody.

## 6. `gen_fobb.py` (Article 2 for a no-county party)

Emits `fobb.json`, mirroring `gen_skeeter.py`: required sponsor quotes
asserted present in the banked rules text (both captures); the score
formula re-verified over the banked 3830 CSV — **all 90 rows must satisfy
`score = QSOs × Bumblebees × 3` exactly**, the four section names and the
K4UPG zero row asserted; roster assertions over the banked CSV — 234 rows,
all numbers unique, spot checks (K2SQS #1 NJ, W4KAC #7 NC, K4KBL #234 GA,
NN5DE under two numbers); the notes' markers asserted. A wrong formula, a
drifted page, or a hand-edited roster cannot regenerate the file.

## Test plan

- Party-free engine: `MemberMultiplierTests` (contribution fires only on a
  parsed number — power and blank contribute nothing; per-band keys; raw
  `/BB` identity; the `wantedClasses` gate for parties without the class;
  badge inputs), `MultiplierFloorTests` (floor 0 default no-op, floor 1
  with zero keys, floor × cap interplay, empty log still 0, sidebar
  binding), `ScoreSidebar` label from `memberPlural`, `NeededMult` skip.
- Party-free roster: `FOBBRosterParserTests` over the banked fixture
  (header drift → nil, CALL + CALL/BB double emission, NN5DE repeated-call
  behavior pinned, token in output), client tests over the scripted mock
  fetcher (success, non-200, drift failure, daily re-check, no
  short-circuit).
- Party: `FlightOfTheBumblebeesTests` mirroring `SkeeterHuntTests` — shape,
  both schedule instants, exchange parsing end-to-end (S/P/C + member
  gating, `DL` prefix accepted, `DX` token accepted, member element
  required to parse or be blank), uniform 3 points including a blank
  element, member mult per band with a would-fail-per-once case, the floor
  (N contacts + 0 bees = 3·N), dupes (same band = dupe, new band = new
  contact **and** new bee), CW-only (phone row invalid, not zero-point),
  synthetic-log totals `3·C·B` checked against 3830-style arithmetic,
  Cabrillo/ADIF member columns, not a Challenge contest.
- Roster-pinning edits (deliberate, in the party commit):
  `PartyCatalogTests` id set + `expectedPartial` (+fobb),
  `CallHistorySourceTests` count and special-kind set,
  `ChallengeTests` subtraction set, `ExchangeParserTests` prefix-party
  count, `MessageDefaultsTests` member-shape predicate,
  `DelawareQSOPartyTests` fewest-counties (second zero-county party),
  `WisconsinQSOPartyTests` shortest-window superlative (**FOBB ties
  Skeeter at 4 h per window** — read the assertion and restate it
  deliberately), `UpcomingContestsTests` (a Sept 20 window lands amid the
  pinned September ordering).

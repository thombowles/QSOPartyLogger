# NJQRP Skeeter Hunt support — design

2026-08-04. Requested by KE5CW ("Add NJQRP Skeeter Hunt contest support,
including multiplier counting, history file download"). Rules research:
[`skeeter_rules.md`](../../research/skeeter_rules.md) — read that first; this
document is only the mapping onto the app.

The Skeeter Hunt is the second non-State-QSO-Party contest in the catalogue
(NAQP was the first) and the first QRP sprint. Four engine shapes are new, and
all four are the *standard QRP-club-sprint shapes* (ARCI/SKCC/NAQCC events
share them), so each is modelled generically under Article 4 — optional
fields, defaults that leave all 48 existing parties byte-identical, proven by
the existing suite.

## Commit plan (Articles 4 and 9)

1. **Engine, party-free** — the four schema shapes below, their UI, exports,
   macro, and tests.
2. **Roster download, party-free** — the `CallHistorySource` kind for W2LJ's
   roster page, its parser, client wiring, fixtures, tests.
3. **The party** — `gen_skeeter.py` → `skeeter.json`, `SkeeterHuntTests`,
   generator-roster updates (`gen_caveats.py` 48→49, `gen_callhistory.py`
   special source), the roster-pinning test edits, README/PARTIES/PROVENANCE.

## 1. `memberExchange` — the number-or-power element

`PartyDefinition.memberExchange: MemberExchange?` (new type, every field
required — the `ActivatedCountyMultiplier` lesson):

```jsonc
"memberExchange": {
  "term": "Skeeter number",     // display-ready, proper noun preserved
  "shortTerm": "Skeeter #",     // field/column label
  "memberPoints": 3,            // received a member number
  "qrpPoints": 2,               // received a QRP power
  "otherPoints": 1,             // received anything else
  "qrpMaxWatts": {"phone": 10, "cw": 5, "digital": 5}   // inclusive, per mode class
}
```

- **Value grammar** (`MemberExchange.parse`): digits alone = member number;
  a power **requires its unit** (`W`/`MW`/`KW`, case-insensitive, decimal
  allowed) so "5" (number 5) and "5W" (five watts) cannot collide. Anything
  else is invalid and cannot be logged — the element gates logging exactly as
  the NAQP name does.
- **Points**: when the party carries `memberExchange` and the row's received
  element parses, `ScoreEngine` takes the element's points instead of the
  mode table; an unreadable/absent element falls back to the mode table
  rather than guessing. `ScoreBreakdown` gains `memberQSOs/qrpQSOs/otherQSOs`
  counters so the sidebar can show the three counts the sponsor's summary
  email asks for.
- **Fields**: `QSO.memberSent/.memberRcvd: String?` (nil for every existing
  log — decode unchanged); `ContestLog.exchangeMember: String` (the
  contest-long sent value, like `exchangeName`; a Skeeter enters their
  number, everyone else their power, in Contest Setup).
- **Entry bar**: the received field joins the Space chain **after** Exchange
  — the sponsor's order is "RST, S/P/C, Skeeter number" ("559 NJ NR 13"), so
  `.exchange → .memberRcvd → .call`. Prefill mirrors the name chain: last
  logged row wins, then the call-history candidate (the first roster value
  that parses as a member token).
- **Exports**: Cabrillo `qsoLine` appends the member element after each
  side's location column when the row carries one (row-driven, no party
  branching; existing golden lines unchanged because nil appends nothing).
  ADIF uses `APP_QSOPARTYLOGGER_MEMBER_SENT/RCVD` — `STX_STRING`/`SRX_STRING`
  are already occupied by locations, and ADIF has no standard field for a
  member number.
- **Macro**: new `{MEMBER}` token, expansion self-shaping: a member number
  expands to `NR 13` (the on-air convention in the sponsor's own sample QSO),
  a power to `5W` verbatim. Never cut (it is not always a number).
  `MessageSets.defaults(for:)` appends it after `{EXCH}`; the
  `isReportShape` predicate in `MessageDefaultsTests` learns the new flag.

## 2. `entryClasses` — the X1–X4 station class

The sponsor's class table (home/portable × commercial/homebrew paying
1/2/3/4) is **not a product of per-axis factors** (that would pay 6 for
portable homebrew), so it cannot ride `scoreMultipliers`. It is an
irreducible self-declared class:

```jsonc
"entryClasses": [
  {"id": "X1", "label": "Home station, commercial equipment", "factor": 1},
  ...
  {"id": "X4", "label": "Portable station, home brewed or kit built", "factor": 4}
]
```

- `ContestLog.entryClassID: String` (default ""), picked in Contest Setup via
  a data-gated `Picker` (shown only when the party lists classes — no party
  branching in UI). An unset/stale id resolves to the **first** listed class,
  which parties list lowest-factor first — the app never claims a multiplier
  the operator did not.
- `ScoreEngine` multiplies the resolved class factor into the existing
  `categoryFactor` (`ScoreFactor`, exact) — the sidebar's "Category ×" row,
  the archive's `categoryFactor`/`categoryFactorExact` pair, and `total`
  all follow with **zero further schema change** (single-writer confirmed at
  `ScoreEngine.score`).

## 3. `BonusRule.callAreaSum` — Skeeter Hunt Blackjack

`{"type": "callAreaSum", "target": 21, "points": 1000}` — pays once when any
subset of **distinct** worked callsigns' call-area digits (first decimal
digit in the call; `0` counts 10) sums to exactly `target`. Subset-sum over
values 1–10 with a boolean DP array — each call usable once, per the
sponsor's "You can use any call sign worked ONCE". Calls with no digit
contribute nothing. The operator still lists the callsigns in the summary
email themselves (cosmetic caveat).

## 4. Empty county list

`validate()` now permits `counties: []` **only** when `hasHomeRegion ==
false` — the Skeeter Hunt's multipliers are entirely the default
state/province tables plus DXCC entities, so there is nothing to enumerate,
and inventing a list to satisfy the guard would be fiction. Audited fallout:
sidebar/roster/grouping all no-op on empty (guarded at `MultiplierRoster`),
`ExchangeParser` falls through cleanly, `countyAbbrLengthHint` falls back;
the one cosmetic hole is `SetupSheet.locationHint`'s "0 location codes"
string, fixed to drop the county clause when the list is empty.

## 5. The party itself (`skeeter.json`, highlights)

- `homeState: "NA"` pseudo-state (NAQP precedent), `hasHomeRegion: false`,
  `counties: []`, `countyAbbrLength: 2`.
- Mult rule both sides identical: classes `[state, province, dx]`,
  `countScope: "once"`, `dxCountsEntities: true`, `dxStyle: "prefix"`,
  `acceptsDXToken: true` (a DX entrant can be `DX`; a received bare `DX`
  resolves its entity from the callsign — the OQP pairing).
- `points: {phone: 1, cw: 1, digital: 1}` — the documented floor the member
  element supersedes on every gated row.
- `dupeScope: bandMode` with a `ruleInference` caveat: the sponsor names
  bands only ("Stations can be worked on different bands"); same-band
  cross-mode is unstated and arises only for Mixed entries.
- `allowedModes: ["phone", "cw"]`, bands 80/40/20/15/10, one window
  2026-08-16 1700–2100Z.
- `cabrilloContest: "SKEETER-HUNT"` — app-invented (sponsor accepts no log
  files at all; WA7BNM registry has no entry), cosmetic caveat.
- `verified: partial` with the dupe-scope OPEN QUESTION; caveats all
  non-badging (ruleInference / cosmetic / provenance), so the party warns
  nobody.

## 6. Roster download (the "history file")

There is **no N1MM call-history file** for this contest (full inventory grep,
2026-08-04). The roster is W2LJ's Google Sheet, whose document id changes
every season; the **stable discovery point** is the blog page that links it —
the same role the N1MM listing URL plays for every other party. So:

- `CallHistorySource` gains `kind` (`"n1mm"` default — absent in all 48
  existing files) and `pageURL`. Skeeter ships
  `{"kind": "w2ljRosterPage", "pageURL": "http://w2lj.blogspot.com/p/njqrp-skeeter-hunt.html",
  "filePrefix": "SKEETER", "token": "SKEETER ROSTER"}`. Bundled-in-JSON
  rather than hardcoded so a user file can override it mid-season
  (Article 21).
- Client flow for the kind: GET the page → find the spreadsheet link nearest
  the phrase "Skeeter Hunt roster" (the page also links ~14 *scoreboard*
  sheets; the phrase anchor is what distinguishes them; unrecognized markup
  is an explicit failure, never a silent empty) → GET
  `.../export?format=csv` → **convert to N1MM call-history text** (`# SKEETER
  ROSTER` comment + `!!Order!!,Call,Name,State,Exch1` with S/P/C in State and
  the number in Exch1) → the existing token check, store, parser and prefill
  pipeline run **untouched**. Location prefill offers the S/P/C (the number
  fails location parse); member prefill offers the number (the S/P/C fails
  member parse) — both from `Entry.locations`, no format change.
- The sheet is **live** (numbers issue until the day before the event), so
  the kind re-downloads on the ordinary 24 h staleness clock instead of the
  revision short-circuit.
- Roster data remains a hint, never a rule: prefill only, everything
  re-validated by the party's own parsers, nothing reaches `ScoreEngine` —
  points come from the received exchange, not roster membership.

## Test plan

- Party-free: `MemberExchangeTests` (grammar, points, scoring fallback,
  counters), `EntryClassTests` (resolution, factor→archive flow),
  `CallAreaSumBonusTests` (subset-sum edges: exact hit, no subset, 0→10,
  distinct-call rule), `NoCountyPartyTests` (validate gate both ways),
  roster parser/converter tests over banked fixtures, client tests over the
  scripted mock fetcher.
- Party: `SkeeterHuntTests` mirroring `NorthAmericanQSOPartyCWTests`
  (shape, schedule instants, exchange parsing incl. member gating end-to-end,
  mults once-scope with a would-fail-per-band case, 3/2/1 points incl. the
  QRP boundary 5 W CW vs 10 W phone, X-class factors, blackjack, dupes,
  Cabrillo/ADIF lines, not-a-Challenge-contest).
- Roster-pinning edits (deliberate, each in the party commit):
  PartyCatalogTests id set + `unrestricted` + `expectedPartial`,
  CallHistorySourceTests 45→46, ChallengeTests subtraction set,
  ExchangeParserTests 16→17 prefix parties, MessageDefaultsTests shape
  predicate, DelawareQSOPartyTests fewest-counties, WisconsinQSOPartyTests
  shortest-window superlative (Skeeter's 4 h takes it), UpcomingContestsTests
  (verify the pinned first-three are unaffected by an Aug 16 window).

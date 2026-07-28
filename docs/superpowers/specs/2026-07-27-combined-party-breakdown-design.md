# Per-member QSO breakdown for a combined entry

**Status:** approved 2026-07-27. Applies to any party with a non-empty
`combines` list; today that is `in7qpne` alone.

## The problem

`in7qpne` is one log covering four sponsors — Indiana, the 7th Call Area, New
England, and Delaware. The State QSO Party Challenge counts **each of the four
separately**: its formula is `Σ valid QSOs × parties entered`, and *"Entrants
must make at least two contacts in a QSO party for it to count as a
multiplier."* All four are on the 2026 approved list.

Two things follow, and the app got both wrong.

**1. The operator cannot see whether they have qualified.** The sidebar shows
one QSO total and one flat 422-chip county grid. Nothing says how many of those
contacts Delaware would count — and Delaware has *three* counties, so it is the
one you miss.

**2. A combined log scores zero in the Challenge.** `ChallengeStanding.compute`
matches `record.partyID` against the approved-contest list. `in7qpne` is not on
it (47 contests, none combined) and `contest(named:)` will not match its display
name either, so the record lands in `notApproved`: zero QSOs, zero multipliers.
A weekend worth up to four multipliers counted for nothing.

## The trap: the members do not share a band or mode list

| Party | Bands | Modes |
| --- | --- | --- |
| `in7qpne` | 160m–70cm (10) | phone, cw, digital |
| `inqp` | 160m–10m | phone, cw — **no digital** |
| `sevenqp` | 160m–10m | phone, cw, digital |
| `newenglandqp` | **80m–10m — no 160m** | phone, cw, digital |
| `deqp` | 160m–70cm | phone, cw, digital |

The combined entry's own notes say so: *"the band and mode lists are unions too,
so a QSO can be logged that one member contest would not count."*

So counting *"rows whose county is in Indiana"* overstates INQP — two digital
Indiana contacts would read as qualified when INQP counts zero. A naive split
gives the wrong answer about the exact question being asked.

## Design

### `Sources/Core/Engine/CombinedLogSplit.swift` — new

For each member: scope the log to the rows that member's sponsor would look at —
`theirLoc` in **that member's own county list**, `band` in **that member's
`validBands`** — and hand the result to `ScoreEngine.score(log:party:member)`
unchanged. The member's own verified definition then supplies its modes, its
points, and its dupe scope.

```swift
struct MemberLine: Identifiable, Equatable, Sendable {
    let party: PartyDefinition
    let validQSOs: Int
    let countiesWorked: Set<String>
    let ignored: Int          // logged, but this sponsor does not count it
    var qualifiesForChallenge: Bool { validQSOs >= 2 }
}

static func split(log:combined:members:) -> [MemberLine]
static func expand(records:parties:) -> [ContestRecord]
```

**No new scoring rules.** Every number traces to a sponsor's own JSON through
the same fold the sidebar already displays, which is what keeps this out of
Article 1's way — a split that reimplemented four sponsors' scoring would be
model recall wearing a function signature.

The county pre-filter is applied **regardless of `myLocation.isInState`**. The
combined entry is for an operator outside all four regions and
`PartyCatalog.suggestedParty` steers them there, but nothing stops an in-region
operator selecting it; without the filter `ScoreEngine.inScopeRows` would then
be a no-op and every QSO would count for every member.

#### Why the band filter lives here, not in `ScoreEngine`

`ScoreEngine` does not enforce `validBands` today — it filters on
`allowedModeClasses` and `outStateWorksHomeStationsOnly` only. Bands are
enforced in the entry UI (`RadioBar.swift:225`, `EditQSOSheet.swift:40`).
Moving that into the engine would change scoring for all 46 parties at once,
which Article 4 wants as its own party-free commit. Filtering inside the
splitter is additive and leaves every existing score identical.

### Sidebar — `Sources/UI/CombinedBreakdownSection.swift`

Rendered when `!party.combines.isEmpty`. Driven by that field, never by
`id == "in7qpne"`, per the layout rule that `Sources/UI` carries no
party-specific branching.

```
PER-PARTY QSOs                        3 of 4 qualified
  Indiana QSO Party            14  ✓     9/92 counties
  7th Call Area QSO Party      31  ✓    22/259
  New England QSO Party         6  ✓     5/68
  Delaware QSO Party            1  ⚠     1/3    needs 2
```

The ✓/⚠ threshold is the Challenge's two-QSO rule, already sourced in
`ChallengeStanding`. No new keyboard surface: the section is not collapsible and
the sidebar is already on screen, so Article 9 is met by what exists.

### County grid — grouped by party, then state

One generic rule replaces the flat grid: **group by member party, then by
state**. A member with a single state (Indiana, Delaware) gets no redundant
state row. A party with no `combines` and one state renders exactly as it does
today. Standalone `sevenqp` and `newenglandqp` gain state sub-headers as a side
effect of the same code path — an improvement, and cheaper than a special case.

### Challenge — `expand` before `compute`

`CombinedLogSplit.expand(records:parties:)` replaces a combined `ContestRecord`
with one record per member: same year and callsign, the member's `partyID`, and
a `ScoreSnapshot` recomputed under that member's rules from the member-scoped
rows. `ChallengeStanding.compute` is untouched, and each member line then
matches the approved list by its own id.

Only `DashboardModel.standing` sees the expanded set. `SeasonStats` keeps the
unexpanded records, so the season's contest count and totals do not double.

## Tests — `Tests/Core/CombinedLogSplitTests.swift`

Each proven red before the implementation lands.

- A 160 m QSO with a Connecticut county counts for **none** of the four — New
  England has no 160 m, and no other member owns a CT county.
- A digital QSO with an Indiana county gives INQP zero.
- One Delaware QSO does not qualify; two do.
- Each of the 422 counties belongs to exactly one member, so no contact is
  double-counted across the split.
- The four members' valid QSOs never exceed the combined entry's own count.
- An `in7qpne` record expands to four approved `PartyLine`s with multiplier 4,
  where today it yields zero and one `notApproved` row.
- An in-region `myLocation` does not leak rows across members.

## Out of scope

Per-member **scores**. The four sponsors pay different points and count
multipliers on different scopes; the combined entry's `scoreAffecting` caveat
already says the score is indicative only and points at the 4QP parsing tool at
stateqsoparty.com. This change reports QSO counts and counties, which are facts,
and leaves scores where the caveat leaves them.

# Activated-county multipliers — design

**2026-07-28.** Five sponsors give an in-state station a **multiplier** for each
county it operates from. The repo models the *bonus points* half of that shape
(`BonusRule.activatedCountyCount`) and not the multiplier half, so five parties
ship a `scoreAffecting` caveat saying so.

A multiplier is not a bonus of the same size. Bonus points are added after
multiplication; a multiplier compounds against every QSO point in the log, so
the shortfall grows with the log rather than staying flat.

## 1. What the sponsors say

Read from the banked research and the raw rule text, per Article 1. **No two of
the five agree**, which is the whole reason this needs a design rather than a
one-line field.

| Party | Sponsor's own words | Source |
| --- | --- | --- |
| **SCQP** | "3. **Each SC county activated.** At least one (1) QSO must be made from a county in order for it to count as activated." — 9.2.2, under the heading *SC Mobile/Expedition Stations*. And 6.2.3: "Expedition stations that operate from more than one county will receive a multiplier (**ONCE PER MODE PER BAND**) for each county activated." | [`scqp_rules_2026.txt`](../../research/scqp_rules_2026.txt) §9.2.2, §6.2.3 |
| **NCQP** | "Note: **NC stations** may include the county from which operation takes place in the Multiplier count **regardless of whether any QSOs are logged from that same county.** This includes Mobile and Portable stations where operations may take place in more than one county. In that case this provision is applied to **each county activated where at least one QSO was completed**." | [`ncqp_rules.md`](../../research/ncqp_rules.md) §6 |
| **VAQP** | "Mobile, Rover, and Expedition stations that contact **10 (ten) or more different stations** while operating from a county or independent city may claim it as a multiplier, **if not otherwise worked**." | [`vaqp_rules.md`](../../research/vaqp_rules.md) §6 |
| **MOQP** | "3. Any **mobile or portable** category entry that makes **50 or more valid contacts** from a county or county lines will be given the multiplier for that county or counties." | [`moqp_rules_2026.txt`](../../research/moqp_rules_2026.txt) line 79 |
| **TnQP** | "Tennessee **mobiles and rovers** may claim **one** multiplier for any Tennessee county from which they complete **at least 10 QSOs** **if they do not earn a multiplier for that county otherwise**." | [`tnqp_rules.md`](../../research/tnqp_rules.md) §Multipliers |

### The five axes they vary on

1. **Threshold** — 1 (SCQP, NCQP), 10 (VAQP, TnQP), 50 (MOQP).
2. **Unit of the threshold** — QSOs everywhere **except VAQP**, which counts
   *ten different stations*. A mobile working one chaser on five bands from one
   county has made five QSOs and contacted one station.
3. **Scope of the granted multiplier** — SCQP states *once per mode per band*;
   the other four grant it once. **TnQP's differs from its own side's
   `countScope`**, which is `perBand` — so the scope cannot be inherited from
   the `MultRule` it sits on, and must be carried.
4. **Which entrant categories qualify** — SCQP mobile/portable/expedition,
   NCQP **every NC station including fixed**, VAQP mobile/rover/expedition,
   MOQP mobile/portable, TnQP mobile/rover. `isRovingCategory`, which gates the
   existing bonus, is wrong for NCQP and wrong in both directions elsewhere.
5. **Whether working the county forfeits the activation multiplier** — stated
   outright by TnQP and VAQP, and settled for NCQP and MOQP by their own
   arithmetic (below). SCQP alone is additive.

The sketch banked in [`WORKLIST-2026.md`](../../parties/WORKLIST-2026.md)
(`activatedCountyMultiplier: {minQSOs: Int}`, gated on `isRovingCategory`,
inheriting the side's `countScope`) is wrong on axes 2, 3, 4 and 5. It was
written when TnQP and SCQP were the only known users.

### The forfeit clause, and the arithmetic that settles it

An activated county that is *also* worked: one multiplier or two?

- **TnQP** — "if they do not earn a multiplier for that county otherwise". One.
- **VAQP** — "if not otherwise worked". One.
- **NCQP** — the rules print **"164 total possible"**, and 164 is exactly
  100 counties + 50 state-class tokens + 13 provinces + 1 DX. If a station's own
  county could count on top of working it, the ceiling would be 165. One.
- **MOQP** — the rules print **"Missouri counties (115 maximum)"**, which is
  exactly the entity list. One.
- **SCQP** — 9.2.2 lists "1. Each South Carolina county" and "3. Each SC county
  activated" as separate numbered multipliers, states **no maximum** anywhere
  (its scope is per band per mode, so no fixed maximum exists), and carries no
  exclusion clause. **Two.**

SCQP being the only additive one is corroborated rather than assumed: it is also
the only one of the five with no stated county ceiling to violate.

## 2. Schema — `MultRule.activatedCountyMultiplier`

An optional object on `MultRule`, so all 46 bundled parties decode with `nil`
and score identically (Article 4). It sits on the **`inState`** side only: a
station operating from a home-state county is by definition in-state, and
`ScoreEngine` already selects the rule by `log.myLocation.isInState`.

```json
"multipliers": {
  "inState": {
    "classes": ["county", "state", "province", "dx"],
    "homeStateCountsViaCounty": false,
    "countScope": "once",
    "activatedCountyMultiplier": {
      "minCount": 50,
      "countUnit": "qsos",
      "countScope": "once",
      "categories": ["MOBILE", "PORTABLE", "EXPEDITION"],
      "notOtherwiseWorked": true
    }
  },
  "outState": { "classes": ["county"], "homeStateCountsViaCounty": false, "countScope": "once" }
}
```

```swift
/// A multiplier a party gives an entrant for each home-state county they
/// *operate from*, as against each county they *work* — five sponsors, and no
/// two of them agree on the threshold, the unit, the scope, who qualifies, or
/// whether working the county forfeits it. Every field is therefore required:
/// this is a new type, so requiring them breaks no existing file, and a
/// default would be one sponsor's rule silently applied to the next.
struct ActivatedCountyMultiplier: Codable, Equatable, Sendable {
    /// How many of `countUnit` must be logged from a county before it counts.
    let minCount: Int
    /// What is counted toward `minCount`.
    let countUnit: CountUnit
    /// How often the granted multiplier counts. **Not** inherited from the
    /// enclosing rule's `countScope`: TnQP counts worked multipliers per band
    /// and grants this one once.
    let countScope: CountScope
    /// The entrant station categories the sponsor names.
    let categories: [StationProfile.CategoryStation]
    /// Whether working the county forfeits the activation multiplier.
    let notOtherwiseWorked: Bool

    enum CountUnit: String, Codable, Sendable {
        /// Valid QSOs made from the county — four of the five sponsors.
        case qsos
        /// Distinct callsigns worked from the county. VAQP: "contact 10 (ten)
        /// or more **different stations** while operating from a county".
        case stations
    }
}
```

### `MultKey` gains an `activated` component

SCQP being additive means an activated county and a worked county at the same
scope must be two multipliers. They are currently the same `Set` element.

```swift
struct MultKey: Hashable, Sendable {
    let multClass: MultClass
    let value: String
    let scope: String
    /// Earned by operating from the county rather than by working it.
    /// Defaults false, so every key built before this change is unchanged.
    let activated: Bool
}
```

`workedValues(_:)` maps to a `Set<String>` and so still reports the county once
for the sidebar's county grid. `classCounts` and `multiplierCount` count keys,
so an additive activation correctly reads as one more multiplier.

### `ScoreBreakdown.selfActivatedCounties`

`Set<String>`, the counties credited by activation — so a per-party test can
assert precisely which, and so a future sidebar line can name them without
re-deriving. Not persisted anywhere: `ScoreBreakdown` reaches only the three
views and `CabrilloExporter`, which reads `total` alone.

## 3. Engine

In `ScoreEngine.score`, **after** `result.bonusPoints` is computed:

- After the worked loop, so `notOtherwiseWorked` can see the worked keys.
- After `bonusPoints`, so `BonusRule.sweepTiers` keeps counting only *worked*
  counties via `workedValues(.county)`. No bundled party has both, but a sweep
  that silently counted the county you were parked in would be wrong.

```
guard let act = rule.activatedCountyMultiplier,
      log.myLocation.isInState,
      wantedClasses.contains(.county),
      act.categories.contains(log.station.categoryStation)

group the valid (non-dupe, in-scope, allowed-mode) rows by myLoc
for each group whose county is one of the party's:
    count = act.countUnit == .qsos ? rows.count
                                   : Set(rows.map(\.call.uppercased())).count
    skip unless count >= act.minCount
    skip if act.notOtherwiseWorked and a worked .county key for it exists
    for each distinct scopeComponent(act.countScope, row:) among that
        county's own rows:
        insert MultKey(.county, county, scope, activated: true)
```

Deriving the scope components from *that county's own rows* is what makes
`perBandMode` mean the right thing: SCQP grants the activated county once for
each band/mode the operator actually used from it, and `once` collapses the same
loop to a single key.

The threshold is counted over **all** the county's valid rows, not per scope —
every sponsor's sentence reads that way ("50 or more valid contacts from a
county", "10 or more different stations while operating from a county").

County lines: `CountyLineExpander` already writes one row per county with that
county in `myLoc`, so a station on a line accrues toward each county
independently, which is what MOQP's "from a county **or county lines** … the
multiplier for that county **or counties**" asks for.

### `wouldAddMultiplier` — the NEW MULT badge

Today the badge fires when the prospective key is absent from the current set.
With a forfeiting activation that over-promises: a TnQP mobile who has
self-activated DAVI sees **NEW MULT** on the first DAVI station they work, but
that contact forfeits the activation multiplier and the count does not move.

Where the entrant's rule has an `activatedCountyMultiplier`, the county class is
judged on **net gain** instead:

```
before = |worked keys for (county, X)| + |activated keys for (county, X)|
after  = |worked ∪ {new scope}| + (notOtherwiseWorked && worked∪{new} nonempty
                                   ? 0 : |activated keys|)
badge iff after > before
```

Every other class, and every party without an activation rule, keeps the
existing `!current.contains(key)` path untouched. This is the same failure the
`maxScoredMultipliers` guard immediately above it exists to prevent: the badge
must never send an operator chasing a multiplier that pays nothing.

## 4. Per-party values

| | `minCount` | `countUnit` | `countScope` | `categories` | `notOtherwiseWorked` |
| --- | --- | --- | --- | --- | --- |
| **scqp** | 1 | `qsos` | `perBandMode` | MOBILE, PORTABLE, EXPEDITION | **false** |
| **ncqp** | 1 | `qsos` | `once` | all six | true |
| **vaqp** | 10 | **`stations`** | `once` | MOBILE, ROVER, EXPEDITION | true |
| **moqp** | 50 | `qsos` | `once` | MOBILE, PORTABLE, EXPEDITION | true |
| **tnqp** | 10 | `qsos` | `once` | MOBILE, ROVER | true |

Notes on the two readings that are not verbatim:

- **SCQP `PORTABLE`** is the sponsor's, not an inference: 6.2.1 defines Mobile
  Single as "A single mobile **or portable** station that operates from at least
  two (2) different South Carolina counties". `ROVER` is excluded because SCQP
  has no such category.
- **MOQP `EXPEDITION`** is a decision, not the sponsor's word. Rule 3 names
  "mobile or portable category entry", and MOQP defines Expedition separately —
  but Expedition is the category MOQP permits on a county intersection, and rule
  3 pays "from a county **or county lines**". Ships covering Expedition, with a
  `ruleInference` caveat recording that the rule names only two of the three.
- **NCQP all six** encodes "**NC stations** may include the county from which
  operation takes place", which is every entrant and not only the roving ones.
  `minCount: 1` rather than 0 because the discriminating sentence is the
  sponsor's own "each county activated where at least one QSO was completed";
  the two are indistinguishable here in any case, since a county the operator
  logged nothing from leaves no trace in the log to count.

## 5. Commits — Article 9, contest-date order

1. **Engine, party-free.** `ActivatedCountyMultiplier`, `MultKey.activated`,
   `ScoreBreakdown.selfActivatedCounties`, the engine block, the
   `wouldAddMultiplier` net-gain check.
   `Tests/Core/ActivatedCountyMultiplierTests.swift` pins all five axes against
   one another on a synthetic party, in the manner of `BonusScopeTests`, plus
   the Article 4 proof that no bundled party carries the field yet. README.
2. **scqp** — and drops `"scqp"` from `CaveatRosterTests.badges`: the activation
   gap is its only `scoreAffecting` caveat, so closing it de-badges the party.
   A departure from that roster means a real gap was closed, which this is.
3. **ncqp** · 4. **vaqp** · 5. **moqp** · 6. **tnqp**

Each party commit: edit `docs/research/gen_<id>.py` (the new object plus the
`notes` prose, since the KNOWN LIMITATION it carried is no longer true) →
regenerate the JSON → re-run `gen_caveats.py` with that party's `KINDS` indices
adjusted → the per-party test file (Article 18) → README bundled-party entry,
provenance and test count (Article 6) → `WORKLIST-2026.md`.

Verification for every commit, per Article 8:

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS'
```

## 6. Out of scope

- **No UI change.** The counties reach `multiplierCount` and the per-class
  chips through the existing paths. `selfActivatedCounties` is exposed for a
  future sidebar line, and nothing reads it yet but the tests.
- **`BonusRule.activatedCountyCount` is untouched.** TnQP's 500-point and
  VAQP's 100-point activation *bonuses* are separate rules from the same
  sponsors and keep their own thresholds; TnQP's happen to agree at 10, VAQP's
  do not (1 QSO for the bonus, 10 stations for the multiplier).
- **The other caveats on these five parties stay.** NCQP's "Rarest of NC" 10×
  points, MOQP's 40/80 m daytime bonus, VAQP's 3-point mobile QSOs and unnamed
  bonus stations are all untouched by this change.

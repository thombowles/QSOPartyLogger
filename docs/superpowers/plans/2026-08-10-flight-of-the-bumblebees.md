# ARS Flight of the Bumblebees Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bundle the ARS Flight of the Bumblebees (`fobb`) — a twice-a-year QRP CW sprint scoring `contacts × Bumblebees × 3` — with exact scoring, Bumblebee-number prefill from the sponsor's own roster page, and every existing party byte-identical.

**Architecture:** Two additive engine shapes carry the new scoring geometry: a `MultClass.member` case (the worked station's received member number is the multiplier, keyed by callsign, per band) and a `MultRule.multiplierFloor` (the sponsor's printed "(Defaults to … = 1)"). The ×3 folds into per-QSO points, so `total = qsoPoints × multiplierCount` is the sponsor's formula with zero new arithmetic. The Skeeter Hunt's `memberExchange` machinery (entry field, gating, prefill, `{MEMBER}` macro, exports) is reused unchanged. A third small piece is a `CallHistorySource.Kind.arsFobbRoster` that fetches the sponsor's stable roster URL and converts its HTML table to the N1MM call-history shape.

**Tech Stack:** Swift 6 / SwiftUI / XCTest, XcodeGen, Python 3 (generator). Design: `docs/superpowers/specs/2026-08-10-flight-of-the-bumblebees-design.md`. Rules research + banked sources: `docs/research/fobb_rules.md` (read it before Task 6 — the notes and assertions below quote it).

**Repo execution notes (standing project practice):**
- Work in an **isolated worktree** (superpowers:using-git-worktrees), set up before the first edit, then `xcodegen generate` inside it. Master moves under long sessions here.
- Build/test always with `set -o pipefail` in front of piped `xcodebuild` (a `| tee | grep` once masked a failed build as exit 0). Keep the full log for any failure; never judge from a `tail`.
- `project.yml` globs `Sources/`, `Tests/`, and `Resources/`, but the tracked `.xcodeproj` is generated — any task that **adds a file** must run `xcodegen generate` and stage the regenerated `project.pbxproj` in that task's commit. That is Tasks 1, 2, 4, 5, 6, and 7.
- Run the narrow `-only-testing` suite while iterating a task; the **full suite** runs in Task 9 (and any earlier time you suspect fallout).
- Tests never touch the network (constitution Article 5): the roster client is tested over its scripted mock fetcher, the parser over banked fixtures.
- Generator pipeline order after any party generator, or blocks silently drop: `gen_fobb.py` → `gen_hub_map.py` → `gen_callhistory.py` → `gen_caveats.py`.
- One party per commit (Article 9): every commit below touches FOBB alone; Tasks 1–5 are party-free and must leave all 49 existing parties scoring identically (their tests are the proof).

**Sanity data used throughout (verified 2026-08-10, provenance in `fobb_rules.md`):**
- Windows: 2026-07-26 and 2026-09-20, both 17:00–21:00Z. Epoch of 2026-09-20T17:00:00Z = `1_789_923_600`.
- Formula: all 90 rows of the banked 3830 table satisfy `score = QSOs × Bumblebees × 3` exactly; sections are `Bumblebee LP`, `Bumblebee QRP`, `Home LP`, `Home QRP`; the one zero row (K4UPG, 0/0) scored 0.
- Roster: 234 rows, numbers 1–234 unique; K2SQS #1 NJ, W4KAC #7 NC, K4KBL #234 GA; NN5DE holds #65 and #122 (both TX).

---

### Task 1: Engine — `MultClass.member` and its contribution

**Files:**
- Modify: `Sources/Core/Parties/MultClass.swift` (the enum, ~line 4)
- Modify: `Sources/Core/Engine/ScoreEngine.swift` (`multContributions`, `score`, `wouldAddMultiplier`)
- Create: `Tests/Core/MemberMultiplierTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/Core/MemberMultiplierTests.swift`. The party is decoded from a minimal JSON literal (the `MemberExchangeTests` pattern — `PartyDefinition` has no memberwise init):

```swift
import XCTest
@testable import QSOPartyLogger

/// The `member` multiplier class: the worked station's received member
/// number is itself the multiplier, keyed by the raw logged callsign —
/// FOBB's "Working the same Bumblebee on a different band counts as an
/// additional Contact and as an additional Bumblebee Worked."
/// Rules research: docs/research/fobb_rules.md §6.
final class MemberMultiplierTests: XCTestCase {

    /// A minimal member-mult party, decoded rather than constructed.
    func party() throws -> PartyDefinition {
        let json = """
        {
          "schemaVersion": 1, "id": "membertest", "name": "Member Test",
          "cabrilloContest": "TEST", "homeState": "NA", "countyAbbrLength": 2,
          "validBands": ["40m", "20m"],
          "points": {"phone": 3, "cw": 3, "digital": 3},
          "dupeScope": "bandMode",
          "multipliers": {
            "inState":  {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"},
            "outState": {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"}
          },
          "bonuses": [], "counties": [], "hasHomeRegion": false,
          "allowedModes": ["cw"],
          "memberExchange": {
            "term": "Bumblebee number", "shortTerm": "BB #",
            "memberPlural": "Bumblebees",
            "memberPoints": 3, "qrpPoints": 3, "otherPoints": 3,
            "qrpMaxWatts": {"phone": 5, "cw": 5, "digital": 5}
          }
        }
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    var seq: TimeInterval = 0
    func qso(_ call: String, band: Band = .m20, member: String?) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_923_600 + seq),
            call: call, band: band, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599",
            memberSent: "5W", memberRcvd: member,
            myLoc: "TX", theirLoc: "NC"
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "membertest",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "5W"
        )
    }

    /// A received number contributes one member key per band; a power or a
    /// blank element contributes nothing.
    func testOnlyAParsedNumberContributes() throws {
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", member: "7"),      // bee
            qso("K1ABC", member: "5W"),        // power: no key
            qso("AC7A", member: nil),          // blank: no key
        ]), party: try party())
        XCTAssertEqual(score.multiplierKeys.count, 1)
        XCTAssertEqual(score.workedValues(.member), ["W4KAC/BB"])
        XCTAssertEqual(score.memberQSOs, 1)
    }

    /// Per-band scope: the same bee on a second band is a second key — the
    /// case that would fail under a `once` scope.
    func testSameBeeNewBandIsANewMultiplier() throws {
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", band: .m20, member: "7"),
            qso("W4KAC/BB", band: .m40, member: "7"),
        ]), party: try party())
        XCTAssertEqual(score.multiplierKeys.count, 2)
        XCTAssertEqual(score.workedValues(.member), ["W4KAC/BB"])
    }

    /// Same band twice is a dupe — no second key, no second point.
    func testSameBeeSameBandIsADupe() throws {
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", member: "7"),
            qso("W4KAC/BB", member: "7"),
        ]), party: try party())
        XCTAssertEqual(score.dupeCount, 1)
        XCTAssertEqual(score.multiplierKeys.count, 1)
        XCTAssertEqual(score.qsoPoints, 3)
    }

    /// The raw call is the key: /BB and bare forms are distinct values, and
    /// the location contributes nothing when the party wants only members.
    func testRawCallIdentityAndNoLocationKeys() throws {
        let score = ScoreEngine.score(log: log([
            qso("K3JZD/BB", band: .m20, member: "12"),
            qso("K3JZD", band: .m40, member: "12"),
        ]), party: try party())
        XCTAssertEqual(score.workedValues(.member), ["K3JZD/BB", "K3JZD"])
        XCTAssertTrue(score.workedValues(.state).isEmpty,
                      "NC was received but state is not a wanted class")
    }

    /// A party that does not list the class gets no member keys however the
    /// element parses — the wantedClasses gate.
    func testPartiesWithoutTheClassAreUntouched() throws {
        let skeeter = try XCTUnwrap(PartyCatalog.party(id: "skeeter"))
        let contest = ContestLog(
            partyID: "skeeter",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: [qso("W2LJ", member: "13")],
            exchangeMember: "20"
        )
        let score = ScoreEngine.score(log: contest, party: skeeter)
        XCTAssertTrue(score.workedValues(.member).isEmpty)
    }

    /// The NEW MULT badge sees the live member text: a bee not yet worked
    /// on this band is a new multiplier; a bee already worked there, a
    /// power, or a blank is not.
    func testWouldAddMultiplierReadsTheMemberElement() throws {
        let p = try party()
        let contest = log([qso("W4KAC/BB", band: .m20, member: "7")])
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: p, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m20, modeClass: .cw,
            log: contest, party: p, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: p, call: "K1ABC", memberRcvd: "100W"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: p, call: "K1ABC", memberRcvd: nil))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodegen generate
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MemberMultiplierTests 2>&1 | tail -20
```

Expected: **compile failure** — `MultClass` has no `member` case and `wouldAddMultiplier` has no `call:`/`memberRcvd:` parameters. A compile failure is this step's red.

- [ ] **Step 3: Add the enum case**

In `Sources/Core/Parties/MultClass.swift`, extend the enum (keep the doc-comment style of the `section` case):

```swift
enum MultClass: String, Codable, CaseIterable, Sendable {
    case county
    case state
    case province
    case dx
    /// ARRL/RAC section, for the parties whose exchange carries one instead of a
    /// state or province. …(existing comment unchanged)…
    case section
    /// The worked station itself, in a member-exchange party whose received
    /// member number is the multiplier — FOBB counts each Bumblebee worked,
    /// again on each band. The key's value is the raw logged callsign; the
    /// class only ever fires where the party lists it, so every party
    /// without it is untouched.
    case member
```

- [ ] **Step 4: Route the member element through `multContributions`**

In `Sources/Core/Engine/ScoreEngine.swift`, rename the existing `multContributions` body to `locationContributions` (same signature it has today) and add a new `multContributions` in front of it that composes the member key. The member contribution must come **before** the location logic because that logic early-returns on a state/county match:

```swift
    /// Which multiplier(s) a row contributes under the rule: the member key
    /// where the party counts worked members and the received element is a
    /// number, plus whatever the received location contributes.
    private static func multContributions(
        theirLoc: String,
        call: String,
        memberRcvd: String?,
        countyAbbrs: Set<String>,
        party: PartyDefinition,
        rule: PartyDefinition.MultRule
    ) -> [Contribution] {
        var out: [Contribution] = []
        // FOBB: "Working the same Bumblebee on a different band counts …
        // as an additional Bumblebee Worked." Keyed by the raw logged
        // callsign; a power or blank element is not a member. The empty-call
        // guard keeps a locations-only caller (the band map) from minting a
        // valueless key.
        if !call.isEmpty, let raw = memberRcvd,
           case .member = MemberExchange.parse(raw) {
            out.append(Contribution(multClass: .member, value: call.uppercased()))
        }
        out.append(contentsOf: locationContributions(
            theirLoc: theirLoc, call: call, countyAbbrs: countyAbbrs,
            party: party, rule: rule
        ))
        return out
    }

    /// Which multiplier(s) a received location contributes under the rule.
    /// …(the old multContributions doc comment and body, byte-identical,
    /// under the new name)…
    private static func locationContributions(
```

In `score(log:party:)`, pass the row's element at the existing call site:

```swift
            for contribution in multContributions(
                theirLoc: row.theirLoc.uppercased(),
                call: row.call,
                memberRcvd: row.memberRcvd,
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) {
```

- [ ] **Step 5: Give the badge the same inputs**

Still in `ScoreEngine.swift`, widen `wouldAddMultiplier` with defaulted parameters (existing callers compile unchanged) and pass them through:

```swift
    static func wouldAddMultiplier(
        theirLocs: [String],
        band: Band,
        modeClass: ModeClass,
        log: ContestLog,
        party: PartyDefinition,
        call: String = "",
        memberRcvd: String? = nil
    ) -> Bool {
```

and inside its loop, replace the `multContributions(theirLoc: loc.uppercased(), call: "", …)` call with:

```swift
            for c in multContributions(
                theirLoc: loc.uppercased(),
                call: call,
                memberRcvd: memberRcvd,
                countyAbbrs: countyAbbrs,
                party: party,
                rule: rule
            ) where wantedClasses.contains(c.multClass)
```

Note `wouldAddMultiplier` iterates `for loc in theirLocs` — with the member contribution now inside `multContributions`, a multi-county line would test the member key once per location. Harmless (same key each time), but keep the loop as is; do not "optimize" by hoisting.

- [ ] **Step 6: Sweep for exhaustiveness fallout**

```bash
grep -rn "MultClass.allCases\|MultClass\.allCases" Sources Tests
set -o pipefail; xcodebuild build -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger 2>&1 | tail -5
```

The build surfaces every exhaustive `switch` over `MultClass` (known: `ScoreSidebar.label(for:party:)` — fixed properly in Task 3; if the compiler stops here first, add the Task 3 case now and say so in that task). Inspect any `allCases` hit: none may change behavior for a party that does not list `.member` (`classCounts`/roster machinery key off *worked* keys and rule classes, so absent-class parties see nothing).

- [ ] **Step 7: Run the new tests and the guard suites**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MemberMultiplierTests -only-testing:QSOPartyLoggerTests/SkeeterHuntTests -only-testing:QSOPartyLoggerTests/MemberExchangeTests -only-testing:QSOPartyLoggerTests/MultiplierRosterTests 2>&1 | tail -10
```

Expected: PASS (all).

- [ ] **Step 8: Commit**

```bash
git add Sources/Core/Parties/MultClass.swift Sources/Core/Engine/ScoreEngine.swift Tests/Core/MemberMultiplierTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "engine: MultClass.member — worked members as a multiplier class"
```

---

### Task 2: Engine — `MultRule.multiplierFloor`

**Files:**
- Modify: `Sources/Core/Parties/PartyDefinition.swift` (`MultRule`, ~lines 387–472)
- Modify: `Sources/Core/Engine/ScoreEngine.swift` (`ScoreBreakdown`, `score`)
- Create: `Tests/Core/MultiplierFloorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// `MultRule.multiplierFloor` — FOBB's printed "(Defaults to [Total
/// Contacts] = 1 and [Number of Bumblebees] = 1)": the multiplier count
/// that reaches the score never drops below the floor. Default 0 leaves
/// every existing party exactly as it was (max(n, 0) == n).
/// Research: docs/research/fobb_rules.md §8 and OPEN QUESTION 1.
final class MultiplierFloorTests: XCTestCase {

    func party(floor: String) throws -> PartyDefinition {
        let json = """
        {
          "schemaVersion": 1, "id": "floortest", "name": "Floor Test",
          "cabrilloContest": "TEST", "homeState": "NA", "countyAbbrLength": 2,
          "validBands": ["40m", "20m"],
          "points": {"phone": 3, "cw": 3, "digital": 3},
          "dupeScope": "bandMode",
          "multipliers": {
            "inState":  {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"\(floor)},
            "outState": {"classes": ["member"], "homeStateCountsViaCounty": false, "countScope": "perBand"\(floor)}
          },
          "bonuses": [], "counties": [], "hasHomeRegion": false,
          "allowedModes": ["cw"],
          "memberExchange": {
            "term": "Bumblebee number", "shortTerm": "BB #",
            "memberPlural": "Bumblebees",
            "memberPoints": 3, "qrpPoints": 3, "otherPoints": 3,
            "qrpMaxWatts": {"phone": 5, "cw": 5, "digital": 5}
          }
        }
        """
        return try PartyCatalog.decode(Data(json.utf8))
    }

    var seq: TimeInterval = 0
    func qso(_ call: String, member: String?) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_923_600 + seq),
            call: call, band: .m20, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599",
            memberSent: "5W", memberRcvd: member,
            myLoc: "TX", theirLoc: "NC"
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "floortest",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "5W"
        )
    }

    /// Absent from the JSON, the floor is 0 and nothing anywhere moves.
    func testDefaultFloorIsZero() throws {
        let p = try party(floor: "")
        XCTAssertEqual(p.multipliers.inState.multiplierFloor, 0)
    }

    /// Contacts but no member worked: the floor holds the multiplier at 1,
    /// so three contacts score 3 × 3 × 1 = 9 — FOBB's contacts × 1 × 3.
    func testFloorHoldsTheProductUpWithZeroKeys() throws {
        let p = try party(floor: ", \"multiplierFloor\": 1")
        let score = ScoreEngine.score(log: log([
            qso("K1ABC", member: "100W"),
            qso("K2DEF", member: nil),
            qso("K3GHI", member: "5W"),
        ]), party: p)
        XCTAssertTrue(score.multiplierKeys.isEmpty)
        XCTAssertEqual(score.multiplierCount, 1)
        XCTAssertEqual(score.total, 9)
    }

    /// An empty log still totals 0 — qsoPoints is 0 whatever the floor
    /// says (the K4UPG row on the sponsor's calculator).
    func testAnEmptyLogIsStillZero() throws {
        let p = try party(floor: ", \"multiplierFloor\": 1")
        let score = ScoreEngine.score(log: log([]), party: p)
        XCTAssertEqual(score.multiplierCount, 1)
        XCTAssertEqual(score.total, 0)
    }

    /// Once real keys exist the floor is inert.
    func testFloorIsInertOnceKeysExist() throws {
        let p = try party(floor: ", \"multiplierFloor\": 1")
        let score = ScoreEngine.score(log: log([
            qso("W4KAC/BB", member: "7"),
            qso("N7CQR/BB", member: "23"),
        ]), party: p)
        XCTAssertEqual(score.multiplierCount, 2)
        XCTAssertEqual(score.total, 6 * 2)
    }
}
```

- [ ] **Step 2: Run to verify failure**

```bash
xcodegen generate
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MultiplierFloorTests 2>&1 | tail -10
```

Expected: compile failure — `multiplierFloor` does not exist.

- [ ] **Step 3: Add the field to `MultRule`**

In `PartyDefinition.MultRule` (beside its mirror `maxScoredMultipliers`):

```swift
        /// The floor under the multiplier count that reaches the **score**,
        /// where a sponsor's formula never lets the product zero out. FOBB
        /// prints it in the scoring block — "(Defaults to [Total Contacts]
        /// = 1 and [Number of Bumblebees] = 1)" — so a bee-less log with
        /// contacts scores contacts × 1 × 3. Zero (the default everywhere)
        /// is inert: max(n, 0) == n. An empty log still totals 0, because
        /// qsoPoints is 0 — the sponsor's own calculator scored a 0-QSO
        /// entry 0, not 3.
        var multiplierFloor: Int { multiplierFloorRaw ?? 0 }
        private let multiplierFloorRaw: Int?
```

Extend the memberwise `init` with `multiplierFloor: Int? = nil` storing `multiplierFloorRaw = multiplierFloor`, and add to `CodingKeys`:

```swift
            case multiplierFloorRaw = "multiplierFloor"
```

- [ ] **Step 4: Apply it in `ScoreBreakdown`**

In `ScoreEngine.ScoreBreakdown`, beside `multiplierCap`:

```swift
        /// Set from the entrant's `MultRule.multiplierFloor` — the count
        /// that reaches the score never drops below it (FOBB's printed
        /// "Defaults to … = 1"). 0 everywhere else.
        var multiplierFloor = 0

        /// Multipliers that reach the score. Every key is still tallied in
        /// `multiplierKeys` — the cap limits what is paid for, the floor
        /// holds the product up, and neither changes what counts as worked.
        var multiplierCount: Int {
            max(min(multiplierKeys.count, multiplierCap ?? .max), multiplierFloor)
        }
```

and in `score(log:party:)`, next to the existing `result.multiplierCap = rule.maxScoredMultipliers`:

```swift
        result.multiplierFloor = rule.multiplierFloor
```

- [ ] **Step 5: Run the new tests plus a broad guard**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/MultiplierFloorTests -only-testing:QSOPartyLoggerTests/CaliforniaQSOPartyTests -only-testing:QSOPartyLoggerTests/SkeeterHuntTests 2>&1 | tail -6
```

Expected: PASS (CQP exercises the cap the floor now composes with).

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Parties/PartyDefinition.swift Sources/Core/Engine/ScoreEngine.swift Tests/Core/MultiplierFloorTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "engine: MultRule.multiplierFloor — a sponsor formula that never zeroes"
```

---

### Task 3: UI seams — sidebar label and the live badge inputs

**Files:**
- Modify: `Sources/UI/ScoreSidebar.swift` (`label(for:party:)`, ~line 502)
- Modify: `Sources/App/EntryState.swift` (the `wouldAddMultiplier` call, ~line 274)

- [ ] **Step 1: Label the class from party data**

In `ScoreSidebar.label(for:party:)` add the case (the switch is exhaustive — Task 1's build already pointed here):

```swift
        case .member: party.memberExchange?.memberPlural ?? "Members"
```

No other sidebar work: the Bumblebee/QRP/QRO *figures* already render from `score.memberQSOs` (ScoreSidebar ~line 127), and `MultiplierRoster` builds sections from enumerable token sets, which the member class deliberately has none of — worked bees surface as the multiplier count, not a roster grid. `NeededMult` already guards on `rule.classes.contains(.county)` (NeededMult.swift:52) and needs nothing.

- [ ] **Step 2: Wire the live call and member text into the badge**

In `Sources/App/EntryState.swift` (~line 274) the badge currently reads:

```swift
            isNewMult = ScoreEngine.wouldAddMultiplier(
                theirLocs: parsed.locations, band: band, modeClass: modeClass,
                log: log, party: party
            )
```

Change it to pass the entry row's live call and member fields — read the surrounding type for the exact property names (the same state the Skeeter entry field writes; expect them to look like `call` and `memberRcvd` on this state object or its entry struct):

```swift
            isNewMult = ScoreEngine.wouldAddMultiplier(
                theirLocs: parsed.locations, band: band, modeClass: modeClass,
                log: log, party: party,
                call: <live call text>, memberRcvd: <live member text, nil when empty>
            )
```

Then check what re-triggers this computation: if editing the **member field** does not already re-run the exchange-status update that sets `isNewMult` (find the `didSet`/observer that calls it for the exchange and call fields), add the same trigger to the member field's setter — otherwise the badge for a member party only refreshes on exchange edits. `grep -n "isNewMult\|updateExchange" Sources/App/EntryState.swift` to map the triggers.

`Sources/UI/BandMap.swift:108` also calls `wouldAddMultiplier` — leave it untouched; spots carry no member data and the defaulted parameters preserve its behavior exactly.

- [ ] **Step 3: Build and run the entry/UI guard suites**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryCommandTests -only-testing:QSOPartyLoggerTests/SkeeterHuntTests -only-testing:QSOPartyLoggerTests/BandMapTests 2>&1 | tail -6
```

Expected: PASS. (The FOBB end-to-end badge test lands in Task 7 with the party.)

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/ScoreSidebar.swift Sources/App/EntryState.swift
git commit -m "engine: the member class labels from party data and reads the live entry"
```

---

### Task 4: `FOBBRosterParser` — the sponsor's table to call-history text

**Files:**
- Create: `Sources/Core/CallHistory/FOBBRosterParser.swift`
- Create: `Tests/Fixtures/CallHistory/fobb-roster-page-2026-07.html` (copy of `docs/research/fobb_roster_page_2026-07.html`)
- Create: `Tests/Core/FOBBRosterParserTests.swift`

- [ ] **Step 1: Copy the banked fixture**

```bash
cp docs/research/fobb_roster_page_2026-07.html Tests/Fixtures/CallHistory/fobb-roster-page-2026-07.html
xcodegen generate
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

/// The ARS Bumblebee roster pipeline, over the real report page captured
/// 2026-08-10 (234 numbers — the July 2026 event's roster). Provenance:
/// docs/research/fobb_rules.md §13.
final class FOBBRosterParserTests: XCTestCase {

    private func fixture(_ name: String, _ ext: String) throws -> String {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(
            bundle.url(forResource: name, withExtension: ext),
            "\(name).\(ext) missing from Tests/Fixtures/CallHistory")
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testConvertsTheBankedPage() throws {
        let html = try fixture("fobb-roster-page-2026-07", "html")
        let text = try XCTUnwrap(
            FOBBRosterParser.n1mmText(fromHTML: html, token: "FOBB ROSTER"))
        let lines = text.split(separator: "\n").map(String.init)

        XCTAssertEqual(lines[0], "# FOBB ROSTER")
        XCTAssertTrue(lines.contains("!!Order!!,Call,Name,State,Exch1"))
        // Every bee twice: the bare call and the /BB form they sign with.
        XCTAssertTrue(lines.contains("K2SQS,FRANK,NJ,1"), "\(lines.prefix(8))")
        XCTAssertTrue(lines.contains("K2SQS/BB,FRANK,NJ,1"))
        XCTAssertTrue(lines.contains("W4KAC,KEN,NC,7"))
        XCTAssertTrue(lines.contains("K4KBL,JERRY,GA,234"))
        // One call under two numbers survives as two rows each way.
        XCTAssertEqual(lines.filter { $0.hasPrefix("NN5DE,") }.count, 2)
        // 234 bees × 2 forms.
        let records = lines.filter { !$0.hasPrefix("#") && !$0.hasPrefix("!!") }
        XCTAssertEqual(records.count, 468)
    }

    /// The store's declaration gate must accept the converted text.
    func testConvertedTextPassesTheTokenGate() throws {
        let html = try fixture("fobb-roster-page-2026-07", "html")
        let text = try XCTUnwrap(
            FOBBRosterParser.n1mmText(fromHTML: html, token: "FOBB ROSTER"))
        let parsed = try XCTUnwrap(CallHistoryFile.parse(data: Data(text.utf8)))
        XCTAssertGreaterThan(parsed.recordCount, 0)
        let source = CallHistorySource(
            filePrefix: "FOBB", token: "FOBB ROSTER",
            kind: .arsFobbRoster,
            pageURL: "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php")
        XCTAssertTrue(source.isDeclared(inCommentTokens: parsed.tokens))
    }

    /// Drift fails loudly: a page without the observed header is nil, an
    /// empty table is nil.
    func testUnrecognizedMarkupIsNil() {
        XCTAssertNil(FOBBRosterParser.n1mmText(
            fromHTML: "<html><body><p>maintenance</p></body></html>",
            token: "FOBB ROSTER"))
        let renamed = """
        <table><tr><th>Number</th><th>Call</th><th>Name</th><th>SPC</th>\
        <th>Where</th></tr><tr><td>1</td><td>K2SQS</td><td>Frank</td>\
        <td>NJ</td><td>park</td></tr></table>
        """
        XCTAssertNil(FOBBRosterParser.n1mmText(fromHTML: renamed, token: "T"))
        let headerOnly = """
        <table><tr><th>BB</th><th>Callsign</th><th>Name</th><th>SPC</th>\
        <th>Expected Location</th></tr></table>
        """
        XCTAssertNil(FOBBRosterParser.n1mmText(fromHTML: headerOnly, token: "T"))
    }
}
```

Note: Task 5 adds `.arsFobbRoster`; until then `testConvertedTextPassesTheTokenGate` will not compile — write all three tests now, expect the compile failure as this step's red, and bring the suite green over Steps 3–4 and Task 5 Step 2 together if you prefer strict compile-first ordering. Simpler: add the enum case in Task 5 first is NOT allowed (kind belongs with the client change), so instead build this task with the test's `kind:` argument commented and a `// Task 5 uncomments` marker, then uncomment in Task 5. Choose one and say which in the commit body.

- [ ] **Step 3: Write the parser**

Create `Sources/Core/CallHistory/FOBBRosterParser.swift`:

```swift
import Foundation

/// Reads the ARS self-serve Bumblebee roster — the sponsor's own report
/// page at a stable URL (`Process_Get_All_By_Number.php`), one plain HTML
/// table `BB | Callsign | Name | SPC | Expected Location` — and converts
/// it to the N1MM call-history text shape so the store, token gate, parser
/// and prefill pipeline downstream run untouched.
///
/// Pure and offline, like `SkeeterRosterParser`, with the same drift
/// stance: positional reads of somebody else's markup, so an unrecognized
/// page is an explicit `nil` — never a silent empty that reads as "no
/// roster this event". Page shape observed 2026-08-10; captured fixture in
/// `Tests/Fixtures/CallHistory`, provenance in
/// `docs/research/fobb_rules.md` §13.
///
/// Each Bumblebee is emitted under both `CALL` and `CALL/BB`: bees sign
/// /BB on the air and `CallHistoryFile.entry(for:)` matches the typed call
/// exactly, so the double row is what makes prefill fire either way.
///
/// Roster data is a **hint, never a rule** (constitution Article 1): every
/// value is re-validated by the party's own parsers before being offered,
/// and nothing from it reaches `ScoreEngine` — Bumblebee credit comes from
/// the received exchange, not roster membership.
enum FOBBRosterParser {

    /// The roster table converted to N1MM call-history text: the S/P/C
    /// rides the State column and the BB number rides Exch1 (the Skeeter
    /// converter's arrangement), so `Entry.locations` carries both and the
    /// two prefill channels split them. `nil` when the page's first table
    /// row is not the header observed 2026-08-10, or no numbered row
    /// survives.
    static func n1mmText(fromHTML html: String, token: String) -> String? {
        let rows = tableRows(html)
        guard let header = rows.first, header.count >= 4,
              header[0].uppercased() == "BB",
              header[1].uppercased() == "CALLSIGN",
              header[2].uppercased() == "NAME",
              header[3].uppercased() == "SPC"
        else { return nil }

        var lines = [
            "# \(token)",
            "# Converted from the ARS self-serve Bumblebee roster by QSOPartyLogger.",
            "# This is helping file, LOG what you copy.",
            "!!Order!!,Call,Name,State,Exch1",
        ]
        var records = 0
        for row in rows.dropFirst() where row.count >= 4 {
            let number = row[0].trimmingCharacters(in: .whitespaces)
            let call = clean(row[1])
            guard !number.isEmpty, number.allSatisfy(\.isWholeNumber),
                  !call.isEmpty else { continue }
            let name = clean(row[2])
            let spc = clean(row[3])
            lines.append("\(call),\(name),\(spc),\(number)")
            lines.append("\(call)/BB,\(name),\(spc),\(number)")
            records += 1
        }
        guard records > 0 else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    /// `<tr>` rows as arrays of tag-stripped, entity-unescaped cell texts.
    /// Regex-free scanning in the `SkeeterRosterParser` idiom.
    private static func tableRows(_ html: String) -> [[String]] {
        var rows: [[String]] = []
        for rowChunk in html.components(separatedBy: "<tr").dropFirst() {
            let row = rowChunk.components(separatedBy: "</tr>").first ?? rowChunk
            var cells: [String] = []
            for tag in ["<td", "<th"] {
                for cellChunk in row.components(separatedBy: tag).dropFirst() {
                    guard let tagEnd = cellChunk.firstIndex(of: ">") else { continue }
                    let body = cellChunk[cellChunk.index(after: tagEnd)...]
                        .components(separatedBy: "</")
                        .first ?? ""
                    cells.append(unescaped(stripTags(String(body))))
                }
            }
            if !cells.isEmpty { rows.append(cells) }
        }
        return rows
    }

    private static func stripTags(_ text: String) -> String {
        var out = ""
        var inTag = false
        for c in text {
            if c == "<" { inTag = true } else if c == ">" { inTag = false }
            else if !inTag { out.append(c) }
        }
        return out
    }

    /// The handful of entities a hand-maintained roster actually produces.
    private static func unescaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Trimmed, uppercased, and stripped of the emitted format's own
    /// delimiters — the table is hand-maintained (the Skeeter lesson: a
    /// stray "," in a cell shifts every column after it).
    private static func clean(_ field: String) -> String {
        field.trimmingCharacters(in: .whitespaces)
            .uppercased()
            .filter { $0 != "," && $0 != ";" }
    }
}
```

Two data notes for whoever adjusts this against the fixture: the header row may use `<th>` or `<td>` (both are read), and multi-word names ("Ryan Dorkoski") keep their internal spaces — only commas/semicolons are stripped. The banked fixture and its tests are the arbiter of any drift from this sketch.

- [ ] **Step 4: Run the parser tests**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/FOBBRosterParserTests 2>&1 | tail -8
```

Expected: PASS (except the token-gate test if you deferred its `kind:` to Task 5 — state which).

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/CallHistory/FOBBRosterParser.swift Tests/Core/FOBBRosterParserTests.swift Tests/Fixtures/CallHistory/fobb-roster-page-2026-07.html QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "call history: parse the ARS Bumblebee roster page"
```

---

### Task 5: `CallHistorySource.Kind.arsFobbRoster` and the client path

**Files:**
- Modify: `Sources/Core/Parties/CallHistorySource.swift` (the `Kind` enum, ~line 29)
- Modify: `Sources/App/CallHistoryClient.swift` (`refreshIfStale` switch ~line 103; new method beside `refreshFromRosterPage`)
- Modify: `Tests/Core/CallHistoryClientTests.swift` — if that file does not exist, find the client tests with `grep -rln "refreshIfStale" Tests/` and extend the file that has the scripted `CallHistoryFetching` mock.

- [ ] **Step 1: Add the kind**

In `CallHistorySource.Kind`:

```swift
    enum Kind: String, Codable, Sendable {
        case n1mm
        case w2ljRosterPage
        /// The ARS Flight of the Bumblebees arrangement: the sponsor's
        /// self-serve number report is one HTML table at a stable URL
        /// (`pageURL`), so there is no discovery hop at all — fetch, parse,
        /// convert. Live data: numbers issue until the event and the table
        /// resets each event, so the daily clock re-downloads with no
        /// unchanged-revision short circuit.
        case arsFobbRoster
    }
```

(If Task 4 deferred the `kind:` argument in its token-gate test, uncomment it now.)

- [ ] **Step 2: Write the failing client test**

In the client test file located above, alongside the existing w2lj tests (reuse its scripted fetcher and store scaffolding — read two of its tests first and follow their arrangement exactly). The party stub can be built by decoding minimal JSON as in `MemberMultiplierTests`, with:

```swift
          "callHistory": {
            "kind": "arsFobbRoster",
            "pageURL": "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php",
            "filePrefix": "FOBB", "token": "FOBB ROSTER"
          }
```

Cases to cover (mirror the w2lj set):

```swift
    /// One GET, straight to the report page: the converted roster installs
    /// and publishes.
    func testFOBBRosterInstallsFromTheReportPage() async throws { /* scripted
        fetcher returns (fixture HTML, 200) for the pageURL; assert
        status == .ready with records == 468, store has the file, onIndex
        fired with recordCount 468 */ }

    /// A non-200 answer keeps the cached roster and says so.
    func testFOBBRosterKeepsCacheOnHTTPFailure() async throws { /* 503 →
        fail message contains "answered 503"; cached data untouched */ }

    /// A drifted page is an explicit refusal, not an empty install.
    func testFOBBRosterRefusesDriftedMarkup() async throws { /* 200 with
        "<html><p>maintenance</p></html>" → fail message contains
        "changed shape"; nothing installed */ }

    /// The daily clock paces it; there is no revision short-circuit.
    func testFOBBRosterHonorsTheDailyThrottle() async throws { /* second
        refreshIfStale within 24 h performs no fetch; force: true does */ }
```

Write them fully against the real scaffolding in that file — the shapes above name the assertions, the file's existing tests supply the idiom (scripted responses keyed by URL, temp-folder store). Run; expected: compile failure (`arsFobbRoster` unhandled) or red.

- [ ] **Step 3: Implement the client path**

In `CallHistoryClient.refreshIfStale`, extend the switch:

```swift
        switch source.kind {
        case .n1mm:
            await refreshFromListing(party: party, source: source, meta: meta, now: now)
        case .w2ljRosterPage:
            await refreshFromRosterPage(party: party, source: source, now: now)
        case .arsFobbRoster:
            await refreshFromFOBBRoster(party: party, source: source, now: now)
        }
```

New method, beside `refreshFromRosterPage` (same error posture, same install tail — read that method top to bottom first; this one is the same minus the sheet-discovery hop):

```swift
    /// The FOBB arrangement: the sponsor's self-serve number report is one
    /// HTML table at a stable URL, so there is no discovery hop — fetch the
    /// report, convert, install. Live data (numbers issue until the event;
    /// the table resets each event), so no unchanged-revision short circuit;
    /// the once-a-day throttle alone paces the re-download.
    private func refreshFromFOBBRoster(
        party: PartyDefinition,
        source: CallHistorySource,
        now: Date
    ) async {
        guard let pageURLString = source.pageURL,
              let pageURL = URL(string: Self.secured(pageURLString)) else {
            fail("This party's roster source names no page URL — "
                 + "the definition is incomplete.")
            return
        }
        status = .checking
        lastError = nil
        log("*** checking the sponsor's Bumblebee roster")

        do {
            let (pageData, pageResponse) = try await fetcher.get(pageURL)
            guard pageResponse.statusCode == 200,
                  let pageHTML = String(data: pageData, encoding: .utf8) else {
                throw RefreshProblem(message:
                    "The roster page answered \(pageResponse.statusCode). "
                    + "The cached roster, if any, stays in use.")
            }
            guard let converted = FOBBRosterParser.n1mmText(
                fromHTML: pageHTML, token: source.token ?? source.filePrefix) else {
                throw RefreshProblem(message:
                    "The roster page has changed shape — not reading it "
                    + "until the app is updated. The cached roster, if any, "
                    + "stays in use.")
            }

            let data = Data(converted.utf8)
            guard let parsed = CallHistoryFile.parse(data: data),
                  parsed.recordCount > 0,
                  source.isDeclared(inCommentTokens: parsed.tokens) else {
                throw RefreshProblem(message:
                    "The converted roster came back empty — not installing it.")
            }

            let revision = "roster " + Self.dayStamp(now)
            try store.save(
                partyID: party.id,
                data: data,
                meta: CallHistoryStore.Meta(
                    sourceFileName: revision,
                    listedDate: Self.dayStamp(now),
                    fetchedAt: now,
                    lastCheckedAt: now
                )
            )
            status = .ready(
                partyID: party.id,
                revision: revision,
                records: parsed.recordCount
            )
            log("*** installed the roster — \(parsed.recordCount) stations")
            onIndex?(party.id, parsed)
        } catch let error as RefreshProblem {
            fail(error.message)
        } catch {
            fail("Couldn't reach the sponsor's roster: "
                 + "\(error.localizedDescription) The cached roster, if any, "
                 + "stays in use.")
        }
    }
```

- [ ] **Step 4: Run the client and source suites**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/FOBBRosterParserTests -only-testing:QSOPartyLoggerTests/CallHistorySourceTests -only-testing:QSOPartyLoggerTests/SkeeterRosterParserTests 2>&1 | tail -8
```

plus the client test file's own `-only-testing` target. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Parties/CallHistorySource.swift Sources/App/CallHistoryClient.swift Tests/ QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "call history: arsFobbRoster kind — stable-URL roster, daily clock"
```

---

### Task 6: `gen_fobb.py` → `fobb.json`, and the generator pipeline

**Files:**
- Create: `docs/research/gen_fobb.py`
- Create (generated): `Resources/Parties/fobb.json`
- Modify: `docs/research/gen_callhistory.py` (the special-source dict at ~line 71)
- Modify: `docs/research/gen_caveats.py` (the `KINDS` dict)

- [ ] **Step 1: Write the generator**

Create `docs/research/gen_fobb.py`. It mirrors `gen_skeeter.py` (read that file first — the structure below is its structure) and must contain, in order:

**(a) Header docstring** naming what is unusual (no counties; the member element decides Bumblebee-ness, never the rate; the multiplier is Bumblebees-per-band with a printed floor of 1; the formula is printed AND verified against 3830), the four banked sources with fetch dates, and the pipeline-order run instructions.

**(b) Quote assertions over both banked rules texts:**

```python
import csv
import json
import re
from pathlib import Path

HERE = Path(__file__).parent
OUT = HERE.parent.parent / "Resources" / "Parties" / "fobb.json"

FALL = (HERE / "fobb_rules_2026.txt").read_text()
JULY = (HERE / "fobb_rules_2026_july_wayback.txt").read_text()
FLAT_FALL = re.sub(r"\s+", " ", FALL)
FLAT_JULY = re.sub(r"\s+", " ", JULY)

# The rules, verbatim — a drifted page must fail here, not ship quietly.
REQUIRED_QUOTES = [
    "held twice each Year",
    "last Sunday of July",
    "3rd Sunday in September",
    "1700 to 2100 UTC",
    "Your BB Number",
    "Your Power Output",
    "once on each Band",
    "additional Bumblebee Worked",
    "[Total Contacts]",  # the formula's own bracket idiom
    "x  [Number of Bumblebees]",
    "Defaults to [Total Contacts] = 1",
    "Bumblebee Numbers are only valid for One FOBB Event",
    "5W QRP Maximum",
]
for quote in REQUIRED_QUOTES:
    flat_quote = re.sub(r"\s+", " ", quote)
    assert flat_quote in FLAT_FALL, f"fall rules text lost: {quote!r}"
assert "Sunday, September 20, 2026" in FLAT_FALL
assert "Sunday, July 26, 2026" in FLAT_JULY, "the Legacy date is the Wayback capture's"
# Five bands and no others: the Target Scents list.
for mhz in ["3.566", "7.036", "14.036", "21.036", "28.036"]:
    assert mhz in FLAT_FALL, f"watering hole missing: {mhz}"
assert "1.8" not in FLAT_FALL and "10.1" not in FLAT_FALL, "no 160m, no WARC"
```

(Adjust the two formula-fragment quotes to the banked file's actual whitespace — the extraction carries doubled spaces; the `re.sub` collapse above handles it, so write them collapsed: `"x [Number of Bumblebees]"`.)

**(c) Formula verification over the banked 3830 table — every row, exactly:**

```python
# The sponsor-designated calculator's own arithmetic. Analogue of the
# Article 2 county-count assertion for a party with no counties.
rows = list(csv.DictReader(open(HERE / "fobb_3830_claimed_2026-07.csv")))
assert len(rows) == 90, f"expected 90 claimed rows, got {len(rows)}"
sections = {r["section"] for r in rows}
assert sections == {"Bumblebee LP", "Bumblebee QRP", "Home LP", "Home QRP"}, sections
for r in rows:
    q, b, s = int(r["qsos"]), int(r["bumblebees"]), int(r["score"])
    assert s == q * b * 3, f"{r['call']}: {q}x{b}x3 != {s}"
zero = [r for r in rows if r["qsos"] == "0"]
assert [r["call"] for r in zero] == ["K4UPG"] and zero[0]["score"] == "0", \
    "the observed zero row scores 0, not 3 — OPEN QUESTION 1's anchor"
```

**(d) Roster assertions over the banked CSV:**

```python
roster = list(csv.DictReader(open(HERE / "fobb_roster_2026-07.csv")))
assert len(roster) == 234, f"expected 234 numbered rows, got {len(roster)}"
numbers = [int(r["BB"]) for r in roster]
assert sorted(numbers) == list(range(1, 235)), "numbers 1..234, no gap, no dupe"
by_call = {}
for r in roster:
    by_call.setdefault(r["Callsign"].strip().upper(), []).append(r["BB"])
assert by_call["K2SQS"] == ["1"] and roster[0]["SPC"] == "NJ"
assert by_call["W4KAC"] == ["7"]
assert by_call["K4KBL"] == ["234"]
assert by_call["NN5DE"] == ["65", "122"], "one call, two numbers — the parser's repeat case"
```

**(e) The NOTES string and the party dict, emitted like `gen_skeeter.py`** (`json.dump(party, f, indent=2, ensure_ascii=False)` + trailing newline). The full notes text — write it into the generator verbatim:

```python
NOTES = (
    "Rules from the sponsor's own page: ars-qrp.com/FOBB/FOBB.html, read live and "
    "fetched 2026-08-10 ('Last Updated : 27JUL26'), headed for the next running - "
    "'Fall Flight of the Bumblebees / Sunday, September 20, 2026 / 1700 to 2100 UTC'. "
    "The July (Legacy) edition of the same page, captured by the Internet Archive on "
    "2026-07-23 (snapshot 20260723202047), printed 'Legacy Flight of the Bumblebees / "
    "Sunday, July 26, 2026' with every rule identical. NOT A STATE QSO PARTY: a "
    "four-hour Adventure Radio Society QRP CW sprint held twice a year - 'held twice "
    "each Year - Annually on the last Sunday of July. - Annually on the 3rd Sunday in "
    "September' - the event the NJQRP Skeeter Hunt was modelled on. BOTH 2026 WINDOWS "
    "SHIP (Article 19, target year only - the NAQP precedent for a twice-a-year "
    "contest): 2026-07-26 and 2026-09-20, each 1700-2100Z, both sponsor-printed. "
    "EXCHANGE IS RST + S/P/C + BUMBLEBEE NUMBER OR POWER OUTPUT ('If you are a "
    "Bumblebee: RST / Your State, Province, or Country / Your BB Number. If you are a "
    "Home Station: RST / Your State, Province, or Country / Your Power Output'). THE "
    "NUMBER IS WHAT MAKES A BUMBLEBEE CONTACT, NOT THE /BB SUFFIX: 'Bumblebees will "
    "put a /BB after their Call, and/or will give you a BB Number', and the POTA/SOTA "
    "note settles it - 'As long as a Bumblebee Number is sent in the Outgoing "
    "Exchange, that will be a valid FOBB Bumblebee Contact.' Log the call as sent, "
    "/BB and all, and type the number you copy; a station that sends no number is a "
    "home station whatever its suffix. EVERY VALID CONTACT PAYS THE SAME - the "
    "printed formula is '[Total Score] = [Total Contacts] x [Number of Bumblebees] "
    "x 3', and '[Total Contacts] includes both Bumblebees and non-Bumblebees' - "
    "carried here as 3 points per contact times the Bumblebee multiplier. THE "
    "MULTIPLIER IS BUMBLEBEES WORKED, COUNTED AGAIN ON EACH BAND: 'Working the same "
    "Bumblebee on a different band counts as an additional Contact and as an "
    "additional Bumblebee Worked.' THE S/P/C IS NOT A MULTIPLIER - no counting "
    "phrase attaches to it anywhere in the rules; it is exchanged and validated "
    "(the standard state and province tables plus DXCC prefixes, the C in S/P/C) "
    "and worth nothing, WHICH IS WHY THIS PARTY ENUMERATES NO LIST OF ITS OWN. THE "
    "MULTIPLIER NEVER DROPS BELOW ONE: '(Defaults to [Total Contacts] = 1 and "
    "[Number of Bumblebees] = 1)' - a log with contacts and no Bumblebee scores "
    "contacts x 1 x 3. DUPES: 'You can work each Bumblebee or Home Station once on "
    "each Band' - and with one legal mode, the app's band-x-mode dupe scope IS that "
    "rule, so nothing here is inferred. MODE IS CW ONLY, QRP: 'Open to all QRP CW "
    "operators', 'You run QRP CW - You can work Non-QRP Stations'; the power limits "
    "('Participating FOBB Home Stations are expected to be running 5W QRP Maximum'; "
    "hunters over 5 W 'cannot Submit FOBB Results') are entry conditions, not "
    "categories, and never move a score here. BANDS 80/40/20/15/10, taken from the "
    "rules' TARGET SCENTS frequency list (3.566/7.036/14.036/21.036/28.036 '+/-'), "
    "the only bands the sponsor names. HOME vs BUMBLEBEE is a reporting split on "
    "3830scores.com ('Select 'Home' or 'Bumblebee' so that you end up in the proper "
    "Results List'), not a scoring class - same formula, separate lists. THE "
    "FORMULA WAS ALSO VERIFIED AGAINST THE SPONSOR-DESIGNATED CALCULATOR: all 90 "
    "rows of the July 2026 claimed-scores table on 3830scores.com satisfy Contacts "
    "x Bumblebees x 3 exactly - gen_fobb.py re-verifies from the banked table and "
    "refuses to build otherwise. THE ROSTER IS THE PREFILL SOURCE: the sponsor's "
    "self-serve Bumblebee number report at the stable URL "
    "ars-qrp.com/FOBB/Process_Get_All_By_Number.php (number, call, name, S/P/C), "
    "re-fetched through the call history machinery on the daily clock - 'Self-Serve "
    "Bumblebee Numbers Will Be Available Starting One Month Before the Event Date', "
    "and numbers issue until the event. Roster data is prefill only - Bumblebee "
    "credit comes from the number the station actually sends you, never from roster "
    "membership. verified: partial - one reading is unconfirmed by data, below, "
    "with what it costs. OPEN QUESTION 1: WHAT DOES A LOG WITH CONTACTS BUT NO "
    "BUMBLEBEES SCORE? The printed default says the multiplier is 1 (contacts x 3); "
    "the 3830 calculator's one observed zero row (K4UPG, 0 QSOs / 0 Bumblebees) "
    "computed 0, and no contacts-but-no-Bumblebees row has appeared to decide the "
    "case. This app follows the printed line - points x max(1, Bumblebees) - which "
    "also gives an empty log 0. If the sponsor's calculator instead zeroes a "
    "Bumblebee-less log, this app overstates it. KNOWN LIMITATION 1: THE CABRILLO "
    "CONTEST HEADER 'ARS-FOBB' IS THIS APP'S OWN INVENTION. The sponsor accepts no "
    "log files at all - results are self-reported totals on 3830scores.com ('You "
    "will enter your [Total Contacts] that you made and the [Number of Bumblebees] "
    "that you worked') - and the WA7BNM registry has no FOBB entry (checked "
    "2026-08-10), so the header has no recipient anywhere; the export exists for "
    "your own records. The score sidebar keeps both numbers the form wants on "
    "screen: valid contacts, and Bumblebees as the multiplier count. KNOWN "
    "LIMITATION 2: BETWEEN EVENTS THE ROSTER SERVES THE PREVIOUS EVENT'S NUMBERS. "
    "'Bumblebee Numbers are only valid for One FOBB Event' and reissue each time, "
    "with self-serve opening a month out - so prefill offered before the new "
    "event's numbers open can show a station's old number. Prefill is a hint: log "
    "the number the station sends."
)
assert "verified: partial" in NOTES
for marker in ["OPEN QUESTION 1", "KNOWN LIMITATION 1", "KNOWN LIMITATION 2"]:
    assert marker in NOTES
```

```python
party = {
    "schemaVersion": 1,
    "id": "fobb",
    "name": "ARS Flight of the Bumblebees",
    "cabrilloContest": "ARS-FOBB",
    "homeState": "NA",
    "countyAbbrLength": 2,
    "validBands": ["80m", "40m", "20m", "15m", "10m"],
    "points": {"phone": 3, "cw": 3, "digital": 3},
    "dupeScope": "bandMode",
    "multipliers": {
        "inState": {
            "classes": ["member"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
            "multiplierFloor": 1,
        },
        "outState": {
            "classes": ["member"],
            "homeStateCountsViaCounty": False,
            "countScope": "perBand",
            "multiplierFloor": 1,
        },
    },
    "bonuses": [],
    "dxStyle": "prefix",
    "acceptsDXToken": True,
    "allowedModes": ["cw"],
    "maxSimultaneousCounties": 1,
    "hasHomeRegion": False,
    "memberExchange": {
        "term": "Bumblebee number",
        "shortTerm": "BB #",
        "memberPlural": "Bumblebees",
        "memberPoints": 3,
        "qrpPoints": 3,
        "otherPoints": 3,
        "qrpMaxWatts": {"phone": 5, "cw": 5, "digital": 5},
    },
    "schedule": [
        {"start": "2026-07-26T17:00:00Z", "end": "2026-07-26T21:00:00Z"},
        {"start": "2026-09-20T17:00:00Z", "end": "2026-09-20T21:00:00Z"},
    ],
    "counties": [],
    "notes": NOTES,
    # gen_callhistory.py verifies this block against its own roster of
    # special sources; gen_caveats.py appends the caveats. Run both after
    # this script (pipeline order).
    "callHistory": {
        "kind": "arsFobbRoster",
        "pageURL": "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php",
        "filePrefix": "FOBB",
        "token": "FOBB ROSTER",
    },
}

with open(OUT, "w") as f:
    json.dump(party, f, indent=2, ensure_ascii=False)
    f.write("\n")

print(f"wrote {OUT.name}: formula verified on {len(rows)} rows, "
      f"roster {len(roster)} numbers")
```

- [ ] **Step 2: Register the special call-history source**

In `docs/research/gen_callhistory.py`, the special-source dict (~line 71) gains, beside the skeeter entry:

```python
    "fobb": {
        "kind": "arsFobbRoster",
        # The sponsor's self-serve report is one stable URL — no discovery
        # hop. Live per-event data; the client re-fetches on the daily clock.
        "pageURL": "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php",
        "filePrefix": "FOBB",
        "token": "FOBB ROSTER",
    },
```

(Match the surrounding dict's exact shape — read the skeeter entry first; if it carries other keys, mirror them.)

- [ ] **Step 3: Author the caveats**

In `docs/research/gen_caveats.py`, the `KINDS` dict gains (alphabetical position, near "fqp"):

```python
    "fobb": [
        (0, "ruleInference", "A log with contacts but no Bumblebees scores contacts × 3 — the printed default; the sponsor’s calculator has never been observed on that case."),
        (1, "cosmetic", "The Cabrillo CONTEST header is this app’s invention; the sponsor takes self-reported totals on 3830scores.com, and the sidebar carries both numbers the form wants."),
        (2, "cosmetic", "Between events the roster prefills the previous event’s numbers — log the number the station sends."),
        (None, "provenance", "Rules read from ars-qrp.com (fetched 2026-08-10, 'Last Updated : 27JUL26'); the page is edited in place — re-check before each running, and never read dates from its stale HTML title."),
    ],
```

- [ ] **Step 4: Run the pipeline, in order**

```bash
python3 docs/research/gen_fobb.py
python3 docs/research/gen_hub_map.py
python3 docs/research/gen_callhistory.py
python3 docs/research/gen_caveats.py
git diff --stat Resources/Parties/
```

Expected: `gen_fobb.py` prints `wrote fobb.json: formula verified on 90 rows, roster 234 numbers`; the hub map does not gain a fobb entry (FOBB is not on qsopartyhub — that is correct; if the script *fails* on an unknown party, read its skeeter handling and mirror it); `gen_callhistory.py` writes the fobb block into `fobb.json` unchanged-in-place; `gen_caveats.py` appends the four caveats. **Only `fobb.json` may change** — `git diff --stat` must show no other party file.

- [ ] **Step 5: Verify the JSON loads**

```bash
xcodegen generate
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/CaveatRosterTests 2>&1 | tail -6
```

Expected: `CaveatRosterTests` FAILS at this point only if roster-pinning tests live there (they do not — it checks marked-notes-have-caveats, which now pass). If instead `PartyCatalogTests` machinery loads all bundled files at decode, any malformed JSON surfaces here. Green means the file decodes and the caveats landed.

- [ ] **Step 6: Commit**

```bash
git add docs/research/gen_fobb.py docs/research/gen_callhistory.py docs/research/gen_caveats.py Resources/Parties/fobb.json QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "fobb: ARS Flight of the Bumblebees — generator and party data"
```

---

### Task 7: `FlightOfTheBumblebeesTests` and the roster-pinning edits

**Files:**
- Create: `Tests/Core/FlightOfTheBumblebeesTests.swift`
- Modify: `Tests/Core/PartyCatalogTests.swift` (~lines 17, 45, 79)
- Modify: `Tests/Core/CallHistorySourceTests.swift` (~lines 21, 33, 40)
- Modify: `Tests/Core/ChallengeTests.swift` (~line 26)
- Modify: `Tests/Core/ExchangeParserTests.swift` (~line 66)
- Modify: `Tests/Core/WisconsinQSOPartyTests.swift` (~lines 398–424)
- Modify: `Tests/Core/UpcomingContestsTests.swift` (~lines 25–37)

- [ ] **Step 1: Write the party test file**

Model: `SkeeterHuntTests.swift` (same harness idioms). Full file:

```swift
import XCTest
@testable import QSOPartyLogger

/// ARS Flight of the Bumblebees — the catalogue's second QRP sprint and
/// the event the Skeeter Hunt was modelled on. Four hours twice a year,
/// CW only, no counties, every contact 3 points, and the multiplier is
/// Bumblebees worked counted again on each band, never below 1. Rules
/// research: docs/research/fobb_rules.md; the printed formula was verified
/// against all 90 rows of the sponsor-designated 3830 calculator's July
/// 2026 table, which gen_fobb.py re-verifies.
@MainActor
final class FlightOfTheBumblebeesTests: XCTestCase {

    var fobb: PartyDefinition!

    override func setUpWithError() throws {
        fobb = try XCTUnwrap(PartyCatalog.party(id: "fobb"), "fobb.json must load")
    }

    var seq: TimeInterval = 0
    /// Inside the Fall 2026 window (17:00–21:00Z, 2026-09-20) by construction.
    func qso(
        call: String,
        band: Band = .m20,
        mode: ModeClass = .cw,
        their: String = "NC",
        memberRcvd: String?
    ) -> QSO {
        seq += 30
        return QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_789_923_600 + seq),
            call: call, band: band, modeClass: mode,
            rawMode: mode == .phone ? "SSB" : (mode == .digital ? "FT8" : "CW"),
            rstSent: "599", rstRcvd: "599",
            memberSent: "5W", memberRcvd: memberRcvd,
            myLoc: "TX", theirLoc: their
        )
    }

    func log(_ qsos: [QSO]) -> ContestLog {
        ContestLog(
            partyID: "fobb",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: qsos,
            exchangeMember: "5W"
        )
    }

    // MARK: Shape

    func testPartyShape() {
        XCTAssertEqual(fobb.name, "ARS Flight of the Bumblebees")
        XCTAssertEqual(fobb.cabrilloContest, "ARS-FOBB")
        XCTAssertEqual(fobb.homeState, "NA", "a pseudo-state, labels only")
        XCTAssertFalse(fobb.hasHomeRegion)
        XCTAssertTrue(fobb.counties.isEmpty, "S/P/C earns nothing; nothing to enumerate")
        XCTAssertEqual(fobb.allowedModeClasses, [.cw], "'QRP CW Contacts'")
        XCTAssertEqual(fobb.validBands, [.m80, .m40, .m20, .m15, .m10])
        XCTAssertEqual(fobb.maxSimultaneousCounties, 1)
        XCTAssertEqual(fobb.dxStyle, .prefix)
        XCTAssertTrue(fobb.acceptsDXToken)
        XCTAssertTrue(fobb.exchangeIncludesRST)
        XCTAssertFalse(fobb.exchangeIncludesSerial)
        XCTAssertFalse(fobb.exchangeIncludesName)
        XCTAssertNil(fobb.scoreMultipliers)
        XCTAssertTrue(fobb.entryClasses.isEmpty, "no X-classes here, unlike Skeeter")
        XCTAssertTrue(fobb.bonuses.isEmpty, "no bonus of any kind — explicit NONE")
        XCTAssertNil(fobb.hubSpots)
        XCTAssertTrue(fobb.combines.isEmpty)
        XCTAssertTrue(fobb.isPartiallyVerified)
        XCTAssertFalse(fobb.outStateWorksHomeStationsOnly, "everyone works everyone")

        for rule in [fobb.multipliers.inState, fobb.multipliers.outState] {
            XCTAssertEqual(rule.classes, [.member],
                           "the ONLY multiplier is Bumblebees worked")
            XCTAssertEqual(rule.countScope, .perBand,
                           "'an additional Bumblebee Worked' on each new band")
            XCTAssertEqual(rule.multiplierFloor, 1, "'(Defaults to … = 1)'")
            XCTAssertFalse(rule.dxCountsEntities)
            XCTAssertNil(rule.dxMultCap)
        }
        XCTAssertEqual(fobb.multipliers.inState, fobb.multipliers.outState)
    }

    func testMemberExchangeIsTheBumblebeeNumbers() throws {
        let member = try XCTUnwrap(fobb.memberExchange)
        XCTAssertEqual(member.term, "Bumblebee number")
        XCTAssertEqual(member.shortTerm, "BB #")
        XCTAssertEqual(member.memberPlural, "Bumblebees")
        XCTAssertEqual(member.memberPoints, 3)
        XCTAssertEqual(member.qrpPoints, 3, "the element never moves the rate here")
        XCTAssertEqual(member.otherPoints, 3)
        XCTAssertEqual(member.qrpMaxWatts.limit(for: .cw), 5, "'5W QRP Maximum'")
    }

    /// Both sponsor-printed 2026 windows, exact instants (NAQP precedent).
    func testBothFourHourWindowsShip() throws {
        let windows = try XCTUnwrap(fobb.schedule)
        XCTAssertEqual(windows.count, 2)
        let f = ISO8601DateFormatter()
        XCTAssertEqual(windows[0].start, f.date(from: "2026-07-26T17:00:00Z"))
        XCTAssertEqual(windows[0].end, f.date(from: "2026-07-26T21:00:00Z"))
        XCTAssertEqual(windows[1].start, f.date(from: "2026-09-20T17:00:00Z"))
        XCTAssertEqual(windows[1].end, f.date(from: "2026-09-20T21:00:00Z"))
    }

    // MARK: Exchange parsing

    func testEveryPeerLocationShapeParses() {
        for token in ["NJ", "TX", "ON", "BC", "DC"] {
            guard case .success(let parsed) = ExchangeParser.parse(
                token, party: fobb, role: .outOfState) else {
                return XCTFail("\(token) must parse")
            }
            XCTAssertEqual(parsed.locations, [token])
        }
        for token in ["DL", "G", "XE", "DX"] {
            guard case .success = ExchangeParser.parse(
                token, party: fobb, role: .outOfState) else {
                return XCTFail("\(token) must parse — the C in S/P/C")
            }
        }
        guard case .failure = ExchangeParser.parse("QQ", party: fobb, role: .outOfState)
        else { return XCTFail("garbage must not validate") }
    }

    /// The element refuses only text the party cannot read; a blank field
    /// logs (a station that sends no number is a home station).
    func testUnreadableElementBlocksLoggingButABlankOneDoesNot() {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "fobb",
            exchangeMember: "5W",
            undoManager: nil
        )
        let flow = EntryFlow(document: doc)
        let context = EntryFlow.Context()

        flow.entry.call = "W4KAC/BB"
        flow.entry.exchangeTyped = "NC"
        flow.entry.memberRcvd = "seven"
        XCTAssertEqual(flow.logContact(context, undoManager: nil), .nothing)
        XCTAssertTrue(doc.log.qsos.isEmpty)

        flow.entry.memberRcvd = "7"
        guard case .logged(let rows, _) = flow.logContact(context, undoManager: nil) else {
            return XCTFail("a complete exchange logs")
        }
        XCTAssertEqual(rows[0].memberSent, "5W")
        XCTAssertEqual(rows[0].memberRcvd, "7")
        XCTAssertEqual(rows[0].call, "W4KAC/BB", "the call as sent, suffix and all")
    }

    // MARK: Scoring — contacts × Bumblebees × 3

    /// The sponsor's product, end to end: 4 contacts, one bee on two bands
    /// = 2 Bumblebees → 12 points × 2 = 24 = 4 × 2 × 3.
    func testThePrintedFormulaEndToEnd() {
        let rows = [
            qso(call: "W4KAC/BB", band: .m20, memberRcvd: "7"),
            qso(call: "W4KAC/BB", band: .m40, memberRcvd: "7"),
            qso(call: "K1HOME", band: .m20, their: "NH", memberRcvd: "5W"),
            qso(call: "AC7A", band: .m20, their: "AZ", memberRcvd: nil),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertEqual(score.validQSOs, 4)
        XCTAssertEqual(score.qsoPoints, 12, "every valid contact pays 3")
        XCTAssertEqual(score.memberQSOs, 2, "'an additional Bumblebee Worked'")
        XCTAssertEqual(score.multiplierCount, 2)
        XCTAssertEqual(score.total, 24)
    }

    /// The floor: contacts and no bee still score contacts × 1 × 3.
    func testABeeLessLogScoresContactsTimesThree() {
        let rows = [
            qso(call: "K1HOME", their: "NH", memberRcvd: "5W"),
            qso(call: "AC7A", their: "AZ", memberRcvd: nil),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertTrue(score.multiplierKeys.isEmpty)
        XCTAssertEqual(score.multiplierCount, 1, "'(Defaults to … = 1)'")
        XCTAssertEqual(score.total, 6)
    }

    func testAnEmptyLogIsZeroNotThree() {
        XCTAssertEqual(ScoreEngine.score(log: log([]), party: fobb).total, 0,
                       "the K4UPG row: the sponsor's calculator scored 0/0 as 0")
    }

    /// The S/P/C earns nothing — the case that would fail if state or dx
    /// ever crept into the classes.
    func testLocationsNeverMultiply() {
        let rows = [
            qso(call: "K1NH", their: "NH", memberRcvd: "5W"),
            qso(call: "VE3ON", their: "ON", memberRcvd: "5W"),
            qso(call: "DL1AA", their: "DL", memberRcvd: "5W"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertTrue(score.workedValues(.state).isEmpty)
        XCTAssertTrue(score.workedValues(.province).isEmpty)
        XCTAssertTrue(score.workedValues(.dx).isEmpty)
        XCTAssertEqual(score.multiplierCount, 1, "the floor, not the locations")
        XCTAssertEqual(score.total, 9)
    }

    /// A DX bee counts like any bee: prefix location, member key.
    func testADXBumblebeeIsABumblebee() {
        let score = ScoreEngine.score(
            log: log([qso(call: "G4CIB/P", their: "G", memberRcvd: "31")]),
            party: fobb)
        XCTAssertEqual(score.memberQSOs, 1)
        XCTAssertEqual(score.workedValues(.member), ["G4CIB/P"])
        XCTAssertEqual(score.total, 3)
    }

    // MARK: Dupes

    func testSameBandIsADupeNewBandIsNewContactAndNewBee() {
        let rows = [
            qso(call: "N7CQR/BB", band: .m20, memberRcvd: "23"),
            qso(call: "N7CQR/BB", band: .m20, memberRcvd: "23"),
            qso(call: "N7CQR/BB", band: .m40, memberRcvd: "23"),
        ]
        let score = ScoreEngine.score(log: log(rows), party: fobb)
        XCTAssertEqual(score.dupeCount, 1, "'once on each Band'")
        XCTAssertEqual(score.validQSOs, 2)
        XCTAssertEqual(score.multiplierCount, 2)
        XCTAssertEqual(score.total, 6 * 2)
    }

    /// "QRP CW" — a phone row is invalid, not zero-point.
    func testPhoneRowsAreInvalidNotZeroPoint() {
        let score = ScoreEngine.score(
            log: log([qso(call: "W4KAC/BB", mode: .phone, memberRcvd: "7")]),
            party: fobb)
        XCTAssertEqual(score.invalidModeCount, 1)
        XCTAssertEqual(score.validQSOs, 0)
        XCTAssertTrue(score.multiplierKeys.isEmpty)
    }

    // MARK: The live badge

    /// A bee on a fresh band lights NEW MULT; the same bee there again, or
    /// a home station, does not.
    func testNewMultBadgeChasesBeesAcrossBands() {
        let contest = log([qso(call: "W4KAC/BB", band: .m20, memberRcvd: "7")])
        XCTAssertTrue(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m40, modeClass: .cw,
            log: contest, party: fobb, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NC"], band: .m20, modeClass: .cw,
            log: contest, party: fobb, call: "W4KAC/BB", memberRcvd: "7"))
        XCTAssertFalse(ScoreEngine.wouldAddMultiplier(
            theirLocs: ["NH"], band: .m40, modeClass: .cw,
            log: contest, party: fobb, call: "K1HOME", memberRcvd: "100W"))
    }

    // MARK: Exports

    func testCabrilloCarriesTheElementsAndTheEntrantsToken() throws {
        let contest = log([qso(call: "W4KAC/BB", memberRcvd: "7")])
        let score = ScoreEngine.score(log: contest, party: fobb)
        let export = CabrilloExporter.export(log: contest, party: fobb, score: score)

        XCTAssertTrue(export.contains("CONTEST: ARS-FOBB"), export)
        XCTAssertTrue(export.contains("LOCATION: TX"))
        let line = try XCTUnwrap(export.split(separator: "\n").first { $0.hasPrefix("QSO:") })
        let fields = line.split(separator: " ").map(String.init)
        XCTAssertEqual(Array(fields.suffix(8)),
                       ["KE5CW", "599", "TX", "5W", "W4KAC/BB", "599", "NC", "7"])
    }

    func testAdifCarriesTheElementInAppFields() {
        let record = AdifExporter.record(
            qso(call: "W4KAC/BB", memberRcvd: "7"),
            myCall: "KE5CW", party: fobb, countyNames: [:], myState: "TX"
        )
        XCTAssertTrue(record.contains("<app_qsopartylogger_member_sent:2>5W"), record)
        XCTAssertTrue(record.contains("<app_qsopartylogger_member_rcvd:1>7"), record)
    }

    // MARK: Messages

    func testDefaultMessagesTrailTheLocationWithTheElement() {
        let sets = MessageSets.defaults(for: fobb)
        XCTAssertTrue(sets.searchPounce.contains("{RST} {EXCH} {MEMBER}"),
                      "\(sets.searchPounce)")
    }

    // MARK: The roster source

    func testCallHistoryIsTheSponsorsRosterReport() throws {
        let source = try XCTUnwrap(fobb.callHistory)
        XCTAssertEqual(source.kind, .arsFobbRoster)
        XCTAssertEqual(source.pageURL,
                       "https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php")
        XCTAssertEqual(source.filePrefix, "FOBB")
        XCTAssertEqual(source.token, "FOBB ROSTER")
    }

    // MARK: Verification posture

    /// Partial on exactly one open question, and nothing badges: the score
    /// and export are exact on every observed case.
    func testCaveatsAreNamedAndNoneBadge() {
        XCTAssertEqual(fobb.caveats.count, 4)
        XCTAssertTrue(fobb.blockingCaveats.isEmpty)
        XCTAssertEqual(fobb.operatorAlerts.count, 3,
                       "OQ1 and two KNOWN LIMITATIONs; provenance stands alone")
    }

    // MARK: Not a Challenge contest

    func testFOBBIsUpcomingButNotAChallengeContest() throws {
        let calendar = try XCTUnwrap(ChallengeCalendar.loadBundled())
        XCTAssertNil(calendar.contest(partyID: "fobb"))
        XCTAssertNil(calendar.contest(named: "ARS Flight of the Bumblebees"))

        let eve = ISO8601DateFormatter().date(from: "2026-09-10T12:00:00Z")!
        let upcoming = UpcomingContests.upcoming(
            now: eve,
            parties: PartyCatalog.loadBundled(),
            calendar: calendar,
            records: []
        )
        let entry = upcoming.first { $0.partyID == "fobb" }
        XCTAssertNotNil(entry, "the Sept 20 window surfaces by itself")
        XCTAssertEqual(entry?.isApproved, false)
        XCTAssertEqual(entry?.nextWindow.start,
                       ISO8601DateFormatter().date(from: "2026-09-20T17:00:00Z"),
                       "the July window is past; the Fall one is next")
    }
}
```

Adjust only against compiler/actual-API friction (e.g. `AdifExporter.record` argument labels), never against intent; if the ADIF field-length assertion `member_rcvd:1` trips, print the record and match the exporter's real emission.

- [ ] **Step 2: Run it (expect the pinning fallout)**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/fobb-task7.log | tail -25
```

Expected: `FlightOfTheBumblebeesTests` PASS; deliberate failures in the roster-pinning suites, which the next step restates. Read the full log, not the tail, to enumerate them.

- [ ] **Step 3: Restate every pinned roster, deliberately**

Each edit below is a *decision being re-made on purpose* (that is why they are pinned). Apply, citing fobb in comments only where the file's style does:

1. `Tests/Core/PartyCatalogTests.swift:17` — the bundled-id list gains `"fobb"` in alphabetical position (after `"deqp"`, before `"fqp"`).
2. `PartyCatalogTests.swift:45` — `unrestricted` gains `"fobb"` (read the set's comment first; FOBB qualifies: "You can work Non-QRP Stations" — everyone works everyone, and home-to-home counts).
3. `PartyCatalogTests.swift:~79` — the `expectedPartial` roster gains `"fobb"` (OPEN QUESTION 1).
4. `Tests/Core/CallHistorySourceTests.swift:21,33` — the comment becomes "47 of the 50 bundled parties…" and the assertion `== 47`.
5. `CallHistorySourceTests.swift:~40` — beside the `.w2ljRosterPage` filter, add the sibling: exactly one party has kind `.arsFobbRoster` and it is `fobb`.
6. `Tests/Core/ChallengeTests.swift:26` — the subtraction set gains `"fobb"`.
7. `Tests/Core/ExchangeParserTests.swift:66` — prefix-party count `17` → `18`.
8. `Tests/Core/WisconsinQSOPartyTests.swift:398–424` — the totals loop needs no change (FOBB's two windows total 8 h > WIQP's 7 h — verify, don't assume), but the single-window sweep excluding `wiqp`/`skeeter` now sees FOBB's 4 h windows: extend both `filter`/`where` clauses with `&& party.id != "fobb"` (and the `$0.id != "fobb"` form), and reword the doc comment: the two QRP sprints share the 4-hour single-window superlative.
9. `Tests/Core/UpcomingContestsTests.swift:25–37` — with `now: 2026-07-25T12:00:00Z`, FOBB's July 26 window now sits second: first stays `alqp`; `dropFirst().first` becomes `fobb` (`isApproved == false`, window start `2026-07-26T17:00:00Z`); `naqpcw` moves to `dropFirst(2)`, `mdc` to `dropFirst(3)`. Read the whole test before editing — keep its assertion style, just shift the expectations.

- [ ] **Step 4: Full suite green**

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/fobb-task7b.log | tail -6
```

Expected: `** TEST SUCCEEDED **`. Any residual failure is either an unswept pin (fix as above, deliberately) or a real defect (stop and debug with superpowers:systematic-debugging — do not bend a party test to pass).

- [ ] **Step 5: Commit**

```bash
git add Tests/Core/FlightOfTheBumblebeesTests.swift Tests/Core/PartyCatalogTests.swift Tests/Core/CallHistorySourceTests.swift Tests/Core/ChallengeTests.swift Tests/Core/ExchangeParserTests.swift Tests/Core/WisconsinQSOPartyTests.swift Tests/Core/UpcomingContestsTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "fobb: the party test floor, and the rosters restated"
```

---

### Task 8: Docs — README, PARTIES.md, PROVENANCE.md

**Files:**
- Modify: `README.md` (supported-parties table; the test-count line)
- Modify: `docs/PARTIES.md`
- Modify: `docs/PROVENANCE.md`

- [ ] **Step 1: README table row and test count**

Find the Skeeter Hunt row (`grep -n "Skeeter" README.md`) and add FOBB beside it, matching the table's exact columns; derive every value from `fobb.json`, hand-typing nothing (Article 2): two windows 2026-07-26 and 2026-09-20 each 1700–2100Z, CW only, 80/40/20/15/10, multiplier "Bumblebees worked, per band (floor 1)". Update the README's test count from the Task 7 full-suite run's own reported total (`grep -c "passed" /tmp/fobb-task7b.log` is not the number — use the count xcodebuild prints, "Executed N tests"). No keyboard-table change (no key gained a behavior).

- [ ] **Step 2: PARTIES.md entry**

Add beside the Skeeter entry, covering: what is unusual (the S/P/C is exchanged but worth nothing; the multiplier is Bumblebees per band with a printed floor of 1; ×3 folded into points; two windows a year, July printed by the Wayback capture of the sponsor's own page; roster prefill emits CALL and CALL/BB), and every rule not modelled (Home/Bumblebee is a 3830 reporting split, not a class; the 5 W limit is an entry condition; OPEN QUESTION 1's zero-bee edge). Quote the formula line verbatim.

- [ ] **Step 3: PROVENANCE.md**

Add the FOBB block: `https://ars-qrp.com/FOBB/FOBB.html` (fetched 2026-08-10, "Last Updated : 27JUL26"); Internet Archive snapshot 20260723202047 of the same URL (the July printed date); `https://ars-qrp.com/FOBB/Process_Get_All_By_Number.php` (roster, fetched 2026-08-10, 234 numbers); `https://www.3830scores.com/editionscores.php?arg=RvJxJizV77DLxU` (July 2026 claimed scores, 90 rows, formula verification); WA7BNM cabnames checked 2026-08-10 — no entry, header invented. Match the file's existing per-party format.

- [ ] **Step 4: Commit**

```bash
git add README.md docs/PARTIES.md docs/PROVENANCE.md
git commit -m "fobb: docs — README row, PARTIES entry, PROVENANCE sources"
```

---

### Task 9: Full verification and wrap-up

- [ ] **Step 1: The whole suite, from clean**

```bash
xcodegen generate
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /tmp/fobb-final.log | tail -6
```

Expected: `** TEST SUCCEEDED **`. Record the executed-tests count and confirm it matches the README (Task 8). Article 8: report this command and its tail verbatim in the final summary; if any step of this plan was skipped, say which.

- [ ] **Step 2: The Article 22 checklist, ticked in the summary**

- `docs/research/fobb_rules.md` complete, all 14 sections ✓ (landed with the spec)
- roster/formula generated+asserted by script (`gen_fobb.py`, the no-county Article 2 analogue) ✓
- `Resources/Parties/fobb.json` with provenance and `verified: partial` + OPEN QUESTION 1 ✓
- per-party test file meeting the Article 18 floor (adapted to a no-county party: exchange gating, both mult scopes' would-fail cases, invalid modes, dupes, schedule instants, exports) ✓
- full suite green — command and output recorded ✓
- docs: README row + test count, PARTIES.md, PROVENANCE.md ✓
- every commit touches FOBB alone ✓

- [ ] **Step 3: Finish the branch**

Use superpowers:finishing-a-development-branch — present merge/PR options for the worktree branch; do not merge without checking master's divergence first (standing practice: master moves under long sessions).

---

## Self-review notes (already applied)

- The spec's §1 NEW MULT badge, §2 floor, §3 points fold, §4 roster kind, §5 party fields, §6 generator, and the whole test plan each map to Tasks 1–7; docs to Task 8 (spec-coverage check).
- `wouldAddMultiplier(theirLocs:band:modeClass:log:party:call:memberRcvd:)` is spelled identically in Task 1 (definition), Task 3 (call site), and Task 7 (tests); `multiplierFloor` identically in Tasks 2, 6, 7 (type-consistency check).
- Known discovery points left deliberately open, each with its finding command: the EntryState property names and member-field retrigger (Task 3 Step 2), the client-test scaffolding file (Task 5), the special-source dict's exact shape (Task 6 Step 2), and every pinned-test restatement (Task 7 Step 3). Everything else is exact.

# General Contest Logger — Foundations (Phase 0 + Phase 1a) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the general rules model (`ContestDefinition` and its parts), the pure lowering of every bundled `PartyDefinition` into it, the cty.csv table, the WPX prefix rule, the per-kind exchange validator, the general dupe rule and the operating-time computation — all **additive**, with the app's behaviour byte-for-byte unchanged and every existing test green.

**Architecture:** New types live in `Sources/Core/Contests/`. Nothing in the engine, entry flow, exporters or UI is switched to the new model in this plan — that is the next plan ("engine switch"). Every new type has its own test file; the lowering is proven against all 50 bundled party files; the validator is proven equivalent to `ExchangeParser` on the lowered parties.

**Tech Stack:** Swift 6 / SwiftUI, XCTest, XcodeGen (`project.yml` is the source of truth), Python 3 generators under `docs/research/`.

**Spec:** [`docs/superpowers/specs/2026-08-17-general-contest-logger-design.md`](../specs/2026-08-17-general-contest-logger-design.md) — sections 1.2, 1.3, 1.6, 2.9 and "Testing".

---

## Conventions for every task

- Work in the worktree `/Users/tom/AppDev/Apple/QSOPartyLogger/.claude/worktrees/general-contest-logger` (branch `worktree-general-contest-logger`). Never run git or xcodebuild against the main checkout.
- After **adding or moving any Swift or resource file**, run `xcodegen generate` (XcodeGen enumerates files at generation time).
- Build: `xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | tail -5`
- One test class: `set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/<ClassName> 2>&1 | grep -E "Test Case|Executed|error:|BUILD" | tail -30`
- Full suite (end of every task that touches shared code): `set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests|error:|failed" | tail -5` — expected `Executed N tests, with 0 failures` where N ≥ 2875 (the measured baseline) and grows with each task.
- Tests never touch the network or hardware (Article 5). Bundled resources are read through `Bundle.main` (the test bundle is hosted inside the app).
- Commit after every green step with the message shown; every commit message ends with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- Constitution Article 4: this plan adds no party and changes no score. Article 6: the README test count is updated in the last task.

## File structure

Create (`Sources/Core/Contests/`):
- `TokenSet.swift` — enumerated token sets + built-ins (`usStates`, `provinces`, `cqZones`, `ituZones`, `dxToken`, `sections(bundle:)`).
- `Side.swift` — `Side`, `SidePredicate`.
- `ExchangeElement.swift` — `ExchangeElement`, `Kind`, `SentSpec`, `PrefillSource`, `Derivation`, `MemberSpec`.
- `MultiplierClass.swift` — `MultiplierClass`, `Resolver`, `MultiplierLayout`.
- `PointRule.swift` — `PointRule`, `PointCondition`.
- `ContestRules.swift` — `DupeRule`, `OperatingTimeRule`, `Categories`, `CabrilloSpec`, `ScoreFactors`, `SideRules`, `ActivatedRule`, `ContestSources`, `ContestFamily`.
- `ContestDefinition.swift` — the assembled model, Codable, `validate()`.
- `PartyLowering.swift` — `PartyLowering.lower(_:)`.
- `CTYTable.swift` — cty.csv parser and callsign resolver.
- `WPXPrefix.swift` — CQ WPX prefix rule.
- `ExchangeValidator.swift` — per-kind validation of one element value.
- `OperatingTime.swift` — operating/off-time computation.
- `ContestCatalog.swift` — loads parties (lowered) and v2 files.

Move (git mv, unchanged content): `HubSpotSource.swift`, `CallHistorySource.swift`, `DXCCTable.swift`, `DXCCLabelRefresh.swift`, `DXCCLabelStore.swift`, `MultiplierRoster.swift`, `ScoreFactor.swift` from `Sources/Core/Parties/` to `Sources/Core/Contests/`.

Rename: `Sources/UI/PartyNotice.swift` → `ContestNotice.swift` (type `PartyNotice` → `ContestNotice`).

Modify: `Sources/Core/Engine/DupeChecker.swift` (add a `DupeRule` overload), `project.yml` (two resource folders), `README.md` (test count), `CLAUDE.md` (layout row).

Resources: `Resources/Data/arrl_sections.json` (+ generator `docs/research/gen_sections.py`), `Resources/CTY/cty.csv` + `Resources/CTY/VERSION.txt` (+ fetch script `docs/research/fetch_cty.py`).

Tests (`Tests/Core/`): `TokenSetTests`, `ArrlSectionsTests`, `SideTests`, `ExchangeElementTests`, `MultiplierClassTests`, `PointRuleTests`, `ContestDefinitionTests`, `PartyLoweringTests`, `CTYTableTests`, `WPXPrefixTests`, `ExchangeValidatorTests`, `DupeRuleTests`, `OperatingTimeTests`, `ContestCatalogTests`.

---

### Task 1: Baseline

- [ ] **Step 1: Generate the project and record the baseline count**

```bash
xcodegen generate && set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -E "Executed [0-9]+ tests" | tail -1
```
Expected: `Executed 2875 tests, with 0 failures` (measured 2026-08-17 in this worktree: 2875 in ~51 s).

- [ ] **Step 2: Nothing to commit** (the tracked `.xcodeproj` should be unchanged; if `git status` shows it modified, commit it alone as `build: regenerate project`).

---

### Task 2: Rename `PartyNotice` → `ContestNotice`

**Files:**
- Rename: `Sources/UI/PartyNotice.swift` → `Sources/UI/ContestNotice.swift`
- Modify: every file that references `PartyNotice` (7 files: `git grep -l PartyNotice`)
- Rename test: `Tests/UI/PartyNoticeTests.swift` → `Tests/UI/ContestNoticeTests.swift`

- [ ] **Step 1: Rename the files and the identifier**

```bash
git mv Sources/UI/PartyNotice.swift Sources/UI/ContestNotice.swift
git mv Tests/UI/PartyNoticeTests.swift Tests/UI/ContestNoticeTests.swift
git grep -l 'PartyNotice' -- Sources Tests | xargs sed -i '' 's/PartyNotice/ContestNotice/g'
xcodegen generate
```

- [ ] **Step 2: Build and run the renamed tests**

Run: `set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/ContestNoticeTests 2>&1 | grep -E "Executed|error:" | tail -3`
Expected: `Executed N tests, with 0 failures` (same N as `PartyNoticeTests` had).

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "ui: PartyNotice → ContestNotice (rename only)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Move the general types into `Sources/Core/Contests/`

**Files:** `git mv` from `Sources/Core/Parties/` to `Sources/Core/Contests/`: `HubSpotSource.swift`, `CallHistorySource.swift`, `DXCCTable.swift`, `DXCCLabelRefresh.swift`, `DXCCLabelStore.swift`, `MultiplierRoster.swift`, `ScoreFactor.swift`. Modify `CLAUDE.md` (layout table).

- [ ] **Step 1: Move**

```bash
mkdir -p Sources/Core/Contests
for f in HubSpotSource CallHistorySource DXCCTable DXCCLabelRefresh DXCCLabelStore MultiplierRoster ScoreFactor; do git mv Sources/Core/Parties/$f.swift Sources/Core/Contests/$f.swift; done
xcodegen generate
```

- [ ] **Step 2: Add the layout row in `CLAUDE.md`**

Insert after the `Sources/Core/Parties/` row:

```markdown
| `Sources/Core/Contests/` | The general contest model (`ContestDefinition`, token sets, sides, exchange spec, multiplier classes, point rules), `PartyLowering`, `ContestCatalog`, `CTYTable`, `WPXPrefix`, `ExchangeValidator`, `OperatingTime`; shared sources (`HubSpotSource`, `CallHistorySource`, `DXCCTable`, `MultiplierRoster`, `ScoreFactor`) |
```

- [ ] **Step 3: Full suite**

Run the full-suite command. Expected: `Executed 2875 tests, with 0 failures`.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "core: move the contest-general types into Sources/Core/Contests (moves only)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `TokenSet` and the built-in sets

**Files:**
- Create: `Sources/Core/Contests/TokenSet.swift`
- Test: `Tests/Core/TokenSetTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class TokenSetTests: XCTestCase {
    func testCanonicalFoldsCaseAndAliases() {
        let set = TokenSet(id: "states", term: "state", termPlural: "states",
                           tokens: [.init(abbr: "MD"), .init(abbr: "TX")],
                           aliases: ["DC": "MD"])
        XCTAssertEqual(set.canonical("tx"), "TX")
        XCTAssertEqual(set.canonical("dc"), "MD")
        XCTAssertNil(set.canonical("ZZ"))
        XCTAssertTrue(set.accepts("DC"))
        XCTAssertEqual(set.acceptedTokens, ["MD", "TX", "DC"])
    }

    func testUSStatesHasFiftyPlusDC() {
        XCTAssertEqual(TokenSet.usStates.tokens.count, 51)
        XCTAssertTrue(TokenSet.usStates.accepts("DC"))
        XCTAssertTrue(TokenSet.usStates.accepts("HI"))
        XCTAssertEqual(TokenSet.usStates.term, "state")
    }

    func testProvincesAreTheThirteen() {
        XCTAssertEqual(Set(TokenSet.provinces.tokens.map(\.abbr)), MultClass.canadianProvinces)
    }

    func testZoneSetsEnumerateOneToFortyAndNinety() {
        XCTAssertEqual(TokenSet.cqZones.tokens.first?.abbr, "1")
        XCTAssertEqual(TokenSet.cqZones.tokens.last?.abbr, "40")
        XCTAssertEqual(TokenSet.ituZones.tokens.count, 90)
        XCTAssertEqual(TokenSet.cqZones.canonical("05"), "5")
    }

    func testDXTokenSet() {
        XCTAssertEqual(TokenSet.dxToken.acceptedTokens, ["DX"])
    }

    func testBuiltInLookup() {
        XCTAssertNotNil(TokenSet.builtIn(id: "usStates"))
        XCTAssertNil(TokenSet.builtIn(id: "counties"))
    }

    func testTokenGroupsSurviveJSON() throws {
        let set = TokenSet(id: "counties", term: "county", termPlural: "counties",
                           tokens: [.init(abbr: "ADA", name: "Ada", group: "ID")])
        let data = try JSONEncoder().encode(set)
        let back = try JSONDecoder().decode(TokenSet.self, from: data)
        XCTAssertEqual(back, set)
        XCTAssertEqual(back.tokens[0].group, "ID")
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodegen generate` then the one-class command with `TokenSetTests`. Expected: build error `cannot find 'TokenSet' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// An enumerated set of exchange tokens — a party's counties, the 85 ARRL/RAC
/// sections, the US states — with the aliases a sponsor accepts for them.
///
/// Sets are referenced by `id` from `ExchangeElement.sentBy` (what a side
/// sends), `Resolver` (what a class counts) and `MultiplierClass.roster`
/// (what the sidebar lists). A contest's own sets shadow the built-ins by id.
struct TokenSet: Codable, Equatable, Sendable, Identifiable {
    struct Token: Codable, Hashable, Sendable {
        let abbr: String
        let name: String?
        /// The token's grouping for display and for `Resolver.mapTo == "group"`
        /// — a county's state in a multi-state party.
        let group: String?

        init(abbr: String, name: String? = nil, group: String? = nil) {
            self.abbr = abbr.uppercased()
            self.name = name
            self.group = group
        }
    }

    let id: String
    /// Lowercase singular, as `PartyDefinition.countyTerm` is ("county").
    let term: String
    let termPlural: String
    let tokens: [Token]
    /// Accepted spelling → canonical token ("DC" → "MD" where a party credits
    /// DC as Maryland). Keys are accepted on input; values must be tokens.
    let aliases: [String: String]

    init(id: String, term: String, termPlural: String, tokens: [Token], aliases: [String: String] = [:]) {
        self.id = id
        self.term = term
        self.termPlural = termPlural
        self.tokens = tokens
        self.aliases = Dictionary(uniqueKeysWithValues: aliases.map { ($0.key.uppercased(), $0.value.uppercased()) })
    }

    private enum CodingKeys: String, CodingKey { case id, term, termPlural, tokens, aliases }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            term: try c.decode(String.self, forKey: .term),
            termPlural: try c.decode(String.self, forKey: .termPlural),
            tokens: try c.decode([Token].self, forKey: .tokens),
            aliases: try c.decodeIfPresent([String: String].self, forKey: .aliases) ?? [:]
        )
    }

    var abbrs: Set<String> { Set(tokens.map(\.abbr)) }

    /// Every spelling the set accepts: its tokens and its alias keys.
    var acceptedTokens: Set<String> { abbrs.union(aliases.keys) }

    func accepts(_ raw: String) -> Bool { canonical(raw) != nil }

    /// The token a spelling credits, or nil. Zone sets fold "05" to "5".
    func canonical(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespaces).uppercased()
        if abbrs.contains(t) { return t }
        if let aliased = aliases[t] { return aliased }
        if let n = Int(t), abbrs.contains(String(n)) { return String(n) }
        return nil
    }

    func token(for abbr: String) -> Token? {
        guard let canon = canonical(abbr) else { return nil }
        return tokens.first { $0.abbr == canon }
    }

    // MARK: Built-ins

    /// 50 states + DC (`MultClass.acceptedStateTokens`).
    static let usStates = TokenSet(
        id: "usStates", term: "state", termPlural: "states",
        tokens: MultClass.acceptedStateTokens.sorted().map { Token(abbr: $0) })

    /// The 13 provinces and territories (`MultClass.canadianProvinces`).
    static let provinces = TokenSet(
        id: "provinces", term: "province", termPlural: "provinces",
        tokens: MultClass.canadianProvinces.sorted().map { Token(abbr: $0) })

    static let cqZones = TokenSet(
        id: "cqZones", term: "zone", termPlural: "zones",
        tokens: (1...40).map { Token(abbr: String($0)) })

    static let ituZones = TokenSet(
        id: "ituZones", term: "ITU zone", termPlural: "ITU zones",
        tokens: (1...90).map { Token(abbr: String($0)) })

    static let dxToken = TokenSet(
        id: "dxToken", term: "DX", termPlural: "DX",
        tokens: [Token(abbr: MultClass.dxToken, name: "Outside the US and Canada")])

    /// The built-in set for an id, or nil. `sections` is loaded from the
    /// bundle (see `TokenSet.sections(bundle:)`) and is not in this table.
    static func builtIn(id: String) -> TokenSet? {
        switch id {
        case usStates.id: usStates
        case provinces.id: provinces
        case cqZones.id: cqZones
        case ituZones.id: ituZones
        case dxToken.id: dxToken
        default: nil
        }
    }
}
```

- [ ] **Step 4: Run to verify pass** — one-class command with `TokenSetTests`. Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/TokenSet.swift Tests/Core/TokenSetTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: TokenSet — enumerated exchange tokens with aliases, plus the built-in state/province/zone/DX sets

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: The 85 ARRL/RAC sections as bundled data (Article 2)

**Files:**
- Create: `docs/research/gen_sections.py`, `Resources/Data/arrl_sections.json`
- Modify: `project.yml` (add `Resources/Data` folder resource), `Sources/Core/Contests/TokenSet.swift` (add `sections(bundle:)`)
- Test: `Tests/Core/ArrlSectionsTests.swift`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import QSOPartyLogger

final class ArrlSectionsTests: XCTestCase {
    func testEightyFiveSectionsFromTheSponsorsList() throws {
        let sections = try XCTUnwrap(TokenSet.sections(bundle: .main))
        XCTAssertEqual(sections.id, "sections")
        XCTAssertEqual(sections.tokens.count, 85)
        XCTAssertEqual(sections.abbrs.count, 85)
        // Irregular ones (Article 18's habit): not the obvious two-letter states.
        XCTAssertEqual(sections.token(for: "NTX")?.name, "North Texas")
        XCTAssertEqual(sections.token(for: "TER")?.name, "Territories")
        XCTAssertEqual(sections.token(for: "GH")?.name, "Ontario Golden Horseshoe")
        XCTAssertEqual(sections.token(for: "PAC")?.name, "Pacific")
        XCTAssertEqual(sections.token(for: "MDC")?.name, "Maryland-DC")
        XCTAssertEqual(sections.token(for: "NLI")?.name, "New York City-Long Island")
        XCTAssertEqual(sections.token(for: "WCF")?.group, "U.S. Call Area 4")
        XCTAssertEqual(sections.token(for: "AB")?.group, "Canada")
        XCTAssertFalse(sections.accepts("TX"))     // a state, not a section
        XCTAssertFalse(sections.accepts("YT"))     // Yukon sends TER in 2026
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `type 'TokenSet' has no member 'sections'`.

- [ ] **Step 3: Write the generator**

`docs/research/gen_sections.py`:

```python
#!/usr/bin/env python3
"""Generate Resources/Data/arrl_sections.json — the 85 ARRL/RAC sections.

CONSTITUTION Article 2: parsed from the banked sponsor text, never typed.
SOURCE (Article 1): docs/research/arrl_sections_2026.txt, SOURCE A block =
https://contests.arrl.org/contestmultipliers.php?a=wve ("These are the names
of the 85 W/VE sections used in ARRL contests"), page footer "Version: 1.2.0,
Revised: May 12, 2023", fetched 2026-08-17. The Sweepstakes page the same
day: "There will be no Changes to Sweepstakes Multipliers for 2026."
"""
import json, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "docs/research/arrl_sections_2026.txt"
OUT = ROOT / "Resources/Data/arrl_sections.json"

lines = SRC.read_text().splitlines()
start = next(i for i, l in enumerate(lines) if l.startswith("Verbatim table")) + 1
end = next(i for i, l in enumerate(lines) if l.startswith("COUNT (Source A"))

tokens, group = [], None
for line in lines[start:end]:
    if not line.strip() or line.startswith("="):
        continue
    if not line.startswith("  "):
        group = line.strip()
        continue
    m = re.match(r"^\s+(.+?)\s{2,}([A-Z]{2,3})$", line)
    assert m, f"unparsed row: {line!r}"
    tokens.append({"abbr": m.group(2), "name": m.group(1), "group": group})

assert len(tokens) == 85, len(tokens)
assert len({t["abbr"] for t in tokens}) == 85
by_group = {}
for t in tokens:
    by_group[t["group"]] = by_group.get(t["group"], 0) + 1
assert by_group == {
    "U.S. Call Area 0": 8, "U.S. Call Area 1": 7, "U.S. Call Area 2": 6,
    "U.S. Call Area 3": 4, "U.S. Call Area 4": 12, "U.S. Call Area 5": 8,
    "U.S. Call Area 6": 10, "U.S. Call Area 7": 10, "U.S. Call Area 8": 3,
    "U.S. Call Area 9": 3, "Canada": 14,
}, by_group
assert {"NTX", "STX", "WTX", "TER", "PAC", "GH", "MDC"} <= {t["abbr"] for t in tokens}

OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps({
    "id": "sections",
    "term": "section",
    "termPlural": "sections",
    "source": "https://contests.arrl.org/contestmultipliers.php?a=wve (Version 1.2.0, Revised May 12, 2023), fetched 2026-08-17; see docs/research/arrl_sections_2026.txt",
    "tokens": tokens,
    "aliases": {},
}, indent=1) + "\n")
print(f"wrote {OUT} with {len(tokens)} sections")
```

Run: `python3 docs/research/gen_sections.py` — Expected: `wrote .../Resources/Data/arrl_sections.json with 85 sections`.

- [ ] **Step 4: Bundle the folder and add the loader**

`project.yml`, inside the app target's `sources:` after the `Resources/DXCC` entry:

```yaml
      - path: Resources/Data
        type: folder
        buildPhase: resources
```

`TokenSet.swift`, add inside the `// MARK: Built-ins` section:

```swift
    /// The 85 ARRL/RAC sections, from `Resources/Data/arrl_sections.json`
    /// (generated by `docs/research/gen_sections.py`). Nil only if the
    /// resource is missing from the bundle.
    static func sections(bundle: Bundle = .main) -> TokenSet? {
        guard let url = bundle.url(forResource: "arrl_sections", withExtension: "json", subdirectory: "Data"),
              let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }
```

(The JSON's extra `source` key is ignored by the decoder.)

- [ ] **Step 5: Regenerate, run** — `xcodegen generate`, then the one-class command with `ArrlSectionsTests`. Expected: `Executed 1 test, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add docs/research/gen_sections.py Resources/Data/arrl_sections.json project.yml QSOPartyLogger.xcodeproj Sources/Core/Contests/TokenSet.swift Tests/Core/ArrlSectionsTests.swift && git commit -m "data: the 85 ARRL/RAC sections as a bundled token set, generated from the sponsor's list (fetched 2026-08-17)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `Side` and `SidePredicate`

**Files:**
- Create: `Sources/Core/Contests/Side.swift`
- Test: `Tests/Core/SideTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class SideTests: XCTestCase {
    func testDecodesEveryPredicateKind() throws {
        let json = """
        [{"id":"inside","label":"Inside Kansas",
          "predicate":{"kind":"tokenIn","element":"location","set":"counties"},
          "workedPredicate":{"kind":"tokenIn","element":"location","set":"counties"}},
         {"id":"wve","label":"W/VE station",
          "predicate":{"kind":"dxccIn","codes":[291,1]},
          "workedPredicate":{"kind":"dxccIn","codes":[291,1]}},
         {"id":"na","label":"North America",
          "predicate":{"kind":"continentIn","continents":["NA"]},
          "workedPredicate":{"kind":"always"}}]
        """
        let sides = try JSONDecoder().decode([Side].self, from: Data(json.utf8))
        XCTAssertEqual(sides.map(\.id), ["inside", "wve", "na"])
        XCTAssertEqual(sides[0].predicate, SidePredicate(kind: .tokenIn, element: "location", set: "counties"))
        XCTAssertEqual(sides[1].predicate.codes, [291, 1])
        XCTAssertEqual(sides[2].predicate.continents, ["NA"])
        XCTAssertEqual(sides[2].workedPredicate, .always)
    }

    func testTokenInEvaluatesAgainstAnExchange() {
        let counties = TokenSet(id: "counties", term: "county", termPlural: "counties",
                                tokens: [.init(abbr: "LIN"), .init(abbr: "AND")])
        let p = SidePredicate(kind: .tokenIn, element: "location", set: "counties")
        let ctx = SidePredicate.Context(exchange: ["location": ["LIN"]], entityCode: 291, continent: "NA",
                                        sets: { $0 == "counties" ? counties : nil })
        XCTAssertTrue(p.matches(ctx))
        XCTAssertFalse(p.matches(.init(exchange: ["location": ["TX"]], entityCode: 291, continent: "NA",
                                        sets: { $0 == "counties" ? counties : nil })))
    }

    func testDXCCAndContinentEvaluate() {
        let sets: (String) -> TokenSet? = { _ in nil }
        XCTAssertTrue(SidePredicate(kind: .dxccIn, codes: [291, 1])
            .matches(.init(exchange: [:], entityCode: 1, continent: "NA", sets: sets)))
        XCTAssertFalse(SidePredicate(kind: .dxccIn, codes: [291, 1])
            .matches(.init(exchange: [:], entityCode: 110, continent: "OC", sets: sets)))
        XCTAssertTrue(SidePredicate(kind: .continentIn, continents: ["NA"])
            .matches(.init(exchange: [:], entityCode: nil, continent: "NA", sets: sets)))
        XCTAssertTrue(SidePredicate.always.matches(.init(exchange: [:], entityCode: nil, continent: nil, sets: sets)))
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'Side' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Which side of a contest a station is on — inside/outside a party's state,
/// W/VE versus DX in ARRL DX, "everyone" in CQ WW. `predicate` classifies the
/// entrant (from the sent exchange and the entrant's callsign); `workedPredicate`
/// classifies the worked station (from the received exchange and its callsign).
/// Sides are evaluated in declaration order; the first match wins, so a
/// party's `outside` side is simply `always` after `inside`.
struct Side: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let label: String
    let predicate: SidePredicate
    let workedPredicate: SidePredicate
}

/// A flat, data-driven predicate. Only the fields its `kind` reads are
/// meaningful; `ContestDefinition.validate()` rejects a predicate whose kind
/// lacks its field.
struct SidePredicate: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case always
        /// The exchange's `element` holds a token in `set` (any value, for a
        /// county-line entrant sitting on several).
        case tokenIn
        /// The station's DXCC entity code is one of `codes`.
        case dxccIn
        /// The station's continent is one of `continents`.
        case continentIn
    }

    let kind: Kind
    let element: String?
    let set: String?
    let codes: [Int]?
    let continents: [String]?

    init(kind: Kind, element: String? = nil, set: String? = nil, codes: [Int]? = nil, continents: [String]? = nil) {
        self.kind = kind
        self.element = element
        self.set = set
        self.codes = codes
        self.continents = continents
    }

    static let always = SidePredicate(kind: .always)

    /// What a predicate is evaluated against: an exchange (sent or received,
    /// element id → values), the station's entity and continent from
    /// `CTYTable`, and a way to find token sets by id.
    struct Context {
        let exchange: [String: [String]]
        let entityCode: Int?
        let continent: String?
        let sets: (String) -> TokenSet?
    }

    func matches(_ ctx: Context) -> Bool {
        switch kind {
        case .always:
            return true
        case .tokenIn:
            guard let element, let set, let tokens = ctx.sets(set) else { return false }
            return (ctx.exchange[element] ?? []).contains { tokens.accepts($0) }
        case .dxccIn:
            guard let code = ctx.entityCode else { return false }
            return (codes ?? []).contains(code)
        case .continentIn:
            guard let continent = ctx.continent else { return false }
            return (continents ?? []).contains(continent)
        }
    }
}
```

- [ ] **Step 4: Run to verify pass** — one-class `SideTests`. Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/Side.swift Tests/Core/SideTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: Side and SidePredicate — who the entrant and the worked station are

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: `ExchangeElement`

**Files:**
- Create: `Sources/Core/Contests/ExchangeElement.swift`
- Test: `Tests/Core/ExchangeElementTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class ExchangeElementTests: XCTestCase {
    func testDefaultsByKind() {
        let rst = ExchangeElement(id: "rst", kind: .rst, sentBy: ["all": .init()])
        XCTAssertEqual(rst.label, "RST")
        XCTAssertEqual(rst.cabrilloWidth, 3)
        XCTAssertFalse(rst.fixed)
        XCTAssertTrue(rst.required)
        let zone = ExchangeElement(id: "zone", kind: .cqZone, sentBy: ["all": .init()], fixed: true)
        XCTAssertEqual(zone.cabrilloWidth, 6)
        XCTAssertEqual(zone.label, "Zone")
        XCTAssertEqual(ExchangeElement(id: "precedence", kind: .precedence, sentBy: [:], letters: ["Q","A","B","U","M","S"]).cabrilloWidth, 1)
        XCTAssertEqual(ExchangeElement(id: "check", kind: .check, sentBy: [:]).cabrilloWidth, 2)
    }

    func testDecodesTheSpecShape() throws {
        let json = """
        {"id":"location","kind":"token","label":"County/State",
         "sentBy":{"inside":{"sets":["counties"],"multi":{"max":2}},
                   "outside":{"sets":["states","provinces","dxToken"]}},
         "fixed":true,"cabrilloWidth":6,"prefill":["callHistory","spot"]}
        """
        let e = try JSONDecoder().decode(ExchangeElement.self, from: Data(json.utf8))
        XCTAssertEqual(e.kind, .token)
        XCTAssertEqual(e.sentBy["inside"]?.sets, ["counties"])
        XCTAssertEqual(e.sentBy["inside"]?.multi?.max, 2)
        XCTAssertNil(e.sentBy["outside"]?.multi)
        XCTAssertEqual(e.prefill, [.callHistory, .spot])
        XCTAssertEqual(e.setsSent(by: ["inside", "outside"]), ["counties", "states", "provinces", "dxToken"])
        XCTAssertTrue(e.fixed)
    }

    func testDerivationTableFirstMatchWins() throws {
        let json = """
        {"id":"precedence","kind":"precedence","letters":["Q","A","B","U","M","S"],"sentBy":{"wve":{}},"fixed":true,
         "derived":{"kind":"categoryTable","table":[
           {"when":{"operator":"SINGLE-OP","assisted":"NON-ASSISTED","power":"QRP"},"value":"Q"},
           {"when":{"operator":"SINGLE-OP","assisted":"NON-ASSISTED","power":"LOW"},"value":"A"},
           {"when":{"operator":"SINGLE-OP","assisted":"NON-ASSISTED","power":"HIGH"},"value":"B"},
           {"when":{"operator":"SINGLE-OP","assisted":"ASSISTED"},"value":"U"},
           {"when":{"operator":"MULTI-OP","station":"SCHOOL"},"value":"S"},
           {"when":{"operator":"MULTI-OP"},"value":"M"}]}}
        """
        let e = try JSONDecoder().decode(ExchangeElement.self, from: Data(json.utf8))
        let d = try XCTUnwrap(e.derived)
        XCTAssertEqual(d.value(for: ["operator": "SINGLE-OP", "assisted": "NON-ASSISTED", "power": "LOW"]), "A")
        XCTAssertEqual(d.value(for: ["operator": "SINGLE-OP", "assisted": "ASSISTED", "power": "QRP"]), "U")
        XCTAssertEqual(d.value(for: ["operator": "MULTI-OP", "station": "SCHOOL"]), "S")
        XCTAssertEqual(d.value(for: ["operator": "MULTI-OP", "station": "FIXED"]), "M")
        XCTAssertNil(d.value(for: ["operator": "CHECKLOG"]))
    }

    func testMemberSpecRoundTrips() throws {
        let m = MemberSpec(term: "Skeeter number", shortTerm: "Skeeter #", memberPlural: "Skeeters",
                           qrpMaxWatts: .init(phone: 10, cw: 5, digital: 5))
        let e = ExchangeElement(id: "member", kind: .memberOrPower, sentBy: ["all": .init()], fixed: true, member: m)
        let back = try JSONDecoder().decode(ExchangeElement.self, from: JSONEncoder().encode(e))
        XCTAssertEqual(back, e)
        XCTAssertEqual(back.member?.qrpMaxWatts.limit(for: .phone), 10)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'ExchangeElement' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// One piece of a contest exchange, in send order. `sentBy` names every side
/// that sends it and, for `token` kinds, what that side sends; the received
/// fields a side sees are the elements sent by the sides it may work, and a
/// token field accepts the union of those sides' sets.
struct ExchangeElement: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case rst, serial, name, token, cqZone, ituZone, precedence, check
        case classToken, power, memberOrPower, callEcho, grid, report

        var defaultLabel: String {
            switch self {
            case .rst: "RST"
            case .serial: "Nr"
            case .name: "Name"
            case .token: "Exchange"
            case .cqZone: "Zone"
            case .ituZone: "ITU zone"
            case .precedence: "Prec"
            case .check: "Check"
            case .classToken: "Class"
            case .power: "Power"
            case .memberOrPower: "Member #"
            case .callEcho: "Call"
            case .grid: "Grid"
            case .report: "Report"
            }
        }

        /// The generic Cabrillo template's widths: `rst nnn`, `exch ******`;
        /// Sweepstakes' `p` and `ck` are 1 and 2; a call echo has no column.
        var defaultCabrilloWidth: Int {
            switch self {
            case .rst: 3
            case .precedence: 1
            case .check: 2
            case .callEcho: 0
            default: 6
            }
        }
    }

    struct SentSpec: Codable, Equatable, Sendable {
        struct Multi: Codable, Equatable, Sendable { let max: Int }
        /// Token-set ids this side sends (token kinds only).
        let sets: [String]?
        /// Several values at once — a county-line entrant (token kinds only).
        let multi: Multi?
        init(sets: [String]? = nil, multi: Multi? = nil) {
            self.sets = sets
            self.multi = multi
        }
    }

    enum PrefillSource: String, Codable, Sendable { case cty, callHistory, stationMemory, spot }

    /// A sent value computed from the entrant's category (Sweepstakes'
    /// precedence). Rows are tried in order; every key in `when` must equal
    /// the category axis's value.
    struct Derivation: Codable, Equatable, Sendable {
        struct Row: Codable, Equatable, Sendable {
            let when: [String: String]
            let value: String
        }
        let kind: String
        let table: [Row]

        func value(for category: [String: String]) -> String? {
            table.first { row in row.when.allSatisfy { category[$0.key] == $0.value } }?.value
        }
    }

    let id: String
    let kind: Kind
    let label: String
    let shortLabel: String?
    let sentBy: [String: SentSpec]
    /// Set once in Setup and stamped per row; false for a per-QSO value (serial).
    let fixed: Bool
    /// Must be filled before a QSO can be logged.
    let required: Bool
    let cabrilloWidth: Int
    let prefill: [PrefillSource]
    let derived: Derivation?
    /// `precedence` / `classToken`: the accepted letters.
    let letters: [String]?
    /// `classToken`: the smallest transmitter count (Field Day: 1).
    let minNumber: Int?
    /// `memberOrPower`: labels and the QRP ceilings.
    let member: MemberSpec?

    init(id: String, kind: Kind, label: String? = nil, shortLabel: String? = nil,
         sentBy: [String: SentSpec], fixed: Bool = false, required: Bool = true,
         cabrilloWidth: Int? = nil, prefill: [PrefillSource] = [], derived: Derivation? = nil,
         letters: [String]? = nil, minNumber: Int? = nil, member: MemberSpec? = nil) {
        self.id = id
        self.kind = kind
        self.label = label ?? kind.defaultLabel
        self.shortLabel = shortLabel
        self.sentBy = sentBy
        self.fixed = fixed
        self.required = required
        self.cabrilloWidth = cabrilloWidth ?? kind.defaultCabrilloWidth
        self.prefill = prefill
        self.derived = derived
        self.letters = letters
        self.minNumber = minNumber
        self.member = member
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, shortLabel, sentBy, fixed, required, cabrilloWidth, prefill, derived, letters, minNumber, member
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            kind: try c.decode(Kind.self, forKey: .kind),
            label: try c.decodeIfPresent(String.self, forKey: .label),
            shortLabel: try c.decodeIfPresent(String.self, forKey: .shortLabel),
            sentBy: try c.decodeIfPresent([String: SentSpec].self, forKey: .sentBy) ?? [:],
            fixed: try c.decodeIfPresent(Bool.self, forKey: .fixed) ?? false,
            required: try c.decodeIfPresent(Bool.self, forKey: .required) ?? true,
            cabrilloWidth: try c.decodeIfPresent(Int.self, forKey: .cabrilloWidth),
            prefill: try c.decodeIfPresent([PrefillSource].self, forKey: .prefill) ?? [],
            derived: try c.decodeIfPresent(Derivation.self, forKey: .derived),
            letters: try c.decodeIfPresent([String].self, forKey: .letters),
            minNumber: try c.decodeIfPresent(Int.self, forKey: .minNumber),
            member: try c.decodeIfPresent(MemberSpec.self, forKey: .member)
        )
    }

    /// The token-set ids the given sides send, in declaration order, deduplicated.
    func setsSent(by sides: [String]) -> [String] {
        var seen = Set<String>(), out: [String] = []
        for side in sides {
            for set in sentBy[side]?.sets ?? [] where seen.insert(set).inserted { out.append(set) }
        }
        return out
    }

    /// The largest `multi.max` among the given sides — 1 when none allows several.
    func maxValues(for sides: [String]) -> Int {
        sides.compactMap { sentBy[$0]?.multi?.max }.max() ?? 1
    }
}

/// The member-number-or-power element's labels and QRP ceilings — the
/// display half of today's `MemberExchange`; its points live in `PointRule`s.
struct MemberSpec: Codable, Equatable, Sendable {
    let term: String
    let shortTerm: String
    let memberPlural: String
    let qrpMaxWatts: MemberExchange.QRPMaxWatts
}
```

- [ ] **Step 4: Run to verify pass** — one-class `ExchangeElementTests`. Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/ExchangeElement.swift Tests/Core/ExchangeElementTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: ExchangeElement — typed exchange elements with per-side sent specs, prefill, derivation and member labels

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: `MultiplierClass` and `Resolver`

**Files:**
- Create: `Sources/Core/Contests/MultiplierClass.swift`
- Test: `Tests/Core/MultiplierClassTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class MultiplierClassTests: XCTestCase {
    func testDecodesTheCQWWClasses() throws {
        let json = """
        [{"id":"zone","term":"zone","resolvers":[{"kind":"cqZone","from":"received"}],
          "counting":{"all":"perBand"},"roster":"cqZones","layout":"zoneGrid"},
         {"id":"country","term":"country","termPlural":"countries",
          "resolvers":[{"kind":"dxccEntity","from":"callsign","list":"arrlPlusWAE","unlessSuffix":["MM"]}],
          "counting":{"all":"perBand"},"layout":"workedOnly"}]
        """
        let classes = try JSONDecoder().decode([MultiplierClass].self, from: Data(json.utf8))
        XCTAssertEqual(classes[0].termPlural, "zones")               // default: term + "s"
        XCTAssertEqual(classes[0].counting["all"], .perBand)
        XCTAssertEqual(classes[0].resolvers[0].kind, .cqZone)
        XCTAssertEqual(classes[1].resolvers[0].list, .arrlPlusWAE)
        XCTAssertEqual(classes[1].resolvers[0].unlessSuffix, ["MM"])
        XCTAssertTrue(classes[1].resolvers[0].countEntities)          // default true
        XCTAssertEqual(classes[1].layout, .workedOnly)
        XCTAssertNil(classes[1].caps)
    }

    func testResolverAppliesToSideAndSuffix() {
        let r = Resolver(kind: .receivedToken, element: "location", set: "counties", mapTo: "group", sides: ["inside"])
        XCTAssertTrue(r.applies(side: "inside", call: "K5ABC"))
        XCTAssertFalse(r.applies(side: "outside", call: "K5ABC"))
        let mm = Resolver(kind: .dxccEntity, from: .callsign, unlessSuffix: ["MM", "AM"])
        XCTAssertTrue(mm.applies(side: "all", call: "PA0AAA"))
        XCTAssertFalse(mm.applies(side: "all", call: "PA0AAA/MM"))
        XCTAssertFalse(mm.applies(side: "all", call: "K5ABC/am"))
    }

    func testCountsForSide() {
        let c = MultiplierClass(id: "county", term: "county", termPlural: "counties",
                                resolvers: [Resolver(kind: .receivedToken, element: "location", set: "counties")],
                                counting: ["outside": .perBand], roster: "counties", layout: .groupedTokens)
        XCTAssertEqual(c.scope(for: "outside"), .perBand)
        XCTAssertNil(c.scope(for: "inside"))
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'MultiplierClass' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The counting scope of a multiplier — `PartyDefinition.CountScope`, whose
/// `component(band:modeClass:)` the engine and the sidebar already share.
typealias CountScope = PartyDefinition.CountScope

/// One class of multiplier a contest counts, how its value is found for a row,
/// and how often each side counts it. Well-known ids keep today's `MultClass`
/// raw values (`county state province dx section member`) so persisted
/// snapshots and sidebar preferences read unchanged; new ids are `zone`,
/// `ituZone`, `country`, `prefix`, `grid`.
struct MultiplierClass: Codable, Equatable, Sendable, Identifiable {
    enum Layout: String, Codable, Sendable { case tokens, groupedTokens, zoneGrid, workedOnly }

    let id: String
    let term: String
    let termPlural: String
    /// Tried in order; the first that yields a value wins.
    let resolvers: [Resolver]
    /// Side id → scope. A side absent here does not count the class.
    let counting: [String: CountScope]
    /// Side id → the most distinct values that count (WA in-state: 10 DX).
    let caps: [String: Int]?
    /// The token set the sidebar lists in full (nil = worked-only).
    let roster: String?
    let layout: Layout

    init(id: String, term: String, termPlural: String? = nil, resolvers: [Resolver],
         counting: [String: CountScope], caps: [String: Int]? = nil, roster: String? = nil,
         layout: Layout = .tokens) {
        self.id = id
        self.term = term
        self.termPlural = termPlural ?? term + "s"
        self.resolvers = resolvers
        self.counting = counting
        self.caps = caps
        self.roster = roster
        self.layout = layout
    }

    private enum CodingKeys: String, CodingKey { case id, term, termPlural, resolvers, counting, caps, roster, layout }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            term: try c.decode(String.self, forKey: .term),
            termPlural: try c.decodeIfPresent(String.self, forKey: .termPlural),
            resolvers: try c.decode([Resolver].self, forKey: .resolvers),
            counting: try c.decode([String: CountScope].self, forKey: .counting),
            caps: try c.decodeIfPresent([String: Int].self, forKey: .caps),
            roster: try c.decodeIfPresent(String.self, forKey: .roster),
            layout: try c.decodeIfPresent(Layout.self, forKey: .layout) ?? .tokens
        )
    }

    func scope(for side: String) -> CountScope? { counting[side] }
    func cap(for side: String) -> Int? { caps?[side] }
}

/// How a multiplier value is found for one logged row. Flat and data-driven:
/// only the fields the `kind` reads are meaningful.
struct Resolver: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// The received `element` holds a token of `set`; value = the token,
        /// or its `mapTo` (`"group"` = the token's group — a county's state).
        case receivedToken
        /// The DXCC entity of the worked station (`from`), against `list`.
        case dxccEntity
        case cqZone, ituZone
        /// `WPXPrefix.of(call)`.
        case wpxPrefix
        /// The received `element` holds a Maidenhead grid; value = its first `precision` characters.
        case grid
        /// The worked call itself, when the received member element parses as a member number.
        case workedStation
    }
    enum From: String, Codable, Sendable { case callsign, receivedToken, receivedTokenOrCallsign, received }
    enum EntityList: String, Codable, Sendable { case arrl, arrlPlusWAE }

    let kind: Kind
    let element: String?
    let set: String?
    let mapTo: String?
    let from: From?
    let list: EntityList?
    let exclude: [Int]
    /// `dxccEntity`: count each entity separately (false = one literal `DX`).
    let countEntities: Bool
    let precision: Int?
    /// Sides this resolver serves; nil = every side.
    let sides: [String]?
    /// Callsign suffixes for which the resolver yields nothing (CQ WW: `/MM`
    /// counts only for a zone).
    let unlessSuffix: [String]?

    init(kind: Kind, element: String? = nil, set: String? = nil, mapTo: String? = nil,
         from: From? = nil, list: EntityList? = nil, exclude: [Int] = [], countEntities: Bool = true,
         precision: Int? = nil, sides: [String]? = nil, unlessSuffix: [String]? = nil) {
        self.kind = kind
        self.element = element
        self.set = set
        self.mapTo = mapTo
        self.from = from
        self.list = list
        self.exclude = exclude
        self.countEntities = countEntities
        self.precision = precision
        self.sides = sides
        self.unlessSuffix = unlessSuffix
    }

    private enum CodingKeys: String, CodingKey {
        case kind, element, set, mapTo, from, list, exclude, countEntities, precision, sides, unlessSuffix
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kind: try c.decode(Kind.self, forKey: .kind),
            element: try c.decodeIfPresent(String.self, forKey: .element),
            set: try c.decodeIfPresent(String.self, forKey: .set),
            mapTo: try c.decodeIfPresent(String.self, forKey: .mapTo),
            from: try c.decodeIfPresent(From.self, forKey: .from),
            list: try c.decodeIfPresent(EntityList.self, forKey: .list),
            exclude: try c.decodeIfPresent([Int].self, forKey: .exclude) ?? [],
            countEntities: try c.decodeIfPresent(Bool.self, forKey: .countEntities) ?? true,
            precision: try c.decodeIfPresent(Int.self, forKey: .precision),
            sides: try c.decodeIfPresent([String].self, forKey: .sides),
            unlessSuffix: try c.decodeIfPresent([String].self, forKey: .unlessSuffix)
        )
    }

    /// Whether this resolver is consulted for a row: the entrant's side is
    /// served, and the worked call carries none of the excluded suffixes.
    func applies(side: String, call: String) -> Bool {
        if let sides, !sides.contains(side) { return false }
        if let unlessSuffix {
            let upper = call.uppercased()
            for suffix in unlessSuffix where upper.hasSuffix("/" + suffix.uppercased()) { return false }
        }
        return true
    }
}
```

- [ ] **Step 4: Run to verify pass** — one-class `MultiplierClassTests`. Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/MultiplierClass.swift Tests/Core/MultiplierClassTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: MultiplierClass and Resolver — data-driven multiplier classes with per-side scopes and caps

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: `PointRule`

**Files:**
- Create: `Sources/Core/Contests/PointRule.swift`
- Test: `Tests/Core/PointRuleTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class PointRuleTests: XCTestCase {
    private func ctx(mode: ModeClass = .cw, band: Band = .m20, relation: PointCondition.Relation? = .differentContinent,
                     bothIn: String? = nil, side: String = "all", worked: String = "all",
                     rcvd: [String: String] = [:], kind: String? = nil, call: String = "DL1AA") -> PointCondition.Context {
        .init(modeClass: mode, band: band, relation: relation, sharedContinent: bothIn, side: side, workedSide: worked,
              received: rcvd, workedStationKind: kind, call: call, sets: { _ in nil })
    }

    func testCQWWTableFirstMatchWins() throws {
        let json = """
        [{"when":[{"relation":"sameEntity"}],"points":0},
         {"when":[{"bothInContinent":"NA"}],"points":2},
         {"when":[{"relation":"sameContinent"}],"points":1},
         {"points":3}]
        """
        let rules = try JSONDecoder().decode([PointRule].self, from: Data(json.utf8))
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .sameEntity, bothIn: "NA")), 0)
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .sameContinent, bothIn: "NA")), 2)
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .sameContinent, bothIn: "EU")), 1)
        XCTAssertEqual(PointRule.points(rules, ctx(relation: .differentContinent)), 3)
    }

    func testWPXBandGroups() throws {
        let json = """
        [{"when":[{"relation":"sameEntity"}],"points":1},
         {"when":[{"bothInContinent":"NA","band":["160m","80m","40m"]}],"points":4},
         {"when":[{"bothInContinent":"NA"}],"points":2},
         {"when":[{"relation":"sameContinent","band":["160m","80m","40m"]}],"points":2},
         {"when":[{"relation":"sameContinent"}],"points":1},
         {"when":[{"band":["160m","80m","40m"]}],"points":6},
         {"points":3}]
        """
        let rules = try JSONDecoder().decode([PointRule].self, from: Data(json.utf8))
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m40, relation: .sameContinent, bothIn: "NA")), 4)
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m10, relation: .differentContinent)), 3)
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m80, relation: .differentContinent)), 6)
        XCTAssertEqual(PointRule.points(rules, ctx(band: .m80, relation: .sameEntity)), 1)
    }

    func testModeAndReceivedTokenAndKindAndCall() throws {
        let counties = TokenSet(id: "counties", term: "county", termPlural: "counties", tokens: [.init(abbr: "LIN")])
        let sets: (String) -> TokenSet? = { $0 == "counties" ? counties : nil }
        let rules = [
            PointRule(when: [PointCondition(modeClass: [.cw], receivedTokenIn: .init(element: "location", set: "counties"))], points: 3),
            PointRule(when: [PointCondition(workedStationKind: ["member"])], points: 5),
            PointRule(when: [PointCondition(callsign: ["VE3XYZ"])], points: 10),
            PointRule(when: [PointCondition(modeClass: [.phone])], points: 1),
            PointRule(when: [], points: 2),
        ]
        let c = PointCondition.Context(modeClass: .cw, band: .m20, relation: nil, sharedContinent: nil, side: "inside", workedSide: "inside",
                                       received: ["location": "LIN"], workedStationKind: nil, call: "K5ABC", sets: sets)
        XCTAssertEqual(PointRule.points(rules, c), 3)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .cw, kind: "member")), 5)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .cw, call: "ve3xyz")), 10)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .phone)), 1)
        XCTAssertEqual(PointRule.points(rules, ctx(mode: .digital)), 2)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'PointRule' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// QSO points, as an ordered list of rules; the first whose conditions all
/// hold pays. The last rule of a contest carries no conditions.
struct PointRule: Codable, Equatable, Sendable {
    let when: [PointCondition]
    let points: Int

    init(when: [PointCondition] = [], points: Int) {
        self.when = when
        self.points = points
    }

    private enum CodingKeys: String, CodingKey { case when, points }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(when: try c.decodeIfPresent([PointCondition].self, forKey: .when) ?? [],
                  points: try c.decode(Int.self, forKey: .points))
    }

    func matches(_ ctx: PointCondition.Context) -> Bool { when.allSatisfy { $0.matches(ctx) } }

    /// The points the first matching rule pays; 0 when none matches (a
    /// validated contest always ends with an unconditional rule).
    static func points(_ rules: [PointRule], _ ctx: PointCondition.Context) -> Int {
        rules.first { $0.matches(ctx) }?.points ?? 0
    }
}

/// A conjunction of constraints; every present field must hold.
struct PointCondition: Codable, Equatable, Sendable {
    enum Relation: String, Codable, Sendable { case sameEntity, sameContinent, differentContinent }
    struct TokenMatch: Codable, Equatable, Sendable {
        let element: String
        let set: String
    }

    let modeClass: [ModeClass]?
    let band: [Band]?
    let relation: Relation?
    /// Both stations are on this continent (CQ WW / WPX North America).
    let bothInContinent: String?
    let side: [String]?
    let workedSide: [String]?
    let receivedTokenIn: TokenMatch?
    /// `member` / `qrp` / `other` (the member-exchange sprints).
    let workedStationKind: [String]?
    let callsign: [String]?

    init(modeClass: [ModeClass]? = nil, band: [Band]? = nil, relation: Relation? = nil,
         bothInContinent: String? = nil, side: [String]? = nil, workedSide: [String]? = nil,
         receivedTokenIn: TokenMatch? = nil, workedStationKind: [String]? = nil, callsign: [String]? = nil) {
        self.modeClass = modeClass
        self.band = band
        self.relation = relation
        self.bothInContinent = bothInContinent
        self.side = side
        self.workedSide = workedSide
        self.receivedTokenIn = receivedTokenIn
        self.workedStationKind = workedStationKind
        self.callsign = callsign?.map { $0.uppercased() }
    }

    /// Everything a condition can read about one row.
    struct Context {
        let modeClass: ModeClass
        let band: Band
        let relation: Relation?
        /// The continent both stations share, or nil.
        let sharedContinent: String?
        let side: String
        let workedSide: String
        /// Received exchange, element id → value.
        let received: [String: String]
        let workedStationKind: String?
        let call: String
        let sets: (String) -> TokenSet?
    }

    func matches(_ ctx: Context) -> Bool {
        if let modeClass, !modeClass.contains(ctx.modeClass) { return false }
        if let band, !band.contains(ctx.band) { return false }
        if let relation, ctx.relation != relation { return false }
        if let bothInContinent, ctx.sharedContinent != bothInContinent { return false }
        if let side, !side.contains(ctx.side) { return false }
        if let workedSide, !workedSide.contains(ctx.workedSide) { return false }
        if let receivedTokenIn {
            guard let value = ctx.received[receivedTokenIn.element],
                  let set = ctx.sets(receivedTokenIn.set), set.accepts(value) else { return false }
        }
        if let workedStationKind {
            guard let kind = ctx.workedStationKind, workedStationKind.contains(kind) else { return false }
        }
        if let callsign, !callsign.contains(ctx.call.uppercased()) { return false }
        return true
    }
}
```

- [ ] **Step 4: Run to verify pass** — one-class `PointRuleTests`. Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/PointRule.swift Tests/Core/PointRuleTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: PointRule and PointCondition — first-match QSO points by mode, band, relation, side, token, station kind, callsign

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: The remaining rule types (`ContestRules.swift`)

**Files:**
- Create: `Sources/Core/Contests/ContestRules.swift`
- Test: `Tests/Core/ContestRulesTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class ContestRulesTests: XCTestCase {
    func testDupeRuleDefaultsAndDecoding() throws {
        XCTAssertEqual(DupeRule.partyDefault, DupeRule(scope: .bandMode, locationSensitive: true))
        let r = try JSONDecoder().decode(DupeRule.self, from: Data(#"{"scope":"band"}"#.utf8))
        XCTAssertEqual(r, DupeRule(scope: .band, locationSensitive: false))
    }

    func testOperatingTimeAppliesToCategory() throws {
        let rule = try JSONDecoder().decode(OperatingTimeRule.self, from: Data(
            #"{"maxMinutes":1440,"minOffMinutes":60,"appliesTo":{"overlay":"CLASSIC"}}"#.utf8))
        XCTAssertTrue(rule.applies(to: ["overlay": "CLASSIC", "operator": "SINGLE-OP"]))
        XCTAssertFalse(rule.applies(to: ["operator": "SINGLE-OP"]))
        XCTAssertTrue(OperatingTimeRule(maxMinutes: 1440, minOffMinutes: 30).applies(to: [:]))
    }

    func testCategoriesFallBackToTheFullEnums() throws {
        let c = try JSONDecoder().decode(Categories.self, from: Data(#"{"power":["HIGH","LOW"],"overlay":["CLASSIC"]}"#.utf8))
        XCTAssertEqual(c.power, ["HIGH", "LOW"])
        XCTAssertEqual(c.overlay, ["CLASSIC"])
        XCTAssertNil(c.operator)
        XCTAssertEqual(c.allowedOperators, StationProfile.CategoryOperator.allCases.map(\.rawValue))
        XCTAssertEqual(c.allowedPowers, ["HIGH", "LOW"])
        XCTAssertEqual(Categories.all.allowedOverlays, [])
    }

    func testCabrilloSpecDefaults() throws {
        let s = try JSONDecoder().decode(CabrilloSpec.self, from: Data(#"{"contest":"CQ-WW-CW","location":"state"}"#.utf8))
        XCTAssertEqual(s.contest, "CQ-WW-CW")
        XCTAssertEqual(s.location, .state)
        XCTAssertFalse(s.transmitterColumn)
        XCTAssertEqual(s.serialSequence, .contest)
        XCTAssertNil(s.categoryMode)
    }

    func testScoreFactorsAndSideRulesRoundTrip() throws {
        let f = ScoreFactors(power: ["QRP": ScoreFactor(2)], station: nil,
                             entryClasses: [.init(id: "X4", label: "Portable homebrew", factor: ScoreFactor(4))],
                             objectives: [.init(id: "away", label: "Operate away from home", om: 3)],
                             declaredBonuses: [.init(id: "media", label: "Media publicity", points: 100, perCount: nil),
                                               .init(id: "youth", label: "Youth", points: 20, perCount: .init(label: "participants", max: 5))])
        let back = try JSONDecoder().decode(ScoreFactors.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back, f)
        let s = SideRules(maxScoredMultipliers: 58, multiplierFloor: 1,
                          granted: [.init(classID: "section", value: "EPA")],
                          activated: .init(classID: "county", minCount: 10, countUnit: .qsos, countScope: .once,
                                           categories: [.mobile, .rover], notOtherwiseWorked: true))
        XCTAssertEqual(try JSONDecoder().decode(SideRules.self, from: JSONEncoder().encode(s)), s)
        XCTAssertEqual(SideRules.none.multiplierFloor, 0)
        XCTAssertNil(SideRules.none.activated)
    }

    func testFamilyRawValues() {
        XCTAssertEqual(ContestFamily.stateQSOParty.rawValue, "stateQSOParty")
        XCTAssertEqual(ContestFamily.allCases.count, 7)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'DupeRule' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

enum ContestFamily: String, Codable, CaseIterable, Sendable {
    case stateQSOParty, dx, domestic, fieldDay, sprint, qrp, vhf
}

/// When a second contact with the same station is a dupe.
struct DupeRule: Codable, Equatable, Sendable {
    enum Scope: String, Codable, Sendable { case contest, band, bandMode }
    let scope: Scope
    /// A station worked from (or in) a different location is a new contact —
    /// a mobile changing county. Every party; no DX contest.
    let locationSensitive: Bool

    init(scope: Scope, locationSensitive: Bool = false) {
        self.scope = scope
        self.locationSensitive = locationSensitive
    }

    private enum CodingKeys: String, CodingKey { case scope, locationSensitive }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(scope: try c.decode(Scope.self, forKey: .scope),
                  locationSensitive: try c.decodeIfPresent(Bool.self, forKey: .locationSensitive) ?? false)
    }

    /// Today's `DupeChecker` key: band × mode class + both locations.
    static let partyDefault = DupeRule(scope: .bandMode, locationSensitive: true)
}

/// A maximum-operating-time rule (SS 24 of 30 h; WPX single-op 36 of 48 h).
struct OperatingTimeRule: Codable, Equatable, Sendable {
    let maxMinutes: Int
    let minOffMinutes: Int
    /// Category axis → value the rule applies to; nil = every entrant.
    let appliesTo: [String: String]?

    init(maxMinutes: Int, minOffMinutes: Int, appliesTo: [String: String]? = nil) {
        self.maxMinutes = maxMinutes
        self.minOffMinutes = minOffMinutes
        self.appliesTo = appliesTo
    }

    func applies(to category: [String: String]) -> Bool {
        (appliesTo ?? [:]).allSatisfy { category[$0.key] == $0.value }
    }
}

/// The Cabrillo category values a contest admits per axis; nil = the full enum.
struct Categories: Codable, Equatable, Sendable {
    let `operator`: [String]?
    let assisted: [String]?
    let power: [String]?
    let band: [String]?
    let mode: [String]?
    let transmitter: [String]?
    let station: [String]?
    let overlay: [String]?
    let time: [String]?

    init(operator: [String]? = nil, assisted: [String]? = nil, power: [String]? = nil, band: [String]? = nil,
         mode: [String]? = nil, transmitter: [String]? = nil, station: [String]? = nil,
         overlay: [String]? = nil, time: [String]? = nil) {
        self.operator = `operator`
        self.assisted = assisted
        self.power = power
        self.band = band
        self.mode = mode
        self.transmitter = transmitter
        self.station = station
        self.overlay = overlay
        self.time = time
    }

    static let all = Categories()

    var allowedOperators: [String] { `operator` ?? StationProfile.CategoryOperator.allCases.map(\.rawValue) }
    var allowedAssisted: [String] { assisted ?? StationProfile.CategoryAssisted.allCases.map(\.rawValue) }
    var allowedPowers: [String] { power ?? StationProfile.CategoryPower.allCases.map(\.rawValue) }
    var allowedStations: [String] { station ?? StationProfile.CategoryStation.allCases.map(\.rawValue) }
    var allowedTransmitters: [String] { transmitter ?? StationProfile.CategoryTransmitter.allCases.map(\.rawValue) }
    /// Every band the WWROF header spec lists is not useful here; a contest
    /// that admits single-band entries lists them, others get `ALL`.
    var allowedBands: [String] { band ?? ["ALL"] }
    var allowedOverlays: [String] { overlay ?? [] }
    var allowedTimes: [String] { time ?? [] }
}

struct CabrilloSpec: Codable, Equatable, Sendable {
    enum Location: String, Codable, Sendable { case state, section, entrantToken }
    enum SerialSequence: String, Codable, Sendable { case contest, perBand }

    let contest: String
    let location: Location
    let transmitterColumn: Bool
    let serialSequence: SerialSequence
    /// Pins `CATEGORY-MODE:` (Field Day: MIXED); nil = derived from the rows.
    let categoryMode: String?

    init(contest: String, location: Location, transmitterColumn: Bool = false,
         serialSequence: SerialSequence = .contest, categoryMode: String? = nil) {
        self.contest = contest
        self.location = location
        self.transmitterColumn = transmitterColumn
        self.serialSequence = serialSequence
        self.categoryMode = categoryMode
    }

    private enum CodingKeys: String, CodingKey { case contest, location, transmitterColumn, serialSequence, categoryMode }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(contest: try c.decode(String.self, forKey: .contest),
                  location: try c.decode(Location.self, forKey: .location),
                  transmitterColumn: try c.decodeIfPresent(Bool.self, forKey: .transmitterColumn) ?? false,
                  serialSequence: try c.decodeIfPresent(SerialSequence.self, forKey: .serialSequence) ?? .contest,
                  categoryMode: try c.decodeIfPresent(String.self, forKey: .categoryMode))
    }
}

/// Final-score factors and self-declared items: `factor(points × mults) + bonuses`.
struct ScoreFactors: Codable, Equatable, Sendable {
    struct Objective: Codable, Equatable, Sendable {
        let id: String
        let label: String
        /// Winter Field Day: the factor is 1 + the sum of the selected `om`s.
        let om: Int
    }
    struct DeclaredBonus: Codable, Equatable, Sendable {
        struct PerCount: Codable, Equatable, Sendable {
            let label: String
            let max: Int
        }
        let id: String
        let label: String
        let points: Int
        /// Field Day's "100 per transmitter, up to 20": points × count ≤ max.
        let perCount: PerCount?
    }

    let power: [String: ScoreFactor]?
    let station: [String: ScoreFactor]?
    let entryClasses: [PartyDefinition.EntryClass]
    let objectives: [Objective]
    let declaredBonuses: [DeclaredBonus]

    init(power: [String: ScoreFactor]? = nil, station: [String: ScoreFactor]? = nil,
         entryClasses: [PartyDefinition.EntryClass] = [], objectives: [Objective] = [],
         declaredBonuses: [DeclaredBonus] = []) {
        self.power = power
        self.station = station
        self.entryClasses = entryClasses
        self.objectives = objectives
        self.declaredBonuses = declaredBonuses
    }

    private enum CodingKeys: String, CodingKey { case power, station, entryClasses, objectives, declaredBonuses }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(power: try c.decodeIfPresent([String: ScoreFactor].self, forKey: .power),
                  station: try c.decodeIfPresent([String: ScoreFactor].self, forKey: .station),
                  entryClasses: try c.decodeIfPresent([PartyDefinition.EntryClass].self, forKey: .entryClasses) ?? [],
                  objectives: try c.decodeIfPresent([Objective].self, forKey: .objectives) ?? [],
                  declaredBonuses: try c.decodeIfPresent([DeclaredBonus].self, forKey: .declaredBonuses) ?? [])
    }
}

/// A multiplier a side earns by operating from a token of `classID`'s roster
/// — today's `ActivatedCountyMultiplier`, generalised to any class.
struct ActivatedRule: Codable, Equatable, Sendable {
    let classID: String
    let minCount: Int
    let countUnit: PartyDefinition.ActivatedCountyMultiplier.CountUnit
    let countScope: CountScope
    let categories: [StationProfile.CategoryStation]
    let notOtherwiseWorked: Bool
}

/// Per-side multiplier arithmetic beyond the classes themselves.
struct SideRules: Codable, Equatable, Sendable {
    struct Granted: Codable, Equatable, Sendable {
        let classID: String
        let value: String
    }
    let maxScoredMultipliers: Int?
    let multiplierFloor: Int
    let granted: [Granted]
    let activated: ActivatedRule?

    init(maxScoredMultipliers: Int? = nil, multiplierFloor: Int = 0, granted: [Granted] = [], activated: ActivatedRule? = nil) {
        self.maxScoredMultipliers = maxScoredMultipliers
        self.multiplierFloor = multiplierFloor
        self.granted = granted
        self.activated = activated
    }

    private enum CodingKeys: String, CodingKey { case maxScoredMultipliers, multiplierFloor, granted, activated }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(maxScoredMultipliers: try c.decodeIfPresent(Int.self, forKey: .maxScoredMultipliers),
                  multiplierFloor: try c.decodeIfPresent(Int.self, forKey: .multiplierFloor) ?? 0,
                  granted: try c.decodeIfPresent([Granted].self, forKey: .granted) ?? [],
                  activated: try c.decodeIfPresent(ActivatedRule.self, forKey: .activated))
    }

    static let none = SideRules()
}

/// Feeds and features that ride with a contest.
struct ContestSources: Codable, Equatable, Sendable {
    let hubSpots: HubSpotSource?
    let callHistory: CallHistorySource?
    let oneByOne: PartyDefinition.OneByOneConfig?
    let combines: [String]

    init(hubSpots: HubSpotSource? = nil, callHistory: CallHistorySource? = nil,
         oneByOne: PartyDefinition.OneByOneConfig? = nil, combines: [String] = []) {
        self.hubSpots = hubSpots
        self.callHistory = callHistory
        self.oneByOne = oneByOne
        self.combines = combines
    }

    private enum CodingKeys: String, CodingKey { case hubSpots, callHistory, oneByOne, combines }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(hubSpots: try c.decodeIfPresent(HubSpotSource.self, forKey: .hubSpots),
                  callHistory: try c.decodeIfPresent(CallHistorySource.self, forKey: .callHistory),
                  oneByOne: try c.decodeIfPresent(PartyDefinition.OneByOneConfig.self, forKey: .oneByOne),
                  combines: try c.decodeIfPresent([String].self, forKey: .combines) ?? [])
    }

    static let none = ContestSources()
}
```

(`PartyDefinition.EntryClass`, `.ActivatedCountyMultiplier.CountUnit`, `.OneByOneConfig`, `HubSpotSource`, `CallHistorySource` and `ScoreFactor` already exist and are `Codable`.)

- [ ] **Step 4: Run to verify pass** — one-class `ContestRulesTests`. Expected: `Executed 6 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/ContestRules.swift Tests/Core/ContestRulesTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: dupe, operating-time, categories, Cabrillo, score-factor, side-rule and source types

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 11: `ContestDefinition` — the assembled model, `validate()`, and the CQ WW fixture

**Files:**
- Create: `Sources/Core/Contests/ContestDefinition.swift`, `Tests/Fixtures/Contests/cqwwcw.json`
- Test: `Tests/Core/ContestDefinitionTests.swift`

- [ ] **Step 1: Write the fixture** — `Tests/Fixtures/Contests/cqwwcw.json` (this is the spec's sketch; it becomes the real bundled file in the phase-3 CQ WW commit, after the research write-up):

```json
{
  "schemaVersion": 2, "id": "cqwwcw", "name": "CQ World Wide DX Contest, CW", "family": "dx",
  "cabrillo": { "contest": "CQ-WW-CW", "location": "state", "transmitterColumn": true },
  "schedule": [{ "start": "2026-11-28T00:00:00Z", "end": "2026-11-29T23:59:59Z" }],
  "bands": ["160m", "80m", "40m", "20m", "15m", "10m"], "modeClasses": ["cw"],
  "tokenSets": [],
  "sides": [{ "id": "all", "label": "Everyone", "predicate": { "kind": "always" }, "workedPredicate": { "kind": "always" } }],
  "exchange": [
    { "id": "rst", "kind": "rst", "sentBy": { "all": {} } },
    { "id": "zone", "kind": "cqZone", "label": "Zone", "sentBy": { "all": {} }, "fixed": true, "prefill": ["cty"], "cabrilloWidth": 6 }
  ],
  "multipliers": [
    { "id": "zone", "term": "zone", "resolvers": [{ "kind": "cqZone", "from": "received" }],
      "counting": { "all": "perBand" }, "roster": "cqZones", "layout": "zoneGrid" },
    { "id": "country", "term": "country", "termPlural": "countries",
      "resolvers": [{ "kind": "dxccEntity", "from": "callsign", "list": "arrlPlusWAE", "unlessSuffix": ["MM"] }],
      "counting": { "all": "perBand" }, "layout": "workedOnly" }
  ],
  "points": [
    { "when": [{ "relation": "sameEntity" }], "points": 0 },
    { "when": [{ "bothInContinent": "NA" }], "points": 2 },
    { "when": [{ "relation": "sameContinent" }], "points": 1 },
    { "points": 3 }
  ],
  "dupe": { "scope": "band" },
  "categories": { "operator": ["SINGLE-OP", "MULTI-OP", "CHECKLOG"], "assisted": ["NON-ASSISTED", "ASSISTED"],
                  "power": ["HIGH", "LOW", "QRP"], "band": ["ALL", "160M", "80M", "40M", "20M", "15M", "10M"],
                  "transmitter": ["ONE", "TWO", "UNLIMITED"], "overlay": ["CLASSIC", "ROOKIE", "YOUTH"],
                  "station": ["FIXED", "DISTRIBUTED"] },
  "operatingTime": { "maxMinutes": 1440, "minOffMinutes": 60, "appliesTo": { "overlay": "CLASSIC" } },
  "notes": "FIXTURE for tests — not a bundled contest. Shape from docs/superpowers/specs/2026-08-17-general-contest-logger-design.md §1.2; rules per docs/research/cqww_rules_2026.txt.",
  "caveats": []
}
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class ContestDefinitionTests: XCTestCase {
    private func fixture() throws -> ContestDefinition {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json", subdirectory: "Contests"))
        return try ContestDefinition.decode(try Data(contentsOf: url))
    }

    func testDecodesTheCQWWFixture() throws {
        let c = try fixture()
        XCTAssertEqual(c.id, "cqwwcw")
        XCTAssertEqual(c.family, .dx)
        XCTAssertEqual(c.sides.map(\.id), ["all"])
        XCTAssertEqual(c.exchange.map(\.id), ["rst", "zone"])
        XCTAssertEqual(c.multipliers.map(\.id), ["zone", "country"])
        XCTAssertEqual(c.points.count, 4)
        XCTAssertEqual(c.dupe, DupeRule(scope: .band))
        XCTAssertNil(c.pairing)
        XCTAssertEqual(c.sideRules["all"], nil)
        XCTAssertEqual(c.rules(for: "all"), .none)
        XCTAssertEqual(c.operatingTime?.maxMinutes, 1440)
        XCTAssertEqual(c.cabrillo.contest, "CQ-WW-CW")
        XCTAssertEqual(c.categories.allowedOverlays, ["CLASSIC", "ROOKIE", "YOUTH"])
        XCTAssertTrue(c.bonuses.isEmpty)
        XCTAssertEqual(c.scoreFactors, nil)
        XCTAssertEqual(c.schedule?.first?.start, ISO8601DateFormatter().date(from: "2026-11-28T00:00:00Z"))
    }

    func testTokenSetLookupPrefersTheContestsOwnThenBuiltIns() throws {
        let c = try fixture()
        XCTAssertEqual(c.tokenSet(id: "cqZones")?.tokens.count, 40)
        XCTAssertNil(c.tokenSet(id: "counties"))
        XCTAssertNotNil(c.tokenSet(id: "sections"))
    }

    func testReceivedElementsForASide() throws {
        let c = try fixture()
        XCTAssertEqual(c.receivedElements(for: "all").map(\.id), ["rst", "zone"])
        XCTAssertEqual(c.workableSides(for: "all"), ["all"])
    }

    func testValidateRejectsBrokenReferences() throws {
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json", subdirectory: "Contests")))) as! [String: Any]
        json["points"] = [["when": [["relation": "sameEntity"]], "points": 0]]     // no unconditional rule
        XCTAssertThrowsError(try ContestDefinition.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .pointsWithoutDefault)
        }
        json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json", subdirectory: "Contests")))) as! [String: Any]
        var mults = json["multipliers"] as! [[String: Any]]
        mults[0]["counting"] = ["nobody": "perBand"]
        json["multipliers"] = mults
        XCTAssertThrowsError(try ContestDefinition.decode(JSONSerialization.data(withJSONObject: json))) { error in
            XCTAssertEqual(error as? ContestValidationError, .unknownSide("nobody"))
        }
    }
}
```

- [ ] **Step 3: Run to verify failure** — build error `cannot find 'ContestDefinition' in scope`. (`Tests/Fixtures/**` is already a resource folder of the test target — see `project.yml`; new subfolders need `xcodegen generate`.)

- [ ] **Step 4: Implement**

```swift
import Foundation

/// A contest's complete rule set — the one type the engine, entry flow,
/// exporters and UI consume. Decoded from a v2 JSON file, or produced by
/// `PartyLowering.lower(_:)` from a `PartyDefinition`.
struct ContestDefinition: Codable, Identifiable, Equatable, Sendable {
    let schemaVersion: Int
    let id: String
    let name: String
    let family: ContestFamily
    let sponsor: String?
    let notes: String?
    let caveats: [PartyDefinition.Caveat]
    let schedule: [PartyDefinition.ScheduleWindow]?
    let bands: [Band]
    let modeClasses: [ModeClass]
    /// Concrete modes that count when a class is too coarse (a RTTY-only
    /// contest); nil = every raw mode of an allowed class.
    let allowedRawModes: [String]?
    let tokenSets: [TokenSet]
    let sides: [Side]
    let exchange: [ExchangeElement]
    let multipliers: [MultiplierClass]
    let points: [PointRule]
    let dupe: DupeRule
    /// Side id → the worked sides that count; nil = everyone.
    let pairing: [String: [String]]?
    let sideRules: [String: SideRules]
    let bonuses: [BonusRule]
    let scoreFactors: ScoreFactors?
    let operatingTime: OperatingTimeRule?
    let categories: Categories
    let cabrillo: CabrilloSpec
    let sources: ContestSources

    init(schemaVersion: Int = 2, id: String, name: String, family: ContestFamily, sponsor: String? = nil,
         notes: String? = nil, caveats: [PartyDefinition.Caveat] = [], schedule: [PartyDefinition.ScheduleWindow]? = nil,
         bands: [Band], modeClasses: [ModeClass], allowedRawModes: [String]? = nil, tokenSets: [TokenSet] = [],
         sides: [Side], exchange: [ExchangeElement], multipliers: [MultiplierClass], points: [PointRule],
         dupe: DupeRule, pairing: [String: [String]]? = nil, sideRules: [String: SideRules] = [:],
         bonuses: [BonusRule] = [], scoreFactors: ScoreFactors? = nil, operatingTime: OperatingTimeRule? = nil,
         categories: Categories = .all, cabrillo: CabrilloSpec, sources: ContestSources = .none) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.name = name
        self.family = family
        self.sponsor = sponsor
        self.notes = notes
        self.caveats = caveats
        self.schedule = schedule
        self.bands = bands
        self.modeClasses = modeClasses
        self.allowedRawModes = allowedRawModes
        self.tokenSets = tokenSets
        self.sides = sides
        self.exchange = exchange
        self.multipliers = multipliers
        self.points = points
        self.dupe = dupe
        self.pairing = pairing
        self.sideRules = sideRules
        self.bonuses = bonuses
        self.scoreFactors = scoreFactors
        self.operatingTime = operatingTime
        self.categories = categories
        self.cabrillo = cabrillo
        self.sources = sources
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, name, family, sponsor, notes, caveats, schedule, bands, modeClasses, allowedRawModes
        case tokenSets, sides, exchange, multipliers, points, dupe, pairing, sideRules, bonuses, scoreFactors
        case operatingTime, categories, cabrillo, sources
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try c.decode(Int.self, forKey: .schemaVersion),
            id: try c.decode(String.self, forKey: .id),
            name: try c.decode(String.self, forKey: .name),
            family: try c.decode(ContestFamily.self, forKey: .family),
            sponsor: try c.decodeIfPresent(String.self, forKey: .sponsor),
            notes: try c.decodeIfPresent(String.self, forKey: .notes),
            caveats: try c.decodeIfPresent([PartyDefinition.Caveat].self, forKey: .caveats) ?? [],
            schedule: try c.decodeIfPresent([PartyDefinition.ScheduleWindow].self, forKey: .schedule),
            bands: try c.decode([Band].self, forKey: .bands),
            modeClasses: try c.decodeIfPresent([ModeClass].self, forKey: .modeClasses) ?? ModeClass.allCases,
            allowedRawModes: try c.decodeIfPresent([String].self, forKey: .allowedRawModes),
            tokenSets: try c.decodeIfPresent([TokenSet].self, forKey: .tokenSets) ?? [],
            sides: try c.decode([Side].self, forKey: .sides),
            exchange: try c.decode([ExchangeElement].self, forKey: .exchange),
            multipliers: try c.decodeIfPresent([MultiplierClass].self, forKey: .multipliers) ?? [],
            points: try c.decode([PointRule].self, forKey: .points),
            dupe: try c.decode(DupeRule.self, forKey: .dupe),
            pairing: try c.decodeIfPresent([String: [String]].self, forKey: .pairing),
            sideRules: try c.decodeIfPresent([String: SideRules].self, forKey: .sideRules) ?? [:],
            bonuses: try c.decodeIfPresent([BonusRule].self, forKey: .bonuses) ?? [],
            scoreFactors: try c.decodeIfPresent(ScoreFactors.self, forKey: .scoreFactors),
            operatingTime: try c.decodeIfPresent(OperatingTimeRule.self, forKey: .operatingTime),
            categories: try c.decodeIfPresent(Categories.self, forKey: .categories) ?? .all,
            cabrillo: try c.decode(CabrilloSpec.self, forKey: .cabrillo),
            sources: try c.decodeIfPresent(ContestSources.self, forKey: .sources) ?? .none
        )
    }

    /// Decode a v2 file and validate it — the only entry point the catalog uses.
    static func decode(_ data: Data) throws -> ContestDefinition {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let contest = try decoder.decode(ContestDefinition.self, from: data)
        try contest.validate()
        return contest
    }

    // MARK: Lookup

    /// The contest's own set of that id, else a built-in, else the bundled sections.
    func tokenSet(id: String, bundle: Bundle = .main) -> TokenSet? {
        tokenSets.first { $0.id == id } ?? TokenSet.builtIn(id: id) ?? (id == "sections" ? TokenSet.sections(bundle: bundle) : nil)
    }

    func side(id: String) -> Side? { sides.first { $0.id == id } }

    func rules(for side: String) -> SideRules { sideRules[side] ?? .none }

    /// The sides an entrant on `side` may work for credit: its `pairing` row, else every side.
    func workableSides(for side: String) -> [String] { pairing?[side] ?? sides.map(\.id) }

    /// The elements an entrant on `side` receives, in spec order: those sent
    /// by any side it may work, excluding the call echo (which is the call field).
    func receivedElements(for side: String) -> [ExchangeElement] {
        let workable = Set(workableSides(for: side))
        return exchange.filter { $0.kind != .callEcho && !$0.sentBy.keys.filter(workable.contains).isEmpty }
    }

    /// The elements an entrant on `side` sends, in spec order.
    func sentElements(for side: String) -> [ExchangeElement] {
        exchange.filter { $0.sentBy[side] != nil }
    }

    // MARK: Validation

    func validate() throws {
        let sideIDs = Set(sides.map(\.id))
        guard !sides.isEmpty else { throw ContestValidationError.noSides }
        guard !exchange.isEmpty else { throw ContestValidationError.noExchange }
        guard let last = points.last, last.when.isEmpty else { throw ContestValidationError.pointsWithoutDefault }
        guard !cabrillo.contest.isEmpty else { throw ContestValidationError.noCabrilloContest }
        for e in exchange {
            for side in e.sentBy.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            for set in e.sentBy.values.flatMap({ $0.sets ?? [] }) where !isKnownSet(set) {
                throw ContestValidationError.unknownTokenSet(set)
            }
        }
        for m in multipliers {
            for side in m.counting.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            for r in m.resolvers {
                if let set = r.set, !isKnownSet(set) { throw ContestValidationError.unknownTokenSet(set) }
                if let element = r.element, !exchange.contains(where: { $0.id == element }) {
                    throw ContestValidationError.unknownElement(element)
                }
                for side in r.sides ?? [] where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
            }
            if let roster = m.roster, !isKnownSet(roster) { throw ContestValidationError.unknownTokenSet(roster) }
        }
        for (side, worked) in pairing ?? [:] {
            guard sideIDs.contains(side) else { throw ContestValidationError.unknownSide(side) }
            for w in worked where !sideIDs.contains(w) { throw ContestValidationError.unknownSide(w) }
        }
        for side in sideRules.keys where !sideIDs.contains(side) { throw ContestValidationError.unknownSide(side) }
        for s in sides {
            for p in [s.predicate, s.workedPredicate] {
                switch p.kind {
                case .always: break
                case .tokenIn:
                    guard let set = p.set, isKnownSet(set), let element = p.element,
                          exchange.contains(where: { $0.id == element }) else { throw ContestValidationError.badPredicate(s.id) }
                case .dxccIn: guard !(p.codes ?? []).isEmpty else { throw ContestValidationError.badPredicate(s.id) }
                case .continentIn: guard !(p.continents ?? []).isEmpty else { throw ContestValidationError.badPredicate(s.id) }
                }
            }
        }
    }

    /// The dynamic sets the validator resolves without a `TokenSet` value.
    static let dynamicSetIDs: Set<String> = ["dxccPrefix"]

    private func isKnownSet(_ id: String) -> Bool {
        tokenSets.contains { $0.id == id } || TokenSet.builtIn(id: id) != nil || id == "sections" || Self.dynamicSetIDs.contains(id)
    }
}

enum ContestValidationError: Error, Equatable, LocalizedError {
    case noSides, noExchange, pointsWithoutDefault, noCabrilloContest
    case unknownSide(String), unknownTokenSet(String), unknownElement(String), badPredicate(String)

    var errorDescription: String? {
        switch self {
        case .noSides: "Contest declares no sides."
        case .noExchange: "Contest declares no exchange elements."
        case .pointsWithoutDefault: "The last points rule must have no conditions."
        case .noCabrilloContest: "cabrillo.contest is empty."
        case .unknownSide(let s): "Unknown side '\(s)'."
        case .unknownTokenSet(let s): "Unknown token set '\(s)'."
        case .unknownElement(let e): "Unknown exchange element '\(e)'."
        case .badPredicate(let s): "Side '\(s)' has a predicate missing its fields."
        }
    }
}
```

- [ ] **Step 5: Regenerate and run** — `xcodegen generate`, then one-class `ContestDefinitionTests`. Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Contests/ContestDefinition.swift Tests/Core/ContestDefinitionTests.swift Tests/Fixtures/Contests/cqwwcw.json QSOPartyLogger.xcodeproj && git commit -m "contests: ContestDefinition — the assembled v2 model with decode-and-validate, plus the CQ WW fixture

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 12: `PartyLowering` — every bundled party lowers into the model

**Files:**
- Create: `Sources/Core/Contests/PartyLowering.swift`
- Test: `Tests/Core/PartyLoweringTests.swift`

Side ids are `inside` / `outside` (or the single `all` when the party has no home region); token-set ids are `counties`, `states`, `provinces`, `sections`, `dxAliases`, `designatedCounties`; element ids `rst serial name location member`; class ids are today's `MultClass` raw values.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class PartyLoweringTests: XCTestCase {
    private func lowered(_ id: String) throws -> ContestDefinition {
        try PartyLowering.lower(try XCTUnwrap(PartyCatalog.party(id: id)))
    }
    private func party(_ id: String) throws -> PartyDefinition { try XCTUnwrap(PartyCatalog.party(id: id)) }

    func testEveryBundledPartyLowersAndValidates() throws {
        let parties = PartyCatalog.loadBundled()
        XCTAssertEqual(parties.count, 50)
        for p in parties {
            let c = try PartyLowering.lower(p)
            XCTAssertNoThrow(try c.validate(), p.id)
            XCTAssertEqual(c.id, p.id)
            XCTAssertEqual(c.name, p.name)
            XCTAssertEqual(c.cabrillo.contest, p.cabrilloContest)
            XCTAssertEqual(c.bands, p.validBands, p.id)
            XCTAssertEqual(c.modeClasses, p.allowedModeClasses, p.id)
            XCTAssertEqual(c.schedule, p.schedule, p.id)
            XCTAssertEqual(c.caveats, p.caveats, p.id)
            XCTAssertEqual(c.dupe, .partyDefault, p.id)
            XCTAssertEqual(c.family, .stateQSOParty, p.id)
            XCTAssertEqual(c.bonuses, p.bonuses, p.id)
            XCTAssertEqual(c.sources.hubSpots, p.hubSpots, p.id)
            XCTAssertEqual(c.sources.callHistory, p.callHistory, p.id)
            XCTAssertEqual(c.sources.combines, p.combines, p.id)
            // The location element is always present and always a token element.
            let loc = try XCTUnwrap(c.exchange.first { $0.id == "location" }, p.id)
            XCTAssertEqual(loc.kind, .token, p.id)
            XCTAssertTrue(loc.fixed, p.id)
            XCTAssertEqual(loc.cabrilloWidth, 6, p.id)
            // Sides.
            XCTAssertEqual(c.sides.map(\.id), p.hasHomeRegion ? ["inside", "outside"] : ["all"], p.id)
            // Class ids are the union of both sides' classes, in MultClass order.
            let expected = MultClass.allCases.filter {
                p.multipliers.inState.classes.contains($0) || p.multipliers.outState.classes.contains($0)
            }.map(\.rawValue)
            XCTAssertEqual(c.multipliers.map(\.id), expected, p.id)
            // The last points rule is unconditional.
            XCTAssertEqual(c.points.last?.when, [], p.id)
        }
    }

    func testKansasShape() throws {
        let c = try lowered("ksqp"), p = try party("ksqp")
        XCTAssertEqual(c.sides[0].label, "Inside KS")
        XCTAssertEqual(c.sides[0].predicate, SidePredicate(kind: .tokenIn, element: "location", set: "counties"))
        XCTAssertEqual(c.sides[1].predicate, .always)
        XCTAssertEqual(c.exchange.map(\.id), ["rst", "location"])
        let loc = c.exchange[1]
        XCTAssertEqual(loc.sentBy["inside"]?.sets, ["counties"])
        XCTAssertEqual(loc.sentBy["inside"]?.multi?.max, min(4, p.maxSimultaneousCounties))
        XCTAssertEqual(loc.sentBy["outside"]?.sets, ["states", "provinces", "dxToken"])
        XCTAssertNil(loc.sentBy["outside"]?.multi)
        XCTAssertEqual(loc.label, "\(p.countyTerm.sentenceCased)/State")
        XCTAssertEqual(c.tokenSet(id: "counties")?.tokens.count, 105)
        XCTAssertEqual(c.tokenSet(id: "counties")?.term, "county")
        XCTAssertFalse(try XCTUnwrap(c.tokenSet(id: "states")).accepts("KS"))   // excludedStateTokens
        XCTAssertTrue(try XCTUnwrap(c.tokenSet(id: "states")).accepts("TX"))
        XCTAssertEqual(c.cabrillo.location, .state)
        XCTAssertNil(c.pairing)
        // KSQP in-state: states+provinces+dx, home state via county.
        let state = try XCTUnwrap(c.multipliers.first { $0.id == "state" })
        XCTAssertEqual(state.counting["inside"], p.multipliers.inState.countScope)
        XCTAssertTrue(state.resolvers.contains { $0.kind == .receivedToken && $0.set == "counties" && $0.mapTo == "group" && $0.sides == ["inside"] })
        XCTAssertEqual(state.resolvers.first?.set, "states")
        XCTAssertEqual(c.tokenSet(id: "counties")?.tokens.first?.group, "KS")
        XCTAssertEqual(c.points, [
            PointRule(when: [PointCondition(modeClass: [.phone])], points: p.points.phone),
            PointRule(when: [PointCondition(modeClass: [.cw])], points: p.points.cw),
            PointRule(when: [PointCondition(modeClass: [.digital])], points: p.points.digital),
            PointRule(points: p.points.phone),
        ])
    }

    func testNAQPHasOneSideAndAName() throws {
        let c = try lowered("naqpcw")
        XCTAssertEqual(c.sides.map(\.id), ["all"])
        XCTAssertEqual(c.exchange.map(\.id), ["name", "location"])
        XCTAssertEqual(c.exchange[1].sentBy["all"]?.sets, ["counties", "states", "provinces", "dxToken"])
        XCTAssertEqual(c.exchange[1].sentBy["all"]?.multi?.max, 1)
        XCTAssertEqual(c.tokenSet(id: "counties")?.term, "NA entity")
        XCTAssertEqual(c.cabrillo.location, .entrantToken)
        XCTAssertEqual(c.multipliers.first { $0.id == "county" }?.counting, ["all": .perBand])
    }

    func testPennsylvaniaUsesSectionsInsteadOfStates() throws {
        let c = try lowered("paqp")
        XCTAssertEqual(c.exchange.first { $0.id == "location" }?.sentBy["outside"]?.sets, ["sections", "dxToken"])
        XCTAssertNotNil(c.tokenSet(id: "sections"))
        XCTAssertNil(c.tokenSet(id: "states"))
        XCTAssertEqual(c.multipliers.first { $0.id == "section" }?.resolvers.first?.set, "sections")
        XCTAssertEqual(c.rules(for: "inside").granted.map(\.value).sorted(), ["EPA", "WPA"])
    }

    func testMarylandDCPairsOutsideWithInsideOnly() throws {
        let c = try lowered("mdc")
        XCTAssertEqual(c.pairing, ["outside": ["inside"]])
        XCTAssertEqual(c.exchange.map(\.id), ["location"])          // no RST
    }

    func testCaliforniaSerialAndScoredCap() throws {
        let c = try lowered("cqp")
        let serial = try XCTUnwrap(c.exchange.first { $0.id == "serial" })
        XCTAssertFalse(serial.fixed)
        XCTAssertEqual(serial.kind, .serial)
        XCTAssertEqual(c.rules(for: "inside").maxScoredMultipliers, 58)
    }

    func testFloridaDXAliases() throws {
        let c = try lowered("fqp")
        XCTAssertEqual(c.tokenSet(id: "dxAliases")?.abbrs, ["R1", "R2", "R3"])
        let dx = try XCTUnwrap(c.multipliers.first { $0.id == "dx" })
        XCTAssertEqual(dx.resolvers[0].kind, .receivedToken)
        XCTAssertEqual(dx.resolvers[0].set, "dxAliases")
        XCTAssertEqual(dx.resolvers[1].kind, .dxccEntity)
        XCTAssertEqual(dx.resolvers[1].from, .receivedTokenOrCallsign)
        XCTAssertTrue(try XCTUnwrap(c.exchange.first { $0.id == "location" }?.sentBy["outside"]?.sets).contains("dxccPrefix"))
    }

    func testSkeeterMemberElementAndPoints() throws {
        let c = try lowered("skeeter"), p = try party("skeeter")
        let member = try XCTUnwrap(c.exchange.first { $0.id == "member" })
        XCTAssertEqual(member.kind, .memberOrPower)
        XCTAssertEqual(member.member?.term, p.memberExchange?.term)
        XCTAssertEqual(c.points, [
            PointRule(when: [PointCondition(workedStationKind: ["member"])], points: 3),
            PointRule(when: [PointCondition(workedStationKind: ["qrp"])], points: 2),
            PointRule(points: 1),
        ])
        XCTAssertEqual(c.scoreFactors?.entryClasses.count, 4)
        XCTAssertEqual(c.multipliers.first { $0.id == "dx" }?.resolvers.last?.countEntities, true)
    }

    func testBumblebeesMemberClassAndFloor() throws {
        let c = try lowered("fobb")
        let member = try XCTUnwrap(c.multipliers.first { $0.id == "member" })
        XCTAssertEqual(member.resolvers.first?.kind, .workedStation)
        XCTAssertEqual(member.resolvers.first?.element, "member")
        XCTAssertEqual(member.layout, .workedOnly)
        XCTAssertEqual(c.rules(for: "all").multiplierFloor, 1)
    }

    func testNorthCarolinaScalesDesignatedCounties() throws {
        let c = try lowered("ncqp"), p = try party("ncqp")
        let designated = try XCTUnwrap(c.tokenSet(id: "designatedCounties"))
        XCTAssertEqual(designated.tokens.count, p.countyPointFactor?.counties.count)
        XCTAssertEqual(c.points.count, 7)      // 3 designated + 3 by mode + the unconditional tail
        XCTAssertEqual(c.points[0], PointRule(
            when: [PointCondition(modeClass: [.phone], receivedTokenIn: .init(element: "location", set: "designatedCounties"))],
            points: p.points.phone * (p.countyPointFactor?.factor ?? 0)))
        XCTAssertEqual(c.points[3], PointRule(when: [PointCondition(modeClass: [.phone])], points: p.points.phone))
    }

    func testMaineHomeStationPoints() throws {
        let c = try lowered("meqp"), p = try party("meqp")
        XCTAssertEqual(c.points[0], PointRule(
            when: [PointCondition(modeClass: [.phone], receivedTokenIn: .init(element: "location", set: "counties"))],
            points: p.homeStationPoints?.phone ?? -1))
        XCTAssertEqual(c.points.count, 7)      // 3 home-station + 3 by mode + the unconditional tail
    }

    func testSeventhAreaCountiesCarryTheirState() throws {
        let c = try lowered("sevenqp")
        let counties = try XCTUnwrap(c.tokenSet(id: "counties"))
        XCTAssertEqual(Set(counties.tokens.compactMap(\.group)).count, 7)
        XCTAssertFalse(try XCTUnwrap(c.tokenSet(id: "states")).accepts("ID"))
        XCTAssertEqual(c.sides[0].label, "Inside the 7th call area")
    }

    func testTennesseeActivatedCountyRuleAndSalmonRunCap() throws {
        let tn = try lowered("tnqp"), tnp = try party("tnqp")
        let act = try XCTUnwrap(tn.rules(for: "inside").activated)
        XCTAssertEqual(act.classID, "county")
        XCTAssertEqual(act.minCount, tnp.multipliers.inState.activatedCountyMultiplier?.minCount)
        let wa = try lowered("warun"), wap = try party("warun")
        XCTAssertEqual(wa.multipliers.first { $0.id == "dx" }?.caps?["inside"], wap.multipliers.inState.dxMultCap)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'PartyLowering' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Lowers a QSO-party authoring definition (schema v1) into the general model.
/// Pure and total over the bundled catalogue: `PartyLoweringTests` proves every
/// party lowers and validates. Field-by-field mapping: spec §1.3.
enum PartyLowering {
    static let insideID = "inside", outsideID = "outside", allID = "all"

    static func lower(_ p: PartyDefinition) throws -> ContestDefinition {
        let sides = sides(for: p)
        let sideIDs = sides.map(\.id)
        var sets = tokenSets(for: p)
        var points = pointRules(for: p, sets: &sets)
        if points.last?.when.isEmpty != true { points.append(PointRule(points: p.points.phone)) }
        return ContestDefinition(
            id: p.id, name: p.name, family: .stateQSOParty, notes: p.notes, caveats: p.caveats,
            schedule: p.schedule, bands: p.validBands, modeClasses: p.allowedModeClasses,
            tokenSets: sets, sides: sides, exchange: exchange(for: p, sideIDs: sideIDs, sets: sets),
            multipliers: multipliers(for: p, sideIDs: sideIDs), points: points, dupe: .partyDefault,
            pairing: p.outStateWorksHomeStationsOnly && p.hasHomeRegion ? [outsideID: [insideID]] : nil,
            sideRules: sideRules(for: p, sideIDs: sideIDs), bonuses: p.bonuses,
            scoreFactors: scoreFactors(for: p),
            cabrillo: CabrilloSpec(contest: p.cabrilloContest, location: p.hasHomeRegion ? .state : .entrantToken),
            sources: ContestSources(hubSpots: p.hubSpots, callHistory: p.callHistory, oneByOne: p.oneByOne, combines: p.combines)
        )
    }

    // MARK: Sides

    private static func sides(for p: PartyDefinition) -> [Side] {
        guard p.hasHomeRegion else {
            return [Side(id: allID, label: "Everyone", predicate: .always, workedPredicate: .always)]
        }
        let inCounties = SidePredicate(kind: .tokenIn, element: "location", set: "counties")
        return [
            Side(id: insideID, label: "Inside \(p.inStateLabel)", predicate: inCounties, workedPredicate: inCounties),
            Side(id: outsideID, label: "Outside \(p.inStateLabel)", predicate: .always, workedPredicate: .always),
        ]
    }

    /// The v1 rule that governs a side.
    private static func rule(_ p: PartyDefinition, _ side: String) -> PartyDefinition.MultRule {
        side == outsideID ? p.multipliers.outState : p.multipliers.inState
    }

    // MARK: Token sets

    private static func tokenSets(for p: PartyDefinition) -> [TokenSet] {
        var out: [TokenSet] = [
            TokenSet(id: "counties", term: p.countyTerm, termPlural: p.countyTermPlural,
                     tokens: p.counties.map { TokenSet.Token(abbr: $0.abbr, name: $0.name, group: p.state(forCounty: $0.abbr)) }),
        ]
        if p.usesSections {
            out.append(TokenSet(id: "sections", term: "section", termPlural: "sections",
                                tokens: p.sections.sorted().map { TokenSet.Token(abbr: $0) }))
        } else {
            let excluded = Set(p.excludedStateTokens.map { $0.uppercased() })
            let aliasKeys = Set(p.stateAliases.keys.map { $0.uppercased() })
            let states = MultClass.acceptedStateTokens.subtracting(excluded).subtracting(aliasKeys).sorted()
            out.append(TokenSet(id: "states", term: "state", termPlural: "states",
                                tokens: states.map { TokenSet.Token(abbr: $0) }, aliases: p.stateAliases))
            out.append(TokenSet(id: "provinces", term: "province", termPlural: "provinces",
                                tokens: p.provinces.sorted().map { TokenSet.Token(abbr: $0) }))
        }
        if !p.dxTokenAliases.isEmpty {
            out.append(TokenSet(id: "dxAliases", term: "DX", termPlural: "DX",
                                tokens: p.dxTokenAliases.sorted().map { TokenSet.Token(abbr: $0) }))
        }
        return out
    }

    /// What an outside station may send: sections instead of states + provinces
    /// where the party counts sections, then the DX forms it accepts.
    private static func outsideSets(for p: PartyDefinition) -> [String] {
        var sets = p.usesSections ? ["sections"] : ["states", "provinces"]
        if p.acceptsDXToken { sets.append("dxToken") }
        if p.dxStyle == .prefix { sets.append("dxccPrefix") }
        if !p.dxTokenAliases.isEmpty { sets.append("dxAliases") }
        return sets
    }

    // MARK: Exchange

    private static func exchange(for p: PartyDefinition, sideIDs: [String], sets: [TokenSet]) -> [ExchangeElement] {
        let all = Dictionary(uniqueKeysWithValues: sideIDs.map { ($0, ExchangeElement.SentSpec()) })
        var out: [ExchangeElement] = []
        if p.exchangeIncludesRST { out.append(ExchangeElement(id: "rst", kind: .rst, sentBy: all, cabrilloWidth: 3)) }
        if p.exchangeIncludesSerial { out.append(ExchangeElement(id: "serial", kind: .serial, label: "QSO #", sentBy: all, cabrilloWidth: 3)) }
        if p.exchangeIncludesName { out.append(ExchangeElement(id: "name", kind: .name, sentBy: all, fixed: true, cabrilloWidth: 3, prefill: [.callHistory, .stationMemory])) }
        let cap = min(ExchangeParser.maxCounties, p.maxSimultaneousCounties)
        let inside = ExchangeElement.SentSpec(sets: ["counties"], multi: .init(max: cap))
        let sentBy: [String: ExchangeElement.SentSpec] = p.hasHomeRegion
            ? [insideID: inside, outsideID: .init(sets: outsideSets(for: p))]
            : [allID: .init(sets: ["counties"] + outsideSets(for: p), multi: .init(max: cap))]
        out.append(ExchangeElement(
            id: "location", kind: .token,
            label: p.hasHomeRegion ? "\(p.countyTerm.sentenceCased)/State" : "Location",
            sentBy: sentBy, fixed: true, cabrilloWidth: 6, prefill: [.spot, .callHistory, .stationMemory]))
        if let m = p.memberExchange {
            out.append(ExchangeElement(
                id: "member", kind: .memberOrPower, label: m.term, shortLabel: m.shortTerm, sentBy: all, fixed: true,
                cabrilloWidth: 3, prefill: [.callHistory, .stationMemory],
                member: MemberSpec(term: m.term, shortTerm: m.shortTerm, memberPlural: m.memberPlural, qrpMaxWatts: m.qrpMaxWatts)))
        }
        return out
    }

    // MARK: Multipliers

    private static func multipliers(for p: PartyDefinition, sideIDs: [String]) -> [MultiplierClass] {
        let classes = MultClass.allCases.filter { c in sideIDs.contains { rule(p, $0).classes.contains(c) } }
        return classes.map { c in
            var counting: [String: CountScope] = [:]
            for s in sideIDs where rule(p, s).classes.contains(c) { counting[s] = rule(p, s).countScope }
            switch c {
            case .county:
                return MultiplierClass(id: "county", term: p.countyTerm, termPlural: p.countyTermPlural,
                                       resolvers: [Resolver(kind: .receivedToken, element: "location", set: "counties")],
                                       counting: counting, roster: "counties", layout: .groupedTokens)
            case .state:
                var resolvers = [Resolver(kind: .receivedToken, element: "location", set: "states")]
                for s in sideIDs where rule(p, s).homeStateCountsViaCounty {
                    resolvers.append(Resolver(kind: .receivedToken, element: "location", set: "counties", mapTo: "group", sides: [s]))
                }
                return MultiplierClass(id: "state", term: "state", resolvers: resolvers, counting: counting, roster: "states")
            case .province:
                return MultiplierClass(id: "province", term: "province", resolvers: [Resolver(kind: .receivedToken, element: "location", set: "provinces")],
                                       counting: counting, roster: "provinces")
            case .section:
                return MultiplierClass(id: "section", term: "section", resolvers: [Resolver(kind: .receivedToken, element: "location", set: "sections")],
                                       counting: counting, roster: "sections")
            case .dx:
                var resolvers: [Resolver] = []
                if !p.dxTokenAliases.isEmpty { resolvers.append(Resolver(kind: .receivedToken, element: "location", set: "dxAliases")) }
                let entitySides = sideIDs.filter { rule(p, $0).dxCountsEntities }
                let tokenSides = sideIDs.filter { !rule(p, $0).dxCountsEntities }
                if !tokenSides.isEmpty {
                    resolvers.append(Resolver(kind: .dxccEntity, from: .receivedTokenOrCallsign, list: .arrl, countEntities: false,
                                              sides: tokenSides.count == sideIDs.count ? nil : tokenSides))
                }
                if !entitySides.isEmpty {
                    resolvers.append(Resolver(kind: .dxccEntity, from: .receivedTokenOrCallsign, list: .arrl, countEntities: true,
                                              sides: entitySides.count == sideIDs.count ? nil : entitySides))
                }
                var caps: [String: Int] = [:]
                for s in sideIDs { if let cap = rule(p, s).dxMultCap { caps[s] = cap } }
                return MultiplierClass(id: "dx", term: "DX entity", termPlural: "DX entities", resolvers: resolvers,
                                       counting: counting, caps: caps.isEmpty ? nil : caps, layout: .workedOnly)
            case .member:
                return MultiplierClass(id: "member", term: p.memberExchange?.term ?? "member", termPlural: p.memberExchange?.memberPlural,
                                       resolvers: [Resolver(kind: .workedStation, element: "member")],
                                       counting: counting, layout: .workedOnly)
            }
        }
    }

    // MARK: Points

    /// Explicit tables, first match wins: designated counties (scaled),
    /// then home-state stations, then everyone — or the member sprint's three
    /// rates. `sets` gains `designatedCounties` when the party names some.
    private static func pointRules(for p: PartyDefinition, sets: inout [TokenSet]) -> [PointRule] {
        if let m = p.memberExchange {
            return [PointRule(when: [PointCondition(workedStationKind: ["member"])], points: m.memberPoints),
                    PointRule(when: [PointCondition(workedStationKind: ["qrp"])], points: m.qrpPoints),
                    PointRule(points: m.otherPoints)]
        }
        func rows(_ table: PartyDefinition.PointsTable, _ match: PointCondition.TokenMatch?) -> [PointRule] {
            ModeClass.allCases.map { mode in
                PointRule(when: [PointCondition(modeClass: [mode], receivedTokenIn: match)], points: table.points(for: mode))
            }
        }
        var out: [PointRule] = []
        if let f = p.countyPointFactor {
            sets.append(TokenSet(id: "designatedCounties", term: p.countyTerm, termPlural: p.countyTermPlural,
                                 tokens: f.counties.map { TokenSet.Token(abbr: $0) }))
            let base = p.homeStationPoints ?? p.points
            out += rows(base.scaled(by: f.factor), .init(element: "location", set: "designatedCounties"))
        }
        if let home = p.homeStationPoints {
            out += rows(home, .init(element: "location", set: "counties"))
        }
        out += rows(p.points, nil)
        return out
    }

    // MARK: Side rules and factors

    private static func sideRules(for p: PartyDefinition, sideIDs: [String]) -> [String: SideRules] {
        var out: [String: SideRules] = [:]
        for s in sideIDs {
            let r = rule(p, s)
            let activated = r.activatedCountyMultiplier.map {
                ActivatedRule(classID: "county", minCount: $0.minCount, countUnit: $0.countUnit, countScope: $0.countScope,
                              categories: $0.categories, notOtherwiseWorked: $0.notOtherwiseWorked)
            }
            let rules = SideRules(maxScoredMultipliers: r.maxScoredMultipliers, multiplierFloor: r.multiplierFloor,
                                  granted: r.granted.map { .init(classID: $0.multClass.rawValue, value: $0.value) },
                                  activated: activated)
            if rules != .none { out[s] = rules }
        }
        return out
    }

    private static func scoreFactors(for p: PartyDefinition) -> ScoreFactors? {
        guard p.scoreMultipliers != nil || !p.entryClasses.isEmpty else { return nil }
        return ScoreFactors(power: p.scoreMultipliers?.power, station: p.scoreMultipliers?.stationCategory,
                            entryClasses: p.entryClasses)
    }
}
```

`PartyDefinition.MultRule.granted`, `.activatedCountyMultiplier`, `.dxCountsEntities`, `.dxMultCap`, `.maxScoredMultipliers`, `.multiplierFloor` and `PartyDefinition.PointsTable.scaled(by:)` exist today; `PartyDefinition.ScoreMultipliers.stationCategory` is the station table's stored name.

- [ ] **Step 4: Run to verify pass** — one-class `PartyLoweringTests`. Expected: `Executed 13 tests, with 0 failures`. If a party throws in `testEveryBundledPartyLowersAndValidates`, the failure names it — fix the lowering, never the party file.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/PartyLowering.swift Tests/Core/PartyLoweringTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: PartyLowering — every bundled party lowers into ContestDefinition and validates

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 13: `CTYTable` — bigcty `cty.csv` bundled and parsed

**Files:**
- Create: `docs/research/fetch_cty.py`, `Resources/CTY/cty.csv`, `Resources/CTY/VERSION.txt`, `Sources/Core/Contests/CTYTable.swift`
- Modify: `project.yml` (add `Resources/CTY` folder resource)
- Test: `Tests/Core/CTYTableTests.swift`

- [ ] **Step 1: Write the fetch script and run it once** — `docs/research/fetch_cty.py`:

```python
#!/usr/bin/env python3
"""Fetch AD1C's Big CTY cty.csv into Resources/CTY/ and stamp its provenance.

CONSTITUTION Article 1: the file is the authority for callsign → entity, CQ/ITU
zone, continent (spec §1.6). Article 2: bundled verbatim, never retyped.
The server refuses a bare python User-Agent (verified 2026-08-17), so a browser
UA is sent. Re-run each season; commit cty.csv and VERSION.txt together.
"""
import datetime, hashlib, pathlib, re, urllib.request

URL = "https://www.country-files.com/bigcty/cty.csv"
ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "Resources/CTY"
OUT.mkdir(parents=True, exist_ok=True)

req = urllib.request.Request(URL, headers={"User-Agent": "Mozilla/5.0 (Macintosh) QSOPartyLogger-fetch"})
data = urllib.request.urlopen(req, timeout=60).read()
text = data.decode("utf-8", errors="strict")
records = [l for l in text.splitlines() if l.strip()]
assert len(records) >= 340, f"only {len(records)} records"
m = re.search(r"=VER(\d{8})", text)
assert m, "no =VERyyyymmdd release marker in the file"
(OUT / "cty.csv").write_bytes(data)
(OUT / "VERSION.txt").write_text(
    f"source: {URL}\nfetched: {datetime.date.today().isoformat()}\nrelease: VER{m.group(1)}\n"
    f"records: {len(records)}\nbytes: {len(data)}\nsha256: {hashlib.sha256(data).hexdigest()}\n"
    "format: primary prefix, name, ADIF entity code, continent, CQ zone, ITU zone, lat, lon, tz, prefix list ending ';'\n"
    "        (a leading * on the primary prefix marks a WAE-only entity; =CALL is an exact callsign; (n) CQ and [n] ITU overrides)\n"
    "see: docs/research/cty_dat_format.txt\n")
print(f"wrote {len(data)} bytes, {len(records)} records, release VER{m.group(1)}")
```

Run: `python3 docs/research/fetch_cty.py` — Expected: `wrote 3xxxxx bytes, 346 records, release VER2026MMDD` (346 = 340 DXCC + 6 WAE-only on 2026-08-17). If the network is unavailable, stop and report; do not hand-author the file.

Then add to `project.yml` after the `Resources/Data` entry:

```yaml
      - path: Resources/CTY
        type: folder
        buildPhase: resources
```

- [ ] **Step 2: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class CTYTableTests: XCTestCase {
    // Synthetic file: deterministic mechanics.
    private let csv = """
    K,United States,291,NA,5,8,37.53,91.67,5.0,K W N AA AB K5(4)[7] W6(3)[6] =K1ABC(5)[8] =W6XYZ/7(3)[6];
    VE,Canada,1,NA,5,9,44.35,78.75,5.0,VE VA VO VY VE3(4)[4] =VER20260814;
    *IT9,Sicily,,EU,15,28,37.50,-14.00,-1.0,IT9 IW9 =IT9/K5ZD;
    DL,Fed. Rep. of Germany,230,EU,14,28,51.00,-10.00,-1.0,DA DB DC DD DL;
    """

    func testParsesFieldsOverridesExactCallsAndWAE() throws {
        let t = try CTYTable.parse(csv: csv)
        XCTAssertEqual(t.entities.count, 4)
        XCTAssertEqual(t.release, "VER20260814")
        let k5 = try XCTUnwrap(t.match(callsign: "K5ABC"))
        XCTAssertEqual(k5.entity.entityCode, 291)
        XCTAssertEqual(k5.entity.name, "United States")
        XCTAssertEqual(k5.continent, "NA")
        XCTAssertEqual(k5.cqZone, 4)      // K5(4)[7] — the longest listed prefix wins
        XCTAssertEqual(k5.ituZone, 7)
        XCTAssertFalse(k5.exact)
        XCTAssertEqual(try XCTUnwrap(t.match(callsign: "KE5CW")).cqZone, 5)   // no KE5 rule in this synthetic file → entity default
        let w1 = try XCTUnwrap(t.match(callsign: "W1AW"))
        XCTAssertEqual(w1.cqZone, 5)       // entity default
        XCTAssertEqual(w1.ituZone, 8)
        let exact = try XCTUnwrap(t.match(callsign: "k1abc"))
        XCTAssertTrue(exact.exact)
        XCTAssertEqual(exact.cqZone, 5)
        XCTAssertEqual(try XCTUnwrap(t.match(callsign: "W6XYZ/7")).cqZone, 3)   // exact call with a slash
        let ve3 = try XCTUnwrap(t.match(callsign: "VE3XYZ"))
        XCTAssertEqual(ve3.entity.entityCode, 1)
        XCTAssertEqual(ve3.cqZone, 4)
        let it9 = try XCTUnwrap(t.match(callsign: "IT9ABC"))
        XCTAssertTrue(it9.entity.waeOnly)
        XCTAssertNil(it9.entity.entityCode)
        XCTAssertEqual(it9.entity.name, "Sicily")
        XCTAssertEqual(it9.entity.primaryPrefix, "IT9")
        XCTAssertEqual(try XCTUnwrap(t.match(callsign: "DL1AA/P")).entity.entityCode, 230)   // portable suffix stripped
        XCTAssertNil(t.match(callsign: "ZZ9ZZ"))
        XCTAssertNil(t.match(callsign: ""))
    }

    func testEntityNameMayContainACommaAndDXCCPrefixLookup() throws {
        let t = try CTYTable.parse(csv: "VP2E,Anguilla, The Valley,12,NA,8,11,18.22,63.07,4.0,VP2E;\n")
        XCTAssertEqual(t.entities.first?.name, "Anguilla, The Valley")
        XCTAssertEqual(t.entity(forPrimaryPrefix: "VP2E")?.entityCode, 12)
    }

    // Bundled file: facts that do not move between releases.
    func testBundledFileLoadsAndResolvesWellKnownCalls() throws {
        let t = try XCTUnwrap(CTYTable.load(bundle: .main))
        XCTAssertGreaterThanOrEqual(t.entities.filter { !$0.waeOnly }.count, 340)
        XCTAssertNotNil(t.release?.range(of: #"^VER\d{8}$"#, options: .regularExpression))
        XCTAssertEqual(t.match(callsign: "KE5CW")?.entity.entityCode, 291)
        XCTAssertEqual(t.match(callsign: "KE5CW")?.continent, "NA")
        XCTAssertEqual(t.match(callsign: "VE3XYZ")?.entity.entityCode, 1)
        XCTAssertEqual(t.match(callsign: "DL1AA")?.entity.entityCode, 230)
        XCTAssertEqual(t.match(callsign: "DL1AA")?.continent, "EU")
        XCTAssertEqual(t.match(callsign: "JA1AA")?.entity.entityCode, 339)
        XCTAssertEqual(t.match(callsign: "G3AAA")?.entity.entityCode, 223)
        XCTAssertEqual(t.match(callsign: "VK2AA")?.continent, "OC")
        XCTAssertTrue(t.entities.contains { $0.waeOnly && $0.primaryPrefix == "IT9" })
    }

    func testEveryARRLEntityHasACTYCounterpart() throws {
        let cty = try XCTUnwrap(CTYTable.load(bundle: .main))
        let arrl = DXCCTable.shared
        let ctyCodes = Set(cty.entities.compactMap(\.entityCode))
        for entity in arrl.entities {
            XCTAssertTrue(ctyCodes.contains(Int(entity.code) ?? -1), "ARRL entity \(entity.code) \(entity.name) missing from cty.csv")
        }
    }
}
```

(`DXCCTable.shared.entities` is the ARRL roster; codes are stored as strings there.)

- [ ] **Step 3: Run to verify failure** — `xcodegen generate`, then one-class `CTYTableTests`. Expected: build error `cannot find 'CTYTable' in scope`.

- [ ] **Step 4: Implement**

```swift
import Foundation

/// AD1C's Big CTY `cty.csv`, the authority for callsign → DXCC entity, CQ and
/// ITU zone, continent and WAE-only status (spec §1.6; constitution Article 1
/// as amended). Bundled under `Resources/CTY/` with `VERSION.txt`; refreshed
/// by the CTY client and applied at launch only.
struct CTYTable: Sendable {
    struct Entity: Equatable, Sendable {
        let name: String
        let primaryPrefix: String
        /// ADIF/DXCC entity code; nil for a WAE-only entity (`*` in the file).
        let entityCode: Int?
        let continent: String
        let cqZone: Int
        let ituZone: Int
        let waeOnly: Bool
    }

    struct Match: Equatable, Sendable {
        let entity: Entity
        let cqZone: Int
        let ituZone: Int
        let continent: String
        /// Matched an `=CALL` entry rather than a prefix.
        let exact: Bool
    }

    let entities: [Entity]
    /// The `=VERyyyymmdd` release marker the file carries.
    let release: String?

    private struct Rule: Sendable {
        let entity: Int
        let cq: Int?
        let itu: Int?
    }
    private let exact: [String: Rule]
    private let prefixes: [String: Rule]

    // MARK: Loading

    static func load(bundle: Bundle = .main) -> CTYTable? {
        guard let url = bundle.url(forResource: "cty", withExtension: "csv", subdirectory: "CTY"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return try? parse(csv: text)
    }

    enum ParseError: Error, Equatable { case malformedRecord(String), noRecords }

    static func parse(csv: String) throws -> CTYTable {
        var entities: [Entity] = [], exact: [String: Rule] = [:], prefixes: [String: Rule] = [:]
        var release: String?
        for raw in csv.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            var fields = line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 10 else { throw ParseError.malformedRecord(line) }
            // A name may contain commas: everything between the primary prefix
            // and the last eight fields is the name.
            if fields.count > 10 {
                let name = fields[1...(fields.count - 9)].joined(separator: ",")
                fields = [fields[0], name] + Array(fields[(fields.count - 8)...])
            }
            let waeOnly = fields[0].hasPrefix("*")
            let primary = waeOnly ? String(fields[0].dropFirst()) : fields[0]
            guard let cq = Int(fields[4]), let itu = Int(fields[5]) else { throw ParseError.malformedRecord(line) }
            let entity = Entity(name: fields[1], primaryPrefix: primary.uppercased(),
                                entityCode: Int(fields[2]).flatMap { $0 > 0 ? $0 : nil },
                                continent: fields[3], cqZone: cq, ituZone: itu, waeOnly: waeOnly)
            let index = entities.count
            entities.append(entity)
            let list = fields[9].replacingOccurrences(of: ";", with: "")
            for token in list.split(separator: " ") {
                var t = Substring(token)
                let isExact = t.hasPrefix("=")
                if isExact { t = t.dropFirst() }
                var cqOverride: Int?, ituOverride: Int?
                if let open = t.firstIndex(of: "("), let close = t[open...].firstIndex(of: ")") {
                    cqOverride = Int(t[t.index(after: open)..<close]); t = t[..<open] + t[t.index(after: close)...]
                }
                if let open = t.firstIndex(of: "["), let close = t[open...].firstIndex(of: "]") {
                    ituOverride = Int(t[t.index(after: open)..<close]); t = t[..<open] + t[t.index(after: close)...]
                }
                let key = String(t).uppercased()
                if key.hasPrefix("VER"), key.count == 11, Int(key.dropFirst(3)) != nil { release = key; continue }
                let rule = Rule(entity: index, cq: cqOverride, itu: ituOverride)
                // A callsign listed under two entities keeps the first (4U1VIC).
                if isExact { if exact[key] == nil { exact[key] = rule } } else if prefixes[key] == nil { prefixes[key] = rule }
            }
        }
        guard !entities.isEmpty else { throw ParseError.noRecords }
        return CTYTable(entities: entities, release: release, exact: exact, prefixes: prefixes)
    }

    // MARK: Lookup

    func entity(forPrimaryPrefix prefix: String) -> Entity? {
        entities.first { $0.primaryPrefix == prefix.uppercased() }
    }

    /// The entity and zones for a callsign: an exact `=CALL` entry (with or
    /// without its portable suffix), else the longest prefix of the call's
    /// location part (`DXCCTable.locationPart(of:)` strips /P, /MM, /QRP…).
    func match(callsign raw: String) -> Match? {
        let call = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard !call.isEmpty else { return nil }
        if let rule = exact[call] { return make(rule, exact: true) }
        let part = DXCCTable.locationPart(of: call)
        if let rule = exact[part] { return make(rule, exact: true) }
        var end = part.endIndex
        while end > part.startIndex {
            if let rule = prefixes[String(part[..<end])] { return make(rule, exact: false) }
            end = part.index(before: end)
        }
        return nil
    }

    private func make(_ rule: Rule, exact: Bool) -> Match {
        let e = entities[rule.entity]
        return Match(entity: e, cqZone: rule.cq ?? e.cqZone, ituZone: rule.itu ?? e.ituZone, continent: e.continent, exact: exact)
    }
}
```

- [ ] **Step 5: Run to verify pass** — one-class `CTYTableTests`. Expected: `Executed 4 tests, with 0 failures`. If `testEveryARRLEntityHasACTYCounterpart` fails for a code, record it in the commit message and open a caveat item in the plan for the engine switch — do not edit either data file by hand.

- [ ] **Step 6: Commit**

```bash
git add docs/research/fetch_cty.py Resources/CTY project.yml QSOPartyLogger.xcodeproj Sources/Core/Contests/CTYTable.swift Tests/Core/CTYTableTests.swift && git commit -m "contests: CTYTable — bigcty cty.csv bundled with provenance and parsed for entity, zone, continent and WAE

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 14: `WPXPrefix`

**Files:**
- Create: `Sources/Core/Contests/WPXPrefix.swift`
- Test: `Tests/Core/WPXPrefixTests.swift`

- [ ] **Step 1: Write the failing tests** (every expectation is the sponsor's own example, docs/research/cqwpx_rules_2026.txt V.C.1 and the Rules FAQ, except the bare-digit case, marked)

```swift
import XCTest
@testable import QSOPartyLogger

final class WPXPrefixTests: XCTestCase {
    func testRuleExamples() {
        for (call, prefix) in [("N8ABC", "N8"), ("W8XYZ", "W8"), ("WD8ABC", "WD8"), ("HG1AB", "HG1"), ("HG19AB", "HG19"),
                               ("KC2ABC", "KC2"), ("OE2AB", "OE2"), ("OE25AB", "OE25"), ("LY1000AB", "LY1000")] {
            XCTAssertEqual(WPXPrefix.of(call), prefix, call)
        }
    }

    func testPortableDesignatorBecomesThePrefix() {
        XCTAssertEqual(WPXPrefix.of("PA/N8BJQ"), "PA0")     // designator without a number gets Ø after the second letter
        XCTAssertEqual(WPXPrefix.of("OE/K5ZD"), "OE0")
        XCTAssertEqual(WPXPrefix.of("KL7RA/WK9"), "WK9")
        XCTAssertEqual(WPXPrefix.of("N8BJQ/PA"), "PA0")     // either order
    }

    func testCallsWithoutNumbers() {
        XCTAssertEqual(WPXPrefix.of("XEFTJW"), "XE0")       // "assigned a zero (Ø) after the first two letters"
    }

    func testFAQExamples() {
        for (call, prefix) in [("OL25LP", "OL25"), ("DL60CHILD", "DL60"), ("9A800VZ", "9A800"),
                               ("DR2006Q", "DR2006"), ("LY1000CW", "LY1000")] {
            XCTAssertEqual(WPXPrefix.of(call), prefix, call)
        }
    }

    func testClassIdentifiersDoNotCount() {
        for (call, prefix) in [("W1AW/MM", "W1"), ("K5ZD/P", "K5"), ("DL1AA/M", "DL1"), ("G3AAA/A", "G3"),
                               ("F5ABC/QRP", "F5"), ("JA1AA/AM", "JA1"), ("k5zd/p", "K5")] {
            XCTAssertEqual(WPXPrefix.of(call), prefix, call)
        }
    }

    func testBareDigitDesignatorReplacesTheNumber() {
        // NOT STATED by the sponsor; carried as a ruleInference caveat (spec §1.6).
        XCTAssertEqual(WPXPrefix.of("W1ABC/7"), "W7")
        XCTAssertEqual(WPXPrefix.of("KE5CW/4"), "KE4")
    }

    func testEmptyAndJunk() {
        XCTAssertNil(WPXPrefix.of(""))
        XCTAssertNil(WPXPrefix.of("/"))
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'WPXPrefix' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// The CQ WPX prefix of a callsign, per rule V.C.1 (docs/research/cqwpx_rules_2026.txt):
/// "the letter/numeral combination which forms the first part of the amateur
/// call … In cases of portable operation, the portable designator will then
/// become the prefix … Portable designators without numbers will be assigned a
/// zero (Ø) after the second letter … All calls without numbers will be
/// assigned a zero (Ø) after the first two letters … Maritime mobile, mobile,
/// /A, /E, /J, /P, or other license class identifiers do not count as prefixes."
enum WPXPrefix {
    /// Suffixes that are class identifiers, not designators.
    static let ignoredSuffixes: Set<String> = ["MM", "AM", "M", "A", "E", "J", "P", "QRP"]

    static func of(_ raw: String) -> String? {
        let parts = raw.uppercased().split(separator: "/").map(String.init).filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        var candidates = parts.filter { !ignoredSuffixes.contains($0) }
        if candidates.isEmpty { candidates = [parts[0]] }
        if candidates.count == 1 { return prefix(of: candidates[0]) }
        // A bare digit designator replaces the number (NOT STATED — inference).
        if let digit = candidates.first(where: { $0.allSatisfy(\.isNumber) }),
           let home = candidates.first(where: { !$0.allSatisfy(\.isNumber) }),
           let base = prefix(of: home) {
            let letters = base.prefix { $0.isLetter }
            return String(letters) + digit
        }
        // The designator is the part that does not read as a full call
        // (no letters after its digits); ties go to the shorter, then the first.
        let designators = candidates.filter { !looksLikeFullCall($0) }
        let pick = (designators.isEmpty ? candidates : designators)
            .enumerated()
            .min { ($0.element.count, $0.offset) < ($1.element.count, $1.offset) }!
            .element
        return prefix(of: pick)
    }

    /// Letters and digits through the last digit that is followed by a letter
    /// (`OL25LP` → `OL25`, `9A800VZ` → `9A800`); a part with no such digit
    /// keeps its whole self (`WK9`, `OE25`); a part with no digit at all takes
    /// its first two letters and a zero (`XEFTJW` → `XE0`, `PA` → `PA0`).
    static func prefix(of part: String) -> String? {
        guard !part.isEmpty else { return nil }
        let chars = Array(part)
        guard chars.contains(where: \.isNumber) else {
            return String(chars.prefix(2)) + "0"
        }
        var cut: Int?
        for i in chars.indices where chars[i].isNumber && chars[(i + 1)...].contains(where: \.isLetter) { cut = i }
        guard let cut else { return part }
        return String(chars[...cut])
    }

    private static func looksLikeFullCall(_ part: String) -> Bool {
        let chars = Array(part)
        guard let lastDigit = chars.lastIndex(where: \.isNumber) else { return false }
        return chars[(lastDigit + 1)...].contains(where: \.isLetter)
    }
}
```

- [ ] **Step 4: Run to verify pass** — one-class `WPXPrefixTests`. Expected: `Executed 7 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/WPXPrefix.swift Tests/Core/WPXPrefixTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: WPXPrefix — CQ WPX rule V.C.1 with the sponsor's examples as tests

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 15: `ExchangeValidator` — one element, one value, per kind (proven equal to `ExchangeParser` on every party)

**Files:**
- Create: `Sources/Core/Contests/ExchangeValidator.swift`
- Test: `Tests/Core/ExchangeValidatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class ExchangeValidatorTests: XCTestCase {
    private func contest(_ id: String) throws -> ContestDefinition {
        try PartyLowering.lower(try XCTUnwrap(PartyCatalog.party(id: id)))
    }
    private func element(_ c: ContestDefinition, _ id: String) throws -> ExchangeElement {
        try XCTUnwrap(c.exchange.first { $0.id == id })
    }

    func testTokenElementAcceptsCountiesCountyLinesAndOutTokens() throws {
        let c = try contest("ksqp"), loc = try element(c, "location")
        XCTAssertEqual(try ExchangeValidator.validate("lin", element: loc, contest: c, side: "inside").get(), ["LIN"])
        XCTAssertEqual(try ExchangeValidator.validate("lin/and", element: loc, contest: c, side: "inside").get(), ["LIN", "AND"])
        XCTAssertEqual(try ExchangeValidator.validate("tx", element: loc, contest: c, side: "inside").get(), ["TX"])
        XCTAssertEqual(try ExchangeValidator.validate("dx", element: loc, contest: c, side: "outside").get(), ["DX"])
        XCTAssertThrowsError(try ExchangeValidator.validate("ks", element: loc, contest: c, side: "inside").get())    // home state token
        XCTAssertThrowsError(try ExchangeValidator.validate("lin/tx", element: loc, contest: c, side: "inside").get()) // mixed
        XCTAssertThrowsError(try ExchangeValidator.validate("", element: loc, contest: c, side: "inside").get())
        if case .failure(.invalid(let token, let suggestions)) = ExchangeValidator.validate("LNI", element: loc, contest: c, side: "inside") {
            XCTAssertEqual(token, "LNI")
            XCTAssertTrue(suggestions.contains("LIN"))
        } else { XCTFail("expected a suggestion") }
    }

    func testMarylandOutsideEntrantReceivesCountiesOnly() throws {
        let c = try contest("mdc"), loc = try element(c, "location")
        let county = try XCTUnwrap(PartyCatalog.party(id: "mdc")?.counties.first?.abbr)
        XCTAssertNoThrow(try ExchangeValidator.validate(county, element: loc, contest: c, side: "outside").get())
        XCTAssertThrowsError(try ExchangeValidator.validate("TX", element: loc, contest: c, side: "outside").get())
        XCTAssertNoThrow(try ExchangeValidator.validate("TX", element: loc, contest: c, side: "inside").get())
    }

    func testDXPrefixesAndAliases() throws {
        let c = try contest("fqp"), loc = try element(c, "location")
        XCTAssertEqual(try ExchangeValidator.validate("dl", element: loc, contest: c, side: "inside").get(), ["DL"])
        XCTAssertEqual(try ExchangeValidator.validate("r2", element: loc, contest: c, side: "inside").get(), ["R2"])
        XCTAssertThrowsError(try ExchangeValidator.validate("EM32", element: loc, contest: c, side: "inside").get())
        XCTAssertThrowsError(try ExchangeValidator.validate("FL", element: loc, contest: c, side: "inside").get())    // home state, not a prefix here
    }

    func testOtherKinds() throws {
        let c = try contest("cqp")
        let serial = try element(c, "serial")
        XCTAssertEqual(try ExchangeValidator.validate("007", element: serial, contest: c, side: "inside").get(), ["7"])
        XCTAssertThrowsError(try ExchangeValidator.validate("7a", element: serial, contest: c, side: "inside").get())
        let rst = ExchangeElement(id: "rst", kind: .rst, sentBy: ["all": .init()])
        XCTAssertEqual(try ExchangeValidator.validate("5nn", element: rst, contest: c, side: "inside").get(), ["599"])
        XCTAssertEqual(try ExchangeValidator.validate("59", element: rst, contest: c, side: "inside").get(), ["59"])
        XCTAssertThrowsError(try ExchangeValidator.validate("5", element: rst, contest: c, side: "inside").get())
        let zone = ExchangeElement(id: "zone", kind: .cqZone, sentBy: ["all": .init()])
        XCTAssertEqual(try ExchangeValidator.validate("05", element: zone, contest: c, side: "inside").get(), ["5"])
        XCTAssertThrowsError(try ExchangeValidator.validate("41", element: zone, contest: c, side: "inside").get())
        let prec = ExchangeElement(id: "precedence", kind: .precedence, sentBy: [:], letters: ["Q", "A", "B", "U", "M", "S"])
        XCTAssertEqual(try ExchangeValidator.validate("a", element: prec, contest: c, side: "inside").get(), ["A"])
        XCTAssertThrowsError(try ExchangeValidator.validate("X", element: prec, contest: c, side: "inside").get())
        let check = ExchangeElement(id: "check", kind: .check, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("65", element: check, contest: c, side: "inside").get(), ["65"])
        XCTAssertThrowsError(try ExchangeValidator.validate("655", element: check, contest: c, side: "inside").get())
        let cls = ExchangeElement(id: "class", kind: .classToken, sentBy: [:], letters: ["A", "B", "C", "D", "E", "F"], minNumber: 1)
        XCTAssertEqual(try ExchangeValidator.validate("3a", element: cls, contest: c, side: "inside").get(), ["3A"])
        XCTAssertThrowsError(try ExchangeValidator.validate("0A", element: cls, contest: c, side: "inside").get())
        XCTAssertThrowsError(try ExchangeValidator.validate("3G", element: cls, contest: c, side: "inside").get())
        let power = ExchangeElement(id: "power", kind: .power, sentBy: [:])
        for ok in ["100", "KW", "K", "500W", "1KW"] { XCTAssertNoThrow(try ExchangeValidator.validate(ok, element: power, contest: c, side: "inside").get(), ok) }
        XCTAssertThrowsError(try ExchangeValidator.validate("LOTS", element: power, contest: c, side: "inside").get())
        let grid = ExchangeElement(id: "grid", kind: .grid, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("em13le", element: grid, contest: c, side: "inside").get(), ["EM13LE"])
        XCTAssertThrowsError(try ExchangeValidator.validate("EM1", element: grid, contest: c, side: "inside").get())
        let report = ExchangeElement(id: "report", kind: .report, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("-12", element: report, contest: c, side: "inside").get(), ["-12"])
        let name = ExchangeElement(id: "name", kind: .name, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("bill", element: name, contest: c, side: "inside").get(), ["BILL"])
        XCTAssertThrowsError(try ExchangeValidator.validate("B1LL", element: name, contest: c, side: "inside").get())
        let member = ExchangeElement(id: "member", kind: .memberOrPower, sentBy: [:])
        XCTAssertEqual(try ExchangeValidator.validate("5 w", element: member, contest: c, side: "inside").get(), ["5W"])
        XCTAssertEqual(try ExchangeValidator.validate("013", element: member, contest: c, side: "inside").get(), ["013"])
        XCTAssertThrowsError(try ExchangeValidator.validate("five", element: member, contest: c, side: "inside").get())
    }

    /// The oracle: on every bundled party, for both roles, the validator
    /// accepts exactly what `ExchangeParser` accepts and returns the same
    /// locations. Success/failure only — the two report errors differently.
    func testAgreesWithExchangeParserOnEveryParty() throws {
        for p in PartyCatalog.loadBundled() {
            let c = try PartyLowering.lower(p)
            let loc = try element(c, "location")
            var corpus = p.counties.map(\.abbr) + p.validOutStateTokens.sorted()
            corpus += ["ZZZ", "EM32", "SAF", "DL", "JA", "PA", "ON", "OK", "SD", "TN", "R1", "DX", "TX/OK", ""]
            if p.counties.count >= 2 { corpus += ["\(p.counties[0].abbr)/\(p.counties[1].abbr)", "\(p.counties[0].abbr)/TX"] }
            if p.counties.count >= 5 { corpus.append(p.counties.prefix(5).map(\.abbr).joined(separator: "/")) }
            for (role, side) in [(ExchangeParser.Role.inState, p.hasHomeRegion ? "inside" : "all"),
                                 (ExchangeParser.Role.outOfState, p.hasHomeRegion ? "outside" : "all")] {
                for raw in corpus {
                    // The legacy parser let an outside entrant of a
                    // home-stations-only party (MDC) log a bare DX prefix the
                    // rules give no credit for; the validator follows the
                    // pairing instead (spec §1.2). Skip those probes there.
                    if role == .outOfState, p.outStateWorksHomeStationsOnly, p.dxStyle == .prefix,
                       ["DL", "JA"].contains(raw) { continue }
                    let legacy = ExchangeParser.parse(raw, party: p, role: role)
                    let new = ExchangeValidator.validate(raw, element: loc, contest: c, side: side)
                    switch (legacy, new) {
                    case (.success(let l), .success(let n)):
                        XCTAssertEqual(l.locations, n, "\(p.id) \(role) '\(raw)'")
                    case (.failure, .failure):
                        break
                    default:
                        XCTFail("\(p.id) \(role) '\(raw)': legacy \(legacy) vs new \(new)")
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'ExchangeValidator' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Validates one received exchange element for an entrant on `side`, per its
/// kind. Token kinds keep `ExchangeParser`'s tokeniser, suggestions and
/// edit-distance help; the parity test pins them equal on every party.
enum ExchangeValidator {
    enum Failure: Error, Equatable, LocalizedError {
        case empty
        case invalid(String, suggestions: [String])
        case tooMany(Int, max: Int)
        case mixed
        case badFormat(String)

        var errorDescription: String? {
            switch self {
            case .empty: "Enter the exchange."
            case .invalid(let t, let s):
                s.isEmpty ? "'\(t)' is not valid." : "'\(t)' is not valid. Did you mean \(s.joined(separator: ", "))?"
            case .tooMany(let n, let max): "\(n) values given — at most \(max) allowed."
            case .mixed: "Mixing counties with states/provinces isn't valid."
            case .badFormat(let what): what
            }
        }
    }

    /// Canonical value(s): one for every kind but a multi-valued token
    /// element (a county line), which returns each county in typed order.
    static func validate(_ raw: String, element: ExchangeElement, contest: ContestDefinition,
                         side: String, bundle: Bundle = .main) -> Result<[String], Failure> {
        let text = raw.trimmingCharacters(in: .whitespaces).uppercased()
        switch element.kind {
        case .token:
            return validateToken(text, element: element, contest: contest, side: side, bundle: bundle)
        case .rst:
            let cut = text.replacingOccurrences(of: "N", with: "9")
            return cut.count >= 2 && cut.count <= 3 && cut.allSatisfy(\.isNumber) ? .success([cut]) : .failure(.badFormat("A signal report is 2 or 3 digits."))
        case .serial:
            guard !text.isEmpty, text.count <= 5, text.allSatisfy(\.isNumber), let n = Int(text) else {
                return .failure(.badFormat("A QSO number is 1–5 digits."))
            }
            return .success([String(n)])
        case .name:
            return !text.isEmpty && text.count <= 15 && text.allSatisfy(\.isLetter) ? .success([text]) : .failure(.badFormat("A name is 1–15 letters."))
        case .cqZone, .ituZone:
            let top = element.kind == .cqZone ? 40 : 90
            guard let n = Int(text), (1...top).contains(n) else { return .failure(.badFormat("A zone is 1–\(top).")) }
            return .success([String(n)])
        case .precedence:
            return (element.letters ?? []).contains(text) ? .success([text]) : .failure(.badFormat("Precedence is one of \((element.letters ?? []).joined(separator: " "))."))
        case .check:
            return text.count == 2 && text.allSatisfy(\.isNumber) ? .success([text]) : .failure(.badFormat("A check is two digits."))
        case .classToken:
            let digits = text.prefix { $0.isNumber }
            let letter = text.dropFirst(digits.count)
            guard let n = Int(digits), n >= (element.minNumber ?? 1), letter.count == 1,
                  (element.letters ?? []).contains(String(letter)) else {
                return .failure(.badFormat("A class is a number and one of \((element.letters ?? []).joined(separator: " "))."))
            }
            return .success([String(n) + letter])
        case .power:
            let ok = text == "K" || text == "KW" || text.range(of: #"^\d+(W|K|KW)?$"#, options: .regularExpression) != nil
            return ok ? .success([text]) : .failure(.badFormat("Power is a number, or K/KW."))
        case .memberOrPower:
            guard let value = MemberExchange.parse(text) else { return .failure(.badFormat("A member number, or a power with its unit (5W).")) }
            switch value {
            case .member(let number): return .success([number])
            case .power: return .success([text.filter { !$0.isWhitespace }])
            }
        case .callEcho:
            return .success([text])
        case .grid:
            return text.range(of: #"^[A-R]{2}\d{2}([A-X]{2})?$"#, options: .regularExpression) != nil
                ? .success([text]) : .failure(.badFormat("A grid is 4 or 6 characters (EM13 or EM13LE)."))
        case .report:
            return text.range(of: #"^[-+]?\d{1,2}$"#, options: .regularExpression) != nil
                ? .success([text]) : .failure(.badFormat("A report is a signed number of dB."))
        }
    }

    // MARK: Token kinds

    private static func validateToken(_ text: String, element: ExchangeElement, contest: ContestDefinition,
                                      side: String, bundle: Bundle) -> Result<[String], Failure> {
        let tokens = ExchangeParser.tokenize(text)
        guard !tokens.isEmpty else { return .failure(.empty) }
        let workable = contest.workableSides(for: side)
        let sets = element.setsSent(by: workable)
        // Sets a side may send several of at once (a county line), and how many.
        var multiSets = Set<String>(), maxValues = 1
        for s in workable {
            if let spec = element.sentBy[s], let multi = spec.multi {
                multiSets.formUnion(spec.sets ?? []); maxValues = max(maxValues, multi.max)
            }
        }
        // Everything the element accepts, for the dynamic prefix set's exclusions and for suggestions.
        let enumerated = sets.compactMap { contest.tokenSet(id: $0, bundle: bundle) }
        let allAccepted = enumerated.reduce(into: Set<String>()) { $0.formUnion($1.acceptedTokens) }

        func classify(_ token: String) -> (set: String, value: String)? {
            for id in sets {
                if id == "dxccPrefix" {
                    if isDXPrefix(token, excluding: allAccepted) { return (id, token) }
                } else if let set = contest.tokenSet(id: id, bundle: bundle), let canon = set.canonical(token) {
                    return (id, canon)
                }
            }
            return nil
        }

        var classified: [(set: String, value: String)] = []
        for token in tokens {
            guard let hit = classify(token) else {
                return .failure(.invalid(token, suggestions: suggestions(for: token, among: allAccepted)))
            }
            classified.append(hit)
        }
        var seen = Set<String>()
        let unique = classified.filter { seen.insert($0.value).inserted }
        if unique.count > 1 {
            guard unique.allSatisfy({ multiSets.contains($0.set) }) else { return .failure(.mixed) }
            guard unique.count <= maxValues else { return .failure(.tooMany(unique.count, max: maxValues)) }
        }
        return .success(unique.map(\.value))
    }

    /// The party rule: a DXCC prefix the ARRL list carries that is not also
    /// one of this element's own tokens, a state, a province or `DX`.
    static func isDXPrefix(_ token: String, excluding accepted: Set<String>) -> Bool {
        guard !accepted.contains(token), !MultClass.acceptedStateTokens.contains(token),
              !MultClass.canadianProvinces.contains(token), token != MultClass.dxToken else { return false }
        return DXCCTable.shared.isKnownPrefix(token)
    }

    /// Prefix matches then Damerau-1 candidates, capped at 3 — `ExchangeParser.suggestions` verbatim.
    static func suggestions(for token: String, among accepted: Set<String>) -> [String] {
        let all = accepted.sorted()
        var out: [String] = []
        for a in all where a.hasPrefix(token) && a != token { out.append(a) }
        for a in all where !out.contains(a) && ExchangeParser.isEditDistanceOne(token, a) { out.append(a) }
        return Array(out.prefix(3))
    }
}
```

- [ ] **Step 4: Run to verify pass** — one-class `ExchangeValidatorTests`. Expected: `Executed 5 tests, with 0 failures`. If the parity test disagrees for a party, the legacy parser is the oracle: read `ExchangeParser.parse` for that party's shape and fix the validator, never the test.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/ExchangeValidator.swift Tests/Core/ExchangeValidatorTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: ExchangeValidator — per-kind element validation, equal to ExchangeParser on every party

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 16: `DupeChecker` on a `DupeRule`

**Files:**
- Modify: `Sources/Core/Engine/DupeChecker.swift` (add an overload; nothing existing changes)
- Test: `Tests/Core/DupeRuleTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class DupeRuleTests: XCTestCase {
    private func qso(_ call: String, _ band: Band, _ mode: ModeClass, my: String = "LIN", their: String = "TX", minute: Int) -> QSO {
        QSO(timestampUTC: Date(timeIntervalSince1970: TimeInterval(minute * 60)), call: call, band: band, modeClass: mode,
            rawMode: mode == .cw ? "CW" : "SSB", rstSent: "599", rstRcvd: "599", myLoc: my, theirLoc: their)
    }

    func testPartyDefaultEqualsTheLegacyKey() {
        let log = [qso("W1AW", .m20, .cw, minute: 0), qso("W1AW", .m20, .cw, minute: 1),
                   qso("W1AW", .m20, .cw, their: "OK", minute: 2), qso("W1AW", .m40, .cw, minute: 3),
                   qso("W1AW", .m20, .phone, minute: 4)]
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: .partyDefault), DupeChecker.firstOccurrenceIDs(log))
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: .partyDefault).count, 4)
    }

    func testContestScopeIsOncePerContest() {
        let log = [qso("W1AW", .m20, .cw, minute: 0), qso("W1AW", .m40, .cw, minute: 1), qso("W1AW", .m20, .phone, minute: 2),
                   qso("W1AW", .m20, .cw, their: "OK", minute: 3), qso("K5ZD", .m20, .cw, minute: 4)]
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .contest)).map { $0 }.count, 2)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .contest, locationSensitive: true)).count, 3)
    }

    func testBandScopeIgnoresMode() {
        let log = [qso("W1AW", .m20, .cw, minute: 0), qso("W1AW", .m20, .phone, minute: 1), qso("W1AW", .m40, .phone, minute: 2)]
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .band)).count, 2)
        XCTAssertEqual(DupeChecker.firstOccurrenceIDs(log, rule: DupeRule(scope: .bandMode)).count, 3)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error: no overload `firstOccurrenceIDs(_:rule:)`.

- [ ] **Step 3: Implement** — append to `DupeChecker` in `Sources/Core/Engine/DupeChecker.swift`:

```swift
    /// The general key: call, plus band and/or mode class per `rule.scope`,
    /// plus both locations when the rule is location-sensitive. With
    /// `.partyDefault` this is exactly `key(_:)`.
    struct RuleKey: Hashable {
        let call: String
        let band: Band?
        let modeClass: ModeClass?
        let myLoc: String?
        let theirLoc: String?
    }

    static func key(_ q: QSO, rule: DupeRule) -> RuleKey {
        RuleKey(
            call: q.call.uppercased(),
            band: rule.scope == .contest ? nil : q.band,
            modeClass: rule.scope == .bandMode ? q.modeClass : nil,
            myLoc: rule.locationSensitive ? q.myLoc.uppercased() : nil,
            theirLoc: rule.locationSensitive ? q.theirLoc.uppercased() : nil
        )
    }

    /// IDs of the chronologically-first row for each `RuleKey`; later rows are dupes.
    static func firstOccurrenceIDs(_ log: [QSO], rule: DupeRule) -> Set<UUID> {
        var seen = Set<RuleKey>()
        var firsts = Set<UUID>()
        for q in log.sortedChronologically() where seen.insert(key(q, rule: rule)).inserted {
            firsts.insert(q.id)
        }
        return firsts
    }
```

- [ ] **Step 4: Run to verify pass** — one-class `DupeRuleTests`. Expected: `Executed 3 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Engine/DupeChecker.swift Tests/Core/DupeRuleTests.swift QSOPartyLogger.xcodeproj && git commit -m "engine: DupeChecker overload keyed by DupeRule (contest / band / band-mode, location-sensitive)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 17: `OperatingTime` — operated / off minutes and the cutoff

**Files:**
- Create: `Sources/Core/Contests/OperatingTime.swift`
- Test: `Tests/Core/OperatingTimeTests.swift`

Model (spec §1.2 `OperatingTimeRule`): the operating period starts at the first row's minute; the empty clock minutes strictly between two consecutive rows are **off time** only when they number ≥ `minOffMinutes` (SS package: 0115–0144 is 30 empty minutes and counts; 0115–0143 does not); otherwise the whole gap is operating time. Operated minutes = the elapsed minutes of every operating segment (WPX FAQ: last QSO 09:00, next 10:00 → 60 operating minutes; next 10:01 → 60 off minutes). A row whose operated total exceeds `maxMinutes` is out of time.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class OperatingTimeTests: XCTestCase {
    private func row(_ hhmm: String, day: Int = 1) -> QSO {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HHmm"; f.timeZone = TimeZone(identifier: "UTC")
        return QSO(timestampUTC: f.date(from: "2026-11-0\(day) \(hhmm)")!, call: "W1AW", band: .m20, modeClass: .cw,
                   rawMode: "CW", rstSent: "599", rstRcvd: "599", myLoc: "NTX", theirLoc: "CT")
    }

    func testSweepstakesPackageExample() {
        let ss = OperatingTimeRule(maxMinutes: 24 * 60, minOffMinutes: 30)
        let counted = OperatingTime.compute(rows: [row("0100"), row("0114"), row("0145")], rule: ss)
        XCTAssertEqual(counted.offMinutes, 30)          // 0115 … 0144
        XCTAssertEqual(counted.operatedMinutes, 14)
        XCTAssertTrue(counted.outOfTimeRowIDs.isEmpty)
        let notOff = OperatingTime.compute(rows: [row("0100"), row("0114"), row("0144")], rule: ss)
        XCTAssertEqual(notOff.offMinutes, 0)            // 29 empty minutes count as operating
        XCTAssertEqual(notOff.operatedMinutes, 44)
    }

    func testWPXFAQExample() {
        let wpx = OperatingTimeRule(maxMinutes: 36 * 60, minOffMinutes: 60)
        XCTAssertEqual(OperatingTime.compute(rows: [row("0900"), row("1001")], rule: wpx).offMinutes, 60)
        XCTAssertEqual(OperatingTime.compute(rows: [row("0900"), row("1001")], rule: wpx).operatedMinutes, 0)
        XCTAssertEqual(OperatingTime.compute(rows: [row("0900"), row("1000")], rule: wpx).operatedMinutes, 60)
    }

    func testRowsPastTheLimitAreOutOfTime() {
        let rule = OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30)
        let rows = [row("0000"), row("0030"), row("0100"), row("0101"), row("0300"), row("0301")]
        let r = OperatingTime.compute(rows: rows, rule: rule)
        XCTAssertEqual(r.outOfTimeRowIDs, Set([rows[3].id, rows[4].id, rows[5].id]))
        XCTAssertEqual(r.operatedMinutes, 60)           // the meter stops at the limit
        XCTAssertEqual(r.cutoff, rows[2].timestampUTC)  // the last row that still counted
    }

    func testEmptyAndSingleRow() {
        let rule = OperatingTimeRule(maxMinutes: 60, minOffMinutes: 30)
        XCTAssertEqual(OperatingTime.compute(rows: [], rule: rule), .zero)
        let one = OperatingTime.compute(rows: [row("0000")], rule: rule)
        XCTAssertEqual(one.operatedMinutes, 0)
        XCTAssertNil(one.cutoff)
    }

    func testCrossesMidnight() {
        let rule = OperatingTimeRule(maxMinutes: 24 * 60, minOffMinutes: 30)
        let r = OperatingTime.compute(rows: [row("2350"), row("0010", day: 2)], rule: rule)
        XCTAssertEqual(r.operatedMinutes, 20)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'OperatingTime' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Operating-time arithmetic for `OperatingTimeRule` (spec §1.2): minute
/// granularity, off time only when the empty minutes between two rows reach
/// the rule's minimum, rows past the maximum marked out of time.
enum OperatingTime {
    struct Result: Equatable, Sendable {
        var operatedMinutes = 0
        var offMinutes = 0
        /// The timestamp of the last row that still counted, once the limit is
        /// reached; nil while the entrant is within the limit.
        var cutoff: Date?
        var outOfTimeRowIDs: Set<UUID> = []

        static let zero = Result()
    }

    /// Whole minutes since the epoch, seconds ignored (the sponsors' rule).
    static func minute(_ date: Date) -> Int { Int(floor(date.timeIntervalSince1970 / 60)) }

    static func compute(rows: [QSO], rule: OperatingTimeRule) -> Result {
        let ordered = rows.sortedChronologically()
        guard let first = ordered.first else { return .zero }
        var result = Result()
        var operated = 0
        var previous = minute(first.timestampUTC)
        var lastCounted = first
        for row in ordered.dropFirst() {
            let now = minute(row.timestampUTC)
            let empty = max(0, now - previous - 1)
            if empty >= rule.minOffMinutes {
                result.offMinutes += empty
            } else {
                operated += now - previous
            }
            previous = now
            if operated > rule.maxMinutes {
                result.outOfTimeRowIDs.insert(row.id)
                if result.cutoff == nil { result.cutoff = lastCounted.timestampUTC }
            } else {
                lastCounted = row
            }
        }
        result.operatedMinutes = min(operated, rule.maxMinutes)
        return result
    }
}
```

Note the out-of-time row still advances `previous` (its minute is when it was logged) but never becomes `lastCounted`; the meter reports at most `maxMinutes`.

- [ ] **Step 4: Run to verify pass** — one-class `OperatingTimeTests`. Expected: `Executed 5 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/OperatingTime.swift Tests/Core/OperatingTimeTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: OperatingTime — operated/off minutes and the out-of-time cutoff, per the SS and WPX examples

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 18: `ContestCatalog` — parties lowered plus v2 files, user overrides by id

**Files:**
- Create: `Sources/Core/Contests/ContestCatalog.swift`
- Test: `Tests/Core/ContestCatalogTests.swift`

`PartyCatalog` stays as the v1 loader (its 300+ call sites, mostly per-party tests, are untouched). `ContestCatalog` is what the app will read from the engine-switch plan onward. Nothing calls it yet.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import QSOPartyLogger

final class ContestCatalogTests: XCTestCase {
    func testBundledCatalogueIsEveryPartyLowered() {
        let contests = ContestCatalog.loadBundled()
        XCTAssertEqual(contests.count, 50)                    // no v2 file ships yet
        XCTAssertEqual(Set(contests.map(\.id)), Set(PartyCatalog.loadBundled().map(\.id)))
        XCTAssertEqual(contests.map(\.name), contests.map(\.name).sorted())
    }

    func testLookupByID() {
        XCTAssertEqual(ContestCatalog.contest(id: "ksqp")?.cabrillo.contest, "KS-QSO-PARTY")
        XCTAssertNil(ContestCatalog.contest(id: "nope"))
    }

    func testDecodesAV2FileFromAFolder() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fixture = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json", subdirectory: "Contests"))
        try FileManager.default.copyItem(at: fixture, to: dir.appendingPathComponent("cqwwcw.json"))
        try Data("{ not json".utf8).write(to: dir.appendingPathComponent("broken.json"))
        let loaded = ContestCatalog.loadUserContests(in: dir)
        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded.compactMap { try? $0.result.get() }.map(\.id), ["cqwwcw"])
        XCTAssertTrue(loaded.contains { $0.url.lastPathComponent == "broken.json" && (try? $0.result.get()) == nil })
    }

    func testUserV2FileOverridesAPartyOfTheSameID() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "cqwwcw", withExtension: "json", subdirectory: "Contests")))) as! [String: Any]
        json["id"] = "ksqp"; json["name"] = "Kansas, overridden"
        try JSONSerialization.data(withJSONObject: json).write(to: dir.appendingPathComponent("ksqp.json"))
        let all = ContestCatalog.all(userContestsDirectory: dir)
        XCTAssertEqual(all.first { $0.id == "ksqp" }?.name, "Kansas, overridden")
        XCTAssertEqual(all.count, 50)
    }
}
```

- [ ] **Step 2: Run to verify failure** — build error `cannot find 'ContestCatalog' in scope`.

- [ ] **Step 3: Implement**

```swift
import Foundation

/// Every contest the app knows: the bundled parties, lowered, plus bundled v2
/// files under `Resources/Contests/`, with user files overriding by id from
/// `~/Library/Application Support/QSOPartyLogger/{Parties,Contests}`.
enum ContestCatalog {
    static var userContestsDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QSOPartyLogger/Contests", isDirectory: true)
    }

    /// Bundled parties (lowered) and bundled v2 contests, by name.
    static func loadBundled(bundle: Bundle = .main) -> [ContestDefinition] {
        var byID: [String: ContestDefinition] = [:]
        for party in PartyCatalog.loadBundled(bundle: bundle) {
            if let lowered = try? PartyLowering.lower(party) { byID[lowered.id] = lowered }
        }
        for url in bundle.urls(forResourcesWithExtension: "json", subdirectory: "Contests") ?? [] {
            if let data = try? Data(contentsOf: url), let contest = try? ContestDefinition.decode(data) {
                byID[contest.id] = contest
            }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    /// User v2 files in a folder; failures are returned so the UI can explain them.
    static func loadUserContests(in dir: URL = userContestsDirectory) -> [(url: URL, result: Result<ContestDefinition, Error>)] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        return urls
            .filter { $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                do { return (url, .success(try ContestDefinition.decode(try Data(contentsOf: url)))) }
                catch { return (url, .failure(error)) }
            }
    }

    /// Everything, user party files (lowered) and user v2 files overriding
    /// bundled contests of the same id — v2 last, so it wins.
    static func all(bundle: Bundle = .main, userContestsDirectory: URL = userContestsDirectory) -> [ContestDefinition] {
        var byID = Dictionary(uniqueKeysWithValues: loadBundled(bundle: bundle).map { ($0.id, $0) })
        for (_, result) in PartyCatalog.loadUserParties() {
            if case .success(let party) = result, let lowered = try? PartyLowering.lower(party) { byID[lowered.id] = lowered }
        }
        for (_, result) in loadUserContests(in: userContestsDirectory) {
            if case .success(let contest) = result { byID[contest.id] = contest }
        }
        return byID.values.sorted { $0.name < $1.name }
    }

    static func contest(id: String, bundle: Bundle = .main) -> ContestDefinition? {
        all(bundle: bundle).first { $0.id == id }
    }
}
```

- [ ] **Step 4: Run to verify pass** — one-class `ContestCatalogTests`. Expected: `Executed 4 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Contests/ContestCatalog.swift Tests/Core/ContestCatalogTests.swift QSOPartyLogger.xcodeproj && git commit -m "contests: ContestCatalog — bundled parties lowered plus v2 files, user overrides by id

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 19: Full suite, docs, and hand-off

**Files:**
- Modify: `README.md` (the test-count line)

- [ ] **Step 1: Full suite in the worktree**

Run the full-suite command. Expected: `Executed 2947 tests, with 0 failures` — the 2,875 baseline plus the 72 added here (7 + 1 + 3 + 4 + 3 + 3 + 6 + 4 + 13 + 4 + 7 + 5 + 3 + 5 + 4). Record the exact line; if the number differs, count the new `func test` declarations and reconcile before proceeding.

- [ ] **Step 2: README test count** — in `README.md`, replace `**2875 unit tests**` with the suite's figure: `**2947 unit tests**`, or whatever Step 1 reported. Also replace the `CLAUDE.md` `Sources/Core/Contests/` layout row (which lists only the seven moved files today) with:

```markdown
| `Sources/Core/Contests/` | The general contest model — `ContestDefinition`, `TokenSet`, `Side`, `ExchangeElement`, `MultiplierClass`/`Resolver`, `PointRule`, `ContestRules` (dupe, op-time, categories, Cabrillo, factors) — plus `PartyLowering`, `ContestCatalog`, `CTYTable`, `WPXPrefix`, `ExchangeValidator`, `OperatingTime`, and the shared `HubSpotSource`, `CallHistorySource`, `DXCCTable` (+ label refresh/store), `MultiplierRoster`, `ScoreFactor` |
```

- [ ] **Step 3: Commit**

```bash
git add README.md CLAUDE.md && git commit -m "docs: foundations landed — test count, Contests layout row

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 4: Hand-off** — `xcodegen generate` (so the tracked pbxproj is current; commit it if it changed), then report to Tom: the full-suite line, `git log --oneline master..HEAD`, and the fast-forward he runs from the main checkout after checking `git log --oneline HEAD..worktree-general-contest-logger` shows no divergence:

```bash
git merge --ff-only worktree-general-contest-logger
```

The next plan (engine switch: `ScoreEngine`, exporters, `QSO`/`ContestLog` v2 shape, deleting the old engine) is written only after this one has merged.

---

## Self-review

- **Spec coverage (Part 1, §1.2–1.6 and 2.9):** token sets → Task 4/5; sides → 6; exchange elements incl. derivation and member labels → 7; multiplier classes and resolvers → 8; point rules → 9; dupe / operating time / categories / Cabrillo / score factors / side rules / sources → 10; the assembled model with validation → 11; lowering of every v1 field → 12; `CTYTable` with provenance and the ARRL cross-check → 13; `WPXPrefix` → 14; per-kind validation with the party oracle → 15; `DupeRule` in `DupeChecker` → 16; operating time → 17; catalog with user overrides → 18; docs → 19. Not in this plan by design: the engine, exporters, `QSO`/`ContestLog` shape, UI, `family` on the four non-state parties, `sides` on bonuses (next plans).
- **Placeholders:** none — every step carries its code and command.
- **Type consistency:** `TokenSet.Token(abbr:name:group:)`, `TokenSet.canonical/accepts/acceptedTokens/abbrs`, `SidePredicate(kind:element:set:codes:continents:)` + `.always` + `.matches(Context)`, `ExchangeElement(id:kind:label:shortLabel:sentBy:fixed:required:cabrilloWidth:prefill:derived:letters:minNumber:member:)` + `setsSent(by:)` + `maxValues(for:)`, `MemberSpec(term:shortTerm:memberPlural:qrpMaxWatts:)`, `MultiplierClass(id:term:termPlural:resolvers:counting:caps:roster:layout:)` + `scope(for:)`, `Resolver(kind:element:set:mapTo:from:list:exclude:countEntities:precision:sides:unlessSuffix:)` + `applies(side:call:)`, `PointRule(when:points:)` + `PointRule.points(_:_:)`, `PointCondition(...)` + `Context`, `DupeRule(scope:locationSensitive:)` + `.partyDefault`, `OperatingTimeRule(maxMinutes:minOffMinutes:appliesTo:)` + `applies(to:)`, `Categories` + `.all` + `allowed*`, `CabrilloSpec(contest:location:transmitterColumn:serialSequence:categoryMode:)`, `ScoreFactors(power:station:entryClasses:objectives:declaredBonuses:)`, `SideRules(...)` + `.none`, `ActivatedRule(classID:minCount:countUnit:countScope:categories:notOtherwiseWorked:)`, `ContestSources` + `.none`, `ContestDefinition(...)` + `decode(_:)` + `validate()` + `tokenSet(id:bundle:)` + `rules(for:)` + `workableSides(for:)` + `receivedElements(for:)` + `sentElements(for:)`, `ContestValidationError`, `PartyLowering.lower(_:)`, `CTYTable.parse(csv:)` + `load(bundle:)` + `match(callsign:)` + `entity(forPrimaryPrefix:)` + `release`, `WPXPrefix.of(_:)` + `prefix(of:)`, `ExchangeValidator.validate(_:element:contest:side:bundle:)` + `Failure`, `DupeChecker.firstOccurrenceIDs(_:rule:)` + `RuleKey`, `OperatingTime.compute(rows:rule:)` + `Result` + `.zero`, `ContestCatalog.loadBundled/loadUserContests/all/contest(id:)` — used with the same names and labels throughout.







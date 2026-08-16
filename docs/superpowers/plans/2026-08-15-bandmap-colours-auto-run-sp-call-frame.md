# Band map colours, automatic Run ⇄ S&P, and the call frame — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Colour band-map spots red / blue / grey by what they are worth, switch Run ⇄ S&P automatically as the VFO leaves and returns to the CQ frequency, and show the spot under the VFO as a ghost call in the empty call field that Space or Return (ESM) takes — all as N1MM Logger+ documents them.

**Architecture:** Pure decisions live in Core (`TuningPolicy` for the zones and the mode change, `SpotStore.nearest` for the spot under the VFO, `StationMemory.knownLocation` for a cluster spot's location, `SpotStatus` for the three colours). `EntryState`/`EntryFlow` own the call frame and the app-filled call (`callIsAutoFilled`, `hasOperatorText`, `takeCallFrame`, `tunedAway`). `BandMapModel` classifies spots with two non-observable caches. `MainView` wires one `.onChange(of: radio.radioState?.frequencyHz)` to `vfoMoved()`, which runs the CQ-frequency zone check and then the call frame.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen. macOS 15+.

**Spec:** `docs/superpowers/specs/2026-08-15-bandmap-colours-auto-run-sp-call-frame-design.md` — read it first; it carries the N1MM citations every doc comment below quotes.

**Working directory:** the `tuning-follow` worktree at `/Users/tom/AppDev/Apple/QSOPartyLogger/.claude/worktrees/tuning`. Every command below runs there. New source files need `xcodegen generate` before they build (the `.pbxproj` is generated **and tracked** — stage it with the files it lists).

**Test commands.** One class:

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/<ClassName> 2>&1 | tee /private/tmp/claude-501/-Users-tom-AppDev-Apple-QSOPartyLogger/4a739cfd-5af4-4313-9088-7d5b41003845/scratchpad/<ClassName>.log | grep -E "Test Case .*(passed|failed)|error:|\*\* TEST"
```

Build only:

```bash
set -o pipefail; xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | tee /private/tmp/claude-501/-Users-tom-AppDev-Apple-QSOPartyLogger/4a739cfd-5af4-4313-9088-7d5b41003845/scratchpad/build.log | grep -E "error:|warning: .*Sources/|\*\* BUILD"
```

Full suite (Task 10):

```bash
set -o pipefail; xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tee /private/tmp/claude-501/-Users-tom-AppDev-Apple-QSOPartyLogger/4a739cfd-5af4-4313-9088-7d5b41003845/scratchpad/full.log | grep -E "Executed [0-9]+ tests|error:|\*\* TEST"
```

Never `tail` an xcodebuild log; the `Executed N tests` line near the end is the count for the README.

---

## File structure

| Path | Responsibility |
| --- | --- |
| `Sources/Core/Engine/TuningPolicy.swift` (new) | `TuningPolicy.Zone`, `zone(...)`, `modeChange(...)`; `TuningDistances` (per-mode Hz values with N1MM-derived defaults) |
| `Sources/Core/Spotting/SpotStatus.swift` (new) | `SpotStatus` — worked / neededMultiplier / unworked |
| `Sources/Core/Spotting/SpotStore.swift` | `nearest(in:toKHz:withinHz:workedCalls:workedCallCounties:)` |
| `Sources/Core/Engine/StationMemory.swift` | `Source.callHistory`; `knownLocation(call:log:index:callHistory:party:role:)` |
| `Sources/App/RepeatCQPolicy.swift` | `continues(in:)` |
| `Sources/App/EntryState.swift` | `callIsAutoFilled`, `callTyped`, `autoFillCall`, `hasOperatorText`, `callFrame` |
| `Sources/App/EntryFlow.swift` | `Context.offersSpotCounty`; `refreshPrefill` via `knownLocation`; `stationChanged(...atKHz:)`; `stationLeft`; `updateCallFrame`; `takeCallFrame`; `tunedAway`; Return under ESM takes the frame |
| `Sources/App/AppSettings.swift` | `callFrameEnabled`, `autoLeaveRun`, `autoReturnToRun`, `tuningToleranceHz`, `leaveRunDistanceHz` |
| `Sources/UI/BandMap.swift` | `BandMapModel` verdict/status + caches + index inputs; colours, tooltips, legend; TUNING section |
| `Sources/UI/EntryBar.swift` | binds `callTyped`; ghost overlay; Space takes the frame |
| `Sources/UI/MainView.swift` | `radioBar` seam; `cqZone`; `vfoMoved`; mode-change wiring; model inputs; `tune(to:)` records the frequency |
| `Sources/UI/MessagesRow.swift` | picker tooltip |
| `README.md` | features, keyboard table, test count |
| Tests | `Tests/Core/TuningPolicyTests.swift`, `Tests/Core/SpottingTests.swift` (nearest), `Tests/Core/StationMemoryTests.swift`, `Tests/App/RepeatCQPolicyTests.swift`, `Tests/App/CallFrameTests.swift` (new), `Tests/App/TuningPreferenceTests.swift` (new), `Tests/App/BandMapStatusTests.swift` (new), `Tests/App/BandMapObservationTests.swift` |

---

### Task 1: `TuningPolicy`, `TuningDistances`, `SpotStatus` (Core, pure)

**Files:**
- Create: `Sources/Core/Engine/TuningPolicy.swift`
- Create: `Sources/Core/Spotting/SpotStatus.swift`
- Create: `Tests/Core/TuningPolicyTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/Core/TuningPolicyTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// Run ⇄ S&P follows the VFO around the CQ frequency, as N1MM's does
/// (Entry window, "Run mode and S+P mode", fetched 2026-08-15): "Normally
/// when you are on your CQ-frequency you will be in Run mode and QSYing will
/// switch to S&P mode" and "if you are in S&P mode and you tune within the
/// tuning tolerance of the marker, the program will switch automatically to
/// Run mode." The leave distance is this app's own, larger than the tolerance,
/// so a QRM dodge stays in Run — Tom's "reasonable amount of vfo change".
final class TuningPolicyTests: XCTestCase {

    // MARK: Zones

    func testOnFrequencyUpToAndIncludingTheTolerance() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_000, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .onFrequency)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_300, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .onFrequency, "the boundary is inside")
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_039_700, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .onFrequency, "either side")
    }

    func testNearBetweenToleranceAndLeaveDistance() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_301, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .near)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_041_000, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .near, "the leave boundary is still near")
    }

    func testAwayBeyondTheLeaveDistance() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_041_001, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .away)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_030_000, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 1000), .away)
    }

    /// A leave distance smaller than the tolerance is treated as equal to it:
    /// `near` simply never occurs.
    func testLeaveDistanceBelowToleranceCollapsesNear() {
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_200, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 100), .onFrequency)
        XCTAssertEqual(TuningPolicy.zone(vfoHz: 14_040_400, cqHz: 14_040_000, toleranceHz: 300, leaveHz: 100), .away)
    }

    // MARK: Leaving Run

    func testLeavingRunFromNearGoesToSearchPounce() {
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .near, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true),
            .searchPounce
        )
    }

    func testLeavingRunStraightFromTheFrequencyGoesToSearchPounce() {
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .onFrequency, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true),
            .searchPounce
        )
    }

    /// The QRM dodge: off the frequency but inside the leave distance is still Run.
    func testDodgingWithinTheLeaveDistanceStaysInRun() {
        XCTAssertNil(TuningPolicy.modeChange(from: .onFrequency, to: .near, mode: .run, leaveEnabled: true, returnEnabled: true))
    }

    func testLeaveOffLeavesRunAlone() {
        XCTAssertNil(TuningPolicy.modeChange(from: .near, to: .away, mode: .run, leaveEnabled: false, returnEnabled: true))
    }

    /// Already searching and moving away is nothing new.
    func testMovingAwayWhileSearchingChangesNothing() {
        XCTAssertNil(TuningPolicy.modeChange(from: .near, to: .away, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
    }

    // MARK: Returning to Run

    func testComingBackOntoTheFrequencyReturnsToRun() {
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .near, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true),
            .run
        )
        XCTAssertEqual(
            TuningPolicy.modeChange(from: .away, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true),
            .run, "a big jump straight back — ⌘J's own path lands here too"
        )
    }

    /// N1MM's "Do not automatically switch to Run on CQ-frequency".
    func testReturnOffKeepsSearchPounce() {
        XCTAssertNil(TuningPolicy.modeChange(from: .away, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: false))
    }

    /// Approaching is not arriving.
    func testApproachingToNearDoesNotReturnToRun() {
        XCTAssertNil(TuningPolicy.modeChange(from: .away, to: .near, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
    }

    // MARK: Edge-triggered — ⌘R is never fought

    /// Switch to S&P by hand while sitting on the CQ frequency: nothing flips
    /// you back, because the zone did not change.
    func testSameZoneNeverActs() {
        XCTAssertNil(TuningPolicy.modeChange(from: .onFrequency, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
        XCTAssertNil(TuningPolicy.modeChange(from: .away, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true),
                     "Run chosen by hand five kHz away stays Run")
    }

    /// The first observation after a CQ frequency appears only records the zone.
    func testNoPreviousZoneNeverActs() {
        XCTAssertNil(TuningPolicy.modeChange(from: nil, to: .away, mode: .run, leaveEnabled: true, returnEnabled: true))
        XCTAssertNil(TuningPolicy.modeChange(from: nil, to: .onFrequency, mode: .searchPounce, leaveEnabled: true, returnEnabled: true))
    }

    // MARK: Distances

    func testDefaultsAreN1MMsForCWAndDigitalAndWiderForPhone() {
        XCTAssertEqual(TuningDistances.defaultTolerance.hz(for: .cw), 300)
        XCTAssertEqual(TuningDistances.defaultTolerance.hz(for: .digital), 300)
        XCTAssertEqual(TuningDistances.defaultTolerance.hz(for: .phone), 1000)
        XCTAssertEqual(TuningDistances.defaultLeaveRun.hz(for: .cw), 1000)
        XCTAssertEqual(TuningDistances.defaultLeaveRun.hz(for: .digital), 1000)
        XCTAssertEqual(TuningDistances.defaultLeaveRun.hz(for: .phone), 3000)
    }

    func testSetChangesOnlyThatMode() {
        var distances = TuningDistances.defaultTolerance
        distances.set(500, for: .phone)
        XCTAssertEqual(distances.hz(for: .phone), 500)
        XCTAssertEqual(distances.hz(for: .cw), 300)
        XCTAssertEqual(distances.hz(for: .digital), 300)
    }

    func testDistancesRoundTripThroughJSON() throws {
        let original = TuningDistances(cwHz: 200, phoneHz: 1500, digitalHz: 400)
        let data = try JSONEncoder().encode(original)
        XCTAssertEqual(try JSONDecoder().decode(TuningDistances.self, from: data), original)
    }
}
```

- [ ] **Step 2: Create the two source files**

`Sources/Core/Engine/TuningPolicy.swift`:

```swift
import Foundation

/// How the operating mode follows the VFO knob around the CQ frequency.
///
/// N1MM Logger+ (Entry window, "Run mode and S+P mode", fetched 2026-08-15):
/// "When you call CQ on a frequency, the marker CQ-Frequency is placed at that
/// frequency on the Bandmap. Thereafter, if you are in S&P mode and you tune
/// within the tuning tolerance of the marker, the program will switch
/// automatically to Run mode." and "Normally when you are on your CQ-frequency
/// you will be in Run mode and QSYing will switch to S&P mode."
///
/// Three zones rather than N1MM's two: **on** the frequency (within the
/// tuning tolerance), **near** it (a QRM dodge — Tom's "reasonable amount of
/// vfo change"), and **away** (hunting). Leaving Run needs *away*; returning
/// needs *on*. In N1MM the S&P F1 is a CQ that puts you back in Run, so an
/// early flip costs one key there; here S&P F1 is "my call", so the flip has
/// to wait until you have genuinely left.
///
/// **Edge-triggered.** Only a change of zone acts, so ⌘R is never fought:
/// choose S&P by hand on the CQ frequency and you stay there; choose Run by
/// hand five kHz away and you stay there until F1 records the new frequency.
enum TuningPolicy {

    enum Zone: Equatable, Sendable {
        case onFrequency
        case near
        case away
    }

    /// `|vfo − cq|` ≤ tolerance → `.onFrequency`; ≤ leave → `.near`; else
    /// `.away`. A leave distance below the tolerance is read as equal to it.
    static func zone(vfoHz: Int, cqHz: Int, toleranceHz: Int, leaveHz: Int) -> Zone {
        let distance = abs(vfoHz - cqHz)
        if distance <= toleranceHz { return .onFrequency }
        if distance <= max(leaveHz, toleranceHz) { return .near }
        return .away
    }

    /// The mode to switch to on arriving in `zone` from `previous`, or nil.
    /// A nil `previous` is the first observation after a CQ frequency
    /// appeared: it only records the zone.
    static func modeChange(
        from previous: Zone?,
        to zone: Zone,
        mode: OperatingMode,
        leaveEnabled: Bool,
        returnEnabled: Bool
    ) -> OperatingMode? {
        guard let previous, previous != zone else { return nil }
        switch (zone, mode) {
        case (.away, .run):
            return leaveEnabled ? .searchPounce : nil
        case (.onFrequency, .searchPounce):
            return returnEnabled ? .run : nil
        default:
            return nil
        }
    }
}

/// One distance in Hz per mode class — N1MM's Configurer keeps a tuning
/// tolerance for SSB, CW and RTTY separately ("The default value is 300" for
/// each, fetched 2026-08-15). Used twice: the tuning tolerance (the call
/// frame, and "on the CQ frequency") and the leave-Run distance.
struct TuningDistances: Codable, Equatable, Sendable {
    var cwHz: Int
    var phoneHz: Int
    var digitalHz: Int

    func hz(for mode: ModeClass) -> Int {
        switch mode {
        case .cw: cwHz
        case .phone: phoneHz
        case .digital: digitalHz
        }
    }

    mutating func set(_ hz: Int, for mode: ModeClass) {
        switch mode {
        case .cw: cwHz = hz
        case .phone: phoneHz = hz
        case .digital: digitalHz = hz
        }
    }

    /// N1MM's 300 Hz for CW and digital. Phone is wider than N1MM's 300: RBN
    /// does not skim SSB, and human SSB spots are posted to the kHz or
    /// half-kHz, so 300 Hz misses a station you can plainly hear.
    static let defaultTolerance = TuningDistances(cwHz: 300, phoneHz: 1000, digitalHz: 300)

    /// Far enough that dodging QRM stays in Run; near enough that hunting
    /// does not. This app's own — N1MM leaves Run at the tolerance.
    static let defaultLeaveRun = TuningDistances(cwHz: 1000, phoneHz: 3000, digitalHz: 1000)
}
```

`Sources/Core/Spotting/SpotStatus.swift`:

```swift
import Foundation

/// What a spot is worth right now — the band map's three colours, and the
/// colour of the ghost call in the entry field.
///
/// N1MM Logger+ (Bandmap window, "Colors of the Incoming Spots", fetched
/// 2026-08-15): "Blue: Will be a good QSO, not a multiplier / Red: Single
/// Multiplier / Gray: Dupe". Green (double multiplier) is not drawn: a QSO
/// party contact carries one location.
enum SpotStatus: Equatable, Sendable {
    /// Worked on this band and mode, or superseded by a later spot — grey.
    case worked
    /// Unworked, and the location the app knows for the station would still
    /// add a multiplier — red.
    case neededMultiplier
    /// Unworked, not a multiplier — or location unknown — blue.
    case unworked
}
```

- [ ] **Step 3: Regenerate the project and run the tests**

```bash
xcodegen generate
```

Then the one-class test command with `TuningPolicyTests`. Expected: every `Test Case ... passed`, `** TEST SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/Core/Engine/TuningPolicy.swift Sources/Core/Spotting/SpotStatus.swift Tests/Core/TuningPolicyTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "tuning: TuningPolicy — zones round the CQ frequency, and the mode change they drive

N1MM's Run/S+P switching on the CQ-frequency marker, with a leave distance
of its own above the tuning tolerance so a QRM dodge stays in Run. Edge-
triggered so ⌘R is never fought. TuningDistances carries one Hz value per
mode class (N1MM's Configurer keeps three); SpotStatus names the three
colours.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `SpotStore.nearest`

**Files:**
- Modify: `Sources/Core/Spotting/SpotStore.swift` (after `next(in:afterKHz:direction:...)`, before the closing brace)
- Test: `Tests/Core/SpottingTests.swift` (append after `testNextSpotUpDownWithWrap`)

- [ ] **Step 1: Write the failing tests**

Append inside `SpottingTests`, after the `// MARK: Next/previous spot navigation` tests:

```swift
    // MARK: The spot under the VFO (call frame)

    /// N1MM: "if a station on the Bandmap is within the tuning tolerance, its
    /// call will be placed in the Entry window's call-frame."
    func testNearestWithinToleranceIsTheSpotUnderTheVFO() {
        let spots = [
            spot(call: "A1AA", freqKHz: 14005.0),
            spot(call: "B1BB", freqKHz: 14026.1),
            spot(call: "C1CC", freqKHz: 14026.5),
        ]
        XCTAssertEqual(SpotStore.nearest(in: spots, toKHz: 14026.2, withinHz: 300)?.call, "B1BB")
        XCTAssertEqual(SpotStore.nearest(in: spots, toKHz: 14026.4, withinHz: 300)?.call, "C1CC")
    }

    func testNothingWithinToleranceMeansNoSpot() {
        let spots = [spot(call: "A1AA", freqKHz: 14005.0)]
        XCTAssertNil(SpotStore.nearest(in: spots, toKHz: 14005.4, withinHz: 300))
        XCTAssertNil(SpotStore.nearest(in: [], toKHz: 14005.0, withinHz: 300))
    }

    func testTheToleranceBoundaryIsInside() {
        let spots = [spot(call: "A1AA", freqKHz: 14005.0)]
        XCTAssertEqual(SpotStore.nearest(in: spots, toKHz: 14005.3, withinHz: 300)?.call, "A1AA")
        XCTAssertEqual(SpotStore.nearest(in: spots, toKHz: 14004.7, withinHz: 300)?.call, "A1AA")
    }

    /// A call the board has already corrected is not somewhere to point the
    /// operator, exactly as ⌘↑/⌘↓ skip it.
    func testSupersededSpotsAreNeverUnderTheVFO() {
        var busted = spot(call: "B1BB", freqKHz: 14026.1)
        busted.isSuperseded = true
        let spots = [busted, spot(call: "C1CC", freqKHz: 14026.3)]
        XCTAssertEqual(SpotStore.nearest(in: spots, toKHz: 14026.1, withinHz: 300)?.call, "C1CC")
    }

    /// Two spots at one frequency: the one still worth working shows.
    func testATieGoesToTheUnworkedStation() {
        let spots = [spot(call: "A1AA", freqKHz: 14026.1), spot(call: "B1BB", freqKHz: 14026.1)]
        XCTAssertEqual(
            SpotStore.nearest(in: spots, toKHz: 14026.1, withinHz: 300, workedCalls: ["A1AA"])?.call,
            "B1BB"
        )
        XCTAssertEqual(
            SpotStore.nearest(in: spots, toKHz: 14026.1, withinHz: 300)?.call,
            "A1AA", "both unworked: by call, so the answer is stable between polls"
        )
    }
```

- [ ] **Step 2: Run to verify they fail**

One-class test command with `SpottingTests`. Expected: build error `type 'SpotStore' has no member 'nearest'`.

- [ ] **Step 3: Implement**

In `Sources/Core/Spotting/SpotStore.swift`, after the closing brace of `next(in:afterKHz:direction:workedCalls:workedCallCounties:)` and before the class's closing brace, add:

```swift
    /// The spot the VFO is sitting on: the nearest within `withinHz`, or nil.
    /// This is N1MM's call frame — "if a station on the Bandmap is within
    /// the tuning tolerance, its call will be placed in the Entry window's
    /// call-frame" (Entry window, fetched 2026-08-15).
    ///
    /// Worked stations are included — N1MM shows a dupe in grey so "You can
    /// tune by them more quickly" — but lose a tie to an unworked one. A
    /// superseded call is skipped outright, as `next` skips it. The last
    /// tie-break is the call, so two polls at one frequency agree.
    nonisolated static func nearest(
        in spots: [Spot],
        toKHz vfoKHz: Double,
        withinHz toleranceHz: Int,
        workedCalls: Set<String> = [],
        workedCallCounties: Set<String> = []
    ) -> Spot? {
        // 0.1 Hz of slack: 14040.3 − 14040.0 is 0.30000000000068 in binary.
        let toleranceKHz = Double(toleranceHz) / 1000 + 0.0001
        func distance(_ spot: Spot) -> Double { abs(spot.freqKHz - vfoKHz) }
        func worked(_ spot: Spot) -> Bool {
            SpotFilter.isWorked(spot, workedCalls: workedCalls, workedCallCounties: workedCallCounties)
        }
        return spots
            .filter { !$0.isSuperseded && distance($0) <= toleranceKHz }
            .min { a, b in
                let da = distance(a), db = distance(b)
                if abs(da - db) > 0.0001 { return da < db }
                let aWorked = worked(a), bWorked = worked(b)
                if aWorked != bWorked { return !aWorked }
                return a.call < b.call
            }
    }
```

- [ ] **Step 4: Run to verify they pass**

One-class test command with `SpottingTests`. Expected: `** TEST SUCCEEDED **`, the five new cases listed as passed.

- [ ] **Step 5: Commit**

```bash
git add Sources/Core/Spotting/SpotStore.swift Tests/Core/SpottingTests.swift
git commit -m "spotting: SpotStore.nearest — the spot under the VFO

N1MM's call frame rule: the nearest spot within the tuning tolerance, worked
or not, superseded never; a tie goes to the unworked station, then to the
call so two polls agree.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: `StationMemory.knownLocation` and the prefill refactor

**Files:**
- Modify: `Sources/Core/Engine/StationMemory.swift`
- Modify: `Sources/App/EntryFlow.swift:578-626` (`refreshPrefill`), and add a helper next to `callHistoryCandidate`
- Test: `Tests/Core/StationMemoryTests.swift` (append)

- [ ] **Step 1: Write the failing tests**

Append inside `StationMemoryTests`, before the final closing brace:

```swift
    // MARK: knownLocation — the chain the band map colours by

    /// This log, then the archive, then the call history file — the order the
    /// exchange pre-fill uses, so a red spot is one whose county will land in
    /// the exchange field.
    func testKnownLocationPrefersThisLogOverTheCallHistoryFile() {
        let history = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY KS
        K5NA,,SED,
        """)
        let known = StationMemory.knownLocation(
            call: "K5NA", log: [qso(call: "K5NA", their: "MIA")], index: .empty,
            callHistory: history, party: ksqp, role: .outOfState
        )
        XCTAssertEqual(known?.text, "MIA")
        XCTAssertEqual(known?.source, .thisLog)
    }

    func testKnownLocationFallsBackToTheCallHistoryFile() {
        let history = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY KS
        K5NA,,SED,
        """)
        let known = StationMemory.knownLocation(
            call: "K5NA", log: [], index: .empty,
            callHistory: history, party: ksqp, role: .outOfState
        )
        XCTAssertEqual(known?.text, "SED")
        XCTAssertEqual(known?.source, .callHistory)
    }

    func testKnownLocationUsesTheArchiveBeforeTheFile() {
        let history = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY KS
        K5NA,,SED,
        """)
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "MIA", party: "ksqp", year: 2025, county: true)]
        ])
        let known = StationMemory.knownLocation(
            call: "K5NA", log: [], index: index,
            callHistory: history, party: ksqp, role: .outOfState
        )
        XCTAssertEqual(known?.text, "MIA")
        XCTAssertEqual(known?.source, .archive(partyID: "ksqp", year: 2025))
    }

    func testKnownLocationIsNilWhenNothingIsKnown() {
        XCTAssertNil(StationMemory.knownLocation(
            call: "K5NA", log: [], index: .empty, callHistory: nil, party: ksqp, role: .outOfState
        ))
        let unrelated = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        W0BH,,BAR,
        """)
        XCTAssertNil(StationMemory.knownLocation(
            call: "K5NA", log: [], index: .empty, callHistory: unrelated, party: ksqp, role: .outOfState
        ))
    }
```

- [ ] **Step 2: Run to verify they fail**

One-class test command with `StationMemoryTests`. Expected: build error `type 'StationMemory' has no member 'knownLocation'`.

- [ ] **Step 3: Implement in `StationMemory`**

In `Sources/Core/Engine/StationMemory.swift`, change `Source`:

```swift
    /// Where a candidate came from, for the operator to judge it by.
    enum Source: Equatable, Sendable {
        case thisLog
        case archive(partyID: String, year: Int)
        /// The party's call history file — a curated community roster of what
        /// a station usually sends; third-party, and last season's.
        case callHistory
    }
```

Then, after the closing brace of `candidate(call:log:index:party:role:)` and before `parses(...)`, add:

```swift
    /// The best location the app can offer for `call` from everything it has:
    /// this log and the archive (`candidate`), then the party's call history
    /// file. The exchange pre-fill and the band map's colours both read this,
    /// so a red spot is exactly one whose county the entry row would offer.
    /// Nil when nothing usable is known — the map then says "location unknown"
    /// rather than guessing.
    static func knownLocation(
        call: String,
        log: [QSO],
        index: Index,
        callHistory: CallHistoryFile.Parsed?,
        party: PartyDefinition,
        role: ExchangeParser.Role
    ) -> Candidate? {
        if let remembered = candidate(call: call, log: log, index: index, party: party, role: role) {
            return remembered
        }
        guard let callHistory,
              let history = CallHistoryFile.candidate(for: call, in: callHistory, party: party, role: role),
              let exchange = history.exchange
        else { return nil }
        return Candidate(text: exchange, source: .callHistory)
    }
```

(Find the `parses` helper with `grep -n "static func parses\|private static func parses" Sources/Core/Engine/StationMemory.swift`; the new function goes above it, inside the enum.)

- [ ] **Step 4: Route `refreshPrefill` through it**

In `Sources/App/EntryFlow.swift`, in `refreshPrefill`, replace this block:

```swift
            if entry.exchange.isEmpty || entry.exchangeIsAutoFilled {
                if let candidate = StationMemory.candidate(
                    call: call,
                    log: document.log.qsos,
                    index: archiveIndex,
                    party: party,
                    role: role
                ) {
                    entry.autoFillExchange(candidate.text)
                } else if let exchange = history?.exchange {
                    // The community's roster of what this station sends —
                    // curated, but still third-party and last season's, so it
                    // ranks below anything we copied ourselves.
                    entry.autoFillExchange(exchange, origin: .callHistory)
                } else if let hint = spotCountyHint, hint.call == call {
```

with:

```swift
            if entry.exchange.isEmpty || entry.exchangeIsAutoFilled {
                // This log, the archive, then the call history file — the
                // community's roster ranks below anything we copied ourselves.
                // The band map colours spots by the same call, so a red spot
                // is one whose county lands here.
                if let known = StationMemory.knownLocation(
                    call: call,
                    log: document.log.qsos,
                    index: archiveIndex,
                    callHistory: callHistoryParsed(for: party),
                    party: party,
                    role: role
                ) {
                    entry.autoFillExchange(
                        known.text,
                        origin: known.source == .callHistory ? .callHistory : .ownLog
                    )
                } else if let hint = spotCountyHint, hint.call == call {
```

and add, directly below `callHistoryCandidate(call:party:role:)`:

```swift
    /// The party's parsed call history file, or nil when the one loaded is
    /// another party's (the download may land after a party change).
    private func callHistoryParsed(for party: PartyDefinition) -> CallHistoryFile.Parsed? {
        guard let callHistoryIndex, callHistoryIndex.partyID == party.id else { return nil }
        return callHistoryIndex.parsed
    }
```

`history` (from `callHistoryCandidate`) is still used below for the name and member chains — leave that line alone.

- [ ] **Step 5: Run the memory tests and the prefill suites**

One-class test command with `StationMemoryTests`, then with `CallHistoryPrefillTests`, then with `SpotExchangePrefillTests`. Expected: all three `** TEST SUCCEEDED **` — the refactor changes no entry-row behaviour.

- [ ] **Step 6: Commit**

```bash
git add Sources/Core/Engine/StationMemory.swift Sources/App/EntryFlow.swift Tests/Core/StationMemoryTests.swift
git commit -m "memory: StationMemory.knownLocation — this log, the archive, then the call history file

One chain for the exchange pre-fill and, next, the band map's colours, so a
red spot is exactly one whose county the entry row would offer.
refreshPrefill routes through it; the prefill suites are unchanged.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: `RepeatCQPolicy.continues(in:)`

**Files:**
- Modify: `Sources/App/RepeatCQPolicy.swift`
- Test: `Tests/App/RepeatCQPolicyTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append inside `RepeatCQPolicyTests`, before the final closing brace:

```swift
    /// N1MM: Repeat CQ "is automatically turned off when no longer on the
    /// CQ-frequency and the mode changed to S&P." Leaving Run — by ⌘R or by
    /// tuning off the CQ frequency — takes the loop down; left running, its
    /// next pass would key S&P's F1, which is "my call", not a CQ.
    func testTheLoopContinuesOnlyInRun() {
        XCTAssertTrue(RepeatCQPolicy.continues(in: .run))
        XCTAssertFalse(RepeatCQPolicy.continues(in: .searchPounce))
    }
```

- [ ] **Step 2: Run to verify it fails**

One-class test command with `RepeatCQPolicyTests`. Expected: build error `has no member 'continues'`.

- [ ] **Step 3: Implement**

In `Sources/App/RepeatCQPolicy.swift`, after `onSend(...)` inside the enum:

```swift
    /// Whether the loop may go on in `mode`. Only Run: leaving it — by ⌘R or
    /// by tuning off the CQ frequency — takes the loop down, or its next pass
    /// would re-resolve slot 0 against the S&P set and key "my call" every
    /// few seconds. N1MM: the function "is automatically turned off when no
    /// longer on the CQ-frequency and the mode changed to S&P."
    static func continues(in mode: OperatingMode) -> Bool {
        mode == .run
    }
```

- [ ] **Step 4: Run to verify it passes**

One-class test command with `RepeatCQPolicyTests`. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/RepeatCQPolicy.swift Tests/App/RepeatCQPolicyTests.swift
git commit -m "repeat CQ: the loop continues only in Run

N1MM turns Repeat CQ off when the mode changes to S&P; ours kept running and
would have keyed S&P's F1 on its next pass.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: The call frame in `EntryState` and `EntryFlow`

**Files:**
- Modify: `Sources/App/EntryState.swift`
- Modify: `Sources/App/EntryFlow.swift`
- Create: `Tests/App/CallFrameTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/App/CallFrameTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// N1MM's call frame, in the entry row: the spot under the VFO while
/// searching, taken by Space or by Return under ESM ("Hitting the space bar
/// (or Enter, in ESM) will pull the call-sign from the call-frame into the
/// Call-sign textbox" — Entry window, fetched 2026-08-15), and erased again
/// when the VFO tunes away ("any call-sign captured into the Entry window's
/// call-frame or brought into the Entry window's call-sign textbox will be
/// erased" — Bandmap window). Typed text is never touched by tuning.
@MainActor
final class CallFrameTests: XCTestCase {

    // MARK: Fixtures

    /// A KSQP log, out-of-state TX, searching — the state the frame lives in.
    private func ksqpFlow() -> EntryFlow {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        doc.log.operatingMode = .searchPounce
        return EntryFlow(document: doc)
    }

    /// CW, radio connected, ESM on unless said otherwise, cursor in the call
    /// field unless said otherwise.
    private func context(
        cursor: ESM.Cursor = .call, esm: Bool = true, offersSpotCounty: Bool = true
    ) -> EntryFlow.Context {
        EntryFlow.Context(
            band: .m40, modeClass: .cw, rawMode: "CW", freqKHz: 7040,
            radioConnected: true, cursor: cursor,
            keying: KeyingSettings(esmEnabled: esm),
            offersSpotCounty: offersSpotCounty
        )
    }

    private func hubSpot(_ call: String = "W0BH", county: String? = "MRN", kHz: Double = 7040.0) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: "N0AX", comment: "",
             receivedAt: Date(), county: county, source: .hub)
    }

    // MARK: Taking the frame

    func testSpaceTakesTheFrameIntoAnEmptyCallField() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        XCTAssertTrue(flow.takeCallFrame(context()))

        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertTrue(flow.entry.callIsAutoFilled, "the app put it there")
        XCTAssertEqual(flow.entry.exchange, "MRN", "the spot's county comes with it")
        XCTAssertTrue(flow.entry.exchangeIsUnconfirmed, "as a stranger's claim, marked so")
    }

    func testTheCountyIsNotOfferedWhenTheOptionIsOff() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        XCTAssertTrue(flow.takeCallFrame(context(offersSpotCounty: false)))
        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertEqual(flow.entry.exchange, "")
    }

    /// N1MM: "When the call-sign textbox is empty, pressing the space bar will
    /// copy the call-sign" — and only then.
    func testAFieldWithTextInItIsNeverOverwritten() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        flow.entry.callTyped = "K5"
        XCTAssertFalse(flow.takeCallFrame(context()))
        XCTAssertEqual(flow.entry.call, "K5")
    }

    func testNoFrameNothingToTake() {
        let flow = ksqpFlow()
        XCTAssertFalse(flow.takeCallFrame(context()))
        XCTAssertEqual(flow.entry.call, "")
    }

    /// The frame never writes the field by itself.
    func testTheFrameByItselfLeavesTheFieldEmpty() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        XCTAssertEqual(flow.entry.callFrame?.call, "W0BH")
        XCTAssertEqual(flow.entry.call, "")
        flow.updateCallFrame(nil)
        XCTAssertNil(flow.entry.callFrame)
    }

    // MARK: Return under ESM

    /// One Return fills the row and calls him: S&P with the cursor in the
    /// call field is F1, my call — the same message Return sends on an empty
    /// row, now with the call in the field.
    func testReturnUnderESMInTheEmptyCallFieldTakesTheFrameAndCalls() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        let outcome = flow.returnPressed(context(cursor: .call), undoManager: nil)

        XCTAssertEqual(outcome, .send(index: 0, transmission: .cw("KE5CW")))
        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertEqual(flow.entry.exchange, "MRN")
    }

    /// From any other field the frame stays put: with the county pre-filled
    /// the row could be loggable, and the cursor in the exchange field is what
    /// ESM reads as "I have him". The call field never logs, which is why it
    /// alone may take the frame.
    func testReturnFromTheExchangeFieldLeavesTheFrameAlone() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        let outcome = flow.returnPressed(context(cursor: .exchange), undoManager: nil)

        XCTAssertEqual(outcome, .send(index: 0, transmission: .cw("KE5CW")), "the empty-row F1, as before")
        XCTAssertEqual(flow.entry.call, "", "not taken")
        XCTAssertEqual(flow.entry.callFrame?.call, "W0BH", "still on offer")
    }

    /// Outside ESM, Return logs — so it must not first fill a row that would
    /// then be loggable. N1MM: "(or Enter, in ESM)".
    func testReturnWithoutESMLeavesTheFrameAlone() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())

        let outcome = flow.returnPressed(context(cursor: .call, esm: false), undoManager: nil)

        XCTAssertEqual(outcome, .nothing)
        XCTAssertEqual(flow.entry.call, "")
    }

    // MARK: Ownership of the call

    func testStationChangedMarksTheCallAppFilledAndTypingTakesItBack() {
        let flow = ksqpFlow()
        flow.stationChanged(to: "W0BH", context(), spotCounty: nil, atKHz: 7040.0)
        XCTAssertTrue(flow.entry.callIsAutoFilled)

        flow.entry.callTyped = "W0BHX"
        XCTAssertFalse(flow.entry.callIsAutoFilled, "the first keystroke makes it the operator's")
    }

    func testClearingForTheNextContactResetsTheMark() {
        let flow = ksqpFlow()
        flow.stationChanged(to: "W0BH", context(), spotCounty: nil, atKHz: 7040.0)
        flow.entry.clearForNextContact(modeClass: .cw)
        XCTAssertFalse(flow.entry.callIsAutoFilled)
        XCTAssertEqual(flow.entry.call, "")
    }

    // MARK: hasOperatorText

    func testAFreshRowHasNoOperatorText() {
        let flow = ksqpFlow()
        flow.entry.applyDefaults(modeClass: .cw)
        XCTAssertFalse(flow.entry.hasOperatorText)
    }

    func testAnAppFilledRowHasNoOperatorText() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot())
        _ = flow.takeCallFrame(context())
        XCTAssertEqual(flow.entry.exchange, "MRN", "precondition: county auto-filled")
        XCTAssertFalse(flow.entry.hasOperatorText, "call and county are both the app's")
    }

    func testEachTypedFieldCountsAsOperatorText() {
        let fresh = { () -> EntryState in
            let entry = EntryState()
            entry.applyDefaults(modeClass: .cw)
            return entry
        }
        var entry = fresh(); entry.callTyped = "K"
        XCTAssertTrue(entry.hasOperatorText, "typed call")
        entry = fresh(); entry.exchangeTyped = "M"
        XCTAssertTrue(entry.hasOperatorText, "typed exchange")
        entry = fresh(); entry.nameTyped = "T"
        XCTAssertTrue(entry.hasOperatorText, "typed name")
        entry = fresh(); entry.memberTyped = "1"
        XCTAssertTrue(entry.hasOperatorText, "typed member element")
        entry = fresh(); entry.serialRcvd = "1"
        XCTAssertTrue(entry.hasOperatorText, "received number")
        entry = fresh(); entry.theirParkTyped = "US-1"
        XCTAssertTrue(entry.hasOperatorText, "park")
        entry = fresh(); entry.serialSent = "7"
        XCTAssertTrue(entry.hasOperatorText, "sent number override")
        entry = fresh(); entry.rstRcvd = "579"
        XCTAssertTrue(entry.hasOperatorText, "a report changed from the default")
        entry = fresh(); entry.autoFillExchange("MRN", origin: .spot); entry.autoFillName("BOB")
        XCTAssertFalse(entry.hasOperatorText, "auto-filled text is the app's")
    }

    // MARK: Erasing what was taken

    func testTuningAwayErasesAnAppFilledRow() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot(kHz: 7040.0))
        _ = flow.takeCallFrame(context())
        XCTAssertEqual(flow.entry.call, "W0BH", "precondition")

        flow.tunedAway(toKHz: 7040.2, toleranceKHz: 0.3, context())
        XCTAssertEqual(flow.entry.call, "W0BH", "still within tolerance — zero-beating him")

        flow.tunedAway(toKHz: 7040.4, toleranceKHz: 0.3, context())
        XCTAssertEqual(flow.entry.call, "", "erased")
        XCTAssertEqual(flow.entry.exchange, "", "and the county the app offered with it")
        XCTAssertFalse(flow.entry.callIsAutoFilled)
    }

    /// The same for a spot click or ⌘↑/⌘↓ — every app-filled call.
    func testTuningAwayErasesACallFromASpotClick() {
        let flow = ksqpFlow()
        flow.stationChanged(to: "W0BH", context(), spotCounty: "MRN", atKHz: 7040.0)
        flow.tunedAway(toKHz: 7041.0, toleranceKHz: 0.3, context())
        XCTAssertEqual(flow.entry.call, "")
    }

    func testTypedTextIsNeverErasedByTuning() {
        let flow = ksqpFlow()
        flow.updateCallFrame(hubSpot(kHz: 7040.0))
        _ = flow.takeCallFrame(context())
        flow.entry.exchangeTyped = "MRN"   // he copied it himself

        flow.tunedAway(toKHz: 7041.0, toleranceKHz: 0.3, context())

        XCTAssertEqual(flow.entry.call, "W0BH", "he has engaged with this station")
        XCTAssertEqual(flow.entry.exchange, "MRN")

        let typed = ksqpFlow()
        typed.entry.callTyped = "K5ABC"
        typed.tunedAway(toKHz: 7041.0, toleranceKHz: 0.3, context())
        XCTAssertEqual(typed.entry.call, "K5ABC", "a typed call is not the app's to erase")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodegen generate
```

One-class test command with `CallFrameTests`. Expected: build errors — `extra argument 'offersSpotCounty'`, `no member 'updateCallFrame'`, etc.

- [ ] **Step 3: `EntryState` — ownership of the call, `hasOperatorText`, `callFrame`**

In `Sources/App/EntryState.swift`, replace

```swift
    var call = ""
```

with

```swift
    var call = ""

    /// Whether `call` holds text the app put there — a spot click, ⌘↑/⌘↓,
    /// or the call frame — rather than text the operator typed. The same
    /// ownership rule as the exchange, name and member: tuning away may take
    /// back only what the app wrote, and never what was typed.
    private(set) var callIsAutoFilled = false

    /// The call as the operator edits it; the entry field binds here, never
    /// to `call`. Writing through it is what makes the text theirs.
    var callTyped: String {
        get { call }
        set {
            call = newValue
            callIsAutoFilled = false
        }
    }

    func autoFillCall(_ text: String) {
        call = text
        callIsAutoFilled = !text.isEmpty
    }

    /// N1MM's call frame: the spot the VFO is sitting on while searching. Drawn
    /// as a ghost in the empty call field and taken by Space, or by Return
    /// under ESM. It never writes `call` by itself — "When the call-sign
    /// textbox is empty, pressing the space bar will copy the call-sign from
    /// the call-frame to the call-sign textbox" (Entry window, fetched
    /// 2026-08-15).
    var callFrame: Spot?

    /// Whether the row holds anything the operator typed: a call, exchange,
    /// name or member element that is not auto-filled, a received number, a
    /// park, a sent-number override, or a report changed from the default.
    /// The one question the erase rule asks — a row the operator has engaged
    /// with is never cleared by tuning.
    var hasOperatorText: Bool {
        if !call.isEmpty, !callIsAutoFilled { return true }
        if !exchange.isEmpty, !exchangeIsAutoFilled { return true }
        if !nameRcvd.isEmpty, !nameIsAutoFilled { return true }
        if !memberRcvd.isEmpty, !memberIsAutoFilled { return true }
        if !serialRcvd.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if !theirParkTyped.trimmingCharacters(in: .whitespaces).isEmpty { return true }
        if hasSerialOverride { return true }
        let defaults = Set(ModeClass.allCases.map(\.defaultRST))
        if !rstSent.isEmpty, !defaults.contains(rstSent) { return true }
        if !rstRcvd.isEmpty, !defaults.contains(rstRcvd) { return true }
        return false
    }
```

In `clearForNextContact(modeClass:)`, change the first line `call = ""` to:

```swift
        call = ""
        callIsAutoFilled = false
```

- [ ] **Step 4: `EntryFlow` — the context flag, station bookkeeping, the frame, the erase rule, Return**

In `Sources/App/EntryFlow.swift`:

(a) In `struct Context`, after `var phoneSource: PhoneSource`, add:

```swift
        /// Whether a spot's county is offered into the exchange when a
        /// station arrives from the call frame — the band map's "Offer the
        /// spotted county as the exchange" option. Defaulted on, so every
        /// context built before the frame existed means what it did.
        var offersSpotCounty: Bool
```

and in the `init`, add the parameter `offersSpotCounty: Bool = true` after `phoneSource: PhoneSource = .radioMemories`, and the assignment `self.offersSpotCounty = offersSpotCounty` after `self.phoneSource = phoneSource`.

(b) In `returnPressed`, change

```swift
        if let command = EntryCommand.parse(entry.call) {
            entry.call = ""
```

to

```swift
        if let command = EntryCommand.parse(entry.call) {
            entry.callTyped = ""
```

and after

```swift
        guard esmDrivesReturn(context) else {
            return logContact(context, undoManager: undoManager)
        }
```

insert

```swift
        // N1MM: "Hitting the space bar (or Enter, in ESM) will pull the
        // call-sign from the call-frame into the Call-sign textbox." Only from
        // the call field — it never logs, so filling it here is always safe;
        // from the exchange field ESM reads the cursor as "I have him", and a
        // row filled with a county could log on the same keystroke.
        if context.cursor == .call, entry.callNormalized.isEmpty {
            takeCallFrame(context)
        }
```

(c) Replace `stationChanged` (the whole function, keeping its doc comment) with:

```swift
    func stationChanged(
        to call: String, _ context: Context, spotCounty: String? = nil, atKHz: Double? = nil
    ) {
        stashPending()
        entry.exchangeTyped = ""
        entry.serialRcvd = ""
        entry.nameTyped = ""
        entry.memberTyped = ""
        entry.autoFillCall(call)
        // Where the app filled it, for the erase rule; nil when nobody arrived.
        autoFilledCallKHz = entry.callIsAutoFilled ? atKHz : nil
        // Tied to the call it arrived with, so typing over a busted spot does
        // not carry the old station's county to the new one.
        spotCountyHint = spotCounty
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .flatMap { $0.isEmpty ? nil : (call: entry.callNormalized, county: $0) }
        refreshPrefill(context)
        revalidate(context)
    }

    /// The station left the row without a contact — the VFO moved on. The
    /// same bookkeeping as arriving at a new one, with nobody arriving.
    func stationLeft(_ context: Context) {
        stationChanged(to: "", context)
    }

    /// The frequency the app filled the call at — a spot's, from the frame, a
    /// click or ⌘↑/⌘↓. Compared with the VFO by `tunedAway`.
    private var autoFilledCallKHz: Double?

    // MARK: The call frame

    /// The spot under the VFO, or nil. Written by the view on every VFO
    /// change while searching; never touches the call field.
    func updateCallFrame(_ spot: Spot?) {
        if entry.callFrame != spot { entry.callFrame = spot }
    }

    /// Space, or Return under ESM, in an empty call field: the frame's call
    /// goes into the field and its county — when the option is on — into the
    /// exchange, exactly as a spot click arrives. False when there is nothing
    /// to take or the field already holds text, typed or filled.
    @discardableResult
    func takeCallFrame(_ context: Context) -> Bool {
        guard entry.callNormalized.isEmpty, let spot = entry.callFrame else { return false }
        stationChanged(
            to: spot.call, context,
            spotCounty: context.offersSpotCounty ? spot.county : nil,
            atKHz: spot.freqKHz
        )
        return true
    }

    /// N1MM: "If you tune the VFO outside that range, any call-sign captured
    /// into the Entry window's call-frame or brought into the Entry window's
    /// call-sign textbox will be erased." Here: a call the app filled, once the
    /// VFO is more than the tolerance from where it was filled, and only while
    /// the row holds nothing the operator typed. Typed text is never touched
    /// by tuning.
    func tunedAway(toKHz vfoKHz: Double, toleranceKHz: Double, _ context: Context) {
        guard entry.callIsAutoFilled, !entry.hasOperatorText,
              let filledAt = autoFilledCallKHz,
              abs(vfoKHz - filledAt) > toleranceKHz + 0.0001
        else { return }
        stationLeft(context)
    }
```

(d) In `clearEntry(_:)`, add `autoFilledCallKHz = nil` before `entry.clearForNextContact(...)`.

- [ ] **Step 5: Run to verify they pass**

One-class test command with `CallFrameTests`. Expected: `** TEST SUCCEEDED **`, every case passed. Then `EntryFlowTests`, `SpotExchangePrefillTests`, `CallHistoryPrefillTests`, `EntryClassTests` — all `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/App/EntryState.swift Sources/App/EntryFlow.swift Tests/App/CallFrameTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "entry: the call frame — the spot under the VFO, taken by Space or Return under ESM

N1MM's call-frame: it never writes the field itself; Space, or Return with
the cursor in the empty call field under ESM, pulls the call in and offers
the county; the same Return then calls him. A call the app filled — frame,
spot click, ⌘↑/⌘↓ — is erased when the VFO tunes more than the tolerance
away and nothing was typed. callIsAutoFilled / callTyped / hasOperatorText
carry the ownership rule the exchange already had.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: `AppSettings` — the five tuning preferences

**Files:**
- Modify: `Sources/App/AppSettings.swift`
- Create: `Tests/App/TuningPreferenceTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/App/TuningPreferenceTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// The tuning preferences behind the band map's TUNING section — defaults,
/// persistence under their own keys, and the JSON round trip of the per-mode
/// distances.
final class TuningPreferenceTests: XCTestCase {

    /// A fixed suite name — `removePersistentDomain` leaves the plist behind,
    /// so a per-run UUID would litter Preferences (see PreferenceIsolationTests).
    private func scratchStore(seeding seed: [String: Any] = [:]) throws -> UserDefaults {
        let suiteName = "org.b5n.QSOPartyLogger.tests.tuning"
        UserDefaults().removePersistentDomain(forName: suiteName)
        addTeardownBlock { UserDefaults().removePersistentDomain(forName: suiteName) }
        let scratch = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        for (key, value) in seed { scratch.set(value, forKey: key) }
        return scratch
    }

    @MainActor
    func testAnEmptyStoreHasEverythingOnAtN1MMsDistances() throws {
        let settings = AppSettings(defaults: try scratchStore())
        XCTAssertTrue(settings.callFrameEnabled)
        XCTAssertTrue(settings.autoLeaveRun)
        XCTAssertTrue(settings.autoReturnToRun)
        XCTAssertEqual(settings.tuningToleranceHz, .defaultTolerance)
        XCTAssertEqual(settings.leaveRunDistanceHz, .defaultLeaveRun)
    }

    @MainActor
    func testTheTogglesPersistUnderTheirOwnKeys() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.callFrameEnabled = false
        settings.autoLeaveRun = false
        settings.autoReturnToRun = false
        XCTAssertEqual(scratch.object(forKey: "callFrameEnabled") as? Bool, false)
        XCTAssertEqual(scratch.object(forKey: "autoLeaveRun") as? Bool, false)
        XCTAssertEqual(scratch.object(forKey: "autoReturnToRun") as? Bool, false)
        let reread = AppSettings(defaults: scratch)
        XCTAssertFalse(reread.callFrameEnabled)
        XCTAssertFalse(reread.autoLeaveRun)
        XCTAssertFalse(reread.autoReturnToRun)
    }

    @MainActor
    func testTheDistancesAreReadBackOnTheNextLaunch() throws {
        let scratch = try scratchStore()
        let settings = AppSettings(defaults: scratch)
        settings.tuningToleranceHz.set(500, for: .phone)
        settings.leaveRunDistanceHz.set(2000, for: .cw)
        XCTAssertNotNil(scratch.data(forKey: "tuningToleranceHz"))
        XCTAssertNotNil(scratch.data(forKey: "leaveRunDistanceHz"))
        let reread = AppSettings(defaults: scratch)
        XCTAssertEqual(reread.tuningToleranceHz.hz(for: .phone), 500)
        XCTAssertEqual(reread.tuningToleranceHz.hz(for: .cw), 300, "untouched modes keep their default")
        XCTAssertEqual(reread.leaveRunDistanceHz.hz(for: .cw), 2000)
    }

    /// A hand-edited or downgraded preference file falls back to the defaults
    /// rather than to nothing.
    @MainActor
    func testUnreadableDistancesFallBackToTheDefaults() throws {
        let scratch = try scratchStore(seeding: ["tuningToleranceHz": Data("garbage".utf8)])
        XCTAssertEqual(AppSettings(defaults: scratch).tuningToleranceHz, .defaultTolerance)
    }

    @MainActor
    func testNothingLeaksIntoTheAppWideStore() throws {
        let scratch = try scratchStore()
        AppSettings(defaults: scratch).callFrameEnabled = false
        XCTAssertNil(Preferences.store.object(forKey: "callFrameEnabled"),
                     "an injected store must not write through to the app-wide one")
    }
}
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodegen generate
```

One-class test command with `TuningPreferenceTests`. Expected: build errors `no member 'callFrameEnabled'` etc.

- [ ] **Step 3: Implement**

In `Sources/App/AppSettings.swift`, directly after the `followBandPlan` property (`var followBandPlan: Bool { didSet { ... } }`), add:

```swift
    // MARK: Tuning — the band map's TUNING section

    /// The spot under the VFO shows as a ghost call in the empty call field
    /// while searching; Space or Return (ESM) takes it. N1MM's call frame.
    var callFrameEnabled: Bool {
        didSet { defaults.set(callFrameEnabled, forKey: "callFrameEnabled") }
    }

    /// Tuning past the leave-Run distance from the CQ frequency switches to
    /// S&P. N1MM: "QSYing will switch to S&P mode. Press Alt+F11 to disable
    /// this automatic mode change."
    var autoLeaveRun: Bool {
        didSet { defaults.set(autoLeaveRun, forKey: "autoLeaveRun") }
    }

    /// Tuning back within the tolerance of the CQ frequency switches to Run.
    /// Off is N1MM's "Do not automatically switch to Run on CQ-frequency".
    var autoReturnToRun: Bool {
        didSet { defaults.set(autoReturnToRun, forKey: "autoReturnToRun") }
    }

    /// How close the VFO must be to a spot for the call frame, and to the CQ
    /// frequency to be "on" it — per mode class, as N1MM's Configurer has it.
    var tuningToleranceHz: TuningDistances {
        didSet {
            if let data = try? JSONEncoder().encode(tuningToleranceHz) {
                defaults.set(data, forKey: "tuningToleranceHz")
            }
        }
    }

    /// How far off the CQ frequency counts as leaving it. Larger than the
    /// tolerance so a QRM dodge stays in Run.
    var leaveRunDistanceHz: TuningDistances {
        didSet {
            if let data = try? JSONEncoder().encode(leaveRunDistanceHz) {
                defaults.set(data, forKey: "leaveRunDistanceHz")
            }
        }
    }
```

In `init(defaults:)`, directly after `followBandPlan = defaults.object(forKey: "followBandPlan") as? Bool ?? true`, add:

```swift
        callFrameEnabled = defaults.object(forKey: "callFrameEnabled") as? Bool ?? true
        autoLeaveRun = defaults.object(forKey: "autoLeaveRun") as? Bool ?? true
        autoReturnToRun = defaults.object(forKey: "autoReturnToRun") as? Bool ?? true
        // Unreadable data falls back to the defaults rather than to nothing.
        tuningToleranceHz = defaults.data(forKey: "tuningToleranceHz")
            .flatMap { try? JSONDecoder().decode(TuningDistances.self, from: $0) }
            ?? .defaultTolerance
        leaveRunDistanceHz = defaults.data(forKey: "leaveRunDistanceHz")
            .flatMap { try? JSONDecoder().decode(TuningDistances.self, from: $0) }
            ?? .defaultLeaveRun
```

- [ ] **Step 4: Run to verify they pass**

One-class test command with `TuningPreferenceTests`. Expected: `** TEST SUCCEEDED **`. Also `PreferenceIsolationTests` — `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppSettings.swift Tests/App/TuningPreferenceTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "settings: the tuning preferences — call frame, leave Run, return to Run, and the two distances

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: `BandMapModel` colours, verdicts and caches; the map's drawing; the TUNING section

**Files:**
- Modify: `Sources/UI/BandMap.swift`
- Create: `Tests/App/BandMapStatusTests.swift`
- Modify: `Tests/App/BandMapObservationTests.swift` (append one test)

- [ ] **Step 1: Write the failing tests**

Create `Tests/App/BandMapStatusTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// The band map's three colours — N1MM's "Blue: Will be a good QSO, not a
/// multiplier / Red: Single Multiplier / Gray: Dupe" (Bandmap window, fetched
/// 2026-08-15) — and where a cluster spot's location comes from: this log, the
/// archive, the call history file, in that order, so a red spot is exactly one
/// whose county lands in the exchange field on tuning to it.
///
/// ALQP counts multipliers per mode, which is what lets "worked on phone" leave
/// a CW spot red.
@MainActor
final class BandMapStatusTests: XCTestCase {

    private func model() throws -> BandMapModel {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let model = BandMapModel(
            radio: RadioController(),
            spotStore: SpotStore(),
            settings: AppSettings.shared
        )
        model.party = alqp
        var log = ContestLog(partyID: alqp.id)
        log.myLocation = .outOfState(location: "TX")
        model.log = log
        model.allowedModes = alqp.allowedModeClasses
        return model
    }

    /// 7030: unambiguously CW on 40 m.
    private func clusterSpot(_ call: String = "K4EES", kHz: Double = 7030) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: "W3LPL", comment: "", receivedAt: Date())
    }

    private func hubSpot(_ call: String, county: String, kHz: Double = 7030) -> Spot {
        Spot(call: call, freqKHz: kHz, spotter: "N4EMP", comment: "",
             receivedAt: Date(), county: county, source: .hub)
    }

    private func qso(_ call: String, _ county: String, band: Band = .m20,
                     modeClass: ModeClass = .cw) -> QSO {
        QSO(call: call, band: band, modeClass: modeClass,
            rawMode: modeClass == .phone ? "USB" : "CW",
            rstSent: modeClass.defaultRST, rstRcvd: modeClass.defaultRST,
            myLoc: "TX", theirLoc: county)
    }

    // MARK: Cluster spots — where the location comes from

    func testAClusterSpotNobodyKnowsIsBlueWithNoVerdict() throws {
        let model = try model()
        XCTAssertNil(model.verdict(for: clusterSpot()))
        XCTAssertEqual(model.status(for: clusterSpot()), .unworked)
    }

    func testThisLogColoursAClusterSpotRed() throws {
        let model = try model()
        var log = try XCTUnwrap(model.log)
        log.qsos = [qso("K4EES", "BALD", band: .m20, modeClass: .phone)]   // Baldwin counted on phone only
        model.log = log

        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertEqual(verdict.location, "BALD")
        XCTAssertEqual(verdict.source, .thisLog)
        XCTAssertTrue(verdict.needed, "ALQP counts per mode: Baldwin on CW is still open")
        XCTAssertEqual(model.status(for: clusterSpot()), .neededMultiplier)
    }

    func testACountyAlreadyCountedMakesItBlue() throws {
        let model = try model()
        var log = try XCTUnwrap(model.log)
        log.qsos = [qso("K4EES", "BALD", band: .m20, modeClass: .cw)]      // Baldwin counted on CW
        model.log = log

        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertFalse(verdict.needed)
        XCTAssertEqual(model.status(for: clusterSpot()), .unworked, "a good QSO, not a multiplier")
    }

    func testTheArchiveColoursAClusterSpotRed() throws {
        let model = try model()
        model.archiveIndex = StationMemory.Index(byCall: [
            "K4EES": [StationMemory.ArchiveEntry(
                call: "K4EES", theirLoc: "BALD", partyID: "alqp", year: 2025,
                timestampUTC: Date(timeIntervalSince1970: 1_750_000_000), isCountyOfItsParty: true
            )]
        ])
        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertEqual(verdict.location, "BALD")
        XCTAssertEqual(verdict.source, .archive)
        XCTAssertTrue(verdict.needed)
    }

    func testTheCallHistoryFileColoursAClusterSpotRed() throws {
        let model = try model()
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        # QSOPARTY AL
        K4EES,,BALD,
        """)
        let verdict = try XCTUnwrap(model.verdict(for: clusterSpot()))
        XCTAssertEqual(verdict.location, "BALD")
        XCTAssertEqual(verdict.source, .callHistory)
        XCTAssertTrue(verdict.needed)
    }

    // MARK: Hub spots keep their own county

    func testAHubSpotUsesItsOwnCountyEvenWhenTheLogRemembersAnother() throws {
        let model = try model()
        var log = try XCTUnwrap(model.log)
        log.qsos = [qso("K4EES", "MDSN")]                                   // worked in Madison earlier
        model.log = log

        let verdict = try XCTUnwrap(model.verdict(for: hubSpot("K4EES", county: "BALD")))
        XCTAssertEqual(verdict.location, "BALD", "the spot is where he is now")
        XCTAssertEqual(verdict.source, .spot)
        XCTAssertTrue(verdict.needed)
        XCTAssertTrue(model.isNeededMultiplier(hubSpot("K4EES", county: "BALD")), "the old entry point agrees")
    }

    // MARK: Grey wins

    func testWorkedWinsOverNeeded() throws {
        let model = try model()
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        K4EES,,BALD,
        """)
        model.workedCalls = ["K4EES"]
        XCTAssertEqual(model.status(for: clusterSpot()), .worked)
        var busted = clusterSpot("W4XYZ")
        busted.isSuperseded = true
        XCTAssertEqual(model.status(for: busted), .worked, "superseded draws grey too")
    }

    // MARK: Caches follow their inputs

    func testANewCallHistoryFileChangesTheAnswer() throws {
        let model = try model()
        XCTAssertNil(model.verdict(for: clusterSpot()))
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        K4EES,,BALD,
        """)
        XCTAssertEqual(model.verdict(for: clusterSpot())?.location, "BALD", "the memo was dropped")
    }
}
```

Append inside `BandMapObservationTests`, before its final closing brace:

```swift
    /// The same rule for the location memo behind a cluster spot's colour: the
    /// first read computes and stores it, and that store must not invalidate
    /// the view either.
    func testReadingAClusterSpotsColourDoesNotInvalidateTheView() throws {
        let alqp = try XCTUnwrap(PartyCatalog.party(id: "alqp"))
        let model = model(party: alqp)
        model.callHistory = CallHistoryFile.parse("""
        !!Order!!,Call,Name,Exch1,UserText,
        K4EES,,BALD,
        N4UC,,MDSN,
        """)
        let cluster = { (call: String, kHz: Double) in
            Spot(call: call, freqKHz: kHz, spotter: "W3LPL", comment: "", receivedAt: Date())
        }

        final class Flag: @unchecked Sendable { var tripped = false }
        let invalidated = Flag()

        withObservationTracking {
            _ = model.status(for: cluster("K4EES", 7030))
        } onChange: {
            invalidated.tripped = true
        }
        _ = model.status(for: cluster("N4UC", 7032))
        _ = model.status(for: cluster("WA1FCN", 7034))

        XCTAssertFalse(invalidated.tripped,
                       "classifying a spot invalidated the view — the render loop again")
    }
```

- [ ] **Step 2: Run to verify they fail**

```bash
xcodegen generate
```

One-class test command with `BandMapStatusTests`. Expected: build errors `no member 'verdict'`, `'archiveIndex'`, `'callHistory'`.

- [ ] **Step 3: `BandMapModel` — inputs, verdict, status, caches**

In `Sources/UI/BandMap.swift`, inside `BandMapModel`:

Replace

```swift
    var party: PartyDefinition? {
        didSet { neededMultiplierCache = [:] }
    }
    var log: ContestLog? {
        didSet { neededMultiplierCache = [:] }
    }
```

with

```swift
    var party: PartyDefinition? {
        didSet { dropCaches() }
    }
    var log: ContestLog? {
        didSet { dropCaches() }
    }
    /// Previous contests, and the party's call history file — what a cluster
    /// spot's location is looked up in when it carries none. Set by MainView
    /// wherever it sets the flow's; the file is already checked against the
    /// party there.
    var archiveIndex = StationMemory.Index.empty {
        didSet { dropCaches() }
    }
    var callHistory: CallHistoryFile.Parsed? {
        didSet { dropCaches() }
    }
```

Replace the `neededMultiplierCache` declaration (keep its long comment above it) with:

```swift
    @ObservationIgnored private var neededMultiplierCache: [String: Bool] = [:]
    /// Call → what the app knows of its location, nil included — the second
    /// memo under the same rule. A dictionary of optionals so "looked up,
    /// nothing known" is remembered too, and not re-derived every render.
    @ObservationIgnored private var locationCache: [String: Located?] = [:]

    private func dropCaches() {
        neededMultiplierCache = [:]
        locationCache = [:]
    }
```

Replace `isNeededMultiplier(_:)` (the whole function and its doc comment) with:

```swift
    /// Where a spot's location came from, for the tooltip and for how far to
    /// trust it. A hub or local spot names its own county; a cluster spot is
    /// looked up the way the exchange pre-fill looks the call up.
    enum LocationSource: Equatable, Sendable {
        case spot, thisLog, archive, callHistory

        init(_ source: StationMemory.Source) {
            switch source {
            case .thisLog: self = .thisLog
            case .archive: self = .archive
            case .callHistory: self = .callHistory
            }
        }
    }

    struct LocationVerdict: Equatable, Sendable {
        let location: String
        let source: LocationSource
        /// Whether that location would still add a multiplier on the spot's
        /// band and mode.
        let needed: Bool
    }

    private struct Located: Equatable {
        let location: String
        let source: LocationSource
    }

    /// The location the app knows for this spot's station and whether it is a
    /// multiplier still worth chasing — nil when nothing is known, which the
    /// map draws blue and calls "location unknown".
    ///
    /// A hub or local spot carries a county and uses it: the spot is where he
    /// is *now*, which for a rover outranks where the log last had him. A
    /// cluster spot carries none, so `StationMemory.knownLocation` resolves
    /// the call — this log, the archive, the call history file — the same
    /// chain the exchange pre-fill uses, so a red spot is exactly one whose
    /// county will land in the exchange field.
    ///
    /// `wouldAddMultiplier` honours the party's scored-multiplier ceiling, so
    /// this never sends the operator after a multiplier that pays nothing.
    /// Memoised per call and per location+band+mode; see the caches.
    func verdict(for spot: Spot) -> LocationVerdict? {
        guard let party, let log, let band = spot.band else { return nil }
        let located: Located?
        if let county = spot.county, !county.isEmpty {
            located = Located(location: county, source: .spot)
        } else {
            located = knownLocation(call: spot.call, log: log, party: party)
        }
        guard let located else { return nil }
        let mode = SpotFilter.modeClass(freqKHz: spot.freqKHz, comment: spot.comment,
                                        allowedModes: allowedModes)
        let key = "\(located.location)|\(band.rawValue)|\(mode.rawValue)"
        let needed: Bool
        if let cached = neededMultiplierCache[key] {
            needed = cached
        } else {
            needed = ScoreEngine.wouldAddMultiplier(
                theirLocs: [located.location], band: band, modeClass: mode, log: log, party: party
            )
            neededMultiplierCache[key] = needed
        }
        return LocationVerdict(location: located.location, source: located.source, needed: needed)
    }

    private func knownLocation(call: String, log: ContestLog, party: PartyDefinition) -> Located? {
        let key = call.uppercased()
        if let cached = locationCache[key] { return cached }
        let role: ExchangeParser.Role = log.myLocation.isInState ? .inState : .outOfState
        let known = StationMemory.knownLocation(
            call: key, log: log.qsos, index: archiveIndex, callHistory: callHistory,
            party: party, role: role
        )
        let located = known.map { Located(location: $0.text, source: LocationSource($0.source)) }
        // updateValue, not subscript assignment: assigning nil would remove
        // the key, and "nothing known" is exactly what is worth remembering.
        locationCache.updateValue(located, forKey: key)
        return located
    }

    /// Whether this spot's county is a multiplier still worth chasing.
    func isNeededMultiplier(_ spot: Spot) -> Bool {
        verdict(for: spot)?.needed ?? false
    }

    /// The colour: grey for worked or superseded, red for a needed
    /// multiplier, blue otherwise. Read by the map for every spot and by the
    /// entry bar for the ghost call, so the two never disagree.
    func status(for spot: Spot) -> SpotStatus {
        if spot.isSuperseded || isWorked(spot) { return .worked }
        return verdict(for: spot)?.needed == true ? .neededMultiplier : .unworked
    }
```

- [ ] **Step 4: Run the model tests**

One-class test command with `BandMapStatusTests`, then `BandMapObservationTests`. Expected: both `** TEST SUCCEEDED **`.

- [ ] **Step 5: Draw the colours**

Still in `Sources/UI/BandMap.swift`. Add, at file scope after the `BandMapModel` class (before `struct BandMapView`):

```swift
extension SpotStatus {
    /// N1MM's scheme: "Blue: Will be a good QSO, not a multiplier / Red:
    /// Single Multiplier / Gray: Dupe".
    var color: Color {
        switch self {
        case .worked: .secondary
        case .neededMultiplier: .red
        case .unworked: .blue
        }
    }
}
```

In `BandMapView.header`, give the band label the legend:

```swift
            Text(model.band.rawValue)
                .font(.headline)
                .help("Red — a multiplier you still need. Blue — unworked, not a multiplier "
                      + "(or nobody knows where he is). Grey — worked on this band and mode, "
                      + "or superseded. A cluster spot's county comes from your log, previous "
                      + "contests or the party's call history file — the same places the "
                      + "exchange pre-fill looks.")
```

In `map(size:)`, replace the spot `ForEach` body's first two lines and the label so that it reads:

```swift
            ForEach(placements(scale: scale, size: size)) { row in
                let status = model.status(for: row.spot)
                let verdict = model.verdict(for: row.spot)
                let needed = status == .neededMultiplier
                Button {
                    model.onTuneSpot?(row.spot)
                } label: {
                    HStack(spacing: 3) {
                        Circle().frame(width: 5, height: 5)
                        Text(row.spot.call)
                            .font(.system(size: CGFloat(labelSize.callPointSize),
                                          design: .monospaced).weight(.semibold))
                            .strikethrough(status == .worked)
                        // The county is the whole reason the hub feed exists —
                        // a cluster spot never carries one.
                        if let county = row.spot.county, !county.isEmpty {
                            Text(county)
                                .font(.system(size: CGFloat(labelSize.countyPointSize),
                                              design: .monospaced))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(needed ? Color.red.opacity(0.18)
                                                     : Color.secondary.opacity(0.15))
                                )
                                .foregroundStyle(needed ? Color.red : Color.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if model.canSpot {
                        Button("Spot \(row.spot.call)…") {
                            model.onSpotStation?(row.spot)
                        }
                    }
                }
                .foregroundStyle(status.color)
                .opacity(row.spot.isSuperseded ? 0.45 : 1)
                .offset(
                    x: rulerWidth + labelInset
                        + CGFloat(row.column) * CGFloat(labelSize.columnWidth),
                    y: CGFloat(row.y) - CGFloat(labelSize.verticalOffset)
                )
                .help(helpText(for: row.spot, status: status, verdict: verdict))
            }
```

Delete `spotColor(worked:spot:)` and replace `helpText(for:worked:needed:)` with:

```swift
    /// Everything the label had no room for. The reconstructed-frequency and
    /// superseded notes are warnings, not decoration: one means the frequency
    /// was inferred rather than read, the other that the board has already
    /// corrected this call. The location line says where the app got it, so a
    /// red spot from last season's roster reads as exactly that.
    private func helpText(for spot: Spot, status: SpotStatus, verdict: BandMapModel.LocationVerdict?) -> String {
        var parts = [String(format: "%.1f de %@", spot.freqKHz, spot.spotter)]
        if !spot.comment.isEmpty { parts.append("(\(spot.comment))") }
        if let verdict {
            let origin = switch verdict.source {
            case .spot: ""
            case .thisLog: " (your log)"
            case .archive: " (a previous contest)"
            case .callHistory: " (call history)"
            }
            parts.append(verdict.location + origin
                         + (verdict.needed ? " — NEW MULTIPLIER" : " — already counted"))
        } else if spot.county == nil {
            parts.append("location unknown")
        }
        if spot.source == .hub { parts.append("via QSO Party Hub") }
        if spot.source == .local { parts.append("from your own log — nobody spotted him") }
        if spot.frequencyConfidence == .reconstructed {
            parts.append("frequency reconstructed from a malformed entry — verify before calling")
        }
        if spot.isSuperseded {
            parts.append("a later spot on this frequency corrected this call")
        }
        parts.append(status == .worked ? "already worked on this band and mode" : "click to tune")
        return parts.joined(separator: " — ")
    }
```

- [ ] **Step 6: The TUNING section in the filters popover**

In `filtersPopover`, after the BAND PLAN block (the `Toggle("Follow band plan on QSY", ...)` and its `.help`) and before the `Divider()` that precedes the Reset All row, insert:

```swift
            Divider()
            Text("TUNING")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Toggle("Show the spot under the VFO as a ghost call (S&P)", isOn: $settings.callFrameEnabled)
                .help("Searching, the nearest visible spot within the tuning tolerance appears in "
                      + "the empty call field in the map's colour for it — Space, or Return under "
                      + "ESM, takes it and its county. Tuning further than the tolerance away erases "
                      + "a call the app put there; typed text is never touched. N1MM's call frame.")
            Toggle("Leave Run when the VFO moves off your CQ frequency", isOn: $settings.autoLeaveRun)
                .help("Past the leave-Run distance below you are hunting, so the mode goes to S&P — "
                      + "a QRM dodge inside it keeps you in Run. F1 in Run remembers the CQ frequency; "
                      + "⌘J jumps back to it. Leaving Run stops Repeat CQ.")
            Toggle("Return to Run when it comes back", isOn: $settings.autoReturnToRun)
                .help("Tuning back within the tolerance of your CQ frequency puts you in Run again — "
                      + "N1MM's default. Off, only F1, ⌘R and ⌘J switch to Run "
                      + "(N1MM's \"Do not automatically switch to Run on CQ-frequency\").")
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                GridRow {
                    Text("")
                    ForEach(ModeClass.allCases) { mode in
                        Text(mode.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                GridRow {
                    Text("Spot within").font(.caption)
                    ForEach(ModeClass.allCases) { mode in
                        distancePicker(
                            binding: toleranceBinding(mode, settings: settings),
                            choices: Self.toleranceChoices
                        )
                    }
                }
                GridRow {
                    Text("Leave Run at").font(.caption)
                    ForEach(ModeClass.allCases) { mode in
                        distancePicker(
                            binding: leaveRunBinding(mode, settings: settings),
                            choices: Self.leaveRunChoices
                        )
                    }
                }
            }
            .help("The tuning tolerance (N1MM's Configurer keeps one per mode, 300 Hz each; "
                  + "phone is wider here because SSB spots are posted to the kHz) and how far off "
                  + "your CQ frequency counts as leaving it.")
```

Widen the popover: change `.frame(width: 290)` at the end of `filtersPopover` to `.frame(width: 330)`.

Extend Reset All. Replace the Reset All button's action and `.disabled` with:

```swift
                Button("Reset All") {
                    settings.northAmericanSpottersOnly = false
                    settings.northAmericanStationsOnly = false
                    settings.hideWorkedSpots = false
                    settings.hideSkimmerSpots = false
                    settings.spotModes = []
                    settings.spotBands = []
                    settings.spotMaxAgeMinutes = 15
                    settings.followBandPlan = true
                    settings.callFrameEnabled = true
                    settings.autoLeaveRun = true
                    settings.autoReturnToRun = true
                    settings.tuningToleranceHz = .defaultTolerance
                    settings.leaveRunDistanceHz = .defaultLeaveRun
                }
                .disabled(!model.filtersActive && settings.spotMaxAgeMinutes == 15
                          && settings.followBandPlan && tuningAtDefaults)
```

Add these helpers to `BandMapView`, next to `hubOnlyBinding`:

```swift
    private static let toleranceChoices = [100, 200, 300, 500, 1000, 2000]
    private static let leaveRunChoices = [500, 1000, 2000, 3000, 5000, 10000]

    private var tuningAtDefaults: Bool {
        let settings = model.settings
        return settings.callFrameEnabled && settings.autoLeaveRun && settings.autoReturnToRun
            && settings.tuningToleranceHz == .defaultTolerance
            && settings.leaveRunDistanceHz == .defaultLeaveRun
    }

    private static func hzLabel(_ hz: Int) -> String {
        hz < 1000 ? "\(hz) Hz" : String(format: "%g kHz", Double(hz) / 1000)
    }

    /// A menu of the usual values — plus whatever is stored, so a hand-edited
    /// preference still shows rather than a blank control.
    private func distancePicker(binding: Binding<Int>, choices: [Int]) -> some View {
        let all = choices.contains(binding.wrappedValue) ? choices : (choices + [binding.wrappedValue]).sorted()
        return Picker("", selection: binding) {
            ForEach(all, id: \.self) { hz in
                Text(Self.hzLabel(hz)).tag(hz)
            }
        }
        .labelsHidden()
        .controlSize(.small)
        .frame(width: 70)
    }

    private func toleranceBinding(_ mode: ModeClass, settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.tuningToleranceHz.hz(for: mode) },
            set: { settings.tuningToleranceHz.set($0, for: mode) }
        )
    }

    private func leaveRunBinding(_ mode: ModeClass, settings: AppSettings) -> Binding<Int> {
        Binding(
            get: { settings.leaveRunDistanceHz.hz(for: mode) },
            set: { settings.leaveRunDistanceHz.set($0, for: mode) }
        )
    }
```

- [ ] **Step 7: Build, then run the model tests again**

Build-only command. Expected: `** BUILD SUCCEEDED **`, no `error:`. If the type-checker complains about `filtersPopover` ("unable to type-check this expression in reasonable time"), extract the new TUNING block into `@ViewBuilder private var tuningSection: some View { ... }` (with `@Bindable var settings = model.settings` at its top) and call `tuningSection` in its place — the same seam pattern MainView uses.

Then one-class test command with `BandMapStatusTests` and `BandMapObservationTests`. Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Sources/UI/BandMap.swift Tests/App/BandMapStatusTests.swift Tests/App/BandMapObservationTests.swift QSOPartyLogger.xcodeproj/project.pbxproj
git commit -m "band map: red, blue, grey — what a spot is worth, and where the app learnt it

N1MM's colours: red a multiplier still needed, blue a good QSO, grey worked
or superseded. A cluster spot's county comes from this log, the archive or
the call history file — StationMemory.knownLocation, the exchange pre-fill's
own chain — so a red spot is one whose county lands in the exchange field.
Two non-observable memos, dropped when their inputs change. The TUNING
section: ghost call, leave Run, return to Run, and the two distances per
mode.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 8: `EntryBar` ghost and Space; `MainView` wiring

**Files:**
- Modify: `Sources/UI/EntryBar.swift`
- Modify: `Sources/UI/MainView.swift`

- [ ] **Step 1: `EntryBar` — bind `callTyped`, draw the ghost, let Space take it**

In `Sources/UI/EntryBar.swift`, after `let showsP2P: Bool` (and its comment) add:

```swift
    /// The colour of the ghost call — the band map's colour for the spot under
    /// the VFO — and what Space does when the empty call field shows one.
    /// Defaulted so a bar built without a band map (the caret tests) is the
    /// bar it always was.
    var callFrameColor: Color = .secondary
    var onTakeCallFrame: () -> Void = {}
```

Change the call field line to:

```swift
                field("Call", text: $entry.callTyped, width: 140, focusTag: .call,
                      ghost: entry.call.isEmpty ? entry.callFrame.map { (text: $0.call, color: callFrameColor) } : nil)
```

Change the `field(...)` builder's signature to:

```swift
    private func field(
        _ label: String,
        text: Binding<String>,
        width: CGFloat,
        focusTag: Field,
        provisional: Bool = false,
        ghost: (text: String, color: Color)? = nil
    ) -> some View {
```

and inside it, after `.frame(width: width)`, add:

```swift
                // N1MM's call frame, drawn inside the field: the spot the VFO
                // is on, in the map's colour for it, while the field is empty.
                // Not interactive — Space or Return takes it.
                .overlay(alignment: .leading) {
                    if let ghost {
                        Text(ghost.text)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(ghost.color)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                            .accessibilityLabel("Spot under the VFO: \(ghost.text)")
                    }
                }
```

Replace the `.onKeyPress(.space)` closure body with:

```swift
                .onKeyPress(.space) {
                    // An empty call field showing a ghost: Space takes it —
                    // "if a call is in the callframe, space will load it into
                    // the call textbox" — and stays put. Otherwise it advances.
                    if focusTag == .call, entry.call.isEmpty, entry.callFrame != nil {
                        onTakeCallFrame()
                        return .handled
                    }
                    focus = focusTag.next(
                        includesRST: party?.exchangeIncludesRST ?? true,
                        includesSerial: party?.exchangeIncludesSerial ?? false,
                        includesName: party?.exchangeIncludesName ?? false,
                        includesMember: party?.memberExchange != nil
                    )
                    return .handled
                }
```

Update the file's header comment (`/// N1MM-style entry row: ...`) to mention the ghost call: append the line `/// The empty call field shows the spot under the VFO as a ghost call (N1MM's call frame); Space, or Return under ESM, takes it.`

- [ ] **Step 2: `MainView` — state, context, seams**

In `Sources/UI/MainView.swift`:

(a) After `@State private var cqFrequencyHz: Int?` add:

```swift
    /// Which side of the CQ frequency the VFO was on at the last report — on
    /// it, near it, or away — so only a *change* of zone switches the mode
    /// (`TuningPolicy`). Reset to `.onFrequency` when a CQ frequency is
    /// captured; nil when there is none.
    @State private var cqZone: TuningPolicy.Zone?
```

(b) In `operatingContext`, add `offersSpotCounty: settings.prefillExchangeFromSpots` after `phoneSource: phoneSource`.

(c) Replace the `RadioBar(...)` expression and its nine `.onChange`s inside `leftPaneContent` with a single `radioBar`, and add the seam directly above `leftPaneContent`:

```swift
    /// The radio bar with the radio-driven wiring — frequency, band, mode,
    /// speed, connection, and the voice path — pulled out of `leftPaneContent`
    /// so that VStack stays under the type-checker's budget (2026-08-04).
    private var radioBar: some View {
        RadioBar(
            settings: settings,
            radio: radio,
            party: party,
            manualBand: $manualBand,
            manualRawMode: $manualRawMode
        )
        .onChange(of: radio.radioState?.band) { revalidate() }
        .onChange(of: radio.radioState?.rawMode) { modeChanged() }
        // The knob: Run ⇄ S&P round the CQ frequency, and the call frame.
        .onChange(of: radio.radioState?.frequencyHz) { vfoMoved() }
        .onChange(of: radio.radioReportedWPM) { syncSpeedFromRadio() }
        .onChange(of: repeatCQ) { repeatCQChanged() }
        .onChange(of: radio.isConnected) { if !radio.isConnected { stopRepeat() } }
        // The recordings path re-derives from the voice settings while
        // connected; `connect` derives it itself.
        .onChange(of: settings.voiceOutputDeviceUID) { radio.refreshVoicePath(settings: settings) }
        .onChange(of: settings.voicePTT) { radio.refreshVoicePath(settings: settings) }
        .onChange(of: settings.phoneMessageSource) { radio.refreshVoicePath(settings: settings) }
        // The flow reads recordings by value, like the call history file.
        .onChange(of: voiceStore.rendered) { flow.voiceRecordings = voiceStore.rendered }
    }
```

so `leftPaneContent` begins:

```swift
    private var leftPaneContent: some View {
        VStack(spacing: 0) {
            radioBar
            Divider()
```

(d) In `leftPaneContent`, change the `stationStrip` chain's QSO line to:

```swift
                .onChange(of: document.log.qsos) {
                    autoSaveAfterChange()
                    // Every change to the log changes which multipliers are
                    // still needed — including a row deleted on another band.
                    bandMapModel?.log = document.log
                }
```

and the `EntryBar(...)` construction to:

```swift
            EntryBar(entry: entry, party: party, showsP2P: !document.log.myPotaRefs.isEmpty,
                     callFrameColor: callFrameColor, onTakeCallFrame: takeCallFrame,
                     onLog: returnPressed, focus: $focusedField)
```

(e) In `leftPaneSpotWired`, change the CQ-frequency line to:

```swift
        .onChange(of: cqFrequencyHz) {
            bandMapModel?.cqKHz = cqFrequencyHz.map { Double($0) / 1000 }
            cqZone = cqFrequencyHz == nil ? nil : .onFrequency
        }
```

(f) Add a third seam between `leftPaneSpotWired` and `leftPane`, and point `leftPane` at it:

```swift
    /// The mode and tuning wiring — its own seam for the same type-checker
    /// reason as the other two.
    private var leftPaneTuningWired: some View {
        leftPaneSpotWired
        // Leaving Run — by ⌘R or by tuning off the CQ frequency — takes Repeat
        // CQ down (N1MM: turned off "when … the mode changed to S&P"), and
        // the call frame follows the mode: empty in Run.
        .onChange(of: document.log.operatingMode) { operatingModeChanged() }
        .onChange(of: settings.callFrameEnabled) { refreshCallFrame() }
    }

    private var leftPane: some View {
        leftPaneTuningWired
```

(the rest of `leftPane`'s chain is unchanged).

- [ ] **Step 3: `MainView` — the follower functions**

Add, after `jumpToCQFrequency()` in the `// MARK: CQ frequency memory` section:

```swift
    // MARK: Following the knob — Run ⇄ S&P, and the call frame

    /// Every frequency the radio reports. The zone check runs first so a turn
    /// that leaves Run can seed the call frame in the same pass.
    private func vfoMoved() {
        guard let hz = radio.radioState?.frequencyHz else {
            cqZone = nil
            flow.updateCallFrame(nil)
            return
        }
        followCQFrequency(vfoHz: hz)
        followSpots(vfoHz: hz)
    }

    /// N1MM: on the CQ frequency you are in Run and QSYing switches to S&P;
    /// tuning back within tolerance switches to Run. `TuningPolicy` decides,
    /// edge-triggered, so ⌘R is never fought.
    private func followCQFrequency(vfoHz: Int) {
        guard let cq = cqFrequencyHz else {
            cqZone = nil
            return
        }
        let zone = TuningPolicy.zone(
            vfoHz: vfoHz, cqHz: cq,
            toleranceHz: settings.tuningToleranceHz.hz(for: currentModeClass),
            leaveHz: settings.leaveRunDistanceHz.hz(for: currentModeClass)
        )
        if let mode = TuningPolicy.modeChange(
            from: cqZone, to: zone, mode: operatingMode.wrappedValue,
            leaveEnabled: settings.autoLeaveRun, returnEnabled: settings.autoReturnToRun
        ) {
            operatingMode.wrappedValue = mode
        }
        cqZone = zone
    }

    /// The call frame: searching, the nearest visible spot within the tuning
    /// tolerance — the list ⌘↑/⌘↓ step through, so a hidden worked station
    /// never ghosts. First the erase rule for a call the app filled earlier,
    /// then the frame for wherever the VFO is now.
    private func followSpots(vfoHz: Int) {
        guard settings.callFrameEnabled, operatingMode.wrappedValue == .searchPounce else {
            flow.updateCallFrame(nil)
            return
        }
        let vfoKHz = Double(vfoHz) / 1000
        let toleranceHz = settings.tuningToleranceHz.hz(for: currentModeClass)
        flow.tunedAway(toKHz: vfoKHz, toleranceKHz: Double(toleranceHz) / 1000, operatingContext)
        flow.updateCallFrame(SpotStore.nearest(
            in: visibleSpotsOnBand,
            toKHz: vfoKHz,
            withinHz: toleranceHz,
            workedCalls: workedCallsOnCurrentBandMode,
            workedCallCounties: workedCallCountiesOnCurrentBandMode
        ))
    }

    /// Recompute the frame from where the radio is now — after the option or
    /// the mode changes rather than the VFO.
    private func refreshCallFrame() {
        guard let hz = radio.radioState?.frequencyHz else {
            flow.updateCallFrame(nil)
            return
        }
        followSpots(vfoHz: hz)
    }

    private func operatingModeChanged() {
        if !RepeatCQPolicy.continues(in: operatingMode.wrappedValue) {
            stopRepeat()
        }
        refreshCallFrame()
    }

    /// Space in the empty call field, with a ghost showing.
    private func takeCallFrame() {
        guard flow.takeCallFrame(operatingContext) else { return }
        focusedField = .call
    }

    /// The ghost call's colour — the band map's colour for that spot.
    private var callFrameColor: Color {
        entry.callFrame.flatMap { bandMapModel?.status(for: $0) }?.color ?? .secondary
    }
```

- [ ] **Step 4: `MainView` — feed the model, record the tune frequency, reset the zone**

(a) In `onAppear`, in the `if bandMapModel == nil {` block, after `model.log = document.log` add:

```swift
            model.archiveIndex = flow.archiveIndex
            model.callHistory = flow.callHistoryIndex?.parsed
```

(b) Change the call history callback to:

```swift
        callHistoryClient.onIndex = { [weak flow] partyID, parsed in
            guard let flow, flow.party?.id == partyID else { return }
            flow.callHistoryIndex = (partyID, parsed)
            bandMapModel?.callHistory = parsed
        }
```

(c) In `activateCallHistory()`, change `flow.callHistoryIndex = nil` to:

```swift
        flow.callHistoryIndex = nil
        bandMapModel?.callHistory = nil
```

(d) In `loadArchiveIndex()`, change `flow.archiveIndex = index` to:

```swift
            flow.archiveIndex = index
            bandMapModel?.archiveIndex = index
```

(e) In `tune(to:)`, change the `flow.stationChanged(...)` call to:

```swift
        flow.stationChanged(
            to: spot.call,
            operatingContext,
            spotCounty: settings.prefillExchangeFromSpots ? spot.county : nil,
            atKHz: spot.freqKHz
        )
```

(f) In `captureCQFrequency()`:

```swift
    private func captureCQFrequency() {
        if let hz = radio.radioState?.frequencyHz {
            cqFrequencyHz = hz
            // Captured at the VFO, so by definition on it — even when the
            // frequency is the same one as before and no `onChange` fires.
            cqZone = .onFrequency
        }
    }
```

- [ ] **Step 5: `MessagesRow` tooltip**

In `Sources/UI/MessagesRow.swift`, change the picker's `.help(...)` to:

```swift
            .help("Run = calling CQ; S&P = search and pounce. Each has its own F1–F8 set. "
                  + "Toggle Run / Search & Pounce (⌘R). Tuning off your CQ frequency switches to "
                  + "S&P and tuning back onto it switches to Run — the band map's Tuning options.")
```

- [ ] **Step 6: Build**

Build-only command. Expected: `** BUILD SUCCEEDED **`, no `error:`. If `leftPaneContent` or `leftPane` fails to type-check, move the offending `.onChange` into `leftPaneTuningWired` (it exists for exactly this) — never inline a seam back.

- [ ] **Step 7: Run the affected suites**

One-class test command with `CallFrameTests`, `EntryFlowTests`, `UppercasingFieldTests`, `BandMapStatusTests`, `ShortcutHintsTests`. Expected: every one `** TEST SUCCEEDED **`.

- [ ] **Step 8: Commit**

```bash
git add Sources/UI/EntryBar.swift Sources/UI/MainView.swift Sources/UI/MessagesRow.swift
git commit -m "tuning: the knob drives Run ⇄ S&P and the ghost call

One onChange on the reported frequency: TuningPolicy's zone check round the
CQ frequency, then the call frame — the nearest visible spot within
tolerance, drawn as a ghost in the empty call field in the map's colour,
taken by Space or Return under ESM, erased when the VFO tunes on. Leaving
Run stops Repeat CQ. The radio bar's wiring moves to its own seam.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 9: README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Features — the band map section**

In the `## Spotting and the band map` section, after the `- **Rovers stop hiding.** …` bullet, add:

```markdown
- **Colours say what a spot is worth** — N1MM's scheme. **Red**: a multiplier
  you still need. **Blue**: unworked, not a multiplier (or nobody knows where
  he is). **Grey**, struck through: worked on this band and mode, or
  superseded. A cluster spot carries no county, so the app looks the call up
  the way the exchange pre-fill does — your log, previous contests, the party's
  call history file — and a red cluster spot is one whose county lands in the
  exchange field the moment you tune to it. The tooltip says where the county
  came from.
```

After the `- **CQ frequency memory**: …` bullet, add:

```markdown
- **Run and S&P follow the knob.** Tune more than the leave-Run distance off
  your CQ frequency (1 kHz on CW and digital, 3 kHz on phone) and the mode goes
  to S&P — a QRM dodge inside it keeps you in Run; tune back within the
  tolerance and you're in Run again, F1 ready to CQ. Only a *change* of zone
  acts, so ⌘R is never fought. Leaving Run stops Repeat CQ. Both halves are
  N1MM's ("QSYing will switch to S&P mode"; back "within the tuning tolerance
  of the marker, the program will switch automatically to Run mode"), each
  with its own switch under the funnel's **Tuning** section.
- **The call frame — a ghost call.** Searching, the nearest visible spot within
  the tuning tolerance (300 Hz on CW and digital, 1 kHz on phone; settable)
  appears in the empty call field in the map's colour for it. **Space**, or
  **Return** under ESM, takes it — call and county — and that same Return then
  calls him. Type anything and the ghost is just gone. A call the app put there
  (ghost, spot click, ⌘↑/⌘↓) is erased when you tune more than the tolerance
  away without having typed anything; typed text is never touched. Off, or
  the numbers, under **Tuning**.
```

- [ ] **Step 2: Keyboard table**

Change the `Enter` row to:

```markdown
| `Enter` | Log the QSO (or send the next ESM message, or run a typed QSY command). In the empty call field under ESM with a ghost call showing, take it — call and county — and call him |
```

Change the `Space` row to:

```markdown
| `Space` | In an empty call field showing a ghost call: take it (call and county) and stay put. Otherwise cycle Call → Exchange → Call — via QSO number and Name ahead of the exchange, and the member number/power (Skeeter #, BB #) after it, where the party uses them. Signal reports are stepped over |
```

Change the `⌘R` row to:

```markdown
| `⌘R` | Toggle Run / Search & Pounce (the knob also switches: off the CQ frequency → S&P, back onto it → Run) |
```

- [ ] **Step 3: Commit (test count comes in Task 10)**

```bash
git add README.md
git commit -m "docs: colours, Run ⇄ S&P from the knob, the ghost call — features and keys

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 10: Full suite, test count, Release build

- [ ] **Step 1: Run the whole suite**

Full-suite command. Expected: `** TEST SUCCEEDED **` and a final `Executed N tests, with 0 failures`. If anything fails, fix it before going on — never report a partial run as green.

- [ ] **Step 2: Update the test count in the README**

Take `N` from the last `Executed N tests` line of the full log (`grep -E "Executed [0-9]+ tests" …/full.log | tail -1`) and replace `**2760 unit tests**` in `README.md` with `**N unit tests**`. Then:

```bash
git add README.md
git commit -m "docs: test count

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

- [ ] **Step 3: Cut a Release build to try**

```bash
set -o pipefail; xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -configuration Release -destination 'platform=macOS' build CONFIGURATION_BUILD_DIR="$PWD/build/Release" 2>&1 | tee /private/tmp/claude-501/-Users-tom-AppDev-Apple-QSOPartyLogger/4a739cfd-5af4-4313-9088-7d5b41003845/scratchpad/release.log | grep -E "error:|\*\* BUILD"
ls -d "$PWD/build/Release/QSOPartyLogger.app"
```

Expected: `** BUILD SUCCEEDED **` and the app path. Report the path to Tom; do **not** replace `/Applications/QSOPartyLogger.app` unasked. `build/` is untracked — confirm with `git status --short` that nothing under it is staged.

- [ ] **Step 4: Report**

State: the commands run and their summary lines, the test count, the app path, and what to look at on the air — spot colours on the map (and the tooltip's origin note), leaving and returning to the CQ frequency with the messages row's Run/S&P picker, the ghost call while tuning in S&P and Space / Return taking it, the TUNING section under the funnel.

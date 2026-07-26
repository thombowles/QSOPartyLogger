# Station memory and spot navigation — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five search-and-pounce fixes — the band map stops vanishing when another
app takes focus, ⌘↑/⌘↓ step spots, a history table shows every prior contact with
the call in the entry field, the exchange pre-fills from what we already know
about a station, and an exchange copied for a station who never answered is kept
under his call instead of following you to the next spot.

**Architecture:** Everything that decides anything is a pure function over values
in `Sources/Core/`, called by thin wiring in `Sources/App/` and `Sources/UI/`.
The three entry-row features are one idea — what the app knows about the station
whose call is in the field — reached through `EntryFlow`, which already owns the
seam between the entry row and the document.

**Tech Stack:** Swift 6, SwiftUI, XCTest, XcodeGen. macOS 15+.

**Spec:** `docs/superpowers/specs/2026-07-25-station-memory-and-spot-navigation-design.md`

---

## Setup

- [ ] **Step 1: Branch off master**

Implementation does not land on `master` directly.

```bash
git checkout -b feat/station-memory-and-spot-navigation
```

- [ ] **Step 2: Confirm a green baseline before changing anything**

```bash
xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`. If it is not green now, stop — nothing below
can be trusted against a red baseline.

---

## File structure

| File | Responsibility |
| --- | --- |
| `Sources/UI/BandMap.swift` | Panel construction — gains one AppKit property |
| `Sources/UI/KeyMonitorGate.swift` | The key table — gains two rows |
| `Sources/Core/Engine/DupeChecker.swift` | Prior contacts with a call, one entry per on-air contact |
| `Sources/Core/Engine/StationMemory.swift` | **new** — archive index, candidate exchange, parse guard |
| `Sources/UI/WorkedBeforeTable.swift` | **new** — the history table and its height arithmetic |
| `Sources/App/EntryState.swift` | Auto-filled vs typed exchange, per-call pending exchanges |
| `Sources/App/EntryFlow.swift` | `callChanged`, `stationChanged`, prefill resolution |
| `Sources/UI/EntryBar.swift` | Binds the exchange field through the typed accessor |
| `Sources/UI/MainView.swift` | Table placement, log-table compensation, archive load, `tune(to:)` |

`project.yml` globs `Sources` and `Tests` by path, so new files need no project
edit — only `xcodegen generate`.

---

## Task 1: Band map survives app deactivation

**Files:**
- Modify: `Sources/UI/BandMap.swift:365`
- Modify: `README.md`

No test. This is a single AppKit window property with no seam worth inventing;
the spec says so explicitly. It is verified by build, and by the operator seeing
the panel stay put.

- [ ] **Step 1: Set the property**

In `BandMapPanel.make`, immediately after the `becomesKeyOnlyIfNeeded` line:

```swift
        panel.becomesKeyOnlyIfNeeded = true  // spot clicks don't steal typing focus
        // AppKit defaults this to true for panels, which is why the map vanished
        // the moment SmartSDR took focus. A band map is for reading while you
        // work another app's panadapter, so it outlives our own activation.
        panel.hidesOnDeactivate = false
        panel.level = .floating
```

- [ ] **Step 2: Build**

```bash
xcodegen generate && xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | tail -3
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Document it**

In `README.md`, find the band map bullet that begins `- **Band map window (⌘B)**:`
and append this sentence to it:

```
  The panel stays on screen when another app takes focus, so it can sit beside
  a panadapter in SmartSDR rather than disappearing the moment you click one.
```

- [ ] **Step 4: Commit**

```bash
git add Sources/UI/BandMap.swift README.md
git commit -m "$(cat <<'EOF'
fix: band map panel stays on screen when another app takes focus

NSPanel defaults hidesOnDeactivate to true, so clicking into SmartSDR
took the band map with it — which is precisely when it is being read.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: ⌘↑ / ⌘↓ step spots

**Files:**
- Modify: `Sources/UI/KeyMonitorGate.swift:124-134`
- Test: `Tests/App/KeyMonitorGateTests.swift`
- Modify: `README.md`, `Sources/UI/MainView.swift` (help strings), `Sources/UI/BandMap.swift` (help strings)

- [ ] **Step 1: Write the failing tests**

Append to `Tests/App/KeyMonitorGateTests.swift`, inside the class:

```swift
    // MARK: Vertical spot stepping

    /// The band map draws high frequency at the top, so ⌘↑ means "up the map",
    /// which is the higher frequency — the same station ⌘→ lands on.
    func testCommandUpAndDownStepSpotsLikeCommandRightAndLeft() {
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 126, command: true), .nextSpot)
        XCTAssertEqual(KeyMonitorGate.action(keyCode: 125, command: true), .previousSpot)
        XCTAssertEqual(
            KeyMonitorGate.action(keyCode: 126, command: true),
            KeyMonitorGate.action(keyCode: 124, command: true),
            "⌘↑ and ⌘→ are the same action"
        )
        XCTAssertEqual(
            KeyMonitorGate.action(keyCode: 125, command: true),
            KeyMonitorGate.action(keyCode: 123, command: true),
            "⌘↓ and ⌘← are the same action"
        )
    }

    /// Without ⌘ the arrows belong to whatever has focus — a text field, the
    /// log table — and the monitor must not consume them.
    func testPlainArrowsAreNotOurs() {
        XCTAssertNil(KeyMonitorGate.action(keyCode: 126, command: false))
        XCTAssertNil(KeyMonitorGate.action(keyCode: 125, command: false))
    }
```

- [ ] **Step 2: Run them and watch them fail**

```bash
xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/KeyMonitorGateTests 2>&1 | grep -E "error:|failed|passed|TEST"
```

Expected: `testCommandUpAndDownStepSpotsLikeCommandRightAndLeft` fails —
`XCTAssertEqual failed: ("nil") is not equal to ("Optional(nextSpot)")`.
`testPlainArrowsAreNotOurs` already passes; that is fine, it is a guard.

- [ ] **Step 3: Add the two rows**

In `KeyMonitorGate.commandAction`, alongside the existing arrow cases:

```swift
        case 123: return .previousSpot  // ←
        case 124: return .nextSpot  // →
        // The map draws high frequency at the top, so up the map is up the band.
        case 126: return .nextSpot  // ↑
        case 125: return .previousSpot  // ↓
```

- [ ] **Step 4: Run them and watch them pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/KeyMonitorGateTests 2>&1 | grep -E "error:|failed|passed|TEST"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Update every place that names the keys**

Four help strings and one README table currently say only ⌘← / ⌘→. All become
`⌘← / ⌘→ / ⌘↑ / ⌘↓`:

1. `Sources/UI/BandMap.swift`, the `hideWorkedSpots` toggle help:
   `"Drop worked calls from the map entirely — off, they stay greyed out and ⌘← / ⌘→ / ⌘↑ / ⌘↓ steps over them"`
2. `Sources/UI/BandMap.swift`, the `followBandPlan` toggle help: replace
   `⌘← / ⌘→, ⌘J` with `⌘← / ⌘→ / ⌘↑ / ⌘↓, ⌘J`
3. `Sources/UI/MainView.swift`, the Spots toolbar button help:
   `"DX cluster connection for spots — click a spot to tune, ⌘← / ⌘→ / ⌘↑ / ⌘↓ to step"`
4. `Sources/UI/MainView.swift`, the last line of `clusterPopover`: replace
   `⌘← / ⌘→ to step through them.` with `⌘← / ⌘→ / ⌘↑ / ⌘↓ to step through them.`

In `README.md`, replace the keyboard-table row

```
| `⌘←` / `⌘→` | Tune to previous / next unworked spot on the band |
```

with

```
| `⌘←` / `⌘→` | Tune to previous / next unworked spot on the band |
| `⌘↓` / `⌘↑` | The same, on the vertical axis — ⌘↑ goes up the band map |
```

and in the band map feature bullet replace `spot-to-spot with ⌘← / ⌘→.` with
`spot-to-spot with ⌘← / ⌘→ or ⌘↓ / ⌘↑.`

- [ ] **Step 6: Full suite, then commit**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tail -5
git add -A
git commit -m "$(cat <<'EOF'
feat: ⌘↑ / ⌘↓ step spots alongside ⌘← / ⌘→

The band map draws high frequency at the top, so ⌘↑ is up the map is up
the band — the station ⌘→ already lands on. Both pairs stay bound.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Worked-before table

**Files:**
- Modify: `Sources/Core/Engine/DupeChecker.swift`
- Create: `Sources/UI/WorkedBeforeTable.swift`
- Test: `Tests/Core/DupeCheckerTests.swift`, `Tests/Core/WorkedBeforeTableTests.swift`
- Modify: `Sources/UI/MainView.swift`, `README.md`

- [ ] **Step 1: Write the failing tests for prior contacts**

Append to `Tests/Core/DupeCheckerTests.swift`, inside the class:

```swift
    // MARK: Prior contacts with a call

    func testNoPriorContactsForACallNeverWorked() {
        let log = [qso(call: "W0BH")]
        XCTAssertTrue(DupeChecker.workedContacts(call: "K5NA", log: log).isEmpty)
    }

    func testCallMatchIsCaseInsensitiveAndTrimmed() {
        let log = [qso(call: "K5NA")]
        XCTAssertEqual(DupeChecker.workedContacts(call: " k5na ", log: log).count, 1)
    }

    /// A county-line contact is one contact that produced several rows. It is
    /// one entry, and it names both counties the way the parser accepts them.
    func testCountyLineGroupCollapsesToOneEntry() {
        let group = UUID()
        var a = qso(call: "K5NA", their: "JO"); a.groupID = group
        var b = qso(call: "K5NA", their: "MI", t: 1); b.groupID = group
        let entries = DupeChecker.workedContacts(call: "K5NA", log: [a, b])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].theirLoc, "JO/MI")
    }

    func testEntriesAreMostRecentFirst() {
        let early = qso(call: "K5NA", band: .m80, t: 0)
        let late = qso(call: "K5NA", band: .m20, t: 3600)
        let entries = DupeChecker.workedContacts(call: "K5NA", log: [early, late])
        XCTAssertEqual(entries.map(\.band), [.m20, .m80])
    }

    func testEntryCarriesBandModeAndTime() {
        let q = qso(call: "K5NA", band: .m40, mode: .phone, their: "JO")
        let entries = DupeChecker.workedContacts(call: "K5NA", log: [q])
        XCTAssertEqual(entries.first?.band, .m40)
        XCTAssertEqual(entries.first?.modeClass, .phone)
        XCTAssertEqual(entries.first?.timestampUTC, q.timestampUTC)
        XCTAssertEqual(entries.first?.theirLoc, "JO")
    }
```

- [ ] **Step 2: Run them and watch them fail**

```bash
xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/DupeCheckerTests 2>&1 | grep -E "error:|TEST"
```

Expected: compile error — `type 'DupeChecker' has no member 'workedContacts'`.

- [ ] **Step 3: Implement prior contacts**

Append inside `enum DupeChecker` in `Sources/Core/Engine/DupeChecker.swift`,
after `existingDupePairs`:

```swift
    /// One prior on-air contact with a station, for the worked-before table.
    ///
    /// A county-line contact produced several log rows from one contact, so it
    /// is one entry here and carries both counties — the row of a table that
    /// answers "which bands and modes is he already in my log on" must not
    /// count one QSO twice.
    struct WorkedContact: Equatable, Identifiable, Sendable {
        /// The contact's `groupID` — stable, and unique per contact.
        let id: UUID
        let band: Band
        let modeClass: ModeClass
        let timestampUTC: Date
        /// Their location, county-line pairs joined the way the exchange
        /// parser accepts them.
        let theirLoc: String
    }

    /// Every prior contact with `call`, most recent first, across all bands and
    /// modes. Empty for a call that is blank or never worked.
    static func workedContacts(call: String, log: [QSO]) -> [WorkedContact] {
        let wanted = call.trimmingCharacters(in: .whitespaces).uppercased()
        guard !wanted.isEmpty else { return [] }

        var byGroup: [UUID: [QSO]] = [:]
        for q in log where q.call.uppercased() == wanted {
            byGroup[q.groupID, default: []].append(q)
        }

        return byGroup.values
            .compactMap { rows -> WorkedContact? in
                let ordered = rows.sortedChronologically()
                guard let first = ordered.first else { return nil }
                return WorkedContact(
                    id: first.groupID,
                    band: first.band,
                    modeClass: first.modeClass,
                    timestampUTC: first.timestampUTC,
                    theirLoc: ordered.map(\.theirLoc).joined(separator: "/")
                )
            }
            .sorted { $0.timestampUTC > $1.timestampUTC }
    }
```

- [ ] **Step 4: Run them and watch them pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/DupeCheckerTests 2>&1 | grep -E "error:|TEST"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Write the failing tests for the height arithmetic**

Create `Tests/Core/WorkedBeforeTableTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// The table takes its space from the log table, not from the window. These
/// assert the arithmetic that makes that true — a measured height would let
/// macOS grow the window the first time a match appeared, which is the one
/// thing this table must never do.
final class WorkedBeforeTableTests: XCTestCase {

    func testNothingToShowIsNoHeight() {
        XCTAssertEqual(
            WorkedBeforeTable.height(contacts: 0, hasArchiveLine: false), 0
        )
    }

    /// The archive alone is worth showing: it is where a pre-filled exchange
    /// came from when this log has never worked the station.
    func testArchiveLineAloneEarnsATable() {
        XCTAssertGreaterThan(
            WorkedBeforeTable.height(contacts: 0, hasArchiveLine: true), 0
        )
    }

    func testEachContactAddsExactlyOneRow() {
        let one = WorkedBeforeTable.height(contacts: 1, hasArchiveLine: false)
        let two = WorkedBeforeTable.height(contacts: 2, hasArchiveLine: false)
        XCTAssertEqual(two - one, WorkedBeforeTable.rowHeight)
    }

    func testGrowthStopsAtTheRowCap() {
        let cap = WorkedBeforeTable.visibleRowCap
        XCTAssertEqual(
            WorkedBeforeTable.height(contacts: cap, hasArchiveLine: false),
            WorkedBeforeTable.height(contacts: cap + 40, hasArchiveLine: false),
            "past the cap the table scrolls rather than growing"
        )
    }

    /// The invariant the window depends on: whatever the table takes, the log
    /// table gives back, so the left pane's minimum content height never moves.
    func testTablePlusLogMinimumIsInvariant() {
        for contacts in 0...12 {
            for archive in [false, true] {
                let table = WorkedBeforeTable.height(
                    contacts: contacts, hasArchiveLine: archive
                )
                XCTAssertEqual(
                    table + WorkedBeforeTable.logTableMin(tableHeight: table),
                    WorkedBeforeTable.logTableMinAlone,
                    accuracy: 0.001,
                    "\(contacts) contacts, archive line \(archive)"
                )
            }
        }
    }
}
```

- [ ] **Step 6: Run them and watch them fail**

```bash
xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/WorkedBeforeTableTests 2>&1 | grep -E "error:|TEST"
```

Expected: compile error — `cannot find 'WorkedBeforeTable' in scope`.

- [ ] **Step 7: Write the table**

Create `Sources/UI/WorkedBeforeTable.swift`:

```swift
import SwiftUI

/// Every prior contact with the station whose call is in the entry field,
/// between the F-key row and the log.
///
/// It exists only while there is history to show, and its height comes out of
/// the log table rather than out of the window — see `height` and
/// `logTableMin`. Rows are deliberately not interactive: there is nothing
/// useful to click, and a live row directly above the log table is a mis-click
/// waiting to happen mid-run.
struct WorkedBeforeTable: View {
    let call: String
    let contacts: [DupeChecker.WorkedContact]
    /// "KSQP 2025 — JO" when the archive knows the station and this log does
    /// not. Nil otherwise, including while the index is still loading.
    let archiveLine: String?
    let currentBand: Band
    let currentModeClass: ModeClass

    // MARK: Height arithmetic

    /// Row and header heights are layout constants so the table's footprint is
    /// arithmetic rather than a measurement. `MainView` subtracts exactly this
    /// from the log table's minimum height, which is what stops macOS growing
    /// the window the first time a match appears.
    static let rowHeight: CGFloat = 15
    static let headerHeight: CGFloat = 14
    /// Padding, the divider, and the gap above the card.
    static let chrome: CGFloat = 16
    /// Past this the table scrolls. A station can only be worked bands × modes
    /// times, and six covers any realistic weekend.
    static let visibleRowCap = 6
    /// The log table's minimum with no history table above it.
    static let logTableMinAlone: CGFloat = 240

    static func height(contacts: Int, hasArchiveLine: Bool) -> CGFloat {
        guard contacts > 0 || hasArchiveLine else { return 0 }
        let rows = min(contacts, visibleRowCap) + (hasArchiveLine ? 1 : 0)
        return headerHeight + rowHeight * CGFloat(rows) + chrome
    }

    static func logTableMin(tableHeight: CGFloat) -> CGFloat {
        logTableMinAlone - tableHeight
    }

    private var scrollHeight: CGFloat {
        Self.height(contacts: contacts.count, hasArchiveLine: archiveLine != nil)
            - Self.headerHeight - Self.chrome
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(contacts) { row($0) }
                    if let archiveLine {
                        archiveRow(archiveLine)
                    }
                }
            }
            .scrollDisabled(contacts.count <= Self.visibleRowCap)
            .frame(height: scrollHeight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .frame(
            height: Self.height(
                contacts: contacts.count, hasArchiveLine: archiveLine != nil
            ),
            alignment: .top
        )
    }

    /// The last column names the station, so the table needs no title line —
    /// which would cost a row to say nothing.
    private var header: some View {
        columns(
            Text("Band"), Text("Mode"), Text("Time"),
            Text("Worked \(call) as")
        )
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(height: Self.headerHeight)
    }

    /// Bold and orange for the band and mode the radio is on right now: there
    /// is nothing left to work here. Weight as well as colour, so the cue does
    /// not rest on colour alone.
    private func row(_ contact: DupeChecker.WorkedContact) -> some View {
        let here = contact.band == currentBand && contact.modeClass == currentModeClass
        return columns(
            Text(contact.band.rawValue),
            Text(contact.modeClass.displayName),
            Text(Self.utc.string(from: contact.timestampUTC)),
            Text(contact.theirLoc)
        )
        .font(.system(size: 10, design: .monospaced).weight(here ? .semibold : .regular))
        .foregroundStyle(here ? Color.orange : Color.secondary)
        .frame(height: Self.rowHeight)
    }

    private func archiveRow(_ line: String) -> some View {
        Text(line)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(height: Self.rowHeight, alignment: .leading)
    }

    private func columns(
        _ a: Text, _ b: Text, _ c: Text, _ d: Text
    ) -> some View {
        HStack(spacing: 6) {
            a.frame(width: 42, alignment: .leading)
            b.frame(width: 40, alignment: .leading)
            c.frame(width: 52, alignment: .leading)
            d.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let utc: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}
```

- [ ] **Step 8: Run them and watch them pass**

```bash
xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/WorkedBeforeTableTests 2>&1 | grep -E "error:|TEST"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 9: Place it in the window**

In `Sources/UI/MainView.swift`, add these computed properties next to
`workedCallsOnCurrentBandMode`:

```swift
    /// Every prior contact with the call in the entry field — the history
    /// table's contents, and the reason it is on screen at all.
    private var workedBefore: [DupeChecker.WorkedContact] {
        DupeChecker.workedContacts(call: entry.callNormalized, log: document.log.qsos)
    }

    private var workedBeforeHeight: CGFloat {
        WorkedBeforeTable.height(contacts: workedBefore.count, hasArchiveLine: false)
    }
```

In `leftPane`, immediately after the `MessagesRow(...)` call and its closing
parenthesis, and before the `Divider()` that precedes `logTable`:

```swift
            if workedBeforeHeight > 0 {
                WorkedBeforeTable(
                    call: entry.callNormalized,
                    contacts: workedBefore,
                    // The archive index supplies this once it has loaded.
                    archiveLine: nil,
                    currentBand: currentBand,
                    currentModeClass: currentModeClass
                )
            }
            Divider()

            logTable
```

Change `logTable` to compensate — replace its `.frame(minHeight: 240)` with:

```swift
        .frame(minHeight: WorkedBeforeTable.logTableMin(tableHeight: workedBeforeHeight))
```

- [ ] **Step 10: Build and run the full suite**

```bash
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | tail -3
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`

- [ ] **Step 11: Document it**

In `README.md`, add a feature bullet immediately after the dupe/mult bullet in
the operating section:

```
- **Worked before**: type or tune to a call already in the log and a table
  appears between the F-keys and the log listing every prior contact with him —
  band, mode, time, and what he sent. The entry for the band and mode you are on
  right now is bold and orange: nothing left to work here. It occupies no space
  at all for a station you have not worked, and the room comes out of the log
  table rather than out of the window, so nothing resizes.
```

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: worked-before table between the F-keys and the log

Answers the question a callsign actually raises in search and pounce —
which bands and modes is he already in my log on — instead of a warning
that only appears once an exchange has been typed.

A county-line contact is one entry, not two: it was one contact. The
table's height is arithmetic on the row count and comes straight out of
the log table's minimum, so the window never resizes when a match
appears. That invariant is asserted rather than eyeballed.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Exchange prefill from log and archive

**Files:**
- Create: `Sources/Core/Engine/StationMemory.swift`
- Test: `Tests/Core/StationMemoryTests.swift`
- Modify: `Sources/App/EntryState.swift`, `Sources/App/EntryFlow.swift`,
  `Sources/UI/EntryBar.swift`, `Sources/UI/MainView.swift`, `README.md`

- [ ] **Step 1: Write the failing tests**

Create `Tests/Core/StationMemoryTests.swift`:

```swift
import XCTest
@testable import QSOPartyLogger

/// What the app already knows a station sends, and where it learned it.
///
/// The rule that matters: a county means nothing outside the party that
/// defines it. A Kansas county abbreviation must never be offered in an Alabama
/// log, however recently it was copied.
final class StationMemoryTests: XCTestCase {

    var ksqp: PartyDefinition!

    override func setUpWithError() throws {
        ksqp = try XCTUnwrap(PartyCatalog.party(id: "ksqp"), "bundled KSQP should load")
    }

    func qso(
        call: String, their: String, band: Band = .m20, t: TimeInterval = 0
    ) -> QSO {
        QSO(
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000 + t),
            call: call, band: band, modeClass: .cw, rawMode: "CW",
            rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: their
        )
    }

    /// The snapshot is irrelevant here, but `ContestRecord` requires one.
    let emptySnapshot = ScoreSnapshot(
        validQSOs: 0, dupeCount: 0, invalidModeCount: 0, outOfScopeCount: 0,
        qsosByMode: [:], qsosByBand: [:], countiesWorked: 0,
        operatingMinutes: 0, figures: nil
    )

    func entry(
        call: String, loc: String, party: String, year: Int,
        county: Bool, t: TimeInterval = 0
    ) -> StationMemory.ArchiveEntry {
        StationMemory.ArchiveEntry(
            call: call, theirLoc: loc, partyID: party, year: year,
            timestampUTC: Date(timeIntervalSince1970: 1_787_500_000 + t),
            isCountyOfItsParty: county
        )
    }

    // MARK: Candidate order

    func testNothingKnownYieldsNoCandidate() {
        XCTAssertNil(
            StationMemory.candidate(
                call: "K5NA", log: [], index: .empty,
                party: ksqp, role: .outOfState
            )
        )
    }

    func testThisLogWins() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "MI", party: "ksqp", year: 2025, county: true)]
        ])
        let candidate = StationMemory.candidate(
            call: "K5NA", log: [qso(call: "K5NA", their: "JO")],
            index: index, party: ksqp, role: .outOfState
        )
        XCTAssertEqual(candidate?.text, "JO")
        XCTAssertEqual(candidate?.source, .thisLog)
    }

    func testMostRecentContactInThisLogWins() {
        let log = [
            qso(call: "K5NA", their: "JO", t: 0),
            qso(call: "K5NA", their: "MI", t: 3600),
        ]
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: log, index: .empty,
                party: ksqp, role: .outOfState
            )?.text,
            "MI"
        )
    }

    /// Same sponsor, so a county from a previous year still means something.
    func testSamePartyCountyIsOffered() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "JO", party: "ksqp", year: 2025, county: true)]
        ])
        let candidate = StationMemory.candidate(
            call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
        )
        XCTAssertEqual(candidate?.text, "JO")
        XCTAssertEqual(candidate?.source, .archive(partyID: "ksqp", year: 2025))
    }

    /// The rule the whole archive fallback rests on.
    func testCountyFromAnotherPartyIsNeverOffered() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "JEFF", party: "alqp", year: 2025, county: true)]
        ])
        XCTAssertNil(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
            )
        )
    }

    /// A state is stable across sponsors — he is in Texas whoever is running
    /// the contest.
    func testStateFromAnotherPartyIsOffered() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [entry(call: "K5NA", loc: "TX", party: "alqp", year: 2025, county: false)]
        ])
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
            )?.text,
            "TX"
        )
    }

    /// The guard behind everything else: whatever the source, the current
    /// party's own parser has the last word.
    func testCandidateThatDoesNotParseIsSkipped() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [
                entry(call: "K5NA", loc: "ZZZZ", party: "alqp", year: 2026, county: false, t: 100),
                entry(call: "K5NA", loc: "TX", party: "alqp", year: 2025, county: false, t: 0),
            ]
        ])
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
            )?.text,
            "TX",
            "the unparseable newer entry is skipped, not fatal"
        )
    }

    func testNewerArchiveYearWins() {
        let index = StationMemory.Index(byCall: [
            "K5NA": [
                entry(call: "K5NA", loc: "MI", party: "ksqp", year: 2026, county: true, t: 100),
                entry(call: "K5NA", loc: "JO", party: "ksqp", year: 2025, county: true, t: 0),
            ]
        ])
        XCTAssertEqual(
            StationMemory.candidate(
                call: "K5NA", log: [], index: index, party: ksqp, role: .outOfState
            )?.text,
            "MI"
        )
    }

    // MARK: Index

    func testIndexKeysByUppercasedCallNewestFirst() {
        let record = ContestRecord(
            partyID: "ksqp", year: 2025, callsign: "KE5CW",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .outOfState(location: "TX"),
            qsos: [
                qso(call: "k5na", their: "JO", t: 0),
                qso(call: "K5NA", their: "MI", t: 3600),
            ],
            snapshot: emptySnapshot, updatedAt: Date(), sourceFileName: nil
        )
        let index = StationMemory.Index.build(
            ContestArchive(records: [record]),
            countiesByParty: ["ksqp": ["JO", "MI"]]
        )
        let entries = index.entries(for: "K5NA")
        XCTAssertEqual(entries.map(\.theirLoc), ["MI", "JO"])
        XCTAssertTrue(entries.allSatisfy(\.isCountyOfItsParty))
    }

    func testIndexMarksNonCountyLocations() {
        let record = ContestRecord(
            partyID: "ksqp", year: 2025, callsign: "KE5CW",
            station: StationProfile(callsign: "KE5CW"),
            myLocation: .inState(counties: ["JO"]),
            qsos: [qso(call: "W1ABC", their: "MA")],
            snapshot: emptySnapshot, updatedAt: Date(), sourceFileName: nil
        )
        let index = StationMemory.Index.build(
            ContestArchive(records: [record]),
            countiesByParty: ["ksqp": ["JO", "MI"]]
        )
        XCTAssertEqual(index.entries(for: "W1ABC").first?.isCountyOfItsParty, false)
    }
}
```

- [ ] **Step 2: Run them and watch them fail**

```bash
xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/StationMemoryTests 2>&1 | grep -E "error:|TEST"
```

Expected: compile error — `cannot find 'StationMemory' in scope`.

- [ ] **Step 3: Implement station memory**

Create `Sources/Core/Engine/StationMemory.swift`:

```swift
import Foundation

/// What the app already knows a station sends, and where it learned it.
///
/// The rule the archive fallback rests on: a county abbreviation means nothing
/// outside the party that defines it. `KS` counties are Kansas QSO Party
/// vocabulary — offering one in an Alabama log would be a wrong exchange with a
/// confident face on it. A state, province or DX is stable across sponsors, so
/// it carries over.
enum StationMemory {

    /// Where a candidate came from, for the operator to judge it by.
    enum Source: Equatable, Sendable {
        case thisLog
        case archive(partyID: String, year: Int)
    }

    struct Candidate: Equatable, Sendable {
        let text: String
        let source: Source
    }

    /// One archived contact, flattened for lookup by call.
    struct ArchiveEntry: Equatable, Sendable {
        let call: String
        let theirLoc: String
        let partyID: String
        let year: Int
        let timestampUTC: Date
        /// Whether `theirLoc` was a county of the party that recorded it.
        let isCountyOfItsParty: Bool
    }

    /// Calls → their archived contacts, newest first. Built once, off the main
    /// actor; a value, so handing it across an actor boundary copies nothing
    /// that can change underneath.
    struct Index: Equatable, Sendable {
        var byCall: [String: [ArchiveEntry]] = [:]

        static let empty = Index()

        init(byCall: [String: [ArchiveEntry]] = [:]) {
            self.byCall = byCall
        }

        func entries(for call: String) -> [ArchiveEntry] {
            byCall[call.trimmingCharacters(in: .whitespaces).uppercased()] ?? []
        }

        /// `countiesByParty` maps a party id to its county abbreviations. Passed
        /// in rather than looked up so this stays a pure function — and so the
        /// bundle is read once per party instead of once per QSO.
        static func build(
            _ archive: ContestArchive,
            countiesByParty: [String: Set<String>]
        ) -> Index {
            var byCall: [String: [ArchiveEntry]] = [:]
            for record in archive.records {
                let counties = countiesByParty[record.partyID] ?? []
                for qso in record.qsos {
                    let call = qso.call.uppercased()
                    byCall[call, default: []].append(
                        ArchiveEntry(
                            call: call,
                            theirLoc: qso.theirLoc,
                            partyID: record.partyID,
                            year: record.year,
                            timestampUTC: qso.timestampUTC,
                            isCountyOfItsParty: counties.contains(qso.theirLoc.uppercased())
                        )
                    )
                }
            }
            for (call, entries) in byCall {
                byCall[call] = entries.sorted { $0.timestampUTC > $1.timestampUTC }
            }
            return Index(byCall: byCall)
        }
    }

    /// The best exchange to offer for `call`, or nil when nothing is known that
    /// the current party can accept.
    ///
    /// Order: this log, then the archive under the same sponsor, then the
    /// archive under any sponsor where the value was not a county. Every
    /// candidate must survive the current party's own parser — belt and braces
    /// against a county abbreviation that collides across two counties lists.
    static func candidate(
        call: String,
        log: [QSO],
        index: Index,
        party: PartyDefinition,
        role: ExchangeParser.Role
    ) -> Candidate? {
        let wanted = call.trimmingCharacters(in: .whitespaces).uppercased()
        guard !wanted.isEmpty else { return nil }

        if let recent = DupeChecker.workedContacts(call: wanted, log: log).first,
           parses(recent.theirLoc, party: party, role: role) {
            return Candidate(text: recent.theirLoc, source: .thisLog)
        }

        let archived = index.entries(for: wanted)
        let sameParty = archived.filter { $0.partyID == party.id }
        for entry in sameParty where parses(entry.theirLoc, party: party, role: role) {
            return Candidate(
                text: entry.theirLoc,
                source: .archive(partyID: entry.partyID, year: entry.year)
            )
        }
        for entry in archived
        where entry.partyID != party.id
            && !entry.isCountyOfItsParty
            && parses(entry.theirLoc, party: party, role: role) {
            return Candidate(
                text: entry.theirLoc,
                source: .archive(partyID: entry.partyID, year: entry.year)
            )
        }
        return nil
    }

    private static func parses(
        _ text: String, party: PartyDefinition, role: ExchangeParser.Role
    ) -> Bool {
        if case .success = ExchangeParser.parse(text, party: party, role: role) {
            return true
        }
        return false
    }
}
```

- [ ] **Step 4: Run them and watch them pass**

```bash
xcodegen generate && xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/StationMemoryTests 2>&1 | grep -E "error:|TEST"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 5: Write the failing tests for the auto-fill rules**

Append to `Tests/App/EntryFlowTests.swift`, inside the class:

```swift
    // MARK: Exchange prefill

    /// A KSQP log, out-of-state TX, with one contact already worked.
    func ksqpDocumentWorking(_ call: String, as loc: String) -> LogDocument {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        doc.append(
            qsos: [
                QSO(
                    call: call, band: .m40, modeClass: .cw, rawMode: "CW",
                    rstSent: "599", rstRcvd: "599", myLoc: "TX", theirLoc: loc
                )
            ],
            undoManager: nil
        )
        return doc
    }

    func testTypingAKnownCallFillsTheExchange() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JO"))
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "JO")
        XCTAssertTrue(flow.entry.exchangeIsAutoFilled)
    }

    func testAutoFillNeverOverwritesTypedText() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JO"))
        flow.entry.exchangeTyped = "MI"
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "MI", "what the operator typed stands")
        XCTAssertFalse(flow.entry.exchangeIsAutoFilled)
    }

    /// Auto-filled text is the app's, so the app takes it back the moment the
    /// call it belonged to is no longer in the field.
    func testAutoFillWithdrawsWhenTheCallStopsMatching() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JO"))
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "JO")

        flow.entry.call = "K5NAX"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "", "the fill belonged to K5NA")
    }

    func testUnknownCallFillsNothing() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JO"))
        flow.entry.call = "W1ABC"
        flow.callChanged(context())
        XCTAssertEqual(flow.entry.exchange, "")
    }
```

- [ ] **Step 6: Run them and watch them fail**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | grep -E "error:|TEST"
```

Expected: compile error — `value of type 'EntryFlow' has no member 'callChanged'`.

- [ ] **Step 7: Teach `EntryState` the difference between filled and typed**

In `Sources/App/EntryState.swift`, add after the `exchange` property:

```swift
    /// Whether `exchange` holds text the app put there rather than text the
    /// operator typed. Auto-fill only ever writes into a field it already owns,
    /// so it can never destroy a copied exchange — and it takes its own text
    /// back when the call it belonged to leaves the field.
    private(set) var exchangeIsAutoFilled = false

    /// The exchange as the operator edits it. Writing through here is what
    /// marks the text as theirs; the view binds to this, never to `exchange`.
    var exchangeTyped: String {
        get { exchange }
        set {
            exchange = newValue
            exchangeIsAutoFilled = false
        }
    }

    func autoFillExchange(_ text: String) {
        exchange = text
        exchangeIsAutoFilled = true
    }

    /// Take back text the app put there. Text the operator typed is untouched.
    func clearAutoFilledExchange() {
        guard exchangeIsAutoFilled else { return }
        exchange = ""
        exchangeIsAutoFilled = false
    }
```

In `clearForNextContact`, after `exchange = ""`, add:

```swift
        exchangeIsAutoFilled = false
```

- [ ] **Step 8: Give `EntryFlow` the archive index and the call hook**

In `Sources/App/EntryFlow.swift`, add a stored property below `document`:

```swift
    /// Previous contests, indexed by call. Empty until the load finishes, which
    /// costs nothing but a missed prefill in the first second of a contest.
    var archiveIndex = StationMemory.Index.empty
```

Add to the `// MARK: Entry housekeeping` section:

```swift
    /// The call field changed by typing. Refresh what the app is offering for
    /// this station, then revalidate. Safe on every keystroke: the only text it
    /// can overwrite is text it wrote itself.
    func callChanged(_ context: Context) {
        refreshPrefill(context)
        revalidate(context)
    }

    /// Offer what we know about the call now in the field, or take back what we
    /// offered for the last one.
    private func refreshPrefill(_ context: Context) {
        guard let party,
              entry.exchange.isEmpty || entry.exchangeIsAutoFilled else { return }

        let call = entry.callNormalized
        guard !call.isEmpty else {
            entry.clearAutoFilledExchange()
            return
        }

        let role: ExchangeParser.Role =
            document.log.myLocation.isInState ? .inState : .outOfState
        guard let candidate = StationMemory.candidate(
            call: call,
            log: document.log.qsos,
            index: archiveIndex,
            party: party,
            role: role
        ) else {
            entry.clearAutoFilledExchange()
            return
        }
        entry.autoFillExchange(candidate.text)
    }
```

- [ ] **Step 9: Run them and watch them pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | grep -E "error:|TEST"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 10: Wire the view**

In `Sources/UI/EntryBar.swift`, bind the exchange field through the typed
accessor so a keystroke marks the text as the operator's — replace

```swift
                field(exchangeLabel, text: $entry.exchange.uppercasing, width: 170, focusTag: .exchange)
```

with

```swift
                field(
                    exchangeLabel,
                    text: $entry.exchangeTyped.uppercasing,
                    width: 170,
                    focusTag: .exchange,
                    provisional: entry.exchangeIsAutoFilled
                )
```

Add the parameter to `field`, defaulting off so the other five calls are
unchanged, and grey the text while it is the app's:

```swift
    private func field(
        _ label: String,
        text: Binding<String>,
        width: CGFloat,
        focusTag: Field,
        provisional: Bool = false
    ) -> some View {
```

and inside it, on the `TextField`, after `.font(...)`:

```swift
                .foregroundStyle(provisional ? .secondary : .primary)
```

In `Sources/UI/MainView.swift`, replace

```swift
                .onChange(of: entry.call) { revalidate() }
```

with

```swift
                .onChange(of: entry.call) { flow.callChanged(operatingContext) }
```

- [ ] **Step 11: Load the archive index at window open**

In `Sources/UI/MainView.swift`, add to `onAppear` after the `spotStore.maxAgeMinutes`
line:

```swift
        loadArchiveIndex()
```

and add the method next to `connectCluster`:

```swift
    /// Previous contests, read once and indexed by call — what a prefill falls
    /// back on when this log has never worked the station. Off the main actor
    /// because the archive holds every QSO of every contest ever logged, and a
    /// failure is silent: this is a convenience, not a correctness path.
    private func loadArchiveIndex() {
        Task {
            let index = await Task.detached(priority: .userInitiated) {
                () -> StationMemory.Index in
                let folder = ContestHistorian.resolveFolder()
                guard let archive = try? ArchiveStore(folder: folder).load() else {
                    return .empty
                }
                var counties: [String: Set<String>] = [:]
                for id in Set(archive.records.map(\.partyID)) {
                    counties[id] = Set(
                        PartyCatalog.party(id: id)?.counties.map(\.abbr) ?? []
                    )
                }
                return StationMemory.Index.build(archive, countiesByParty: counties)
            }.value
            flow.archiveIndex = index
        }
    }
```

- [ ] **Step 12: Show the archive line in the table**

In `Sources/UI/MainView.swift`, add next to `workedBefore`:

```swift
    /// "KSQP 2025 — JO" when previous contests know the station and this one
    /// does not. It is where a pre-filled exchange came from, which is why it
    /// belongs on screen rather than only in the field.
    private var workedBeforeArchiveLine: String? {
        guard workedBefore.isEmpty, !entry.callNormalized.isEmpty else { return nil }
        guard let entryFound = flow.archiveIndex.entries(for: entry.callNormalized).first
        else { return nil }
        return "\(entryFound.partyID.uppercased()) \(entryFound.year) — \(entryFound.theirLoc)"
    }
```

Change `workedBeforeHeight` to account for it:

```swift
    private var workedBeforeHeight: CGFloat {
        WorkedBeforeTable.height(
            contacts: workedBefore.count,
            hasArchiveLine: workedBeforeArchiveLine != nil
        )
    }
```

and in the `WorkedBeforeTable(...)` call, replace `archiveLine: nil,` with:

```swift
                    archiveLine: workedBeforeArchiveLine,
```

- [ ] **Step 13: Build, full suite**

```bash
xcodegen generate && xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | tail -3
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`

- [ ] **Step 14: Document it**

In `README.md`, add after the worked-before bullet:

```
- **Exchange pre-fill**: work a station on a new band and his county or state is
  already in the field, taken from your most recent contact with him — or, when
  this contest has never worked him, from previous contests in the history
  archive. A county only carries over within the same sponsor's party, because
  a Kansas county means nothing in Alabama, and every candidate has to survive
  the current party's own exchange parser before it is offered. Pre-filled text
  is greyed until you type over it, and it withdraws itself if the call changes.
```

- [ ] **Step 15: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: pre-fill the exchange from this log, then previous contests

Working a station on a new band should not mean copying his county a
second time. The candidate comes from the most recent contact in this
log, then the archive under the same sponsor, then the archive under any
sponsor — but only where the value was not a county, because a county
abbreviation means nothing outside the party that defines it.

Whatever the source, the current party's own parser has the last word,
which also covers abbreviations that collide across two counties lists.
Filled text is the app's until the operator types: it only ever writes
into a field it already owns, and it takes its own text back when the
call leaves the field.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Pending exchange stashed per station

**Files:**
- Modify: `Sources/App/EntryState.swift`, `Sources/App/EntryFlow.swift`,
  `Sources/UI/MainView.swift`
- Test: `Tests/App/EntryFlowTests.swift`
- Modify: `README.md`

- [ ] **Step 1: Write the failing tests**

Append to `Tests/App/EntryFlowTests.swift`, inside the class:

```swift
    // MARK: Pending exchanges across spot moves

    /// A KSQP log with nothing worked — the state of hunting a fresh band.
    func ksqpDocument() -> LogDocument {
        let doc = LogDocument()
        doc.updateStation(
            StationProfile(callsign: "KE5CW"),
            location: .outOfState(location: "TX"),
            partyID: "ksqp",
            undoManager: nil
        )
        return doc
    }

    /// The niggle itself: a county copied for a station who never came back
    /// must not follow you to the next spot and get logged against him.
    func testMovingToAnotherStationClearsWhatWasCopied() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JO"
        flow.entry.serialRcvd = "42"

        flow.stationChanged(to: "W0BH", context())

        XCTAssertEqual(flow.entry.call, "W0BH")
        XCTAssertEqual(flow.entry.exchange, "")
        XCTAssertEqual(flow.entry.serialRcvd, "")
    }

    func testComingBackRestoresWhatWasCopied() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JO"
        flow.entry.serialRcvd = "42"

        flow.stationChanged(to: "W0BH", context())
        flow.stationChanged(to: "K5NA", context())

        XCTAssertEqual(flow.entry.exchange, "JO")
        XCTAssertEqual(flow.entry.serialRcvd, "42")
        XCTAssertFalse(
            flow.entry.exchangeIsAutoFilled,
            "restored text is the operator's, not the app's"
        )
    }

    /// The restore hangs off the call, not off the navigation.
    func testTypingTheCallBackRestoresWhatWasCopied() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JO"
        flow.stationChanged(to: "W0BH", context())

        flow.entry.call = "K5NA"
        flow.callChanged(context())

        XCTAssertEqual(flow.entry.exchange, "JO")
    }

    /// Auto-filled text regenerates from the log, so stashing it would only
    /// make a typed-looking copy of something the app already knows.
    func testAutoFilledTextIsNeverStashed() {
        let flow = EntryFlow(document: ksqpDocumentWorking("K5NA", as: "JO"))
        flow.entry.call = "K5NA"
        flow.callChanged(context())
        XCTAssertTrue(flow.entry.exchangeIsAutoFilled)

        flow.stationChanged(to: "W0BH", context())
        XCTAssertNil(flow.entry.pendingExchanges["K5NA"])
    }

    func testLoggingAContactDropsItsPendingExchange() {
        let doc = ksqpDocument()
        let flow = EntryFlow(document: doc)
        flow.entry.call = "K5NA"
        flow.entry.exchangeTyped = "JO"
        flow.stationChanged(to: "W0BH", context())
        XCTAssertNotNil(flow.entry.pendingExchanges["K5NA"])

        flow.stationChanged(to: "K5NA", context())
        _ = flow.logContact(context(), undoManager: nil)

        XCTAssertEqual(doc.log.qsos.count, 1)
        XCTAssertNil(
            flow.entry.pendingExchanges["K5NA"],
            "he is in the log now — there is nothing pending about him"
        )
    }

    func testAnEmptyExchangeIsNotStashed() {
        let flow = EntryFlow(document: ksqpDocument())
        flow.entry.call = "K5NA"
        flow.stationChanged(to: "W0BH", context())
        XCTAssertTrue(flow.entry.pendingExchanges.isEmpty)
    }
```

- [ ] **Step 2: Run them and watch them fail**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | grep -E "error:|TEST"
```

Expected: compile error — `value of type 'EntryFlow' has no member 'stationChanged'`.

- [ ] **Step 3: Add the stash to `EntryState`**

In `Sources/App/EntryState.swift`, add below `exchangeTyped`:

```swift
    /// What the operator copied for a station and never logged. Hunting a
    /// station who can be heard but cannot hear you means copying his exchange
    /// with nothing to show for it; moving to the next spot must not carry that
    /// to the next station, and coming back must not mean copying it twice.
    struct Pending: Equatable {
        var exchange: String
        var serialRcvd: String

        var isEmpty: Bool {
            exchange.trimmingCharacters(in: .whitespaces).isEmpty
                && serialRcvd.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var pendingExchanges: [String: Pending] = [:]

    /// Put back what was copied for this station, as the operator's own text.
    func restorePending(_ pending: Pending) {
        exchange = pending.exchange
        serialRcvd = pending.serialRcvd
        exchangeIsAutoFilled = false
    }
```

- [ ] **Step 4: Add `stationChanged` to `EntryFlow`**

In `Sources/App/EntryFlow.swift`, add next to `callChanged`:

```swift
    /// A different station, chosen whole — a spot click or ⌘← / ⌘→ / ⌘↑ / ⌘↓.
    ///
    /// Distinct from `callChanged` on purpose. Typing is incremental and must
    /// never cost the operator text they typed; arriving at a new station is a
    /// deliberate move away, so what was copied for the last one comes off the
    /// row — kept under his call, not thrown away.
    func stationChanged(to call: String, _ context: Context) {
        stashPending()
        entry.exchangeTyped = ""
        entry.serialRcvd = ""
        entry.call = call
        refreshPrefill(context)
        revalidate(context)
    }

    private func stashPending() {
        let outgoing = entry.callNormalized
        guard !outgoing.isEmpty, !entry.exchangeIsAutoFilled else { return }
        let pending = EntryState.Pending(
            exchange: entry.exchange,
            serialRcvd: entry.serialRcvd
        )
        guard !pending.isEmpty else { return }
        entry.pendingExchanges[outgoing] = pending
    }
```

In `refreshPrefill`, before the `StationMemory.candidate` lookup and after the
empty-call guard, restore a stash first — what the operator copied outranks
anything the app can derive:

```swift
        if let pending = entry.pendingExchanges[call] {
            entry.restorePending(pending)
            return
        }
```

In `logContact`, immediately before `entry.clearForNextContact(...)`:

```swift
        // He is in the log now; there is nothing pending about him.
        entry.pendingExchanges.removeValue(forKey: entry.callNormalized)
```

- [ ] **Step 5: Run them and watch them pass**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' -only-testing:QSOPartyLoggerTests/EntryFlowTests 2>&1 | grep -E "error:|TEST"
```

Expected: `** TEST SUCCEEDED **`

- [ ] **Step 6: Route spot tuning through it**

In `Sources/UI/MainView.swift`, in `tune(to:)`, replace

```swift
        entry.call = spot.call
        focusedField = .call
        revalidate()
```

with

```swift
        flow.stationChanged(to: spot.call, operatingContext)
        focusedField = .call
```

- [ ] **Step 7: Build, full suite**

```bash
xcodebuild -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger build 2>&1 | tail -3
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **` and `** TEST SUCCEEDED **`

- [ ] **Step 8: Document it, and update the test count**

In `README.md`, add after the exchange pre-fill bullet:

```
- **Copied, not lost**: a station you can hear but who cannot hear you takes an
  exchange to copy and gives no contact for it. Moving to the next spot clears
  the field so nothing is logged against the wrong station, and keeps what you
  copied under his call — land back on him, by spot or by typing his call, and
  it is there again.
```

Count the tests and update the sentence at `README.md:483` that currently reads
`811 unit tests cover…`:

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | grep -c "Test case .* passed"
```

Use that number.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "$(cat <<'EOF'
feat: an exchange copied for a station stays with that station

Hunting someone who can be heard but cannot hear you means copying his
exchange with no contact to show for it. Moving to the next spot used to
leave that county in the field, one Return away from being logged
against a different station.

It now comes off the row and is kept under his call: land back on him,
by spot or by typing, and it is there again. Typing is untouched — only
a deliberate move to another station stashes, so fixing a typo in a call
never costs the exchange underneath it.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
EOF
)"
```

---

## Done

- [ ] **Step 1: Confirm the whole suite is green and report the number**

```bash
xcodebuild test -project QSOPartyLogger.xcodeproj -scheme QSOPartyLogger -destination 'platform=macOS' 2>&1 | tail -5
```

- [ ] **Step 2: Offer the merge**

Report each commit, the test count before and after, and what was verified by
test versus what needs the operator's eyes — the two AppKit behaviors (the panel
staying put, the table appearing without the window resizing) can only be
confirmed by running the app.
